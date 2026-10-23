#!/usr/bin/env bash
# TP10 — vérifie le cluster que VOUS avez installé avec kubeadm (pas minikube) :
# nœuds, control plane, etcd, Calico, puis Télémarché déployé de bout en bout.
#
# À lancer là où kubectl joint ce cluster : sur cp-1, ou sur votre poste avec
# le kubeconfig de cp-1 (voir l'étape 8 du README).
# Ce TP n'est PAS rejoué par la CI : elle n'a pas de VM (voir .ci-statique).
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster
k get nodes -o jsonpath='{.items[*].metadata.name}' | grep -qw cp-1 \
  || die "Ce cluster n'a pas de nœud cp-1 : ce n'est pas celui du TP10 (contexte : $(k config current-context))."

step "Vos fichiers ($(basename "$DIR"))"
no_holes "$DIR"
VOULU="$(grep -E '^ *podSubnet:' "$DIR/kubeadm-config.yaml" | awk '{print $2}')"
REEL="$(k get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}' | awk '/podSubnet:/{print $2}')"
assert_eq "Le cluster a été initialisé avec VOTRE réseau des pods" "$VOULU" "$REEL"

step "Les nœuds"
assert_eq "Trois nœuds" "3" "$(k get nodes -o name | grep -c .)"
check "Tous Ready" k wait --for=condition=Ready nodes --all --timeout=60s
assert_eq "Tous en Kubernetes v1.37.1" "v1.37.1" "$(k get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}' | tr ' ' '\n' | sort -u | xargs)"
assert_eq "Tous sur containerd, en cgroups systemd" "containerd" \
  "$(k get nodes -o jsonpath='{.items[*].status.nodeInfo.containerRuntimeVersion}' | tr ' ' '\n' | cut -d: -f1 | sort -u | xargs)"
assert_contains "Les nœuds annoncent le réseau du cluster (10.30.0.0/24)" "10.30.0.21" \
  "$(k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')"
assert_contains "Le control plane refuse les applications (taint)" "node-role.kubernetes.io/control-plane" \
  "$(k get node cp-1 -o jsonpath='{.spec.taints[*].key}')"

step "Le control plane"
for c in kube-apiserver kube-controller-manager kube-scheduler etcd; do
  assert_eq "$c (pod statique) prêt" "True" \
    "$(k get pod "$c-cp-1" -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
done
ETCD="$(k exec -n kube-system etcd-cp-1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key endpoint health 2>&1 || true)"
assert_contains "etcd répond (endpoint health)" "is healthy" "$ETCD"

step "Le réseau (Calico)"
NODES="$(k get nodes -o name | grep -c .)"
check "Un calico-node prêt par nœud ($NODES)" k rollout status daemonset/calico-node -n calico-system --timeout=180s
check "Le DNS du cluster est prêt" k rollout status deployment/coredns -n kube-system --timeout=120s

step "Télémarché sur le nouveau cluster"
verify_namespace tp10-verify
apply "$HERE/outils/telemarche.yaml"
wait_rollout api 240
wait_rollout web 180
assert_eq "Aucun pod applicatif sur le control plane" "0" \
  "$(k get pods -n "$NS" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | grep -cx cp-1 || true)"
assert_eq "Les pods sont répartis sur les deux workers" "2" \
  "$(k get pods -n "$NS" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | grep -c .)"
assert_contains "Les pods ont une adresse du réseau des pods (192.168.x.x)" "192.168." \
  "$(k get pods -n "$NS" -l app=api -o jsonpath='{.items[0].status.podIP}')"
wait_svc_http web 80 /api/info 90 || true
assert_contains "La vitrine joint l'API d'un autre nœud (DNS + réseau des pods)" '"service":"api"' "$(svc_get web 80 /api/info || true)"

summary
