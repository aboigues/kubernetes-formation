# Guide d'installation Kubernetes avec kubeadm

## Introduction

Ce guide vous accompagne dans l'installation d'un cluster Kubernetes avec **kubeadm**, l'outil officiel de bootstrap de clusters Kubernetes. Contrairement à minikube qui est destiné au développement local, kubeadm permet de déployer des clusters production-ready.

## Différences entre minikube et kubeadm

| Caractéristique | minikube | kubeadm |
|-----------------|----------|---------|
| **Usage** | Développement local | Production / Test |
| **Architecture** | Single-node (principalement) | Multi-node natif |
| **Installation** | Automatique | Manuelle mais contrôlée |
| **Réseau** | Configuré automatiquement | Nécessite un CNI plugin |
| **LoadBalancer** | Support intégré | Nécessite MetalLB ou cloud provider |
| **Addons** | Nombreux addons faciles | Installation manuelle |
| **Ressources** | Légères | Ressources réalistes |

## Prérequis matériels

### Configuration minimale (1 master + 2 workers)

**Master node :**
- 2 CPU minimum
- 2 Go RAM minimum
- 20 Go disque
- Connexion réseau entre tous les nœuds
- Accès Internet (pour télécharger les images)

**Worker nodes :**
- 1 CPU minimum
- 1 Go RAM minimum
- 20 Go disque
- Connexion réseau

### Configuration recommandée

**Master node :**
- 4 CPU
- 8 Go RAM
- 50 Go disque SSD

**Worker nodes :**
- 2 CPU
- 4 Go RAM
- 50 Go disque SSD

## Partie 1 : Préparation des nœuds

Ces étapes doivent être exécutées sur **TOUS** les nœuds (master et workers).

### 1.1 Mise à jour du système (AlmaLinux/Rocky Linux)

```bash
# Mettre à jour le système
sudo dnf update -y

# Installer les outils de base
sudo dnf install -y curl wget git vim bash-completion
```

### 1.2 Désactivation de SELinux et du firewall

```bash
# Désactiver SELinux (nécessaire pour kubeadm)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Désactiver le firewall (ou configurer les règles appropriées)
sudo systemctl disable --now firewalld
```

**Note production :** En production, il est préférable de configurer le firewall avec les règles appropriées plutôt que de le désactiver.

### 1.3 Désactivation du swap

Kubernetes ne fonctionne pas correctement avec le swap activé.

```bash
# Désactiver le swap immédiatement
sudo swapoff -a

# Désactiver le swap de manière permanente
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Vérifier que le swap est désactivé
free -h
```

### 1.4 Configuration des modules kernel

```bash
# Charger les modules nécessaires
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configuration sysctl pour Kubernetes
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Appliquer les paramètres sysctl
sudo sysctl --system
```

### 1.5 Installation du runtime de conteneurs (containerd)

```bash
# Installer containerd
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y containerd.io

# Créer la configuration par défaut
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Configurer le cgroup driver pour systemd
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Redémarrer containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Vérifier que containerd fonctionne
sudo systemctl status containerd
```

### 1.6 Installation de kubeadm, kubelet et kubectl

```bash
# Ajouter le dépôt Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Installer les packages
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Activer kubelet
sudo systemctl enable --now kubelet
```

## Partie 2 : Initialisation du cluster (Master uniquement)

Ces étapes sont à exécuter **UNIQUEMENT sur le nœud master**.

### 2.1 Initialisation du cluster

```bash
# Initialiser le cluster
# Remplacer 10.244.0.0/16 par votre réseau pod si nécessaire
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# IMPORTANT : Sauvegarder la commande 'kubeadm join' affichée à la fin !
# Elle ressemble à :
# kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

### 2.2 Configuration de kubectl pour l'utilisateur courant

```bash
# Créer le répertoire .kube
mkdir -p $HOME/.kube

# Copier la configuration admin
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Changer le propriétaire
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Vérifier que kubectl fonctionne
kubectl get nodes
```

Vous devriez voir votre master node avec le statut `NotReady` (normal, le réseau n'est pas encore configuré).

### 2.3 Installation d'un plugin CNI (réseau)

Kubernetes nécessite un plugin CNI pour la communication entre pods. Voici plusieurs options :

#### Option A : Calico (recommandé pour production)

```bash
# Télécharger le manifest Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Vérifier le déploiement
kubectl get pods -n kube-system -w
```

#### Option B : Flannel (plus simple)

```bash
# Installer Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Vérifier le déploiement
kubectl get pods -n kube-system -w
```

Attendez que tous les pods soient en état `Running`.

### 2.4 Vérification du master

```bash
# Vérifier les nœuds
kubectl get nodes

