#!/usr/bin/env bash
# TP11 — vérifie les NetworkPolicies de Télémarché avec de vrais paquets :
# la vitrine est ouverte à tous, l'API ne répond qu'à la vitrine, et les pods
# du namespace ne sortent que vers le DNS (et la vitrine vers l'API).
# Il faut un plugin réseau qui APPLIQUE les NetworkPolicies (Calico ici).
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster
k get daemonset calico-node -n kube-system >/dev/null 2>&1 \
  || die "Calico absent : les NetworkPolicies seraient acceptées mais IGNORÉES. Étape 1 : minikube start --cni=calico."

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp11-verify
DEHORS="$NS-dehors"
trap 'k delete namespace "$DEHORS" --ignore-not-found --wait=false >/dev/null 2>&1 || true; cleanup_ns' EXIT
k delete namespace "$DEHORS" --ignore-not-found --wait=true --timeout=120s >/dev/null
k create namespace "$DEHORS" >/dev/null
apply "$DIR"

step "L'état de départ, sous les politiques"
wait_rollout api 180
wait_rollout web 120
assert_eq "tout-interdire vise tous les pods, entrée et sortie" "{}:Ingress Egress" \
  "$(jp networkpolicy/tout-interdire '{.spec.podSelector}:{.spec.policyTypes[*]}')"

# Deux clients : l'un dans un autre namespace, l'autre dans celui-ci, sans label.
client() {
  k apply -n "$1" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $2
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: client
      image: telemachlearning/curl:8.21.0
      command: ["sleep", "600"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {cpu: 100m, memory: 32Mi}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
EOF
  k wait --for=condition=Ready "pod/$2" -n "$1" --timeout=90s >/dev/null
}
client "$DEHORS" dehors
client "$NS" pirate
WEB="http://web.$NS.svc.cluster.local"
API="http://api.$NS.svc.cluster.local"
# Code HTTP obtenu, ou « bloqué » si la connexion n'aboutit pas.
# --retry : le résolveur musl de l'image rate parfois la toute première requête.
code() {
  local c
  c="$(k exec -n "$1" "$2" -- curl -s -o /dev/null -m 5 --retry 2 --retry-connrefused -w '%{http_code}' "${@:3}" 2>/dev/null || true)"
  case "$c" in ""|000) echo "bloqué" ;; *) echo "$c" ;; esac
}

step "Le trafic autorisé"
assert_eq "Un client d'un autre namespace joint la vitrine" "200" "$(code "$DEHORS" dehors "$WEB/")"
assert_eq "La vitrine joint l'API (DNS + port 8080)" "200" "$(code "$DEHORS" dehors "$WEB/api/info")"

step "Le trafic interdit"
assert_eq "Un client d'un autre namespace ne joint pas l'API" "bloqué" "$(code "$DEHORS" dehors "$API/api/info")"
assert_eq "Un pod du namespace, sans le label app=web, ne joint pas l'API" "bloqué" "$(code "$NS" pirate "$API/api/info")"
assert_eq "Un pod du namespace ne sort pas (API server injoignable)" "bloqué" "$(code "$NS" pirate -k https://kubernetes.default.svc)"

summary
