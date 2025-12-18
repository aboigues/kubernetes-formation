#!/bin/bash

# Script de validation de l'installation Tekton
# Ce script vérifie que tous les composants sont correctement installés

set -e

echo "============================================================"
echo "  VALIDATION DE L'INSTALLATION TEKTON"
echo "============================================================"
echo ""

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Fonction pour afficher un succès
success() {
    echo "  ✓ $1"
}

# Fonction pour afficher un warning
warning() {
    echo "  ⚠ $1"
}

# Fonction pour afficher une erreur
error() {
    echo "  ✗ $1"
}

ERRORS=0

# 1. Vérifier kubectl
echo "1️⃣  Vérification de kubectl"
echo "------------------------------------------------------------"
if command_exists kubectl; then
    success "kubectl est installé"
    kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || true
else
    error "kubectl n'est pas installé"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 2. Vérifier la connexion au cluster
echo "2️⃣  Vérification de la connexion au cluster"
echo "------------------------------------------------------------"
if kubectl cluster-info >/dev/null 2>&1; then
    success "Connexion au cluster établie"
    kubectl cluster-info | head -1
else
    error "Impossible de se connecter au cluster"
    warning "Assurez-vous que minikube est démarré: minikube start"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 3. Vérifier Tekton Pipelines
echo "3️⃣  Vérification de Tekton Pipelines"
echo "------------------------------------------------------------"
if kubectl get namespace tekton-pipelines >/dev/null 2>&1; then
    success "Namespace tekton-pipelines existe"

    PODS=$(kubectl get pods -n tekton-pipelines --no-headers 2>/dev/null | wc -l)
    READY=$(kubectl get pods -n tekton-pipelines --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

    if [ "$PODS" -gt 0 ]; then
        success "Tekton Pipelines installé ($READY/$PODS pods prêts)"
    else
        error "Aucun pod Tekton trouvé"
        ERRORS=$((ERRORS + 1))
    fi
else
    error "Tekton Pipelines n'est pas installé"
    warning "Exécutez: ./install-tekton.sh"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 4. Vérifier les Tasks
echo "4️⃣  Vérification des Tasks Tekton"
echo "------------------------------------------------------------"
EXPECTED_TASKS=("git-clone" "npm-test" "docker-build" "trivy-scan" "helm-deploy" "kubectl-verify")
FOUND=0

for task in "${EXPECTED_TASKS[@]}"; do
    if kubectl get task "$task" >/dev/null 2>&1; then
        success "Task '$task' installée"
        FOUND=$((FOUND + 1))
    else
        error "Task '$task' manquante"
    fi
done

if [ "$FOUND" -eq "${#EXPECTED_TASKS[@]}" ]; then
    success "Toutes les Tasks sont installées (${FOUND}/${#EXPECTED_TASKS[@]})"
else
    warning "Certaines Tasks sont manquantes (${FOUND}/${#EXPECTED_TASKS[@]})"
    warning "Exécutez: kubectl apply -f tasks/"
fi
echo ""

# 5. Vérifier les Pipelines
echo "5️⃣  Vérification des Pipelines Tekton"
echo "------------------------------------------------------------"
EXPECTED_PIPELINES=("ci-pipeline" "cd-pipeline")
FOUND=0

for pipeline in "${EXPECTED_PIPELINES[@]}"; do
    if kubectl get pipeline "$pipeline" >/dev/null 2>&1; then
        success "Pipeline '$pipeline' installé"
        FOUND=$((FOUND + 1))
    else
        error "Pipeline '$pipeline' manquant"
    fi
done

if [ "$FOUND" -eq "${#EXPECTED_PIPELINES[@]}" ]; then
    success "Tous les Pipelines sont installés (${FOUND}/${#EXPECTED_PIPELINES[@]})"
else
    warning "Certains Pipelines sont manquants (${FOUND}/${#EXPECTED_PIPELINES[@]})"
    warning "Exécutez: kubectl apply -f pipelines/"
fi
echo ""

# 6. Vérifier le Dashboard (optionnel)
echo "6️⃣  Vérification du Dashboard Tekton (optionnel)"
echo "------------------------------------------------------------"
if kubectl get deployment tekton-dashboard -n tekton-pipelines >/dev/null 2>&1; then
    success "Dashboard Tekton installé"
    REPLICAS=$(kubectl get deployment tekton-dashboard -n tekton-pipelines -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    if [ "$REPLICAS" -gt 0 ]; then
        success "Dashboard prêt"
        echo "  Accédez au Dashboard avec:"
        echo "    kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097"
    else
        warning "Dashboard installé mais pas prêt"
    fi
else
    warning "Dashboard Tekton non installé (optionnel)"
fi
echo ""

# 7. Vérifier le registry local
echo "7️⃣  Vérification du registry Docker local"
echo "------------------------------------------------------------"
if kubectl get service registry >/dev/null 2>&1; then
    success "Registry Docker local installé"
    PORT=$(kubectl get service registry -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    success "Port du registry: $PORT"
else
    warning "Registry Docker local non installé"
    warning "Vous pouvez utiliser un registry externe"
fi
echo ""

# Résumé
echo "============================================================"
if [ "$ERRORS" -eq 0 ]; then
    echo "  ✅ VALIDATION RÉUSSIE!"
    echo "============================================================"
    echo ""
    echo "🎉 Votre installation Tekton est complète et fonctionnelle!"
    echo ""
    echo "Prochaines étapes:"
    echo "  1. Modifier les exemples dans runs/ avec vos paramètres"
    echo "  2. Exécuter un pipeline:"
    echo "     kubectl create -f runs/ci-pipelinerun-example.yaml"
    echo "  3. Suivre les logs:"
    echo "     kubectl logs -l tekton.dev/pipelineRun -f"
    echo ""
else
    echo "  ⚠ VALIDATION PARTIELLE ($ERRORS erreur(s))"
    echo "============================================================"
    echo ""
    echo "Certains composants sont manquants ou non configurés."
    echo "Consultez les messages ci-dessus pour les détails."
    echo ""
    echo "Pour installer tous les composants:"
    echo "  ./install-tekton.sh"
    echo ""
fi
