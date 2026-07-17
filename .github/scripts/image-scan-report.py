#!/usr/bin/env python3
"""Agrège les rapports JSON de Trivy en un résumé Markdown.

Lit tous les fichiers *.json d'un répertoire (un par image, produits par le
workflow scan-images.yml) et produit un tableau récapitulatif, suivi de la liste
des images réellement actionnables.

Le rapport classe les CVE en trois catégories, parce qu'elles n'appellent pas la
même action :

  1. CVE de paquet OS AVEC correctif publié -> actionnable, et seule catégorie
     bloquante. Se corrige en montant le tag, ou par un `apk/apt upgrade` si
     l'image est déjà au tag le plus récent (cf. docker/hardened/).
  2. CVE de paquet OS SANS correctif publié -> rien à faire tant que la distro
     n'a pas publié. Redeviendra automatiquement bloquante ce jour-là.
  3. CVE de binaire embarqué (gobinary, jar, node-pkg…) -> ne part que si l'amont
     recompile. Hors de portée de ce dépôt.

Le verdict (--fail-on) ne porte que sur la catégorie 1, pour rendre le même
verdict que la barrière par image du workflow (vuln-type: os + ignore-unfixed).

Usage :
    python3 .github/scripts/image-scan-report.py <dossier-des-rapports>
    python3 .github/scripts/image-scan-report.py reports --fail-on CRITICAL,HIGH
"""

import argparse
import datetime
import json
import sys
from pathlib import Path

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM", "LOW")

# Trivy classe chaque Result : "os-pkgs" pour les paquets de la distribution,
# "lang-pkgs" pour les binaires et bibliothèques embarqués.
OS_CLASS = "os-pkgs"


def load_exceptions(ignore_file: Path) -> set:
    """Les CVE exceptées et non expirées de .trivyignore.yaml.

    Le rapport DOIT appliquer les mêmes exceptions que la barrière : sans ça, les
    deux divergent (rapport rouge / images vertes), ce qui est précisément le
    défaut que la séparation OS/binaire corrige par ailleurs.

    Le rapprochement se fait sur l'ID seul, là où Trivy croise aussi le purl. Un
    même ID de CVE sur un autre paquet serait donc excepté ici et pas par la
    barrière — cas de figure sans occurrence réelle, l'écart resterait de toute
    façon du côté prudent (le job échoue, le rapport non).
    """
    if not ignore_file.is_file():
        return set()

    try:
        import yaml
    except ImportError:
        print(f"⚠️ pyyaml absent : exceptions de {ignore_file.name} non appliquées.",
              file=sys.stderr)
        return set()

    try:
        data = yaml.safe_load(ignore_file.read_text(encoding="utf-8")) or {}
    except (yaml.YAMLError, OSError) as error:
        print(f"⚠️ {ignore_file.name} illisible : {error}", file=sys.stderr)
        return set()

    today = datetime.date.today()
    active = set()
    for entry in data.get("vulnerabilities") or []:
        expiry = entry.get("expired_at")
        if isinstance(expiry, datetime.datetime):
            expiry = expiry.date()
        # Une exception expirée redevient bloquante : c'est tout l'intérêt du champ.
        if isinstance(expiry, datetime.date) and expiry <= today:
            continue
        if entry.get("id"):
            active.add(entry["id"])
    return active


def _empty() -> dict:
    return {severity: 0 for severity in SEVERITIES}


def summarize(report_path: Path, exceptions: set) -> dict:
    """Ventile les vulnérabilités d'un rapport Trivy par gravité et par action possible."""
    data = json.loads(report_path.read_text(encoding="utf-8"))

    # Une CVE de paquet OS "corrigeable" a une version de correctif publiée par la
    # distribution : celle-là, et elle seule, se règle depuis ce dépôt.
    os_fixable = _empty()
    os_unfixable = _empty()
    # Corrigeables mais explicitement exceptées et datées dans .trivyignore.yaml.
    # Comptées à part plutôt que soustraites en silence : une exception se voit.
    excepted = _empty()
    # Les CVE de binaires embarqués ont beau afficher une FixedVersion (ex : Go
    # 1.26.5 pour une CVE stdlib), elle désigne le toolchain amont, pas une image :
    # les distinguer par correctif n'apporterait rien, on ne les sépare donc pas.
    binary = _empty()

    for result in data.get("Results") or []:
        is_os = result.get("Class") == OS_CLASS
        for vuln in result.get("Vulnerabilities") or []:
            severity = vuln.get("Severity")
            if severity not in SEVERITIES:
                continue
            if not is_os:
                binary[severity] += 1
            elif not vuln.get("FixedVersion"):
                os_unfixable[severity] += 1
            elif vuln.get("VulnerabilityID") in exceptions:
                excepted[severity] += 1
            else:
                os_fixable[severity] += 1

    return {
        "image": data.get("ArtifactName", report_path.stem),
        "os_fixable": os_fixable,
        "os_unfixable": os_unfixable,
        "excepted": excepted,
        "binary": binary,
    }


def status_icon(item: dict, fail_on: list) -> str:
    """L'icône suit le verdict : rouge = actionnable, donc bloquant."""
    blocking = [s for s in (fail_on or ["CRITICAL", "HIGH"]) if item["os_fixable"][s]]
    if blocking:
        return "🔴"
    if any(item["excepted"].values()):
        return "⚪"
    if any(item["os_unfixable"].values()) or any(item["binary"].values()):
        return "🟡"
    return "🟢"


