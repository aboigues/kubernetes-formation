#!/bin/bash

# Script de test automatisé pour le TP4 - Monitoring et Logs
# Ce script teste tous les composants du TP4 : Metrics Server, Prometheus, Grafana, HPA
# Usage: ./test-tp4.sh

# Note: Ne pas utiliser 'set -e' car les fonctions de test utilisent 'return 1'
# et nous voulons continuer même si un test échoue

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

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fonction pour afficher les messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_TOTAL++))
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_TOTAL++))
}

log_warning() {
    echo -e "${YELLOW}[! WARNING]${NC} $1"
}

log_fix() {
    echo -e "${YELLOW}[🔧 FIX]${NC} $1"
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Vérification des prérequis"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl n'est pas installé"
        exit 1
    fi
    log_success "kubectl est installé"

    # Vérifier l'accès au cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Impossible de se connecter au cluster Kubernetes"
        log_fix "Commandes de correction :"
        echo "  - minikube start"
        echo "  - kubectl config use-context <context>"
        exit 1
    fi
    log_success "Connexion au cluster OK"

    # Vérifier la version de Kubernetes
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "unknown")
    log_info "Version Kubernetes : $K8S_VERSION"

    # Vérifier si minikube est disponible
    if command -v minikube &> /dev/null; then
        log_info "Minikube détecté - addons disponibles"
    else
        log_warning "Minikube non détecté - installation manuelle requise"
    fi

    echo ""
}

# Fonction de nettoyage
cleanup() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Nettoyage des ressources de test"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Supprimer les pods de test
    kubectl delete pod load-generator --ignore-not-found=true 2>/dev/null || true
    kubectl delete deployment nginx-test --ignore-not-found=true 2>/dev/null || true

    # Supprimer le namespace monitoring
    log_warning "Le namespace monitoring ne sera pas supprimé pour préserver Prometheus/Grafana"
    log_info "Pour nettoyer complètement : kubectl delete namespace monitoring"

    # Supprimer la stack EFK (déployée par ce script, contrairement au reste)
    kubectl delete -f "$SCRIPT_DIR/08-fluentd-daemonset.yaml" --ignore-not-found=true 2>/dev/null || true
    kubectl delete namespace logging --ignore-not-found=true --timeout=60s 2>/dev/null || true

    echo ""
}

# Test 1: Metrics Server
test_metrics_server() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 1: Metrics Server"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier si Metrics Server est déployé
    log_info "Vérification du déploiement Metrics Server..."
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        log_success "Metrics Server est déployé"
    else
        log_error "Metrics Server n'est pas déployé"
        log_fix "Commandes de correction :"
        echo "  minikube addons enable metrics-server"
        echo "  # OU pour installation manuelle :"
        echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        return 1
    fi

    # Vérifier que le pod est Running
    log_info "Vérification de l'état du pod Metrics Server..."
    if kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep -q Running; then
        log_success "Pod Metrics Server est Running"
    else
        log_error "Pod Metrics Server n'est pas Running"
        kubectl get pods -n kube-system -l k8s-app=metrics-server
        return 1
    fi

    # Attendre que Metrics Server soit prêt
    log_info "Attente de la disponibilité des métriques (peut prendre 1-2 minutes)..."
    sleep 10

    # Tester kubectl top nodes
    log_info "Test de 'kubectl top nodes'..."
    if kubectl top nodes &>/dev/null; then
        log_success "kubectl top nodes fonctionne"
    else
        log_warning "kubectl top nodes ne fonctionne pas encore (peut nécessiter plus de temps)"
        log_fix "Commandes de diagnostic :"
        echo "  kubectl logs -n kube-system -l k8s-app=metrics-server"
        echo "  kubectl describe pod -n kube-system -l k8s-app=metrics-server"
    fi

    echo ""
}

