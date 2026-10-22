#!/usr/bin/env bash
# TP03 — déploie web + api, vérifie l'exposition, puis rejoue une mise à jour
# 1.0 -> 1.1 SOUS TRAFIC : aucune requête ne doit échouer.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp03-verify
apply "$DIR"

step "Les déploiements"
wait_rollout api 180
wait_rollout web 120
assert_eq "3 réplicas d'API prêts" "3" "$(jp deployment/api '{.status.readyReplicas}')"
assert_eq "Mise à jour sans baisse de capacité (maxUnavailable)" "0" "$(jp deployment/api '{.spec.strategy.rollingUpdate.maxUnavailable}')"
assert_eq "Readiness sur /ready"   "/ready"   "$(jp deployment/api '{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')"
assert_eq "Liveness sur /healthz"  "/healthz" "$(jp deployment/api '{.spec.template.spec.containers[0].livenessProbe.httpGet.path}')"
check "Une startupProbe est définie" test -n "$(jp deployment/api '{.spec.template.spec.containers[0].startupProbe}')"

step "L'exposition"
assert_eq "Service api interne (ClusterIP)" "ClusterIP" "$(jp service/api '{.spec.type}')"
assert_eq "Service web ouvert (NodePort)"   "NodePort"  "$(jp service/web '{.spec.type}')"
assert_eq "Le Service api a trouvé ses 3 pods" "3" \
  "$(k get endpointslices -n "$NS" -l kubernetes.io/service-name=api -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}' | grep -c . || true)"
wait_svc_http web 80 /api/info 60 || true
assert_contains "La vitrine joint l'API par son nom DNS (web -> api)" '"service":"api"' "$(svc_get web 80 /api/info || true)"

step "Mise à jour 1.0 -> 1.1 sous trafic"
LOG="$(mktemp)"
( while :; do
    if r="$(svc_get web 80 /api/info)"; then
      printf 'ok %s\n' "$(printf '%s' "$r" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
    else
      echo ko
    fi
    sleep 0.2
  done ) >"$LOG" &
LOAD=$!
sleep 3
k set image deployment/api -n "$NS" api=telemachlearning/telemarche-api:1.1 >/dev/null
k rollout status deployment/api -n "$NS" --timeout=180s >/dev/null || true
sleep 3
kill "$LOAD" 2>/dev/null; wait "$LOAD" 2>/dev/null || true
TOTAL="$(grep -c . "$LOG" || true)"; KO="$(grep -c '^ko' "$LOG" || true)"
info "$TOTAL requêtes envoyées pendant la mise à jour"
assert_eq "Aucune requête en échec pendant la mise à jour" "0" "$KO"
assert_contains "Le trafic a basculé sur la 1.1" "ok 1.1" "$(tail -3 "$LOG")"
assert_eq "Tous les pods sont en 1.1" "telemachlearning/telemarche-api:1.1" "$(jp deployment/api '{.spec.template.spec.containers[0].image}')"
rm -f "$LOG"

step "Retour arrière"
k rollout undo deployment/api -n "$NS" >/dev/null 2>&1
k rollout status deployment/api -n "$NS" --timeout=180s >/dev/null || true
assert_eq "rollout undo ramène la 1.0" "telemachlearning/telemarche-api:1.0" "$(jp deployment/api '{.spec.template.spec.containers[0].image}')"

summary
