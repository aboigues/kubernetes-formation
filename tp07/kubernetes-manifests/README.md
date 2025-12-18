# Kubernetes Manifests - Application MyApp

Ce répertoire contient tous les manifests Kubernetes pour déployer l'application complète sur un cluster Kubernetes.

## Vue d'ensemble

L'application est composée de trois tiers :
- **Frontend** : Nginx servant une page HTML
- **Backend** : API Python simple avec endpoints de santé
- **Database** : PostgreSQL pour la persistance

## Structure des fichiers

```
00-namespace.yaml              # Namespace dédié pour l'application
01-database-secret.yaml        # Credentials PostgreSQL
02-backend-config.yaml         # Configuration du backend
03-database-pvc.yaml          # PersistentVolumeClaim pour PostgreSQL
04-database-deployment.yaml   # Déploiement PostgreSQL
05-database-service.yaml      # Service ClusterIP pour PostgreSQL
06-backend-code.yaml          # Code Python du backend (ConfigMap)
06-backend-deployment.yaml    # Déploiement du backend
07-backend-service.yaml       # Service ClusterIP pour le backend
08-frontend-nginx-config.yaml # Configuration Nginx avec proxy API (ConfigMap)
08-frontend-config.yaml       # HTML du frontend (ConfigMap)
09-frontend-deployment.yaml   # Déploiement du frontend
10-frontend-service.yaml      # Service NodePort pour le frontend
11-backend-hpa.yaml           # HorizontalPodAutoscaler pour le backend
12-network-policies.yaml      # Politiques réseau pour la sécurité
```

## Déploiement rapide

### Option 1 : Déploiement complet

```bash
# Déployer tous les manifests dans l'ordre
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-database-secret.yaml
kubectl apply -f 02-backend-config.yaml
kubectl apply -f 03-database-pvc.yaml
kubectl apply -f 04-database-deployment.yaml
kubectl apply -f 05-database-service.yaml
kubectl apply -f 06-backend-code.yaml
kubectl apply -f 06-backend-deployment.yaml
kubectl apply -f 07-backend-service.yaml
kubectl apply -f 08-frontend-nginx-config.yaml
kubectl apply -f 08-frontend-config.yaml
kubectl apply -f 09-frontend-deployment.yaml
kubectl apply -f 10-frontend-service.yaml

# Optionnel : HPA (nécessite metrics-server)
minikube addons enable metrics-server
kubectl apply -f 11-backend-hpa.yaml

# Optionnel : Network Policies (nécessite un CNI compatible)
kubectl apply -f 12-network-policies.yaml
```

### Option 2 : Déploiement en une commande

```bash
# Appliquer tous les fichiers (sauf HPA et NetworkPolicies)
kubectl apply -f 00-namespace.yaml \
              -f 01-database-secret.yaml \
              -f 02-backend-config.yaml \
              -f 03-database-pvc.yaml \
              -f 04-database-deployment.yaml \
              -f 05-database-service.yaml \
              -f 06-backend-code.yaml \
              -f 06-backend-deployment.yaml \
              -f 07-backend-service.yaml \
              -f 08-frontend-nginx-config.yaml \
              -f 08-frontend-config.yaml \
              -f 09-frontend-deployment.yaml \
              -f 10-frontend-service.yaml
```

## Vérification du déploiement

```bash
# Vérifier tous les pods
kubectl get pods -n myapp

# Vérifier les services
kubectl get svc -n myapp

# Vérifier les PVC
kubectl get pvc -n myapp

# Vue d'ensemble complète
kubectl get all -n myapp

# Vérifier les logs
kubectl logs -n myapp -l app=frontend --tail=20
kubectl logs -n myapp -l app=backend --tail=20
kubectl logs -n myapp -l app=database --tail=20
```

## Accès à l'application

```bash
# Obtenir l'URL du frontend
minikube service frontend -n myapp --url

# Ou accéder directement via l'IP de minikube
curl http://$(minikube ip):30080

# Ouvrir dans le navigateur
minikube service frontend -n myapp
```

## Tests de validation

### Test de connectivité inter-services

```bash
# Frontend → Backend
kubectl exec -n myapp -it deployment/frontend -- wget -qO- http://backend:5000/api/health

# Backend → Database
kubectl exec -n myapp -it deployment/backend -- nc -zv database 5432
```

### Test de persistance

```bash
# Créer une table de test
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "CREATE TABLE test (id serial, data text);"

# Insérer des données
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "INSERT INTO test (data) VALUES ('data persistante');"

# Vérifier les données
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "SELECT * FROM test;"

# Supprimer le pod database
kubectl delete pod -n myapp -l app=database

# Attendre que le nouveau pod soit prêt
kubectl wait --for=condition=ready pod -n myapp -l app=database --timeout=60s

# Vérifier que les données persistent
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "SELECT * FROM test;"
```

### Test de résilience

```bash
# Supprimer un pod backend
kubectl delete pod -n myapp -l app=backend --field-selector=status.phase=Running | head -1

# Observer la recréation automatique
kubectl get pods -n myapp -l app=backend -w
```

