# TP1 - Premier déploiement Kubernetes sur AlmaLinux

> **💻 Utilisateurs Windows :** Consultez le [guide spécifique Windows (WINDOWS.md)](WINDOWS.md) qui adapte ce TP pour Windows avec Minikube ou WSL2. Voir aussi le [guide d'installation Windows complet](../docs/WINDOWS_SETUP.md).

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Installer et configurer un cluster Kubernetes (minikube ou kubeadm)
- Démarrer un cluster Kubernetes
- Déployer votre première application
- Exposer l'application via un service
- Interagir avec les pods et services

## Prérequis

### Pour minikube (développement local)
- Une machine AlmaLinux (physique ou virtuelle) **ou Windows** ([voir guide Windows](WINDOWS.md))
- 2 CPU minimum (4 CPU recommandé pour Windows)
- 2 Go de RAM minimum (4 Go recommandé pour Windows)
- 20 Go d'espace disque
- Accès root ou sudo (ou droits administrateur sur Windows)

### Pour kubeadm (environnement multi-nœuds)
- 2-3 machines AlmaLinux (1 master + 1-2 workers) **ou WSL2 sur Windows**
- **Master :** 2 CPU, 2 Go RAM, 20 Go disque
- **Workers :** 1 CPU, 1 Go RAM, 20 Go disque
- Réseau entre les machines
- Accès root ou sudo

## Choix de votre environnement

Ce TP peut être réalisé avec **deux approches différentes** :

### Option A : minikube (recommandé pour débuter)
- ✅ Installation rapide et simple
- ✅ Idéal pour le développement local
- ✅ Nécessite une seule machine
- ✅ Gestion automatique du réseau
- ❌ Ne reflète pas un environnement de production
- ❌ Limitations pour le multi-nœud

### Option B : kubeadm (recommandé pour la production)
- ✅ Architecture réaliste multi-nœuds
- ✅ Proche d'un environnement de production
- ✅ Contrôle total sur la configuration
- ✅ Scalabilité native
- ❌ Installation plus complexe
- ❌ Nécessite plusieurs machines

**💡 Conseil :** Commencez avec minikube pour apprendre les concepts, puis passez à kubeadm pour comprendre la production.

---

## Partie 1 : Installation de l'environnement

### 1.1 Mise à jour du système

```bash
sudo dnf update -y
```

### 1.2 Installation de Docker

```bash
# Installer les dépendances
sudo dnf install -y yum-utils device-mapper-persistent-data lvm2

# Ajouter le repository Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Installer Docker
sudo dnf install -y docker-ce docker-ce-cli containerd.io

# Démarrer et activer Docker
sudo systemctl start docker
sudo systemctl enable docker

# Ajouter votre utilisateur au groupe docker
sudo usermod -aG docker $USER

# Appliquer les changements (ou se reconnecter)
newgrp docker
```

### 1.3 Alternative : Utilisation avec Podman sur WSL

> **💡 Section pour les utilisateurs WSL avec Podman** : Si vous utilisez Windows avec WSL2 et préférez Podman à Docker, cette section est pour vous. Podman est une alternative sans démon (daemonless) et rootless à Docker.

#### Pourquoi Podman ?

- **Rootless par défaut** : Pas besoin de privilèges root pour exécuter des conteneurs
- **Sans démon** : Pas de service en arrière-plan à maintenir
- **Compatible OCI** : Mêmes images que Docker
- **Intégration WSL** : Fonctionne bien dans WSL2

#### Installation de Podman dans WSL (Ubuntu/Debian)

```bash
# Mettre à jour les paquets
sudo apt update && sudo apt upgrade -y

# Installer Podman
sudo apt install -y podman

# Vérifier l'installation
podman --version

# Tester avec un conteneur
podman run --rm hello-world
```

#### Installation de Podman dans WSL (Fedora/AlmaLinux)

```bash
# Installer Podman
sudo dnf install -y podman

# Vérifier l'installation
podman --version
```

#### Configuration de minikube avec Podman

```bash
# Configurer Podman comme driver par défaut pour minikube
minikube config set driver podman

# OU démarrer minikube avec le driver Podman explicitement
minikube start --driver=podman

# Si vous rencontrez des problèmes avec rootless, utilisez :
minikube start --driver=podman --container-runtime=containerd
```

#### Résolution des problèmes courants avec Podman + WSL

**Problème : "cannot find crun"**
```bash
# Installer crun (runtime OCI léger)
sudo apt install -y crun
# ou sur Fedora/AlmaLinux
sudo dnf install -y crun
```

**Problème : Erreurs de réseau ou de registre**
```bash
# Configurer les registries non qualifiés
mkdir -p ~/.config/containers
cat > ~/.config/containers/registries.conf << 'EOF'
unqualified-search-registries = ["docker.io", "quay.io"]

[[registry]]
location = "docker.io"
EOF
```

**Problème : "rootless mode requires a user namespace"**
```bash
# Vérifier que les user namespaces sont activés
cat /proc/sys/user/max_user_namespaces
# Si la valeur est 0, activer avec :
echo "user.max_user_namespaces=28633" | sudo tee /etc/sysctl.d/userns.conf
sudo sysctl -p /etc/sysctl.d/userns.conf
```

**Problème : minikube ne démarre pas avec Podman**
```bash
# Option 1 : Utiliser le mode rootful (nécessite sudo)
minikube start --driver=podman --rootless=false

# Option 2 : Vérifier les prérequis
podman system info
minikube start --driver=podman --alsologtostderr -v=4
```

**Problème : Erreur "aardvark-dns" ou résolution DNS**
```bash
# Installer les plugins réseau manquants
sudo apt install -y aardvark-dns netavark
# ou sur Fedora/AlmaLinux
sudo dnf install -y aardvark-dns netavark

# Redémarrer Podman
podman system reset
```

#### Commandes Podman utiles

```bash
# Équivalent de docker ps
podman ps -a

# Voir les images
podman images

# Nettoyer les ressources inutilisées
podman system prune -a

# Voir les informations système
podman system info

# Debugger un problème
podman system connection list
```

#### Alias pour compatibilité Docker

Si vous avez des scripts qui utilisent la commande `docker`, vous pouvez créer un alias :

```bash
# Ajouter à ~/.bashrc ou ~/.zshrc
echo 'alias docker=podman' >> ~/.bashrc
source ~/.bashrc
```

**Note :** Certaines commandes Docker avancées peuvent ne pas avoir d'équivalent exact dans Podman.

---

### 1.4 Installation de kubectl

```bash
# Télécharger kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Rendre le binaire exécutable
chmod +x kubectl

# Déplacer vers /usr/local/bin
sudo mv kubectl /usr/local/bin/

# Vérifier l'installation
kubectl version --client
```

### 1.5 Installation de minikube (Option A)

**Si vous choisissez minikube :**

```bash
# Télécharger minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Installer minikube
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Vérifier l'installation
minikube version
```

### 1.6 Installation de kubeadm (Option B)

**Si vous choisissez kubeadm :**

Pour une installation complète avec kubeadm, consultez le **[Guide d'installation kubeadm](../docs/KUBEADM_SETUP.md)** qui couvre :
- La préparation des nœuds (désactivation swap, modules kernel, etc.)
- L'installation de containerd
- L'installation de kubeadm, kubelet et kubectl
- L'initialisation du cluster
- L'ajout de workers
- La configuration du réseau (CNI)

**Installation rapide (résumé) :**

```bash
# Sur TOUS les nœuds (master et workers)

# 1. Désactiver swap et SELinux
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# 2. Configurer les modules kernel
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 3. Installer containerd
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 4. Installer kubeadm, kubelet et kubectl
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
```

**Sur le nœud MASTER uniquement :**

```bash
# Initialiser le cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configurer kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installer Flannel (CNI)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Sur chaque nœud WORKER :**

```bash
# Utiliser la commande 'kubeadm join' affichée après l'init sur le master
# Exemple :
# sudo kubeadm join <master-ip>:6443 --token <token> \
#   --discovery-token-ca-cert-hash sha256:<hash>
```

**💡 Note :** Consultez le [guide complet kubeadm](../docs/KUBEADM_SETUP.md) pour plus de détails et le dépannage.

---

## Partie 2 : Démarrage du cluster Kubernetes

### 2.1 Option A : Démarrer minikube

**Si vous utilisez minikube :**

```bash
# Démarrer minikube avec Docker comme driver
minikube start --driver=docker

# Vérifier le statut
minikube status
```

**Résultat attendu :**
```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

### 2.1 Option B : Vérifier le cluster kubeadm

**Si vous utilisez kubeadm :**

Après avoir suivi les étapes d'installation de la section 1.6, vérifiez que votre cluster est opérationnel :

```bash
# Vérifier que tous les pods système sont prêts
kubectl get pods -n kube-system

# Attendre que tous les pods soient Running
kubectl wait --for=condition=ready pod --all -n kube-system --timeout=300s
```

**Résultat attendu :** Tous les pods (coredns, flannel, kube-proxy, etc.) doivent être en état `Running`.

### 2.2 Vérifier le cluster

**Ces commandes fonctionnent pour minikube ET kubeadm :**

```bash
# Afficher les informations du cluster
kubectl cluster-info

# Lister les nœuds
kubectl get nodes

# Afficher plus de détails sur les nœuds
kubectl describe nodes
```

**Avec minikube, vous verrez :**
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   5m    v1.29.0
```

**Avec kubeadm (exemple 1 master + 2 workers), vous verrez :**
```
NAME              STATUS   ROLES           AGE   VERSION
master-node       Ready    control-plane   10m   v1.29.0
worker-node-1     Ready    <none>          5m    v1.29.0
worker-node-2     Ready    <none>          4m    v1.29.0
```

## Partie 3 : Premier déploiement

### 3.1 Déployer une application Nginx

```bash
# Créer un déploiement nginx
kubectl create deployment nginx-demo --image=nginx:latest

# Vérifier le déploiement
kubectl get deployments

# Vérifier les pods
kubectl get pods
```

### 3.2 Comprendre ce qui se passe en coulisse

Lorsque vous exécutez `kubectl create deployment nginx-demo --image=nginx:latest`, voici le processus complet qui se déroule dans votre cluster Kubernetes :

#### Le flux de création du déploiement

**1. kubectl → API Server**
- `kubectl` envoie une requête HTTP REST à l'**API Server** de Kubernetes
- L'API Server authentifie et autorise la requête
- La définition du Deployment est stockée dans **etcd** (la base de données du cluster)

**2. Deployment Controller**
- Le **Deployment Controller** (dans `kube-controller-manager`) détecte le nouveau Deployment
- Il crée automatiquement un **ReplicaSet** pour gérer les pods
- Le ReplicaSet spécifie 1 réplica par défaut

**3. ReplicaSet Controller**
- Le **ReplicaSet Controller** crée la définition d'un **Pod** avec le conteneur nginx

**4. Scheduler**
- Le **kube-scheduler** cherche le meilleur nœud disponible
- Il assigne le pod à un nœud en fonction des ressources disponibles

**5. Kubelet (sur le nœud sélectionné)**
- Le **kubelet** reçoit l'instruction de créer le pod
- Il communique avec le **container runtime** (containerd, Docker, CRI-O)
- C'est ici que l'image va être téléchargée !

#### Où Kubernetes va-t-il chercher l'image ?

Quand vous spécifiez `--image=nginx:latest`, le nom complet implicite est :

```
docker.io/library/nginx:latest
└────┬────┘ └──┬──┘ └─┬─┘ └──┬─┘
  Registry  Namespace Nom  Tag
```

- **Registry** : `docker.io` (Docker Hub) - **DÉFAUT** si non spécifié
- **Namespace** : `library` (images officielles Docker) - **DÉFAUT**
- **Image** : `nginx`
- **Tag** : `latest`

**Processus de téléchargement :**

1. Le kubelet demande au container runtime l'image `nginx:latest`
2. Le runtime vérifie si l'image existe localement
3. Si elle n'existe pas, il contacte `https://registry-1.docker.io`
4. Il télécharge les différentes couches (layers) de l'image
5. Il extrait et assemble l'image
6. Il crée et démarre le conteneur

**Schéma du flux complet :**

```
Vous (kubectl)
    │
    ▼
┌───────────────────────────────────────────┐
│      Cluster Kubernetes                   │
│                                          │
│  API Server → etcd                       │
│       ↓                                  │
│  Deployment Controller                   │
│       ↓                                  │
│  ReplicaSet Controller                   │
│       ↓                                  │
│  Scheduler                               │
│       ↓                                  │
│  ┌────────────────────────┐             │
│  │  Nœud (minikube)       │             │
│  │                        │             │
│  │  Kubelet               │             │
│  │    ↓                   │             │
│  │  Container Runtime     │             │
│  └────────┬───────────────┘             │
│           │                              │
└───────────┼──────────────────────────────┘
            │ Pull image
            ▼
    ┌─────────────────┐
    │   Docker Hub    │  registry-1.docker.io
    │  nginx:latest   │  (image officielle)
    └─────────────────┘
```

#### Vérifier le processus en temps réel

Vous pouvez observer ce qui se passe avec les commandes suivantes :

```bash
# Voir les événements du cluster en temps réel
kubectl get events --watch

# Voir les détails du déploiement d'un pod
kubectl describe pod <pod-name>
```

Dans les événements, vous verrez :
```
Type    Reason     Message
----    ------     -------
Normal  Scheduled  Successfully assigned default/nginx-demo-xxx to minikube
Normal  Pulling    Pulling image "nginx:latest"
Normal  Pulled     Successfully pulled image "nginx:latest"
Normal  Created    Created container nginx
Normal  Started    Started container nginx
```

#### Autres registries disponibles

Kubernetes peut télécharger des images depuis n'importe quel registry :

```bash
# Docker Hub (défaut)
kubectl create deployment nginx --image=nginx:latest

# Google Container Registry
kubectl create deployment nginx --image=gcr.io/project/nginx:v1

# Amazon ECR
kubectl create deployment nginx --image=123456789.dkr.ecr.us-east-1.amazonaws.com/nginx:v1

# Registry privé
kubectl create deployment nginx --image=registry.example.com:5000/nginx:v1
```

#### Politique de pull d'image

Le comportement de téléchargement dépend du tag et de la politique `imagePullPolicy` :

- **Tag `latest`** : Kubernetes télécharge toujours l'image (`imagePullPolicy: Always`)
- **Tag spécifique** (ex: `nginx:1.24`) : Kubernetes utilise l'image locale si disponible (`imagePullPolicy: IfNotPresent`)

**💡 Astuce :** En production, évitez d'utiliser le tag `latest`. Préférez des versions spécifiques (ex: `nginx:1.24-alpine`) pour garantir la reproductibilité.

### 3.3 Examiner le pod

```bash
# Obtenir plus d'informations sur le pod
kubectl get pods -o wide

# Décrire le pod (remplacer <pod-name> par le nom réel)
kubectl describe pod <pod-name>

# Voir les logs du pod
kubectl logs <pod-name>
```

## Partie 4 : Comprendre les types de Service Kubernetes

Avant d'exposer notre application, il est important de comprendre les différents types de services disponibles dans Kubernetes. Un **Service** est une abstraction qui définit un ensemble logique de pods et une politique d'accès à ces pods.

### 4.1 Les trois types de Service principaux

#### ClusterIP (par défaut)

**Description :** Expose le service sur une IP interne au cluster. Ce type rend le service accessible uniquement depuis l'intérieur du cluster Kubernetes.

**Cas d'usage :**
- Communication entre services internes (ex: backend vers base de données)
- Services qui ne doivent pas être accessibles depuis l'extérieur
- Micro-services communiquant entre eux

**Exemple :**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-internal-service
spec:
  type: ClusterIP  # Peut être omis car c'est la valeur par défaut
  selector:
    app: my-app
  ports:
  - protocol: TCP
    port: 80          # Port du service
    targetPort: 8080  # Port du conteneur
```

**Schéma conceptuel :**
```
┌─────────────────────────────────────┐
│         Cluster Kubernetes          │
│                                     │
│  ┌──────────┐      ┌──────────┐   │
│  │  Pod A   │─────▶│ Service  │   │
│  └──────────┘      │ClusterIP │   │
│                    │ 10.0.0.5 │   │
│  ┌──────────┐      └──────────┘   │
│  │  Pod B   │─────▶      │         │
│  └──────────┘            ▼         │
│                    ┌──────────┐    │
│                    │  Pods    │    │
│                    │  Backend │    │
│                    └──────────┘    │
└─────────────────────────────────────┘
```

#### NodePort

**Description :** Expose le service sur un port statique de chaque nœud du cluster. Kubernetes alloue automatiquement un port dans la plage 30000-32767 (configurable). Le service devient accessible depuis l'extérieur via `<NodeIP>:<NodePort>`.

**Cas d'usage :**
- Environnements de développement/test (comme minikube)
- Applications qui doivent être accessibles depuis l'extérieur sans load balancer
- Accès direct pour le débogage

**Exemple :**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-nodeport-service
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
  - protocol: TCP
    port: 80           # Port du service
    targetPort: 8080   # Port du conteneur
    nodePort: 30080    # Port sur chaque nœud (optionnel, sinon auto-assigné)
```

**Schéma conceptuel :**
```
┌────────────────────────────────────────┐
│          Cluster Kubernetes            │
│                                        │
│  ┌────────────┐    ┌──────────┐      │
│  │   Node     │    │ Service  │      │
│  │192.168.1.10│    │ NodePort │      │
│  │Port: 30080 │◀───│          │      │
│  └────────────┘    └──────────┘      │
│         │                 │           │
│         └────────────▶┌──────────┐   │
│                       │  Pods    │   │
│                       │  Backend │   │
│                       └──────────┘   │
└────────────────────────────────────────┘
         ▲
         │
    ┌────────┐
    │ Client │ accède via http://192.168.1.10:30080
    │Externe │
    └────────┘
```

#### LoadBalancer

**Description :** Expose le service via un load balancer externe fourni par le cloud provider (AWS ELB, GCP Load Balancer, Azure Load Balancer, etc.). C'est une extension du type NodePort : un service LoadBalancer crée automatiquement un NodePort et demande au cloud provider de créer un load balancer pointant vers ce NodePort.

**Cas d'usage :**
- Applications en production sur des plateformes cloud
- Services qui nécessitent une IP publique stable
- Distribution automatique du trafic avec haute disponibilité

**Exemple :**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-loadbalancer-service
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - protocol: TCP
    port: 80           # Port du load balancer
    targetPort: 8080   # Port du conteneur
```

**Schéma conceptuel :**
```
    ┌────────┐
    │ Client │
    │Internet│
    └────┬───┘
         │
         ▼
┌──────────────────┐
│  Load Balancer   │  ◀─── IP Publique: 203.0.113.10
│  (Cloud Provider)│
└────────┬─────────┘
         │
┌────────┴───────────────────────────────┐
│         Cluster Kubernetes             │
│                                        │
│  ┌────────────┐    ┌──────────┐      │
│  │   Nodes    │    │ Service  │      │
│  │:30080-32767│◀───│LoadBal.  │      │
│  └────────────┘    └──────────┘      │
│         │                 │           │
│         └────────────▶┌──────────┐   │
│                       │  Pods    │   │
│                       │  Backend │   │
│                       └──────────┘   │
└────────────────────────────────────────┘
```

**Note sur minikube :** Dans un environnement minikube (cluster local), le type LoadBalancer sera automatiquement converti en NodePort car il n'y a pas de cloud provider pour créer un vrai load balancer. Minikube fournit la commande `minikube tunnel` pour simuler un load balancer en environnement local.

### 4.2 Tableau comparatif

| Type | Accessible depuis | IP externe | Cas d'usage principal | Port Range |
|------|-------------------|------------|----------------------|------------|
| **ClusterIP** | Cluster uniquement | Non | Services internes | Port du service (ex: 80, 3306) |
| **NodePort** | Externe (NodeIP:Port) | Non | Dev/Test, accès direct | 30000-32767 |
| **LoadBalancer** | Externe (via LB) | Oui | Production cloud | Standard (80, 443, etc.) |

### 4.3 Comment choisir le bon type ?

```
Besoin d'accès externe ?
│
├─ NON  ──▶ ClusterIP
│           (communication interne)
│
└─ OUI
    │
    ├─ Environnement local/dev ?
    │  OUI ──▶ NodePort
    │          (accès via IP:Port du nœud)
    │
    └─ NON (Production cloud)
       └──▶ LoadBalancer
            (IP publique + distribution)
```

## Partie 5 : Exposition de l'application

### 5.1 Exemples concrets pour chaque type de service

Voici des exemples pratiques et déployables pour chaque type de service. Vous pouvez les tester directement dans votre cluster.

#### Exemple 1 : Service ClusterIP - Base de données Redis

**Scénario :** Déployer une base de données Redis qui sera utilisée uniquement par d'autres applications dans le cluster.

```yaml
# redis-clusterip.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
      tier: backend
  template:
    metadata:
      labels:
        app: redis
        tier: backend
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis-service
spec:
  type: ClusterIP  # Accessible uniquement depuis l'intérieur du cluster
  selector:
    app: redis
    tier: backend
  ports:
  - protocol: TCP
    port: 6379
    targetPort: 6379
```

**Déploiement et test :**
```bash
# Déployer Redis avec ClusterIP
kubectl apply -f redis-clusterip.yaml

# Vérifier le service (notez l'IP interne)
kubectl get service redis-service

# Tester l'accès depuis un pod temporaire dans le cluster
kubectl run redis-client --rm -it --image=redis:7-alpine -- redis-cli -h redis-service ping
# Résultat attendu : PONG

# Essayer d'accéder depuis l'extérieur (cela échouera car ClusterIP est interne)
# curl http://<CLUSTER-IP>:6379  # Ne fonctionnera pas depuis votre machine
```

**Cas d'usage réel :** Base de données pour une API, cache interne, message queue (RabbitMQ, Kafka), services de stockage interne.

---

#### Exemple 2 : Service NodePort - Application de développement

**Scénario :** Déployer une application web simple accessible depuis l'extérieur pour les tests et le développement.

```yaml
# webapp-nodeport.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
      env: dev
  template:
    metadata:
      labels:
        app: webapp
        env: dev
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: webapp-html
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-html
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Application de Développement</title></head>
    <body>
      <h1>🚀 Application NodePort</h1>
      <p>Cette application est exposée via NodePort et accessible depuis l'extérieur du cluster.</p>
      <p>Hostname: <span id="hostname"></span></p>
      <script>
        fetch('/hostname.txt').then(r => r.text()).then(h => {
          document.getElementById('hostname').textContent = h || window.location.hostname;
        }).catch(() => {
          document.getElementById('hostname').textContent = window.location.hostname;
        });
      </script>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: webapp-nodeport
spec:
  type: NodePort
  selector:
    app: webapp
    env: dev
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30100  # Port fixe pour un accès prévisible
```

**Déploiement et test :**
```bash
# Déployer l'application avec NodePort
kubectl apply -f webapp-nodeport.yaml

# Vérifier le service et noter le NodePort
kubectl get service webapp-nodeport

# Option A : Avec minikube
minikube service webapp-nodeport --url
curl $(minikube service webapp-nodeport --url)

# Option B : Avec kubeadm
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl http://$NODE_IP:30100

# Ouvrir dans le navigateur
# http://<NODE-IP>:30100
```

**Cas d'usage réel :** Applications de développement/test, API de débogage, dashboards internes, démos temporaires.

---

#### Exemple 3 : Service LoadBalancer - Frontend web en production

**Scénario :** Déployer une application web frontend qui doit être accessible publiquement avec une IP stable.

```yaml
# frontend-loadbalancer.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-prod
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
      tier: web
  template:
    metadata:
      labels:
        app: frontend
        tier: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-loadbalancer
  annotations:
    # Annotations spécifiques aux cloud providers (exemples)
    # AWS ELB
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    # GCP
    cloud.google.com/load-balancer-type: "External"
    # Azure
    service.beta.kubernetes.io/azure-load-balancer-internal: "false"
spec:
  type: LoadBalancer
  selector:
    app: frontend
    tier: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  sessionAffinity: ClientIP  # Optionnel : maintenir les sessions utilisateur
```

**Déploiement et test :**
```bash
# Déployer l'application avec LoadBalancer
kubectl apply -f frontend-loadbalancer.yaml

# Vérifier le service
kubectl get service frontend-loadbalancer -w
# Attendez que EXTERNAL-IP passe de <pending> à une IP réelle

# Sur un cloud provider (AWS, GCP, Azure)
export LB_IP=$(kubectl get service frontend-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$LB_IP

# Avec minikube (simulation de LoadBalancer)
# Terminal 1 : Créer un tunnel
minikube tunnel

# Terminal 2 : Tester l'accès
kubectl get service frontend-loadbalancer
# L'EXTERNAL-IP sera maintenant 127.0.0.1
curl http://127.0.0.1

# Tester la haute disponibilité
# Supprimer un pod et vérifier que le service reste accessible
kubectl delete pod $(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
curl http://$LB_IP  # Fonctionne toujours grâce aux autres réplicas
```

**Cas d'usage réel :** Site web public, API REST publique, application SaaS, microservices exposés à des clients externes.

---

#### Exemple 4 : Architecture complète (3 tiers)

**Scénario :** Application complète avec frontend (LoadBalancer), backend (ClusterIP), et base de données (ClusterIP).

```yaml
# architecture-complete.yaml
# Base de données (ClusterIP - interne uniquement)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: "secretpassword"
        - name: POSTGRES_DB
          value: "appdb"
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: database-service
spec:
  type: ClusterIP  # Accessible uniquement depuis le cluster
  selector:
    app: db
  ports:
  - port: 5432
    targetPort: 5432
---
# Backend API (ClusterIP - appelé par le frontend)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: httpd:2.4-alpine  # Remplacer par votre API réelle
        ports:
        - containerPort: 80
        env:
        - name: DATABASE_HOST
          value: "database-service"  # Utilise le nom du service
        - name: DATABASE_PORT
          value: "5432"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-api-service
spec:
  type: ClusterIP  # Interne, appelé uniquement par le frontend
  selector:
    app: api
  ports:
  - port: 8080
    targetPort: 80
---
# Frontend (LoadBalancer - accessible publiquement)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        env:
        - name: API_URL
          value: "http://backend-api-service:8080"  # Utilise le nom du service
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: LoadBalancer  # Accessible depuis Internet
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
```

**Déploiement et test :**
```bash
# Déployer toute l'architecture
kubectl apply -f architecture-complete.yaml

# Vérifier tous les services
kubectl get services
# Vous devriez voir :
# - database-service (ClusterIP)
# - backend-api-service (ClusterIP)
# - frontend-service (LoadBalancer avec EXTERNAL-IP)

# Tester la connectivité interne
kubectl run test-pod --rm -it --image=busybox -- sh
# Dans le pod :
# wget -qO- http://backend-api-service:8080
# wget -qO- http://database-service:5432
# exit

# Accéder au frontend depuis l'extérieur
# Avec minikube tunnel
minikube tunnel  # Dans un terminal séparé
curl http://127.0.0.1

# Sur un cloud provider
export LB_IP=$(kubectl get service frontend-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$LB_IP
```

**Visualisation de l'architecture :**
```
Internet
   │
   ▼
┌──────────────────┐
│  LoadBalancer    │ ◀── IP Publique (ex: 203.0.113.10)
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│         Cluster Kubernetes              │
│                                         │
│  ┌─────────────────┐                   │
│  │ Frontend Service│ (LoadBalancer)    │
│  │  Port 80        │                   │
│  └────────┬────────┘                   │
│           │                             │
│           ▼                             │
│  ┌─────────────────┐                   │
│  │ Frontend Pods   │                   │
│  │ (3 réplicas)    │                   │
│  └────────┬────────┘                   │
│           │                             │
│           │ Appel HTTP interne          │
│           ▼                             │
│  ┌─────────────────┐                   │
│  │ Backend API Svc │ (ClusterIP)       │
│  │  Port 8080      │                   │
│  └────────┬────────┘                   │
│           │                             │
│           ▼                             │
│  ┌─────────────────┐                   │
│  │ Backend Pods    │                   │
│  │ (2 réplicas)    │                   │
│  └────────┬────────┘                   │
│           │                             │
│           │ Requête SQL                 │
│           ▼                             │
│  ┌─────────────────┐                   │
│  │ Database Svc    │ (ClusterIP)       │
│  │  Port 5432      │                   │
│  └────────┬────────┘                   │
│           │                             │
│           ▼                             │
│  ┌─────────────────┐                   │
│  │ PostgreSQL Pod  │                   │
│  └─────────────────┘                   │
│                                         │
└─────────────────────────────────────────┘
```

---

### 5.2 Créer un service (exemple simple)

```bash
# Exposer le déploiement nginx-demo via un service de type NodePort
kubectl expose deployment nginx-demo --type=NodePort --port=80

# Vérifier le service
kubectl get services
```

**Note :** Nous utilisons NodePort ici car minikube est un environnement local. Pour comprendre quand utiliser NodePort vs ClusterIP vs LoadBalancer, référez-vous à la section 4 ci-dessus.

### 5.3 Accéder à l'application

#### Option A : Avec minikube

```bash
# Obtenir l'URL du service
minikube service nginx-demo --url

# Ou ouvrir directement dans le navigateur
minikube service nginx-demo
```

**Alternative avec curl :**
```bash
# Récupérer l'IP et le port
export NODE_PORT=$(kubectl get services nginx-demo -o jsonpath='{.spec.ports[0].nodePort}')
export NODE_IP=$(minikube ip)

# Tester l'accès
curl http://$NODE_IP:$NODE_PORT
```

#### Option B : Avec kubeadm

Avec kubeadm, vous accédez au service via l'IP de n'importe quel nœud et le NodePort :

```bash
# Récupérer le NodePort assigné
export NODE_PORT=$(kubectl get services nginx-demo -o jsonpath='{.spec.ports[0].nodePort}')

# Récupérer l'IP d'un worker (ou du master si scheduling autorisé)
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Afficher l'URL
echo "Service accessible à : http://$NODE_IP:$NODE_PORT"

# Tester l'accès
curl http://$NODE_IP:$NODE_PORT
```

**Note :** Avec kubeadm en multi-nœuds, le service est accessible via **n'importe quel nœud** du cluster grâce à kube-proxy, même si le pod n'est pas sur ce nœud.

**Astuce :** Pour un accès plus simple en production, considérez :
- **Ingress Controller** : Pour le routage HTTP/HTTPS (voir TPs suivants)
- **MetalLB** : Pour des LoadBalancers avec IP externe (voir [guide kubeadm](../docs/KUBEADM_SETUP.md#partie-6--configuration-du-loadbalancer-metallb))
- **HAProxy/Nginx externe** : Pour load balancer devant les NodePorts

## Partie 6 : Manipulation avancée

### 6.1 Scaler l'application

```bash
# Augmenter le nombre de réplicas à 3
kubectl scale deployment nginx-demo --replicas=3

# Vérifier les pods
kubectl get pods

# Observer la distribution
kubectl get pods -o wide
```

### 6.2 Mettre à jour l'application

```bash
# Mettre à jour l'image vers une version spécifique
kubectl set image deployment/nginx-demo nginx=nginx:1.24

# Suivre le rollout
kubectl rollout status deployment/nginx-demo

# Voir l'historique des déploiements
kubectl rollout history deployment/nginx-demo
```

### 6.3 Revenir à la version précédente

```bash
# Annuler le dernier déploiement
kubectl rollout undo deployment/nginx-demo

# Vérifier le statut
kubectl rollout status deployment/nginx-demo
```

## Partie 7 : Utilisation de fichiers YAML

### 7.1 Créer un fichier de déploiement

Créer un fichier `webapp-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  labels:
    app: webapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: httpd:2.4
        ports:
        - containerPort: 80
```

### 7.2 Créer un fichier de service

Créer un fichier `webapp-service.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp-service
spec:
  type: NodePort
  selector:
    app: webapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
```

**Note :** Ce service utilise un NodePort fixe (30080) ce qui est pratique pour le développement. Consultez la Partie 4 pour comprendre quand utiliser ce type de service.

### 7.3 Appliquer les configurations

```bash
# Appliquer le déploiement
kubectl apply -f webapp-deployment.yaml

# Appliquer le service
kubectl apply -f webapp-service.yaml

# Vérifier les ressources créées
kubectl get deployments,services,pods
```

### 7.4 Tester l'application

#### Option A : Avec minikube

```bash
# Accéder au service
curl http://$(minikube ip):30080
```

#### Option B : Avec kubeadm

```bash
# Récupérer l'IP d'un nœud
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Tester l'accès
curl http://$NODE_IP:30080

# Ou depuis un autre serveur sur le réseau
# curl http://<IP-du-noeud>:30080
```

**Note :** Avec kubeadm, le service est accessible sur le port 30080 depuis n'importe quel nœud du cluster grâce à kube-proxy.

## Partie 8 : Nettoyage et commandes utiles

### 8.1 Nettoyer les ressources

```bash
# Supprimer le déploiement nginx-demo
kubectl delete deployment nginx-demo
kubectl delete service nginx-demo

# Supprimer les ressources webapp
kubectl delete -f webapp-deployment.yaml
kubectl delete -f webapp-service.yaml

# Ou supprimer par nom
kubectl delete deployment webapp
kubectl delete service webapp-service
```

### 8.2 Commandes utiles

#### Communes (minikube et kubeadm)

```bash
# Voir toutes les ressources dans le namespace par défaut
kubectl get all

# Voir les pods de tous les namespaces
kubectl get pods --all-namespaces

# Afficher les événements récents
kubectl get events --sort-by='.lastTimestamp'
```

#### Spécifiques minikube

```bash
# Accéder au dashboard Kubernetes
minikube dashboard

# Voir les addons disponibles
minikube addons list

# Activer un addon (exemple: metrics-server)
minikube addons enable metrics-server

# Voir les logs de minikube
minikube logs

# SSH dans le nœud minikube
minikube ssh
```

#### Spécifiques kubeadm

```bash
# Installer le dashboard manuellement
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Créer un token pour accéder au dashboard
kubectl -n kubernetes-dashboard create token admin-user

# Accéder au dashboard via port-forward
kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8443:443

# Installer metrics-server manuellement
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# SSH dans un nœud spécifique (adapter l'IP)
ssh user@<node-ip>

# Voir les logs des composants système
kubectl logs -n kube-system -l component=kube-apiserver
kubectl logs -n kube-system -l k8s-app=kube-proxy
```

### 8.3 Arrêter et supprimer le cluster

#### Avec minikube

```bash
# Arrêter minikube
minikube stop

# Supprimer le cluster
minikube delete

# Démarrer à nouveau
minikube start
```

#### Avec kubeadm

```bash
# Pour arrêter le cluster, arrêter les VMs/serveurs ou :
# Sur chaque nœud
sudo systemctl stop kubelet

# Pour redémarrer
sudo systemctl start kubelet

# Pour supprimer complètement le cluster
# Sur tous les nœuds (master et workers)
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# Puis réinitialiser depuis le début si nécessaire (voir section 1.6)
```

## Exercices pratiques

### Exercice 1 : Déploiement Redis
1. Déployer une instance Redis avec l'image `redis:7-alpine`
2. L'exposer via un service de type **ClusterIP** sur le port 6379
3. Vérifier que le pod est en cours d'exécution

**Pourquoi ClusterIP ?** Redis est typiquement une base de données backend qui doit être accessible uniquement depuis l'intérieur du cluster par d'autres applications. Il n'a pas besoin d'être exposé à l'extérieur. Voir Partie 4.1 pour plus de détails sur ClusterIP.

### Exercice 2 : Application multi-conteneurs
1. Créer un déploiement avec 3 réplicas d'nginx
2. Créer un service **LoadBalancer**
3. Tester l'accès à l'application
4. Scaler à 5 réplicas
5. Observer la distribution des pods

**À propos de LoadBalancer :**
- **Avec minikube :** Le type LoadBalancer est automatiquement converti en NodePort. Pour simuler un vrai LoadBalancer localement, vous pouvez utiliser `minikube tunnel` dans un terminal séparé.
- **Avec kubeadm :** Installez MetalLB pour obtenir des IPs externes pour vos LoadBalancers (voir [guide kubeadm](../docs/KUBEADM_SETUP.md#partie-6--configuration-du-loadbalancer-metallb))

### Exercice 3 : Manipulation YAML
1. Créer un fichier YAML pour déployer MySQL
   - Image: `mysql:8.0`
   - Variables d'environnement: `MYSQL_ROOT_PASSWORD=secret`
   - Port: 3306
2. Appliquer le déploiement
3. Vérifier les logs du pod MySQL

## Solutions des exercices

<details>
<summary>Solution Exercice 1</summary>

```bash
# Créer le déploiement
kubectl create deployment redis-demo --image=redis:7-alpine

# Créer le service
kubectl expose deployment redis-demo --type=ClusterIP --port=6379

# Vérifier
kubectl get pods,services
```
</details>

<details>
<summary>Solution Exercice 2</summary>

```bash
# Créer le déploiement
kubectl create deployment nginx-multi --image=nginx --replicas=3

# Exposer le service
kubectl expose deployment nginx-multi --type=LoadBalancer --port=80

# Obtenir l'URL
minikube service nginx-multi --url

# Scaler
kubectl scale deployment nginx-multi --replicas=5

# Observer
kubectl get pods -o wide
```
</details>

<details>
<summary>Solution Exercice 3</summary>

Fichier `mysql-deployment.yaml` :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: secret
        ports:
        - containerPort: 3306
```

Commandes :
```bash
kubectl apply -f mysql-deployment.yaml
kubectl get pods
kubectl logs <mysql-pod-name>
```
</details>

## Dépannage

### Problème : minikube ne démarre pas
```bash
# Vérifier Docker
sudo systemctl status docker

# Vérifier les logs
minikube logs

# Supprimer et recréer
minikube delete
minikube start --driver=docker --force
```

### Problème : Impossible de se connecter au service
```bash
# Vérifier que le service existe
kubectl get services

# Vérifier les endpoints
kubectl get endpoints

# Vérifier les pods
kubectl get pods

# Utiliser port-forward comme alternative
kubectl port-forward service/nginx-demo 8080:80
```

### Problème : Permission denied avec Docker
```bash
# S'assurer d'être dans le groupe docker
sudo usermod -aG docker $USER

# Se reconnecter ou utiliser
newgrp docker
```

## Ressources complémentaires

- Documentation officielle Kubernetes : https://kubernetes.io/docs/
- Documentation minikube : https://minikube.sigs.k8s.io/docs/
- Tutoriels interactifs : https://kubernetes.io/docs/tutorials/
- Cheat sheet kubectl : https://kubernetes.io/docs/reference/kubectl/cheatsheet/

## Points clés à retenir

1. **minikube** est un outil pour exécuter Kubernetes localement
2. **kubectl** est l'outil en ligne de commande pour interagir avec Kubernetes
3. Un **Deployment** gère les réplicas de vos pods
4. Un **Service** expose vos pods au réseau
5. Les fichiers **YAML** permettent de définir l'infrastructure as code
6. Le scaling est simple avec la commande `kubectl scale`
7. Les rollouts permettent des mises à jour sans interruption
