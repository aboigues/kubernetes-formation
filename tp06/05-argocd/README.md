# ArgoCD - GitOps pour Kubernetes

Ce répertoire contient les ressources pour apprendre à utiliser ArgoCD, l'outil de déploiement continu GitOps pour Kubernetes.

## 📋 Prérequis

Avant de commencer, assurez-vous d'avoir:

- **minikube** démarré avec au moins 4GB de RAM:
  ```bash
  minikube start --cpus=4 --memory=4096
  ```
- **kubectl** installé et configuré
- Un **repository Git** pour héberger vos manifests (optionnel pour les tests)

## 🚀 Installation d'ArgoCD

### Étape 1: Créer le namespace

```bash
kubectl create namespace argocd
```

### Étape 2: Installer ArgoCD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Étape 3: Attendre que les pods soient prêts

```bash
# Attendre que tous les pods soient ready (timeout: 10 minutes)
kubectl wait --for=condition=ready pod --all -n argocd --timeout=600s
```

**Vérification:**
```bash
kubectl get pods -n argocd
```

Vous devriez voir tous les pods en état `Running` avec `1/1` dans la colonne READY.

### Étape 4: Accéder à l'UI ArgoCD

#### Option A: Port-forward (recommandé pour les tests)

Dans un terminal dédié:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Note**: Laissez ce terminal ouvert pendant que vous utilisez ArgoCD.

#### Option B: Exposer via NodePort (minikube)

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
minikube service argocd-server -n argocd
```

### Étape 5: Récupérer le mot de passe admin

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
```

**Important**: Notez ce mot de passe, vous en aurez besoin pour vous connecter.

### Étape 6: Se connecter à l'UI

1. Ouvrir un navigateur: https://localhost:8080
2. Accepter le certificat auto-signé
3. Se connecter avec:
   - **Username**: `admin`
   - **Password**: [mot de passe récupéré à l'étape 5]

## 🔧 Installation du CLI ArgoCD (optionnel)

### Méthode 1: Installation globale (nécessite sudo)

```bash
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### Méthode 2: Installation locale (sans sudo)

```bash
mkdir -p ~/.local/bin
curl -sSL -o ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x ~/.local/bin/argocd

# Ajouter au PATH si nécessaire
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Login avec le CLI

```bash
argocd login localhost:8080 --username admin --insecure
# Entrer le mot de passe récupéré précédemment
```

## 📁 Fichiers d'exemple

Ce répertoire contient deux exemples d'applications ArgoCD:

### 1. Application simple (10-argocd-application.yaml)

Application basique déployant depuis un repository Git.

**⚠️ Avant utilisation:**
- Remplacer `https://github.com/username/my-gitops-repo.git` par votre repository
- Adapter le `path` selon votre structure de repository

```bash
# Éditer le fichier pour mettre votre repository
nano 10-argocd-application.yaml

# Appliquer
kubectl apply -f 10-argocd-application.yaml

# Vérifier
kubectl get application -n argocd
```

### 2. Application Helm (11-argocd-helm-app.yaml)

Application déployant un Chart Helm depuis un repository Git.

**⚠️ Avant utilisation:**
- Remplacer l'URL du repository
- Adapter les valeurs Helm selon vos besoins

```bash
# Éditer le fichier
nano 11-argocd-helm-app.yaml

# Appliquer
kubectl apply -f 11-argocd-helm-app.yaml
```

## 🎯 Premiers pas avec ArgoCD

### Créer une application via le CLI

```bash
argocd app create my-app \
  --repo https://github.com/VOTRE-USERNAME/VOTRE-REPO.git \
  --path apps/my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated
```

### Commandes utiles

```bash
# Lister les applications
argocd app list

# Voir les détails d'une application
argocd app get my-app

# Synchroniser manuellement
argocd app sync my-app

# Voir l'historique
argocd app history my-app

# Rollback vers une version précédente
argocd app rollback my-app

# Supprimer une application
argocd app delete my-app
```

## 🔄 Workflow GitOps avec ArgoCD

1. **Pousser les modifications** dans votre repository Git
2. **ArgoCD détecte** automatiquement les changements (si sync automatique activé)
3. **ArgoCD synchronise** l'état du cluster avec Git
4. **Vérifier** dans l'UI ou via CLI que tout est en ordre

## 🛠️ Dépannage

### Les pods ne démarrent pas

```bash
# Vérifier les events
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Vérifier les logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Problème de ressources

```bash
# Vérifier les ressources du cluster
kubectl top nodes
kubectl top pods -n argocd
```

Si insuffisant, redémarrer minikube avec plus de ressources:
```bash
minikube stop
minikube start --cpus=4 --memory=6144
```

### Impossible de se connecter à l'UI

```bash
# Vérifier que le service est up
kubectl get svc argocd-server -n argocd

# Vérifier le port-forward
# S'assurer qu'aucun autre processus n'utilise le port 8080
lsof -i :8080
```

### Mot de passe oublié

```bash
# Régénérer le mot de passe admin
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "'$(htpasswd -nbBC 10 "" YOUR_NEW_PASSWORD | tr -d ':\n' | sed 's/$2y/$2a/')'",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'
```

## 📚 Pour aller plus loin

### Concepts clés ArgoCD

- **Application**: Ressource Kubernetes qui représente une application déployée
- **Project**: Regroupement logique d'applications avec des contraintes RBAC
- **Sync Policy**: Politique de synchronisation (automatique ou manuelle)
- **Health Status**: État de santé de l'application (Healthy, Progressing, Degraded)
- **Sync Status**: État de synchronisation (Synced, OutOfSync)

### Bonnes pratiques

1. **Organisation du repository Git**:
   ```
   gitops-repo/
   ├── base/
   │   └── manifests communs
   └── overlays/
       ├── dev/
       ├── staging/
       └── production/
   ```

2. **Utiliser des Projects** pour isoler les équipes et environnements

3. **Activer les notifications** pour être alerté des changements

4. **Configurer le RBAC** pour contrôler les accès

5. **Utiliser Kustomize ou Helm** pour gérer les variations d'environnement

## 🔗 Ressources

- [Documentation officielle ArgoCD](https://argo-cd.readthedocs.io/)
- [Getting Started Guide](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Exemples ArgoCD](https://github.com/argoproj/argocd-example-apps)

## 🧹 Nettoyage

Pour désinstaller complètement ArgoCD:

```bash
# Supprimer toutes les applications
kubectl delete applications --all -n argocd

# Supprimer ArgoCD
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Supprimer le namespace
kubectl delete namespace argocd
```

---

**Voir aussi**: Le fichier [INSTALLATION_VERIFICATION.md](./INSTALLATION_VERIFICATION.md) pour plus de détails sur la vérification de l'installation.
