#!/bin/bash

# Script de test automatisé pour le TP2 - Maîtriser les Manifests Kubernetes
# Ce script teste la création et la gestion de différentes ressources Kubernetes

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire temporaire pour les manifests de test
TEST_DIR="/tmp/tp2-tests"

# Fonction pour afficher les messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl n'est pas installé"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi

    # Créer le répertoire de test
    mkdir -p "$TEST_DIR"

    log_success "Prérequis OK"
    echo ""
}

# Fonction pour nettoyer les ressources de test
cleanup() {
    log_info "Nettoyage des ressources de test..."

    # Supprimer les pods
    kubectl delete pod nginx-pod webapp-pod multi-container-pod test-pod --ignore-not-found=true 2>/dev/null || true

    # Supprimer les déploiements
    kubectl delete deployment nginx-deployment webapp-deployment frontend-deployment --ignore-not-found=true 2>/dev/null || true

    # Supprimer les services
    kubectl delete service nginx-service webapp-service frontend-service backend-service --ignore-not-found=true 2>/dev/null || true

    # Supprimer les ConfigMaps
    kubectl delete configmap app-config nginx-config webapp-config --ignore-not-found=true 2>/dev/null || true

    # Supprimer les Secrets
    kubectl delete secret db-credentials app-secrets api-keys --ignore-not-found=true 2>/dev/null || true

    # Supprimer les namespaces de test
    kubectl delete namespace dev-ns prod-ns test-namespace --ignore-not-found=true 2>/dev/null || true

    # Nettoyer le répertoire de test
    rm -rf "$TEST_DIR"

    log_success "Nettoyage terminé"
    echo ""
}

# Test 1: Créer un Pod simple
test_simple_pod() {
    log_info "Test 1: Création d'un Pod simple..."

    # Créer un manifest de Pod simple
    cat > "$TEST_DIR/simple-pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
    env: test
spec:
  containers:
  - name: nginx
    image: nginx:1.24
    ports:
    - containerPort: 80
EOF

    # Valider le manifest (dry-run)
    if ! kubectl apply -f "$TEST_DIR/simple-pod.yaml" --dry-run=client &> /dev/null; then
        log_error "Test 1 FAILED: Validation du manifest échouée"
        return 1
    fi

    # Créer le pod
    kubectl apply -f "$TEST_DIR/simple-pod.yaml"

    # Attendre que le pod soit prêt
    log_info "Attente du pod nginx-pod..."
    kubectl wait --for=condition=ready --timeout=60s pod/nginx-pod

    # Vérifier le pod
    if kubectl get pod nginx-pod &> /dev/null; then
        STATUS=$(kubectl get pod nginx-pod -o jsonpath='{.status.phase}')
        if [ "$STATUS" = "Running" ]; then
            log_success "Test 1 OK: Pod simple créé et en état Running"
        else
            log_error "Test 1 FAILED: Pod en état $STATUS au lieu de Running"
            return 1
        fi
    else
        log_error "Test 1 FAILED: Pod non trouvé"
        return 1
    fi
    echo ""
}

