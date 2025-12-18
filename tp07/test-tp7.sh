#!/bin/bash

# Script de test E2E pour le TP7 - Migration Docker Compose vers Kubernetes
# Ce script teste le déploiement complet de l'application (Frontend, Backend, Database)

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire des manifests
MANIFEST_DIR="$(dirname "$0")/kubernetes-manifests"

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

    # Vérifier que le répertoire de manifests existe
    if [ ! -d "$MANIFEST_DIR" ]; then
        log_error "Répertoire de manifests non trouvé: $MANIFEST_DIR"
        exit 1
    fi

    log_success "Prérequis OK"
    echo ""
}

# Fonction pour nettoyer les ressources de test
cleanup() {
    log_info "Nettoyage des ressources de test..."

    # Supprimer les ressources dans l'ordre inverse
    kubectl delete -f "$MANIFEST_DIR/12-network-policies.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/11-backend-hpa.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/10-frontend-service.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/09-frontend-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/08-frontend-config.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/07-backend-service.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/06-backend-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/06-backend-code.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/05-database-service.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/04-database-deployment.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/03-database-pvc.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/02-backend-config.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/01-database-secret.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete -f "$MANIFEST_DIR/00-namespace.yaml" --ignore-not-found=true 2>/dev/null || true

    # Attendre que les ressources soient supprimées
    sleep 5

    log_success "Nettoyage terminé"
    echo ""
}

# Test 1: Déployer le namespace
test_namespace() {
    log_info "Test 1: Création du namespace..."

    kubectl apply -f "$MANIFEST_DIR/00-namespace.yaml"
    sleep 2

    if kubectl get namespace web-app &> /dev/null; then
        log_success "Test 1 OK: Namespace 'web-app' créé"
    else
        log_error "Test 1 FAILED: Namespace non créé"
        return 1
    fi
    echo ""
}

# Test 2: Déployer les secrets et configmaps
test_config() {
    log_info "Test 2: Création des Secrets et ConfigMaps..."

    # Secret de la base de données
    kubectl apply -f "$MANIFEST_DIR/01-database-secret.yaml"

    # ConfigMap du backend
    kubectl apply -f "$MANIFEST_DIR/02-backend-config.yaml"

    # ConfigMap du frontend
    if [ -f "$MANIFEST_DIR/08-frontend-config.yaml" ]; then
        kubectl apply -f "$MANIFEST_DIR/08-frontend-config.yaml"
    fi

    sleep 2

    # Vérifier les ressources
    if kubectl get secret -n web-app db-credentials &> /dev/null && \
       kubectl get configmap -n web-app backend-config &> /dev/null; then
        log_success "Test 2 OK: Secrets et ConfigMaps créés"
    else
        log_error "Test 2 FAILED: Problème avec les Secrets/ConfigMaps"
        return 1
    fi
    echo ""
}