# Le master devrait maintenant être Ready
# NAME              STATUS   ROLES           AGE   VERSION
# master-node       Ready    control-plane   5m    v1.29.0

# Vérifier les pods système
kubectl get pods -n kube-system

# Vérifier les composants du cluster
kubectl get componentstatuses
```

## Partie 3 : Ajout de worker nodes

Ces étapes sont à exécuter sur **CHAQUE worker node**.

### 3.1 Joindre le worker au cluster

Utilisez la commande `kubeadm join` obtenue lors de l'initialisation du master :

```bash
# Exemple (utilisez VOTRE commande avec VOTRE token)
sudo kubeadm join 192.168.1.10:6443 \
  --token abcdef.0123456789abcdef \
  --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

### 3.2 Si vous avez perdu le token

Sur le master, générez un nouveau token :

```bash
# Créer un nouveau token
kubeadm token create --print-join-command

# Cela affichera la commande complète à exécuter sur les workers
```

### 3.3 Vérification sur le master

```bash
# Retourner sur le master et vérifier les nœuds
kubectl get nodes

# Vous devriez voir tous vos nœuds
# NAME              STATUS   ROLES           AGE   VERSION
# master-node       Ready    control-plane   10m   v1.29.0
# worker-node-1     Ready    <none>          2m    v1.29.0
# worker-node-2     Ready    <none>          1m    v1.29.0
```

## Partie 4 : Configuration post-installation

### 4.1 Labels et rôles

```bash
# Ajouter un label pour identifier les workers
kubectl label node worker-node-1 node-role.kubernetes.io/worker=worker
kubectl label node worker-node-2 node-role.kubernetes.io/worker=worker

# Vérifier les labels
kubectl get nodes --show-labels
```

### 4.2 Autoriser le scheduling sur le master (optionnel, déconseillé en production)

Par défaut, aucun pod utilisateur ne peut être schedulé sur le master.

```bash
# Retirer le taint du master (UNIQUEMENT pour les environnements de test)
kubectl taint nodes master-node node-role.kubernetes.io/control-plane:NoSchedule-

# Pour remettre le taint
kubectl taint nodes master-node node-role.kubernetes.io/control-plane:NoSchedule
```

### 4.3 Installation de Metrics Server

```bash
# Télécharger le manifest
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Pour un environnement de test, modifier pour accepter les certificats auto-signés
sed -i 's/- args:/- args:\n        - --kubelet-insecure-tls/' components.yaml

# Appliquer
kubectl apply -f components.yaml

# Vérifier
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
```

## Partie 5 : Test du cluster

### 5.1 Déploiement de test

```bash
# Créer un déploiement nginx
kubectl create deployment nginx-test --image=nginx:latest --replicas=3

# Vérifier les pods
kubectl get pods -o wide

# Les pods doivent être distribués sur les workers
```

### 5.2 Exposition avec NodePort

```bash
# Exposer le déploiement
kubectl expose deployment nginx-test --type=NodePort --port=80

# Récupérer le NodePort
kubectl get svc nginx-test

# Tester l'accès (remplacer <node-ip> et <nodeport>)
curl http://<worker-ip>:<nodeport>
```

### 5.3 Nettoyage

```bash
kubectl delete deployment nginx-test
kubectl delete service nginx-test
```

## Partie 6 : Configuration du LoadBalancer (MetalLB)

Pour simuler un LoadBalancer en bare-metal ou environnement on-premise.

### 6.1 Installation de MetalLB

```bash
# Installer MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

# Attendre que les pods soient prêts
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

### 6.2 Configuration de l'IP pool

Créer un fichier `metallb-config.yaml` :

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250  # Adapter à votre réseau
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

```bash
# Appliquer la configuration
kubectl apply -f metallb-config.yaml
```

### 6.3 Test du LoadBalancer

```bash
# Créer un service de type LoadBalancer
kubectl create deployment nginx-lb --image=nginx
kubectl expose deployment nginx-lb --type=LoadBalancer --port=80

