#!/usr/bin/env bash
# TP01 — vérifie le cluster, puis déploie la vitrine en mode déclaratif.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Le cluster"
need_cluster
check "L'API server se déclare prêt (/readyz)"     k get --raw /readyz
check "Tous les nœuds sont Ready"                   k wait --for=condition=Ready nodes --all --timeout=90s
check "Le DNS du cluster (CoreDNS) est prêt"        k wait --for=condition=Ready pods -n kube-system -l k8s-app=kube-dns --timeout=90s

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp01-verify
apply "$DIR"

step "La vitrine"
wait_rollout web
assert_eq "3 réplicas prêts" "3" "$(jp deployment/web '{.status.readyReplicas}')"
assert_eq "Image en version figée" "telemachlearning/telemarche-web:1.0" "$(jp deployment/web '{.spec.template.spec.containers[0].image}')"
assert_eq "Service de type NodePort" "NodePort" "$(jp service/web '{.spec.type}')"
check "Le Service a trouvé ses 3 pods" bash -c "[ \"\$($KUBECTL get endpointslices -n $NS -l kubernetes.io/service-name=web -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{\"\n\"}{end}' | grep -c .)\" -eq 3 ]"
wait_svc_http web 80 /version 60 || true
assert_contains "La vitrine répond derrière le Service" '"service":"web"' "$(svc_get web 80 /version || true)"

summary
