#!/usr/bin/env bash
# TP04 — vérifie un DaemonSet (un pod par nœud), un Job (5 réussites, 2 à la
# fois) et un CronJob (déclenché à la demande pour ne pas attendre 5 minutes).
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp04-verify
apply "$DIR"

step "L'état de départ"
wait_rollout api 180
wait_rollout web 120

step "Le DaemonSet : un pod par nœud"
NODES="$(k get nodes -o name | grep -c .)"
check "Le DaemonSet sonde est déployé" k rollout status daemonset/sonde -n "$NS" --timeout=120s
assert_eq "Autant de pods sonde que de nœuds ($NODES)" "$NODES" "$(jp daemonset/sonde '{.status.numberReady}')"
POD="$(k get pods -n "$NS" -l app=sonde -o jsonpath='{.items[0].metadata.name}')"
NODE="$(jp "pod/$POD" '{.spec.nodeName}')"
# La sonde peut démarrer avant la vitrine (web=000) : on attend une mesure réussie.
for _ in $(seq 1 20); do
  k logs -n "$NS" "$POD" 2>/dev/null | grep -q "noeud=$NODE web=200" && break
  sleep 2
done
assert_contains "La sonde connaît son nœud et joint la vitrine" "noeud=$NODE web=200" "$(k logs -n "$NS" "$POD" 2>/dev/null || true)"

step "Le Job : 5 réussites, 2 à la fois"
assert_eq "parallelism = 2" "2" "$(jp job/commandes '{.spec.parallelism}')"
check "Le Job commandes se termine" k wait --for=condition=complete job/commandes -n "$NS" --timeout=180s
assert_eq "5 exécutions réussies" "5" "$(jp job/commandes '{.status.succeeded}')"
assert_eq "Aucune relance sur place (restartPolicy)" "Never" "$(jp job/commandes '{.spec.template.spec.restartPolicy}')"

step "Le CronJob : planifié, sans chevauchement"
assert_eq "Toutes les 5 minutes" "*/5 * * * *" "$(jp cronjob/rapport '{.spec.schedule}')"
assert_eq "Jamais deux rapports en même temps" "Forbid" "$(jp cronjob/rapport '{.spec.concurrencyPolicy}')"
k create job rapport-verify --from=cronjob/rapport -n "$NS" >/dev/null
check "Un rapport déclenché à la demande se termine" k wait --for=condition=complete job/rapport-verify -n "$NS" --timeout=120s
assert_contains "Le rapport compte des commandes" "commande(s) vue(s)" "$(k logs -n "$NS" job/rapport-verify 2>/dev/null || true)"

summary