### Test de scaling

```bash
# Scaler manuellement
kubectl scale deployment backend -n myapp --replicas=5

# Vérifier
kubectl get pods -n myapp -l app=backend

# Retour à la normale
kubectl scale deployment backend -n myapp --replicas=2
```

### Test HPA (si activé)

```bash
# Générer de la charge
kubectl run -n myapp load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://backend:5000/api/health; done"

# Observer l'autoscaling
kubectl get hpa -n myapp -w

# Nettoyer
kubectl delete pod load-generator -n myapp
```

## Ressources allouées

| Composant | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|----------|-------------|-----------|----------------|--------------|
| Frontend  | 2        | 50m         | 100m      | 64Mi           | 128Mi        |
| Backend   | 2-10*    | 100m        | 200m      | 128Mi          | 256Mi        |
| Database  | 1        | 250m        | 500m      | 256Mi          | 512Mi        |

\* avec HPA, scale entre 2 et 10 replicas selon la charge CPU/Memory

## Architecture réseau

```
┌─────────────────────────────────────────────────┐
│            Namespace: myapp                     │
│                                                 │
│  ┌──────────────┐                              │
│  │   Frontend   │  NodePort :30080             │
│  │  (Nginx)     │  ◄───────────────┐          │
│  └──────┬───────┘                   │          │
│         │                       External        │
│         │ http://backend:5000   Access         │
│         ▼                                       │
│  ┌──────────────┐                              │
│  │   Backend    │  ClusterIP                   │
│  │  (Python)    │                              │
│  └──────┬───────┘                              │
│         │                                       │
│         │ postgresql://database:5432            │
│         ▼                                       │
│  ┌──────────────┐                              │
│  │   Database   │  ClusterIP                   │
│  │ (PostgreSQL) │                              │
│  └──────┬───────┘                              │
│         │                                       │
│         ▼                                       │
│  ┌──────────────┐                              │
│  │     PVC      │  1Gi                         │
│  │ (database-   │                              │
│  │    pvc)      │                              │
│  └──────────────┘                              │
└─────────────────────────────────────────────────┘
```

## Nettoyage

```bash
# Supprimer toutes les ressources
kubectl delete namespace myapp

# Ou supprimer fichier par fichier
kubectl delete -f .
```

## Personnalisation

### Modifier le nombre de replicas

```bash
# Éditer directement
kubectl edit deployment frontend -n myapp

# Ou scaler
kubectl scale deployment frontend -n myapp --replicas=3
```

### Modifier les variables d'environnement

```bash
# Éditer le ConfigMap
kubectl edit configmap backend-config -n myapp

# Redémarrer les pods pour appliquer
kubectl rollout restart deployment backend -n myapp
```

### Modifier les ressources

```bash
# Éditer le deployment
kubectl edit deployment backend -n myapp

# Ou utiliser set resources
kubectl set resources deployment backend -n myapp \
  --requests=cpu=200m,memory=256Mi \
  --limits=cpu=400m,memory=512Mi
```

## Troubleshooting

### Pods ne démarrent pas

```bash
# Voir les événements
kubectl get events -n myapp --sort-by='.lastTimestamp'

# Décrire un pod
kubectl describe pod <pod-name> -n myapp

# Voir les logs
kubectl logs <pod-name> -n myapp
```

### Problème de connexion entre services

```bash
# Vérifier les services
kubectl get svc -n myapp

# Vérifier les endpoints
kubectl get endpoints -n myapp

# Tester la résolution DNS
kubectl exec -n myapp -it deployment/frontend -- nslookup backend
```

### Base de données ne démarre pas

```bash
# Vérifier le PVC
kubectl get pvc -n myapp

# Vérifier les logs
kubectl logs -n myapp -l app=database

# Vérifier les permissions
kubectl describe pvc database-pvc -n myapp
```

## Notes de sécurité

**Important** : Ces manifests sont conçus pour l'apprentissage et le développement local. Pour la production :

1. **Secrets** : Utilisez Sealed Secrets, Vault, ou le gestionnaire de secrets de votre cloud provider
2. **Images** : Utilisez des tags de version spécifiques, pas `latest`
3. **Resources** : Ajustez les requests/limits selon vos besoins réels
4. **Network Policies** : Activez et testez les Network Policies
5. **RBAC** : Configurez des ServiceAccounts et RBAC appropriés
6. **Monitoring** : Ajoutez Prometheus et Grafana
7. **Backup** : Mettez en place une stratégie de backup pour PostgreSQL
8. **Ingress** : Utilisez un Ingress au lieu de NodePort pour l'exposition

## Pour aller plus loin

- Consultez le [README principal du TP7](../README.md) pour le guide complet
- Voir [TP6 - Mise en Production](../../tp06/README.md) pour l'automatisation CI/CD
- Voir [TP5 - Sécurité et RBAC](../../tp05/README.md) pour sécuriser l'application
- Voir [TP4 - Monitoring](../../tp04/README.md) pour le monitoring et les logs
