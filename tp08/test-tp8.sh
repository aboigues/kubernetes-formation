#!/bin/bash

# Script de test automatisé pour le TP8 - Réseau Kubernetes
# Usage: ./test-tp8.sh [test_name]
# Exemples:
#   ./test-tp8.sh              # Exécute tous les tests
#   ./test-tp8.sh test_services # Exécute uniquement les tests de services

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Compteurs
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Fonction pour afficher un message
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

error() {
    echo -e "${RED}[✗]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log "Vérification des prérequis..."

    # Vérifier kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl n'est pas installé"
        exit 1
    fi
    success "kubectl est installé"

    # Vérifier l'accès au cluster
    if ! kubectl cluster-info &> /dev/null; then
        error "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi
    success "Connexion au cluster OK"

    # Vérifier CoreDNS
    if kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -q Running; then
        success "CoreDNS est actif"
    else
        warning "CoreDNS n'est pas actif ou introuvable"
    fi

    # Vérifier le plugin CNI
    if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -qE 'calico|cilium|weave'; then
        CNI_PLUGIN=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -oE 'calico|cilium|weave' | head -1)
        success "Plugin CNI détecté: $CNI_PLUGIN (NetworkPolicies supportées)"
    elif kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q flannel; then
        warning "Plugin CNI: Flannel (NetworkPolicies NON supportées)"
    else
        warning "Plugin CNI non identifié"
    fi

    echo ""
}

# Test 1 : Communication inter-pods
test_pod_communication() {
    log "Test 1: Communication inter-pods..."

    # Créer deux pods
    kubectl run pod-a --image=nginx:alpine --restart=Never 2>/dev/null || true
    kubectl run pod-b --image=nginx:alpine --restart=Never 2>/dev/null || true

    # Attendre que les pods soient prêts
    kubectl wait --for=condition=ready pod/pod-a pod/pod-b --timeout=60s &>/dev/null || {
        error "Les pods ne sont pas prêts"
        kubectl delete pod pod-a pod-b --ignore-not-found=true 2>/dev/null
        return 1
    }

    # Récupérer l'IP du pod-b
    POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')

    # Tester la communication
    if kubectl exec pod-a -- wget -qO- --timeout=5 http://$POD_B_IP &>/dev/null; then
        success "Communication inter-pods fonctionne"
    else
        error "Échec de la communication inter-pods"
    fi

    # Nettoyer
    kubectl delete pod pod-a pod-b --ignore-not-found=true 2>/dev/null
    echo ""
}

# Test 2 : Service ClusterIP
test_services() {
    log "Test 2: Services..."

    # Déployer le service ClusterIP
    kubectl apply -f examples/01-backend-deployment-service.yaml &>/dev/null

    # Attendre que les pods soient prêts
    kubectl wait --for=condition=ready pod -l app=backend --timeout=60s &>/dev/null || {
        error "Les pods backend ne sont pas prêts"
        kubectl delete -f examples/01-backend-deployment-service.yaml &>/dev/null
        return 1
    }

    # Vérifier le service
    if kubectl get svc backend-svc &>/dev/null; then
        success "Service ClusterIP créé"
    else
        error "Service ClusterIP non créé"
        kubectl delete -f examples/01-backend-deployment-service.yaml &>/dev/null
        return 1
    fi

    # Vérifier les endpoints
    ENDPOINTS=$(kubectl get endpoints backend-svc -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -o '{' | wc -l)
    if [ "$ENDPOINTS" -eq 3 ]; then
        success "3 endpoints détectés (3 replicas)"
    else
        warning "Nombre d'endpoints incorrect: $ENDPOINTS (attendu: 3)"
    fi

    # Tester l'accès au service
    if kubectl run tmp --image=busybox --restart=Never --rm -it --timeout=30s -- wget -qO- --timeout=5 http://backend-svc &>/dev/null; then
        success "Accès au service ClusterIP OK"
    else
        error "Impossible d'accéder au service ClusterIP"
    fi

    # Nettoyer
    kubectl delete -f examples/01-backend-deployment-service.yaml &>/dev/null
    echo ""
}

# Test 3 : DNS
test_dns() {
    log "Test 3: DNS et Service Discovery..."

    # Créer deux namespaces
    kubectl create namespace test-frontend 2>/dev/null || true
    kubectl create namespace test-backend 2>/dev/null || true

    # Créer un service dans test-backend
    kubectl create deployment api -n test-backend --image=nginx:alpine 2>/dev/null || true
    kubectl expose deployment api -n test-backend --port=80 2>/dev/null || true

    # Attendre que le pod soit prêt
    kubectl wait --for=condition=ready pod -l app=api -n test-backend --timeout=60s &>/dev/null || {
        error "Le pod API n'est pas prêt"
        kubectl delete namespace test-frontend test-backend --ignore-not-found=true 2>/dev/null
        return 1
    }

    # Tester résolution DNS inter-namespaces
    if kubectl run test -n test-frontend --image=busybox --restart=Never --rm -it --timeout=30s -- nslookup api.test-backend &>/dev/null; then
        success "Résolution DNS inter-namespaces OK"
    else
        error "Échec de la résolution DNS inter-namespaces"
    fi

    # Nettoyer
    kubectl delete namespace test-frontend test-backend --ignore-not-found=true 2>/dev/null
    echo ""
}

