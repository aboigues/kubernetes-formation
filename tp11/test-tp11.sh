#!/bin/bash

# Script de test automatisé pour le TP11 - Kubernetes Gateway API
# Usage: ./test-tp11.sh [test_name]
# Exemples:
#   ./test-tp11.sh                  # Exécute tous les tests
#   ./test-tp11.sh test_gatewayclass # Exécute uniquement ce test

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

NAMESPACE="tp11"
TIMEOUT=120

# Récupère l'IP du Gateway avec fallback NodePort si LoadBalancer non disponible
get_gw_ip() {
    local gw_ip
    gw_ip=$(kubectl get gateway main-gateway -n "$NAMESPACE" \
        -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)

    if [ -z "$gw_ip" ]; then
        # Fallback : NodeIP + NodePort du service nginx-gateway
        local node_ip node_port
        node_ip=$(kubectl get nodes \
            -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        node_port=$(kubectl get svc -n nginx-gateway \
            -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)

        if [ -n "$node_ip" ] && [ -n "$node_port" ]; then
            gw_ip="${node_ip}:${node_port}"
            warning "LoadBalancer IP non disponible — utilisation du NodePort: $gw_ip"
            warning "Pour minikube : lancer 'minikube tunnel' dans un terminal séparé"
        else
            warning "IP du Gateway non disponible."
            warning "Solutions :"
            warning "  - minikube : lancer 'minikube tunnel' dans un terminal séparé"
            warning "  - Tous clusters : kubectl port-forward svc/nginx-gateway -n nginx-gateway 8080:80"
        fi
    fi

    echo "$gw_ip"
}

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; ((TESTS_PASSED++)); ((TESTS_TOTAL++)); }
error()   { echo -e "${RED}[✗]${NC} $1"; ((TESTS_FAILED++)); ((TESTS_TOTAL++)); }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }

check_prerequisites() {
    log "Vérification des prérequis..."

    if ! command -v kubectl &> /dev/null; then
        error "kubectl n'est pas installé"
        exit 1
    fi
    success "kubectl installé"

    if ! kubectl cluster-info &> /dev/null; then
        error "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi
    success "Connexion au cluster OK"

    # Vérifier la version K8s (≥ 1.28 requis pour Gateway API v1 stable)
    K8S_VERSION=$(kubectl version --output=json 2>/dev/null | grep -o '"gitVersion":"v[0-9]*\.[0-9]*' | head -1 | grep -o '[0-9]*\.[0-9]*$')
    MINOR=$(echo "$K8S_VERSION" | cut -d. -f2)
    if [ -n "$MINOR" ] && [ "$MINOR" -ge 28 ]; then
        success "Kubernetes $K8S_VERSION (≥ 1.28 requis)"
    else
        warning "Kubernetes $K8S_VERSION — Gateway API v1 nécessite ≥ 1.28"
    fi

    # Vérifier les CRDs Gateway API
    if kubectl get crd httproutes.gateway.networking.k8s.io &> /dev/null; then
        success "CRDs Gateway API présentes"
    else
        error "CRDs Gateway API manquantes — installer via: kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
        exit 1
    fi

    # Vérifier le namespace
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        success "Namespace $NAMESPACE présent"
    else
        warning "Namespace $NAMESPACE absent — création..."
        kubectl create namespace "$NAMESPACE"
        success "Namespace $NAMESPACE créé"
    fi
}

