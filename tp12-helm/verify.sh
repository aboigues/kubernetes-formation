#!/usr/bin/env bash
# TP12 — vérifie le chart Helm de Télémarché : il passe helm lint, ses values
# de production se rendent comme prévu, et une release vit tout son cycle
# (install, upgrade en 1.1, rollback) ; une seconde release cohabite avec la
# première dans le même namespace.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"
CHART="$DIR/telemarche"

need_cluster
command -v helm >/dev/null 2>&1 || die "helm introuvable : installez Helm 4 (voir les prérequis du README racine)."
helm version --short 2>/dev/null | grep -q '^v4\.' || die "Helm 4 attendu (trouvé : $(helm version --short 2>/dev/null))."

step "Le chart ($(basename "$DIR"))"
no_holes "$DIR"
check "helm lint" helm lint "$CHART"
# Rendre sans installer, puis lire un champ : kubectl sait le faire sur un rendu.
# (Le Service n'a pas de spec.replicas : seul le Deployment répond.)
rendu() { helm template rendu "$CHART" --show-only templates/api.yaml "$@" 2>/dev/null | k create --dry-run=client -f - -o 'jsonpath={.spec.replicas}' 2>/dev/null || true; }
assert_eq "values.yaml : 1 réplica d'API" "1" "$(rendu)"
assert_eq "values-prod.yaml : 3 réplicas d'API" "3" "$(rendu -f "$CHART/values-prod.yaml")"
check "Aucun namespace écrit dans les templates" \
  bash -c "! helm template rendu '$CHART' | grep -qE '^  namespace:'"

verify_namespace tp12-verify
H() { helm -n "$NS" "$@"; }
version() { sleep 8; svc_get "$1-web" 80 /api/info | grep -o '"version":"[^"]*"' || true; }

step "Le cycle de vie d'une release"
if out="$(H install verif "$CHART" --wait --timeout 3m 2>&1)"; then
  printf "  ${GREEN}✓${NC} helm install verif\n"; PASS=$((PASS+1))
else
  printf "  ${RED}✗${NC} helm install a échoué :\n"; printf '%s\n' "$out" | tail -5 | sed 's/^/      /'; FAIL=$((FAIL+1)); summary
fi
wait_svc_http verif-web 80 /api/info 60 || true
assert_eq "La vitrine joint SON API : version 1.0 (appVersion)" '"version":"1.0"' "$(version verif)"
assert_eq "LOG_LEVEL vient des values" "debug" "$(jp deployment/verif-api '{.spec.template.spec.containers[0].env[?(@.name=="LOG_LEVEL")].value}')"
check "helm upgrade --set api.image.tag=1.1" H upgrade verif "$CHART" --set api.image.tag=1.1 --wait --timeout 3m
assert_eq "Après l'upgrade : version 1.1" '"version":"1.1"' "$(version verif)"
check "helm rollback verif 1" H rollback verif 1 --wait --timeout 3m
assert_eq "Après le rollback : version 1.0" '"version":"1.0"' "$(version verif)"
assert_eq "Le rollback est une NOUVELLE révision (3)" "3" "$(H history verif -o json 2>/dev/null | grep -o '"revision":[0-9]*' | tail -1 | cut -d: -f2)"

step "Deux releases dans le même namespace"
check "helm install verif-b (sans collision de noms)" H install verif-b "$CHART" --wait --timeout 3m
assert_eq "Sa vitrine appelle sa propre API" "http://verif-b-api" \
  "$(jp deployment/verif-b-web '{.spec.template.spec.containers[0].env[?(@.name=="API_URL")].value}')"
wait_svc_http verif-b-web 80 /api/info 60 || true

summary
