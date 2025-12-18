#!/bin/bash
# add-worker-node.sh - Script pour ajouter un worker node au cluster Kubernetes
# Usage: ./add-worker-node.sh <worker-ip> <worker-hostname>

set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Variables
WORKER_IP=$1
WORKER_HOSTNAME=$2
SSH_USER=${SSH_USER:-admin}  # Par défaut : admin
TIMEOUT=120

# Vérifier les arguments
if [ -z "$WORKER_IP" ] || [ -z "$WORKER_HOSTNAME" ]; then
    echo "Usage: $0 <worker-ip> <worker-hostname>"
    echo ""
    echo "Exemples:"
    echo "  $0 192.168.1.20 worker1"
    echo "  $0 10.0.1.50 worker-prod-01"
    echo ""
    echo "Variables d'environnement optionnelles:"
    echo "  SSH_USER : Utilisateur SSH (défaut: admin)"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Ajout du worker node au cluster${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Worker IP       : $WORKER_IP"
echo "Worker Hostname : $WORKER_HOSTNAME"
echo "SSH User        : $SSH_USER"
echo ""

# Étape 1 : Vérifier les prérequis
print_step "1" "Vérification des prérequis"

# Vérifier qu'on est sur un control plane
if ! kubectl get nodes &>/dev/null; then
    print_error "Ce script doit être exécuté depuis un control plane avec kubectl configuré"
    exit 1
fi

# Vérifier la connectivité SSH
print_info "Test de connectivité SSH vers $WORKER_IP..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $SSH_USER@$WORKER_IP "exit" 2>/dev/null; then
    print_error "Impossible de se connecter en SSH à $WORKER_IP"
    print_info "Vérifiez que l'authentification par clé SSH est configurée"
    exit 1
fi
print_success "Connectivité SSH OK"

# Vérifier que le nœud n'existe pas déjà
if kubectl get node $WORKER_HOSTNAME &>/dev/null; then
    print_error "Le nœud $WORKER_HOSTNAME existe déjà dans le cluster"
    echo ""
    kubectl get node $WORKER_HOSTNAME
    exit 1
fi

# Étape 2 : Vérifier les prérequis sur le worker
print_step "2" "Vérification des prérequis sur le worker"

print_info "Vérification du hostname..."
REMOTE_HOSTNAME=$(ssh $SSH_USER@$WORKER_IP "hostname")
if [ "$REMOTE_HOSTNAME" != "$WORKER_HOSTNAME" ]; then
    print_error "Le hostname distant ($REMOTE_HOSTNAME) ne correspond pas à $WORKER_HOSTNAME"
    print_info "Configurez le hostname avec: sudo hostnamectl set-hostname $WORKER_HOSTNAME"
    exit 1
fi

print_info "Vérification que kubeadm est installé..."
if ! ssh $SSH_USER@$WORKER_IP "which kubeadm" &>/dev/null; then
    print_error "kubeadm n'est pas installé sur $WORKER_IP"
    print_info "Installez les composants Kubernetes avant de continuer"
    exit 1
fi

print_info "Vérification que kubelet est actif..."
if ! ssh $SSH_USER@$WORKER_IP "systemctl is-enabled kubelet" &>/dev/null; then
    print_error "kubelet n'est pas activé sur $WORKER_IP"
    exit 1
fi

print_info "Vérification que le swap est désactivé..."
if ssh $SSH_USER@$WORKER_IP "swapon --show" 2>/dev/null | grep -q "/"; then
    print_error "Le swap est actif sur $WORKER_IP"
    print_info "Désactivez le swap avec: sudo swapoff -a"
    exit 1
fi

print_success "Tous les prérequis sont satisfaits"

# Étape 3 : Générer la commande de join
print_step "3" "Génération du token et de la commande de join"

JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
if [ -z "$JOIN_CMD" ]; then
    print_error "Impossible de générer la commande de join"
    exit 1
fi

print_info "Commande de join générée:"
echo "  $JOIN_CMD"

# Étape 4 : Rejoindre le cluster
print_step "4" "Rattachement du worker au cluster"

print_info "Exécution de kubeadm join sur $WORKER_IP..."
if ssh $SSH_USER@$WORKER_IP "sudo $JOIN_CMD"; then
    print_success "Le worker a rejoint le cluster avec succès"
else
    print_error "Échec du rattachement du worker"
    exit 1
fi

# Étape 5 : Vérifier que le nœud apparaît dans le cluster
print_step "5" "Vérification de l'ajout du nœud"

print_info "Attente que le nœud apparaisse dans le cluster..."
COUNT=0
while [ $COUNT -lt $TIMEOUT ]; do
    if kubectl get node $WORKER_HOSTNAME &>/dev/null; then
        print_success "Le nœud $WORKER_HOSTNAME est visible dans le cluster"
        break
    fi
    sleep 2
    COUNT=$((COUNT + 2))
done

if [ $COUNT -ge $TIMEOUT ]; then
    print_error "Timeout : le nœud n'apparaît pas dans le cluster"
    exit 1
fi

# Afficher les informations du nœud
echo ""
kubectl get node $WORKER_HOSTNAME

# Étape 6 : Attendre que le nœud soit Ready
print_step "6" "Attente que le nœud soit Ready"

print_info "Attente de l'état Ready (peut prendre 1-2 minutes)..."
COUNT=0
while [ $COUNT -lt $TIMEOUT ]; do
    NODE_STATUS=$(kubectl get node $WORKER_HOSTNAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$NODE_STATUS" == "True" ]; then
        print_success "Le nœud $WORKER_HOSTNAME est Ready"
        break
    fi
    sleep 5
    COUNT=$((COUNT + 5))
    echo -n "."
done
echo ""

if [ $COUNT -ge $TIMEOUT ]; then
    print_error "Le nœud n'est pas passé à l'état Ready dans le temps imparti"
    print_info "Vérifiez les logs avec: kubectl describe node $WORKER_HOSTNAME"
    print_info "Ou sur le nœud: ssh $SSH_USER@$WORKER_IP 'sudo journalctl -u kubelet -n 50'"
    exit 1
fi

# Étape 7 : Labelliser le nœud (optionnel)
print_step "7" "Labellisation du nœud"

# Ajouter le label worker
kubectl label node $WORKER_HOSTNAME node-role.kubernetes.io/worker=worker 2>/dev/null || true
print_info "Label 'worker' ajouté"

# Résumé
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Résumé${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
kubectl get node $WORKER_HOSTNAME -o wide
echo ""
print_success "Le worker $WORKER_HOSTNAME a été ajouté avec succès au cluster !"
echo ""
print_info "Prochaines étapes suggérées:"
echo "  1. Ajouter des labels personnalisés:"
echo "     kubectl label node $WORKER_HOSTNAME environment=production zone=zone-a"
echo ""
echo "  2. Vérifier les pods système sur le nœud:"
echo "     kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=$WORKER_HOSTNAME"
echo ""
echo "  3. Voir tous les nœuds du cluster:"
echo "     kubectl get nodes -o wide"
