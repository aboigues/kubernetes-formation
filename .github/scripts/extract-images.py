#!/usr/bin/env python3
"""Extrait les images de conteneurs des manifests Kubernetes du projet.

Parcourt les YAML des TPs et de docs/, et ne retient que les images
réellement scannables :
  - les images déclarées dans containers / initContainers / ephemeralContainers
    (Kubernetes) et steps / sidecars (Tekton), à n'importe quel niveau
    d'imbrication (Deployment, CronJob, Task, ...)
  - en excluant les images pédagogiques fictives listées dans
    .github/image-scan-ignore.txt (elles n'existent sur aucun registre)

Sortie : une ligne par image sur stdout, ou du JSON avec --json / --matrix.

Usage :
    python3 .github/scripts/extract-images.py
    python3 .github/scripts/extract-images.py --json
    python3 .github/scripts/extract-images.py --matrix   # pour GitHub Actions
"""

import argparse
import fnmatch
import json
import re
import sys
from pathlib import Path

import yaml

# Répertoires scannés : tous les dossiers de TP (ancienne génération « tpNN »
# et nouvelle « tpNN-thème »), découverts à chaque exécution, plus docs/.
# Une liste écrite en dur oubliait les nouveaux TP sans que rien ne le signale.
SCAN_GLOBS = ("tp[0-9][0-9]", "tp[0-9][0-9]-*")
EXTRA_DIRS = ("docs",)


def scan_dirs(root: Path) -> list[Path]:
    dirs = {d for pattern in SCAN_GLOBS for d in root.glob(pattern) if d.is_dir()}
    dirs.update(root / d for d in EXTRA_DIRS if (root / d).is_dir())
    return sorted(dirs)

# Clés dont la valeur est une liste de conteneurs portant un champ "image"
CONTAINER_KEYS = (
    "containers",
    "initContainers",
    "ephemeralContainers",
    "steps",     # Tekton Task
    "sidecars",  # Tekton Task
)

IGNORE_FILE = Path(".github/image-scan-ignore.txt")


def load_ignore_patterns(root: Path) -> list[str]:
    ignore_path = root / IGNORE_FILE
    if not ignore_path.exists():
        return []
    patterns = []
    for line in ignore_path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            patterns.append(line)
    return patterns


def find_images(node) -> list[str]:
    """Descend récursivement dans le YAML et récolte les images de conteneurs."""
    images = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key in CONTAINER_KEYS and isinstance(value, list):
                for container in value:
                    if isinstance(container, dict):
                        image = container.get("image")
                        if isinstance(image, str) and image.strip():
                            images.append(image.strip())
            images.extend(find_images(value))
    elif isinstance(node, list):
        for item in node:
            images.extend(find_images(item))
    return images


def is_templated(image: str) -> bool:
    """Image contenant une variable non résolue (Helm, Tekton params, envsubst)."""
    return any(token in image for token in ("{{", "$(", "${"))


def slugify(image: str) -> str:
    """Identifiant sûr pour un nom de fichier ou d'artefact (contient le tag)."""
    return re.sub(r"[^a-zA-Z0-9]+", "-", image).strip("-").lower()


# --- Catégories SARIF ---------------------------------------------------------
# Une alerte de code scanning ne se ferme que si la MÊME catégorie est renvoyée
# sans elle. Avec le tag dans la catégorie, chaque montée de version laissait
# les alertes de l'ancienne version ouvertes à vie (alertes « fantômes »).
# La catégorie est donc le nom de l'image, SANS tag.
#
# Piège : une même image peut être scannée en plusieurs tags dans un même run
# (registry 2/3, loki 3.7.2/3.7.8…) ; une catégorie partagée ferait s'écraser
# leurs uploads. Dans ce cas seulement, on suffixe un RANG (tags triés par
# version) : le bump d'un tag réutilise son rang, donc sa catégorie.
# Cas résiduel : si un des tags disparaît, le dernier rang devient orphelin et
# ses alertes sont à fermer à la main.


def _nom_et_tag(ref: str) -> tuple[str, str]:
    ref = ref.split("@", 1)[0]  # digest éventuel
    nom, _, tag = ref.rpartition(":")
    if not nom or "/" in tag:  # pas de tag (le « : » était celui d'un port de registre)
        return ref, "latest"
    return nom, tag


def _cle_version(tag: str) -> tuple:
    # « 1.10 » après « 1.9 », « 18 » avant « 18-alpine »
    return tuple(
        (0, int(t), "") if t.isdigit() else (1, 0, t) for t in re.findall(r"\d+|\D+", tag)
    )


def categories_sarif(images: list[str]) -> dict[str, str]:
    """Catégorie SARIF STABLE (sans tag) de chaque image, unique dans le lot."""
    groupes: dict[str, list[str]] = {}
    for image in images:
        groupes.setdefault(_nom_et_tag(image)[0], []).append(image)
    categories = {}
    for nom, refs in groupes.items():
        base = "trivy-image-" + re.sub(r"[^A-Za-z0-9._-]", "-", nom)
        if len(refs) == 1:
            categories[refs[0]] = base
            continue
        refs.sort(key=lambda r: (_cle_version(_nom_et_tag(r)[1]), r))
        for rang, ref in enumerate(refs, start=1):
            categories[ref] = f"{base}-rang-{rang}"
    return categories


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="sortie JSON (liste d'images)")
    parser.add_argument(
        "--matrix",
        action="store_true",
        help="sortie JSON [{image, slug, categorie}] pour une matrice GitHub Actions",
    )
    parser.add_argument("--verbose", action="store_true", help="détaille les images écartées")
    args = parser.parse_args()

    root = Path.cwd()
    ignore_patterns = load_ignore_patterns(root)

    scannable: set[str] = set()
    skipped: dict[str, str] = {}

    for directory in scan_dirs(root):
        for path in sorted(list(directory.rglob("*.yaml")) + list(directory.rglob("*.yml"))):
            # starter/ : manifestes à trous (« image: ______ ») ; leurs vraies
            # images sont celles de solution/, déjà scannées.
            if "starter" in path.relative_to(root).parts:
                continue
            try:
                documents = list(yaml.safe_load_all(path.read_text(encoding="utf-8")))
            except yaml.YAMLError:
                # Templates Helm et autres YAML non parsables : ignorés silencieusement,
                # la validation de syntaxe est déjà couverte par le workflow principal.
                continue
            for document in documents:
                for image in find_images(document):
                    if is_templated(image):
                        skipped[image] = "variable non résolue"
                    elif any(fnmatch.fnmatch(image, pattern) for pattern in ignore_patterns):
                        skipped[image] = "image pédagogique fictive (ignore-list)"
                    else:
                        scannable.add(image)

    result = sorted(scannable)

    if args.matrix:
        categories = categories_sarif(result)
        print(json.dumps([
            {"image": image, "slug": slugify(image), "categorie": categories[image]}
            for image in result
        ]))
        return 0

    if args.json:
        print(json.dumps(result))
        return 0

    for image in result:
        print(image)

    if args.verbose and skipped:
        print(f"\n{len(skipped)} image(s) écartée(s) :", file=sys.stderr)
        for image, reason in sorted(skipped.items()):
            print(f"  - {image} : {reason}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
