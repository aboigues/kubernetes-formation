#!/usr/bin/env bash
# TP08 — vérifie le budget du namespace (ResourceQuota + LimitRange) et les
# droits du ServiceAccount de supervision : lire les pods, rien d'autre.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp08-verify
apply "$DIR"

step "Le budget du namespace"
wait_rollout api 180
wait_rollout web 120
assert_eq "Quota : 10 pods au plus" "10" "$(jp resourcequota/budget '{.spec.hard.pods}')"
assert_eq "Quota : 512 Mi de requests mémoire" "512Mi" "$(jp resourcequota/budget '{.spec.hard.requests\.memory}')"
check "Le quota décompte déjà les pods en place" test -n "$(jp resourcequota/budget '{.status.used.pods}')"
# Un pod sans aucune ressource : refusé par le quota, sauf si la LimitRange
# lui en donne. --dry-run=server passe toute l'admission sans rien créer.
DEF="$(k run essai -n "$NS" --image=busybox:1.38.0 --restart=Never --dry-run=server \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.requests.memory}' 2>&1 || true)"
assert_eq "Un pod sans ressources reçoit celles de la LimitRange" "100m/64Mi" "$DEF"
k scale deployment/api -n "$NS" --replicas=12 >/dev/null
EXCES=""
for _ in $(seq 1 20); do
  EXCES="$(k get events -n "$NS" --field-selector reason=FailedCreate -o jsonpath='{.items[*].message}' 2>/dev/null | grep -o 'exceeded quota: budget' | head -1 || true)"
  [ -n "$EXCES" ] && break
  sleep 2
done
assert_eq "Au-delà de 10 pods, le quota refuse les créations" "exceeded quota: budget" "$EXCES"
k scale deployment/api -n "$NS" --replicas=3 >/dev/null

step "Les droits de la supervision"
SA="system:serviceaccount:$NS:supervision"
can() { k auth can-i "$@" --as="$SA" 2>/dev/null || true; }
assert_eq "Elle liste les pods" "yes" "$(can list pods -n "$NS")"
assert_eq "Elle lit leurs journaux" "yes" "$(can get pods/log -n "$NS")"
assert_eq "Elle ne supprime pas de pod" "no" "$(can delete pods -n "$NS")"
assert_eq "Elle ne lit pas les Secrets" "no" "$(can get secrets -n "$NS")"
assert_eq "Elle ne voit rien hors de son namespace" "no" "$(can list pods -n default)"

step "Vu du pod de supervision"
wait_pod_ready supervision 60
assert_eq "Le pod porte l'identité supervision" "supervision" "$(jp pod/supervision '{.spec.serviceAccountName}')"
appel() { k exec -n "$NS" supervision -- /outils/appel "$@" 2>/dev/null | awk '{print $NF}' || true; }
assert_eq "Son jeton liste les pods (200)" "200" "$(appel GET pods)"
assert_eq "Son jeton ne lit pas les Secrets (403)" "403" "$(appel GET secrets)"

summary
