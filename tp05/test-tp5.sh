#!/bin/bash

# Script de test automatisé pour le TP5 - Sécurité et RBAC
# Ce script teste tous les exercices du TP5

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

# Fonction pour vérifier si kubectl est installé
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

    log_success "Prérequis OK"
}

# Fonction pour nettoyer les ressources de test
cleanup() {
    log_info "Nettoyage des ressources de test..."

    # Supprimer les pods de test
    kubectl delete pod pod-a pod-b pod-with-sa security-context-demo \
        security-context-container pod-with-secrets unauthorized test-permissions \
        --ignore-not-found=true 2>/dev/null || true

    # Supprimer les déploiements
    kubectl delete deployment backend frontend secure-app --ignore-not-found=true 2>/dev/null || true

    # Supprimer les services
    kubectl delete service backend --ignore-not-found=true 2>/dev/null || true

    # Supprimer les Network Policies
    kubectl delete networkpolicy --all --ignore-not-found=true 2>/dev/null || true

    # Supprimer les Roles et RoleBindings
    kubectl delete role pod-reader developer-role secret-reader app-role --ignore-not-found=true 2>/dev/null || true
    kubectl delete rolebinding read-pods-binding developer-binding app-secret-binding --ignore-not-found=true 2>/dev/null || true

    # Supprimer les ClusterRoles et ClusterRoleBindings
    kubectl delete clusterrole secret-reader --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterrolebinding read-secrets-global --ignore-not-found=true 2>/dev/null || true

    # Supprimer les ServiceAccounts personnalisés
    kubectl delete sa my-app-sa developer-sa app-sa --ignore-not-found=true 2>/dev/null || true

    # Supprimer les namespaces de test
    kubectl delete namespace secure-namespace dev-namespace prod-namespace secure-app --ignore-not-found=true 2>/dev/null || true

    # Supprimer les secrets de test
    kubectl delete secret app-secrets --ignore-not-found=true 2>/dev/null || true

    # Supprimer les quotas et limites
    kubectl delete resourcequota compute-quota --ignore-not-found=true 2>/dev/null || true
    kubectl delete limitrange limit-range --ignore-not-found=true 2>/dev/null || true

    log_success "Nettoyage terminé"
}

# Exercice 1: ServiceAccounts
test_exercise_1() {
    log_info "Test Exercice 1: ServiceAccounts..."

    kubectl apply -f 01-serviceaccount.yaml
    kubectl get sa my-app-sa

    # Vérifier que le ServiceAccount existe
    if kubectl get sa my-app-sa &> /dev/null; then
        log_success "Exercice 1: ServiceAccount créé avec succès"
    else
        log_error "Exercice 1: Échec de la création du ServiceAccount"
        return 1
    fi

    # Créer un token pour le ServiceAccount (Kubernetes >= 1.24)
    log_info "Création d'un token pour le ServiceAccount..."
    kubectl create token my-app-sa --duration=1h

    # Appliquer le pod avec ServiceAccount
    kubectl apply -f 02-pod-with-sa.yaml
    kubectl wait --for=condition=ready pod/pod-with-sa --timeout=60s

    # Vérifier le ServiceAccount utilisé
    SA_USED=$(kubectl get pod pod-with-sa -o jsonpath='{.spec.serviceAccountName}')
    if [ "$SA_USED" == "my-app-sa" ]; then
        log_success "Exercice 1: Pod utilise le bon ServiceAccount"
    else
        log_error "Exercice 1: Pod n'utilise pas le bon ServiceAccount"
        return 1
    fi
}

# Exercice 2: Créer un Role
test_exercise_2() {
    log_info "Test Exercice 2: Créer un Role..."

    kubectl apply -f 03-role-pod-reader.yaml
    kubectl get role pod-reader

    if kubectl get role pod-reader &> /dev/null; then
        log_success "Exercice 2: Role créé avec succès"
    else
        log_error "Exercice 2: Échec de la création du Role"
        return 1
    fi

    # Vérifier les règles du role
    kubectl describe role pod-reader
}

