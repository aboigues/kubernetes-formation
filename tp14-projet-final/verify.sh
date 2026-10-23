#!/usr/bin/env bash
# TP14 — projet final : Télémarché complet doit tourner de bout en bout, et le
# rapport d'incidents doit être rempli. Chaque contrôle désigne l'incident qu'il
# vérifie, pour dire OÙ chercher quand il échoue.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Le rapport et les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
check "Le rapport décrit 5 incidents" test "$(grep -cE '^\| [1-5] \|' "$DIR/rapport.md")" -eq 5
check "Aucun Secret écrit dans les fichiers" bash -c "! grep -rqE '^kind: *Secret' '$DIR'"
verify_namespace tp14-verify
k create secret generic db-credentials -n "$NS" \
  --from-literal=POSTGRES_USER=telemarche \
  --from-literal=POSTGRES_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" >/dev/null
apply "$DIR"

step "Le stockage (incident 1)"
SC="$(jp statefulset/db '{.spec.volumeClaimTemplates[0].spec.storageClassName}')"
check "La StorageClass demandée existe (${SC:-défaut})" bash -c "[ -z '$SC' ] || $KUBECTL get storageclass '$SC'"
for _ in $(seq 1 30); do [ "$(jp pvc/donnees-db-0 '{.status.phase}')" = Bound ] && break; sleep 3; done
assert_eq "Le volume de la base est lié" "Bound" "$(jp pvc/donnees-db-0 '{.status.phase}')"

step "La base (incident 2)"
check "Le StatefulSet db est prêt" k rollout status statefulset/db -n "$NS" --timeout=180s
if [ "$(jp pod/db-0 '{.status.containerStatuses[0].state.waiting.reason}')" = CreateContainerConfigError ]; then
  warn "db-0 : $(k get events -n "$NS" --field-selector involvedObject.name=db-0,reason=Failed -o jsonpath='{.items[-1:].message}' 2>/dev/null)"
fi

step "Le schéma (incident 3)"
if k wait --for=condition=complete job/migration -n "$NS" --timeout=180s >/dev/null 2>&1; then
  printf "  ${GREEN}✓${NC} Le Job de migration a réussi\n"; PASS=$((PASS+1))
else
  printf "  ${RED}✗${NC} Le Job de migration n'a pas abouti\n"; FAIL=$((FAIL+1))
  k get events -n "$NS" --field-selector reason=Failed -o jsonpath='{range .items[-2:]}{.message}{"\n"}{end}' 2>/dev/null | cut -c1-160 | sed 's/^/      /' || true
fi

step "L'API (incidents 4 et 5)"
wait_rollout api 180
assert_eq "La readiness probe interroge /ready" "/ready" "$(jp deployment/api '{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')"
EP="$(k get endpointslices -n "$NS" -l kubernetes.io/service-name=api -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null || true)"
check "Le Service api a des pods derrière lui (endpoints)" test -n "$EP"

step "Télémarché, de bout en bout"
wait_rollout web 120
wait_svc_http web 80 /api/info 60 || true
assert_contains "La vitrine joint l'API, qui stocke dans PostgreSQL" '"stockage":"postgresql"' "$(svc_get web 80 /api/info || true)"
BODY="$(mktemp)"; echo '{"product_id": 2, "quantity": 5}' >"$BODY"
check "Une commande est enregistrée" k create --raw "/api/v1/namespaces/$NS/services/http:web:80/proxy/api/orders" -f "$BODY"
rm -f "$BODY"
assert_contains "La commande se relit" '"quantity":5' "$(svc_get web 80 /api/orders || true)"

summary
