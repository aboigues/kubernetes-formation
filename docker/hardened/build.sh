#!/usr/bin/env bash
# Construit les images durcies, mesure le gain, et les publie avec --push.
#
# Le tag reflète celui de l'amont (voir README.md). Une image dont le durcissement
# n'apporte rien ne doit pas être publiée : c'est de la dette de maintenance.
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
  "hpa-example|telemachlearning/hpa-example:1.0.0|—"
)

count_os_cves() {
  trivy image --quiet --scanners vuln --pkg-types os --severity CRITICAL,HIGH \
    --format json "$1" 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for r in (d.get("Results") or []) for v in (r.get("Vulnerabilities") or [])))' \
    2>/dev/null || echo "?"
}

printf '%-46s %8s %8s\n' "IMAGE" "AMONT" "DURCIE"
for entry in "${IMAGES[@]}"; do
  IFS='|' read -r dir image upstream <<<"$entry"

  docker build -q -t "$image" "$dir" >/dev/null

  before="—"
  [[ "$upstream" != "—" ]] && before=$(count_os_cves "$upstream")
  after=$(count_os_cves "$image")

  printf '%-46s %8s %8s\n' "$image" "$before" "$after"

  if [[ "$after" != "0" ]]; then
    echo "  ⚠️  $image n'est pas à 0 CVE OS : vérifier avant de publier." >&2
  fi

  if $PUSH; then
    docker push -q "$image" >/dev/null && echo "  ✅ poussée"
  fi
done
