#!/usr/bin/env bash
# Construit les images durcies, mesure le gain, et les publie avec --push.
#
# Le tag reflète celui de l'amont (voir README.md). Une image dont le durcissement
# n'apporte rien ne doit pas être publiée : c'est de la dette de maintenance.
#
# Sort en échec si une image reste avec des CVE OS corrigeables : c'est exactement
# ce sur quoi la barrière de scan-images.yml bloquera le lundi suivant.
set -euo pipefail

cd "$(dirname "$0")"

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

# répertoire | image publiée | image amont (— si remplacement)
IMAGES=(
  "nginx|telemachlearning/nginx:1.29-alpine|nginx:1.29-alpine"
  "trivy|telemachlearning/trivy:0.72.0|aquasec/trivy:0.72.0"
  "git|telemachlearning/git:v2.54.0|alpine/git:v2.54.0"
  "netshoot|telemachlearning/netshoot:v0.16|nicolaka/netshoot:v0.16"
  "curl|telemachlearning/curl:8.21.0|curlimages/curl:8.21.0"
  "httpd|telemachlearning/httpd:2.4-alpine|httpd:2.4-alpine"
  "wordpress|telemachlearning/wordpress:7.0-php8.5-apache|wordpress:7.0-php8.5-apache"
  "hpa-example|telemachlearning/hpa-example:1.0.0|—"
)

# Rend « <corrigeables>/<total> » pour les CVE de paquets OS CRITICAL+HIGH.
#
# ⚠️ Le chiffre qui décide, c'est le PREMIER : la barrière de scan-images.yml ajoute
# `ignore-unfixed: true` au filtre OS. Compter le total ferait diverger ce script de
# la barrière — wordpress durcie affiche 0/163 : verte, alors qu'un décompte total
# la dirait catastrophique. Les 163 n'ont aucun correctif publié, rien à en faire.
count_os_cves() {
  trivy image --quiet --scanners vuln --pkg-types os --severity CRITICAL,HIGH \
    --format json "$1" 2>/dev/null |
    python3 -c '
import json, sys
d = json.load(sys.stdin)
vulns = [v for r in (d.get("Results") or []) for v in (r.get("Vulnerabilities") or [])]
print("%d/%d" % (sum(1 for v in vulns if v.get("FixedVersion")), len(vulns)))
' 2>/dev/null || echo "?/?"
}

failed=0

printf '%-46s %12s %12s\n' "IMAGE" "AMONT" "DURCIE"
printf '%-46s %12s %12s\n' "" "(corr./tot.)" "(corr./tot.)"
for entry in "${IMAGES[@]}"; do
  IFS='|' read -r dir image upstream <<<"$entry"

  # --no-cache --pull est obligatoire, pas une précaution : sans eux, Docker réutilise
  # le layer `apk/apt upgrade` du build précédent et l'image reconstruite est identique
  # à l'ancienne. Un re-durcissement serait un no-op silencieux (mesuré le 2026-07-27
  # sur netshoot : 15 CVE avant, 15 après avec cache, 0 sans).
  docker build --no-cache --pull -q -t "$image" "$dir" >/dev/null

  before="—"
  [[ "$upstream" != "—" ]] && before=$(count_os_cves "$upstream")
  after=$(count_os_cves "$image")

  printf '%-46s %12s %12s\n' "$image" "$before" "$after"

  if [[ "${after%%/*}" != "0" ]]; then
    echo "  ⚠️  $image garde des CVE OS corrigeables : la barrière bloquera dessus." >&2
    failed=1
  fi

  if $PUSH; then
    docker push -q "$image" >/dev/null && echo "  ✅ poussée"
  fi
done

exit "$failed"