# Vérifier l'IP externe assignée
kubectl get svc nginx-lb

# Tester
curl http://<external-ip>
```

## Partie 7 : Commandes équivalentes minikube vs kubeadm

### Démarrage du cluster

| minikube | kubeadm |
|----------|---------|
| `minikube start` | `sudo kubeadm init` (master)<br/>`sudo kubeadm join ...` (workers) |
| `minikube stop` | Arrêter les VMs/serveurs |
| `minikube delete` | `sudo kubeadm reset` sur tous les nœuds |

### Accès aux services

| minikube | kubeadm |
|----------|---------|
| `minikube service <name>` | Utiliser NodePort : `http://<node-ip>:<nodeport>` |
| `minikube service <name> --url` | `kubectl get svc <name>` puis construire l'URL |
| `minikube ip` | `kubectl get nodes -o wide` (voir INTERNAL-IP) |
| `minikube tunnel` | Utiliser MetalLB pour LoadBalancer |

### Dashboard

| minikube | kubeadm |
|----------|---------|
| `minikube dashboard` | Installation manuelle (voir TP4) |
| `minikube addons enable dashboard` | `kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/...` |

### Addons

| minikube | kubeadm |
|----------|---------|
| `minikube addons enable metrics-server` | Installation manuelle avec `kubectl apply` |
| `minikube addons enable ingress` | Installation manuelle de nginx-ingress |
| `minikube addons list` | Pas d'équivalent, installation manuelle de chaque composant |

### SSH et accès aux nœuds

| minikube | kubeadm |
|----------|---------|
| `minikube ssh` | `ssh user@<node-ip>` (accès SSH direct) |
| `minikube ssh "command"` | `ssh user@<node-ip> "command"` |

### Gestion du contexte

| minikube | kubeadm |
|----------|---------|
| Context automatique | `kubectl config use-context <cluster-name>` |
| Fichier config intégré | Fichier `~/.kube/config` à gérer |

## Partie 8 : Dépannage

### Problème : Les nœuds restent en NotReady

```bash
# Vérifier les logs kubelet
sudo journalctl -u kubelet -f

# Vérifier que le CNI est déployé
kubectl get pods -n kube-system

# Vérifier la configuration réseau
kubectl get nodes -o wide
```

### Problème : Le token a expiré

```bash
# Sur le master, créer un nouveau token
kubeadm token create --print-join-command
```

### Problème : Erreur de certificat

```bash
# Regénérer les certificats
sudo kubeadm init phase certs all --config=/path/to/kubeadm-config.yaml
```

### Problème : Pod en CrashLoopBackOff

```bash
# Voir les logs
kubectl logs <pod-name>

# Décrire le pod pour voir les événements
kubectl describe pod <pod-name>
```

### Reset complet du cluster

```bash
# Sur tous les nœuds (master et workers)
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config

# Puis réinitialiser depuis le début
```

## Partie 9 : Bonnes pratiques

### Sécurité

1. **Ne pas exposer l'API server** directement sur Internet
2. **Utiliser RBAC** pour contrôler les accès
3. **Chiffrer les secrets** avec un KMS provider
4. **Scanner les images** avec Trivy ou Clair
5. **Mettre à jour régulièrement** le cluster

### Haute disponibilité

1. **3 masters minimum** pour la haute disponibilité
2. **Load balancer** devant les masters
3. **Etcd externe** ou en cluster
4. **Backup régulier** d'etcd

### Monitoring

1. **Installer Prometheus** et Grafana (voir TP4)
2. **Configurer des alertes** pour les événements critiques
3. **Surveiller les ressources** des nœuds

### Réseau

1. **Utiliser Network Policies** pour isoler les pods (voir TP5)
2. **Configurer un Ingress Controller** pour le trafic HTTP/HTTPS
3. **Utiliser MetalLB** pour les LoadBalancers en bare-metal

## Partie 10 : Mise à jour du cluster

### Mise à jour de kubeadm

```bash
# Sur le master
sudo dnf update -y kubeadm --disableexcludes=kubernetes

# Vérifier la version
kubeadm version

# Planifier la mise à jour
sudo kubeadm upgrade plan

# Appliquer la mise à jour
sudo kubeadm upgrade apply v1.29.x

# Mettre à jour kubelet et kubectl
sudo dnf update -y kubelet kubectl --disableexcludes=kubernetes
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

### Mise à jour des workers

```bash
# Sur chaque worker
sudo dnf update -y kubeadm --disableexcludes=kubernetes
sudo kubeadm upgrade node

