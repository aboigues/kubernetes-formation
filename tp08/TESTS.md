# Guide de validation du TP8 - Réseau Kubernetes

Ce document fournit un guide complet pour tester et valider tous les exercices du TP8.

## Prérequis

- Cluster Kubernetes fonctionnel (minikube, kind, ou cluster cloud)
- kubectl installé et configuré
- Plugin CNI supportant les NetworkPolicies (Calico, Cilium, Weave)

## Vérification de l'environnement

### 1. Vérifier le cluster

```bash
# Vérifier que le cluster est actif
kubectl cluster-info

# Vérifier les nœuds
kubectl get nodes

# Vérifier le plugin CNI
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|flannel'
```

**⚠️ Important :** Si vous utilisez Flannel, les NetworkPolicies ne fonctionneront pas. Utilisez Calico ou un autre plugin.

### 2. Vérifier CoreDNS

```bash
# Vérifier que CoreDNS est actif
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Devrait afficher 2 pods coredns en Running
```

---

## Tests Partie 1 : Modèle réseau Kubernetes

### Exercice 1.1 : Visualiser l'adressage IP

```bash
# Créer plusieurs pods
kubectl create deployment web --image=nginx:alpine --replicas=3

# Voir les IPs des pods
kubectl get pods -o wide

# Vérifier les détails réseau
POD_NAME=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $POD_NAME | grep IP

# Nettoyer
kubectl delete deployment web
```

**✅ Validation :**
- Chaque Pod a une IP unique
- Les IPs sont dans une plage spécifique (ex: 10.244.x.x)

### Exercice 1.2 : Communication inter-pods

```bash
# Créer deux pods
kubectl run pod-a --image=nginx:alpine
kubectl run pod-b --image=nginx:alpine

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod/pod-a pod/pod-b --timeout=60s

# Récupérer l'IP du pod-b
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')
echo "Pod B IP: $POD_B_IP"

# Tester la communication depuis pod-a vers pod-b
kubectl exec pod-a -- wget -qO- http://$POD_B_IP

# Tester avec ping (si supporté)
kubectl exec pod-a -- ping -c 3 $POD_B_IP || echo "ICMP peut être bloqué"

# Nettoyer
kubectl delete pod pod-a pod-b
```

**✅ Validation :**
- wget réussit (code 200)
- La communication est directe sans NAT

---

## Tests Partie 2 : Services

### Test 2.1 : Service ClusterIP

```bash
# Déployer l'exemple
kubectl apply -f examples/01-backend-deployment-service.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=backend --timeout=60s

# Vérifier le service
kubectl get svc backend-svc

# Vérifier les endpoints
kubectl get endpoints backend-svc
# Devrait montrer 3 IPs (3 replicas)

# Tester depuis un pod temporaire
kubectl run tmp --image=busybox --rm -it -- wget -qO- http://backend-svc

# Tester avec le FQDN
kubectl run tmp --image=busybox --rm -it -- wget -qO- http://backend-svc.default.svc.cluster.local

# Nettoyer
kubectl delete -f examples/01-backend-deployment-service.yaml
```

**✅ Validation :**
- Le service a une ClusterIP
- 3 endpoints sont listés
- wget réussit avec nom court et FQDN

### Test 2.2 : Service NodePort

```bash
# Déployer l'exemple
kubectl apply -f examples/02-nodeport-service.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=web --timeout=60s

# Vérifier le service
kubectl get svc web-nodeport

# Pour minikube
minikube service web-nodeport --url

# Ou obtenir l'URL manuellement
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "URL: http://$NODE_IP:30080"

# Tester (si minikube)
curl $(minikube service web-nodeport --url)

# Nettoyer
kubectl delete -f examples/02-nodeport-service.yaml
```

**✅ Validation :**
- Le service expose le port 30080
- Accessible depuis l'extérieur du cluster

### Test 2.3 : Headless Service

```bash
# Déployer l'exemple
kubectl apply -f examples/03-headless-service.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=database --timeout=120s

# Vérifier le service
kubectl get svc db-headless
# ClusterIP devrait être "None"

# Test DNS - devrait retourner les IPs des pods
kubectl run tmp --image=busybox --rm -it -- nslookup db-headless

# Comparer avec les IPs des pods
kubectl get pods -l app=database -o wide

# Nettoyer
kubectl delete -f examples/03-headless-service.yaml
```

