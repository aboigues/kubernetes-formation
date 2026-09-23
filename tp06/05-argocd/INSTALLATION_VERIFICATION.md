# Vérification de l'installation ArgoCD - TP6

## ✅ Vérifications effectuées

### 1. URL du manifeste d'installation
- **Status**: ✅ Validé
- **URL**: `https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`
- **Résultat**: L'URL est correcte et pointe vers la dernière version stable d'ArgoCD

### 2. CLI ArgoCD
- **Status**: ✅ Validé
- **URL**: `https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64`
- **Version actuelle**: v3.2.0
- **Résultat**: Le CLI est disponible et téléchargeable

### 3. Fichiers d'exemple
- **Status**: ✅ Validés
- **Fichiers vérifiés**:
  - `10-argocd-application.yaml` - Syntaxe YAML valide ✅
  - `11-argocd-helm-app.yaml` - Syntaxe YAML valide ✅

### 4. Commandes d'installation
- **Status**: ✅ Validées (re-testées le 2026-09-23 avec ArgoCD v3.5.3 sur microk8s / containerd)
- ⚠️ L'installation exige `kubectl apply --server-side --force-conflicts` : sans `--server-side`, le CRD `applicationsets.argoproj.io` (plus de 370 Ko) dépasse la limite de 256 Ko de l'annotation `last-applied-configuration`

## ⚠️ Recommandations et points d'attention

### 1. Prérequis ressources minimales

ArgoCD nécessite des ressources minimales pour fonctionner correctement:

**Recommandations pour minikube:**
```bash
# Démarrer minikube avec des ressources suffisantes
minikube start --cpus=4 --memory=4096
```

**Ressources minimales recommandées:**
- CPU: 2-4 cores
- Mémoire: 4 GB RAM
- Espace disque: 10 GB

### 2. Timeout d'installation

Le timeout actuel de 300s (5 minutes) peut être insuffisant sur des systèmes lents.

**Recommandation:**
```bash
# Augmenter le timeout si nécessaire
kubectl wait --for=condition=ready pod --all -n argocd --timeout=600s
```

### 3. Installation du CLI ArgoCD

L'installation dans `/usr/local/bin/` nécessite les droits sudo.

**Alternative sans sudo:**
```bash
# Télécharger dans un répertoire utilisateur
mkdir -p ~/.local/bin
curl -sSL -o ~/.local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x ~/.local/bin/argocd

# Ajouter au PATH si nécessaire
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 4. Port-forwarding

La commande actuelle utilise `&` pour mettre le port-forward en background:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

**Recommandations:**
- Pour une utilisation temporaire, exécuter sans `&` dans un terminal dédié
- Pour une utilisation permanente, créer un service de type NodePort ou LoadBalancer
- Alternative avec minikube:
  ```bash
  # Exposer via minikube service (optionnel)
  minikube service argocd-server -n argocd
  ```

### 5. Fichiers d'exemple

Les fichiers d'exemple utilisent des URLs de repository fictives:
- `https://github.com/username/my-gitops-repo.git`

**Action requise avant utilisation:**
Les étudiants doivent remplacer ces URLs par leurs propres repositories Git avant d'appliquer les fichiers.

**Exemple:**
```yaml
source:
  repoURL: https://github.com/VOTRE-USERNAME/VOTRE-REPO.git  # ⚠️ À modifier
  targetRevision: HEAD
  path: apps/my-app
```

### 6. Accès à l'UI ArgoCD

**Étapes complètes d'accès:**
```bash
# 1. Port-forward (terminal dédié recommandé)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 2. Dans un autre terminal, récupérer le mot de passe
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# 3. Accéder à l'UI
# Ouvrir un navigateur: https://localhost:8080
# Username: admin
# Password: [mot de passe récupéré à l'étape 2]
```

**Note de sécurité:**
- Accepter le certificat auto-signé dans le navigateur
- Changer le mot de passe admin après la première connexion

## 📋 Checklist d'installation

Avant de commencer l'installation d'ArgoCD, vérifier:

- [ ] minikube est démarré avec au moins 4GB de RAM
- [ ] kubectl est installé et configuré
- [ ] Le cluster a suffisamment de ressources disponibles
- [ ] Vous avez un terminal dédié pour le port-forward
- [ ] Vous avez un repository Git pour tester les applications ArgoCD

## 🔧 Commandes de vérification

Après l'installation, vérifier que tout fonctionne:

```bash
# Vérifier que tous les pods ArgoCD sont running
kubectl get pods -n argocd

# Vérifier les services
kubectl get svc -n argocd

# Vérifier la version d'ArgoCD
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].spec.containers[0].image}'
```

## 📚 Ressources supplémentaires

- [Documentation officielle ArgoCD](https://argo-cd.readthedocs.io/)
- [Getting Started Guide](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

## 🎓 Notes pour les formateurs

- Prévoir 10-15 minutes pour l'installation complète d'ArgoCD
- Anticiper les problèmes de ressources sur les machines des étudiants
- Avoir un repository Git d'exemple prêt pour les démonstrations
- Montrer comment gérer le mot de passe admin en production

---

**Date de vérification**: 2025-11-19
**Version ArgoCD testée**: v3.2.0 (latest stable)
**Status global**: ✅ Prêt pour l'installation
