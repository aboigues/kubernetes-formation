# TP1 - Premier déploiement Kubernetes sur Windows (WSL2)

Ce document complète le [TP1 principal](README.md) pour les utilisateurs **Windows avec WSL2**.

> **💡 Important :** Ce guide utilise **WSL2 avec Ubuntu**, ce qui vous donne un environnement Linux complet avec Bash. Les commandes sont **identiques** au TP1 principal pour AlmaLinux.

## 📋 Avant de commencer

Assurez-vous d'avoir suivi le **[Guide d'installation Windows](../docs/WINDOWS_SETUP.md)** avant de commencer ce TP.

Vous devez avoir installé dans WSL2 :
- ✅ Ubuntu 22.04
- ✅ Docker
- ✅ kubectl
- ✅ Minikube (ou kubeadm)

---

## 🚀 Démarrage rapide

### Ouvrir votre environnement

1. **Lancer Ubuntu** depuis le menu Démarrer Windows
2. Vous êtes maintenant dans un **terminal Bash** Linux

### Démarrer les services

```bash
# Démarrer Docker
sudo service docker start

# Démarrer Minikube
minikube start

# Vérifier
kubectl get nodes
```

**Vous pouvez maintenant suivre le [TP1 principal](README.md) normalement !**

Les commandes sont identiques entre AlmaLinux et Ubuntu sur WSL2.

---

## 🎯 Différences spécifiques Windows/WSL2

### 1. Démarrage de Docker

Sur WSL2, Docker ne démarre pas automatiquement. Vous devez le démarrer à chaque session :

```bash
sudo service docker start
```

**Astuce :** Pour le démarrer automatiquement, ajoutez à `~/.bashrc` :

```bash
# Ajouter à la fin de ~/.bashrc
if ! service docker status > /dev/null 2>&1; then
    sudo service docker start > /dev/null 2>&1
fi
```

Puis recharger :
```bash
source ~/.bashrc
```

**Éviter de taper le mot de passe :** Éditer sudoers :

```bash
sudo visudo

# Ajouter à la fin (remplacer 'user' par votre nom d'utilisateur)
user ALL=(ALL) NOPASSWD: /usr/sbin/service docker start
```

### 2. Accès aux fichiers

#### Depuis WSL2 vers Windows

Les disques Windows sont montés sous `/mnt/` :

```bash
# Accéder à C:\
cd /mnt/c/

# Accéder à vos documents
cd /mnt/c/Users/<votre-nom>/Documents

# Créer un lien symbolique
ln -s /mnt/c/Users/<votre-nom>/Documents/kubernetes-formation ~/kubernetes-formation
```

#### Depuis Windows vers WSL2

Dans l'Explorateur Windows, tapez :
```
\\wsl$\Ubuntu-22.04\home\<votre-nom>
```

### 3. Éditeurs de fichiers

**VS Code (Recommandé)**

VS Code s'intègre parfaitement avec WSL2 :

```bash
# Dans WSL2, ouvrir un dossier avec VS Code
cd ~/kubernetes-formation/tp1
code .
```

VS Code installera automatiquement l'extension WSL.

**Vim**
```bash
vim fichier.yaml
```

**Nano (plus simple)**
```bash
nano fichier.yaml
```

### 4. Accès aux services web

Avec Minikube sur WSL2, vous pouvez accéder aux services depuis Windows :

**Option 1 : Utiliser `minikube service`**
```bash
# Cette commande ouvre automatiquement votre navigateur Windows
minikube service <service-name>
```

**Option 2 : Port forwarding**
```bash
kubectl port-forward service/<service-name> 8080:80

# Puis ouvrir dans Windows : http://localhost:8080
```

**Option 3 : Obtenir l'IP et le port**
```bash
# Obtenir l'IP de Minikube
minikube ip

# Obtenir le NodePort
kubectl get svc <service-name>

# Accéder depuis Windows : http://<minikube-ip>:<node-port>
```

---

## 📝 Exemple complet : Premier déploiement

Suivez ces étapes dans votre terminal Ubuntu WSL2 :

### 1. Préparer l'environnement

```bash
# Démarrer Docker si nécessaire
sudo service docker start

# Démarrer Minikube
minikube start

# Vérifier
kubectl get nodes
```

### 2. Créer un déploiement NGINX

```bash
# Créer le déploiement
kubectl create deployment nginx --image=nginx:latest

# Vérifier
kubectl get deployments
kubectl get pods
```

### 3. Exposer le service

```bash
# Exposer via NodePort
kubectl expose deployment nginx --type=NodePort --port=80

# Voir le service
kubectl get svc nginx
```

### 4. Accéder au service depuis Windows

```bash
# Option la plus simple : ouvre automatiquement le navigateur
minikube service nginx

# Ou obtenir l'URL
minikube service nginx --url
```

### 5. Scaler le déploiement

```bash
# Passer à 3 réplicas
kubectl scale deployment nginx --replicas=3

# Vérifier
kubectl get pods -o wide
```

