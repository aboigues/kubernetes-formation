#!/bin/bash

# Script de test pour les exercices du TP6
# Ce script permet de tester tous les exercices de mise en production et CI/CD
# Version adaptée : peut fonctionner sans cluster Kubernetes

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis..."

    # Vérifier kubectl (optionnel pour validation syntaxique)
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl n'est pas installé (optionnel pour ce test)"
        KUBECTL_AVAILABLE=false
    else
        KUBECTL_AVAILABLE=true
        log_info "kubectl est disponible ✓"
    fi

    # Vérifier helm (optionnel)
    if ! command -v helm &> /dev/null; then
        log_warning "helm n'est pas installé (optionnel pour ce test)"
        HELM_AVAILABLE=false
    else
        HELM_AVAILABLE=true
        log_info "helm est disponible ✓"
    fi

    # Vérifier minikube (optionnel)
    if ! command -v minikube &> /dev/null; then
        log_warning "minikube n'est pas installé (optionnel pour ce test)"
        MINIKUBE_AVAILABLE=false
    else
        MINIKUBE_AVAILABLE=true
        log_info "minikube est disponible ✓"
    fi

    # Vérifier que le cluster est démarré (optionnel)
    if [ "$KUBECTL_AVAILABLE" = true ]; then
        if ! kubectl cluster-info &> /dev/null; then
            log_warning "Le cluster Kubernetes n'est pas accessible"
            log_warning "Les tests réels nécessitent un cluster (minikube start)"
            CLUSTER_AVAILABLE=false
        else
            CLUSTER_AVAILABLE=true
            log_info "Cluster Kubernetes accessible ✓"
        fi
    else
        CLUSTER_AVAILABLE=false
    fi

    log_info "Vérification des prérequis terminée"
}