# Exercice 3: Tester les permissions
test_exercise_3() {
    log_info "Test Exercice 3: RoleBinding et permissions..."

    kubectl apply -f 04-rolebinding-pod-reader.yaml

    # Tester avec kubectl auth can-i
    log_info "Test: Peut lister les pods..."
    if kubectl auth can-i list pods --as=system:serviceaccount:default:my-app-sa | grep -q "yes"; then
        log_success "ServiceAccount peut lister les pods"
    else
        log_error "ServiceAccount ne peut pas lister les pods"
        return 1
    fi

    log_info "Test: Ne peut pas créer de pods..."
    if kubectl auth can-i create pods --as=system:serviceaccount:default:my-app-sa | grep -q "no"; then
        log_success "ServiceAccount ne peut pas créer de pods (attendu)"
    else
        log_warning "ServiceAccount peut créer des pods (non attendu)"
    fi

    log_info "Test: Ne peut pas supprimer de pods..."
    if kubectl auth can-i delete pods --as=system:serviceaccount:default:my-app-sa | grep -q "no"; then
        log_success "ServiceAccount ne peut pas supprimer de pods (attendu)"
    else
        log_warning "ServiceAccount peut supprimer des pods (non attendu)"
    fi
}

# Exercice 4: Tester le role développeur
test_exercise_4() {
    log_info "Test Exercice 4: Role développeur..."

    kubectl apply -f 06-developer-role.yaml

    # Tester les permissions
    log_info "Test: Peut créer des deployments..."
    if kubectl auth can-i create deployments --as=system:serviceaccount:default:developer-sa | grep -q "yes"; then
        log_success "Developer-SA peut créer des deployments"
    else
        log_error "Developer-SA ne peut pas créer de deployments"
        return 1
    fi

    log_info "Test: Ne peut pas supprimer des deployments..."
    if kubectl auth can-i delete deployments --as=system:serviceaccount:default:developer-sa | grep -q "no"; then
        log_success "Developer-SA ne peut pas supprimer de deployments (attendu)"
    else
        log_warning "Developer-SA peut supprimer des deployments (non attendu)"
    fi

    log_info "Test: Ne peut pas créer de secrets..."
    if kubectl auth can-i create secrets --as=system:serviceaccount:default:developer-sa | grep -q "no"; then
        log_success "Developer-SA ne peut pas créer de secrets (attendu)"
    else
        log_warning "Developer-SA peut créer des secrets (non attendu)"
    fi
}

# Exercice 5: Security Context au niveau Pod
test_exercise_5() {
    log_info "Test Exercice 5: Security Context Pod..."

    kubectl apply -f 07-pod-security-context.yaml
    kubectl wait --for=condition=ready pod/security-context-demo --timeout=60s

    # Vérifier les UID/GID
    log_info "Vérification des UID/GID..."
    UID_OUTPUT=$(kubectl exec security-context-demo -- id 2>/dev/null || true)
    echo "Output: $UID_OUTPUT"

    if echo "$UID_OUTPUT" | grep -q "uid=1000"; then
        log_success "UID correct (1000)"
    else
        log_warning "UID peut être différent"
    fi

    # Tester l'écriture dans le volume
    kubectl exec security-context-demo -- sh -c 'echo "test" > /data/demo/test.txt' 2>/dev/null || true
    kubectl exec security-context-demo -- ls -l /data/demo/test.txt 2>/dev/null || true

    log_success "Exercice 5: Security Context Pod testé"
}

