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
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

> ⚠️ `--server-side` est obligatoire : le CRD `applicationsets.argoproj.io` d'ArgoCD 3.x dépasse 370 Ko, au-delà de la limite de 256 Ko de l'annotation `last-applied-configuration` utilisée par un `kubectl apply` classique (erreur `metadata.annotations: Too long`).

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

Les deux Applications pointent sur **ce dépôt de formation** (public) : elles s'appliquent telles quelles, sans compte GitHub ni modification.

| Fichier | Déploie | Namespace |
|---|---|---|
| `10-argocd-application.yaml` | l'overlay Kustomize `tp06/07-gitops-structure/overlays/dev` | `dev` |
| `11-argocd-helm-app.yaml` | le chart Helm `tp06/01-helm/my-app` avec des valeurs surchargées | `production` |

```bash
kubectl apply -f 10-argocd-application.yaml
kubectl get application -n argocd -w
```

👉 Le parcours complet, avec les schémas et les expériences guidées (selfHeal, suppression de l'Application, modification de Git), est dans le [README du TP6, Partie 5](../README.md#partie-5--gitops-avec-argocd).

Pour **modifier Git** et voir ArgoCD suivre, remplacez `repoURL` par l'URL de votre fork du dépôt.

## 🎯 Premiers pas avec ArgoCD

### Créer une application via le CLI

```bash
argocd app create my-app-dev \
  --repo https://github.com/aboigues/kubernetes-formation.git \
  --path tp06/07-gitops-structure/overlays/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated --self-heal --auto-prune \
  --sync-option CreateNamespace=true
```

### Commandes utiles

```bash
# Lister les applications
argocd app list

# Voir les détails d'une application
argocd app get my-app-dev

# Synchroniser manuellement
argocd app sync my-app-dev

# Voir l'historique
argocd app history my-app-dev

# Rollback vers une version précédente
argocd app rollback my-app-dev   # refusé si la sync automatique est active : en GitOps, on fait git revert

# Supprimer une application
argocd app delete my-app-dev
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