# Test 3: Déployer la base de données
test_database() {
    log_info "Test 3: Déploiement de la base de données..."

    # PVC
    kubectl apply -f "$MANIFEST_DIR/03-database-pvc.yaml"
    sleep 2

    # Vérifier le PVC
    PVC_STATUS=$(kubectl get pvc -n web-app postgres-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$PVC_STATUS" != "Bound" ] && [ "$PVC_STATUS" != "Pending" ]; then
        log_warning "PVC en état: $PVC_STATUS"
    else
        log_success "PVC créé (statut: $PVC_STATUS)"
    fi

    # Deployment de la base de données
    kubectl apply -f "$MANIFEST_DIR/04-database-deployment.yaml"
    kubectl apply -f "$MANIFEST_DIR/05-database-service.yaml"

    # Attendre que la base de données soit prête
    log_info "Attente du démarrage de la base de données (peut prendre 1-2 minutes)..."
    if kubectl wait --for=condition=available --timeout=180s deployment/postgres -n web-app; then
        log_success "Test 3 OK: Base de données déployée et prête"
    else
        log_error "Test 3 FAILED: Base de données non prête"
        kubectl get pods -n web-app -l app=postgres
        return 1
    fi
    echo ""
}

# Test 4: Déployer le backend
test_backend() {
    log_info "Test 4: Déploiement du backend..."

    # ConfigMap avec le code du backend
    if [ -f "$MANIFEST_DIR/06-backend-code.yaml" ]; then
        kubectl apply -f "$MANIFEST_DIR/06-backend-code.yaml"
    fi

    # Deployment du backend
    kubectl apply -f "$MANIFEST_DIR/06-backend-deployment.yaml"
    kubectl apply -f "$MANIFEST_DIR/07-backend-service.yaml"

    # Attendre que le backend soit prêt
    log_info "Attente du démarrage du backend..."
    if kubectl wait --for=condition=available --timeout=120s deployment/backend -n web-app; then
        log_success "Test 4 OK: Backend déployé et prêt"
    else
        log_error "Test 4 FAILED: Backend non prêt"
        kubectl get pods -n web-app -l app=backend
        return 1
    fi
    echo ""
}

# Test 5: Déployer le frontend
test_frontend() {
    log_info "Test 5: Déploiement du frontend..."

    # Deployment du frontend
    kubectl apply -f "$MANIFEST_DIR/09-frontend-deployment.yaml"
    kubectl apply -f "$MANIFEST_DIR/10-frontend-service.yaml"

    # Attendre que le frontend soit prêt
    log_info "Attente du démarrage du frontend..."
    if kubectl wait --for=condition=available --timeout=120s deployment/frontend -n web-app; then
        log_success "Test 5 OK: Frontend déployé et prêt"
    else
        log_error "Test 5 FAILED: Frontend non prêt"
        kubectl get pods -n web-app -l app=frontend
        return 1
    fi
    echo ""
}

# Test 6: Vérifier la connectivité backend -> database
test_backend_db_connectivity() {
    log_info "Test 6: Test de connectivité Backend -> Database..."

    # Récupérer le nom d'un pod backend
    BACKEND_POD=$(kubectl get pods -n web-app -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$BACKEND_POD" ]; then
        log_error "Test 6 FAILED: Aucun pod backend trouvé"
        return 1
    fi

    # Tester la résolution DNS de postgres
    if kubectl exec -n web-app "$BACKEND_POD" -- sh -c "getent hosts postgres" &> /dev/null; then
        log_success "Test 6a OK: Backend peut résoudre le service 'postgres'"
    else
        log_warning "Test 6a WARNING: Résolution DNS de 'postgres' échouée"
    fi

    # Vérifier que les variables d'environnement sont injectées
    if kubectl exec -n web-app "$BACKEND_POD" -- env | grep -q "DATABASE_HOST"; then
        DB_HOST=$(kubectl exec -n web-app "$BACKEND_POD" -- env | grep "DATABASE_HOST" | cut -d'=' -f2)
        log_success "Test 6b OK: Variables d'environnement DB injectées (DATABASE_HOST=$DB_HOST)"
    else
        log_error "Test 6b FAILED: Variables d'environnement DB non injectées"
        return 1
    fi

    echo ""
}

# Test 7: Vérifier la connectivité frontend -> backend
test_frontend_backend_connectivity() {
    log_info "Test 7: Test de connectivité Frontend -> Backend..."

    # Récupérer le nom d'un pod frontend
    FRONTEND_POD=$(kubectl get pods -n web-app -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$FRONTEND_POD" ]; then
        log_error "Test 7 FAILED: Aucun pod frontend trouvé"
        return 1
    fi

    # Tester la résolution DNS de backend
    if kubectl exec -n web-app "$FRONTEND_POD" -- sh -c "getent hosts backend" &> /dev/null; then
        log_success "Test 7a OK: Frontend peut résoudre le service 'backend'"
    else
        log_warning "Test 7a WARNING: Résolution DNS de 'backend' échouée (peut être normal selon l'image)"
    fi

    # Vérifier que le service backend est accessible
    BACKEND_SERVICE=$(kubectl get service -n web-app backend -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$BACKEND_SERVICE" ]; then
        log_success "Test 7b OK: Service backend accessible (ClusterIP: $BACKEND_SERVICE)"
    else
        log_error "Test 7b FAILED: Service backend non trouvé"
        return 1
    fi

    echo ""
}

# Test 8: Vérifier les services
test_services() {
    log_info "Test 8: Vérification des services..."

    # Liste des services attendus
    SERVICES=("postgres" "backend" "frontend")
    ALL_OK=true

    for SERVICE in "${SERVICES[@]}"; do
        if kubectl get service -n web-app "$SERVICE" &> /dev/null; then
            ENDPOINTS=$(kubectl get endpoints -n web-app "$SERVICE" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | wc -w)
            if [ "$ENDPOINTS" -gt "0" ]; then
                log_success "Service '$SERVICE' OK ($ENDPOINTS endpoints)"
            else
                log_warning "Service '$SERVICE' n'a pas d'endpoints"
                ALL_OK=false
            fi
        else
            log_error "Service '$SERVICE' non trouvé"
            ALL_OK=false
        fi
    done

    if [ "$ALL_OK" = true ]; then
        log_success "Test 8 OK: Tous les services sont opérationnels"
    else
        log_error "Test 8 FAILED: Problème avec certains services"
        return 1
    fi
    echo ""
}

# Test 9: Vérifier la persistence de la base de données
test_database_persistence() {
    log_info "Test 9: Test de persistence de la base de données..."

    # Vérifier que le PVC est bien monté
    POSTGRES_POD=$(kubectl get pods -n web-app -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$POSTGRES_POD" ]; then
        log_error "Test 9 FAILED: Aucun pod postgres trouvé"
        return 1
    fi

    # Vérifier les volumes montés
    VOLUMES=$(kubectl get pod -n web-app "$POSTGRES_POD" -o jsonpath='{.spec.volumes[*].name}' 2>/dev/null)

    if echo "$VOLUMES" | grep -q "postgres-storage"; then
        log_success "Test 9 OK: Volume persistent monté sur le pod postgres"
    else
        log_warning "Test 9 WARNING: Volume 'postgres-storage' non trouvé (peut avoir un nom différent)"
    fi

    echo ""
}

# Test 10: Déployer les configurations avancées (optionnel)
test_advanced_config() {
    log_info "Test 10: Déploiement des configurations avancées..."

    # HPA (si disponible)
    if [ -f "$MANIFEST_DIR/11-backend-hpa.yaml" ]; then
        if kubectl apply -f "$MANIFEST_DIR/11-backend-hpa.yaml" 2>/dev/null; then
            # Vérifier que metrics-server est disponible
            if kubectl get hpa -n web-app backend-hpa &> /dev/null; then
                log_success "Test 10a OK: HPA créé (nécessite metrics-server)"
            else
                log_warning "Test 10a WARNING: HPA créé mais peut nécessiter metrics-server"
            fi
        else
            log_warning "Test 10a WARNING: HPA non créé (metrics-server peut-être absent)"
        fi
    fi

    # Network Policies (si disponibles)
    if [ -f "$MANIFEST_DIR/12-network-policies.yaml" ]; then
        if kubectl apply -f "$MANIFEST_DIR/12-network-policies.yaml" 2>/dev/null; then
            log_success "Test 10b OK: NetworkPolicies créées"
        else
            log_warning "Test 10b WARNING: NetworkPolicies non créées (CNI peut ne pas les supporter)"
        fi
    fi

    echo ""
}

# Test 11: Vérifier l'état global de l'application
test_overall_health() {
    log_info "Test 11: Vérification de l'état global de l'application..."

    # Compter les pods en état Running
    TOTAL_PODS=$(kubectl get pods -n web-app --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(kubectl get pods -n web-app --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    log_info "Pods: $RUNNING_PODS/$TOTAL_PODS en état Running"

    # Afficher un résumé
    echo ""
    kubectl get all -n web-app
    echo ""

    if [ "$RUNNING_PODS" -ge "3" ]; then
        log_success "Test 11 OK: Application déployée avec succès ($RUNNING_PODS pods Running)"
    else
        log_error "Test 11 FAILED: Pas assez de pods en état Running ($RUNNING_PODS/$TOTAL_PODS)"
        return 1
    fi
    echo ""
}

# Fonction principale
main() {
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "      TESTS E2E TP7 - Migration Docker Compose → K8s      "
    log_info "═══════════════════════════════════════════════════════════"
    echo ""

    # Nettoyage initial
    cleanup

    # Vérifier les prérequis
    check_prerequisites

    # Compteur de tests
    TESTS_PASSED=0
    TESTS_FAILED=0

    # Exécuter les tests dans l'ordre
    if test_namespace; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_config; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_database; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_backend; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_frontend; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_backend_db_connectivity; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_frontend_backend_connectivity; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_services; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_database_persistence; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_advanced_config; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_overall_health; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi

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

    log_info "Pour nettoyer l'application:"
    log_info "  ./test-tp7.sh cleanup"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "✓ TOUS LES TESTS E2E SONT PASSÉS !"
        log_info "L'application web complète est déployée et fonctionnelle"
        echo ""
        return 0
    else
        log_error "✗ CERTAINS TESTS ONT ÉCHOUÉ"
        echo ""
        return 1
    fi
}

# Permettre de nettoyer sans exécuter les tests
if [ "$1" = "cleanup" ]; then
    cleanup
    exit 0
fi

# Trap pour afficher un message en cas d'interruption
trap 'log_warning "Tests interrompus. Exécutez ./test-tp7.sh cleanup pour nettoyer les ressources."' INT TERM

# Exécuter les tests
main