**✅ Validation :**
- ClusterIP est "None"
- nslookup retourne plusieurs IPs (une par Pod)

### Test 2.4 : ExternalName Service

```bash
# Déployer l'exemple
kubectl apply -f examples/04-externalname-service.yaml

# Test DNS
kubectl run tmp --image=busybox --rm -it -- nslookup external-db

# Nettoyer
kubectl delete -f examples/04-externalname-service.yaml
```

**✅ Validation :**
- nslookup retourne un CNAME vers database.example.com

### Test 2.5 : Session Affinity

```bash
# Déployer l'exemple
kubectl apply -f examples/08-session-affinity.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=sticky --timeout=60s

# Créer un pod de test
kubectl run test-client --image=busybox -- sleep 3600

# Faire plusieurs requêtes depuis le même client
for i in {1..10}; do
  kubectl exec test-client -- wget -qO- http://sticky-service
done

# Sans session affinity, les requêtes iraient à différents pods
# Avec session affinity, elles vont au même pod

# Nettoyer
kubectl delete -f examples/08-session-affinity.yaml
kubectl delete pod test-client
```

**✅ Validation :**
- Toutes les requêtes vont au même Pod backend

---

## Tests Partie 3 : DNS et Service Discovery

### Test 3.1 : Résolution DNS entre namespaces

```bash
# Créer deux namespaces
kubectl create namespace frontend
kubectl create namespace backend

# Créer un service dans backend
kubectl create deployment api -n backend --image=nginx:alpine
kubectl expose deployment api -n backend --port=80

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod -l app=api -n backend --timeout=60s

# Tester les différentes formes DNS depuis frontend
kubectl run test -n frontend --image=busybox --rm -it -- sh

# Dans le pod, tester :
wget -qO- http://api.backend
wget -qO- http://api.backend.svc
wget -qO- http://api.backend.svc.cluster.local

# Tenter sans namespace (devrait échouer)
wget -qO- http://api  # ERREUR attendue

# Nettoyer
kubectl delete namespace frontend backend
```

**✅ Validation :**
- Les 3 formes avec namespace fonctionnent
- La forme sans namespace échoue

### Test 3.2 : Debug DNS

```bash
# Déployer un pod avec outils DNS
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --rm -it -- sh

# Dans le pod, tester :
nslookup kubernetes.default
host kubernetes.default.svc.cluster.local
dig kubernetes.default.svc.cluster.local

# Voir la configuration DNS
cat /etc/resolv.conf

# Devrait montrer :
# - nameserver 10.96.0.10 (ou similaire)
# - search default.svc.cluster.local svc.cluster.local cluster.local
```

**✅ Validation :**
- Toutes les commandes DNS fonctionnent
- /etc/resolv.conf est correctement configuré

---

## Tests Partie 4 : NetworkPolicies

### Test 4.1 : Deny All Ingress

```bash
# Créer namespace et pods
kubectl create namespace secure
kubectl create deployment web -n secure --image=nginx:alpine
kubectl wait --for=condition=ready pod -l app=web -n secure --timeout=60s

# Obtenir l'IP du pod
POD_IP=$(kubectl get pod -n secure -l app=web -o jsonpath='{.items[0].status.podIP}')

# Tester l'accès AVANT NetworkPolicy (devrait marcher)
kubectl run tmp -n secure --image=busybox --rm -it -- wget --timeout=2 -qO- http://$POD_IP

# Appliquer la NetworkPolicy deny all
kubectl apply -f examples/05-networkpolicy-deny-all.yaml

# Tester l'accès APRÈS NetworkPolicy (devrait timeout)
kubectl run tmp -n secure --image=busybox --rm -it -- wget --timeout=2 -qO- http://$POD_IP
# Devrait échouer avec timeout

# Nettoyer
kubectl delete namespace secure
```

**✅ Validation :**
- Avant : wget réussit
- Après : wget timeout

### Test 4.2 : Exercice complet multi-tiers