# Test 2: HPA (Horizontal Pod Autoscaler)
test_hpa() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 2: Horizontal Pod Autoscaler (HPA)"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Déployer l'application HPA
    log_info "Déploiement de l'application de test HPA..."
    if [ -f "$SCRIPT_DIR/01-hpa-demo.yaml" ]; then
        kubectl apply -f "$SCRIPT_DIR/01-hpa-demo.yaml" &>/dev/null
        log_success "Application HPA déployée"
    else
        log_error "Fichier 01-hpa-demo.yaml introuvable"
        return 1
    fi

    # Attendre que les pods soient prêts
    log_info "Attente du démarrage des pods..."
    if kubectl wait --for=condition=ready pod -l app=php-apache --timeout=90s &>/dev/null; then
        log_success "Pods php-apache prêts"
    else
        log_error "Les pods php-apache ne sont pas prêts"
        kubectl get pods -l app=php-apache
        return 1
    fi

    # Vérifier que le HPA existe
    log_info "Vérification du HPA..."
    if kubectl get hpa php-apache-hpa &>/dev/null; then
        log_success "HPA php-apache-hpa créé"
    else
        log_error "HPA php-apache-hpa n'existe pas"
        return 1
    fi

    # Vérifier l'état du HPA
    log_info "État du HPA :"
    kubectl get hpa php-apache-hpa

    # Vérifier que le HPA peut obtenir des métriques
    sleep 15
    HPA_CURRENT=$(kubectl get hpa php-apache-hpa -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || echo "")
    if [ -n "$HPA_CURRENT" ]; then
        log_success "HPA peut lire les métriques CPU : ${HPA_CURRENT}%"
    else
        log_warning "HPA ne peut pas encore lire les métriques (peut nécessiter plus de temps)"
    fi

    echo ""
}

# Test 3: Prometheus - Déploiement et Configuration
test_prometheus_deployment() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 3: Prometheus - Déploiement"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier le namespace monitoring
    if kubectl get namespace monitoring &>/dev/null; then
        log_success "Namespace monitoring existe"
    else
        log_error "Namespace monitoring n'existe pas"
        log_fix "Commandes de correction :"
        echo "  kubectl apply -f $SCRIPT_DIR/04-prometheus-deployment.yaml"
        return 1
    fi

    # Vérifier le déploiement Prometheus
    log_info "Vérification du déploiement Prometheus..."
    if kubectl get deployment prometheus -n monitoring &>/dev/null; then
        log_success "Déploiement Prometheus existe"
    else
        log_error "Déploiement Prometheus n'existe pas"
        log_fix "Commandes de correction :"
        echo "  kubectl apply -f $SCRIPT_DIR/04-prometheus-deployment.yaml"
        return 1
    fi

    # Vérifier que le pod Prometheus est Running
    log_info "Vérification de l'état du pod Prometheus..."
    if kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | grep -q Running; then
        log_success "Pod Prometheus est Running"
    else
        log_error "Pod Prometheus n'est pas Running"
        kubectl get pods -n monitoring -l app=prometheus
        log_fix "Commandes de diagnostic :"
        echo "  kubectl describe pod -n monitoring -l app=prometheus"
        echo "  kubectl logs -n monitoring -l app=prometheus"
        return 1
    fi

    # Vérifier le service Prometheus
    log_info "Vérification du service Prometheus..."
    if kubectl get service prometheus -n monitoring &>/dev/null; then
        log_success "Service Prometheus existe"
        PROM_PORT=$(kubectl get service prometheus -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
        log_info "Prometheus accessible via NodePort: $PROM_PORT"
    else
        log_error "Service Prometheus n'existe pas"
        return 1
    fi

    echo ""
}

