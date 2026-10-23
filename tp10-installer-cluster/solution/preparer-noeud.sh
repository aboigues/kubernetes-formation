#!/usr/bin/env bash
# Préparer un nœud AlmaLinux 10 pour kubeadm : système, containerd, paquets
# Kubernetes. À lancer en root sur CHAQUE nœud (control plane et workers).
#
# Usage : sudo ./preparer-noeud.sh <IP du nœud sur le réseau du cluster>
#   ex. sur cp-1 : sudo ./preparer-noeud.sh 10.30.0.11
set -euo pipefail

NODE_IP="${1:?Usage : $0 <IP du nœud sur le réseau du cluster, ex. 10.30.0.11>}"
K8S_MINEURE="v1.37"

echo "== 1. Modules noyau du réseau des conteneurs"
# Sur AlmaLinux 10, br_netfilter n'est plus livré avec le noyau de base : il
# est dans kernel-modules-extra, qui doit correspondre EXACTEMENT au noyau lancé.
if ! modinfo br_netfilter >/dev/null 2>&1; then
  dnf -y install "kernel-modules-extra-$(uname -r)" >/dev/null \
    || { echo "kernel-modules-extra-$(uname -r) introuvable : « dnf -y update kernel », redémarrez, puis relancez ce script." >&2; exit 1; }
fi
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "== 2. Routage des paquets entre interfaces"
cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo "== 3. Pas de swap (le kubelet refuse de démarrer s'il en trouve)"
swapoff -a
sed -i '/\sswap\s/ s/^#*/#/' /etc/fstab
# AlmaLinux 10 crée aussi un swap compressé en mémoire (zram) à chaque démarrage.
if rpm -q zram-generator-defaults >/dev/null 2>&1; then
  dnf -y remove zram-generator-defaults >/dev/null
fi

echo "== 4. SELinux en mode permissif (recommandation de kubeadm)"
setenforce 0 || true
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo "== 5. Pare-feu : les ports du cluster, si firewalld est actif"
if systemctl is-active --quiet firewalld; then
  # control plane : API server, etcd, kubelet, scheduler, controller-manager
  # workers : kubelet, NodePort ; Calico : BGP, VXLAN, Typha
  for p in 6443/tcp 2379-2380/tcp 10250/tcp 10257/tcp 10259/tcp 30000-32767/tcp \
           179/tcp 4789/udp 5473/tcp; do
    firewall-cmd --permanent --add-port="$p" >/dev/null
  done
  firewall-cmd --reload >/dev/null
fi

echo "== 6. Le runtime de conteneurs : containerd, en cgroups systemd"
dnf -y install dnf-plugins-core >/dev/null
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf -y install containerd.io >/dev/null
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml
cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
systemctl enable --now containerd
systemctl restart containerd

echo "== 7. kubeadm, kubelet et kubectl ${K8S_MINEURE}"
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINEURE}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINEURE}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes >/dev/null

echo "== 8. Le kubelet annonce l'IP du réseau du cluster (la VM en a deux)"
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" >/etc/sysconfig/kubelet
systemctl enable --now kubelet

echo "== Nœud prêt : $(kubeadm version -o short), containerd $(containerd --version | awk '{print $3}')"
echo "   (le kubelet redémarre en boucle jusqu'à « kubeadm init » ou « kubeadm join » : c'est normal)"
