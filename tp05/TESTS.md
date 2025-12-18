# Guide d'Utilisation des Tests TP5

Ce document explique comment utiliser les fichiers de test créés pour le TP5 sur la sécurité et RBAC.

## Fichiers de Test

### 1. validate_yaml.py
Script Python pour valider la syntaxe YAML de tous les fichiers.

**Prérequis**: Python 3 avec le module `yaml`

**Installation du module yaml (si nécessaire)**:
```bash
pip3 install pyyaml
```

**Utilisation**:
```bash
cd tp5
python3 validate_yaml.py
```

**Résultat attendu**:
```
Validation de 22 fichiers YAML...

  ✅ 01-serviceaccount.yaml: Valide (1 document(s))
  ✅ 02-pod-with-sa.yaml: Valide (1 document(s))
  ...

============================================================
Résumé:
  Fichiers valides: 22
  Fichiers invalides: 0
  Total: 22
============================================================
```

---

### 2. test-tp5.sh
Script Bash automatisé pour tester tous les exercices du TP5.

**Prérequis**:
- kubectl installé et configuré
- Cluster Kubernetes actif (minikube recommandé)
- CNI supportant les Network Policies (Calico recommandé)

**Utilisation**:
```bash
cd tp5
chmod +x test-tp5.sh
./test-tp5.sh
```

**Ce que le script fait**:
1. Vérifie que kubectl et le cluster sont disponibles
2. Nettoie les ressources de test existantes
3. Exécute les 10 exercices principaux:
   - Exercice 1: ServiceAccounts
   - Exercice 2: Créer un Role
   - Exercice 3: RoleBinding et permissions
   - Exercice 4: Role développeur
   - Exercice 5: Security Context Pod
   - Exercice 6: Security Context Conteneur
   - Exercice 7: Pod Security Standards
   - Exercice 8: Network Policy Deny All
   - Exercice 9: Network Policy Allow Specific
   - Exercice 10: Utiliser les Secrets
4. Affiche un résumé des résultats
5. Propose de nettoyer les ressources

**Résultat attendu**:
```
==========================================
Test du TP5 - Sécurité et RBAC
==========================================

[INFO] Vérification des prérequis...
[SUCCESS] Prérequis OK

...

==========================================
Résumé des tests
==========================================
✅ Exercice 1: ServiceAccounts
✅ Exercice 2: Créer un Role
✅ Exercice 3: RoleBinding et permissions
✅ Exercice 4: Role développeur
✅ Exercice 5: Security Context Pod
✅ Exercice 6: Security Context Conteneur
✅ Exercice 7: Pod Security Standards
✅ Exercice 8: Network Policy Deny All
✅ Exercice 9: Network Policy Allow Specific
✅ Exercice 10: Utiliser les Secrets
==========================================
```

---

## Configuration de l'Environnement de Test

### Option 1: Minikube avec Calico (Recommandé)

```bash
# Arrêter minikube existant (si nécessaire)
minikube stop
minikube delete

# Démarrer avec Calico pour Network Policies
minikube start --cni=calico --memory=4096 --kubernetes-version=v1.28.0

# Vérifier que Calico est installé
kubectl get pods -n kube-system | grep calico

# Attendre que tous les pods Calico soient prêts
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=120s
```

### Option 2: Minikube standard (Network Policies non supportées)

```bash
minikube start --memory=4096

# Note: Les Network Policies (exercices 8 et 9) ne fonctionneront pas
```

### Option 3: Cluster Kubernetes existant

Assurez-vous que:
- Le cluster supporte les Network Policies (CNI compatible)
- Vous avez les permissions nécessaires pour créer des ressources
- Pod Security Admission est activé (Kubernetes 1.25+)

---

## Tests Manuels des Exercices

Si vous préférez tester manuellement chaque exercice:

### Exercice 1: ServiceAccounts

