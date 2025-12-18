# TP9 - Gestion Multi-Noeud de Kubernetes

## Objectifs du TP

Ce TP vous permettra de maîtriser la gestion de clusters Kubernetes multi-noeuds en environnement production. Vous apprendrez :

- L'architecture d'un cluster Kubernetes multi-noeud
- La mise en place d'un cluster avec plusieurs nœuds maîtres et workers
- La gestion du cycle de vie des nœuds (ajout, suppression, maintenance)
- La haute disponibilité des control planes
- Les stratégies de planification avancées (labels, taints, affinité)
- La maintenance et les mises à jour de nœuds
- Le monitoring et le troubleshooting des nœuds

**Durée estimée :** 8-10 heures
**Niveau :** Avancé

## Prérequis

- Avoir complété les TP1 à TP5 (bases, manifests, sécurité)
- Connaissances en réseau et système Linux
- kubectl installé et configuré
- Accès à plusieurs machines virtuelles ou serveurs (minimum 3 VMs)
  - 3 control plane nodes (2 CPU, 4 Go RAM chacun)
  - 3 worker nodes (2 CPU, 4 Go RAM chacun)
- Compréhension de systemd et des services Linux

## Table des matières

- [Partie 1 : Architecture multi-noeud](#partie-1--architecture-multi-noeud)
- [Partie 2 : Installation d'un cluster multi-noeud avec kubeadm](#partie-2--installation-dun-cluster-multi-noeud-avec-kubeadm)
- [Partie 3 : Gestion des nœuds](#partie-3--gestion-des-nœuds)
- [Partie 4 : Haute disponibilité du Control Plane](#partie-4--haute-disponibilité-du-control-plane)
- [Partie 5 : Labels, Selectors et NodeSelectors](#partie-5--labels-selectors-et-nodeselectors)
- [Partie 6 : Taints et Tolerations](#partie-6--taints-et-tolerations)
- [Partie 7 : Affinité et Anti-Affinité](#partie-7--affinité-et-anti-affinité)
- [Partie 8 : Maintenance et Upgrade des nœuds](#partie-8--maintenance-et-upgrade-des-nœuds)
- [Partie 9 : Monitoring et Troubleshooting](#partie-9--monitoring-et-troubleshooting)
- [Exercices pratiques](#exercices-pratiques)

---

## Partie 1 : Architecture multi-noeud

### 1.1 Composants d'un cluster Kubernetes

Un cluster Kubernetes production se compose de :

**Control Plane (Master Nodes) :**
- **kube-apiserver** : Point d'entrée de l'API Kubernetes
- **etcd** : Base de données clé-valeur distribuée pour l'état du cluster
- **kube-scheduler** : Planification des Pods sur les nœuds
- **kube-controller-manager** : Gestionnaires de contrôleurs
- **cloud-controller-manager** : Intégration avec les fournisseurs cloud (optionnel)

**Worker Nodes :**
- **kubelet** : Agent qui exécute les Pods
- **kube-proxy** : Gestion du réseau et load balancing
- **Container Runtime** : Docker, containerd, ou CRI-O

### 1.2 Architecture haute disponibilité

```
┌─────────────────────────────────────────────────────────────────┐
│                    Load Balancer (HAProxy/NGINX)                │
│                         :6443 (API Server)                       │
└────────────┬───────────────┬────────────────┬────────────────────┘
             │               │                │
   ┌─────────▼─────┐  ┌──────▼──────┐  ┌──────▼──────┐
   │ Control Plane │  │ Control Plane│  │Control Plane│
   │   Node 1      │  │   Node 2     │  │   Node 3    │
   │               │  │              │  │             │
   │ - API Server  │  │ - API Server │  │ - API Server│
   │ - Scheduler   │  │ - Scheduler  │  │ - Scheduler │
   │ - Controller  │  │ - Controller │  │ - Controller│
   │ - etcd        │  │ - etcd       │  │ - etcd      │
   └───────────────┘  └──────────────┘  └─────────────┘
             │               │                │
        ─────┴───────────────┴────────────────┴──────
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
   │ Worker  │      │ Worker  │     │ Worker  │
   │ Node 1  │      │ Node 2  │     │ Node 3  │
   │         │      │         │     │         │
   │ kubelet │      │ kubelet │     │ kubelet │
   │ kube-   │      │ kube-   │     │ kube-   │
   │ proxy   │      │ proxy   │     │ proxy   │
   │ runtime │      │ runtime │     │ runtime │
   └─────────┘      └─────────┘     └─────────┘
```

### 1.3 Modes de déploiement

**1. Stacked etcd topology** (etcd sur les control planes)
- ✅ Plus simple à déployer
- ✅ Moins de ressources nécessaires
- ⚠️ Couplage entre etcd et control plane

**2. External etcd topology** (etcd séparé)
- ✅ Meilleure isolation
- ✅ Évolutivité indépendante
- ⚠️ Plus de machines nécessaires
- ⚠️ Plus complexe à gérer

### 1.4 Considérations réseau

**Plages IP à planifier :**
```yaml
# Réseau des Pods
Pod Network CIDR: 10.244.0.0/16

# Réseau des Services
Service CIDR: 10.96.0.0/12

# Nœuds du cluster
Node Network: 192.168.1.0/24
```

**Ports requis :**

| Composant | Port | Protocole | Usage |
|-----------|------|-----------|-------|
| API Server | 6443 | TCP | API Kubernetes |
| etcd | 2379-2380 | TCP | Client/Peer communication |
| Scheduler | 10251 | TCP | Healthcheck |
| Controller Manager | 10252 | TCP | Healthcheck |
| Kubelet API | 10250 | TCP | API Kubelet |
| NodePort Services | 30000-32767 | TCP | Services exposés |

---

## Partie 2 : Installation d'un cluster multi-noeud avec kubeadm

### 2.0 Création et provisionnement des nœuds

Avant d'installer Kubernetes, vous devez créer les machines qui formeront votre cluster. Voici différentes approches selon votre environnement.

#### 2.0.1 Architecture cible pour ce TP

Pour ce TP, nous allons créer :
- **3 nœuds Control Plane** : master1, master2, master3
- **3 nœuds Workers** : worker1, worker2, worker3
- **1 nœud Load Balancer** : lb (optionnel, peut être sur master1)

**Spécifications recommandées par nœud :**

| Type | CPU | RAM | Disk | IP |
|------|-----|-----|------|-----|
| Control Plane | 2 vCPU | 4 Go | 40 Go | 192.168.1.10-12 |
| Worker | 2 vCPU | 4 Go | 40 Go | 192.168.1.20-22 |
| Load Balancer | 1 vCPU | 1 Go | 20 Go | 192.168.1.100 |

#### 2.0.2 Option 1 : VirtualBox / VMware (local)

**Étape 1 : Télécharger l'ISO**
```bash
# AlmaLinux 9
wget https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso

# Ou Ubuntu Server 22.04
wget https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso
```

**Étape 2 : Créer la première VM (master1)**

Dans VirtualBox :
1. Cliquer sur "Nouvelle"
2. Nom : master1
3. Type : Linux, Version : Red Hat (64-bit) ou Ubuntu (64-bit)
4. Mémoire : 4096 Mo
5. Disque : Créer un disque virtuel (40 Go, VDI, dynamique)
6. Configuration :
   - Processeur : 2 CPU
   - Réseau :
     - Carte 1 : Accès par pont (Bridged) ou Réseau NAT
     - Activer l'adaptateur réseau
   - Stockage : Attacher l'ISO

**Étape 3 : Installer le système**
```bash
# Pendant l'installation :
# - Hostname : master1
# - IP statique : 192.168.1.10/24
# - Gateway : 192.168.1.1
# - DNS : 8.8.8.8
# - Créer un utilisateur : admin (avec sudo)
```

**Étape 4 : Configuration post-installation**
```bash
# SSH vers la VM
ssh admin@192.168.1.10

# Mettre à jour le système
sudo yum update -y  # AlmaLinux
# ou
sudo apt update && sudo apt upgrade -y  # Ubuntu

# Configurer le hostname
sudo hostnamectl set-hostname master1

# Configurer /etc/hosts sur TOUTES les machines
cat <<EOF | sudo tee -a /etc/hosts
192.168.1.10 master1
192.168.1.11 master2
192.168.1.12 master3
192.168.1.20 worker1
192.168.1.21 worker2
192.168.1.22 worker3
192.168.1.100 lb
EOF

# Désactiver SELinux (si AlmaLinux/CentOS)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Configurer le firewall (ou le désactiver pour le lab)
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```

**Étape 5 : Cloner la VM pour les autres nœuds**

Dans VirtualBox :
1. Clic droit sur master1 → Cloner
2. Nom : master2, master3, worker1, worker2, worker3
3. Type de clone : Clone complet
4. Politique MAC : Générer de nouvelles adresses MAC

**Sur chaque VM clonée, modifier :**
```bash
# Sur master2
ssh admin@192.168.1.11
sudo hostnamectl set-hostname master2
sudo nmcli con mod "System eth0" ipv4.addresses 192.168.1.11/24
sudo nmcli con down "System eth0" && sudo nmcli con up "System eth0"

# Sur master3
ssh admin@192.168.1.12
sudo hostnamectl set-hostname master3
sudo nmcli con mod "System eth0" ipv4.addresses 192.168.1.12/24
sudo nmcli con down "System eth0" && sudo nmcli con up "System eth0"

# Sur worker1
ssh admin@192.168.1.20
sudo hostnamectl set-hostname worker1
sudo nmcli con mod "System eth0" ipv4.addresses 192.168.1.20/24
sudo nmcli con down "System eth0" && sudo nmcli con up "System eth0"

# Répéter pour worker2 et worker3
```

#### 2.0.3 Option 2 : Cloud Provider (AWS, GCP, Azure)

**AWS EC2 :**
```bash
# Créer un VPC et un subnet
aws ec2 create-vpc --cidr-block 10.0.0.0/16
aws ec2 create-subnet --vpc-id vpc-xxx --cidr-block 10.0.1.0/24

# Créer un Security Group
aws ec2 create-security-group --group-name k8s-cluster --description "Kubernetes cluster"

# Ouvrir les ports requis
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 6443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 2379-2380 --cidr 10.0.0.0/16
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 10250-10252 --cidr 10.0.0.0/16
aws ec2 authorize-security-group-ingress --group-id sg-xxx --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0

# Lancer les instances (exemple pour master1)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.medium \
  --key-name my-key \
  --security-group-ids sg-xxx \
  --subnet-id subnet-xxx \
  --private-ip-address 10.0.1.10 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=master1},{Key=Role,Value=master}]'

# Répéter pour les autres nœuds
```

**GCP Compute Engine :**
```bash
# Créer le réseau
gcloud compute networks create k8s-network --subnet-mode=custom
gcloud compute networks subnets create k8s-subnet \
  --network=k8s-network \
  --region=us-central1 \
  --range=10.0.1.0/24

# Créer les règles de firewall
gcloud compute firewall-rules create k8s-allow-internal \
  --network k8s-network \
  --allow tcp,udp,icmp \
  --source-ranges 10.0.1.0/24

gcloud compute firewall-rules create k8s-allow-external \
  --network k8s-network \
  --allow tcp:22,tcp:6443,tcp:30000-32767 \
  --source-ranges 0.0.0.0/0

# Créer les instances
for i in 1 2 3; do
  gcloud compute instances create master$i \
    --machine-type=e2-medium \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=40GB \
    --subnet=k8s-subnet \
    --private-network-ip=10.0.1.1$i \
    --tags=k8s-master
done

for i in 1 2 3; do
  gcloud compute instances create worker$i \
    --machine-type=e2-medium \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=40GB \
    --subnet=k8s-subnet \
    --private-network-ip=10.0.1.2$i \
    --tags=k8s-worker
done
```

#### 2.0.4 Option 3 : Terraform (Infrastructure as Code)

**Créer un fichier terraform pour automatiser :**

```hcl
# main.tf
provider "libvirt" {
  uri = "qemu:///system"
}

# Pool de stockage
resource "libvirt_pool" "k8s" {
  name = "k8s-pool"
  type = "dir"
  path = "/var/lib/libvirt/pools/k8s"
}

# Volume de base (image cloud)
resource "libvirt_volume" "base" {
  name   = "base.qcow2"
  pool   = libvirt_pool.k8s.name
  source = "https://cloud.almalinux.org/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
  format = "qcow2"
}

# Volumes pour chaque nœud
resource "libvirt_volume" "master" {
  count          = 3
  name           = "master${count.index + 1}.qcow2"
  base_volume_id = libvirt_volume.base.id
  pool           = libvirt_pool.k8s.name
  size           = 42949672960  # 40 GB
}

resource "libvirt_volume" "worker" {
  count          = 3
  name           = "worker${count.index + 1}.qcow2"
  base_volume_id = libvirt_volume.base.id
  pool           = libvirt_pool.k8s.name
  size           = 42949672960
}

# Cloud-init pour chaque nœud
data "template_file" "user_data_master" {
  count    = 3
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    hostname = "master${count.index + 1}"
    ip_address = "192.168.1.${10 + count.index}"
  }
}

# VMs masters
resource "libvirt_domain" "master" {
  count  = 3
  name   = "master${count.index + 1}"
  memory = "4096"
  vcpu   = 2

  disk {
    volume_id = libvirt_volume.master[count.index].id
  }

  network_interface {
    network_name = "default"
    addresses    = ["192.168.1.${10 + count.index}"]
  }

  cloudinit = libvirt_cloudinit_disk.master[count.index].id
}

# VMs workers
resource "libvirt_domain" "worker" {
  count  = 3
  name   = "worker${count.index + 1}"
  memory = "4096"
  vcpu   = 2

  disk {
    volume_id = libvirt_volume.worker[count.index].id
  }

  network_interface {
    network_name = "default"
    addresses    = ["192.168.1.${20 + count.index}"]
  }

  cloudinit = libvirt_cloudinit_disk.worker[count.index].id
}

# Appliquer avec :
# terraform init
# terraform plan
# terraform apply
```

#### 2.0.5 Vérification des prérequis

**Sur chaque nœud, vérifier :**

```bash
# 1. Connectivité réseau
ping -c 3 master1
ping -c 3 master2
ping -c 3 worker1

# 2. Résolution DNS
nslookup master1
nslookup worker1

# 3. Ports ouverts (depuis un autre nœud)
nc -zv master1 6443
nc -zv master1 2379

# 4. Ressources système
free -h  # Minimum 2 Go RAM
nproc    # Minimum 2 CPU
df -h    # Minimum 20 Go disque

# 5. Swap désactivé
swapon --show  # Doit être vide

# 6. Modules kernel
lsmod | grep br_netfilter
lsmod | grep overlay
```

#### 2.0.6 Script de préparation automatisé

**Créer un script pour automatiser la préparation :**

```bash
#!/bin/bash
# prepare-node.sh - À exécuter sur chaque nœud

# Variables
NODE_TYPE=$1  # master ou worker
NODE_NUMBER=$2
NODE_IP="192.168.1.$([[ $NODE_TYPE == 'master' ]] && echo $((10 + NODE_NUMBER)) || echo $((20 + NODE_NUMBER)))"
HOSTNAME="${NODE_TYPE}${NODE_NUMBER}"

# Vérifier les arguments
if [ -z "$NODE_TYPE" ] || [ -z "$NODE_NUMBER" ]; then
  echo "Usage: $0 <master|worker> <number>"
  exit 1
fi

echo "=== Configuration de $HOSTNAME ($NODE_IP) ==="

# Hostname
sudo hostnamectl set-hostname $HOSTNAME

# /etc/hosts
cat <<EOF | sudo tee /etc/hosts
127.0.0.1   localhost
$NODE_IP    $HOSTNAME

# Control Planes
192.168.1.10 master1
192.168.1.11 master2
192.168.1.12 master3

# Workers
192.168.1.20 worker1
192.168.1.21 worker2
192.168.1.22 worker3

# Load Balancer
192.168.1.100 lb k8s-api
EOF

# Désactiver swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Désactiver SELinux (RHEL/CentOS/AlmaLinux)
if [ -f /etc/selinux/config ]; then
  sudo setenforce 0
  sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
fi

# Désactiver firewall (pour le lab)
sudo systemctl stop firewalld 2>/dev/null
sudo systemctl disable firewalld 2>/dev/null

echo "✓ Node $HOSTNAME configuré"
echo "✓ Prêt pour l'installation de Kubernetes"
```

**Utilisation :**
```bash
# Sur master1
./prepare-node.sh master 1

# Sur master2
./prepare-node.sh master 2

# Sur worker1
./prepare-node.sh worker 1

# Etc.
```

### 2.1 Préparation des nœuds

**Sur TOUS les nœuds (control plane et workers) :**

```bash
# Désactiver le swap (requis par Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Configurer les modules kernel
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Paramètres sysctl pour Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Installer containerd
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y containerd.io

# Configurer containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Installer kubeadm, kubelet et kubectl
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable kubelet
```

### 2.2 Configuration du Load Balancer (HAProxy)

**Sur un serveur dédié ou le premier control plane :**

```bash
# Installer HAProxy
sudo yum install -y haproxy

# Configurer HAProxy
sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend kubernetes-apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-apiserver

backend kubernetes-apiserver
    mode tcp
    option tcp-check
    balance roundrobin
    server master1 192.168.1.10:6443 check fall 3 rise 2
    server master2 192.168.1.11:6443 check fall 3 rise 2
    server master3 192.168.1.12:6443 check fall 3 rise 2
EOF

# Démarrer HAProxy
sudo systemctl restart haproxy
sudo systemctl enable haproxy
```

### 2.3 Initialiser le premier Control Plane

**Sur le premier nœud master (192.168.1.10) :**

```bash
# Créer la configuration kubeadm
cat > kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "192.168.1.100:6443"  # IP du Load Balancer
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
etcd:
  local:
    dataDir: /var/lib/etcd
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
EOF

# Initialiser le cluster
sudo kubeadm init --config=kubeadm-config.yaml --upload-certs

# Configurer kubectl pour l'utilisateur courant
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Installer un plugin CNI (Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

**⚠️ IMPORTANT : Sauvegarder les commandes de join affichées !**

```bash
# Exemple de sortie à sauvegarder :
# Pour ajouter un control plane :
kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:xxxx \
    --control-plane --certificate-key yyyy

# Pour ajouter un worker :
kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:xxxx
```

### 2.4 Ajouter les Control Planes supplémentaires

**Sur les nœuds master 2 et 3 :**

```bash
# Utiliser la commande de join pour control plane sauvegardée précédemment
sudo kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:xxxx \
    --control-plane --certificate-key yyyy

# Configurer kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 2.5 Ajouter les Worker Nodes

#### 2.5.1 Comprendre le processus de join

Quand un worker rejoint le cluster :
1. Il contacte l'API server via le load balancer (ou l'IP du master)
2. Il vérifie le certificat CA avec le hash fourni
3. Il s'authentifie avec le token
4. Le control plane crée le nœud dans le cluster
5. kubelet démarre et commence à gérer les pods

#### 2.5.2 Obtenir la commande de join

**Sur un control plane (master1) :**

```bash
# Si vous avez perdu la commande de join originale
kubeadm token create --print-join-command

# Sortie exemple :
# kubeadm join 192.168.1.100:6443 --token abc123.xyz789 \
#   --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Décomposition de la commande :**
- `192.168.1.100:6443` : Endpoint de l'API server (load balancer ou master)
- `--token abc123.xyz789` : Token d'authentification (expire après 24h)
- `--discovery-token-ca-cert-hash sha256:xxxx` : Hash du certificat CA pour sécurité

#### 2.5.3 Ajouter worker1

**Sur worker1 (192.168.1.20) :**

```bash
# Vérifier que worker1 est prêt
echo "=== Vérification des prérequis ==="
hostname  # Doit afficher: worker1
ping -c 2 192.168.1.100  # Ping vers le load balancer
ping -c 2 master1
systemctl status kubelet  # Doit être actif

# Rejoindre le cluster
echo "=== Rattachement au cluster ==="
sudo kubeadm join 192.168.1.100:6443 \
  --token abc123.xyz789 \
  --discovery-token-ca-cert-hash sha256:1234567890abcdef...

# Sortie attendue :
# [preflight] Running pre-flight checks
# [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
# [kubelet-start] Starting the kubelet
# [kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap...
#
# This node has joined the cluster:
# * Certificate signing request was sent to apiserver and a response was received.
# * The Kubelet was informed of the new secure connection details.
#
# Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

**Vérifier depuis master1 :**

```bash
# Sur master1
kubectl get nodes

# Sortie :
# NAME      STATUS     ROLES           AGE   VERSION
# master1   Ready      control-plane   15m   v1.28.0
# master2   Ready      control-plane   10m   v1.28.0
# master3   Ready      control-plane   8m    v1.28.0
# worker1   NotReady   <none>          10s   v1.28.0  ← Nouveau nœud !

# Attendre 30-60 secondes que le CNI configure le réseau
sleep 60
kubectl get nodes

# Sortie :
# worker1   Ready      <none>          1m    v1.28.0  ← Maintenant Ready !
```

#### 2.5.4 Ajouter les autres workers

**Script pour automatiser l'ajout de plusieurs workers :**

```bash
#!/bin/bash
# add-workers.sh - À exécuter depuis un control plane

# Générer la commande de join
JOIN_CMD=$(kubeadm token create --print-join-command)

# Liste des workers à ajouter
WORKERS=("worker1:192.168.1.20" "worker2:192.168.1.21" "worker3:192.168.1.22")

for WORKER_INFO in "${WORKERS[@]}"; do
  WORKER_NAME=$(echo $WORKER_INFO | cut -d: -f1)
  WORKER_IP=$(echo $WORKER_INFO | cut -d: -f2)

  echo "=== Ajout de $WORKER_NAME ($WORKER_IP) ==="

  # Exécuter le join via SSH
  ssh admin@$WORKER_IP "sudo $JOIN_CMD"

  if [ $? -eq 0 ]; then
    echo "✓ $WORKER_NAME ajouté avec succès"
    sleep 10
  else
    echo "✗ Échec de l'ajout de $WORKER_NAME"
  fi
done

# Vérifier tous les nœuds
echo ""
echo "=== État du cluster ==="
kubectl get nodes
```

**Utilisation :**
```bash
chmod +x add-workers.sh
./add-workers.sh
```

#### 2.5.5 Ajouter manuellement worker2 et worker3

**Sur worker2 :**
```bash
ssh admin@192.168.1.21

# Utiliser la même commande de join
sudo kubeadm join 192.168.1.100:6443 \
  --token abc123.xyz789 \
  --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Sur worker3 :**
```bash
ssh admin@192.168.1.22

sudo kubeadm join 192.168.1.100:6443 \
  --token abc123.xyz789 \
  --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Vérifier depuis master1 :**
```bash
watch kubectl get nodes
# Attendre que tous les workers soient Ready
```

#### 2.5.6 Troubleshooting de l'ajout de workers

**Problème 1 : Token expiré**
```bash
# Erreur :
# error execution phase preflight: couldn't validate the identity of the API Server

# Solution : Créer un nouveau token
kubeadm token create --print-join-command
```

**Problème 2 : Worker reste en NotReady**
```bash
# Vérifier les pods CNI
kubectl get pods -n kube-system | grep calico

# Vérifier les logs du worker
ssh worker1 "sudo journalctl -u kubelet -n 50"

# Redémarrer kubelet si nécessaire
ssh worker1 "sudo systemctl restart kubelet"
```

**Problème 3 : Impossible de contacter l'API server**
```bash
# Sur le worker
ping 192.168.1.100
nc -zv 192.168.1.100 6443

# Vérifier le firewall
sudo firewall-cmd --list-all
```

**Problème 4 : Certificat CA invalide**
```bash
# Récupérer le bon hash depuis un master
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'
```

#### 2.5.7 Labelliser les workers (optionnel)

Après l'ajout, vous pouvez labelliser les workers :

```bash
# Ajouter le label "node" comme role
kubectl label node worker1 node-role.kubernetes.io/worker=worker
kubectl label node worker2 node-role.kubernetes.io/worker=worker
kubectl label node worker3 node-role.kubernetes.io/worker=worker

# Ajouter des labels personnalisés
kubectl label node worker1 environment=production zone=zone-a
kubectl label node worker2 environment=production zone=zone-b
kubectl label node worker3 environment=production zone=zone-c

# Vérifier
kubectl get nodes --show-labels
```

### 2.6 Vérifier le cluster

```bash
# Vérifier tous les nœuds
kubectl get nodes

# Vérifier les composants du système
kubectl get pods -n kube-system

# Vérifier la santé d'etcd
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Vérifier les certificats
kubeadm certs check-expiration
```

### 2.7 Regénérer les tokens (si expirés)

```bash
# Les tokens expirent après 24h, pour en créer un nouveau :
kubeadm token create --print-join-command

# Pour obtenir le certificate-key (ajout de control planes) :
sudo kubeadm init phase upload-certs --upload-certs
```

---

## Partie 3 : Gestion des nœuds

### 3.1 Opérations de base sur les nœuds

**Lister les nœuds :**

```bash
# Liste simple
kubectl get nodes

# Avec plus de détails
kubectl get nodes -o wide

# Voir les ressources (CPU, RAM)
kubectl top nodes

# Détails complets d'un nœud
kubectl describe node <node-name>
```

### 3.2 Cordon : Empêcher la planification

**Marquer un nœud comme non-planifiable :**

```bash
# Empêcher de nouveaux pods d'être planifiés sur le nœud
kubectl cordon worker1

# Vérifier le statut
kubectl get nodes
# worker1 affichera "SchedulingDisabled"

# Les pods existants continuent de fonctionner
kubectl get pods -o wide
```

**Cas d'usage :**
- Avant une maintenance
- Pour isoler un nœud problématique
- Pour tester le comportement du cluster

### 3.3 Drain : Évacuer un nœud

**Évacuer tous les pods d'un nœud :**

```bash
# Évacuer le nœud (supprime les pods)
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

# Options importantes :
# --ignore-daemonsets : ignorer les DaemonSets (non évacuables)
# --delete-emptydir-data : supprimer les données emptyDir
# --force : forcer même pour les pods non gérés
# --grace-period : délai de grâce pour l'arrêt (défaut: 30s)

# Exemple avec grace period
kubectl drain worker1 --ignore-daemonsets --grace-period=60
```

**Ce qui se passe lors d'un drain :**
1. Le nœud est marqué comme `SchedulingDisabled` (cordon automatique)
2. Les pods sont évacués avec respect des PodDisruptionBudgets
3. Les pods sont recréés sur d'autres nœuds disponibles
4. Les DaemonSets restent (sauf si forcé)

**⚠️ Attention avec drain :**
- Les pods avec des volumes locaux (emptyDir) perdent leurs données
- Les pods sans contrôleur (pods standalone) sont supprimés définitivement
- Respecte les PodDisruptionBudgets (peut échouer si le PDB n'est pas satisfait)

```bash
# Drain avec timeout
kubectl drain worker1 --ignore-daemonsets --timeout=5m

# Drain forcé (dangereux !)
kubectl drain worker1 --ignore-daemonsets --force --delete-emptydir-data
```

### 3.4 Uncordon : Réactiver la planification

```bash
# Réactiver le nœud
kubectl uncordon worker1

# Vérifier
kubectl get nodes
# worker1 est de nouveau "Ready" sans "SchedulingDisabled"

# Les nouveaux pods peuvent maintenant être planifiés sur ce nœud
```

### 3.5 Supprimer un nœud du cluster

**Depuis le control plane :**

```bash
# 1. Évacuer le nœud
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data --force

# 2. Supprimer le nœud du cluster
kubectl delete node worker1
```

**Sur le nœud lui-même (pour le nettoyer) :**

```bash
# Réinitialiser kubeadm
sudo kubeadm reset

# Nettoyer les règles iptables
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

# Supprimer les interfaces CNI
sudo ip link delete cni0
sudo ip link delete flannel.1

# Nettoyer les répertoires
sudo rm -rf /etc/cni /var/lib/etcd /var/lib/kubelet /etc/kubernetes
```

### 3.6 Exercice pratique : Maintenance d'un nœud

**Scénario : Vous devez effectuer une maintenance sur worker2**

```bash
# 1. Déployer une application de test
kubectl create deployment nginx-test --image=nginx:alpine --replicas=6
kubectl get pods -o wide

# 2. Identifier les pods sur worker2
kubectl get pods -o wide | grep worker2

# 3. Marquer worker2 comme non-planifiable
kubectl cordon worker2
kubectl get nodes

# 4. Vérifier qu'aucun nouveau pod n'est créé sur worker2
kubectl scale deployment nginx-test --replicas=9
kubectl get pods -o wide | grep worker2
# Même nombre de pods qu'avant

# 5. Évacuer worker2
kubectl drain worker2 --ignore-daemonsets

# 6. Vérifier que les pods ont été déplacés
kubectl get pods -o wide | grep worker2
# Aucun pod (sauf DaemonSets)

# 7. Simuler la maintenance (attendre quelques secondes)
echo "Maintenance en cours..."
sleep 30

# 8. Réactiver worker2
kubectl uncordon worker2

# 9. Vérifier la distribution
kubectl get pods -o wide
```

---

## Partie 4 : Haute disponibilité du Control Plane

### 4.1 Vérifier la santé du Control Plane

**Vérifier les composants API Server :**

```bash
# Status de l'API server
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'

# Vérifier tous les control planes
kubectl get pods -n kube-system -o wide | grep kube-apiserver

# Tester l'accès via le load balancer
curl -k https://192.168.1.100:6443/healthz
```

**Vérifier etcd :**

```bash
# Vérifier les membres etcd
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list

# Vérifier la santé de tous les membres
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --endpoints=https://192.168.1.10:2379,https://192.168.1.11:2379,https://192.168.1.12:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Voir le leader etcd
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table
```

### 4.2 Test de résilience

**Tester la perte d'un control plane :**

```bash
# Sur master2 : arrêter kubelet et les composants
sudo systemctl stop kubelet

# Depuis master1 : vérifier que le cluster fonctionne toujours
kubectl get nodes
kubectl create deployment test-ha --image=nginx:alpine

# Redémarrer master2
sudo systemctl start kubelet
```

**Tester la perte du load balancer :**

```bash
# Arrêter HAProxy
sudo systemctl stop haproxy

# Le cluster devrait continuer à fonctionner si vous utilisez directement un master
kubectl --server=https://192.168.1.10:6443 get nodes

# Redémarrer HAProxy
sudo systemctl start haproxy
```

### 4.3 Sauvegarder et restaurer etcd

**Sauvegarder etcd :**

```bash
# Créer un snapshot
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/snapshot.db

# Copier le snapshot localement
kubectl cp kube-system/etcd-master1:/var/lib/etcd/snapshot.db ./etcd-snapshot.db

# Vérifier le snapshot
kubectl exec -n kube-system etcd-master1 -- etcdctl \
  --write-out=table snapshot status /var/lib/etcd/snapshot.db
```

**Restaurer depuis un snapshot :**

```bash
# ⚠️ ATTENTION : Cette opération arrête le cluster !

# 1. Déplacer les anciennes données etcd
sudo mv /var/lib/etcd /var/lib/etcd.old

# 2. Restaurer le snapshot
sudo etcdctl snapshot restore /tmp/snapshot.db \
  --data-dir=/var/lib/etcd \
  --name=master1 \
  --initial-cluster=master1=https://192.168.1.10:2380,master2=https://192.168.1.11:2380,master3=https://192.168.1.12:2380 \
  --initial-advertise-peer-urls=https://192.168.1.10:2380

# 3. Redémarrer etcd
sudo systemctl restart kubelet

# 4. Vérifier
kubectl get nodes
```

---

## Partie 5 : Labels, Selectors et NodeSelectors

### 5.1 Labels sur les nœuds

**Ajouter des labels aux nœuds :**

```bash
# Ajouter un label
kubectl label nodes worker1 environment=production
kubectl label nodes worker2 environment=development
kubectl label nodes worker3 disktype=ssd

# Voir les labels
kubectl get nodes --show-labels

# Filtrer par label
kubectl get nodes -l environment=production

# Voir un label spécifique
kubectl get nodes -L environment,disktype

# Supprimer un label
kubectl label nodes worker1 environment-
```

**Labels courants pour les nœuds :**
```yaml
environment: production|staging|development
tier: frontend|backend|database
disktype: ssd|hdd
gpu: nvidia-tesla-v100|amd-radeon
zone: us-east-1a|us-east-1b
node-role: worker|monitoring|logging
```

### 5.2 NodeSelector : Planifier sur des nœuds spécifiques

**Exemple 1 : Déployer sur les nœuds SSD**

```yaml
# deployment-ssd.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-ssd
spec:
  replicas: 3
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      nodeSelector:
        disktype: ssd
      containers:
      - name: postgres
        image: postgres:15-alpine
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
```

```bash
kubectl apply -f deployment-ssd.yaml

# Vérifier que les pods sont sur les bons nœuds
kubectl get pods -o wide
```

**Exemple 2 : Séparation environnements**

```yaml
# deployment-prod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-production
spec:
  replicas: 5
  selector:
    matchLabels:
      app: myapp
      env: prod
  template:
    metadata:
      labels:
        app: myapp
        env: prod
    spec:
      nodeSelector:
        environment: production
      containers:
      - name: app
        image: myapp:v2.1
```

### 5.3 Exercice : Organisation par zones

```bash
# Labelliser les nœuds par zones
kubectl label nodes worker1 zone=zone-a
kubectl label nodes worker2 zone=zone-b
kubectl label nodes worker3 zone=zone-c

# Créer un déploiement pour chaque zone
cat > app-zone-a.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-zone-a
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
      zone: zone-a
  template:
    metadata:
      labels:
        app: myapp
        zone: zone-a
    spec:
      nodeSelector:
        zone: zone-a
      containers:
      - name: nginx
        image: nginx:alpine
EOF

kubectl apply -f app-zone-a.yaml
kubectl get pods -o wide -l zone=zone-a
```

---

## Partie 6 : Taints et Tolerations

### 6.1 Comprendre les Taints

Les taints (souillures) empêchent les pods d'être planifiés sur certains nœuds, sauf si les pods ont une toleration correspondante.

**Syntaxe d'un taint :**
```
key=value:effect
```

**Effets possibles :**
- `NoSchedule` : N'accepte pas les nouveaux pods
- `PreferNoSchedule` : Évite de planifier (soft)
- `NoExecute` : Évacue les pods existants qui ne tolèrent pas

### 6.2 Ajouter des Taints

```bash
# Ajouter un taint
kubectl taint nodes worker1 dedicated=database:NoSchedule

# Ajouter plusieurs taints
kubectl taint nodes worker2 gpu=true:NoSchedule
kubectl taint nodes worker2 expensive=true:PreferNoSchedule

# Voir les taints
kubectl describe node worker1 | grep Taints

# Supprimer un taint (noter le "-" à la fin)
kubectl taint nodes worker1 dedicated-
```

### 6.3 Tolerations dans les Pods

**Exemple 1 : Pod qui tolère un taint spécifique**

```yaml
# pod-toleration.yaml
apiVersion: v1
kind: Pod
metadata:
  name: database-pod
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "database"
    effect: "NoSchedule"
  containers:
  - name: postgres
    image: postgres:15-alpine
```

```bash
kubectl apply -f pod-toleration.yaml

# Vérifier qu'il est planifié sur worker1
kubectl get pod database-pod -o wide
```

**Exemple 2 : Toleration avec opérateur "Exists"**

```yaml
# pod-tolerate-all.yaml
apiVersion: v1
kind: Pod
metadata:
  name: admin-pod
spec:
  tolerations:
  - key: "dedicated"
    operator: "Exists"
    effect: "NoSchedule"
  containers:
  - name: admin
    image: busybox:latest
    command: ['sh', '-c', 'sleep 3600']
```

**Exemple 3 : Tolérer tous les taints**

```yaml
# pod-tolerate-everything.yaml
apiVersion: v1
kind: Pod
metadata:
  name: super-admin
spec:
  tolerations:
  - operator: "Exists"
  containers:
  - name: admin
    image: busybox:latest
    command: ['sh', '-c', 'sleep 3600']
```

### 6.4 Cas pratiques avec Taints

**Cas 1 : Nœuds dédiés pour les bases de données**

```bash
# 1. Marquer un nœud pour les bases de données
kubectl taint nodes worker1 workload=database:NoSchedule
kubectl label nodes worker1 workload=database

# 2. Déployer une base de données
cat > postgres-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      nodeSelector:
        workload: database
      tolerations:
      - key: "workload"
        operator: "Equal"
        value: "database"
        effect: "NoSchedule"
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: mysecretpassword
EOF

kubectl apply -f postgres-deployment.yaml
```

**Cas 2 : Nœuds GPU**

```bash
# Taint pour les nœuds avec GPU
kubectl taint nodes worker2 nvidia.com/gpu=true:NoSchedule

# Deployment pour workload GPU
cat > gpu-job.yaml <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-training
spec:
  template:
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: ml-training
        image: tensorflow/tensorflow:latest-gpu
        command: ["python", "train.py"]
        resources:
          limits:
            nvidia.com/gpu: 1
      restartPolicy: Never
EOF
```

**Cas 3 : NoExecute pour évacuation automatique**

```bash
# Ajouter un taint NoExecute
kubectl taint nodes worker3 maintenance=true:NoExecute

# Les pods sans toleration seront évacués automatiquement
kubectl get pods -o wide

# Pod qui survit au taint NoExecute
cat > pod-survive-noexecute.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: maintenance-tolerant
spec:
  tolerations:
  - key: "maintenance"
    operator: "Equal"
    value: "true"
    effect: "NoExecute"
    tolerationSeconds: 3600  # Reste 1h puis est évacué
  containers:
  - name: app
    image: nginx:alpine
EOF

kubectl apply -f pod-survive-noexecute.yaml
```

---

## Partie 7 : Affinité et Anti-Affinité

L'affinité permet un contrôle plus fin de la planification des pods que les NodeSelectors.

### 7.1 Node Affinity

**Types d'affinité de nœuds :**
- `requiredDuringSchedulingIgnoredDuringExecution` : Règle stricte (hard)
- `preferredDuringSchedulingIgnoredDuringExecution` : Règle préférée (soft)

**Exemple 1 : Affinité stricte (required)**

```yaml
# deployment-node-affinity-required.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: environment
                operator: In
                values:
                - production
                - staging
      containers:
      - name: webapp
        image: nginx:alpine
```

**Exemple 2 : Affinité préférée (preferred)**

```yaml
# deployment-node-affinity-preferred.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-preference
spec:
  replicas: 5
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: disktype
                operator: In
                values:
                - ssd
          - weight: 50
            preference:
              matchExpressions:
              - key: zone
                operator: In
                values:
                - zone-a
      containers:
      - name: app
        image: myapp:latest
```

**Opérateurs disponibles :**
- `In` : Valeur dans la liste
- `NotIn` : Valeur pas dans la liste
- `Exists` : Clé existe (ignore les valeurs)
- `DoesNotExist` : Clé n'existe pas
- `Gt` : Greater than (pour valeurs numériques)
- `Lt` : Less than (pour valeurs numériques)

### 7.2 Pod Affinity (Inter-Pod Affinity)

Permet de placer des pods proches d'autres pods.

**Exemple 1 : Web server proche du cache**

```yaml
# redis-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: cache
    spec:
      containers:
      - name: redis
        image: redis:alpine
---
# web-deployment-with-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
        tier: frontend
    spec:
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - redis
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
```

**topologyKey expliqué :**
- `kubernetes.io/hostname` : Même nœud
- `topology.kubernetes.io/zone` : Même zone
- `topology.kubernetes.io/region` : Même région

### 7.3 Pod Anti-Affinity

Permet de séparer des pods pour la haute disponibilité.

**Exemple : Répartir les replicas sur différents nœuds**

```yaml
# deployment-anti-affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-ha
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - web
            topologyKey: kubernetes.io/hostname
      containers:
      - name: nginx
        image: nginx:alpine
```

**Anti-affinité préférée (soft) :**

```yaml
# deployment-anti-affinity-soft.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-distributed
spec:
  replicas: 10
  selector:
    matchLabels:
      app: distributed-app
  template:
    metadata:
      labels:
        app: distributed-app
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - distributed-app
              topologyKey: kubernetes.io/hostname
      containers:
      - name: app
        image: myapp:latest
```

### 7.4 Combinaison d'affinités

**Exemple complet : Application 3-tiers avec affinités**

```yaml
# full-affinity-example.yaml
# Frontend : dispersé sur les nœuds, préfère zone-a
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 5
  selector:
    matchLabels:
      tier: frontend
  template:
    metadata:
      labels:
        tier: frontend
        app: myapp
    spec:
      affinity:
        # Node Affinity : Préfère zone-a
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: zone
                operator: In
                values:
                - zone-a
        # Pod Anti-Affinity : Répartir sur différents nœuds
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: tier
                  operator: In
                  values:
                  - frontend
              topologyKey: kubernetes.io/hostname
      containers:
      - name: frontend
        image: frontend:v2
---
# Backend : proche du frontend
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      tier: backend
  template:
    metadata:
      labels:
        tier: backend
        app: myapp
    spec:
      affinity:
        # Pod Affinity : Proche du frontend
        podAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: tier
                  operator: In
                  values:
                  - frontend
              topologyKey: kubernetes.io/hostname
        # Pod Anti-Affinity : Répartir les backends
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 50
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: tier
                  operator: In
                  values:
                  - backend
              topologyKey: kubernetes.io/hostname
      containers:
      - name: backend
        image: backend:v2
---
# Database : nœuds SSD, anti-affinité stricte
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  replicas: 3
  selector:
    matchLabels:
      tier: database
  template:
    metadata:
      labels:
        tier: database
        app: myapp
    spec:
      affinity:
        # Node Affinity : Requiert SSD
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: disktype
                operator: In
                values:
                - ssd
        # Pod Anti-Affinity : Strictement sur différents nœuds
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: tier
                operator: In
                values:
                - database
            topologyKey: kubernetes.io/hostname
      containers:
      - name: postgres
        image: postgres:15-alpine
```

---

## Partie 8 : Maintenance et Upgrade des nœuds

### 8.1 Stratégie de mise à jour

**Mise à jour rolling des workers :**

```bash
# Pour chaque worker node :
# 1. Marquer comme non-planifiable
kubectl cordon worker1

# 2. Évacuer les pods
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

# 3. Sur le nœud worker1 : Mettre à jour
sudo yum update -y
sudo yum install -y kubeadm-1.28.5 kubelet-1.28.5 kubectl-1.28.5

# 4. Redémarrer kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. Réactiver le nœud
kubectl uncordon worker1

# 6. Vérifier la version
kubectl get nodes
kubectl describe node worker1 | grep "Kubelet Version"

# 7. Répéter pour les autres workers
```

### 8.2 Upgrade d'un cluster Kubernetes

**Upgrade du Control Plane :**

```bash
# 1. Vérifier la version actuelle
kubectl version --short
kubeadm version

# 2. Voir les versions disponibles
yum list --showduplicates kubeadm --disableexcludes=kubernetes

# 3. Upgrade kubeadm sur le premier control plane
sudo yum install -y kubeadm-1.28.5 --disableexcludes=kubernetes

# 4. Planifier l'upgrade
sudo kubeadm upgrade plan

# 5. Appliquer l'upgrade
sudo kubeadm upgrade apply v1.28.5

# 6. Drainer le control plane
kubectl drain master1 --ignore-daemonsets

# 7. Upgrade kubelet et kubectl
sudo yum install -y kubelet-1.28.5 kubectl-1.28.5 --disableexcludes=kubernetes
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 8. Réactiver le nœud
kubectl uncordon master1

# 9. Pour les autres control planes
# Sur master2 et master3 :
sudo yum install -y kubeadm-1.28.5 --disableexcludes=kubernetes
sudo kubeadm upgrade node
kubectl drain master2 --ignore-daemonsets
sudo yum install -y kubelet-1.28.5 kubectl-1.28.5 --disableexcludes=kubernetes
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl uncordon master2
```

### 8.3 PodDisruptionBudget (PDB)

Les PDB garantissent un nombre minimum de pods disponibles pendant les maintenances.

**Exemple 1 : Minimum de pods disponibles**

```yaml
# pdb-min-available.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web
```

**Exemple 2 : Maximum de pods indisponibles**

```yaml
# pdb-max-unavailable.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: backend
```

**Exemple 3 : Pourcentage**

```yaml
# pdb-percentage.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
spec:
  minAvailable: 50%
  selector:
    matchLabels:
      tier: frontend
```

**Tester le PDB :**

```bash
# Créer un déploiement
kubectl create deployment web --image=nginx:alpine --replicas=5
kubectl label deployment web app=web

# Créer le PDB
kubectl apply -f pdb-min-available.yaml

# Vérifier le PDB
kubectl get pdb

# Essayer de drainer (respectera le PDB)
kubectl drain worker1 --ignore-daemonsets
# Attendra que suffisamment de pods soient disponibles ailleurs
```

### 8.4 Automatisation avec scripts

**Script de maintenance d'un nœud :**

```bash
#!/bin/bash
# maintain-node.sh

NODE=$1

if [ -z "$NODE" ]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi

echo "=== Maintenance de $NODE ==="

# 1. Cordon
echo "1. Marquage du nœud comme non-planifiable..."
kubectl cordon $NODE

# 2. Drain
echo "2. Évacuation des pods..."
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force --grace-period=120

# 3. Vérification
echo "3. Vérification de l'évacuation..."
PODS=$(kubectl get pods --all-namespaces -o wide | grep $NODE | grep -v DaemonSet | wc -l)
if [ $PODS -eq 0 ]; then
  echo "✓ Tous les pods ont été évacués"
else
  echo "⚠ Il reste $PODS pods sur le nœud"
  kubectl get pods --all-namespaces -o wide | grep $NODE
fi

echo "4. Le nœud $NODE est prêt pour la maintenance"
echo "5. Après la maintenance, exécutez: kubectl uncordon $NODE"
```

**Script d'upgrade automatisé :**

```bash
#!/bin/bash
# upgrade-worker-nodes.sh

VERSION=$1
WORKERS=$(kubectl get nodes -l node-role.kubernetes.io/worker=true -o name | cut -d'/' -f2)

for WORKER in $WORKERS; do
  echo "=== Upgrade de $WORKER ==="

  # Cordon + Drain
  kubectl cordon $WORKER
  kubectl drain $WORKER --ignore-daemonsets --delete-emptydir-data --force

  # Upgrade sur le nœud (via SSH)
  ssh $WORKER "sudo yum install -y kubeadm-$VERSION kubelet-$VERSION kubectl-$VERSION && \
               sudo systemctl daemon-reload && \
               sudo systemctl restart kubelet"

  # Uncordon
  kubectl uncordon $WORKER

  # Attendre que le nœud soit Ready
  kubectl wait --for=condition=Ready node/$WORKER --timeout=300s

  echo "✓ $WORKER upgradé avec succès"
  sleep 30
done

echo "=== Upgrade terminé ==="
kubectl get nodes
```

---

## Partie 9 : Monitoring et Troubleshooting

### 9.1 Monitoring des nœuds

**Commandes de base :**

```bash
# Voir l'état des nœuds
kubectl get nodes

# Détails d'un nœud
kubectl describe node worker1

# Ressources utilisées
kubectl top nodes

# Voir les pods sur un nœud spécifique
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=worker1

# Conditions des nœuds
kubectl get nodes -o json | jq '.items[] | {name:.metadata.name, conditions:.status.conditions}'

# Capacité et allocation
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Voir les events d'un nœud :**

```bash
# Events généraux
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Events d'un nœud spécifique
kubectl get events --field-selector involvedObject.name=worker1

# Events de type Warning
kubectl get events --field-selector type=Warning
```

### 9.2 Problèmes courants et solutions

**Problème 1 : Nœud NotReady**

```bash
# Vérifier le statut
kubectl get nodes
kubectl describe node worker1

# Vérifier sur le nœud
ssh worker1

# Vérifier kubelet
sudo systemctl status kubelet
sudo journalctl -u kubelet -f

# Vérifier containerd
sudo systemctl status containerd

# Problèmes réseau
sudo ip addr
sudo iptables -L -n

# Redémarrer si nécessaire
sudo systemctl restart kubelet
```

**Problème 2 : Pods en Pending sur un nœud**

```bash
# Voir pourquoi le pod est pending
kubectl describe pod <pod-name>

# Vérifier les ressources du nœud
kubectl describe node <node-name> | grep -A 5 "Allocated resources"

# Vérifier les taints
kubectl describe node <node-name> | grep Taints

# Vérifier les labels requis
kubectl get nodes --show-labels
```

**Problème 3 : Haute utilisation CPU/Mémoire**

```bash
# Identifier les pods consommateurs
kubectl top pods --all-namespaces --sort-by=memory
kubectl top pods --all-namespaces --sort-by=cpu

# Voir les pods sur le nœud problématique
kubectl top pods --all-namespaces -o wide | grep worker1

# Analyser un pod spécifique
kubectl describe pod <pod-name>
kubectl logs <pod-name>

# Solutions :
# 1. Limiter les ressources
# 2. Scaler horizontalement
# 3. Ajouter des nœuds
```

### 9.3 Déployer Metrics Server

```bash
# Installer Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Pour minikube ou cluster de test (désactive la vérification TLS)
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Vérifier
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
kubectl top pods -A
```

### 9.4 Node Problem Detector

Détecte automatiquement les problèmes de nœuds.

```yaml
# node-problem-detector.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-problem-detector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: node-problem-detector
  template:
    metadata:
      labels:
        app: node-problem-detector
    spec:
      hostNetwork: true
      containers:
      - name: node-problem-detector
        image: k8s.gcr.io/node-problem-detector/node-problem-detector:v0.8.12
        securityContext:
          privileged: true
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: log
          mountPath: /var/log
          readOnly: true
      volumes:
      - name: log
        hostPath:
          path: /var/log/
```

```bash
kubectl apply -f node-problem-detector.yaml

# Vérifier les conditions ajoutées
kubectl describe nodes | grep -A 10 Conditions
```

### 9.5 Logs et Debugging

**Logs de kubelet :**

```bash
# Sur le nœud
sudo journalctl -u kubelet -f
sudo journalctl -u kubelet --since "1 hour ago"

# Filtrer les erreurs
sudo journalctl -u kubelet -p err

# Exporter les logs
sudo journalctl -u kubelet > kubelet-logs.txt
```

**Debugging réseau sur un nœud :**

```bash
# Installer netshoot pour le debug
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- /bin/bash

# Depuis netshoot :
# Test de connectivité
ping <pod-ip>
curl <service-name>.<namespace>.svc.cluster.local

# DNS
nslookup kubernetes.default
dig kubernetes.default.svc.cluster.local

# Traceroute
traceroute <pod-ip>

# Port scanning
nc -zv <service-name> 80
```

---

## Exercices pratiques

### Exercice 1 : Déploiement HA complet

**Objectif :** Déployer une application 3-tiers avec haute disponibilité

**Instructions :**

1. Labelliser vos nœuds :
   ```bash
   kubectl label nodes worker1 tier=frontend zone=zone-a
   kubectl label nodes worker2 tier=backend zone=zone-b
   kubectl label nodes worker3 tier=database zone=zone-c disktype=ssd
   ```

2. Créer les manifests pour :
   - Frontend (5 replicas, répartis sur différents nœuds)
   - Backend (3 replicas, proche du frontend)
   - Database (1 replica, sur nœud SSD)

3. Créer des PodDisruptionBudgets appropriés

4. Tester la résilience :
   - Drainer un nœud
   - Vérifier que l'application reste disponible

**Solution :** Voir `exercices/exercice1-ha-deployment.yaml`

### Exercice 2 : Maintenance planifiée

**Objectif :** Effectuer une maintenance sur un nœud sans interruption de service

**Scénario :**
Vous devez mettre à jour le kernel sur worker2 qui héberge des applications critiques.

**Instructions :**

1. Déployer une application de test avec 6 replicas et un PDB (minAvailable: 4)
2. Cordon worker2
3. Drain worker2
4. Simuler la maintenance (sleep 60)
5. Réactiver worker2
6. Vérifier que tous les pods sont revenus

**Script solution :** Voir `exercices/exercice2-maintenance.sh`

### Exercice 3 : Isolation des workloads

**Objectif :** Isoler différents types de workloads sur des nœuds dédiés

**Instructions :**

1. Créer 3 catégories de nœuds :
   - Production (worker1)
   - Staging (worker2)
   - Development (worker3)

2. Utiliser taints et tolerations pour isoler

3. Déployer des applications sur chaque environnement

4. Vérifier qu'elles sont bien isolées

**Solution :** Voir `exercices/exercice3-isolation.yaml`

### Exercice 4 : Auto-scaling et gestion de charge

**Objectif :** Configurer l'auto-scaling et gérer la charge sur les nœuds

**Instructions :**

1. Installer Metrics Server
2. Créer un HPA (Horizontal Pod Autoscaler)
3. Générer de la charge
4. Observer la répartition sur les nœuds

**Manifest :** Voir `exercices/exercice4-autoscaling.yaml`

### Exercice 5 : Troubleshooting d'un cluster

**Objectif :** Diagnostiquer et résoudre des problèmes de nœuds

**Scénarios à résoudre :**

1. Un nœud est en NotReady
2. Des pods restent en Pending
3. Un nœud consomme 100% CPU
4. etcd ne répond plus sur un master

**Guide de résolution :** Voir `exercices/exercice5-troubleshooting.md`

---

## Bonnes pratiques

### 1. Architecture

✅ **À faire :**
- Déployer au minimum 3 control planes en production
- Utiliser un load balancer pour l'API server
- Séparer etcd sur des nœuds dédiés (clusters critiques)
- Répartir les nœuds sur plusieurs zones de disponibilité
- Utiliser des nœuds de tailles homogènes par pool

❌ **À éviter :**
- Cluster avec un seul control plane en production
- Nombre pair de control planes (problèmes de quorum)
- Mélanger workloads de production et développement
- Nœuds sous-dimensionnés

### 2. Labels et organisation

✅ **À faire :**
- Utiliser des labels cohérents et documentés
- Préfixer les labels custom (company.com/label)
- Labelliser les nœuds par : environment, zone, workload type
- Documenter la stratégie de labellisation

❌ **À éviter :**
- Labels ad-hoc sans convention
- Modifier les labels système Kubernetes
- Trop de labels (garde la simplicité)

### 3. Taints et Tolerations

✅ **À faire :**
- Utiliser pour isoler des workloads spéciaux (GPU, SSD)
- Documenter tous les taints appliqués
- Préférer NoSchedule à NoExecute (moins disruptif)
- Combiner avec labels pour une meilleure clarté

❌ **À éviter :**
- Taints sans documentation
- NoExecute sans toleration grace period
- Trop de taints (complexité inutile)

### 4. Maintenance

✅ **À faire :**
- Toujours utiliser cordon avant drain
- Utiliser des PodDisruptionBudgets
- Planifier les maintenances hors heures de pointe
- Automatiser avec des scripts
- Tester d'abord sur un nœud non-critique
- Monitorer pendant l'opération

❌ **À éviter :**
- Drain sans --ignore-daemonsets
- Supprimer un nœud sans l'évacuer
- Maintenances simultanées sur plusieurs nœuds
- Oublier de uncordon après maintenance

### 5. Upgrades

✅ **À faire :**
- Upgrade version par version (pas de saut)
- Lire les release notes avant upgrade
- Backup etcd avant toute upgrade
- Upgrade control planes avant workers
- Tester en staging d'abord
- Un nœud à la fois avec validation entre chaque

❌ **À éviter :**
- Upgrade directe multi-versions
- Upgrade sans backup
- Upgrade de tous les nœuds en parallèle
- Upgrade en production sans test

### 6. Monitoring

✅ **À faire :**
- Installer Metrics Server
- Monitorer CPU, RAM, disk des nœuds
- Configurer des alertes sur les conditions
- Logger les events importants
- Utiliser Node Problem Detector

❌ **À éviter :**
- Cluster sans monitoring
- Ignorer les warnings
- Pas d'alerting configuré

### 7. Sécurité

✅ **À faire :**
- Rotate les certificats régulièrement
- Restreindre l'accès SSH aux nœuds
- Utiliser RBAC pour limiter les accès
- Sécuriser etcd (encryption at rest)
- Maintenir les nœuds à jour (security patches)

❌ **À éviter :**
- Certificats expirés
- Accès root sans restriction
- etcd non chiffré
- Nœuds non patchés

---

## Résumé des commandes importantes

```bash
# Gestion des nœuds
kubectl get nodes
kubectl describe node <node-name>
kubectl top nodes
kubectl cordon <node-name>
kubectl uncordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Labels
kubectl label nodes <node-name> key=value
kubectl get nodes --show-labels
kubectl get nodes -l key=value

# Taints
kubectl taint nodes <node-name> key=value:effect
kubectl taint nodes <node-name> key-  # Supprimer

# Cluster
kubectl cluster-info
kubectl get componentstatuses
kubeadm token create --print-join-command
kubeadm certs check-expiration

# Debugging
kubectl get events --sort-by='.lastTimestamp'
kubectl logs -n kube-system <pod-name>
journalctl -u kubelet -f  # Sur le nœud

# Upgrade
kubeadm upgrade plan
kubeadm upgrade apply v1.28.5
kubeadm upgrade node

# etcd
etcdctl endpoint health
etcdctl member list
etcdctl snapshot save <file>
etcdctl snapshot restore <file>
```

---

## Ressources complémentaires

### Documentation officielle
- [Kubernetes Multi-Node Setup](https://kubernetes.io/docs/setup/production-environment/)
- [kubeadm Documentation](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Node Management](https://kubernetes.io/docs/concepts/architecture/nodes/)
- [Cluster Administration](https://kubernetes.io/docs/tasks/administer-cluster/)

### Outils
- **kubeadm** : Bootstrap de clusters
- **kubespray** : Déploiement automatisé avec Ansible
- **kops** : Clusters sur cloud providers
- **Rancher** : Management de clusters
- **Lens** : IDE Kubernetes

### Concepts avancés
- Cluster Federation (multi-cluster)
- Cluster Autoscaler
- Vertical Pod Autoscaler
- Descheduler
- Node Feature Discovery

---

## Conclusion

Ce TP vous a permis de :

✅ Comprendre l'architecture multi-noeud de Kubernetes
✅ Déployer un cluster HA avec kubeadm
✅ Maîtriser la gestion du cycle de vie des nœuds
✅ Utiliser les stratégies de planification avancées
✅ Effectuer des maintenances sans interruption
✅ Monitorer et troubleshooter un cluster

**Prochaines étapes :**
- Explorer les clusters managés (EKS, GKE, AKS)
- Approfondir l'auto-scaling (Cluster Autoscaler)
- Étudier la fédération de clusters
- Mettre en place du disaster recovery

**Bon apprentissage et bonne gestion de vos clusters Kubernetes !**
