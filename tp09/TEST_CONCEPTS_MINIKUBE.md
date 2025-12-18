# Tests de concepts du TP9 avec Minikube

Ce document montre quels concepts du TP9 peuvent être testés avec Minikube (cluster mono-nœud).

## ⚠️ Limitations

Minikube est un cluster **mono-nœud**, donc certains concepts multi-nœuds ne peuvent pas être testés :
- ❌ Ajout de workers
- ❌ Haute disponibilité du control plane
- ❌ Anti-affinité stricte entre nœuds
- ❌ Distribution géographique

## ✅ Concepts testables avec Minikube

### 1. Labels et NodeSelectors

```bash
# Démarrer minikube
minikube start

# Voir les labels du nœud
kubectl get nodes --show-labels

# Ajouter des labels
kubectl label nodes minikube disktype=ssd
kubectl label nodes minikube zone=zone-a

# Créer un pod avec nodeSelector
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-ssd
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: nginx
    image: nginx:alpine
EOF

# Vérifier
kubectl get pod nginx-ssd -o wide
```

**✅ Résultat attendu :** Le pod est planifié sur le nœud minikube avec le label disktype=ssd

---

### 2. Taints et Tolerations

```bash
# Ajouter un taint au nœud
kubectl taint nodes minikube dedicated=database:NoSchedule

# Essayer de créer un pod sans toleration
kubectl run test-no-toleration --image=nginx:alpine

# Vérifier qu'il reste en Pending
kubectl get pods test-no-toleration
kubectl describe pod test-no-toleration

# Créer un pod avec toleration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-with-toleration
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "database"
    effect: "NoSchedule"
  containers:
  - name: nginx
    image: nginx:alpine
EOF

# Vérifier qu'il est Running
kubectl get pods nginx-with-toleration

# Nettoyer
kubectl delete pod test-no-toleration nginx-with-toleration
kubectl taint nodes minikube dedicated-
```

**✅ Résultat attendu :**
- Pod sans toleration : Pending
- Pod avec toleration : Running

---

### 3. Node Affinity

```bash
# Tester l'affinité requise
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-affinity
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disktype
            operator: In
            values:
            - ssd
  containers:
  - name: nginx
    image: nginx:alpine
EOF

# Vérifier
kubectl get pod nginx-affinity -o wide
kubectl describe pod nginx-affinity | grep -A 5 "Node-Selectors"
```

**✅ Résultat attendu :** Le pod utilise l'affinité pour être planifié

---

### 4. PodDisruptionBudgets

```bash
# Créer un deployment
kubectl create deployment web --image=nginx:alpine --replicas=3

# Créer un PDB
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web
EOF

# Vérifier le PDB
kubectl get pdb
kubectl describe pdb web-pdb

# Tester l'évacuation du nœud (simulation)
# Note : Sur minikube, drain ne fonctionne pas comme sur multi-nœuds
# car il n'y a qu'un seul nœud, mais on peut voir le PDB

# Voir les pods
kubectl get pods -l app=web

# Le PDB protège contre les évacuations accidentelles
kubectl get pdb web-pdb -o yaml | grep -A 5 status

# Nettoyer
kubectl delete deployment web
kubectl delete pdb web-pdb
```

**✅ Résultat attendu :** Le PDB est créé et protège les pods

---

### 5. Commandes de gestion des nœuds

```bash
# Lister les nœuds
kubectl get nodes
kubectl get nodes -o wide

# Voir les détails d'un nœud
kubectl describe node minikube

# Voir les ressources
kubectl top node minikube

# Cordon (marquer comme non-planifiable)
kubectl cordon minikube
kubectl get nodes
# STATUS affichera "Ready,SchedulingDisabled"

# Essayer de créer un pod (restera en Pending)
kubectl run test-cordon --image=nginx:alpine
kubectl get pods test-cordon

# Uncordon (réactiver)
kubectl uncordon minikube
kubectl get nodes

# Le pod devrait maintenant être planifié
kubectl get pods test-cordon

# Nettoyer
kubectl delete pod test-cordon
```

**✅ Résultat attendu :**
- Cordon : Nouveaux pods en Pending
- Uncordon : Pods planifiés normalement

---

### 6. Validation des manifests d'exemples

