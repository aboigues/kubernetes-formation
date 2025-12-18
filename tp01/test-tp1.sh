#!/bin/bash

# Script de test automatisé pour le TP1 - Premier déploiement Kubernetes
# Ce script teste les concepts fondamentaux du TP1

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    # Vérifier kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl n'est pas installé"
        log_info "Installez kubectl avec: curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        exit 1
    fi
    log_success "kubectl est installé (version: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -n1))"

    # Vérifier la connexion au cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Impossible de se connecter au cluster Kubernetes"
        log_info "Assurez-vous qu'un cluster est démarré (minikube start ou kubeadm)"
        exit 1
    fi
    log_success "Connexion au cluster OK"

    # Afficher les informations du cluster
    log_info "Informations du cluster:"
    kubectl cluster-info | head -n 2

    log_success "Tous les prérequis sont OK"
    echo ""
}

# Fonction pour nettoyer les ressources de test
cleanup() {
    log_info "Nettoyage des ressources de test..."

    # Supprimer les déploiements
    kubectl delete deployment nginx-test webapp-test hello-world --ignore-not-found=true 2>/dev/null || true

    # Supprimer les services
    kubectl delete service nginx-test-service webapp-service hello-world --ignore-not-found=true 2>/dev/null || true

    # Supprimer les pods standalone
    kubectl delete pod test-pod nginx-standalone --ignore-not-found=true 2>/dev/null || true

    # Attendre que les ressources soient supprimées
    sleep 3

    log_success "Nettoyage terminé"
    echo ""
}

# Test 1: Créer un déploiement simple
test_basic_deployment() {
    log_info "Test 1: Création d'un déploiement basique..."

    # Créer un déploiement nginx
    kubectl create deployment nginx-test --image=nginx:1.24 --replicas=2

    # Attendre que le déploiement soit prêt
    log_info "Attente du déploiement..."
    kubectl wait --for=condition=available --timeout=120s deployment/nginx-test

    # Vérifier que le déploiement existe
    if kubectl get deployment nginx-test &> /dev/null; then
        REPLICAS=$(kubectl get deployment nginx-test -o jsonpath='{.status.readyReplicas}')
        if [ "$REPLICAS" = "2" ]; then
            log_success "Test 1 OK: Déploiement créé avec succès (2/2 replicas prêts)"
        else
            log_error "Test 1 FAILED: Seulement $REPLICAS/2 replicas prêts"
            return 1
        fi
    else
        log_error "Test 1 FAILED: Le déploiement n'existe pas"
        return 1
    fi
    echo ""
}

