# Exercice 10 : Application WordPress Complète

## Description

Cet exercice déploie une application WordPress complète avec :
- Une base de données MySQL
- Un serveur WordPress
- Des volumes persistants pour les données
- Un service NodePort pour l'accès externe

## Fichiers

- `wordpress-namespace.yaml` : Namespace dédié `wordpress-app`
- `wordpress-secret.yaml` : Secret pour le mot de passe MySQL
- `wordpress-mysql.yaml` : Déploiement MySQL avec PVC et Service
- `wordpress-app.yaml` : Déploiement WordPress avec PVC et Service

## Déploiement

```bash
# 1. Créer le namespace
kubectl apply -f wordpress-namespace.yaml

# 2. Créer le secret
kubectl apply -f wordpress-secret.yaml

# 3. Déployer MySQL
kubectl apply -f wordpress-mysql.yaml

# 4. Déployer WordPress
kubectl apply -f wordpress-app.yaml

# 5. Attendre que tout soit prêt
kubectl wait --for=condition=ready pod -l app=mysql -n wordpress-app --timeout=120s
kubectl wait --for=condition=ready pod -l app=wordpress -n wordpress-app --timeout=120s
```

## Vérification

```bash
# Vérifier les pods
kubectl get pods -n wordpress-app

# Vérifier les services
kubectl get svc -n wordpress-app

# Vérifier les PVC
kubectl get pvc -n wordpress-app
```

## Accès à WordPress

### Avec Minikube

```bash
minikube service wordpress-service -n wordpress-app
```

### Avec Kubeadm

```bash
# Récupérer le NodePort et l'IP d'un nœud
NODE_PORT=$(kubectl get svc wordpress-service -n wordpress-app -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "WordPress accessible à : http://$NODE_IP:$NODE_PORT"
```

Le NodePort par défaut est configuré sur `30080`, donc vous pouvez aussi accéder directement à :
- `http://<NODE_IP>:30080`

## Nettoyage

```bash
# Supprimer toutes les ressources
kubectl delete -f wordpress-app.yaml
kubectl delete -f wordpress-mysql.yaml
kubectl delete -f wordpress-secret.yaml
kubectl delete -f wordpress-namespace.yaml

# Ou supprimer directement le namespace (supprime tout)
kubectl delete namespace wordpress-app
```

## Points clés

1. **Ordre de déploiement** : Il est important de déployer MySQL avant WordPress
2. **Secrets** : Le mot de passe MySQL est stocké dans un Secret Kubernetes
3. **Persistance** : Les données MySQL et WordPress sont stockées dans des PersistentVolumeClaims
4. **Networking** : WordPress se connecte à MySQL via le service `mysql-service`
5. **Exposition** : WordPress est exposé via un service NodePort sur le port 30080

## Sécurité

Cette configuration implémente les meilleures pratiques de sécurité Kubernetes :

### MySQL (wordpress-mysql.yaml)
- **runAsNonRoot**: true - Le container tourne avec l'utilisateur mysql (UID 999)
- **readOnlyRootFilesystem**: true - Système de fichiers en lecture seule avec volumes emptyDir pour /tmp et /var/run/mysqld
- **allowPrivilegeEscalation**: false - Empêche l'escalade de privilèges
- **capabilities**: DROP ALL - Suppression de toutes les capabilities Linux
- **seccompProfile**: RuntimeDefault - Utilisation du profil seccomp par défaut

### WordPress (wordpress-app.yaml)
- **runAsNonRoot**: true - Le container tourne avec l'utilisateur www-data (UID 33)
- **readOnlyRootFilesystem**: true - Système de fichiers en lecture seule avec volumes emptyDir pour /tmp, /var/run/apache2 et /var/lock/apache2
- **allowPrivilegeEscalation**: false - Empêche l'escalade de privilèges
- **capabilities**: DROP ALL - Suppression de toutes les capabilities Linux
- **seccompProfile**: RuntimeDefault - Utilisation du profil seccomp par défaut

**Note sur le port 80** : WordPress utilise le port 80 (port privileged) pour la compatibilité standard. L'image officielle WordPress est configurée pour permettre à l'utilisateur www-data (non-root) d'écouter sur ce port via la configuration Apache.
