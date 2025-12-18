#!/bin/bash

set -e

echo "========================================="
echo "   Installation de Tekton CI/CD"
echo "========================================="
echo ""

# 1. Installer Tekton Pipelines
echo "1. Installation de Tekton Pipelines v0.37.0..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.37.0/release.yaml

echo "   Attente que Tekton Pipelines soit prêt..."
kubectl wait --for=condition=ready pod --all -n tekton-pipelines --timeout=300s

echo "   ✓ Tekton Pipelines installé"
echo ""

# 2. Installer Tekton Triggers
echo "2. Installation de Tekton Triggers v0.20.0..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.20.0/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.20.0/interceptors.yaml

echo "   ✓ Tekton Triggers installé"
echo ""

# 3. Installer Tekton Dashboard
echo "3. Installation du Tekton Dashboard v0.28.0..."
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/previous/v0.28.0/tekton-dashboard-release.yaml

echo "   Attente que le Dashboard soit prêt..."
sleep 10
kubectl wait --for=condition=ready pod -l app=tekton-dashboard -n tekton-pipelines --timeout=300s

echo "   ✓ Tekton Dashboard installé"
echo ""

# 4. Installer un registry Docker local
echo "4. Installation d'un registry Docker local..."
kubectl get deployment registry 2>/dev/null || kubectl create deployment registry --image=registry:2
kubectl get service registry 2>/dev/null || kubectl expose deployment registry --port=5000 --type=NodePort

echo "   ✓ Registry Docker local installé"
echo ""

# 5. Appliquer les Tasks et Pipelines
echo "5. Installation des Tasks et Pipelines..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -d "$SCRIPT_DIR/tasks" ]; then
    kubectl apply -f "$SCRIPT_DIR/tasks/"
    echo "   ✓ Tasks installées"
else
    echo "   ⚠ Dossier tasks/ non trouvé"
fi

if [ -d "$SCRIPT_DIR/pipelines" ]; then
    kubectl apply -f "$SCRIPT_DIR/pipelines/"
    echo "   ✓ Pipelines installés"
else
    echo "   ⚠ Dossier pipelines/ non trouvé"
fi

echo ""
echo "========================================="
echo "   Installation terminée avec succès!"
echo "========================================="
echo ""
echo "Pour accéder au Dashboard Tekton:"
echo "  kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097"
echo "  Puis ouvrir: http://localhost:9097"
echo ""
echo "Pour lister les Tasks et Pipelines:"
echo "  kubectl get tasks"
echo "  kubectl get pipelines"
echo ""
echo "Pour exécuter le pipeline CI:"
echo "  kubectl create -f tekton/runs/ci-pipelinerun-example.yaml"
echo ""
echo "Ou avec tkn CLI (si installé):"
echo "  tkn pipeline start ci-pipeline --showlog"
echo ""
echo "Pour plus d'informations, voir:"
echo "  cat ALTERNATIVE_SANS_GITHUB.md"
echo ""
