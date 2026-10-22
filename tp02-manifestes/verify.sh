#!/usr/bin/env bash
# TP02 — vérifie trois pods décrits à la main, et les labels qui permettent de les retrouver.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
check "L'API server valide les manifestes (--dry-run=server)" k apply --dry-run=server -n default -f "$DIR"
verify_namespace tp02-verify
apply "$DIR"

step "Les pods"
for p in api-demo api-canari web-demo; do wait_pod_ready "$p" 90; done

step "Les labels et les sélecteurs"
count() { k get pods -n "$NS" -l "$1" -o name | grep -c . || true; }
assert_eq "app=api sélectionne les 2 API"                         "2" "$(count app=api)"
assert_eq "app.kubernetes.io/part-of=telemarche sélectionne les 3" "3" "$(count app.kubernetes.io/part-of=telemarche)"
assert_eq "environnement=production ne sélectionne que le canari"  "api-canari" "$(k get pods -n "$NS" -l environnement=production -o jsonpath='{.items[*].metadata.name}')"
assert_eq "Le canari porte le label de version 1.1"                "1.1" "$(jp pod/api-canari '{.metadata.labels.app\.kubernetes\.io/version}')"
assert_eq "Le canari tourne bien l'image 1.1"                      "telemachlearning/telemarche-api:1.1" "$(jp pod/api-canari '{.spec.containers[0].image}')"

step "Les applications répondent"
for p in api-demo api-canari; do wait_pod_http "$p" 8080 /api/info 30 || true; done
assert_contains "api-demo répond en version 1.0"   '"version":"1.0"' "$(pod_get api-demo 8080 /api/info || true)"
assert_contains "api-canari répond en version 1.1" '"version":"1.1"' "$(pod_get api-canari 8080 /api/info || true)"
assert_contains "web-demo répond"                  '"service":"web"' "$(pod_get web-demo 8080 /version || true)"
assert_eq "LOG_LEVEL est défini sur l'API"         "info" "$(jp pod/api-demo '{.spec.containers[0].env[?(@.name=="LOG_LEVEL")].value}')"

summary
