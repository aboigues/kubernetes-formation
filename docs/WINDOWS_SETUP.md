# Guide d'installation Kubernetes sur Windows avec WSL2

Ce guide vous permet de suivre la formation Kubernetes sur une machine Windows **en utilisant WSL2 (Windows Subsystem for Linux)**, ce qui vous donne un environnement **Linux complet avec Bash**, identique aux instructions du cours.

## Pourquoi WSL2 ?

- ✅ **Environnement Linux natif** sur Windows
- ✅ **Commandes Bash identiques** au cours AlmaLinux
- ✅ **Pas besoin de PowerShell**
- ✅ Performance native pour Docker et Kubernetes
- ✅ Accès aux fichiers Windows depuis Linux

---

## Table des matières

1. [Prérequis Windows](#prérequis-windows)
2. [Installation de WSL2 et Ubuntu](#installation-de-wsl2-et-ubuntu)
3. [Option A : Minikube sur WSL2](#option-a--minikube-sur-wsl2-recommandé)
4. [Option B : kubeadm sur WSL2](#option-b--kubeadm-sur-wsl2)
5. [Vérification de l'installation](#vérification-de-linstallation)
6. [Accès aux fichiers et éditeurs](#accès-aux-fichiers-et-éditeurs)
7. [Troubleshooting](#troubleshooting)

---

## Prérequis Windows

### Configuration matérielle minimale

- **Processeur :** 64-bit avec support de virtualisation (Intel VT-x ou AMD-V)
- **RAM :** 4 Go minimum (8 Go recommandé)
- **Disque :** 20 Go d'espace libre
- **OS :** Windows 10 version 2004+ (Build 19041+) ou Windows 11

### Vérification de la virtualisation

1. Ouvrir le **Gestionnaire des tâches** (Ctrl + Shift + Échap)
2. Onglet **Performance** → **CPU**
3. Vérifier que **Virtualisation : Activé**

Si désactivé, activer dans le BIOS/UEFI :
- Redémarrer et accéder au BIOS (généralement F2, F10, ou Suppr au démarrage)
- Chercher **Intel VT-x** ou **AMD-V** et l'activer
- Sauvegarder et redémarrer

---

## Installation de WSL2 et Ubuntu

### Étape 1 : Installation rapide (Windows 11 ou Windows 10 récent)

Ouvrir **PowerShell ou Invite de commandes** en tant qu'**administrateur** et exécuter :

```bash
wsl --install
```

Cette commande va :
- Activer WSL
- Installer WSL2
- Installer Ubuntu par défaut
- Redémarrer si nécessaire

**Redémarrer Windows après l'installation.**

### Étape 2 : Installation manuelle (si nécessaire)

Si la commande `wsl --install` ne fonctionne pas :

#### 2.1 Activer WSL

```bash
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```

#### 2.2 Activer la plateforme de machine virtuelle

```bash
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

#### 2.3 Redémarrer Windows

```bash
shutdown /r /t 0
```

#### 2.4 Définir WSL 2 comme version par défaut

Après le redémarrage, ouvrir PowerShell en administrateur :

```bash
wsl --set-default-version 2
```

#### 2.5 Installer Ubuntu

**Option A : Via Microsoft Store**
- Ouvrir le Microsoft Store
- Chercher "Ubuntu 22.04 LTS"
- Cliquer "Installer"

**Option B : Via ligne de commande**
```bash
wsl --install -d Ubuntu-22.04
```

### Étape 3 : Premier démarrage d'Ubuntu

1. Lancer **Ubuntu** depuis le menu Démarrer
2. Attendre l'installation initiale (quelques minutes)
3. Créer un nom d'utilisateur (exemple : `user`)
4. Créer un mot de passe
5. Confirmer le mot de passe

**Félicitations ! Vous avez maintenant un terminal Linux (Bash) sur Windows !**

### Étape 4 : Mise à jour du système

Dans votre terminal Ubuntu WSL2 :

```bash
# Mettre à jour les packages
sudo apt update && sudo apt upgrade -y

# Installer les outils de base
sudo apt install -y curl wget git vim ca-certificates gnupg lsb-release
```

---

## Option A : Minikube sur WSL2 (Recommandé)

Cette option est **la plus simple** et parfaite pour suivre la formation.

### A.1 Installation de Docker dans WSL2

```bash
# Ajouter la clé GPG Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Ajouter le repository Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installer Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Démarrer Docker
sudo service docker start

# Ajouter votre utilisateur au groupe docker
sudo usermod -aG docker $USER

# Appliquer les changements
newgrp docker

# Vérifier Docker
docker --version
docker run hello-world
```

**Note :** Sur WSL2, Docker doit être démarré manuellement à chaque session :
```bash
sudo service docker start
```

Pour le démarrer automatiquement, ajoutez à votre `~/.bashrc` :
```bash
# Démarrer Docker automatiquement
if ! service docker status > /dev/null 2>&1; then
    sudo service docker start > /dev/null 2>&1
fi
```

### A.2 Installation de kubectl

```bash
# Télécharger kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Rendre exécutable
chmod +x kubectl

# Déplacer vers /usr/local/bin
sudo mv kubectl /usr/local/bin/

# Vérifier
kubectl version --client
```

### A.3 Installation de Minikube

```bash
# Télécharger Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Installer
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Vérifier
minikube version
```

### A.4 Démarrer Minikube

```bash
# Démarrer Minikube avec le driver Docker
minikube start --driver=docker

# Définir Docker comme driver par défaut (optionnel)
minikube config set driver docker

# Vérifier le statut
minikube status

# Vérifier les nodes
kubectl get nodes
```

**Résultat attendu :**
```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   2m    v1.28.0
```

### A.5 Configuration de l'auto-complétion (optionnel mais recommandé)

```bash
# Ajouter à ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# Recharger
source ~/.bashrc
```

---

## Option B : kubeadm sur WSL2

Cette option crée un cluster Kubernetes plus proche d'un environnement de production.

### B.1 Prérequis

Assurez-vous que Docker est installé (voir section A.1).

### B.2 Installation de kubeadm, kubelet et kubectl

```bash
# Mettre à jour apt
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

# Ajouter la clé GPG Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Ajouter le repository Kubernetes
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Installer kubeadm, kubelet et kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### B.3 Configuration du système

```bash
# Désactiver swap (normalement pas actif dans WSL2)
sudo swapoff -a

# Charger les modules kernel
sudo modprobe overlay
sudo modprobe br_netfilter

# Configurer sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### B.4 Configuration de containerd

```bash
# Créer la configuration par défaut
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Activer SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Redémarrer containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### B.5 Initialiser le cluster

```bash
# Initialiser le cluster (single-node)
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Configurer kubectl pour l'utilisateur actuel
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### B.6 Installer un CNI (Flannel)

```bash
# Installer Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Attendre que les pods soient prêts
kubectl get pods -n kube-flannel -w
```

### B.7 Permettre le scheduling sur le master (pour single-node)

```bash
# Enlever le taint sur le master pour permettre le scheduling de pods
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Vérifier les nodes
kubectl get nodes
```

**Résultat attendu :**
```
NAME       STATUS   ROLES           AGE   VERSION
hostname   Ready    control-plane   5m    v1.28.0
```

---

## Vérification de l'installation

Quelle que soit l'option choisie (Minikube ou kubeadm), vérifiez :

```bash
# Vérifier la version de kubectl
kubectl version --client

# Vérifier les nodes
kubectl get nodes

# Vérifier tous les pods système
kubectl get pods -A

# Vérifier les informations du cluster
kubectl cluster-info

# (Pour Minikube uniquement) Vérifier le statut
minikube status
```

---

## Accès aux fichiers et éditeurs

### Accès aux fichiers Windows depuis WSL2

```bash
# Les disques Windows sont montés sous /mnt/
cd /mnt/c/Users/<votre-nom>/Documents

# Créer un lien symbolique vers vos projets
ln -s /mnt/c/Users/<votre-nom>/Documents/kubernetes-formation ~/kubernetes-formation
```

### Accès aux fichiers WSL2 depuis Windows

Dans l'Explorateur Windows, tapez dans la barre d'adresse :
```
\\wsl$\Ubuntu-22.04\home\<votre-nom>
```

Ou directement :
```
\\wsl$
```

### Éditeurs recommandés

**1. VS Code (Recommandé)**

VS Code s'intègre parfaitement avec WSL2 :

```bash
# Installer VS Code sur Windows depuis https://code.visualstudio.com/

# Dans WSL2, ouvrir un projet avec VS Code
cd ~/kubernetes-formation
code .
```

VS Code installera automatiquement l'extension "WSL" et vous donnera un environnement de développement complet.

**Extensions recommandées pour VS Code :**
- WSL (automatique)
- Kubernetes (ms-kubernetes-tools.vscode-kubernetes-tools)
- YAML (redhat.vscode-yaml)
- Docker (ms-azuretools.vscode-docker)

**2. Vim dans WSL2**

```bash
# Vim est déjà installé
vim fichier.yaml
```

**3. Nano (plus simple que Vim)**

```bash
nano fichier.yaml
```

---

## Commandes utiles WSL2

### Gestion de WSL2

```bash
# Depuis Windows (PowerShell/CMD), lister les distributions
wsl --list --verbose

# Arrêter WSL2
wsl --shutdown

# Redémarrer Ubuntu
wsl -d Ubuntu-22.04

# Définir Ubuntu comme distribution par défaut
wsl --set-default Ubuntu-22.04
```

### Démarrage automatique de services

Créer un script de démarrage `~/.bashrc` :

```bash
# Ajouter à la fin de ~/.bashrc
# Démarrer Docker automatiquement
if ! service docker status > /dev/null 2>&1; then
    sudo service docker start > /dev/null 2>&1
fi
```

Pour éviter de taper le mot de passe sudo à chaque fois :

```bash
# Éditer sudoers
sudo visudo

# Ajouter à la fin (remplacer 'user' par votre nom d'utilisateur)
user ALL=(ALL) NOPASSWD: /usr/sbin/service docker start
```

---

## Commandes Minikube utiles

```bash
# Démarrer Minikube
minikube start

# Démarrer avec plus de ressources
minikube start --cpus=4 --memory=8192 --disk-size=40g

# Arrêter Minikube
minikube stop

# Supprimer le cluster
minikube delete

# Voir le statut
minikube status

# Obtenir l'IP de Minikube
minikube ip

# Accéder au dashboard
minikube dashboard

# Activer des addons
minikube addons enable metrics-server
minikube addons enable dashboard
minikube addons enable ingress

# Lister les addons
minikube addons list

# Construire une image directement dans Minikube
# (fonctionne avec containerd, le runtime par défaut depuis minikube v1.39)
minikube image build -t myapp:v1 .

# Voir les images disponibles dans Minikube
minikube image ls

# Utiliser le daemon Docker de Minikube : seulement si le cluster a été créé
# avec --container-runtime=docker (sous containerd, docker build y échoue)
eval $(minikube docker-env)
eval $(minikube docker-env -u)   # retour au Docker local
```

---

## Troubleshooting

### Problème : WSL2 ne démarre pas

**Solution :**
```bash
# Depuis PowerShell (administrateur)
wsl --shutdown
wsl --update

# Redémarrer
wsl
```

### Problème : Docker ne démarre pas dans WSL2

**Symptôme :**
```
Cannot connect to the Docker daemon
```

**Solution :**
```bash
# Démarrer Docker manuellement
sudo service docker start

# Vérifier le statut
sudo service docker status

# Voir les logs en cas d'erreur
sudo journalctl -u docker
```

### Problème : "No space left on device"

**Solution :**

```bash
# Nettoyer Docker
docker system prune -a

# Voir l'utilisation du disque
df -h

# Nettoyer les images Minikube
minikube delete
minikube start
```

### Problème : Minikube ne démarre pas

**Solution :**

```bash
# Voir les logs
minikube logs

# Supprimer et recréer
minikube delete
minikube start --driver=docker

# Vérifier que Docker fonctionne
docker ps
```

### Problème : kubectl ne se connecte pas

**Solution :**

```bash
# Vérifier le contexte
kubectl config current-context

# Lister les contextes
kubectl config get-contexts

# Basculer vers minikube
kubectl config use-context minikube

# Mettre à jour le contexte (pour Minikube)
minikube update-context
```

### Problème : Lenteur de WSL2

**Solution 1 : Limiter la mémoire WSL2**

Créer le fichier `C:\Users\<votre-nom>\.wslconfig` (depuis Windows) :

```ini
[wsl2]
memory=4GB
processors=2
swap=0
localhostForwarding=true
```

Redémarrer WSL2 :
```bash
# Depuis PowerShell
wsl --shutdown
```

**Solution 2 : Désactiver les antivirus pour le dossier WSL2**

Ajouter une exception dans Windows Defender pour :
```
\\wsl$\Ubuntu-22.04
```

### Problème : systemctl ne fonctionne pas

WSL2 n'utilise pas systemd par défaut. Pour l'activer :

Éditer `/etc/wsl.conf` :
```bash
sudo nano /etc/wsl.conf
```

Ajouter :
```ini
[boot]
systemd=true
```

Redémarrer WSL2 :
```bash
# Depuis PowerShell
wsl --shutdown
```

---

## Pour aller plus loin

### Windows Terminal (Recommandé)

Windows Terminal est un terminal moderne qui améliore l'expérience WSL2 :

```bash
# Installer via Microsoft Store
# Chercher "Windows Terminal"

# Ou via winget (PowerShell)
winget install Microsoft.WindowsTerminal
```

Configurer Ubuntu comme profil par défaut :
1. Ouvrir Windows Terminal
2. Settings (Ctrl + ,)
3. Startup → Default profile → Ubuntu-22.04

### Outils utiles

```bash
# k9s - Terminal UI pour Kubernetes
curl -sS https://webinstall.dev/k9s | bash
source ~/.bashrc

# Helm - Gestionnaire de packages Kubernetes
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectx/kubens - Changer de contexte facilement
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens
```

### Alias Bash utiles

Ajouter à `~/.bashrc` :

```bash
# Alias kubectl
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kdp='kubectl describe pod'
alias kdd='kubectl describe deployment'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'

# Alias Minikube
alias mk='minikube'
alias mks='minikube status'
alias mkstart='minikube start'
alias mkstop='minikube stop'
alias mkd='minikube dashboard'

# Alias Docker
alias d='docker'
alias dps='docker ps'
alias di='docker images'

# Recharger .bashrc
alias reload='source ~/.bashrc'
```

Recharger :
```bash
source ~/.bashrc
```

---

## Résumé : Commandes essentielles

### Démarrage d'une session de travail

```bash
# 1. Ouvrir Ubuntu depuis le menu Démarrer

# 2. Démarrer Docker (si pas automatique)
sudo service docker start

# 3. Démarrer Minikube
minikube start

# 4. Vérifier
kubectl get nodes

# 5. Naviguer vers votre projet
cd ~/kubernetes-formation
```

### Vérifications rapides

```bash
# Cluster OK ?
kubectl get nodes

# Pods OK ?
kubectl get pods -A

# Services OK ?
kubectl get svc

# Tout est OK ?
kubectl get all
```

---

## Prochaines étapes

Maintenant que votre environnement WSL2 est configuré :

1. ✅ Vous avez un environnement Linux complet avec Bash
2. ✅ Les commandes du cours fonctionnent à l'identique
3. ✅ Kubernetes (Minikube ou kubeadm) est opérationnel

**Vous pouvez maintenant suivre les TPs normalement :**

- 📚 [TP1 - Premier déploiement Kubernetes](../tp1/README.md)
- 💡 [Version Windows du TP1 avec exemples](../tp1/WINDOWS.md) (optionnel)

**Bon apprentissage Kubernetes sur Windows avec WSL2 !** 🚀