def _ch(counts: dict) -> str:
    return f"{counts['CRITICAL']}/{counts['HIGH']}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports_dir", help="dossier contenant les rapports JSON de Trivy")
    parser.add_argument(
        "--fail-on",
        default="",
        help="gravités faisant sortir en code 1, séparées par des virgules (ex: CRITICAL,HIGH)",
    )
    parser.add_argument(
        "--ignorefile",
        default=".trivyignore.yaml",
        help="exceptions datées, à garder identique à celui que lit la barrière",
    )
    args = parser.parse_args()

    fail_on = [s.strip().upper() for s in args.fail_on.split(",") if s.strip()]
    unknown = [s for s in fail_on if s not in SEVERITIES]
    if unknown:
        parser.error(f"gravité(s) inconnue(s) : {', '.join(unknown)}")

    reports_dir = Path(args.reports_dir)
    report_files = sorted(reports_dir.rglob("*.json"))

    if not report_files:
        print("⚠️ Aucun rapport de scan trouvé.")
        return 0

    exceptions = load_exceptions(Path(args.ignorefile))

    summaries = []
    for report_file in report_files:
        try:
            summaries.append(summarize(report_file, exceptions))
        except (json.JSONDecodeError, OSError) as error:
            print(f"⚠️ Rapport illisible ({report_file.name}) : {error}", file=sys.stderr)

    # Les images actionnables en premier, puis les plus bruyantes.
    summaries.sort(
        key=lambda item: (
            -item["os_fixable"]["CRITICAL"],
            -item["os_fixable"]["HIGH"],
            -item["os_unfixable"]["CRITICAL"],
            item["image"],
        )
    )

    def total(bucket: str, severity: str) -> int:
        return sum(item[bucket][severity] for item in summaries)

    actionable = [
        item for item in summaries
        if any(item["os_fixable"][s] for s in (fail_on or ["CRITICAL", "HIGH"]))
    ]
    clean = sum(
        1 for item in summaries
        if not any(item[b][s] for b in ("os_fixable", "os_unfixable", "excepted", "binary")
                   for s in SEVERITIES)
    )

    print("## 🔎 Scan de vulnérabilités des images\n")
    print(f"**{len(summaries)} image(s) scannée(s)** — {clean} sans vulnérabilité connue.\n")

    print("### 🔴 Actionnable — CVE de paquets OS avec correctif publié\n")
    print("C'est la seule catégorie bloquante, et la seule sur laquelle ce dépôt peut agir :")
    print("monter le tag, ou durcir l'image par `apk/apt upgrade` si elle est déjà au tag le")
    print("plus récent (voir `docker/hardened/`).\n")
    print("| CRITICAL | HIGH | MEDIUM | LOW |\n|---:|---:|---:|---:|")
    print(f"| {total('os_fixable','CRITICAL')} | {total('os_fixable','HIGH')} "
          f"| {total('os_fixable','MEDIUM')} | {total('os_fixable','LOW')} |\n")

    print("### 🟡 Informatif — non actionnable depuis ce dépôt\n")
    print("| Catégorie | CRITICAL | HIGH | MEDIUM | LOW | Pourquoi |")
    print("|---|---:|---:|---:|---:|---|")
    print(f"| CVE de paquets OS **sans correctif** | {total('os_unfixable','CRITICAL')} "
          f"| {total('os_unfixable','HIGH')} | {total('os_unfixable','MEDIUM')} "
          f"| {total('os_unfixable','LOW')} | La distribution n'a rien publié. "
          f"Redeviendra bloquante dès qu'un correctif sortira. |")
    if any(total("excepted", s) for s in SEVERITIES):
        print(f"| CVE **exceptées** (`.trivyignore.yaml`) | {total('excepted','CRITICAL')} "
              f"| {total('excepted','HIGH')} | {total('excepted','MEDIUM')} "
              f"| {total('excepted','LOW')} | Corrigeables, mais acceptées "
              f"temporairement avec justification et date d'expiration. |")
    print(f"| CVE de **binaires embarqués** | {total('binary','CRITICAL')} "
          f"| {total('binary','HIGH')} | {total('binary','MEDIUM')} | {total('binary','LOW')} "
          f"| Ne partent que si l'amont recompile. Leur nombre suit l'âge du build "
          f"(~5-6/mois pour un binaire Go), pas un risque nouveau. |\n")

    print("### Détail par image\n")
    print("🔴 à traiter · ⚪ excepté · 🟡 rien à faire · 🟢 sain\n")
    print("| | Image | OS corrigeables (C/H) | Exceptées (C/H) "
          "| OS sans correctif (C/H) | Binaires (C/H) |")
    print("|---|---|---:|---:|---:|---:|")
    for item in summaries:
        print(
            f"| {status_icon(item, fail_on)} | `{item['image']}` "
            f"| {_ch(item['os_fixable'])} | {_ch(item['excepted'])} "
            f"| {_ch(item['os_unfixable'])} | {_ch(item['binary'])} |"
        )

    if actionable:
        print("\n### ⚠️ À traiter\n")
        for item in actionable:
            print(f"- `{item['image']}` — {_ch(item['os_fixable'])} (CRITICAL/HIGH) "
                  f"de paquets OS avec un correctif publié.")
        print("\nSi l'image est déjà au tag le plus récent, monter le tag n'y changera rien :")
        print("c'est un durcissement qu'il faut (`docker/hardened/`, un `apk/apt upgrade`).")

    print("\n> Détail complet des CVE : onglet **Security → Code scanning** du dépôt.")

    if not fail_on:
        return 0

    blocking = {s: total("os_fixable", s) for s in fail_on if total("os_fixable", s)}
    if not blocking:
        print(f"\n✅ Aucune CVE de paquet OS {'/'.join(fail_on)} corrigeable détectée.")
        return 0

    detail = ", ".join(f"{count} {severity}" for severity, count in blocking.items())
    print(f"\n❌ **Scan en échec** : {detail} de paquets OS corrigeable(s) "
          f"sur {len(actionable)} image(s).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
