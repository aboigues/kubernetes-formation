#!/usr/bin/env bash
# TP06 — vérifie les requests/limits de l'API (et sa classe QoS), puis un HPA
# qui la fait réellement monter en réplicas sous une charge CPU.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster
# metrics-server n'est prêt qu'après sa première collecte (une minute environ).
metrics_ok() {
  k get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q True
}
for _ in $(seq 1 40); do metrics_ok && break; sleep 3; done
metrics_ok || die "metrics-server absent ou pas prêt : « minikube addons enable metrics-server », puis attendez une minute (étape 4)."

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp06-verify
apply "$DIR"

step "Les ressources de l'API"
wait_rollout api 180
wait_rollout web 120
assert_eq "Request CPU : un dixième de cœur" "100m" "$(jp deployment/api '{.spec.template.spec.containers[0].resources.requests.cpu}')"
assert_eq "Limite mémoire : 64 Mi" "64Mi" "$(jp deployment/api '{.spec.template.spec.containers[0].resources.limits.memory}')"
POD="$(k get pods -n "$NS" -l app=api -o jsonpath='{.items[0].metadata.name}')"
assert_eq "Classe QoS de l'API" "Burstable" "$(jp "pod/$POD" '{.status.qosClass}')"
# Un « replicas » dans le manifeste remettrait l'API à ce nombre à chaque apply.
check "Le manifeste ne fixe plus replicas (le HPA décide)" \
  bash -c "! $KUBECTL get deployment/api -n '$NS' -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | grep -q '\"replicas\"'"

step "Le HPA"
assert_eq "Il pilote le Deployment api" "Deployment/api" "$(jp hpa/api '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')"
assert_eq "Entre 2 et 6 réplicas" "2-6" "$(jp hpa/api '{.spec.minReplicas}-{.spec.maxReplicas}')"
# metrics-server publie une mesure par fenêtre de 15 à 60 s : on attend la première.
UTIL=""
for _ in $(seq 1 60); do
  UTIL="$(jp hpa/api '{.status.currentMetrics[0].resource.current.averageUtilization}')"
  [ -n "$UTIL" ] && break
  sleep 3
done
check "Le HPA lit la consommation CPU (actuellement ${UTIL:-?} %)" test -n "$UTIL"

step "Sous la charge"
apply "$HERE/outils/charge.yaml"
MAX=0
for _ in $(seq 1 60); do
  N="$(jp deployment/api '{.status.readyReplicas}')"
  [ "${N:-0}" -gt "$MAX" ] && MAX="$N"
  [ "$MAX" -ge 4 ] && break
  sleep 4
done
check "L'API monte à 4 réplicas prêts ou plus (atteint : $MAX)" test "$MAX" -ge 4
k get hpa api -n "$NS" 2>/dev/null | sed 's/^/      /' || true

summary