### 6. Voir les logs

```bash
# Lister les pods
kubectl get pods

# Voir les logs d'un pod
kubectl logs <nom-du-pod>

# Suivre les logs en temps réel
kubectl logs -f <nom-du-pod>
```

### 7. Nettoyage

```bash
# Supprimer le déploiement et le service
kubectl delete deployment nginx
kubectl delete service nginx

# Vérifier
kubectl get all
```

---

## 📁 Travailler avec des fichiers YAML

### Créer les fichiers

**Option 1 : Avec VS Code (recommandé)**

```bash
cd ~/kubernetes-formation/tp1
code .
```

Créer `nginx-deployment.yaml` dans VS Code avec le contenu du TP1.

**Option 2 : Avec vim**

```bash
vim nginx-deployment.yaml
```

**Option 3 : Avec nano**

```bash
nano nginx-deployment.yaml
```

**Option 4 : Créer depuis Windows**

1. Ouvrir l'Explorateur Windows
2. Taper : `\\wsl$\Ubuntu-22.04\home\<votre-nom>\kubernetes-formation\tp1`
3. Créer les fichiers avec votre éditeur préféré (Notepad++, VS Code, etc.)

### Appliquer les fichiers

```bash
# Appliquer un fichier YAML
kubectl apply -f nginx-deployment.yaml

# Appliquer tous les fichiers d'un dossier
kubectl apply -f ./manifests/

# Vérifier
kubectl get all
```

---

## 🔧 Commandes utiles pour WSL2

### Gestion de WSL2 (depuis Windows)

Ouvrir PowerShell ou Invite de commandes :

```bash
# Lister les distributions WSL
wsl --list --verbose

# Arrêter WSL2 (ferme toutes les distributions)
wsl --shutdown

# Redémarrer Ubuntu
wsl -d Ubuntu-22.04

# Mettre à jour WSL
wsl --update
```

### Alias Bash recommandés

Ajouter à `~/.bashrc` pour gagner du temps :

```bash
# Ouvrir le fichier
nano ~/.bashrc

# Ajouter à la fin :

# Alias kubectl
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kga='kubectl get all'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# Alias Minikube
alias mk='minikube'
alias mks='minikube status'
alias mkstart='minikube start'
alias mkstop='minikube stop'

# Alias Docker
alias d='docker'
alias dps='docker ps'
alias di='docker images'

# Recharger
alias reload='source ~/.bashrc'
```

Puis recharger :
```bash
source ~/.bashrc
```

Maintenant vous pouvez utiliser :
```bash
k get pods        # au lieu de kubectl get pods
kgp              # au lieu de kubectl get pods
mk status        # au lieu de minikube status
```

---

## 🎓 Exercices du TP1 (identiques)

Vous pouvez suivre **tous les exercices du [TP1 principal](README.md)** sans modification.

Les commandes sont identiques car vous utilisez Ubuntu avec Bash.

### Exemple : Exercice 1 du TP1

```bash
# 1. Créer un déploiement
kubectl create deployment hello-kubernetes --image=gcr.io/google-samples/hello-app:1.0

# 2. Exposer le déploiement
kubectl expose deployment hello-kubernetes --type=NodePort --port=8080

# 3. Accéder au service
minikube service hello-kubernetes

# 4. Scaler
kubectl scale deployment hello-kubernetes --replicas=3

# 5. Mettre à jour
kubectl set image deployment/hello-kubernetes hello-app=gcr.io/google-samples/hello-app:2.0

# 6. Voir le rollout
kubectl rollout status deployment/hello-kubernetes

# 7. Rollback
kubectl rollout undo deployment/hello-kubernetes

# 8. Nettoyer
kubectl delete deployment hello-kubernetes
kubectl delete service hello-kubernetes
```

---

## 🐛 Troubleshooting spécifique Windows/WSL2

### Problème : Docker ne démarre pas

```bash
# Vérifier le statut
sudo service docker status

# Essayer de démarrer manuellement
sudo service docker start

# Voir les logs
sudo journalctl -u docker
```

### Problème : Minikube échoue au démarrage

```bash
# Vérifier que Docker fonctionne
docker ps

# Supprimer et recréer Minikube
minikube delete
minikube start --driver=docker

# Voir les logs détaillés
minikube logs
```

### Problème : kubectl ne trouve pas le cluster

```bash
# Vérifier le contexte
kubectl config current-context

# Lister les contextes
kubectl config get-contexts

# Utiliser le contexte minikube
kubectl config use-context minikube

# Pour Minikube, mettre à jour le contexte
minikube update-context
```

### Problème : Espace disque insuffisant

```bash
# Voir l'utilisation du disque
df -h

# Nettoyer Docker
docker system prune -a

# Nettoyer Minikube
minikube delete
minikube start
```

### Problème : WSL2 est lent

**Solution 1 : Limiter la mémoire**