# Test 4: Prometheus - RBAC et Permissions
test_prometheus_rbac() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 4: Prometheus - RBAC et Permissions"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier le ServiceAccount
    log_info "Vérification du ServiceAccount prometheus..."
    if kubectl get serviceaccount prometheus -n monitoring &>/dev/null; then
        log_success "ServiceAccount prometheus existe"
    else
        log_error "ServiceAccount prometheus n'existe pas"
        log_fix "Commandes de correction :"
        echo "  kubectl apply -f $SCRIPT_DIR/04-prometheus-deployment.yaml"
        return 1
    fi

    # Vérifier le ClusterRole
    log_info "Vérification du ClusterRole prometheus..."
    if kubectl get clusterrole prometheus &>/dev/null; then
        log_success "ClusterRole prometheus existe"
    else
        log_error "ClusterRole prometheus n'existe pas"
        log_fix "Commandes de correction :"
        echo "  kubectl apply -f $SCRIPT_DIR/04-prometheus-deployment.yaml"
        return 1
    fi

    # Vérifier les permissions critiques
    log_info "Vérification des permissions nodes/metrics..."
    if kubectl auth can-i get nodes/metrics --as=system:serviceaccount:monitoring:prometheus 2>/dev/null | grep -q "yes"; then
        log_success "Permission nodes/metrics OK"
    else
        log_error "Permission nodes/metrics manquante"
        log_fix "Vérifier que le ClusterRole contient 'nodes/metrics' dans les resources"
        return 1
    fi

    log_info "Vérification des permissions pods..."
    if kubectl auth can-i list pods --as=system:serviceaccount:monitoring:prometheus 2>/dev/null | grep -q "yes"; then
        log_success "Permission list pods OK"
    else
        log_error "Permission list pods manquante"
        return 1
    fi

    log_info "Vérification des permissions namespaces..."
    if kubectl auth can-i list namespaces --as=system:serviceaccount:monitoring:prometheus 2>/dev/null | grep -q "yes"; then
        log_success "Permission list namespaces OK"
    else
        log_error "Permission list namespaces manquante"
        return 1
    fi

    # Vérifier le ClusterRoleBinding
    log_info "Vérification du ClusterRoleBinding..."
    if kubectl get clusterrolebinding prometheus &>/dev/null; then
        log_success "ClusterRoleBinding prometheus existe"
    else
        log_error "ClusterRoleBinding prometheus n'existe pas"
        return 1
    fi

    echo ""
}

# Test 5: Prometheus - Collecte de métriques
test_prometheus_metrics() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 5: Prometheus - Collecte de métriques"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Setup port-forward pour accéder à Prometheus
    log_info "Configuration du port-forward vers Prometheus..."
    kubectl port-forward -n monitoring svc/prometheus 9090:9090 &>/dev/null &
    PORT_FORWARD_PID=$!
    sleep 5

    # Vérifier que Prometheus est accessible
    log_info "Vérification de l'accès à Prometheus..."
    if curl -s http://localhost:9090/-/healthy | grep -q "Prometheus is Healthy"; then
        log_success "Prometheus est accessible et healthy"
    else
        log_error "Prometheus n'est pas accessible"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        log_fix "Commandes de diagnostic :"
        echo "  kubectl logs -n monitoring -l app=prometheus --tail=50"
        echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
        echo "  curl http://localhost:9090/-/healthy"
        return 1
    fi

    # Vérifier que Prometheus peut interroger l'API
    log_info "Vérification de l'API Prometheus..."
    if curl -s http://localhost:9090/api/v1/status/config | jq -e '.status == "success"' &>/dev/null; then
        log_success "API Prometheus fonctionne"
    else
        log_error "API Prometheus ne répond pas correctement"
        kill $PORT_FORWARD_PID 2>/dev/null || true
        return 1
    fi

    # Vérifier les targets (cibles de scraping)
    log_info "Vérification des targets Prometheus..."
    TARGETS_UP=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | sort -u | wc -l)
    if [ "$TARGETS_UP" -gt 0 ]; then
        log_success "Targets actives détectées : $TARGETS_UP jobs UP"
        log_info "Jobs actifs :"
        curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets[] | select(.health=="up") | .labels.job' | sort -u | sed 's/^/  - /'
    else
        log_warning "Aucune target UP détectée (peut nécessiter plus de temps)"
    fi

    # Vérifier les métriques cAdvisor
    log_info "Vérification des métriques cAdvisor (container_cpu_usage_seconds_total)..."
    CADVISOR_METRICS=$(curl -s 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total' 2>/dev/null | jq -r '.data.result | length')
    if [ "$CADVISOR_METRICS" -gt 0 ]; then
        log_success "Métriques cAdvisor collectées : $CADVISOR_METRICS séries"
    else
        log_warning "Métriques cAdvisor non disponibles"
        log_fix "Vérifier que le job 'kubernetes-cadvisor' est UP dans Prometheus Targets"
        log_fix "Vérifier les permissions RBAC (nonResourceURLs: /metrics/cadvisor)"
    fi

    # Vérifier la requête 'up'
    log_info "Test de la requête 'up'..."
    UP_COUNT=$(curl -s 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | jq -r '.data.result | length')
    if [ "$UP_COUNT" -gt 0 ]; then
        log_success "Requête 'up' retourne $UP_COUNT résultats"
    else
        log_error "Requête 'up' ne retourne aucun résultat"
    fi

    # Nettoyer le port-forward
    kill $PORT_FORWARD_PID 2>/dev/null || true
    echo ""
}

