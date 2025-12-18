#!/bin/bash
# prepare-node.sh - Script de préparation d'un nœud pour Kubernetes
# Usage: ./prepare-node.sh <master|worker> <number>

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables configurables
K8S_VERSION=${K8S_VERSION:-"v1.28"}
BASE_IP=${BASE_IP:-"192.168.1"}

# Fonctions
print_step() {
    echo -e "${GREEN}[STEP $1]${NC} $2"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Vérifier qu'on est root ou sudo
if [ "$EUID" -ne 0 ]; then
    print_error "Ce script doit être exécuté en tant que root ou avec sudo"
    exit 1
fi

# Variables
NODE_TYPE=$1
NODE_NUMBER=$2

# Vérifier les arguments
if [ -z "$NODE_TYPE" ] || [ -z "$NODE_NUMBER" ]; then
    echo "Usage: $0 <master|worker> <number>"
    echo ""
    echo "Exemples:"
    echo "  sudo $0 master 1   # Préparer master1 (192.168.1.10)"
    echo "  sudo $0 worker 2   # Préparer worker2 (192.168.1.21)"
    echo ""
    echo "Variables d'environnement optionnelles:"
    echo "  K8S_VERSION : Version de Kubernetes (défaut: v1.28)"
    echo "  BASE_IP     : Base des IPs (défaut: 192.168.1)"
    exit 1
fi

# Valider le type
if [ "$NODE_TYPE" != "master" ] && [ "$NODE_TYPE" != "worker" ]; then
    print_error "Le type doit être 'master' ou 'worker'"
    exit 1
fi

# Calculer l'IP et le hostname
if [ "$NODE_TYPE" == "master" ]; then
    NODE_IP="${BASE_IP}.$((10 + NODE_NUMBER - 1))"
else
    NODE_IP="${BASE_IP}.$((20 + NODE_NUMBER - 1))"
fi
HOSTNAME="${NODE_TYPE}${NODE_NUMBER}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Préparation du nœud Kubernetes${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Type           : $NODE_TYPE"
echo "Numéro         : $NODE_NUMBER"
echo "Hostname       : $HOSTNAME"
echo "IP             : $NODE_IP"
echo "Version K8s    : $K8S_VERSION"
echo ""
read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Étape 1 : Configuration système de base
print_step "1" "Configuration système de base"

print_info "Configuration du hostname..."
hostnamectl set-hostname $HOSTNAME

print_info "Configuration de /etc/hosts..."
cat > /etc/hosts <<EOF
127.0.0.1   localhost
$NODE_IP    $HOSTNAME

# Control Planes
${BASE_IP}.10 master1
${BASE_IP}.11 master2
${BASE_IP}.12 master3

# Workers
${BASE_IP}.20 worker1
${BASE_IP}.21 worker2
${BASE_IP}.22 worker3

# Load Balancer
${BASE_IP}.100 lb k8s-api
EOF

print_success "Configuration de base terminée"

# Étape 2 : Désactivation du swap
print_step "2" "Désactivation du swap"

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
print_success "Swap désactivé"

# Étape 3 : Configuration SELinux (si présent)
if [ -f /etc/selinux/config ]; then
    print_step "3" "Configuration SELinux"
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    print_success "SELinux configuré en mode permissive"
fi

# Étape 4 : Désactivation du firewall (pour lab)
print_step "4" "Configuration du firewall"
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
print_info "Firewall désactivé (pour environnement de lab)"

# Étape 5 : Modules kernel
print_step "5" "Configuration des modules kernel"

cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
print_success "Modules kernel chargés"

# Étape 6 : Paramètres sysctl
print_step "6" "Configuration des paramètres sysctl"

cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system > /dev/null
print_success "Paramètres sysctl appliqués"

# Étape 7 : Installation de containerd
print_step "7" "Installation de containerd"

# Détecter la distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

case $OS in
    "ubuntu"|"debian")
        print_info "Installation pour Ubuntu/Debian..."
        apt-get update -qq
        apt-get install -y apt-transport-https ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y containerd.io
        ;;
    "centos"|"rhel"|"almalinux"|"rocky")
        print_info "Installation pour RHEL/CentOS/AlmaLinux..."
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y containerd.io
        ;;
    *)
        print_error "Distribution non supportée: $OS"
        exit 1
        ;;
esac

print_success "Containerd installé"

# Étape 8 : Configuration de containerd
print_step "8" "Configuration de containerd"

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
print_success "Containerd configuré et démarré"

# Étape 9 : Installation de kubeadm, kubelet et kubectl
print_step "9" "Installation de kubeadm, kubelet et kubectl"

case $OS in
    "ubuntu"|"debian")
        print_info "Installation des outils Kubernetes pour Ubuntu/Debian..."
        curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
        apt-get update -qq
        apt-get install -y kubelet kubeadm kubectl
        apt-mark hold kubelet kubeadm kubectl
        ;;
    "centos"|"rhel"|"almalinux"|"rocky")
        print_info "Installation des outils Kubernetes pour RHEL/CentOS/AlmaLinux..."
        cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
        yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        ;;
esac

systemctl enable kubelet
print_success "Outils Kubernetes installés"

# Étape 10 : Vérification finale
print_step "10" "Vérification de l'installation"

echo ""
print_info "Versions installées:"
echo "  - Containerd: $(containerd --version | awk '{print $3}')"
echo "  - kubeadm: $(kubeadm version -o short)"
echo "  - kubelet: $(kubelet --version | awk '{print $2}')"
echo "  - kubectl: $(kubectl version --client -o json | grep gitVersion | cut -d'"' -f4)"
echo ""

print_info "Vérifications:"
echo -n "  - Swap désactivé: "
if [ -z "$(swapon --show)" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo -n "  - Modules kernel: "
if lsmod | grep -q br_netfilter && lsmod | grep -q overlay; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo -n "  - Containerd actif: "
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo -n "  - Kubelet activé: "
if systemctl is-enabled --quiet kubelet; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Résumé
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Installation terminée !${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
print_success "Le nœud $HOSTNAME est prêt pour Kubernetes"
echo ""
print_info "Prochaines étapes:"
if [ "$NODE_TYPE" == "master" ]; then
    echo "  1. Si c'est le premier master, initialisez le cluster:"
    echo "     sudo kubeadm init --control-plane-endpoint=\"lb:6443\" --upload-certs --pod-network-cidr=10.244.0.0/16"
    echo ""
    echo "  2. Si ce n'est pas le premier master, rejoignez le cluster avec:"
    echo "     sudo kubeadm join lb:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <key>"
else
    echo "  1. Rejoignez le cluster avec la commande fournie par 'kubeadm init' sur un master:"
    echo "     sudo kubeadm join lb:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
    echo ""
    echo "  2. Vérifiez l'ajout sur un control plane:"
    echo "     kubectl get nodes"
fi
echo ""