```bash
# Créer le namespace
kubectl create namespace my-app

# Déployer l'architecture 3-tiers
kubectl apply -f exercices/exercice-1-multi-tiers.yaml

# Attendre que tout soit prêt
kubectl wait --for=condition=ready pod --all -n my-app --timeout=120s

# Vérifier tous les services
kubectl get all -n my-app

# Tester l'accès (AVANT NetworkPolicies)
# Frontend accessible
curl $(minikube ip):30090

# Appliquer les NetworkPolicies
kubectl apply -f exercices/exercice-2-networkpolicies.yaml

# Tester l'accès (APRÈS NetworkPolicies)
# Frontend toujours accessible
curl $(minikube ip):30090

# Tester l'isolation Backend
BACKEND_POD=$(kubectl get pod -n my-app -l tier=backend -o jsonpath='{.items[0].metadata.name}')
kubectl run tmp -n my-app --image=busybox --rm -it -- wget --timeout=2 http://backend.my-app:8080
# Devrait timeout (non autorisé)

# Nettoyer
kubectl delete namespace my-app
```

**✅ Validation :**
- Frontend accessible de partout
- Backend isolé (pas accessible directement)
- Database isolée (uniquement depuis Backend)

---

## Tests Partie 5 : Débogage réseau

### Test 5.1 : Utiliser netshoot

```bash
# Déployer netshoot
kubectl run netshoot --image=nicolaka/netshoot -- sleep 3600

# Créer un service à tester
kubectl create deployment test-app --image=nginx:alpine
kubectl expose deployment test-app --port=80

# Attendre
kubectl wait --for=condition=ready pod -l app=test-app --timeout=60s

# Entrer dans netshoot
kubectl exec -it netshoot -- bash

# Dans netshoot, tester :
curl http://test-app
nslookup test-app
dig test-app.default.svc.cluster.local
ping -c 3 test-app
nc -zv test-app 80

# Nettoyer
kubectl delete pod netshoot
kubectl delete deployment test-app
kubectl delete service test-app
```

**✅ Validation :**
- Tous les outils fonctionnent
- Communication réseau OK

---

## Checklist complète de validation

### ✅ Partie 1 : Modèle réseau
- [ ] Chaque Pod a une IP unique
- [ ] Communication inter-pods fonctionne
- [ ] Pas de NAT entre Pods

### ✅ Partie 2 : Services
- [ ] ClusterIP fonctionne (interne)
- [ ] NodePort accessible depuis l'extérieur
- [ ] Headless Service retourne les IPs des Pods
- [ ] ExternalName résout le CNAME
- [ ] Session Affinity fonctionne

### ✅ Partie 3 : DNS
- [ ] Résolution DNS avec nom court
- [ ] Résolution DNS avec FQDN
- [ ] Résolution inter-namespaces
- [ ] CoreDNS fonctionne

### ✅ Partie 4 : NetworkPolicies
- [ ] Deny all bloque le trafic
- [ ] Allow from specific pods fonctionne
- [ ] Egress rules fonctionnent
- [ ] Architecture multi-tiers isolée

### ✅ Partie 5 : Débogage
- [ ] netshoot installé et fonctionnel
- [ ] Tests de connectivité OK
- [ ] DNS debugging OK
- [ ] Endpoints vérifiés

---

## Problèmes courants et solutions

### NetworkPolicies ne fonctionnent pas

**Cause :** Plugin CNI ne supporte pas les NetworkPolicies (Flannel)

**Solution :**
```bash
# Installer Calico sur minikube
minikube start --cni=calico

# Ou sur un cluster existant
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### DNS ne résout pas

**Cause :** CoreDNS en erreur

**Solution :**
```bash
# Vérifier CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Voir les logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# Redémarrer si nécessaire
kubectl rollout restart deployment coredns -n kube-system
```

### Service sans Endpoints

**Cause :** Selector ne matche aucun Pod

**Solution :**
```bash
# Vérifier les labels
kubectl get pods --show-labels

# Vérifier le selector du service
kubectl describe svc <service-name>

# Corriger les labels si nécessaire
kubectl label pod <pod-name> app=correct-label
```

---

## Script de test automatisé

Un script complet de test est disponible dans `test-tp8.sh`.

```bash
# Rendre le script exécutable
chmod +x test-tp8.sh

# Exécuter tous les tests
./test-tp8.sh

# Exécuter un test spécifique
./test-tp8.sh test_services
```

---

## Conclusion

Ce guide couvre tous les aspects du TP8. Pour des résultats optimaux :

1. Suivre les tests dans l'ordre
2. Vérifier chaque validation
3. Nettoyer entre les tests
4. Consulter les logs en cas d'erreur

**Bon courage ! 🚀**