# Test 6: Grafana
test_grafana() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 6: Grafana"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier le déploiement Grafana
    log_info "Vérification du déploiement Grafana..."
    if kubectl get deployment grafana -n monitoring &>/dev/null; then
        log_success "Déploiement Grafana existe"
    else
        log_error "Déploiement Grafana n'existe pas"
        log_fix "Commandes de correction :"
        echo "  kubectl apply -f $SCRIPT_DIR/05-grafana-deployment.yaml"
        return 1
    fi

    # Vérifier que le pod Grafana est Running
    log_info "Vérification de l'état du pod Grafana..."
    if kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | grep -q Running; then
        log_success "Pod Grafana est Running"
    else
        log_error "Pod Grafana n'est pas Running"
        kubectl get pods -n monitoring -l app=grafana
        log_fix "Commandes de diagnostic :"
        echo "  kubectl describe pod -n monitoring -l app=grafana"
        echo "  kubectl logs -n monitoring -l app=grafana"
        return 1
    fi

    # Vérifier le service Grafana
    log_info "Vérification du service Grafana..."
    if kubectl get service grafana -n monitoring &>/dev/null; then
        log_success "Service Grafana existe"
        GRAFANA_PORT=$(kubectl get service grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
        log_info "Grafana accessible via NodePort: $GRAFANA_PORT"
        log_info "Credentials: admin / admin123"
    else
        log_error "Service Grafana n'existe pas"
        return 1
    fi

    # Test de connexion à Grafana
    log_info "Test de connexion à Grafana..."
    kubectl port-forward -n monitoring svc/grafana 3000:3000 &>/dev/null &
    GRAFANA_PID=$!
    sleep 5

    if curl -s http://localhost:3000/api/health | jq -e '.database == "ok"' &>/dev/null; then
        log_success "Grafana est accessible et opérationnel"
    else
        log_warning "Grafana n'est pas encore complètement prêt"
    fi

    kill $GRAFANA_PID 2>/dev/null || true
    echo ""
}

# Test 7: Configuration Prometheus complète
test_prometheus_config() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 7: Configuration Prometheus"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    # Vérifier la ConfigMap
    log_info "Vérification de la ConfigMap prometheus-config..."
    if kubectl get configmap prometheus-config -n monitoring &>/dev/null; then
        log_success "ConfigMap prometheus-config existe"
    else
        log_error "ConfigMap prometheus-config n'existe pas"
        return 1
    fi

    # Vérifier les jobs de scraping configurés
    log_info "Vérification des jobs de scraping configurés..."
    JOBS=$(kubectl get configmap prometheus-config -n monitoring -o jsonpath='{.data.prometheus\.yml}' | grep -E 'job_name:' | wc -l)
    if [ "$JOBS" -ge 4 ]; then
        log_success "Jobs de scraping configurés : $JOBS"
        kubectl get configmap prometheus-config -n monitoring -o jsonpath='{.data.prometheus\.yml}' | grep -E 'job_name:' | sed 's/^/  /'
    else
        log_warning "Moins de 4 jobs configurés : $JOBS"
    fi

    # Vérifier les logs Prometheus pour les erreurs
    log_info "Vérification des logs Prometheus (dernières 50 lignes)..."
    ERROR_COUNT=$(kubectl logs -n monitoring -l app=prometheus --tail=50 2>/dev/null | grep -ciE 'error|forbidden|unauthorized|failed' || echo "0")
    if [ "$ERROR_COUNT" -eq 0 ]; then
        log_success "Aucune erreur critique dans les logs"
    else
        log_warning "$ERROR_COUNT erreurs détectées dans les logs"
        log_fix "Commandes de diagnostic :"
        echo "  kubectl logs -n monitoring -l app=prometheus --tail=100 | grep -iE 'error|forbidden'"
    fi

    echo ""
}

