# TP8 - Réseau Kubernetes : Services, DNS et Connectivité

## Objectifs du TP

Ce TP vous permettra de maîtriser le réseau dans Kubernetes de manière approfondie et pratique. Vous apprendrez :

- Le modèle réseau Kubernetes et ses principes fondamentaux
- Les différents types de Services et leurs cas d'usage
- Le DNS Kubernetes et la découverte de services
- Les NetworkPolicies pour sécuriser les communications
- Le débogage réseau avec les outils appropriés
- L'implémentation d'architectures réseau complexes

**Durée estimée :** 6-8 heures
**Niveau :** Intermédiaire à Avancé

## Prérequis

- Avoir complété le TP1 (bases Kubernetes) et TP2 (manifests)
- Cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)
- kubectl installé et configuré
- Notions de réseau (IP, ports, DNS)

**Note pour kubeadm :** Les concepts réseau (Services, Ingress, Network Policies) sont identiques. Pour l'Ingress Controller, consultez le [guide kubeadm](../docs/KUBEADM_SETUP.md#113-ingress-controller-nginx-ingress).

## Table des matières

- [Partie 1 : Le modèle réseau Kubernetes](#partie-1--le-modèle-réseau-kubernetes)
- [Partie 2 : Services et types d'exposition](#partie-2--services-et-types-dexposition)
- [Partie 3 : DNS et Service Discovery](#partie-3--dns-et-service-discovery)
- [Partie 4 : NetworkPolicies et sécurité réseau](#partie-4--networkpolicies-et-sécurité-réseau)
- [Partie 5 : Débogage réseau](#partie-5--débogage-réseau)
- [Partie 6 : Architectures réseau avancées](#partie-6--architectures-réseau-avancées)
- [Exercices pratiques](#exercices-pratiques)

---

## Partie 1 : Le modèle réseau Kubernetes

### 1.1 Principes fondamentaux

Kubernetes implémente un modèle réseau "flat" basé sur plusieurs principes clés :

1. **Chaque Pod obtient sa propre adresse IP**
   - Pas de NAT entre Pods
   - Les conteneurs dans un même Pod partagent le même namespace réseau

2. **Communication directe entre Pods**
   - Tous les Pods peuvent communiquer entre eux sans NAT
   - Les Pods sur différents nœuds peuvent se parler directement

3. **Communication Pod-à-Node**
   - Les Pods peuvent communiquer avec tous les nœuds sans NAT
   - Les nœuds peuvent communiquer avec tous les Pods sans NAT

### 1.2 Architecture réseau

```
┌─────────────────────────────────────────────────────────────┐
│                    Cluster Kubernetes                        │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────┐          │
│  │   Node 1         │         │   Node 2         │          │
│  │                  │         │                  │          │
│  │  ┌───────────┐   │         │  ┌───────────┐   │          │
│  │  │ Pod A     │   │         │  │ Pod C     │   │          │
│  │  │ IP: 10.1.1.1 │         │  │ IP: 10.1.2.1 │          │
│  │  └───────────┘   │         │  └───────────┘   │          │
│  │       │          │         │       │          │          │
│  │  ┌───────────┐   │         │  ┌───────────┐   │          │
│  │  │ Pod B     │   │         │  │ Pod D     │   │          │
│  │  │ IP: 10.1.1.2 │         │  │ IP: 10.1.2.2 │          │
│  │  └───────────┘   │         │  └───────────┘   │          │
│  │       │          │         │       │          │          │
│  │  ┌────▼──────┐   │         │  ┌────▼──────┐   │          │
│  │  │  Bridge   │   │         │  │  Bridge   │   │          │
│  │  └─────┬─────┘   │         │  └─────┬─────┘   │          │
│  └────────┼─────────┘         └────────┼─────────┘          │
│           │                            │                     │
│      ┌────▼────────────────────────────▼─────┐               │
│      │      Overlay Network (CNI)            │               │
│      │   (Calico, Flannel, Weave, etc.)      │               │
│      └───────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Container Network Interface (CNI)

Les plugins CNI les plus courants :

| Plugin | Description | Fonctionnalités |
|--------|-------------|-----------------|
| **Calico** | Solution réseau et NetworkPolicy | Routing BGP, NetworkPolicies avancées |
| **Flannel** | Overlay network simple | Simple, léger, orienté overlay |
| **Weave** | Mesh network automatique | Chiffrement, service discovery |
| **Cilium** | Basé sur eBPF | Haute performance, observabilité |
| **Canal** | Calico + Flannel | Networking Flannel + NetworkPolicies Calico |

**🔍 Vérifier le plugin CNI actuel :**

```bash
# Voir les pods du système réseau
kubectl get pods -n kube-system | grep -E 'calico|flannel|weave|cilium'

# Vérifier la configuration CNI
ls /etc/cni/net.d/

# Voir les détails d'un pod pour identifier le réseau
kubectl describe pod <pod-name> | grep "cni"
```

### 1.4 Exercice pratique : Explorer le réseau

**Exercice 1.1 : Visualiser l'adressage IP**

```bash
# Créer plusieurs pods
kubectl create deployment web --image=nginx:alpine --replicas=3

# Voir les IPs des pods
kubectl get pods -o wide

# Voir les détails réseau d'un pod
kubectl describe pod <pod-name> | grep IP
```

**Questions :**
- Quelle est la plage d'adresses IP utilisée pour les Pods ?
- Les Pods sur le même nœud ont-ils des IPs consécutives ?
- Que se passe-t-il si vous supprimez et recréez un Pod ?

**Exercice 1.2 : Communication inter-pods**

```bash
# Créer deux pods
kubectl run pod-a --image=nginx:alpine
kubectl run pod-b --image=nginx:alpine

# Récupérer l'IP du pod-b
POD_B_IP=$(kubectl get pod pod-b -o jsonpath='{.status.podIP}')

# Tester la communication depuis pod-a vers pod-b
kubectl exec pod-a -- wget -qO- http://$POD_B_IP

# Vérifier que la communication fonctionne sans NAT
kubectl exec pod-a -- ping -c 3 $POD_B_IP
```

---

## Partie 2 : Services et types d'exposition

### 2.1 Pourquoi les Services ?

Les Pods sont **éphémères** : ils peuvent être créés, détruits, et leurs IPs changent. Les Services fournissent :

- **Abstraction stable** : Une IP et un DNS qui ne changent pas
- **Load balancing** : Distribution du trafic entre plusieurs Pods
- **Service discovery** : Découverte automatique via DNS

### 2.2 Service ClusterIP (par défaut)

Expose le Service sur une IP interne au cluster.

**Cas d'usage :**
- Communication entre microservices
- Bases de données internes
- APIs backend

**Exemple complet :**

```yaml
# deployment-backend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: nginx:alpine
        ports:
        - containerPort: 80
---
# service-backend.yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - protocol: TCP
    port: 80        # Port du Service
    targetPort: 80  # Port du conteneur
```

**Déploiement et test :**

```bash
# Créer les ressources
kubectl apply -f deployment-backend.yaml

# Vérifier le service
kubectl get svc backend-svc
# NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)
# backend-svc   ClusterIP   10.96.123.45   <none>        80/TCP

# Tester depuis un pod temporaire
kubectl run tmp --image=busybox --rm -it -- wget -qO- http://backend-svc

# Tester avec le FQDN complet
kubectl run tmp --image=busybox --rm -it -- wget -qO- http://backend-svc.default.svc.cluster.local
```

### 2.3 Service NodePort

Expose le Service sur un port statique de chaque nœud.

**Cas d'usage :**
- Développement et tests
- Accès externe sans load balancer cloud
- Applications nécessitant un port spécifique

**Exemple :**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80          # Port du Service (interne)
    targetPort: 80    # Port du conteneur
    nodePort: 30080   # Port sur chaque nœud (30000-32767)
```

**Accès :**

```bash
# Créer le deployment et service
kubectl create deployment web --image=nginx:alpine
kubectl apply -f service-nodeport.yaml

# Obtenir l'IP du nœud
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Accéder au service (si minikube)
minikube service web-nodeport --url

# Ou directement avec curl
curl http://$NODE_IP:30080
```

### 2.4 Service LoadBalancer

Expose le Service via un load balancer cloud (AWS ELB, GCP LB, etc.).

**Cas d'usage :**
- Production sur cloud provider
- Applications exposées publiquement
- Haute disponibilité

**Exemple :**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

**Note pour minikube :**

```bash
# Sur minikube, utiliser le tunnel pour simuler un LoadBalancer
minikube tunnel

# Dans un autre terminal
kubectl get svc web-lb
# EXTERNAL-IP passera de <pending> à une IP
```

### 2.5 Service ExternalName

Crée un alias DNS vers un service externe.

**Cas d'usage :**
- Intégration avec services externes
- Migration progressive vers Kubernetes
- Abstraction des dépendances externes

**Exemple :**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-db
spec:
  type: ExternalName
  externalName: database.example.com
```

**Utilisation :**

```bash
# Les pods peuvent maintenant utiliser "external-db" au lieu de "database.example.com"
kubectl run tmp --image=busybox --rm -it -- nslookup external-db
```

### 2.6 Headless Service

Service sans IP de cluster (ClusterIP: None), pour un accès direct aux IPs des Pods.

**Cas d'usage :**
- StatefulSets et bases de données
- Communication P2P entre Pods
- Service discovery personnalisé

**Exemple :**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db-headless
spec:
  clusterIP: None
  selector:
    app: database
  ports:
  - port: 3306
```

**Test :**

```bash
# Créer des pods avec le label app=database
kubectl create deployment db --image=mysql:8 --replicas=3
kubectl set env deployment/db MYSQL_ROOT_PASSWORD=secret

# Créer le headless service
kubectl apply -f headless-service.yaml

# Faire un DNS lookup
kubectl run tmp --image=busybox --rm -it -- nslookup db-headless
# Retourne les IPs de tous les Pods, pas une seule IP de service
```

### 2.7 Endpoints et EndpointSlices

Les Services utilisent des **Endpoints** pour suivre les IPs des Pods.

```bash
# Voir les endpoints d'un service
kubectl get endpoints backend-svc

# Voir les détails
kubectl describe endpoints backend-svc

# Depuis Kubernetes 1.21, utiliser EndpointSlices (plus scalable)
kubectl get endpointslices
```

**Créer un Service avec Endpoints manuels (pour services externes) :**

```yaml
# Service sans selector
apiVersion: v1
kind: Service
metadata:
  name: external-api
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
# Endpoints manuels
apiVersion: v1
kind: Endpoints
metadata:
  name: external-api
subsets:
- addresses:
  - ip: 192.168.1.100
  - ip: 192.168.1.101
  ports:
  - port: 80
```

### 2.8 Session Affinity

Diriger toujours le même client vers le même Pod.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-service
spec:
  selector:
    app: web
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600
  ports:
  - port: 80
```

---

## Partie 3 : DNS et Service Discovery

### 3.1 DNS dans Kubernetes

Kubernetes inclut un serveur DNS (CoreDNS par défaut) qui crée automatiquement des enregistrements pour les Services et Pods.

**Architecture DNS :**

```
┌─────────────────────────────────────────────┐
│              Pod Application                 │
│                                              │
│  Requête DNS: backend-svc.default.svc.cluster.local
│                     │                        │
└─────────────────────┼─────────────────────────┘
                      │
                      ▼
           ┌─────────────────┐
           │    CoreDNS      │
           │ (kube-system)   │
           └─────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   Service IP    Endpoints     Pod IPs
```

### 3.2 Format DNS des Services

**Format complet (FQDN) :**

```
<service-name>.<namespace>.svc.<cluster-domain>
```

**Exemples :**

```bash
# Service "backend-svc" dans namespace "default"
backend-svc.default.svc.cluster.local

# Service "api" dans namespace "production"
api.production.svc.cluster.local
```

**Formes courtes (depuis un Pod) :**

```bash
# Même namespace
backend-svc

# Autre namespace (il faut le namespace)
api.production

# FQDN complet fonctionne partout
api.production.svc.cluster.local
```

### 3.3 DNS pour les Pods

Les Pods obtiennent aussi des enregistrements DNS.

**Format :**

```
<pod-ip-address>.<namespace>.pod.<cluster-domain>
```

**Exemple :**

```bash
# Pod avec IP 10.244.1.5 dans namespace default
10-244-1-5.default.pod.cluster.local
```

**Pour les Pods d'un Headless Service :**

```
<pod-name>.<headless-service-name>.<namespace>.svc.<cluster-domain>
```

### 3.4 Exercices pratiques DNS

**Exercice 3.1 : Résolution DNS entre namespaces**

```bash
# Créer deux namespaces
kubectl create namespace frontend
kubectl create namespace backend

# Créer un service dans backend
kubectl create deployment api -n backend --image=nginx:alpine
kubectl expose deployment api -n backend --port=80

# Créer un pod dans frontend
kubectl run test -n frontend --image=busybox --rm -it -- sh

# Dans le pod, tester les différentes formes DNS
wget -qO- http://api.backend
wget -qO- http://api.backend.svc
wget -qO- http://api.backend.svc.cluster.local

# Tenter d'accéder avec juste le nom (devrait échouer - namespace différent)
wget -qO- http://api  # ERREUR
```

**Exercice 3.2 : Debug DNS**

```bash
# Tester la résolution DNS
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --rm -it -- sh

# Dans le pod
nslookup kubernetes.default
nslookup backend-svc.default.svc.cluster.local
host backend-svc.default.svc.cluster.local

# Voir la configuration DNS du pod
cat /etc/resolv.conf
```

**Sortie attendue (/etc/resolv.conf) :**

```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

### 3.5 Configuration DNS des Pods

Personnaliser la configuration DNS d'un Pod :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-dns
spec:
  containers:
  - name: app
    image: nginx:alpine
  dnsPolicy: "None"
  dnsConfig:
    nameservers:
      - 8.8.8.8
    searches:
      - custom.local
    options:
      - name: ndots
        value: "2"
```

**Politiques DNS disponibles :**

- `ClusterFirst` (défaut) : Utilise CoreDNS du cluster
- `Default` : Hérite du nœud
- `ClusterFirstWithHostNet` : Pour pods avec hostNetwork
- `None` : Configuration manuelle

---

## Partie 4 : NetworkPolicies et sécurité réseau

### 4.1 Principe des NetworkPolicies

Par défaut, **tous les Pods peuvent communiquer avec tous les Pods**. Les NetworkPolicies permettent de restreindre ce trafic.

**⚠️ Important :** Les NetworkPolicies nécessitent un plugin CNI qui les supporte (Calico, Cilium, Weave, etc.). **Flannel ne supporte PAS les NetworkPolicies**.

**Vérifier le support :**

```bash
# Voir le plugin CNI
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'
```

### 4.2 Comportement par défaut

```yaml
# NetworkPolicy qui deny tout le trafic ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}  # S'applique à tous les pods du namespace
  policyTypes:
  - Ingress
```

```yaml
# NetworkPolicy qui deny tout le trafic egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

### 4.3 Allow depuis des Pods spécifiques

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

**Schéma :**

```
┌──────────────┐
│ Pod frontend │
│ (app=frontend)
└──────┬───────┘
       │ ✅ AUTORISÉ sur port 8080
       ▼
┌──────────────┐
│ Pod backend  │
│ (app=backend)│
└──────────────┘
       ▲
       │ ❌ REFUSÉ
┌──────┴───────┐
│  Autre Pod   │
└──────────────┘
```

### 4.4 Allow depuis un Namespace spécifique

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-admin-ns
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: admin
    ports:
    - protocol: TCP
      port: 80
```

**⚠️ N'oubliez pas de labelliser le namespace :**

```bash
kubectl label namespace admin name=admin
```

### 4.5 Règles Egress

Contrôler le trafic sortant des Pods :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-and-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  # Autoriser DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Autoriser l'API backend
  - to:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 8080
```

### 4.6 Utilisation d'ipBlock

Autoriser/bloquer des plages d'IPs :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-cidr
spec:
  podSelector:
    matchLabels:
      app: public-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 192.168.1.0/24
        except:
        - 192.168.1.5/32
    ports:
    - protocol: TCP
      port: 443
```

### 4.7 Exemple complet : Architecture 3-tiers

```yaml
---
# Frontend peut accéder au Backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-to-backend
  namespace: app
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
---
# Backend peut accéder à la Database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-to-database
  namespace: app
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
---
# Database : allow egress pour DNS uniquement
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-egress
  namespace: app
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Schéma de l'architecture :**

```
Internet
   │
   ▼
┌──────────────┐
│  Frontend    │  (tier=frontend)
│  Pods        │
└──────┬───────┘
       │ port 8080 ✅
       ▼
┌──────────────┐
│  Backend     │  (tier=backend)
│  Pods        │
└──────┬───────┘
       │ port 5432 ✅
       ▼
┌──────────────┐
│  Database    │  (tier=database)
│  Pods        │  (egress limité au DNS)
└──────────────┘
```

---

## Partie 5 : Débogage réseau

### 5.1 Outils de débogage

**Créer un pod de debug avec tous les outils :**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: netshoot
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ['sh', '-c', 'sleep 3600']
```

**Outils disponibles dans netshoot :**
- `curl`, `wget` : Tests HTTP
- `ping`, `traceroute` : Tests ICMP
- `nslookup`, `dig`, `host` : DNS
- `netstat`, `ss` : Connexions réseau
- `tcpdump` : Capture de paquets
- `nmap` : Scan de ports

### 5.2 Tests de connectivité

**Test HTTP :**

```bash
kubectl exec netshoot -- curl -v http://backend-svc
kubectl exec netshoot -- wget -O- --timeout=5 http://backend-svc
```

**Test DNS :**

```bash
kubectl exec netshoot -- nslookup backend-svc
kubectl exec netshoot -- dig backend-svc.default.svc.cluster.local
kubectl exec netshoot -- host backend-svc
```

**Test de port :**

```bash
# Tester si un port est ouvert
kubectl exec netshoot -- nc -zv backend-svc 80

# Scanner les ports
kubectl exec netshoot -- nmap -p 1-1000 <pod-ip>
```

**Test ICMP :**

```bash
kubectl exec netshoot -- ping -c 3 <pod-ip>
```

### 5.3 Diagnostic des Services

```bash
# Vérifier que le service existe
kubectl get svc backend-svc

# Vérifier les endpoints
kubectl get endpoints backend-svc
kubectl describe endpoints backend-svc

# Vérifier les labels
kubectl get pods --show-labels
kubectl get pods -l app=backend

# Voir les détails du service
kubectl describe svc backend-svc
```

**Problèmes courants :**

| Problème | Cause probable | Solution |
|----------|----------------|----------|
| Endpoints vide | Selector ne matche aucun Pod | Vérifier labels et selector |
| Service timeout | NetworkPolicy bloque | Vérifier NetworkPolicies |
| DNS ne résout pas | CoreDNS en erreur | Vérifier pods kube-system |
| Connection refused | Port incorrect | Vérifier targetPort vs containerPort |

### 5.4 Debug NetworkPolicies

```bash
# Lister toutes les NetworkPolicies
kubectl get networkpolicies --all-namespaces

# Voir les détails
kubectl describe networkpolicy deny-all-ingress

# Tester la connectivité
kubectl run test --image=busybox --rm -it -- wget --timeout=2 http://<pod-ip>
# Si timeout = NetworkPolicy bloque probablement
```

**Méthodologie de debug :**

1. **Vérifier que le plugin CNI supporte NetworkPolicies**
2. **Tester sans NetworkPolicy** (supprimer temporairement)
3. **Vérifier les labels** des Pods et Namespaces
4. **Tester étape par étape** (ingress puis egress)
5. **Utiliser les logs** des pods CNI

### 5.5 Capture de paquets avec tcpdump

```bash
# Dans un pod netshoot
kubectl exec -it netshoot -- tcpdump -i any port 80

# Capturer et sauvegarder
kubectl exec netshoot -- tcpdump -i any -w /tmp/capture.pcap

# Copier le fichier localement
kubectl cp netshoot:/tmp/capture.pcap ./capture.pcap

# Analyser avec Wireshark
wireshark capture.pcap
```

### 5.6 Vérifier CoreDNS

```bash
# Status des pods CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Logs CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns

# ConfigMap CoreDNS
kubectl get configmap coredns -n kube-system -o yaml
```

---

## Partie 6 : Architectures réseau avancées

### 6.1 Architecture microservices sécurisée

```yaml
---
# Namespace avec NetworkPolicies par défaut
apiVersion: v1
kind: Namespace
metadata:
  name: secure-app
---
# Deny all ingress par défaut
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: secure-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Frontend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: secure-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      tier: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      containers:
      - name: frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
---
# Frontend Service
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: secure-app
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    nodePort: 30080
---
# Allow ingress to frontend from anywhere
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-ingress
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - ports:
    - protocol: TCP
      port: 80
---
# Backend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: secure-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
      tier: backend
  template:
    metadata:
      labels:
        app: backend
        tier: backend
    spec:
      containers:
      - name: backend
        image: nginx:alpine
        ports:
        - containerPort: 8080
---
# Backend Service (ClusterIP)
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: secure-app
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - port: 8080
    targetPort: 8080
---
# Allow backend ingress from frontend only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-from-frontend
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
---
# Database StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database
  namespace: secure-app
spec:
  serviceName: database-headless
  replicas: 1
  selector:
    matchLabels:
      app: database
      tier: database
  template:
    metadata:
      labels:
        app: database
        tier: database
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          value: "secret"
---
# Database Headless Service
apiVersion: v1
kind: Service
metadata:
  name: database-headless
  namespace: secure-app
spec:
  clusterIP: None
  selector:
    app: database
  ports:
  - port: 5432
---
# Allow database access from backend only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-database-from-backend
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 6.2 Multi-tenancy avec isolation réseau

```yaml
---
# Namespace Tenant A
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    tenant: a
---
# Namespace Tenant B
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-b
  labels:
    tenant: b
---
# Deny cross-tenant traffic pour Tenant A
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-other-tenants
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: a
---
# Deny cross-tenant traffic pour Tenant B
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-other-tenants
  namespace: tenant-b
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: b
```

### 6.3 Monitoring avec Service Mesh (aperçu)

Pour des architectures encore plus avancées, considérer un **Service Mesh** comme :

- **Istio** : Fonctionnalités complètes (mTLS, tracing, policies)
- **Linkerd** : Léger et simple
- **Consul Connect** : Integration HashiCorp

**Avantages :**
- mTLS automatique entre services
- Observabilité avancée (tracing distribué)
- Traffic management (canary, circuit breaker)
- Retry et timeout automatiques

---

## Exercices pratiques

### Exercice 1 : Déploiement multi-tiers

**Objectif :** Créer une architecture 3-tiers avec Services appropriés

1. Créer un namespace `my-app`
2. Déployer :
   - **Frontend** : nginx (3 replicas) → NodePort
   - **Backend** : nginx (2 replicas) → ClusterIP
   - **Database** : postgres (1 replica) → Headless Service
3. Configurer les Services
4. Tester la communication entre les tiers

**Vérifications :**
- Frontend accessible depuis l'extérieur
- Backend accessible depuis Frontend
- Database accessible depuis Backend uniquement

### Exercice 2 : NetworkPolicies progressives

**Objectif :** Sécuriser l'exercice 1 avec NetworkPolicies

1. Appliquer une politique "deny all" par défaut
2. Autoriser l'ingress vers Frontend depuis l'extérieur
3. Autoriser Frontend → Backend
4. Autoriser Backend → Database
5. Autoriser DNS pour tous les Pods
6. Tester que les restrictions fonctionnent

### Exercice 3 : Service Discovery

**Objectif :** Maîtriser le DNS Kubernetes

1. Créer 2 namespaces : `ns-a` et `ns-b`
2. Déployer un service dans chaque namespace
3. Tester les différentes formes DNS
4. Configurer un ExternalName pour un service externe
5. Vérifier la résolution DNS avec dig/nslookup

### Exercice 4 : Debug réseau

**Objectif :** Diagnostiquer et résoudre des problèmes réseau

**Scénarios à résoudre :**

1. Service sans Endpoints
2. DNS qui ne résout pas
3. NetworkPolicy qui bloque le trafic
4. Mauvais targetPort configuré

**Outils à utiliser :**
- kubectl describe
- kubectl logs
- Pod netshoot
- tcpdump

### Exercice 5 : Load balancing et Session Affinity

**Objectif :** Comprendre le load balancing des Services

1. Créer un Deployment avec 5 replicas
2. Créer un Service standard (round-robin)
3. Générer du trafic et observer la distribution
4. Activer sessionAffinity
5. Observer le changement de comportement

---

## Résumé des concepts clés

### Types de Services

| Type | Cas d'usage | Accessible depuis |
|------|-------------|-------------------|
| ClusterIP | Communication interne | Cluster uniquement |
| NodePort | Dev/test, accès externe simple | Extérieur via NodeIP:NodePort |
| LoadBalancer | Production cloud | Extérieur via IP publique |
| ExternalName | Alias DNS vers externe | Cluster (résolution DNS) |
| Headless | StatefulSet, accès direct Pods | Cluster (retourne IPs des Pods) |

### NetworkPolicy : Sélecteurs

```yaml
# Sélectionner des Pods
podSelector:
  matchLabels:
    app: backend

# Sélectionner des Namespaces
namespaceSelector:
  matchLabels:
    env: production

# Sélectionner des IPs
ipBlock:
  cidr: 192.168.1.0/24
  except:
  - 192.168.1.5/32
```

### DNS Kubernetes

```
# Format complet
<service>.<namespace>.svc.<cluster-domain>

# Exemples
backend.default.svc.cluster.local
api.production.svc.cluster.local

# Forme courte (même namespace)
backend

# Avec namespace
backend.default
```

### Commandes essentielles

```bash
# Services
kubectl get svc
kubectl describe svc <name>
kubectl get endpoints <name>

# NetworkPolicies
kubectl get networkpolicies
kubectl describe networkpolicy <name>

# DNS Debug
kubectl run tmp --image=busybox --rm -it -- nslookup <service>

# Connectivité
kubectl exec <pod> -- curl http://<service>
kubectl exec <pod> -- nc -zv <host> <port>
```

---

## Ressources complémentaires

### Documentation officielle

- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Gateway API](https://gateway-api.sigs.k8s.io/) — successeur de l'Ingress (stable K8s 1.31)

### Outils et plugins

- [Calico](https://www.projectcalico.org/) - NetworkPolicy et networking
- [Cilium](https://cilium.io/) - eBPF-based networking (recommandé pour nouveaux clusters)
- [CoreDNS](https://coredns.io/) - DNS server

### Guides avancés

- [Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Debugging DNS Resolution](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)
- [Gateway API — Guide de migration depuis Ingress](https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/)
- [Service Mesh Comparison](https://servicemesh.es/)

---

## Partie 7 : Gateway API — Le futur du réseau Kubernetes (K8s 1.31+)

La **Gateway API** est le successeur standardisé de l'Ingress, stable depuis Kubernetes 1.31. Elle résout les limitations de l'Ingress en proposant une hiérarchie d'objets claire.

### 7.1 Modèle mental : Ingress vs Gateway API

```
INGRESS (ancien modèle)            GATEWAY API (nouveau modèle)
─────────────────────────          ──────────────────────────────────────────
                                   GatewayClass  (admin infra : type de LB)
Ingress Controller                      │
    │                                   ▼
    └── Ingress                    Gateway  (admin cluster : point d'entrée)
         (routes HTTP/HTTPS)            │
                                        ▼
                                   HTTPRoute  (équipe app : règles de routage)
                                   TCPRoute   (idem pour TCP)
                                   TLSRoute   (idem pour TLS)
```

### 7.2 Concepts clés

**GatewayClass** — Définit le type de contrôleur (nginx, envoy, istio, etc.) :
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: gateway.nginx.org/nginx-gateway-controller
```

**Gateway** — Point d'entrée avec les listeners (ports, protocoles, TLS) :
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gateway
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      certificateRefs:
      - name: tls-cert
    allowedRoutes:
      namespaces:
        from: All  # Accepte des routes de tous les namespaces
```

**HTTPRoute** — Règles de routage (peut être géré par chaque équipe applicative) :
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-routes
  namespace: team-a  # L'équipe A gère ses propres routes
spec:
  parentRefs:
  - name: prod-gateway
    namespace: infra       # Pointe vers le Gateway de l'infra
  hostnames: ["api.example.com"]
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v2
      headers:
      - name: X-API-Version
        value: "2"
    backendRefs:
    - name: api-v2-service
      port: 8080
      weight: 100
  - matches:
    - path:
        type: PathPrefix
        value: /v2
    backendRefs:
    - name: api-v1-service
      port: 8080
      weight: 100
```

### 7.3 Exercice : Implémenter un canary avec Gateway API

Un **canary deployment** avec la Gateway API est plus propre et portable qu'avec des annotations Ingress.

**Scénario :** Vous avez `api-v1` en production. Vous déployez `api-v2` et voulez lui envoyer 10% du trafic.

```yaml
# canary-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-canary
spec:
  parentRefs:
  - name: prod-gateway
  hostnames: ["api.local"]
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: api-v1-service
      port: 8080
      weight: 90   # 90% du trafic vers v1
    - name: api-v2-service
      port: 8080
      weight: 10   # 10% vers v2 (canary)
```

**Questions de réflexion :**
- Quelle est la différence entre ce canary et celui basé sur des annotations Ingress NGINX ?
- Qui devrait avoir le droit de modifier l'objet `Gateway` vs l'objet `HTTPRoute` ?
- Pourquoi les `weight` sont-ils plus flexibles que le canary par pourcentage d'Ingress ?
- Recherchez : quelles implémentations (contrôleurs) supportent la Gateway API aujourd'hui ?

---

## Prochaines étapes

Après avoir maîtrisé ce TP, vous pouvez explorer :

1. **Gateway API** — Implémentez des scénarios multi-équipes et multi-tenants
2. **Ingress Controllers** (TP6) pour approfondir avec Helm et ArgoCD
3. **Service Mesh** (Istio, Linkerd) pour mTLS et observabilité — complémentaire à la Gateway API
4. **Cilium** — CNI eBPF avec NetworkPolicies L7 et Gateway API intégrée
5. **Multi-cluster networking** avec Cilium Cluster Mesh ou Submariner

---

**🎉 Félicitations !** Vous maîtrisez maintenant le réseau Kubernetes !

N'hésitez pas à expérimenter avec différentes architectures et à pratiquer le débogage réseau. Le réseau est un aspect fondamental de Kubernetes, et cette maîtrise vous sera précieuse dans vos déploiements en production.
