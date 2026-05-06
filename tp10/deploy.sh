#!/bin/bash

# Script de déploiement rapide du TP10 - Projet de Synthèse TaskFlow
# Déploie tous les composants dans le bon ordre

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TP10 - Déploiement TaskFlow${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

NAMESPACE="taskflow"

# Vérifier que l'image backend est construite
echo -e "${YELLOW}[0/8] Vérification de l'image Docker backend${NC}"
eval $(minikube docker-env)
if ! docker images | grep -q "taskflow-backend"; then
    echo -e "${YELLOW}⚠️  L'image taskflow-backend n'est pas trouvée${NC}"
    echo -e "${YELLOW}   Construction de l'image en cours...${NC}"
    ./build-image.sh
    if [ $? -ne 0 ]; then
        echo "❌ Erreur lors de la construction de l'image backend"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Image taskflow-backend:latest trouvée${NC}"
fi
echo ""

# Créer le namespace
echo -e "${YELLOW}[1/8] Création du namespace $NAMESPACE${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo ""

# Déployer PostgreSQL (avec initContainer)
echo -e "${YELLOW}[2/8] Déploiement de PostgreSQL avec initContainer${NC}"
kubectl apply -f 01-postgres-init-script.yaml
kubectl apply -f 02-postgres-secret.yaml
kubectl apply -f 03-postgres-pvc.yaml
kubectl apply -f 04-postgres-deployment.yaml
kubectl apply -f 05-postgres-service.yaml
echo "Attente que PostgreSQL soit prêt..."
kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=300s
echo ""

# Déployer Redis
echo -e "${YELLOW}[3/8] Déploiement de Redis${NC}"
kubectl apply -f 06-redis-deployment.yaml
kubectl apply -f 07-redis-service.yaml
kubectl wait --for=condition=ready pod -l app=redis -n $NAMESPACE --timeout=120s
echo ""

# Déployer Backend API
echo -e "${YELLOW}[4/8] Déploiement du Backend API${NC}"
kubectl apply -f 08-backend-config.yaml
kubectl apply -f 09a-backend-app-code.yaml
kubectl apply -f 09b-backend-deployment.yaml
kubectl apply -f 10-backend-service.yaml
kubectl apply -f 11-backend-hpa.yaml
echo "Attente que le Backend soit prêt..."
kubectl wait --for=condition=ready pod -l app=backend-api -n $NAMESPACE --timeout=300s
echo ""

# Déployer Frontend
echo -e "${YELLOW}[5/8] Déploiement du Frontend${NC}"
kubectl apply -f 12b-frontend-nginx-config.yaml
kubectl apply -f 12a-frontend-config.yaml
kubectl apply -f 13-frontend-deployment.yaml
kubectl apply -f 14-frontend-service.yaml
kubectl wait --for=condition=ready pod -l app=frontend -n $NAMESPACE --timeout=120s
echo ""

# Déployer Prometheus
echo -e "${YELLOW}[6/8] Déploiement de Prometheus${NC}"
kubectl apply -f 15-prometheus-config.yaml
kubectl apply -f 16-prometheus-rbac.yaml
kubectl apply -f 17-prometheus-pvc.yaml
kubectl apply -f 18-prometheus-deployment.yaml
kubectl apply -f 19-prometheus-service.yaml
echo "Attente que Prometheus soit prêt..."
kubectl wait --for=condition=ready pod -l app=prometheus -n $NAMESPACE --timeout=300s
echo ""

# Déployer Grafana
echo -e "${YELLOW}[7/8] Déploiement de Grafana${NC}"
kubectl apply -f 20a-grafana-datasource.yaml
kubectl apply -f 24-grafana-dashboard-configmap.yaml
kubectl apply -f 25-grafana-dashboard-provider.yaml
kubectl apply -f 20b-grafana-deployment.yaml
kubectl apply -f 21-grafana-service.yaml
kubectl wait --for=condition=ready pod -l app=grafana -n $NAMESPACE --timeout=120s
echo ""

# Afficher l'état final
echo -e "${YELLOW}[8/8] Vérification du déploiement${NC}"
echo ""
kubectl get all -n $NAMESPACE
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Déploiement terminé avec succès !${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}Informations de connexion :${NC}"
echo ""

# Frontend
echo -e "${YELLOW}Frontend :${NC}"
if command -v minikube &> /dev/null; then
    echo "  minikube service frontend -n $NAMESPACE"
else
    FRONTEND_PORT=$(kubectl get svc frontend -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    echo "  http://<NODE-IP>:$FRONTEND_PORT"
fi
echo ""

# Grafana
echo -e "${YELLOW}Grafana (monitoring) :${NC}"
if command -v minikube &> /dev/null; then
    echo "  minikube service grafana -n $NAMESPACE"
else
    GRAFANA_PORT=$(kubectl get svc grafana -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    echo "  http://<NODE-IP>:$GRAFANA_PORT"
fi
echo "  Username: admin"
echo "  Password: admin2024"
echo ""

# HPA
echo -e "${YELLOW}HorizontalPodAutoscaler :${NC}"
kubectl get hpa -n $NAMESPACE 2>/dev/null || echo "  En attente de métriques..."
echo ""

echo -e "${BLUE}Prochaines étapes :${NC}"
echo "1. Vérifier que PostgreSQL contient 1000 tâches :"
echo "   kubectl exec -n $NAMESPACE deployment/postgres -- psql -U taskflow -d taskflow_db -c 'SELECT COUNT(*) FROM tasks;'"
echo ""
echo "2. Tester l'API Backend :"
echo "   kubectl port-forward -n $NAMESPACE svc/backend-api 5000:5000"
echo "   curl http://localhost:5000/stats"
echo ""
echo "3. Lancer le générateur de charge pour tester l'autoscaling :"
echo "   kubectl apply -f 22-load-generator.yaml"
echo ""
echo "4. Observer l'autoscaling en temps réel :"
echo "   watch kubectl get hpa,pods -n $NAMESPACE"
echo ""
echo "5. Exécuter le script de test :"
echo "   ./test-tp10.sh"
echo ""