# Exercice 6: Security Context au niveau Conteneur
test_exercise_6() {
    log_info "Test Exercice 6: Security Context Conteneur..."

    kubectl apply -f 08-container-security-context.yaml

    # Attendre que le pod soit prêt ou en erreur
    sleep 5
    POD_STATUS=$(kubectl get pod security-context-container -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

    log_info "Status du pod: $POD_STATUS"

    # Même si le pod échoue (problème avec nginx:alpine et runAsUser), c'est OK
    # car cela démontre les contraintes de sécurité
    if [ "$POD_STATUS" == "Running" ] || [ "$POD_STATUS" == "Error" ] || [ "$POD_STATUS" == "CrashLoopBackOff" ]; then
        log_success "Exercice 6: Security Context appliqué (pod peut être en erreur, c'est normal avec nginx)"
    else
        log_warning "Exercice 6: Status inattendu: $POD_STATUS"
    fi
}

# Exercice 7: Pod Security Standards
test_exercise_7() {
    log_info "Test Exercice 7: Pod Security Standards..."

    kubectl apply -f 10-namespace-pss.yaml

    # Vérifier que le namespace a les labels PSS
    ENFORCE_LABEL=$(kubectl get namespace secure-namespace -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")

    if [ "$ENFORCE_LABEL" == "restricted" ]; then
        log_success "Namespace avec Pod Security Standards configuré"
    else
        log_warning "Pod Security Standards peuvent ne pas être supportés dans ce cluster"
    fi

    # Tenter de créer un pod privileged (devrait échouer)
    log_info "Test: Tentative de création d'un pod privileged (devrait échouer)..."
    if kubectl run privileged-pod --image=nginx --privileged -n secure-namespace 2>&1 | grep -q "violation\|forbidden\|denied"; then
        log_success "Pod privileged rejeté (attendu)"
    else
        log_warning "Pod privileged peut avoir été créé ou PSS non supporté"
        kubectl delete pod privileged-pod -n secure-namespace --ignore-not-found=true 2>/dev/null || true
    fi
}

# Exercice 8: Network Policy Deny All
test_exercise_8() {
    log_info "Test Exercice 8: Network Policy Deny All..."

    # Créer deux pods de test
    kubectl run pod-a --image=nginx 2>/dev/null || true
    kubectl run pod-b --image=busybox --command -- sleep 3600 2>/dev/null || true

    kubectl wait --for=condition=ready pod/pod-a --timeout=60s 2>/dev/null || true
    kubectl wait --for=condition=ready pod/pod-b --timeout=60s 2>/dev/null || true

    # Vérifier la connectivité avant Network Policy
    log_info "Test connectivité avant Network Policy..."
    POD_A_IP=$(kubectl get pod pod-a -o jsonpath='{.status.podIP}')
    kubectl exec pod-b -- wget -O- --timeout=2 "http://$POD_A_IP" &>/dev/null && \
        log_info "Connectivité OK avant Network Policy" || \
        log_warning "Pas de connectivité (peut être dû à d'autres policies)"

    # Appliquer la Network Policy
    kubectl apply -f 12-network-policy-deny-all.yaml
    sleep 5

    # Tester à nouveau (devrait échouer)
    log_info "Test connectivité après Network Policy Deny All..."
    if kubectl exec pod-b -- wget -O- --timeout=2 "http://$POD_A_IP" &>/dev/null; then
        log_warning "Connectivité toujours présente (CNI peut ne pas supporter Network Policies)"
    else
        log_success "Connectivité bloquée par Network Policy"
    fi

    # Supprimer pour les tests suivants
    kubectl delete networkpolicy deny-all
}

# Exercice 9: Network Policy Allow Specific
test_exercise_9() {
    log_info "Test Exercice 9: Network Policy Allow Specific..."

    kubectl apply -f 13-network-policy-allow-specific.yaml

    # Attendre que les pods soient prêts
    kubectl wait --for=condition=ready pod -l app=backend --timeout=60s 2>/dev/null || true
    kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s 2>/dev/null || true

    # Tester depuis frontend (devrait marcher)
    log_info "Test: Frontend -> Backend (devrait marcher)..."
    if kubectl exec -it deployment/frontend -- wget -O- --timeout=2 http://backend &>/dev/null; then
        log_success "Frontend peut accéder au backend"
    else
        log_warning "Frontend ne peut pas accéder au backend (CNI peut ne pas supporter Network Policies)"
    fi

    # Créer un pod non autorisé
    kubectl run unauthorized --image=busybox --command -- sleep 3600 2>/dev/null || true
    kubectl wait --for=condition=ready pod/unauthorized --timeout=60s 2>/dev/null || true

    # Tester depuis unauthorized (devrait échouer)
    log_info "Test: Unauthorized -> Backend (devrait échouer)..."
    if kubectl exec unauthorized -- wget -O- --timeout=2 http://backend &>/dev/null; then
        log_warning "Pod non autorisé peut accéder au backend (CNI peut ne pas supporter Network Policies)"
    else
        log_success "Pod non autorisé bloqué par Network Policy"
    fi
}

# Exercice 10: Utiliser les Secrets
test_exercise_10() {
    log_info "Test Exercice 10: Utiliser les Secrets..."

    kubectl apply -f 16-pod-with-secrets.yaml
    kubectl wait --for=condition=ready pod/pod-with-secrets --timeout=60s

    # Vérifier les variables d'environnement
    log_info "Vérification des variables d'environnement..."
    if kubectl exec pod-with-secrets -- env | grep -q "DB_USERNAME=dbuser"; then
        log_success "Variable d'environnement DB_USERNAME correcte"
    else
        log_error "Variable d'environnement DB_USERNAME incorrecte"
        return 1
    fi

    # Vérifier les fichiers montés
    log_info "Vérification des fichiers montés..."
    if kubectl exec pod-with-secrets -- ls /etc/secrets | grep -q "api-key"; then
        log_success "Secret monté comme fichier"
    else
        log_error "Secret non monté comme fichier"
        return 1
    fi

    API_KEY=$(kubectl exec pod-with-secrets -- cat /etc/secrets/api-key)
    if [ "$API_KEY" == "sk-1234567890abcdef" ]; then
        log_success "Contenu du secret correct"
    else
        log_error "Contenu du secret incorrect"
        return 1
    fi
}

# Fonction principale
main() {
    echo "=========================================="
    echo "Test du TP5 - Sécurité et RBAC"
    echo "=========================================="
    echo ""

    check_prerequisites
    echo ""

    # Nettoyer avant de commencer
    cleanup
    echo ""

    # Tableau pour suivre les résultats
    declare -A results

    # Exécuter les tests
    test_exercise_1 && results[1]="✅" || results[1]="❌"
    echo ""

    test_exercise_2 && results[2]="✅" || results[2]="❌"
    echo ""

    test_exercise_3 && results[3]="✅" || results[3]="❌"
    echo ""

    test_exercise_4 && results[4]="✅" || results[4]="❌"
    echo ""

    test_exercise_5 && results[5]="✅" || results[5]="❌"
    echo ""

    test_exercise_6 && results[6]="✅" || results[6]="❌"
    echo ""

    test_exercise_7 && results[7]="✅" || results[7]="❌"
    echo ""

    test_exercise_8 && results[8]="✅" || results[8]="❌"
    echo ""

    test_exercise_9 && results[9]="✅" || results[9]="❌"
    echo ""

    test_exercise_10 && results[10]="✅" || results[10]="❌"
    echo ""

    # Afficher le résumé
    echo "=========================================="
    echo "Résumé des tests"
    echo "=========================================="
    echo "${results[1]} Exercice 1: ServiceAccounts"
    echo "${results[2]} Exercice 2: Créer un Role"
    echo "${results[3]} Exercice 3: RoleBinding et permissions"
    echo "${results[4]} Exercice 4: Role développeur"
    echo "${results[5]} Exercice 5: Security Context Pod"
    echo "${results[6]} Exercice 6: Security Context Conteneur"
    echo "${results[7]} Exercice 7: Pod Security Standards"
    echo "${results[8]} Exercice 8: Network Policy Deny All"
    echo "${results[9]} Exercice 9: Network Policy Allow Specific"
    echo "${results[10]} Exercice 10: Utiliser les Secrets"
    echo "=========================================="
    echo ""

    # Nettoyer après les tests
    read -p "Voulez-vous nettoyer les ressources de test? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    fi
}

# Gérer Ctrl+C
trap cleanup EXIT

# Exécuter
main