# Test 8: Résumé de la stack de monitoring
test_monitoring_summary() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 8: Résumé de la stack de monitoring"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    log_info "État des composants dans le namespace monitoring :"
    kubectl get all -n monitoring

    echo ""
    log_info "Services exposés :"
    kubectl get svc -n monitoring

    echo ""
    log_info "ConfigMaps :"
    kubectl get configmap -n monitoring

    echo ""
    log_info "ServiceAccounts :"
    kubectl get sa -n monitoring

    echo ""
    log_info "Pour accéder aux interfaces web :"
    echo "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "             http://localhost:9090"
    echo ""
    echo "  Grafana:    kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "             http://localhost:3000 (admin/admin123)"
    echo ""

    log_success "Résumé affiché"
}

# Test 9: Stack EFK (Elasticsearch, Fluentd, Kibana)
#
# Contrairement aux tests précédents, celui-ci déploie lui-même les manifests
# au lieu de supposer qu'ils sont déjà appliqués : cette stack n'était testée
# nulle part (ni ici avant cet ajout, ni dans le workflow CI) et un manifest
# cassé n'a été détecté que par un déploiement manuel après merge en
# production. Voir tp04/09-elasticsearch.yaml pour le contexte du bug corrigé
# (readOnlyRootFilesystem sans volume inscriptible pour le keystore).
test_efk_stack() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "  Test 9: Stack EFK (Elasticsearch, Fluentd, Kibana)"
    log_info "═══════════════════════════════════════════════════════"
    echo ""

    log_info "Vérification de vm.max_map_count (requis par Elasticsearch)..."
    if command -v minikube &> /dev/null && minikube status &>/dev/null; then
        MAX_MAP_COUNT=$(minikube ssh -- 'sysctl -n vm.max_map_count' 2>/dev/null | tr -d '\r')
        if [ "$MAX_MAP_COUNT" -lt 262144 ] 2>/dev/null; then
            log_error "vm.max_map_count=$MAX_MAP_COUNT, doit être >= 262144"
            log_fix "minikube ssh -- 'sudo sysctl -w vm.max_map_count=262144'"
            return 1
        fi
        log_success "vm.max_map_count OK ($MAX_MAP_COUNT)"
    else
        log_warning "Pas sur minikube, vérifiez vm.max_map_count manuellement sur vos nœuds"
    fi

    log_info "Déploiement d'Elasticsearch..."
    kubectl apply -f "$SCRIPT_DIR/09-elasticsearch.yaml" &>/dev/null

    log_info "Attente d'Elasticsearch (jusqu'à 3 min)..."
    if kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=180s &>/dev/null; then
        log_success "Pod Elasticsearch est Ready"
    else
        log_error "Pod Elasticsearch pas prêt après 3 minutes"
        kubectl get pods -n logging
        log_fix "Commandes de diagnostic :"
        echo "  kubectl describe pod -n logging -l app=elasticsearch"
        echo "  kubectl logs -n logging -l app=elasticsearch"
        return 1
    fi

    log_info "Vérification de la santé du cluster Elasticsearch..."
    kubectl port-forward -n logging svc/elasticsearch 9200:9200 &>/dev/null &
    ES_PID=$!
    sleep 3
    ES_HEALTH=$(curl -s http://localhost:9200/_cluster/health 2>/dev/null)
    kill $ES_PID 2>/dev/null || true
    if echo "$ES_HEALTH" | jq -e '.status == "green" or .status == "yellow"' &>/dev/null; then
        log_success "Elasticsearch cluster health: $(echo "$ES_HEALTH" | jq -r '.status')"
    else
        log_error "Elasticsearch cluster health KO ou injoignable"
        echo "$ES_HEALTH"
        return 1
    fi

    log_info "Déploiement de Kibana..."
    kubectl apply -f "$SCRIPT_DIR/10-kibana.yaml" &>/dev/null
    if kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=180s &>/dev/null; then
        log_success "Pod Kibana est Ready"
    else
        log_error "Pod Kibana pas prêt après 3 minutes"
        kubectl get pods -n logging
        return 1
    fi

    log_info "Déploiement de Fluentd..."
    kubectl apply -f "$SCRIPT_DIR/08-fluentd-daemonset.yaml" &>/dev/null
    if kubectl rollout status daemonset/fluentd -n kube-system --timeout=120s &>/dev/null; then
        log_success "DaemonSet Fluentd est Ready"
    else
        log_error "DaemonSet Fluentd pas prêt après 2 minutes"
        kubectl get pods -n kube-system -l app=fluentd
        kubectl logs -n kube-system -l app=fluentd --tail=30
        return 1
    fi

    log_info "Vérification qu'un index fluentd apparaît dans Elasticsearch (jusqu'à 2 min)..."
    kubectl port-forward -n logging svc/elasticsearch 9200:9200 &>/dev/null &
    ES_PID=$!
    sleep 3
    FLUENTD_INDEX_FOUND=false
    for i in $(seq 1 12); do
        if curl -s http://localhost:9200/_cat/indices?v 2>/dev/null | grep -q fluentd; then
            FLUENTD_INDEX_FOUND=true
            break
        fi
        sleep 10
    done
    kill $ES_PID 2>/dev/null || true
    if [ "$FLUENTD_INDEX_FOUND" = true ]; then
        log_success "Index fluentd-* trouvé dans Elasticsearch — le pipeline de logs fonctionne"
    else
        log_error "Aucun index fluentd-* après 2 minutes — le pipeline de logs ne fonctionne pas"
        log_fix "Commandes de diagnostic :"
        echo "  kubectl logs -n kube-system -l app=fluentd --tail=50"
        return 1
    fi

    echo ""
}

