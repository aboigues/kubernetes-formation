# Exercice 11 : Application avec microservices

## Description

Cet exercice déploie une stack de microservices complète :
- **Frontend** (Nginx) : sert le HTML statique et fait proxy vers le backend
- **Backend** (Node.js) : API HTTP simple (bibliothèque standard uniquement)
- **Database** (PostgreSQL) : base de données relationnelle
- **Cache** (Redis) : cache en mémoire

## Fichiers

- `00-namespace.yaml` : Namespace dédié `microservices`
- `01-configmaps.yaml` : Configuration du backend, code du backend, configuration et HTML du frontend
- `02-secrets.yaml` : Identifiants PostgreSQL
- `03-redis.yaml` : Déploiement et Service du cache Redis
- `04-database.yaml` : Déploiement et Service de la base PostgreSQL
- `05-backend.yaml` : Déploiement et Service du backend Node.js
- `06-frontend.yaml` : Déploiement et Service (NodePort) du frontend Nginx

## Déploiement

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-configmaps.yaml
kubectl apply -f 02-secrets.yaml
kubectl apply -f 03-redis.yaml
kubectl apply -f 04-database.yaml
kubectl apply -f 05-backend.yaml
kubectl apply -f 06-frontend.yaml

# Attendre que tout soit prêt
kubectl wait --for=condition=ready pod -l app=cache -n microservices --timeout=120s
kubectl wait --for=condition=ready pod -l app=database -n microservices --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend -n microservices --timeout=120s
kubectl wait --for=condition=ready pod -l app=frontend -n microservices --timeout=120s
```

## Vérification

```bash
kubectl get pods -n microservices
kubectl get svc -n microservices

# Le backend rapporte sa config DB/cache (sans s'y connecter réellement,
# c'est un exercice pédagogique, pas un vrai driver PostgreSQL/Redis) :
kubectl exec -n microservices deploy/backend -- wget -qO- http://localhost:5000/api/health
```

## Accès au frontend

### Avec Minikube

```bash
minikube service frontend -n microservices
```

### Avec Kubeadm

```bash
NODE_PORT=$(kubectl get svc frontend -n microservices -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Frontend accessible à : http://$NODE_IP:$NODE_PORT"
```

Le NodePort par défaut est `30081`.

## Nettoyage

```bash
kubectl delete namespace microservices
```

## Points clés

1. **Ordre de dépendance** : cache et database d'abord, puis backend (un `initContainer` attend les deux avant de démarrer), puis frontend.
2. **ConfigMaps** : configuration non sensible (hôtes, ports) et code applicatif du backend séparés dans `01-configmaps.yaml`.
3. **Secrets** : identifiants PostgreSQL injectés via `envFrom.secretRef`, jamais en clair dans les manifests.
4. **Exposition** : seul le frontend est en NodePort ; backend, database et cache restent en ClusterIP, inaccessibles depuis l'extérieur du cluster.
5. **Persistance** : `database-storage` utilise un `emptyDir` pour rester fidèle à la structure suggérée de l'énoncé — en conditions réelles, remplacez-le par un `PersistentVolumeClaim` (voir l'Exercice 10) pour ne pas perdre les données à chaque redémarrage du pod.

## Sécurité

Chaque Deployment applique la checklist de [`.claude/SECURITY.md`](../../.claude/SECURITY.md) :

| Composant | Image | UID non-root | readOnlyRootFilesystem |
|-----------|-------|:---:|:---:|
| Frontend | `telemachlearning/nginx:1.29-alpine` | 101 | ✅ (volumes emptyDir pour `/var/cache/nginx`, `/var/run`) |
| Backend | `node:24-alpine` | 1000 | ✅ (aucune écriture disque nécessaire) |
| Database | `postgres:17-alpine` | 70 | ✅ (volumes emptyDir pour `/tmp`, `/var/run/postgresql`) |
| Cache | `redis:7.4-alpine` | 999 | ✅ (volumes emptyDir pour `/tmp`, `/data`) |

Tous les containers ont en commun `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` et `seccompProfile: RuntimeDefault`.
