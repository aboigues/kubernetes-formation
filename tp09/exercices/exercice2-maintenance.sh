#!/bin/bash
# Exercice 2 : Maintenance planifiée d'un nœud
# Script de test pour effectuer une maintenance sans interruption

set -e

echo "=== Exercice 2 : Maintenance planifiée d'un nœud ==="
echo ""

# Variables
NODE_TO_MAINTAIN="worker2"
NAMESPACE="maintenance-exercise"

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

wait_for_pods() {
    local namespace=$1
    local expected_count=$2
    local timeout=120
    local elapsed=0

    print_info "Attente que $expected_count pods soient Ready..."
    while [ $elapsed -lt $timeout ]; do
        ready_count=$(kubectl get pods -n $namespace -o json | jq '[.items[] | select(.status.phase=="Running")] | length')
        if [ "$ready_count" -eq "$expected_count" ]; then
            print_info "✓ $ready_count pods sont Ready"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    print_error "Timeout : seulement $ready_count/$expected_count pods sont Ready"
    return 1
}

# Étape 1 : Créer le namespace
print_step "1" "Création du namespace et des ressources de test"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Créer une application de test avec PDB
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: $NAMESPACE
spec:
  replicas: 6
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: test-app
  namespace: $NAMESPACE
spec:
  selector:
    app: test-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: test-app-pdb
  namespace: $NAMESPACE
spec:
  minAvailable: 4
  selector:
    matchLabels:
      app: test-app
EOF

print_info "Attente du déploiement..."
kubectl wait --for=condition=available --timeout=120s deployment/test-app -n $NAMESPACE

# Étape 2 : Vérifier l'état initial
print_step "2" "Vérification de l'état initial"
echo ""
kubectl get nodes
echo ""
kubectl get pods -n $NAMESPACE -o wide
echo ""
kubectl get pdb -n $NAMESPACE

# Compter les pods sur le nœud à maintenir
pods_on_node=$(kubectl get pods -n $NAMESPACE -o wide | grep $NODE_TO_MAINTAIN | wc -l)
print_info "Nombre de pods sur $NODE_TO_MAINTAIN : $pods_on_node"

# Étape 3 : Cordon du nœud
print_step "3" "Marquage du nœud $NODE_TO_MAINTAIN comme non-planifiable (cordon)"
kubectl cordon $NODE_TO_MAINTAIN

print_info "Vérification du statut :"
kubectl get nodes | grep $NODE_TO_MAINTAIN

# Étape 4 : Vérifier qu'aucun nouveau pod n'est créé sur ce nœud
print_step "4" "Vérification que les nouveaux pods ne sont pas planifiés sur $NODE_TO_MAINTAIN"
print_info "Scaling à 9 replicas..."
kubectl scale deployment test-app -n $NAMESPACE --replicas=9

sleep 10
new_pods_on_node=$(kubectl get pods -n $NAMESPACE -o wide | grep $NODE_TO_MAINTAIN | wc -l)
print_info "Pods sur $NODE_TO_MAINTAIN après scaling : $new_pods_on_node"

if [ "$new_pods_on_node" -eq "$pods_on_node" ]; then
    print_info "✓ Aucun nouveau pod créé sur $NODE_TO_MAINTAIN (cordon fonctionne)"
else
    print_error "⚠ Des nouveaux pods ont été créés sur $NODE_TO_MAINTAIN"
fi

echo ""
kubectl get pods -n $NAMESPACE -o wide

# Étape 5 : Drain du nœud
print_step "5" "Évacuation des pods de $NODE_TO_MAINTAIN (drain)"
print_info "Le drain respectera le PodDisruptionBudget (minAvailable: 4)"

kubectl drain $NODE_TO_MAINTAIN --ignore-daemonsets --delete-emptydir-data --timeout=3m

# Étape 6 : Vérifier l'évacuation
print_step "6" "Vérification de l'évacuation"
remaining_pods=$(kubectl get pods -n $NAMESPACE -o wide 2>/dev/null | grep $NODE_TO_MAINTAIN | grep -v DaemonSet | wc -l)

if [ "$remaining_pods" -eq 0 ]; then
    print_info "✓ Tous les pods ont été évacués de $NODE_TO_MAINTAIN"
else
    print_error "⚠ Il reste $remaining_pods pods sur $NODE_TO_MAINTAIN"
fi

echo ""
kubectl get pods -n $NAMESPACE -o wide
echo ""

# Vérifier que le minimum est respecté
ready_pods=$(kubectl get pods -n $NAMESPACE -o json | jq '[.items[] | select(.status.phase=="Running")] | length')
print_info "Pods Ready actuellement : $ready_pods (minimum requis par PDB : 4)"

# Étape 7 : Simuler la maintenance
print_step "7" "Simulation de la maintenance (60 secondes)"
for i in {60..1}; do
    printf "\r${YELLOW}[INFO]${NC} Maintenance en cours... $i secondes restantes "
    sleep 1
done
echo ""
print_info "✓ Maintenance terminée"

# Étape 8 : Réactiver le nœud
print_step "8" "Réactivation du nœud $NODE_TO_MAINTAIN (uncordon)"
kubectl uncordon $NODE_TO_MAINTAIN

print_info "Vérification du statut :"
kubectl get nodes | grep $NODE_TO_MAINTAIN

# Étape 9 : Vérifier la redistribution
print_step "9" "Vérification de la redistribution des pods"
sleep 15

echo ""
kubectl get pods -n $NAMESPACE -o wide
echo ""

pods_after=$(kubectl get pods -n $NAMESPACE -o wide | grep $NODE_TO_MAINTAIN | wc -l)
print_info "Pods maintenant sur $NODE_TO_MAINTAIN : $pods_after"

# Étape 10 : Résumé
print_step "10" "Résumé de la maintenance"
echo ""
echo "=== RÉSUMÉ ==="
echo "Nœud maintenu         : $NODE_TO_MAINTAIN"
echo "Pods avant drain      : $pods_on_node"
echo "Pods après uncordon   : $pods_after"
echo "Pods Ready total      : $(kubectl get pods -n $NAMESPACE -o json | jq '[.items[] | select(.status.phase=="Running")] | length')"
echo "PDB respecté          : ✓"
echo ""

# Étape 11 : Nettoyage (optionnel)
echo ""
read -p "Voulez-vous nettoyer les ressources de test ? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "11" "Nettoyage des ressources"
    kubectl delete namespace $NAMESPACE
    print_info "✓ Namespace $NAMESPACE supprimé"
else
    print_info "Ressources conservées dans le namespace $NAMESPACE"
    print_info "Pour nettoyer manuellement : kubectl delete namespace $NAMESPACE"
fi

echo ""
echo "=== EXERCICE TERMINÉ ==="
echo ""
print_info "Points clés à retenir :"
echo "  1. Toujours utiliser 'cordon' avant 'drain'"
echo "  2. Les PodDisruptionBudgets protègent contre les évacuations trop rapides"
echo "  3. Le flag --ignore-daemonsets est nécessaire (les DaemonSets ne sont pas évacuables)"
echo "  4. Penser à 'uncordon' après la maintenance"
echo "  5. Vérifier la redistribution des pods après réactivation"