# Test 2: Exposer le déploiement via un service
test_service_exposure() {
    log_info "Test 2: Exposition du déploiement via un service..."

    # Exposer le déploiement
    kubectl expose deployment nginx-test --port=80 --target-port=80 --name=nginx-test-service --type=ClusterIP

    # Attendre que le service soit créé
    sleep 2

    # Vérifier que le service existe
    if kubectl get service nginx-test-service &> /dev/null; then
        CLUSTER_IP=$(kubectl get service nginx-test-service -o jsonpath='{.spec.clusterIP}')
        PORT=$(kubectl get service nginx-test-service -o jsonpath='{.spec.ports[0].port}')

        log_success "Test 2 OK: Service créé avec succès (ClusterIP: $CLUSTER_IP, Port: $PORT)"

        # Vérifier les endpoints
        ENDPOINTS=$(kubectl get endpoints nginx-test-service -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
        if [ "$ENDPOINTS" = "2" ]; then
            log_success "Service a 2 endpoints (correspondant aux 2 replicas)"
        else
            log_warning "Service a $ENDPOINTS endpoints au lieu de 2"
        fi
    else
        log_error "Test 2 FAILED: Le service n'existe pas"
        return 1
    fi
    echo ""
}

# Test 3: Tester la connectivité au service
test_service_connectivity() {
    log_info "Test 3: Test de connectivité au service..."

    # Créer un pod de test temporaire pour tester la connectivité
    kubectl run test-pod --image=busybox --rm -i --restart=Never --command -- sh -c "wget -q -O- http://nginx-test-service:80 | head -n 5" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Test 3 OK: Le service est accessible depuis le cluster"
    else
        log_error "Test 3 FAILED: Impossible d'accéder au service"
        return 1
    fi
    echo ""
}

# Test 4: Scaling du déploiement
test_scaling() {
    log_info "Test 4: Scaling du déploiement..."

    # Scaler le déploiement à 3 replicas
    kubectl scale deployment nginx-test --replicas=3

    # Attendre que le scaling soit effectif
    log_info "Attente du scaling (3 replicas)..."
    kubectl wait --for=condition=available --timeout=60s deployment/nginx-test

    # Vérifier le nombre de replicas
    REPLICAS=$(kubectl get deployment nginx-test -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" = "3" ]; then
        log_success "Test 4a OK: Scaling UP vers 3 replicas réussi"
    else
        log_error "Test 4a FAILED: $REPLICAS/3 replicas prêts"
        return 1
    fi

    # Scaler le déploiement à 1 replica
    kubectl scale deployment nginx-test --replicas=1

    # Attendre que le scaling soit effectif
    log_info "Attente du scaling (1 replica)..."
    kubectl wait --for=condition=available --timeout=60s deployment/nginx-test
    sleep 5  # Attendre la terminaison des pods

    REPLICAS=$(kubectl get deployment nginx-test -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" = "1" ]; then
        log_success "Test 4b OK: Scaling DOWN vers 1 replica réussi"
    else
        log_error "Test 4b FAILED: $REPLICAS/1 replicas prêts"
        return 1
    fi
    echo ""
}

# Test 5: Rolling update
test_rolling_update() {
    log_info "Test 5: Test du rolling update..."

    # Récupérer l'image actuelle
    CURRENT_IMAGE=$(kubectl get deployment nginx-test -o jsonpath='{.spec.template.spec.containers[0].image}')
    log_info "Image actuelle: $CURRENT_IMAGE"

    # Mettre à jour l'image
    NEW_IMAGE="nginx:1.25"
    kubectl set image deployment/nginx-test nginx=$NEW_IMAGE

    # Attendre que le rollout soit terminé
    log_info "Attente du rolling update..."
    kubectl rollout status deployment/nginx-test --timeout=120s

    # Vérifier la nouvelle image
    UPDATED_IMAGE=$(kubectl get deployment nginx-test -o jsonpath='{.spec.template.spec.containers[0].image}')

    if [ "$UPDATED_IMAGE" = "$NEW_IMAGE" ]; then
        log_success "Test 5 OK: Rolling update réussi ($CURRENT_IMAGE → $NEW_IMAGE)"
    else
        log_error "Test 5 FAILED: Image non mise à jour (actuelle: $UPDATED_IMAGE)"
        return 1
    fi
    echo ""
}

# Test 6: Rollback
test_rollback() {
    log_info "Test 6: Test du rollback..."

    # Afficher l'historique
    log_info "Historique des révisions:"
    kubectl rollout history deployment/nginx-test

    # Effectuer un rollback
    kubectl rollout undo deployment/nginx-test

    # Attendre que le rollback soit terminé
    log_info "Attente du rollback..."
    kubectl rollout status deployment/nginx-test --timeout=120s

    # Vérifier que l'image est revenue à la version précédente
    ROLLBACK_IMAGE=$(kubectl get deployment nginx-test -o jsonpath='{.spec.template.spec.containers[0].image}')

    if [ "$ROLLBACK_IMAGE" = "nginx:1.24" ]; then
        log_success "Test 6 OK: Rollback réussi (retour à nginx:1.24)"
    else
        log_warning "Test 6 WARNING: Image après rollback: $ROLLBACK_IMAGE (attendu: nginx:1.24)"
    fi
    echo ""
}

# Test 7: Health checks et self-healing
test_self_healing() {
    log_info "Test 7: Test du self-healing..."

    # Créer un déploiement avec 2 replicas
    kubectl create deployment hello-world --image=gcr.io/google-samples/hello-app:1.0 --replicas=2

    # Attendre que le déploiement soit prêt
    kubectl wait --for=condition=available --timeout=60s deployment/hello-world

    # Récupérer un nom de pod
    POD_NAME=$(kubectl get pods -l app=hello-world -o jsonpath='{.items[0].metadata.name}')
    log_info "Suppression du pod: $POD_NAME"

    # Supprimer le pod
    kubectl delete pod $POD_NAME

    # Attendre un peu
    sleep 3

    # Vérifier que le déploiement a recréé le pod
    NEW_REPLICAS=$(kubectl get deployment hello-world -o jsonpath='{.status.readyReplicas}')

    if [ "$NEW_REPLICAS" = "2" ]; then
        log_success "Test 7 OK: Self-healing fonctionne (pod recréé automatiquement)"
    else
        log_error "Test 7 FAILED: Self-healing ne fonctionne pas ($NEW_REPLICAS/2 replicas)"
        return 1
    fi
    echo ""
}

# Test 8: Labels et sélecteurs
test_labels_selectors() {
    log_info "Test 8: Test des labels et sélecteurs..."

    # Lister les pods avec un label spécifique
    NGINX_PODS=$(kubectl get pods -l app=nginx-test --no-headers | wc -l)
    HELLO_PODS=$(kubectl get pods -l app=hello-world --no-headers | wc -l)

    if [ "$NGINX_PODS" -ge "1" ] && [ "$HELLO_PODS" -ge "1" ]; then
        log_success "Test 8 OK: Sélection par labels fonctionne (nginx: $NGINX_PODS pods, hello-world: $HELLO_PODS pods)"
    else
        log_error "Test 8 FAILED: Problème avec les sélecteurs de labels"
        return 1
    fi
    echo ""
}

# Fonction principale
main() {
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "  TESTS AUTOMATISÉS TP1 - Premier déploiement Kubernetes  "
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
    if test_basic_deployment; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_service_exposure; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_service_connectivity; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_scaling; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_rolling_update; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_rollback; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_self_healing; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi
    if test_labels_selectors; then ((TESTS_PASSED++)); else ((TESTS_FAILED++)); fi

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
