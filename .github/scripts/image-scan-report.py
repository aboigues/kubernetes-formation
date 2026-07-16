#!/usr/bin/env python3
"""Agrège les rapports JSON de Trivy en un résumé Markdown.

Lit tous les fichiers *.json d'un répertoire (un par image, produits par le
workflow scan-images.yml) et produit un tableau récapitulatif trié par gravité,
suivi de la liste des images à mettre à jour en priorité.

Usage :
    python3 .github/scripts/image-scan-report.py <dossier-des-rapports>
"""

import json
import sys
from pathlib import Path

SEVERITIES = ("CRITICAL", "HIGH", "MEDIUM", "LOW")


def summarize(report_path: Path) -> dict:
    """Compte les vulnérabilités d'un rapport Trivy par gravité."""
    data = json.loads(report_path.read_text(encoding="utf-8"))

    counts = {severity: 0 for severity in SEVERITIES}
    # Une vulnérabilité "corrigeable" a une version de correctif publiée :
    # c'est celle sur laquelle on peut agir en montant le tag de l'image.
    fixable = {severity: 0 for severity in SEVERITIES}

    for result in data.get("Results") or []:
        for vuln in result.get("Vulnerabilities") or []:
            severity = vuln.get("Severity")
            if severity not in counts:
                continue
            counts[severity] += 1
            if vuln.get("FixedVersion"):
                fixable[severity] += 1

    return {
        "image": data.get("ArtifactName", report_path.stem),
        "counts": counts,
        "fixable": fixable,
    }


def status_icon(counts: dict) -> str:
    if counts["CRITICAL"]:
        return "🔴"
    if counts["HIGH"]:
        return "🟠"
    if counts["MEDIUM"] or counts["LOW"]:
        return "🟡"
    return "🟢"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    reports_dir = Path(sys.argv[1])
    report_files = sorted(reports_dir.rglob("*.json"))

    if not report_files:
        print("⚠️ Aucun rapport de scan trouvé.")
        return 0

    summaries = []
    for report_file in report_files:
        try:
            summaries.append(summarize(report_file))
        except (json.JSONDecodeError, OSError) as error:
            print(f"⚠️ Rapport illisible ({report_file.name}) : {error}", file=sys.stderr)

    # Les images les plus critiques en premier
    summaries.sort(
        key=lambda item: (
            -item["counts"]["CRITICAL"],
            -item["counts"]["HIGH"],
            item["image"],
        )
    )

    totals = {severity: sum(item["counts"][severity] for item in summaries) for severity in SEVERITIES}
    fixable_critical = sum(item["fixable"]["CRITICAL"] for item in summaries)
    fixable_high = sum(item["fixable"]["HIGH"] for item in summaries)
    clean = sum(1 for item in summaries if not any(item["counts"].values()))

    print("## 🔎 Scan de vulnérabilités des images\n")
    print(f"**{len(summaries)} image(s) scannée(s)** — {clean} sans vulnérabilité connue.\n")
    print(
        f"| CRITICAL | HIGH | MEDIUM | LOW |\n|---:|---:|---:|---:|\n"
        f"| {totals['CRITICAL']} | {totals['HIGH']} | {totals['MEDIUM']} | {totals['LOW']} |\n"
    )
    print(
        f"Dont **{fixable_critical} CRITICAL** et **{fixable_high} HIGH** disposant d'un correctif "
        f"publié (corrigeables en montant le tag de l'image).\n"
    )

    print("### Détail par image\n")
    print("| | Image | CRITICAL | HIGH | MEDIUM | LOW | Corrigeables (C/H) |")
    print("|---|---|---:|---:|---:|---:|---:|")
    for item in summaries:
        counts, fixable = item["counts"], item["fixable"]
        print(
            f"| {status_icon(counts)} | `{item['image']}` "
            f"| {counts['CRITICAL']} | {counts['HIGH']} | {counts['MEDIUM']} | {counts['LOW']} "
            f"| {fixable['CRITICAL']}/{fixable['HIGH']} |"
        )

    to_bump = [item for item in summaries if item["fixable"]["CRITICAL"]]
    if to_bump:
        print("\n### ⚠️ À mettre à jour en priorité\n")
        print("Ces images ont des vulnérabilités CRITICAL déjà corrigées en amont :\n")
        for item in to_bump:
            print(f"- `{item['image']}` — {item['fixable']['CRITICAL']} CRITICAL corrigeable(s)")

    print("\n> Détail complet des CVE : onglet **Security → Code scanning** du dépôt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
