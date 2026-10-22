#!/usr/bin/env bash
# TP05 — PostgreSQL persistante raccordée à l'API : configuration par ConfigMap,
# identifiants par Secret (créé ici, jamais versionné), schéma par un Job, et
# des données qui survivent à la suppression des pods.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
check "Aucun Secret écrit dans les fichiers" bash -c "! grep -rqE '^kind: *Secret' '$DIR'"
verify_namespace tp05-verify
# Le Secret se crée à la main, avec un mot de passe aléatoire (jamais dans Git).
k create secret generic db-credentials -n "$NS" \
  --from-literal=POSTGRES_USER=telemarche \
  --from-literal=POSTGRES_PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" >/dev/null
apply "$DIR"

step "La base"
check "Le StatefulSet db est prêt" k rollout status statefulset/db -n "$NS" --timeout=180s
assert_eq "Le pod a un nom stable" "db-0" "$(k get pods -n "$NS" -l app=db -o jsonpath='{.items[0].metadata.name}')"
assert_eq "Le volume de db-0 est lié (PVC donnees-db-0)" "Bound" "$(jp pvc/donnees-db-0 '{.status.phase}')"
assert_eq "Service headless (clusterIP: None)" "None" "$(jp service/db '{.spec.clusterIP}')"

step "La migration"
if k wait --for=condition=complete job/migration -n "$NS" --timeout=180s >/dev/null 2>&1; then
  printf "  ${GREEN}✓${NC} Le Job de migration a réussi\n"; PASS=$((PASS+1))
else
  printf "  ${RED}✗${NC} Le Job de migration n'a pas abouti\n"; FAIL=$((FAIL+1))
  k logs -n "$NS" job/migration --tail=5 2>/dev/null | sed 's/^/      /' || true
fi

step "L'API raccordée"
wait_rollout api 180
wait_rollout web 120
wait_svc_http web 80 /api/info 60 || true
INFO="$(svc_get web 80 /api/info || true)"
assert_contains "L'API stocke dans PostgreSQL" '"stockage":"postgresql"' "$INFO"
assert_contains "L'API lit le fichier de configuration monté" '"cache.ttl":"300"' "$INFO"
assert_eq "LOG_LEVEL vient de la ConfigMap" "api-config" "$(jp deployment/api '{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')"
assert_eq "Les identifiants viennent du Secret" "db-credentials" "$(jp deployment/api '{.spec.template.spec.containers[0].envFrom[1].secretRef.name}')"

step "Les données survivent aux pods"
BODY="$(mktemp)"; echo '{"product_id": 3, "quantity": 7}' >"$BODY"
check "Une commande est enregistrée" k create --raw "/api/v1/namespaces/$NS/services/http:web:80/proxy/api/orders" -f "$BODY"
rm -f "$BODY"
k delete pod db-0 -n "$NS" --wait=true >/dev/null
k rollout status statefulset/db -n "$NS" --timeout=180s >/dev/null || true
k rollout restart deployment/api -n "$NS" >/dev/null
k rollout status deployment/api -n "$NS" --timeout=180s >/dev/null || true
wait_svc_http web 80 /api/orders 60 || true
SEEN=0
for _ in 1 2 3 4 5 6; do   # plusieurs pods d'API : chacun doit voir la commande
  svc_get web 80 /api/orders | grep -q '"quantity":7' && SEEN=$((SEEN+1))
done
assert_eq "La commande survit à db-0 ET à tous les pods d'API (vue 6 fois sur 6)" "6" "$SEEN"

summary
