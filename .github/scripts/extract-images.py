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

# Répertoires scannés (mêmes cibles que les autres jobs de la CI)
SCAN_DIRS = [
    "tp01", "tp02", "tp03", "tp04", "tp05",
    "tp06", "tp07", "tp08", "tp09", "tp10",
    "docs",
]

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
    """Identifiant sûr pour un nom d'artefact ou une catégorie SARIF."""
    return re.sub(r"[^a-zA-Z0-9]+", "-", image).strip("-").lower()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="sortie JSON (liste d'images)")
    parser.add_argument(
        "--matrix",
        action="store_true",
        help="sortie JSON [{image, slug}] pour une matrice GitHub Actions",
    )
    parser.add_argument("--verbose", action="store_true", help="détaille les images écartées")
    args = parser.parse_args()

    root = Path.cwd()
    ignore_patterns = load_ignore_patterns(root)

    scannable: set[str] = set()
    skipped: dict[str, str] = {}

    for scan_dir in SCAN_DIRS:
        directory = root / scan_dir
        if not directory.is_dir():
            continue
        for path in sorted(list(directory.rglob("*.yaml")) + list(directory.rglob("*.yml"))):
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
        print(json.dumps([{"image": image, "slug": slugify(image)} for image in result]))
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