```bash
# Tester la syntaxe des exemples (dry-run)
kubectl apply --dry-run=client -f examples/node-affinity-examples.yaml
kubectl apply --dry-run=client -f examples/pod-affinity-examples.yaml
kubectl apply --dry-run=client -f examples/taints-tolerations-examples.yaml
kubectl apply --dry-run=client -f examples/poddisruptionbudget-examples.yaml

# Appliquer un exemple simple
kubectl apply -f examples/poddisruptionbudget-examples.yaml

# Voir les ressources créées
kubectl get all
kubectl get pdb

# Nettoyer
kubectl delete -f examples/poddisruptionbudget-examples.yaml
```

**✅ Résultat attendu :** Tous les manifests sont valides

---

### 7. Exercice 2 : Script de maintenance (adapté)

```bash
# Le script exercice2-maintenance.sh peut être testé sur minikube
# mais avec des adaptations car il n'y a qu'un nœud

# Créer un deployment de test
kubectl create deployment test-app --image=nginx:alpine --replicas=3

# Voir les pods
kubectl get pods -o wide

# Cordon
kubectl cordon minikube

# Scale up (les nouveaux pods resteront en Pending)
kubectl scale deployment test-app --replicas=5
kubectl get pods

# Uncordon
kubectl uncordon minikube

# Les pods pending devraient maintenant être Running
kubectl get pods

# Nettoyer
kubectl delete deployment test-app
```

**✅ Résultat attendu :** Les concepts de maintenance sont démontrés

---

## 📊 Résumé des tests possibles

| Concept | Testable avec Minikube | Remarques |
|---------|------------------------|-----------|
| Labels | ✅ Oui | Pleinement testable |
| NodeSelectors | ✅ Oui | Pleinement testable |
| Taints | ✅ Oui | Pleinement testable |
| Tolerations | ✅ Oui | Pleinement testable |
| Node Affinity | ✅ Oui | Testable (1 nœud) |
| Pod Affinity | ⚠️ Limité | Pas d'effet visible (1 nœud) |
| Pod Anti-Affinity | ⚠️ Limité | Pas d'effet visible (1 nœud) |
| PodDisruptionBudgets | ✅ Oui | Pleinement testable |
| Cordon/Uncordon | ✅ Oui | Testable |
| Drain | ⚠️ Limité | Fonctionne mais pas représentatif |
| Ajout de nœuds | ❌ Non | Multi-nœuds requis |
| HA Control Plane | ❌ Non | Multi-nœuds requis |
| Load Balancer | ❌ Non | Multi-nœuds requis |

---

## 🎯 Script de test automatisé pour Minikube

```bash
#!/bin/bash
# test-tp9-minikube.sh - Tests des concepts applicables sur minikube

echo "=== Tests TP9 avec Minikube ==="
echo ""

# Vérifier que minikube est démarré
if ! minikube status | grep -q "Running"; then
    echo "Démarrage de minikube..."
    minikube start
fi

echo "1. Test des labels"
kubectl label nodes minikube disktype=ssd --overwrite
kubectl get nodes --show-labels | grep disktype && echo "✓ Labels OK"

echo ""
echo "2. Test des taints"
kubectl taint nodes minikube test=value:NoSchedule --overwrite
kubectl describe node minikube | grep -A 1 Taints | grep test && echo "✓ Taints OK"
kubectl taint nodes minikube test-

echo ""
echo "3. Test PodDisruptionBudget"
kubectl create deployment test --image=nginx:alpine --replicas=3
cat <<EOF | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: test-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: test
EOF
kubectl get pdb test-pdb && echo "✓ PDB créé"
kubectl delete deployment test
kubectl delete pdb test-pdb

echo ""
echo "4. Test cordon/uncordon"
kubectl cordon minikube
kubectl get nodes | grep SchedulingDisabled && echo "✓ Cordon OK"
kubectl uncordon minikube
kubectl get nodes | grep -v SchedulingDisabled && echo "✓ Uncordon OK"

echo ""
echo "✓ Tous les tests sont passés !"
```

---

## 💡 Conclusion

Même avec Minikube (mono-nœud), il est possible de tester et comprendre :
- ✅ Les labels et sélecteurs
- ✅ Les taints et tolerations
- ✅ L'affinité de nœuds
- ✅ Les PodDisruptionBudgets
- ✅ Les opérations de maintenance (cordon/uncordon)

Pour tester pleinement le TP9 (multi-nœuds, HA, etc.), il faut :
- Un environnement multi-VMs (VirtualBox, VMware)
- Un cluster cloud (AWS, GCP, Azure)
- Plusieurs machines physiques
- Utiliser les scripts fournis (prepare-node.sh, add-worker-node.sh)

**Le TP9 reste pertinent car il explique comment créer et gérer ces environnements !**