# Test 2: Pod avec ressources limitées
test_pod_with_resources() {
    log_info "Test 2: Pod avec contraintes de ressources..."

    cat > "$TEST_DIR/pod-resources.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: webapp-pod
  labels:
    app: webapp
spec:
  containers:
  - name: webapp
    image: httpd:2.4
    ports:
    - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
EOF

    kubectl apply -f "$TEST_DIR/pod-resources.yaml"
    kubectl wait --for=condition=ready --timeout=60s pod/webapp-pod

    # Vérifier les ressources
    CPU_REQUEST=$(kubectl get pod webapp-pod -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
    MEM_LIMIT=$(kubectl get pod webapp-pod -o jsonpath='{.spec.containers[0].resources.limits.memory}')

    if [ "$CPU_REQUEST" = "250m" ] && [ "$MEM_LIMIT" = "128Mi" ]; then
        log_success "Test 2 OK: Pod créé avec contraintes de ressources (CPU: $CPU_REQUEST, Mem limit: $MEM_LIMIT)"
    else
        log_error "Test 2 FAILED: Ressources incorrectes (CPU: $CPU_REQUEST, Mem: $MEM_LIMIT)"
        return 1
    fi
    echo ""
}

# Test 3: Pod multi-conteneurs
test_multi_container_pod() {
    log_info "Test 3: Pod multi-conteneurs..."

    cat > "$TEST_DIR/multi-container.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.24-alpine
    ports:
    - containerPort: 80
  - name: sidecar
    image: busybox
    command: ['sh', '-c', 'while true; do echo "Sidecar running"; sleep 30; done']
EOF

    kubectl apply -f "$TEST_DIR/multi-container.yaml"
    kubectl wait --for=condition=ready --timeout=60s pod/multi-container-pod

    # Vérifier le nombre de conteneurs
    CONTAINER_COUNT=$(kubectl get pod multi-container-pod -o jsonpath='{.spec.containers[*].name}' | wc -w)

    if [ "$CONTAINER_COUNT" = "2" ]; then
        log_success "Test 3 OK: Pod multi-conteneurs créé avec $CONTAINER_COUNT conteneurs"
    else
        log_error "Test 3 FAILED: $CONTAINER_COUNT conteneurs au lieu de 2"
        return 1
    fi
    echo ""
}

# Test 4: Créer un Deployment
test_deployment() {
    log_info "Test 4: Création d'un Deployment..."

    cat > "$TEST_DIR/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        ports:
        - containerPort: 80
EOF

    kubectl apply -f "$TEST_DIR/deployment.yaml"

    log_info "Attente du déploiement..."
    kubectl wait --for=condition=available --timeout=90s deployment/nginx-deployment

    READY_REPLICAS=$(kubectl get deployment nginx-deployment -o jsonpath='{.status.readyReplicas}')

    if [ "$READY_REPLICAS" = "3" ]; then
        log_success "Test 4 OK: Deployment créé avec 3/3 replicas prêts"
    else
        log_error "Test 4 FAILED: $READY_REPLICAS/3 replicas prêts"
        return 1
    fi
    echo ""
}

# Test 5: Service ClusterIP
test_service_clusterip() {
    log_info "Test 5: Création d'un Service ClusterIP..."

    cat > "$TEST_DIR/service-clusterip.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
EOF

    kubectl apply -f "$TEST_DIR/service-clusterip.yaml"
    sleep 2

    SERVICE_TYPE=$(kubectl get service nginx-service -o jsonpath='{.spec.type}')
    ENDPOINTS=$(kubectl get endpoints nginx-service -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)

    if [ "$SERVICE_TYPE" = "ClusterIP" ] && [ "$ENDPOINTS" -ge "1" ]; then
        log_success "Test 5 OK: Service ClusterIP créé avec $ENDPOINTS endpoints"
    else
        log_error "Test 5 FAILED: Type=$SERVICE_TYPE, Endpoints=$ENDPOINTS"
        return 1
    fi
    echo ""
}

# Test 6: ConfigMap
test_configmap() {
    log_info "Test 6: Création et utilisation de ConfigMap..."

    # Créer un ConfigMap
    kubectl create configmap app-config \
        --from-literal=APP_ENV=production \
        --from-literal=APP_DEBUG=false \
        --from-literal=LOG_LEVEL=info

    # Vérifier le ConfigMap
    if kubectl get configmap app-config &> /dev/null; then
        DATA_COUNT=$(kubectl get configmap app-config -o jsonpath='{.data}' | grep -o ':' | wc -l)
        if [ "$DATA_COUNT" -ge "3" ]; then
            log_success "Test 6a OK: ConfigMap créé avec des données"
        else
            log_error "Test 6a FAILED: ConfigMap incomplet"
            return 1
        fi
    else
        log_error "Test 6a FAILED: ConfigMap non créé"
        return 1
    fi

    # Créer un pod qui utilise le ConfigMap
    cat > "$TEST_DIR/pod-with-configmap.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test
    image: busybox
    command: ['sh', '-c', 'env && sleep 3600']
    envFrom:
    - configMapRef:
        name: app-config
EOF

    kubectl apply -f "$TEST_DIR/pod-with-configmap.yaml"
    kubectl wait --for=condition=ready --timeout=60s pod/test-pod

    # Vérifier que les variables sont injectées
    if kubectl exec test-pod -- env | grep -q "APP_ENV=production"; then
        log_success "Test 6b OK: ConfigMap injecté dans le pod comme variables d'environnement"
    else
        log_error "Test 6b FAILED: Variables d'environnement non injectées"
        return 1
    fi
    echo ""
}

# Test 7: Secret
test_secret() {
    log_info "Test 7: Création et utilisation de Secret..."

    # Créer un Secret
    kubectl create secret generic db-credentials \
        --from-literal=username=admin \
        --from-literal=password=secret123

    # Vérifier le Secret
    if kubectl get secret db-credentials &> /dev/null; then
        log_success "Test 7a OK: Secret créé"
    else
        log_error "Test 7a FAILED: Secret non créé"
        return 1
    fi

    # Créer un manifest avec Secret
    cat > "$TEST_DIR/deployment-with-secret.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: nginx:alpine
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
EOF

    kubectl apply -f "$TEST_DIR/deployment-with-secret.yaml"
    kubectl wait --for=condition=available --timeout=60s deployment/webapp-deployment

    # Vérifier que le secret est utilisé
    POD_NAME=$(kubectl get pods -l app=webapp -o jsonpath='{.items[0].metadata.name}')
    if kubectl exec "$POD_NAME" -- env | grep -q "DB_USER=admin"; then
        log_success "Test 7b OK: Secret injecté dans le déploiement"
    else
        log_error "Test 7b FAILED: Secret non injecté"
        return 1
    fi
    echo ""
}

# Test 8: Labels et Selectors
test_labels_selectors() {
    log_info "Test 8: Labels et Selectors..."

    # Créer plusieurs pods avec différents labels
    kubectl run pod-dev --image=nginx:alpine --labels="app=myapp,env=dev"
    kubectl run pod-prod --image=nginx:alpine --labels="app=myapp,env=prod"
    kubectl run pod-other --image=nginx:alpine --labels="app=other,env=dev"

    sleep 5  # Attendre que les pods démarrent

    # Tester les sélecteurs
    MYAPP_COUNT=$(kubectl get pods -l app=myapp --no-headers 2>/dev/null | wc -l)
    DEV_COUNT=$(kubectl get pods -l env=dev --no-headers 2>/dev/null | wc -l)
    MYAPP_DEV_COUNT=$(kubectl get pods -l "app=myapp,env=dev" --no-headers 2>/dev/null | wc -l)

    if [ "$MYAPP_COUNT" = "2" ] && [ "$DEV_COUNT" = "2" ] && [ "$MYAPP_DEV_COUNT" = "1" ]; then
        log_success "Test 8 OK: Sélecteurs de labels fonctionnent (app=myapp: $MYAPP_COUNT, env=dev: $DEV_COUNT, combiné: $MYAPP_DEV_COUNT)"
    else
        log_warning "Test 8 WARNING: Sélecteurs inattendus (app=myapp: $MYAPP_COUNT, env=dev: $DEV_COUNT, combiné: $MYAPP_DEV_COUNT)"
    fi

    # Nettoyer les pods de test
    kubectl delete pod pod-dev pod-prod pod-other --ignore-not-found=true

    echo ""
}

# Test 9: Namespaces
test_namespaces() {
    log_info "Test 9: Namespaces..."

    # Créer des namespaces
    kubectl create namespace dev-ns
    kubectl create namespace prod-ns

    # Vérifier les namespaces
    if kubectl get namespace dev-ns &> /dev/null && kubectl get namespace prod-ns &> /dev/null; then
        log_success "Test 9a OK: Namespaces créés"
    else
        log_error "Test 9a FAILED: Namespaces non créés"
        return 1
    fi

    # Créer des ressources dans différents namespaces
    kubectl create deployment nginx-dev --image=nginx:alpine --namespace=dev-ns
    kubectl create deployment nginx-prod --image=nginx:alpine --namespace=prod-ns

    # Vérifier l'isolation
    DEV_DEPLOYMENTS=$(kubectl get deployments -n dev-ns --no-headers | wc -l)
    PROD_DEPLOYMENTS=$(kubectl get deployments -n prod-ns --no-headers | wc -l)

    if [ "$DEV_DEPLOYMENTS" = "1" ] && [ "$PROD_DEPLOYMENTS" = "1" ]; then
        log_success "Test 9b OK: Ressources isolées par namespace (dev: $DEV_DEPLOYMENTS, prod: $PROD_DEPLOYMENTS)"
    else
        log_error "Test 9b FAILED: Problème d'isolation (dev: $DEV_DEPLOYMENTS, prod: $PROD_DEPLOYMENTS)"
        return 1
    fi
    echo ""
}

# Test 10: Validation YAML
test_yaml_validation() {
    log_info "Test 10: Validation de manifests YAML..."

    # Créer un manifest valide
    cat > "$TEST_DIR/valid.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: valid-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: valid
  template:
    metadata:
      labels:
        app: valid
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
EOF

    # Créer un manifest invalide (manque selector)
    cat > "$TEST_DIR/invalid.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: invalid-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: invalid
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
EOF

    # Tester la validation du manifest valide
    if kubectl apply -f "$TEST_DIR/valid.yaml" --dry-run=client &> /dev/null; then
        log_success "Test 10a OK: Manifest valide accepté"
    else
        log_error "Test 10a FAILED: Manifest valide rejeté"
        return 1
    fi

    # Tester la validation du manifest invalide
    if ! kubectl apply -f "$TEST_DIR/invalid.yaml" --dry-run=client &> /dev/null; then
        log_success "Test 10b OK: Manifest invalide rejeté correctement"
    else
        log_warning "Test 10b WARNING: Manifest invalide accepté (peut varier selon la version de kubectl)"
    fi

    echo ""
}

# Fonction principale
main() {
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "   TESTS AUTOMATISÉS TP2 - Maîtriser les Manifests K8s   "
    log_info "═══════════════════════════════════════════════════════════"
    echo ""

    # Nettoyage initial
    cleanup

    # Vérifier les prérequis
    check_prerequisites

    # Compteur de tests
    TESTS_PASSED=0
    TESTS_FAILED=0

    # Exécuter les tests
    if test_simple_pod; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_pod_with_resources; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_multi_container_pod; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_deployment; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_service_clusterip; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_configmap; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_secret; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_labels_selectors; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_namespaces; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_yaml_validation; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi

    # Nettoyage final
    cleanup

    # Résumé des tests
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "                    RÉSUMÉ DES TESTS                       "
    log_info "═══════════════════════════════════════════════════════════"
    log_success "Tests réussis: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "Tests échoués: $TESTS_FAILED"
    else
        log_info "Tests échoués: $TESTS_FAILED"
    fi
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "✓ TOUS LES TESTS SONT PASSÉS !"
        echo ""
        return 0
    else
        log_error "✗ CERTAINS TESTS ONT ÉCHOUÉ"
        echo ""
        return 1
    fi
}

# Trap pour nettoyer en cas d'interruption
trap cleanup EXIT

# Exécuter les tests
main