sudo dnf update -y kubelet kubectl --disableexcludes=kubernetes
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

## Partie 11 : Addons et fonctionnalités complémentaires

Cette section vous aide à configurer des addons équivalents aux addons minikube sur un cluster kubeadm.

### 11.1 Kubernetes Dashboard

**Installation :**

```bash
# Installer le dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Créer un ServiceAccount admin
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Créer un token
kubectl -n kubernetes-dashboard create token admin-user

# Accéder au dashboard
kubectl proxy

# Ouvrir dans le navigateur : http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

**Équivalence minikube :**
- `minikube dashboard` → `kubectl proxy` + navigateur web
- `minikube addons enable dashboard` → installation manuelle ci-dessus

### 11.2 Metrics Server (monitoring CPU/RAM)

**Installation :**

```bash
# Télécharger le manifest
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Pour environnement de test avec certificats auto-signés
sed -i 's/- args:/- args:\n        - --kubelet-insecure-tls/' components.yaml

# Appliquer
kubectl apply -f components.yaml

# Vérifier
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
kubectl top pods
```

**Équivalence minikube :**
- `minikube addons enable metrics-server` → installation manuelle ci-dessus
- `kubectl top nodes/pods` fonctionne identiquement

### 11.3 Ingress Controller (nginx-ingress)

> **⚠️ Projet retiré depuis mars 2026.** ingress-nginx n'est plus maintenu (plus de correctifs,
> y compris de sécurité) — ne le déployez plus, y compris pour un usage de test. L'approche
> moderne est la **Gateway API** avec NGINX Gateway Fabric, voir
> [TP6 §2.2](../tp06/README.md#22-installation-de-la-gateway-api-et-de-nginx-gateway-fabric)
> pour l'installation (elle ne dépend pas de minikube, elle fonctionne identiquement sur
> kubeadm). Les instructions ci-dessous sont conservées à titre de référence pour l'API
> `Ingress`, toujours au programme CKAD.

**Installation :**

```bash
# Installer nginx-ingress-controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

# Vérifier
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx

# Le service sera de type NodePort par défaut
# Pour obtenir le port :
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

**Équivalence minikube :**
- `minikube addons enable ingress` → installation manuelle ci-dessus
- Accès : via NodePort au lieu de l'IP minikube

### 11.4 Storage Provisioner

**Installation de local-path-provisioner :**

```bash
# Installer
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Définir comme default
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Vérifier
kubectl get storageclass
```

**Équivalence minikube :**
- `minikube addons enable storage-provisioner` → installation de local-path-provisioner
- StorageClass `standard` (minikube) → `local-path` (kubeadm)

### 11.5 Résumé des équivalences addons

| Addon minikube | Commande minikube | Équivalent kubeadm |
|----------------|-------------------|-------------------|
| **dashboard** | `minikube addons enable dashboard` | Manifests Kubernetes Dashboard |
| **metrics-server** | `minikube addons enable metrics-server` | Manifests metrics-server |
| **ingress** | `minikube addons enable ingress` | nginx-ingress-controller ⚠️ retiré mars 2026, préférer Gateway API (voir §11.3) |
| **storage-provisioner** | `minikube addons enable storage-provisioner` | local-path-provisioner |
| **metallb** | `minikube addons enable metallb` | Installation MetalLB (voir Partie 6) |
| **registry** | `minikube addons enable registry` | Installation Docker Registry |
| **volumesnapshots** | `minikube addons enable volumesnapshots` | CRDs snapshots + snapshot-controller |

## Ressources complémentaires

- [Documentation officielle kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Network plugins](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Production best practices](https://kubernetes.io/docs/setup/best-practices/)
- [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)

## Prochaines étapes

Maintenant que votre cluster kubeadm est opérationnel, vous pouvez :
- Suivre les TPs avec votre cluster kubeadm
- Déployer des applications réelles
- Configurer un Ingress Controller
- Mettre en place la haute disponibilité
- Automatiser le déploiement avec GitOps

---

**Note :** Ce guide est mis à jour pour Kubernetes 1.29. Adaptez les versions selon vos besoins.