# Test 4 : Headless Service
test_headless() {
    log "Test 4: Headless Service..."

    # Déployer le headless service
    kubectl apply -f examples/03-headless-service.yaml &>/dev/null

    # Attendre que les pods soient prêts
    kubectl wait --for=condition=ready pod -l app=database --timeout=120s &>/dev/null || {
        error "Les pods database ne sont pas prêts"
        kubectl delete -f examples/03-headless-service.yaml &>/dev/null
        return 1
    }

    # Vérifier que ClusterIP est None
    CLUSTER_IP=$(kubectl get svc db-headless -o jsonpath='{.spec.clusterIP}')
    if [ "$CLUSTER_IP" = "None" ]; then
        success "Headless Service configuré (ClusterIP: None)"
    else
        error "ClusterIP devrait être None, trouvé: $CLUSTER_IP"
    fi

    # Tester résolution DNS (devrait retourner plusieurs IPs)
    DNS_OUTPUT=$(kubectl run tmp --image=busybox --restart=Never --rm -it --timeout=30s -- nslookup db-headless 2>/dev/null | grep "Address:" | tail -n +2 | wc -l)
    if [ "$DNS_OUTPUT" -ge 1 ]; then
        success "DNS retourne les IPs des Pods (headless)"
    else
        warning "DNS ne retourne pas les IPs attendues"
    fi

    # Nettoyer
    kubectl delete -f examples/03-headless-service.yaml &>/dev/null
    echo ""
}

# Test 5 : NetworkPolicies
test_networkpolicies() {
    log "Test 5: NetworkPolicies..."

    # Vérifier si le CNI supporte les NetworkPolicies
    if kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q flannel; then
        warning "Flannel détecté - NetworkPolicies non supportées"
        echo ""
        return 0
    fi

    # Créer namespace
    kubectl create namespace test-secure 2>/dev/null || true

    # Créer un deployment
    kubectl create deployment web -n test-secure --image=nginx:alpine 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=web -n test-secure --timeout=60s &>/dev/null || {
        error "Le pod web n'est pas prêt"
        kubectl delete namespace test-secure --ignore-not-found=true 2>/dev/null
        return 1
    }

    # Obtenir l'IP du pod
    POD_IP=$(kubectl get pod -n test-secure -l app=web -o jsonpath='{.items[0].status.podIP}')

    # Tester AVANT NetworkPolicy
    if kubectl run tmp -n test-secure --image=busybox --restart=Never --rm -it --timeout=30s -- wget -qO- --timeout=5 http://$POD_IP &>/dev/null; then
        success "Accès AVANT NetworkPolicy: OK"
    else
        warning "Accès AVANT NetworkPolicy: Échec"
    fi

    # Appliquer NetworkPolicy deny-all
    cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: test-secure
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

    # Attendre un peu
    sleep 2

    # Tester APRÈS NetworkPolicy (devrait échouer)
    if ! kubectl run tmp -n test-secure --image=busybox --restart=Never --rm -it --timeout=30s -- wget -qO- --timeout=5 http://$POD_IP &>/dev/null; then
        success "NetworkPolicy deny-all fonctionne (accès bloqué)"
    else
        warning "NetworkPolicy ne bloque pas le trafic"
    fi

    # Nettoyer
    kubectl delete namespace test-secure --ignore-not-found=true 2>/dev/null
    echo ""
}

# Test 6 : Exercice multi-tiers
test_multi_tier() {
    log "Test 6: Architecture multi-tiers..."

    # Créer namespace
    kubectl create namespace test-app 2>/dev/null || true

    # Déployer l'architecture
    kubectl apply -f exercices/exercice-1-multi-tiers.yaml &>/dev/null

    # Attendre que tout soit prêt
    kubectl wait --for=condition=ready pod --all -n test-app --timeout=120s &>/dev/null || {
        error "Les pods de l'architecture multi-tiers ne sont pas prêts"
        kubectl delete namespace test-app --ignore-not-found=true 2>/dev/null
        return 1
    }

    # Vérifier les déploiements
    DEPLOYMENTS=$(kubectl get deployments -n test-app --no-headers | wc -l)
    if [ "$DEPLOYMENTS" -eq 3 ]; then
        success "3 déploiements créés (frontend, backend, database)"
    else
        warning "Nombre de déploiements incorrect: $DEPLOYMENTS (attendu: 3)"
    fi

    # Vérifier les services
    SERVICES=$(kubectl get svc -n test-app --no-headers | wc -l)
    if [ "$SERVICES" -ge 3 ]; then
        success "Services créés"
    else
        warning "Services manquants"
    fi

    # Nettoyer
    kubectl delete namespace test-app --ignore-not-found=true 2>/dev/null
    echo ""
}

# Fonction principale
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Tests TP8 - Réseau Kubernetes                         ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites

    # Si un test spécifique est demandé
    if [ $# -eq 1 ]; then
        case $1 in
            test_pod_communication)
                test_pod_communication
                ;;
            test_services)
                test_services
                ;;
            test_dns)
                test_dns
                ;;
            test_headless)
                test_headless
                ;;
            test_networkpolicies)
                test_networkpolicies
                ;;
            test_multi_tier)
                test_multi_tier
                ;;
            *)
                echo "Test inconnu: $1"
                echo "Tests disponibles: test_pod_communication, test_services, test_dns, test_headless, test_networkpolicies, test_multi_tier"
                exit 1
                ;;
        esac
    else
        # Exécuter tous les tests
        test_pod_communication
        test_services
        test_dns
        test_headless
        test_networkpolicies
        test_multi_tier
    fi

    # Résumé
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Résumé des tests                                      ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "Tests passés:  ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests échoués: ${RED}${TESTS_FAILED}${NC}"
    echo -e "Total:         ${TESTS_TOTAL}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ Tous les tests sont passés !${NC}"
        exit 0
    else
        echo -e "${RED}✗ Certains tests ont échoué.${NC}"
        exit 1
    fi
}

# Exécuter
main "$@"
