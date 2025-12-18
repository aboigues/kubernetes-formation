#!/bin/bash
# test-tp9.sh - Script de validation du TP9
# Teste la structure, les scripts et les manifests

set -e

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Fonctions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "  ℹ $1"
}

# Vérifier qu'on est dans le bon répertoire
if [ ! -f "README.md" ] || [ ! -d "examples" ]; then
    echo "Erreur : Exécutez ce script depuis le répertoire tp9"
    exit 1
fi

echo ""
print_header "Tests de validation du TP9"
echo ""

# ============================================
# Test 1 : Structure du TP
# ============================================
print_header "1. Vérification de la structure"
echo ""

print_test "Fichier README.md présent"
if [ -f "README.md" ]; then
    print_success "README.md trouvé ($(wc -l < README.md) lignes)"
else
    print_error "README.md manquant"
fi

print_test "Répertoire examples/ présent"
if [ -d "examples" ]; then
    EXAMPLE_COUNT=$(ls examples/*.yaml examples/*.sh 2>/dev/null | wc -l)
    print_success "examples/ trouvé ($EXAMPLE_COUNT fichiers)"
else
    print_error "examples/ manquant"
fi

print_test "Répertoire exercices/ présent"
if [ -d "exercices" ]; then
    EXERCICE_COUNT=$(ls exercices/* 2>/dev/null | wc -l)
    print_success "exercices/ trouvé ($EXERCICE_COUNT fichiers)"
else
    print_error "exercices/ manquant"
fi

# ============================================
# Test 2 : Contenu du README
# ============================================
echo ""
print_header "2. Validation du README"
echo ""

print_test "Sections principales présentes"
REQUIRED_SECTIONS=(
    "Partie 1 : Architecture multi-noeud"
    "Partie 2 : Installation d'un cluster multi-noeud avec kubeadm"
    "Partie 3 : Gestion des nœuds"
    "Partie 4 : Haute disponibilité du Control Plane"
    "Partie 5 : Labels, Selectors et NodeSelectors"
    "Partie 6 : Taints et Tolerations"
    "Partie 7 : Affinité et Anti-Affinité"
    "Partie 8 : Maintenance et Upgrade des nœuds"
    "Partie 9 : Monitoring et Troubleshooting"
)

SECTIONS_FOUND=0
for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "$section" README.md; then
        SECTIONS_FOUND=$((SECTIONS_FOUND + 1))
    fi
done

if [ $SECTIONS_FOUND -eq ${#REQUIRED_SECTIONS[@]} ]; then
    print_success "Toutes les 9 parties principales trouvées"
else
    print_error "Seulement $SECTIONS_FOUND/9 parties trouvées"
fi

print_test "Section de création de nœuds présente"
if grep -q "2.0 Création et provisionnement des nœuds" README.md; then
    print_success "Section 2.0 trouvée"
else
    print_error "Section 2.0 manquante"
fi

print_test "Section de rattachement des workers présente"
if grep -q "2.5.1 Comprendre le processus de join" README.md; then
    print_success "Section 2.5 détaillée trouvée"
else
    print_error "Section 2.5 détaillée manquante"
fi

print_test "Exercices pratiques mentionnés"
if grep -q "Exercice 1 : Déploiement HA complet" README.md; then
    print_success "Exercices trouvés dans le README"
else
    print_error "Exercices non trouvés"
fi

# ============================================
# Test 3 : Validation des scripts bash
# ============================================
echo ""
print_header "3. Validation des scripts bash"
echo ""

# Fonction pour tester un script
test_bash_script() {
    local script=$1
    local script_name=$(basename $script)

    print_test "Syntaxe de $script_name"

    if [ ! -f "$script" ]; then
        print_error "Fichier $script non trouvé"
        return
    fi

    if [ ! -x "$script" ]; then
        print_error "$script n'est pas exécutable"
        return
    fi

    # Vérifier la syntaxe bash
    if bash -n "$script" 2>/dev/null; then
        print_success "Syntaxe valide"
    else
        print_error "Erreur de syntaxe"
        return
    fi

    # Vérifier le shebang
    if head -n1 "$script" | grep -q "^#!/bin/bash"; then
        print_success "Shebang correct"
    else
        print_error "Shebang manquant ou incorrect"
    fi

    # Vérifier les bonnes pratiques
    if grep -q "set -e" "$script"; then
        print_info "Utilise 'set -e' (bonne pratique)"
    fi
}

# Tester tous les scripts bash
for script in examples/*.sh exercices/*.sh; do
    if [ -f "$script" ]; then
        test_bash_script "$script"
    fi
done

# ============================================
# Test 4 : Validation des manifests YAML
# ============================================
echo ""
print_header "4. Validation des manifests YAML"
echo ""

# Vérifier que kubectl/kubeadm sont disponibles pour la validation
if command -v kubectl &> /dev/null; then
    KUBECTL_AVAILABLE=true
    print_info "kubectl disponible pour validation"
else
    KUBECTL_AVAILABLE=false
    print_info "kubectl non disponible, validation basique seulement"
fi

# Fonction pour tester un manifest YAML
test_yaml_manifest() {
    local yaml_file=$1
    local yaml_name=$(basename $yaml_file)

    print_test "Validation de $yaml_name"

    if [ ! -f "$yaml_file" ]; then
        print_error "Fichier $yaml_file non trouvé"
        return
    fi

    # Test 1 : Syntaxe YAML basique
    if python3 -c "import yaml; yaml.safe_load_all(open('$yaml_file'))" 2>/dev/null; then
        print_success "Syntaxe YAML valide"
    else
        print_error "Erreur de syntaxe YAML"
        return
    fi

    # Test 2 : Validation Kubernetes (si kubectl disponible)
    if [ "$KUBECTL_AVAILABLE" = true ]; then
        if kubectl apply --dry-run=client -f "$yaml_file" &>/dev/null; then
            print_success "Manifests Kubernetes valides"
        else
            print_error "Erreurs de validation Kubernetes"
        fi
    fi

    # Test 3 : Vérifier les champs requis
    local resource_count=$(grep -c "^kind:" "$yaml_file" 2>/dev/null || echo 0)
    if [ $resource_count -gt 0 ]; then
        print_info "$resource_count ressource(s) définie(s)"
    fi
}

# Tester tous les YAML
for yaml in examples/*.yaml exercices/*.yaml; do
    if [ -f "$yaml" ]; then
        test_yaml_manifest "$yaml"
    fi
done

# ============================================
# Test 5 : Contenu des exemples
# ============================================
echo ""
print_header "5. Vérification du contenu des exemples"
echo ""

print_test "Exemples d'affinité de nœuds"
if [ -f "examples/node-affinity-examples.yaml" ]; then
    affinity_count=$(grep -c "nodeAffinity:" examples/node-affinity-examples.yaml)
    print_success "$affinity_count exemple(s) d'affinité trouvé(s)"
else
    print_error "Fichier node-affinity-examples.yaml manquant"
fi

print_test "Exemples d'affinité de pods"
if [ -f "examples/pod-affinity-examples.yaml" ]; then
    pod_affinity_count=$(grep -c "podAffinity:\|podAntiAffinity:" examples/pod-affinity-examples.yaml)
    print_success "$pod_affinity_count exemple(s) d'affinité/anti-affinité de pods"
else
    print_error "Fichier pod-affinity-examples.yaml manquant"
fi

print_test "Exemples de taints et tolerations"
if [ -f "examples/taints-tolerations-examples.yaml" ]; then
    toleration_count=$(grep -c "tolerations:" examples/taints-tolerations-examples.yaml)
    print_success "$toleration_count exemple(s) de tolerations"
else
    print_error "Fichier taints-tolerations-examples.yaml manquant"
fi

print_test "Exemples de PodDisruptionBudget"
if [ -f "examples/poddisruptionbudget-examples.yaml" ]; then
    pdb_count=$(grep -c "kind: PodDisruptionBudget" examples/poddisruptionbudget-examples.yaml)
    print_success "$pdb_count PodDisruptionBudget(s) défini(s)"
else
    print_error "Fichier poddisruptionbudget-examples.yaml manquant"
fi

# ============================================
# Test 6 : Scripts d'automatisation
# ============================================
echo ""
print_header "6. Vérification des scripts d'automatisation"
echo ""

print_test "Script add-worker-node.sh"
if [ -f "examples/add-worker-node.sh" ]; then
    if grep -q "kubeadm token create" examples/add-worker-node.sh; then
        print_success "Script contient la génération de token"
    else
        print_error "Script incomplet"
    fi

    if grep -q "ssh.*kubeadm join" examples/add-worker-node.sh; then
        print_success "Script contient le join via SSH"
    fi
else
    print_error "Script add-worker-node.sh manquant"
fi

print_test "Script prepare-node.sh"
if [ -f "examples/prepare-node.sh" ]; then
    if grep -q "containerd" examples/prepare-node.sh; then
        print_success "Script installe containerd"
    fi

    if grep -q "kubeadm.*kubelet.*kubectl" examples/prepare-node.sh; then
        print_success "Script installe les outils Kubernetes"
    fi

    if grep -q "swapoff" examples/prepare-node.sh; then
        print_success "Script désactive le swap"
    fi
else
    print_error "Script prepare-node.sh manquant"
fi

# ============================================
# Test 7 : Exercices
# ============================================
echo ""
print_header "7. Vérification des exercices"
echo ""

print_test "Exercice 1 : Déploiement HA"
if [ -f "exercices/exercice1-ha-deployment.yaml" ]; then
    tier_count=$(grep -c "tier:" exercices/exercice1-ha-deployment.yaml)
    print_success "Application 3-tiers ($tier_count tiers définis)"

    if grep -q "PodDisruptionBudget" exercices/exercice1-ha-deployment.yaml; then
        print_success "PodDisruptionBudgets inclus"
    fi
else
    print_error "Exercice 1 manquant"
fi

print_test "Exercice 2 : Script de maintenance"
if [ -f "exercices/exercice2-maintenance.sh" ]; then
    if grep -q "kubectl cordon" exercices/exercice2-maintenance.sh; then
        print_success "Script utilise cordon"
    fi
    if grep -q "kubectl drain" exercices/exercice2-maintenance.sh; then
        print_success "Script utilise drain"
    fi
else
    print_error "Exercice 2 manquant"
fi

print_test "Exercice 3 : Isolation"
if [ -f "exercices/exercice3-isolation.yaml" ]; then
    env_count=$(grep -c "environment:" exercices/exercice3-isolation.yaml)
    print_success "Isolation par environnement ($env_count occurrences)"
else
    print_error "Exercice 3 manquant"
fi

print_test "Exercice 5 : Guide de troubleshooting"
if [ -f "exercices/exercice5-troubleshooting.md" ]; then
    scenario_count=$(grep -c "^### Scénario" exercices/exercice5-troubleshooting.md)
    print_success "$scenario_count scénarios de troubleshooting"
else
    print_error "Exercice 5 manquant"
fi

# ============================================
# Test 8 : Concepts avancés
# ============================================
echo ""
print_header "8. Vérification des concepts avancés"
echo ""

print_test "Documentation sur kubeadm"
if grep -q "kubeadm init" README.md && grep -q "kubeadm join" README.md; then
    print_success "Documentation kubeadm complète"
else
    print_error "Documentation kubeadm incomplète"
fi

print_test "Haute disponibilité (HA)"
if grep -q "control plane" README.md && grep -q "etcd" README.md; then
    print_success "Documentation HA présente"
else
    print_error "Documentation HA manquante"
fi

print_test "Load balancer"
if grep -q "HAProxy" README.md || grep -q "load balancer" README.md; then
    print_success "Load balancing documenté"
else
    print_error "Load balancing non documenté"
fi

print_test "Backup et restore etcd"
if grep -q "etcdctl snapshot" README.md; then
    print_success "Backup etcd documenté"
else
    print_error "Backup etcd non documenté"
fi

# ============================================
# Rapport final
# ============================================
echo ""
print_header "Rapport de validation"
echo ""

echo "Tests exécutés  : $TESTS_TOTAL"
echo -e "Tests réussis   : ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests échoués   : ${RED}$TESTS_FAILED${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED/$TESTS_TOTAL)*100}")
echo "Taux de réussite : $SUCCESS_RATE%"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Tous les tests sont passés !${NC}"
    echo ""
    echo "Le TP9 est prêt à être utilisé."
    exit 0
else
    echo -e "${RED}✗ Certains tests ont échoué${NC}"
    echo ""
    echo "Veuillez corriger les problèmes avant d'utiliser le TP9."
    exit 1
fi
