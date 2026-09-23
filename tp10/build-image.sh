#!/bin/bash

# Script de construction de l'image Docker TaskFlow Backend API
# Usage: ./build-image.sh [tag]
#
# Avec Minikube démarré : construit l'image DIRECTEMENT dans le cache d'images
# du nœud avec `minikube image build`. Cette commande fonctionne quel que soit
# le runtime du cluster (docker ou containerd).
#
# Pourquoi pas `eval $(minikube docker-env)` + `docker build` ? Depuis minikube
# v1.39.0, le runtime par défaut est containerd, même avec le driver docker.
# docker-env pointe alors le CLI docker vers un pont SSH expérimental
# (nerdctld), et BuildKit/buildx échoue à travers ce pont (erreurs du type
# "404 page not found"). `minikube image build` utilise le BuildKit du nœud :
# c'est la méthode utilisée par la CI (job test-tp10-synthesis).

set -e

# Variables
IMAGE_NAME="taskflow-backend"
TAG="${1:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

# Couleurs pour l'affichage
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  TaskFlow Backend API - Build Script                  ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}📦 Image: ${FULL_IMAGE}${NC}"
echo ""

# Vérifier les fichiers requis
echo "🔍 Vérification des fichiers..."
MISSING_FILES=0
for file in Dockerfile requirements.txt app.py; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}  ✗ Fichier manquant: $file${NC}"
        MISSING_FILES=1
    else
        echo -e "${GREEN}  ✓ $file${NC}"
    fi
done

if [ $MISSING_FILES -eq 1 ]; then
    echo ""
    echo -e "${RED}❌ Fichiers manquants détectés${NC}"
    echo -e "${YELLOW}💡 Assurez-vous d'exécuter ce script depuis le répertoire tp10/${NC}"
    exit 1
fi
echo ""

build_failed() {
    echo ""
    echo -e "${RED}❌ Erreur lors de la construction de l'image${NC}"
    echo ""
    echo -e "${YELLOW}💡 Conseils de dépannage:${NC}"
    echo "  - Vérifier la connexion internet (téléchargement de l'image python et des dépendances pip)"
    echo "  - Vérifier la syntaxe du Dockerfile"
    if [ "$1" = "minikube" ]; then
        echo "  - Relancer avec les logs détaillés : minikube image build -t ${FULL_IMAGE} . --alsologtostderr"
        echo "  - En dernier recours : docker build -t ${FULL_IMAGE} . && minikube image load ${FULL_IMAGE}"
    fi
    echo ""
    exit 1
}

# ─── Cas 1 : Minikube démarré → construire dans le nœud ─────────────────────
if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    RUNTIME=$(minikube profile list -o json 2>/dev/null \
        | grep -o '"ContainerRuntime":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}✅ Minikube détecté et démarré${NC} (runtime : ${RUNTIME:-inconnu})"
    echo "🏗️  Construction dans Minikube avec 'minikube image build'..."
    echo ""

    minikube image build -t "${FULL_IMAGE}" . || build_failed minikube

    echo ""
    echo "🔍 Vérification de la présence de l'image dans le cache de Minikube..."
    if ! minikube image ls | grep -q "${IMAGE_NAME}:${TAG}"; then
        echo -e "${RED}❌ L'image ${FULL_IMAGE} n'apparaît pas dans 'minikube image ls'${NC}"
        build_failed minikube
    fi
    minikube image ls | grep "${IMAGE_NAME}:${TAG}"
    echo ""
    echo -e "${GREEN}✅ Image construite et disponible dans Minikube: ${FULL_IMAGE}${NC}"
    echo ""
    echo -e "${YELLOW}📝 Pour déployer l'application:${NC}"
    echo "   ./deploy.sh"
    echo ""
    echo -e "${YELLOW}💡 Pourquoi ça suffit:${NC}"
    echo "   09b-backend-deployment.yaml utilise ${IMAGE_NAME}:latest avec"
    echo "   imagePullPolicy: Never : le kubelet prend l'image du cache du nœud."
    echo ""
    echo -e "${YELLOW}🧪 Pour exécuter les tests:${NC}"
    echo "   ./test-tp10.sh"
    echo ""
    exit 0
fi

# ─── Cas 2 : pas de Minikube démarré → Docker local ─────────────────────────
if command -v minikube &> /dev/null; then
    echo -e "${YELLOW}⚠️  Minikube est installé mais pas démarré${NC}"
else
    echo -e "${BLUE}ℹ️  Minikube non détecté${NC}"
fi
echo -e "${YELLOW}   Construction avec le Docker local${NC}"
echo ""

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker n'est pas installé${NC}"
    echo "Installation: https://docs.docker.com/get-docker/"
    echo "Ou démarrez Minikube (minikube start) et relancez ce script."
    exit 1
fi

docker build --tag "${FULL_IMAGE}" . || build_failed docker

echo ""
echo -e "${GREEN}✅ Image construite avec succès (Docker local): ${FULL_IMAGE}${NC}"
echo ""
echo -e "${YELLOW}⚠️  Cette image n'est PAS dans un cluster.${NC} Pour l'utiliser avec Minikube :"
echo "   minikube start"
echo "   minikube image load ${FULL_IMAGE}"
echo "   ./deploy.sh"
echo ""
echo -e "${YELLOW}💡 Pour tester l'image localement:${NC}"
echo "   docker run --rm -p 5000:5000 \\"
echo "     -e DATABASE_HOST=localhost \\"
echo "     -e DATABASE_USER=taskflow \\"
echo "     -e DATABASE_PASSWORD=taskflow2024 \\"
echo "     ${FULL_IMAGE}"
echo ""