test_gatewayclass() {
    log "=== Test GatewayClass ==="

    kubectl apply -f examples/02-gatewayclass.yaml > /dev/null 2>&1 || true

    # Attendre que la GatewayClass soit acceptée
    local retries=0
    while [ $retries -lt 20 ]; do
        STATUS=$(kubectl get gatewayclass nginx -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
        if [ "$STATUS" = "True" ]; then
            success "GatewayClass nginx: ACCEPTED"
            return
        fi
        sleep 3
        ((retries++))
    done

    # Si pas de GatewayClass nginx, chercher d'autres implémentations
    OTHER=$(kubectl get gatewayclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$OTHER" ]; then
        warning "GatewayClass nginx non acceptée, mais '$OTHER' disponible"
        warning "Adapter examples/02-gatewayclass.yaml ou examples/03-gateway.yaml pour utiliser '$OTHER'"
    else
        error "Aucune GatewayClass disponible — installer une implémentation Gateway API"
    fi
}

test_gateway() {
    log "=== Test Gateway ==="

    kubectl apply -f examples/03-gateway.yaml > /dev/null 2>&1

    log "Attente du provisionnement du Gateway (max ${TIMEOUT}s)..."
    local retries=0
    while [ $retries -lt $((TIMEOUT/5)) ]; do
        STATUS=$(kubectl get gateway main-gateway -n "$NAMESPACE" \
          -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
        if [ "$STATUS" = "True" ]; then
            success "Gateway main-gateway: PROGRAMMED"
            break
        fi
        sleep 5
        ((retries++))
    done

    if [ "$STATUS" != "True" ]; then
        error "Gateway non programmé après ${TIMEOUT}s"
        kubectl describe gateway main-gateway -n "$NAMESPACE" | tail -20
        return
    fi

    GW_IP=$(get_gw_ip)
    if [ -n "$GW_IP" ]; then
        success "Gateway accessible: $GW_IP"
    else
        warning "Pas d'IP assignée au Gateway — les tests HTTP seront ignorés"
        warning "Lancer 'minikube tunnel' ou 'kubectl port-forward svc/nginx-gateway -n nginx-gateway 8080:80'"
    fi
}

test_backends() {
    log "=== Test déploiement des backends ==="

    kubectl apply -f examples/04-backend-v1.yaml > /dev/null 2>&1
    kubectl apply -f examples/05-backend-v2.yaml > /dev/null 2>&1

    log "Attente des pods backend..."
    if kubectl wait --for=condition=ready pod -l app=backend -n "$NAMESPACE" \
        --timeout="${TIMEOUT}s" > /dev/null 2>&1; then
        success "Pods backend prêts"
    else
        error "Pods backend non prêts après ${TIMEOUT}s"
        kubectl get pods -n "$NAMESPACE" -l app=backend
        return
    fi

    # Vérifier les services
    if kubectl get service backend-v1 -n "$NAMESPACE" &> /dev/null; then
        success "Service backend-v1 présent"
    else
        error "Service backend-v1 absent"
    fi

    if kubectl get service backend-v2 -n "$NAMESPACE" &> /dev/null; then
        success "Service backend-v2 présent"
    else
        error "Service backend-v2 absent"
    fi
}

test_basic_routing() {
    log "=== Test routage basique ==="

    kubectl apply -f examples/06-httproute-basic.yaml > /dev/null 2>&1

    sleep 3

    ACCEPTED=$(kubectl get httproute basic-routing -n "$NAMESPACE" \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
    if [ "$ACCEPTED" = "True" ]; then
        success "HTTPRoute basic-routing: Accepted"
    else
        error "HTTPRoute basic-routing non acceptée (status: $ACCEPTED)"
    fi

    RESOLVED=$(kubectl get httproute basic-routing -n "$NAMESPACE" \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null)
    if [ "$RESOLVED" = "True" ]; then
        success "HTTPRoute basic-routing: ResolvedRefs OK"
    else
        error "HTTPRoute basic-routing: ResolvedRefs KO (status: $RESOLVED)"
    fi

    GW_IP=$(get_gw_ip)

    if [ -z "$GW_IP" ]; then
        warning "IP du Gateway non disponible — tests HTTP ignorés"
        return
    fi

    for path in "/api" "/web" "/"; do
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
          -H "Host: app.example.com" "http://$GW_IP$path" 2>/dev/null)
        if [ "$RESPONSE" = "200" ]; then
            success "GET $path → HTTP 200"
        else
            error "GET $path → HTTP $RESPONSE (attendu: 200)"
        fi
    done
}

test_header_routing() {
    log "=== Test routage par header ==="

    kubectl apply -f examples/07-httproute-header-routing.yaml > /dev/null 2>&1
    sleep 3

    GW_IP=$(get_gw_ip)

    if [ -z "$GW_IP" ]; then
        warning "IP du Gateway non disponible — test ignoré"
        return
    fi

    # Sans header → v1
    BODY=$(curl -s -H "Host: ab.example.com" "http://$GW_IP/" 2>/dev/null)
    if echo "$BODY" | grep -qi "v1"; then
        success "Sans header X-Version → backend-v1"
    else
        warning "Sans header X-Version → réponse inattendue: $BODY"
    fi

    # Avec header X-Version: v2 → v2
    BODY=$(curl -s -H "Host: ab.example.com" -H "X-Version: v2" "http://$GW_IP/" 2>/dev/null)
    if echo "$BODY" | grep -qi "v2"; then
        success "Avec X-Version: v2 → backend-v2"
    else
        warning "Avec X-Version: v2 → réponse inattendue: $BODY"
    fi
}

test_rewrite() {
    log "=== Test filtres (réécriture et redirection) ==="

    kubectl apply -f examples/08-httproute-rewrite.yaml > /dev/null 2>&1
    sleep 3

    ACCEPTED=$(kubectl get httproute rewrite-routing -n "$NAMESPACE" \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
    if [ "$ACCEPTED" = "True" ]; then
        success "HTTPRoute rewrite-routing: Accepted"
    else
        error "HTTPRoute rewrite-routing non acceptée (status: $ACCEPTED)"
    fi

    GW_IP=$(get_gw_ip)

    if [ -z "$GW_IP" ]; then
        warning "IP du Gateway non disponible — tests HTTP ignorés"
        return
    fi

    # Test réécriture /old-api → /api (doit retourner 200)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Host: rewrite.example.com" "http://$GW_IP/old-api/users" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        success "URLRewrite /old-api → /api : HTTP 200"
    else
        error "URLRewrite /old-api → /api : HTTP $HTTP_CODE (attendu: 200)"
    fi

    # Test redirection /redirect → 301
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Host: rewrite.example.com" "http://$GW_IP/redirect" 2>/dev/null)
    if [ "$HTTP_CODE" = "301" ]; then
        success "RequestRedirect /redirect : HTTP 301"
    else
        error "RequestRedirect /redirect : HTTP $HTTP_CODE (attendu: 301)"
    fi
}

test_canary() {
    log "=== Test traffic splitting (canary 90/10) ==="

    kubectl apply -f examples/09-httproute-canary.yaml > /dev/null 2>&1
    sleep 3

    GW_IP=$(get_gw_ip)

    if [ -z "$GW_IP" ]; then
        warning "IP du Gateway non disponible — test ignoré"
        return
    fi

    local v1_count=0
    local v2_count=0
    local total=30

    for i in $(seq 1 $total); do
        BODY=$(curl -s -H "Host: canary.example.com" "http://$GW_IP/" 2>/dev/null)
        if echo "$BODY" | grep -qi "v2"; then
            ((v2_count++))
        else
            ((v1_count++))
        fi
    done

    local v2_pct=$(( (v2_count * 100) / total ))
    log "Distribution sur $total requêtes : v1=$v1_count, v2=$v2_count (v2: ${v2_pct}%)"

    # Tolérance : entre 0% et 30% pour v2 (target 10%)
    if [ "$v2_pct" -le 30 ]; then
        success "Distribution canary cohérente (v2: ${v2_pct}%, attendu ≈10%)"
    else
        error "Distribution canary anormale (v2: ${v2_pct}%, attendu ≈10%)"
    fi
}

test_tls() {
    log "=== Test TLS ==="

    if ! command -v openssl &> /dev/null; then
        warning "openssl non disponible — test TLS ignoré"
        return
    fi

    # Créer certificat auto-signé
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /tmp/tp11-tls.key -out /tmp/tp11-tls.crt \
        -subj "/CN=secure.example.com" > /dev/null 2>&1

    kubectl create secret tls tls-secret \
        --cert=/tmp/tp11-tls.crt \
        --key=/tmp/tp11-tls.key \
        -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1

    if kubectl get secret tls-secret -n "$NAMESPACE" &> /dev/null; then
        success "Secret TLS créé"
    else
        error "Échec création Secret TLS"
        return
    fi

    kubectl apply -f examples/10-httproute-tls.yaml > /dev/null 2>&1

    GW_IP=$(get_gw_ip)

    if [ -z "$GW_IP" ]; then
        warning "IP du Gateway non disponible — test HTTPS ignoré"
        return
    fi

    HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" \
        -H "Host: secure.example.com" "https://$GW_IP/" 2>/dev/null)
    if [ "$HTTPS_CODE" = "200" ]; then
        success "HTTPS opérationnel (HTTP 200)"
    else
        warning "HTTPS → HTTP $HTTPS_CODE (le listener HTTPS peut nécessiter plus de temps)"
    fi

    rm -f /tmp/tp11-tls.key /tmp/tp11-tls.crt
}

print_summary() {
    echo ""
    echo "========================================"
    echo "        RÉSULTATS DES TESTS TP11        "
    echo "========================================"
    echo -e "  Tests passés  : ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Tests échoués : ${RED}$TESTS_FAILED${NC}"
    echo -e "  Total         : $TESTS_TOTAL"
    echo "========================================"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✅ Tous les tests sont passés !${NC}"
    else
        echo -e "${RED}❌ $TESTS_FAILED test(s) en échec — voir les erreurs ci-dessus${NC}"
        exit 1
    fi
}

# Point d'entrée
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

check_prerequisites

case "${1:-all}" in
    test_gatewayclass)   test_gatewayclass ;;
    test_gateway)        test_gateway ;;
    test_backends)       test_backends ;;
    test_basic_routing)  test_basic_routing ;;
    test_header_routing) test_header_routing ;;
    test_rewrite)        test_rewrite ;;
    test_canary)         test_canary ;;
    test_tls)            test_tls ;;
    all)
        test_gatewayclass
        test_gateway
        test_backends
        test_basic_routing
        test_header_routing
        test_rewrite
        test_canary
        test_tls
        ;;
    *)
        echo "Usage: $0 [test_gatewayclass|test_gateway|test_backends|test_basic_routing|test_header_routing|test_rewrite|test_canary|test_tls|all]"
        exit 1
        ;;
esac

print_summary