# Fonction principale
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     Test Automatisé - TP4 Monitoring et Logs                 ║"
    echo "║     Kubernetes Formation                                      ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    # Vérifier les prérequis
    check_prerequisites

    # Exécuter les tests
    test_metrics_server
    test_hpa
    test_prometheus_deployment
    test_prometheus_rbac
    test_prometheus_metrics
    test_grafana
    test_prometheus_config
    test_monitoring_summary
    test_efk_stack

    # Afficher le résumé final
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    RÉSUMÉ DES TESTS                           ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Tests réussis : $TESTS_PASSED"
    echo "  Tests échoués : $TESTS_FAILED"
    echo "  Total         : $TESTS_TOTAL"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "✅ Tous les tests sont passés avec succès !"
        echo ""
        log_info "Prochaines étapes suggérées :"
        echo "  1. Accéder à Prometheus : kubectl port-forward -n monitoring svc/prometheus 9090:9090"
        echo "  2. Accéder à Grafana : kubectl port-forward -n monitoring svc/grafana 3000:3000"
        echo "  3. Importer des dashboards dans Grafana (ID: 315, 747, 6417)"
        echo "  4. Tester les requêtes PromQL dans Prometheus"
        echo "  5. Configurer des alertes personnalisées"
    else
        log_warning "⚠️  $TESTS_FAILED test(s) ont échoué"
        echo ""
        log_info "Consultez les messages d'erreur ci-dessus pour les corrections"
    fi

    echo ""
    log_info "Pour nettoyer les ressources de test :"
    echo "  ./test-tp4.sh cleanup"
    echo ""
}

# Gérer les arguments
if [ "$1" == "cleanup" ]; then
    cleanup
    exit 0
fi

# Gérer Ctrl+C (mais pas EXIT pour éviter cleanup automatique en fin normale)
trap cleanup INT TERM

# Exécuter le script
main

# Retourner le code approprié
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
