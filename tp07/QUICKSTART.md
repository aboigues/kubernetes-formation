# Guide de démarrage rapide - TP7

Ce guide vous permet de tester rapidement la migration Docker Compose → Kubernetes.

## Prérequis

```bash
# Vérifier que minikube est démarré
minikube status

# Si non démarré
minikube start

# Activer metrics-server (optionnel, pour HPA)
minikube addons enable metrics-server
```

## Option 1 : Test avec Docker Compose (avant migration)

```bash
# Se placer dans le répertoire docker-compose
cd tp7/docker-compose-app

# Démarrer l'application
docker-compose up -d

# Vérifier que tout fonctionne
docker-compose ps
curl http://localhost:8080

# Voir les logs
docker-compose logs -f

# Arrêter
docker-compose down
```

## Option 2 : Déploiement sur Kubernetes (après migration)

```bash
# Se placer dans le répertoire des manifests
cd tp7/kubernetes-manifests

# Déployer l'application complète
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

# Attendre que tous les pods soient prêts (peut prendre 1-2 minutes)
kubectl wait --for=condition=ready pod -n myapp --all --timeout=300s

# Vérifier le déploiement
kubectl get all -n myapp

# Accéder à l'application
minikube service frontend -n myapp

# Ou obtenir l'URL
echo "Application disponible sur: http://$(minikube ip):30080"
```

## Tests rapides

```bash
# Vérifier les pods
kubectl get pods -n myapp

# Tester la connexion backend
kubectl exec -n myapp deployment/frontend -- wget -qO- http://backend:5000/api/health

# Voir les logs du backend
kubectl logs -n myapp -l app=backend --tail=20

# Scaler le backend
kubectl scale deployment backend -n myapp --replicas=5

# Observer les pods
kubectl get pods -n myapp -w
```

## Nettoyage

```bash
# Supprimer l'application
kubectl delete namespace myapp
```

## Commande unique pour tout déployer

```bash
# Depuis le répertoire tp7/
kubectl apply -f kubernetes-manifests/00-namespace.yaml && \
kubectl apply -f kubernetes-manifests/01-database-secret.yaml && \
kubectl apply -f kubernetes-manifests/02-backend-config.yaml && \
kubectl apply -f kubernetes-manifests/03-database-pvc.yaml && \
kubectl apply -f kubernetes-manifests/04-database-deployment.yaml && \
kubectl apply -f kubernetes-manifests/05-database-service.yaml && \
kubectl apply -f kubernetes-manifests/06-backend-code.yaml && \
kubectl apply -f kubernetes-manifests/06-backend-deployment.yaml && \
kubectl apply -f kubernetes-manifests/07-backend-service.yaml && \
kubectl apply -f kubernetes-manifests/08-frontend-nginx-config.yaml && \
kubectl apply -f kubernetes-manifests/08-frontend-config.yaml && \
kubectl apply -f kubernetes-manifests/09-frontend-deployment.yaml && \
kubectl apply -f kubernetes-manifests/10-frontend-service.yaml && \
echo "Déploiement terminé! Accédez à http://$(minikube ip):30080"
```

## Troubleshooting rapide

### Pods ne démarrent pas

```bash
kubectl describe pod <pod-name> -n myapp
kubectl logs <pod-name> -n myapp
```

### Service non accessible

```bash
# Vérifier les services
kubectl get svc -n myapp

# Port-forward comme solution temporaire
kubectl port-forward -n myapp svc/frontend 8080:80
# Puis accéder à http://localhost:8080
```

### Voir tous les événements

```bash
kubectl get events -n myapp --sort-by='.lastTimestamp'
```

## Prochaines étapes

Une fois l'application déployée avec succès, consultez le [README complet du TP7](README.md) pour :
- Comprendre les différences entre Docker Compose et Kubernetes
- Apprendre à utiliser Kompose pour la conversion automatique
- Optimiser les manifests avec health checks, resources, HPA
- Sécuriser avec Network Policies
- Implémenter des stratégies de déploiement avancées