Depuis Windows, créer `C:\Users\<votre-nom>\.wslconfig` :

```ini
[wsl2]
memory=4GB
processors=2
swap=0
localhostForwarding=true
```

Puis redémarrer WSL2 :
```bash
# Depuis PowerShell
wsl --shutdown
```

**Solution 2 : Désactiver l'antivirus pour WSL2**

Dans Windows Defender, ajouter une exception pour :
```
\\wsl$\Ubuntu-22.04
```

### Problème : Port déjà utilisé

```bash
# Voir les processus utilisant un port
sudo lsof -i :8080

# Tuer un processus
sudo kill <PID>
```

---

## 💡 Astuces et bonnes pratiques

### 1. Windows Terminal (recommandé)

Installer Windows Terminal pour une meilleure expérience :

- Via Microsoft Store : chercher "Windows Terminal"
- Ou via commande : `winget install Microsoft.WindowsTerminal`

Configurer Ubuntu comme profil par défaut :
1. Ouvrir Windows Terminal
2. Settings (Ctrl + ,)
3. Startup → Default profile → Ubuntu-22.04

### 2. Copier-coller dans le terminal

- **Copier :** Sélectionner le texte (copie automatique)
- **Coller :** Clic droit ou Ctrl + Shift + V

### 3. Historique des commandes

```bash
# Chercher dans l'historique
Ctrl + R

# Naviguer dans l'historique
Flèche haut/bas

# Voir l'historique complet
history

# Exécuter une commande de l'historique
!<numéro>
```

### 4. Auto-complétion

```bash
# Activer l'auto-complétion kubectl
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc

# Utiliser la tabulation pour compléter
kubectl get po[TAB]    # complète en 'pods'
kubectl get pods -n ku[TAB]    # complète le namespace
```

### 5. Accès rapide aux logs

```bash
# Logs du dernier déploiement
kubectl logs -l app=nginx

# Logs en temps réel de tous les pods
kubectl logs -f -l app=nginx --all-containers=true

# Logs avec horodatage
kubectl logs <pod> --timestamps=true
```

### 6. Surveiller les ressources

```bash
# Activer metrics-server
minikube addons enable metrics-server

# Voir l'utilisation des ressources
kubectl top nodes
kubectl top pods
```

---

## 🚀 Workflow de développement recommandé

### Configuration initiale (une fois)

```bash
# 1. Installer et configurer WSL2 + Ubuntu (voir guide Windows)

# 2. Cloner le repo dans WSL2
cd ~
git clone https://github.com/aboigues/kubernetes-formation.git
cd kubernetes-formation

# 3. Configurer les alias et auto-complétion
# (voir section Alias Bash recommandés)

# 4. Démarrer Minikube
minikube start
```

### Session de travail quotidienne

```bash
# 1. Ouvrir Ubuntu (menu Démarrer Windows)

# 2. Démarrer Docker (si pas automatique)
sudo service docker start

# 3. Démarrer Minikube (si arrêté)
minikube start

# 4. Vérifier que tout fonctionne
kubectl get nodes

# 5. Aller dans le projet
cd ~/kubernetes-formation/tp1

# 6. Ouvrir VS Code
code .

# 7. Travailler dans VS Code + Terminal
```

### Fin de session

```bash
# Optionnel : arrêter Minikube pour libérer des ressources
minikube stop

# Optionnel : arrêter Docker
sudo service docker stop

# Fermer le terminal
exit
```

---

## 📚 Ressources supplémentaires

### Documentation

- [WSL Documentation](https://docs.microsoft.com/windows/wsl/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [VS Code WSL](https://code.visualstudio.com/docs/remote/wsl)

### Outils recommandés

```bash
# k9s - Interface terminal pour Kubernetes
curl -sS https://webinstall.dev/k9s | bash

# Helm - Gestionnaire de packages Kubernetes
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectx/kubens - Changer de contexte facilement
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens
```

---

## ✅ Checklist de vérification

Avant de passer au TP2, vérifiez que vous savez :

- [ ] Ouvrir Ubuntu dans WSL2
- [ ] Démarrer Docker et Minikube
- [ ] Créer un déploiement avec kubectl
- [ ] Exposer un service
- [ ] Accéder à un service depuis Windows
- [ ] Voir les logs d'un pod
- [ ] Scaler un déploiement
- [ ] Créer et appliquer des fichiers YAML
- [ ] Utiliser VS Code avec WSL2
- [ ] Faire un rollout et un rollback

---

## 🎯 Prochaines étapes

Félicitations ! Vous avez terminé le TP1 sur Windows avec WSL2.

**Continuez avec :**
- 📚 [TP2 - Maîtriser les Manifests Kubernetes](../tp2/README.md)

**Note :** Les TPs suivants utilisent les mêmes commandes. Vous n'avez plus besoin de guides spécifiques Windows, suivez simplement les TPs principaux !

---

**Bon apprentissage Kubernetes sur Windows avec WSL2 !** 🚀