```bash
# Créer le ServiceAccount
kubectl apply -f 01-serviceaccount.yaml
kubectl get sa my-app-sa
kubectl describe sa my-app-sa

# Créer un token
kubectl create token my-app-sa

# Créer le pod avec ServiceAccount
kubectl apply -f 02-pod-with-sa.yaml
kubectl describe pod pod-with-sa | grep "Service Account"

# Vérifier dans le pod
kubectl exec -it pod-with-sa -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

### Exercice 2: Créer un Role

```bash
kubectl apply -f 03-role-pod-reader.yaml
kubectl get role pod-reader
kubectl describe role pod-reader
```

### Exercice 3: RoleBinding et Permissions

```bash
kubectl apply -f 04-rolebinding-pod-reader.yaml

# Tester les permissions
kubectl auth can-i list pods --as=system:serviceaccount:default:my-app-sa
kubectl auth can-i create pods --as=system:serviceaccount:default:my-app-sa
kubectl auth can-i delete pods --as=system:serviceaccount:default:my-app-sa
```

### Exercice 4: Role Développeur

```bash
kubectl apply -f 06-developer-role.yaml

kubectl auth can-i create deployments --as=system:serviceaccount:default:developer-sa
kubectl auth can-i delete deployments --as=system:serviceaccount:default:developer-sa
kubectl auth can-i create secrets --as=system:serviceaccount:default:developer-sa
```

### Exercice 5: Security Context Pod

```bash
kubectl apply -f 07-pod-security-context.yaml

kubectl exec -it security-context-demo -- id
kubectl exec -it security-context-demo -- sh -c 'echo "test" > /data/demo/test.txt'
kubectl exec -it security-context-demo -- ls -l /data/demo/test.txt
```

### Exercice 6: Security Context Conteneur

```bash
kubectl apply -f 08-container-security-context.yaml
kubectl get pod security-context-container
kubectl describe pod security-context-container

# Si le pod démarre (peut échouer avec nginx standard)
kubectl exec -it security-context-container -- sh
# touch /test.txt  # Devrait échouer (read-only)
```

### Exercice 7: Pod Security Standards

```bash
kubectl apply -f 10-namespace-pss.yaml

# Tenter un pod privileged (devrait être rejeté)
kubectl run privileged-pod --image=nginx --privileged -n secure-namespace

# Créer un pod conforme
kubectl apply -f 09-best-practices-security.yaml -n secure-namespace
kubectl get pods -n secure-namespace
```

### Exercice 8: Network Policy Deny All

```bash
# Créer les pods de test
kubectl run pod-a --image=nginx
kubectl run pod-b --image=busybox --command -- sleep 3600

# Test avant Network Policy
kubectl exec pod-b -- wget -O- --timeout=2 http://pod-a

# Appliquer Network Policy
kubectl apply -f 12-network-policy-deny-all.yaml

# Test après (devrait timeout)
kubectl exec pod-b -- wget -O- --timeout=2 http://pod-a

# Nettoyer
kubectl delete networkpolicy deny-all
```

### Exercice 9: Network Policy Allow Specific

```bash
kubectl apply -f 13-network-policy-allow-specific.yaml

kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s

# Test autorisé
kubectl exec -it deployment/frontend -- wget -O- --timeout=2 http://backend

# Créer pod non autorisé
kubectl run unauthorized --image=busybox --command -- sleep 3600

# Test non autorisé (devrait timeout)
kubectl exec unauthorized -- wget -O- --timeout=2 http://backend
```

### Exercice 10: Secrets

```bash
kubectl apply -f 16-pod-with-secrets.yaml

# Vérifier les variables d'environnement
kubectl exec pod-with-secrets -- env | grep DB_

# Vérifier les fichiers montés
kubectl exec pod-with-secrets -- ls /etc/secrets
kubectl exec pod-with-secrets -- cat /etc/secrets/api-key
```

---

## Nettoyage

### Nettoyage manuel

```bash
# Supprimer tous les pods de test
kubectl delete pod pod-a pod-b pod-with-sa security-context-demo \
  security-context-container pod-with-secrets unauthorized --ignore-not-found