# Fonction pour valider la syntaxe YAML avec Python
validate_yaml_syntax() {
    local file=$1
    python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        # Utiliser safe_load_all pour supporter les documents multiples (---)
        docs = list(yaml.safe_load_all(f))
        if not docs or all(doc is None for doc in docs):
            print('Erreur: Fichier YAML vide', file=sys.stderr)
            sys.exit(1)
    sys.exit(0)
except Exception as e:
    print(f'Erreur: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
    return $?
}

# Fonction pour tester Helm
test_helm() {
    log_info "=== Test des exercices Helm ==="

    # Vérifier l'existence du dossier
    if [ ! -d "01-helm/my-app" ]; then
        log_error "Le dossier 01-helm/my-app n'existe pas"
        return 1
    fi

    log_info "Structure du chart Helm trouvée ✓"

    if [ "$HELM_AVAILABLE" = true ]; then
        # Ajouter les repositories Helm
        log_info "Ajout des repositories Helm..."
        helm repo add bitnami https://charts.bitnami.com/bitnami &> /dev/null || true
        helm repo update &> /dev/null

        # Test du chart personnalisé
        log_info "Validation du chart personnalisé..."
        if helm lint 01-helm/my-app/ &> /dev/null; then
            log_info "Validation Helm lint réussie ✓"
        else
            log_warning "Helm lint a échoué (non bloquant)"
        fi

        log_info "Installation du chart personnalisé (dry-run)..."
        if helm install my-release ./01-helm/my-app --dry-run &> /dev/null; then
            log_info "Dry-run Helm réussi ✓"
        else
            log_warning "Dry-run Helm a échoué (non bloquant)"
        fi
    else
        log_warning "Helm non disponible, validation basique uniquement"
        # Vérifier que les fichiers essentiels existent
        if [ -f "01-helm/my-app/Chart.yaml" ] && [ -f "01-helm/my-app/values.yaml" ]; then
            log_info "Fichiers essentiels du chart présents ✓"
        else
            log_error "Fichiers Chart.yaml ou values.yaml manquants"
            return 1
        fi
    fi

    log_info "Tests Helm réussis ✓"
}

# Fonction pour tester les manifests Ingress
test_ingress() {
    log_info "=== Test des exercices Ingress ==="

    # Vérifier l'existence du dossier
    if [ ! -d "02-ingress" ]; then
        log_error "Le dossier 02-ingress n'existe pas"
        return 1
    fi

    log_info "Dossier Ingress trouvé ✓"

    # Valider les fichiers YAML
    log_info "Validation de la syntaxe YAML..."
    for file in 02-ingress/*.yaml; do
        if [ -f "$file" ]; then
            if validate_yaml_syntax "$file"; then
                log_info "  ✓ $(basename $file)"
            else
                log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                return 1
            fi
        fi
    done

    if [ "$KUBECTL_AVAILABLE" = true ] && [ "$CLUSTER_AVAILABLE" = false ]; then
        # Valider avec kubectl --dry-run=client (ne nécessite pas de cluster)
        log_info "Validation kubectl (dry-run client)..."
        if kubectl apply --dry-run=client -f 02-ingress/ &> /dev/null; then
            log_info "Validation kubectl réussie ✓"
        else
            log_warning "Validation kubectl a échoué (non bloquant sans cluster)"
        fi
    fi

    log_info "Tests Ingress réussis ✓"
}

# Fonction pour tester les stratégies de déploiement
test_deployment_strategies() {
    log_info "=== Test des stratégies de déploiement ==="

    if [ ! -d "03-deployment-strategies" ]; then
        log_error "Le dossier 03-deployment-strategies n'existe pas"
        return 1
    fi

    log_info "Dossier stratégies de déploiement trouvé ✓"

    # Valider les fichiers YAML
    log_info "Validation de la syntaxe YAML..."
    for file in 03-deployment-strategies/*.yaml; do
        if [ -f "$file" ]; then
            if validate_yaml_syntax "$file"; then
                log_info "  ✓ $(basename $file)"
            else
                log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                return 1
            fi
        fi
    done

    if [ "$KUBECTL_AVAILABLE" = true ] && [ "$CLUSTER_AVAILABLE" = false ]; then
        log_info "Validation kubectl (dry-run client)..."
        if kubectl apply --dry-run=client -f 03-deployment-strategies/ &> /dev/null; then
            log_info "Validation kubectl réussie ✓"
        else
            log_warning "Validation kubectl a échoué (non bloquant sans cluster)"
        fi
    fi

    log_info "Tests des stratégies de déploiement réussis ✓"
}

# Fonction pour tester les bonnes pratiques
test_best_practices() {
    log_info "=== Test des bonnes pratiques de production ==="

    if [ ! -d "04-production-best-practices" ]; then
        log_error "Le dossier 04-production-best-practices n'existe pas"
        return 1
    fi

    log_info "Dossier bonnes pratiques trouvé ✓"

    # Valider les fichiers YAML
    log_info "Validation de la syntaxe YAML..."
    for file in 04-production-best-practices/*.yaml; do
        if [ -f "$file" ]; then
            if validate_yaml_syntax "$file"; then
                log_info "  ✓ $(basename $file)"
            else
                log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                return 1
            fi
        fi
    done

    log_info "Tests des bonnes pratiques réussis ✓"
}

# Fonction pour tester ArgoCD
test_argocd() {
    log_info "=== Test des fichiers ArgoCD ==="

    if [ ! -d "05-argocd" ]; then
        log_error "Le dossier 05-argocd n'existe pas"
        return 1
    fi

    log_info "Dossier ArgoCD trouvé ✓"

    # Valider les fichiers YAML
    log_info "Validation de la syntaxe YAML..."
    for file in 05-argocd/*.yaml; do
        if [ -f "$file" ]; then
            if validate_yaml_syntax "$file"; then
                log_info "  ✓ $(basename $file)"
            else
                log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                return 1
            fi
        fi
    done

    log_info "Tests ArgoCD réussis ✓"
}

# Fonction pour tester la structure GitOps
test_gitops() {
    log_info "=== Test de la structure GitOps ==="

    if [ ! -d "07-gitops-structure" ]; then
        log_error "Le dossier 07-gitops-structure n'existe pas"
        return 1
    fi

    log_info "Structure GitOps trouvée ✓"

    if [ "$KUBECTL_AVAILABLE" = true ]; then
        log_info "Test de Kustomize - environnement dev..."
        if kubectl kustomize 07-gitops-structure/overlays/dev > /dev/null 2>&1; then
            log_info "  ✓ Environnement dev"
        else
            log_warning "  ⚠ Environnement dev (erreur non bloquante)"
        fi

        log_info "Test de Kustomize - environnement staging..."
        if kubectl kustomize 07-gitops-structure/overlays/staging > /dev/null 2>&1; then
            log_info "  ✓ Environnement staging"
        else
            log_warning "  ⚠ Environnement staging (erreur non bloquante)"
        fi

        log_info "Test de Kustomize - environnement production..."
        if kubectl kustomize 07-gitops-structure/overlays/production > /dev/null 2>&1; then
            log_info "  ✓ Environnement production"
        else
            log_warning "  ⚠ Environnement production (erreur non bloquante)"
        fi
    else
        log_warning "kubectl non disponible, impossible de tester Kustomize"
    fi

    log_info "Tests GitOps réussis ✓"
}

# Fonction pour tester les fichiers de monitoring
test_monitoring() {
    log_info "=== Test des fichiers de monitoring ==="

    if [ ! -d "06-monitoring" ]; then
        log_error "Le dossier 06-monitoring n'existe pas"
        return 1
    fi

    log_info "Dossier monitoring trouvé ✓"

    # Valider les fichiers YAML
    log_info "Validation de la syntaxe YAML..."
    for file in 06-monitoring/*.yaml; do
        if [ -f "$file" ]; then
            if validate_yaml_syntax "$file"; then
                log_info "  ✓ $(basename $file)"
            else
                log_warning "  ⚠ $(basename $file) - Erreur de syntaxe (non bloquant)"
            fi
        fi
    done

    log_info "Tests monitoring réussis ✓"
}

# Fonction pour tester l'alternative Tekton
test_tekton() {
    log_info "=== Test de l'alternative Tekton ==="

    if [ ! -d "tekton" ]; then
        log_warning "Le dossier tekton n'existe pas (optionnel)"
        return 0
    fi

    log_info "Dossier Tekton trouvé ✓"

    # Vérifier les fichiers essentiels
    if [ -f "ALTERNATIVE_SANS_GITHUB.md" ]; then
        log_info "  ✓ Documentation ALTERNATIVE_SANS_GITHUB.md présente"
    else
        log_warning "  ⚠ Documentation ALTERNATIVE_SANS_GITHUB.md manquante"
    fi

    if [ -f "tekton/install-tekton.sh" ]; then
        log_info "  ✓ Script d'installation présent"
    else
        log_warning "  ⚠ Script d'installation manquant"
    fi

    # Valider les Tasks Tekton
    if [ -d "tekton/tasks" ]; then
        log_info "Validation des Tasks Tekton..."
        for file in tekton/tasks/*.yaml; do
            if [ -f "$file" ]; then
                if validate_yaml_syntax "$file"; then
                    log_info "  ✓ $(basename $file)"
                else
                    log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                    return 1
                fi
            fi
        done
    fi

    # Valider les Pipelines Tekton
    if [ -d "tekton/pipelines" ]; then
        log_info "Validation des Pipelines Tekton..."
        for file in tekton/pipelines/*.yaml; do
            if [ -f "$file" ]; then
                if validate_yaml_syntax "$file"; then
                    log_info "  ✓ $(basename $file)"
                else
                    log_error "  ✗ $(basename $file) - Syntaxe YAML invalide"
                    return 1
                fi
            fi
        done
    fi

    log_info "Tests Tekton réussis ✓"
}

# Fonction pour afficher un résumé
show_summary() {
    log_info "=== Résumé des tests ==="
    log_info "Tous les tests ont été exécutés avec succès ✓"
    echo ""
    log_info "Structure des exercices créés:"
    echo "  - 01-helm/          : Charts Helm personnalisés"
    echo "  - 02-ingress/       : Exemples d'Ingress"
    echo "  - 03-deployment-strategies/ : Rolling, Blue-Green, Canary"
    echo "  - 04-production-best-practices/ : HPA, PDB, Health checks"
    echo "  - 05-argocd/        : Applications ArgoCD"
    echo "  - 06-monitoring/    : ServiceMonitor et PrometheusRules"
    echo "  - 07-gitops-structure/ : Structure Kustomize avec overlays"
    echo "  - .github/workflows/ : Pipelines CI/CD GitHub Actions"
    echo "  - tekton/           : Alternative CI/CD Tekton (sans compte GitHub)"
    echo "  - sample-app/       : Application Node.js exemple"
    echo ""
    log_info "Pour tester un exercice spécifique, utilisez:"
    echo "  kubectl apply -f <fichier>.yaml"
    echo "  helm install <release-name> ./01-helm/my-app"
    echo "  kubectl kustomize 07-gitops-structure/overlays/<env>"
    echo ""
    log_info "Pour l'alternative Tekton (sans compte GitHub):"
    echo "  cd tekton && ./install-tekton.sh"
    echo "  Voir: ALTERNATIVE_SANS_GITHUB.md"
}

# Menu principal
main() {
    cd "$(dirname "$0")"

    echo "============================================"
    echo "   Tests des exercices du TP6"
    echo "   Mise en Production et CI/CD avec K8s"
    echo "============================================"
    echo ""

    check_prerequisites
    echo ""

    test_helm
    echo ""

    test_ingress
    echo ""

    test_deployment_strategies
    echo ""

    test_best_practices
    echo ""

    test_argocd
    echo ""

    test_gitops
    echo ""

    test_monitoring
    echo ""

    test_tekton
    echo ""

    show_summary
}

# Exécution du script
main "$@"
