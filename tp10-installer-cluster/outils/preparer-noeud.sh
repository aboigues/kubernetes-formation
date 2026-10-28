#!/usr/bin/env bash
# Préparer un nœud AlmaLinux 10 pour kubeadm : système, containerd, paquets
# Kubernetes. À lancer en root sur CHAQUE nœud (control plane et workers).
#
# Usage : sudo ./preparer-noeud.sh <IP du nœud sur le réseau du cluster>
#   ex. sur cp-1 : sudo ./preparer-noeud.sh 10.30.0.11
set -euo pipefail

NODE_IP="${1:?Usage : $0 <IP du nœud sur le réseau du cluster, ex. 10.30.0.11>}"
K8S_VERSION="1.37.1"              # la MÊME sur tous les nœuds ; verify.sh la contrôle
K8S_MINEURE="v${K8S_VERSION%.*}"  # v1.37 : il y a un dépôt de paquets par version mineure

# Un dépôt kubernetes laissé par un passage précédent ferait échouer le premier
# « dnf install » s'il est faux : l'étape 7 le réécrit de toute façon.
rm -f /etc/yum.repos.d/kubernetes.repo

echo "== 0. Les ressources du nœud"
# Plancher = ce que kubeadm exige (control plane : 2 processeurs, 1700 Mo) ou
# en dessous de quoi le nœud ne tient pas ; conseillé = ce que le lab fournit.
# Disque mesuré sur cp-1 : 3 Go occupés une fois toutes les images téléchargées.
case "$(hostname -s)" in
  cp-*) ROLE="control plane"; CPU_MIN=2; MEM_MIN=1700; MEM_CONSEIL=2800 ;;
  *)    ROLE="worker";        CPU_MIN=1; MEM_MIN=1000; MEM_CONSEIL=1400 ;;
esac
DISQUE_MIN=4   # Go libres sous /var, où containerd range les images
cpus="$(nproc)"
mem="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
disque="$(df -P -BG /var | awk 'NR==2{gsub("G","",$4); print $4}')"
echo "   $(hostname -s) ($ROLE) : $cpus processeur(s), $mem Mo de mémoire, $disque Go libres sous /var"
manque=""
[ "$cpus" -ge "$CPU_MIN" ]      || manque="$manque\n   - $CPU_MIN processeurs au moins (il y en a $cpus)"
[ "$mem" -ge "$MEM_MIN" ]       || manque="$manque\n   - $MEM_MIN Mo de mémoire au moins (il y en a $mem)"
[ "$disque" -ge "$DISQUE_MIN" ] || manque="$manque\n   - $DISQUE_MIN Go libres sous /var au moins (il y en a $disque)"
if [ -n "$manque" ]; then
  printf "Nœud trop petit pour un %s :%b\nAgrandissez la VM (lab Vagrant : le Vagrantfile), puis relancez.\n" "$ROLE" "$manque" >&2
  exit 1
fi
[ "$mem" -ge "$MEM_CONSEIL" ] \
  || echo "   ⚠ $mem Mo de mémoire : ça démarre, mais en dessous de $MEM_CONSEIL Mo le $ROLE risque de saturer (probes qui expirent, redémarrages)."

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

echo "== 7. kubeadm, kubelet et kubectl v${K8S_VERSION}, et crictl"
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINEURE}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINEURE}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
# La version exacte : sans elle, dnf prend le dernier correctif de la mineure,
# et les nœuds préparés à quelques jours d'écart n'auraient pas la même.
for p in kubelet kubeadm kubectl; do
  if rpm -q "$p" >/dev/null 2>&1 && [ "$(rpm -q --qf '%{VERSION}' "$p")" != "$K8S_VERSION" ]; then
    dnf -y downgrade "$p-$K8S_VERSION" --disableexcludes=kubernetes >/dev/null 2>&1 \
      || dnf -y install "$p-$K8S_VERSION" --disableexcludes=kubernetes >/dev/null   # plus récente : install met à jour
  else
    dnf -y install "$p-$K8S_VERSION" --disableexcludes=kubernetes >/dev/null
  fi
done
dnf -y install cri-tools --disableexcludes=kubernetes >/dev/null   # crictl : voir les conteneurs du nœud, même sans API server

echo "== 8. Le kubelet annonce l'IP du réseau du cluster (la VM en a deux)"
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" >/etc/sysconfig/kubelet
systemctl enable --now kubelet

echo "== Nœud prêt : $(kubeadm version -o short), containerd $(containerd --version | awk '{print $3}')"
echo "   (le kubelet redémarre en boucle jusqu'à « kubeadm init » ou « kubeadm join » : c'est normal)"