# Supprimer les déploiements
kubectl delete deployment backend frontend secure-app --ignore-not-found

# Supprimer les services
kubectl delete service backend --ignore-not-found

# Supprimer les Network Policies
kubectl delete networkpolicy --all

# Supprimer les Roles et RoleBindings
kubectl delete role pod-reader developer-role secret-reader app-role --ignore-not-found
kubectl delete rolebinding read-pods-binding developer-binding app-secret-binding --ignore-not-found

# Supprimer les ClusterRoles et ClusterRoleBindings
kubectl delete clusterrole secret-reader --ignore-not-found
kubectl delete clusterrolebinding read-secrets-global --ignore-not-found

# Supprimer les ServiceAccounts
kubectl delete sa my-app-sa developer-sa app-sa --ignore-not-found

# Supprimer les namespaces
kubectl delete namespace secure-namespace dev-namespace prod-namespace secure-app --ignore-not-found

# Supprimer les secrets
kubectl delete secret app-secrets --ignore-not-found

# Supprimer les quotas et limites
kubectl delete resourcequota compute-quota --ignore-not-found
kubectl delete limitrange limit-range --ignore-not-found
```

### Nettoyage avec le script

Le script `test-tp5.sh` inclut une fonction de nettoyage automatique.

---

## Dépannage

### Problème: Network Policies ne fonctionnent pas

**Symptôme**: Le trafic n'est pas bloqué malgré les Network Policies

**Cause**: CNI ne supporte pas les Network Policies

**Solution**:
```bash
minikube delete
minikube start --cni=calico --memory=4096
```

### Problème: Pod Security Standards ne s'appliquent pas

**Symptôme**: Les pods privileged peuvent être créés dans les namespaces restricted

**Cause**: Version Kubernetes < 1.25 ou Pod Security Admission non activé

**Solution**:
- Vérifier la version: `kubectl version`
- Mettre à jour minikube: `minikube start --kubernetes-version=v1.28.0`

### Problème: security-context-container ne démarre pas

**Symptôme**: Pod en CrashLoopBackOff ou Error

**Cause**: nginx:alpine nécessite des privilèges root

**Solution**: C'est normal ! Cela démontre les contraintes de sécurité. Utiliser:
```bash
# Utiliser une image nginx unprivileged
kubectl run nginx-unprivileged --image=nginxinc/nginx-unprivileged:alpine
```

### Problème: kubectl auth can-i retourne toujours "yes"

**Symptôme**: Même sans permissions, la commande retourne "yes"

**Cause**: Vous êtes admin du cluster

**Solution**: La commande `--as` simule les permissions. Si vous êtes admin, vérifiez que vous utilisez bien `--as=system:serviceaccount:namespace:sa-name`

---

## Fichiers de Référence

- `RAPPORT_TESTS.md`: Rapport détaillé des tests et validation
- `README.md`: Documentation complète du TP5
- Fichiers YAML numérotés de 01 à 22: Ressources Kubernetes pour les exercices

---

## Statistiques

- **Fichiers YAML**: 22
- **Exercices couverts**: 10+
- **Concepts testés**:
  - ServiceAccounts
  - RBAC (Roles, ClusterRoles, RoleBindings, ClusterRoleBindings)
  - Security Context (Pod et Container)
  - Pod Security Standards
  - Network Policies
  - Secrets
  - ResourceQuotas
  - LimitRanges

---

## Support

Pour toute question ou problème:
1. Consulter `RAPPORT_TESTS.md`
2. Consulter `README.md` du TP5
3. Vérifier les logs: `kubectl describe pod <pod-name>`
4. Vérifier les events: `kubectl get events --sort-by='.lastTimestamp'`

---

**Dernière mise à jour**: 2025-11-18
**Version**: 1.0
