# TP7 - Migration d'applications Docker Compose vers Kubernetes

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Comprendre les différences entre Docker Compose et Kubernetes
- Analyser une stack Docker Compose existante
- Convertir manuellement des services Docker Compose en manifests Kubernetes
- Utiliser Kompose pour automatiser la conversion
- Adapter et optimiser les manifests pour un environnement Kubernetes
- Appliquer les bonnes pratiques de migration

## Prérequis

- Avoir complété le TP1 (Premier déploiement Kubernetes)
- Avoir complété le TP2 (Maîtriser les Manifests Kubernetes)
- Docker et Docker Compose installés
- Un cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)

**Note pour kubeadm :** Cette application microservices fonctionne de manière identique sur kubeadm. Pour l'Ingress, consultez le [guide kubeadm - Partie 11.3](../docs/KUBEADM_SETUP.md#113-ingress-controller-nginx-ingress) pour installer nginx-ingress.
- kubectl configuré
- Connaissances de base en Docker Compose

## Contexte

Docker Compose est un excellent outil pour le développement local, permettant de définir et d'exécuter des applications multi-conteneurs avec un simple fichier YAML. Cependant, en production, Kubernetes offre des fonctionnalités avancées d'orchestration, de scaling, de résilience et de gestion qui vont bien au-delà de ce que Docker Compose peut offrir.

Ce TP vous guide dans le processus de migration d'une application Docker Compose vers Kubernetes, en comprenant les différences conceptuelles et en appliquant les meilleures pratiques.

## Partie 1 : Comprendre les différences

### 1.1 Tableau comparatif

| Aspect | Docker Compose | Kubernetes |
|--------|----------------|------------|
| **Portée** | Machine unique | Cluster multi-nœuds |
| **Orchestration** | Basique | Avancée (self-healing, scheduling) |
| **Scaling** | Manuel | Automatique (HPA) |
| **Load Balancing** | Via réseau Docker | Services natifs avec load balancing |
| **Stockage** | Volumes Docker | PersistentVolumes, StorageClasses |
| **Configuration** | Variables d'environnement | ConfigMaps, Secrets |
| **Réseau** | Réseau bridge/overlay simple | Network Policies, Services, Ingress |
| **Mise à jour** | Recréation complète | Rolling updates, Rollbacks |
| **Haute disponibilité** | Non | Oui (réplicas, health checks) |
| **Monitoring** | Logs Docker basiques | Métriques avancées, Prometheus |

### 1.2 Correspondance des concepts

```
Docker Compose              →    Kubernetes
─────────────────────────────────────────────────
services:                   →    Deployments + Services
  webapp:                   →    Deployment: webapp
    image: nginx            →      spec.containers.image
    ports:                  →    Service: webapp-service
      - "8080:80"          →      ports: 8080 → targetPort: 80
    environment:            →    ConfigMap ou Secret
    volumes:                →    PersistentVolumeClaim
    depends_on:             →    initContainers ou ordre d'application
    restart: always         →    restartPolicy: Always
    deploy.replicas: 3      →    spec.replicas: 3
```

### 1.3 Architecture conceptuelle

**Docker Compose :**
```
┌─────────────────────────────────┐
│      Machine Hôte Docker        │
│                                 │
│  ┌──────────┐   ┌──────────┐  │
│  │Container │   │Container │  │
│  │ Frontend │   │ Backend  │  │
│  └──────────┘   └──────────┘  │
│        │              │         │
│        └──────┬───────┘         │
│           Network                │
│        ┌──────────┐             │
│        │Container │             │
│        │ Database │             │
│        └──────────┘             │
└─────────────────────────────────┘
```

**Kubernetes :**
```
┌──────────────────────────────────────────────┐
│         Cluster Kubernetes                    │
│                                               │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │  Node 1 │  │  Node 2 │  │  Node 3 │     │
│  │         │  │         │  │         │     │
│  │ ┌─────┐ │  │ ┌─────┐ │  │ ┌─────┐ │     │
│  │ │Pod  │ │  │ │Pod  │ │  │ │Pod  │ │     │
│  │ │Front│ │  │ │Back │ │  │ │Back │ │     │
│  │ └─────┘ │  │ └─────┘ │  │ └─────┘ │     │
│  └─────────┘  └─────────┘  └─────────┘     │
│         │            │            │          │
│         └────────────┼────────────┘          │
│                 Services                      │
│              (Load Balancing)                 │
│                      │                        │
│              ┌───────────────┐               │
│              │ PersistentVol │               │
│              │   (Database)  │               │
│              └───────────────┘               │
└──────────────────────────────────────────────┘
```

## Partie 2 : Application exemple avec Docker Compose

### 2.1 Créer l'application exemple

Nous allons travailler avec une application web typique : frontend, backend API, et base de données.

Créer le fichier `docker-compose.yml` :

```yaml
version: '3.8'

services:
  # Frontend web
  frontend:
    image: nginx:1.25-alpine
    ports:
      - "8080:80"
    volumes:
      - ./frontend:/usr/share/nginx/html:ro
    environment:
      - BACKEND_URL=http://backend:5000
    depends_on:
      - backend
    restart: always

  # Backend API
  backend:
    image: python:3.11-slim
    command: python -m http.server 5000
    working_dir: /app
    volumes:
      - ./backend:/app
    environment:
      - DATABASE_HOST=database
      - DATABASE_PORT=5432
      - DATABASE_NAME=myapp
      - DATABASE_USER=admin
      - DATABASE_PASSWORD=secret123
    depends_on:
      - database
    restart: always
    deploy:
      replicas: 2

  # Base de données
  database:
    image: postgres:15-alpine
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=myapp
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=secret123
    restart: always
    ports:
      - "5432:5432"

volumes:
  db-data:
```

### 2.2 Créer les fichiers de l'application

```bash
# Créer la structure
mkdir -p frontend backend

# Frontend simple
cat > frontend/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>My App</title>
</head>
<body>
    <h1>Welcome to My App</h1>
    <p>Frontend running on Nginx</p>
    <script>
        fetch('/api/health')
            .then(r => r.json())
            .then(d => console.log('Backend status:', d));
    </script>
</body>
</html>
EOF

# Backend simple
cat > backend/server.py <<'EOF'
import http.server
import json

class MyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy"}).encode())

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 5000), MyHandler)
    server.serve_forever()
EOF
```

### 2.3 Tester avec Docker Compose

```bash
# Démarrer l'application
docker-compose up -d

# Vérifier les services
docker-compose ps

# Tester l'accès
curl http://localhost:8080

# Voir les logs
docker-compose logs -f

# Arrêter
docker-compose down
```

## Partie 3 : Conversion manuelle vers Kubernetes

### 3.1 Analyser les besoins

Avant de convertir, identifions ce dont nous avons besoin :

1. **Frontend** : Deployment + Service (NodePort pour accès externe)
2. **Backend** : Deployment + Service (ClusterIP pour accès interne)
3. **Database** : StatefulSet + Service (ClusterIP) + PersistentVolumeClaim
4. **Configuration** : ConfigMap pour les variables non sensibles
5. **Secrets** : Secret pour les mots de passe

### 3.2 Créer le namespace

```bash
# Créer un namespace dédié
kubectl create namespace myapp
```

Ou avec un fichier YAML `00-namespace.yaml` :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  labels:
    name: myapp
    environment: development
```

```bash
kubectl apply -f 00-namespace.yaml
```

### 3.3 Créer le Secret pour la base de données

Fichier `01-database-secret.yaml` :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: myapp
type: Opaque
stringData:
  POSTGRES_DB: myapp
  POSTGRES_USER: admin
  POSTGRES_PASSWORD: secret123
  DATABASE_URL: postgresql://admin:secret123@database:5432/myapp
```

```bash
kubectl apply -f 01-database-secret.yaml
```

**Note de sécurité** : En production, utilisez des outils comme Sealed Secrets ou intégrez avec un gestionnaire de secrets (Vault, AWS Secrets Manager, etc.). Voir TP5 pour plus de détails.

### 3.4 Créer le ConfigMap pour le Backend

Fichier `02-backend-config.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: myapp
data:
  DATABASE_HOST: "database"
  DATABASE_PORT: "5432"
  LOG_LEVEL: "info"
  APP_ENV: "development"
```

```bash
kubectl apply -f 02-backend-config.yaml
```

### 3.5 Déployer la base de données

Fichier `03-database-pvc.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
  namespace: myapp
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  # Pour minikube, pas besoin de storageClassName
  # En production, spécifier le storageClassName approprié
```

Fichier `04-database-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: myapp
  labels:
    app: database
    tier: data
spec:
  replicas: 1  # Important : les bases de données ne scalent pas horizontalement facilement
  selector:
    matchLabels:
      app: database
  strategy:
    type: Recreate  # Important pour éviter plusieurs instances accédant au même volume
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
          name: postgres
        envFrom:
        - secretRef:
            name: database-credentials
        volumeMounts:
        - name: database-storage
          mountPath: /var/lib/postgresql/data
          subPath: postgres  # Important pour éviter les problèmes de permissions
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - admin
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - admin
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: database-storage
        persistentVolumeClaim:
          claimName: database-pvc
```

Fichier `05-database-service.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: myapp
  labels:
    app: database
spec:
  type: ClusterIP  # Accès interne uniquement
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgres
  selector:
    app: database
```

Appliquer les manifests :

```bash
kubectl apply -f 03-database-pvc.yaml
kubectl apply -f 04-database-deployment.yaml
kubectl apply -f 05-database-service.yaml

# Vérifier
kubectl get pods -n myapp
kubectl get pvc -n myapp
kubectl get svc -n myapp
```

### 3.6 Déployer le Backend

Fichier `06-backend-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: myapp
  labels:
    app: backend
    tier: api
spec:
  replicas: 2  # Correspond au deploy.replicas dans docker-compose
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: python:3.11-slim
        command:
          - python
          - -m
          - http.server
          - "5000"
        ports:
        - containerPort: 5000
          name: http
        envFrom:
        - configMapRef:
            name: backend-config
        - secretRef:
            name: database-credentials
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
      # Attendre que la base de données soit prête
      initContainers:
      - name: wait-for-db
        image: busybox:1.36
        command:
          - sh
          - -c
          - |
            until nc -z database 5432; do
              echo "Waiting for database..."
              sleep 2
            done
            echo "Database is ready!"
```

Fichier `07-backend-service.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: myapp
  labels:
    app: backend
spec:
  type: ClusterIP  # Accès interne uniquement (depuis le frontend)
  ports:
  - port: 5000
    targetPort: 5000
    protocol: TCP
    name: http
  selector:
    app: backend
```

Appliquer :

```bash
kubectl apply -f 06-backend-deployment.yaml
kubectl apply -f 07-backend-service.yaml

# Vérifier
kubectl get pods -n myapp -l app=backend
kubectl logs -n myapp -l app=backend --tail=20
```

### 3.7 Déployer le Frontend

D'abord, créons un ConfigMap pour le contenu HTML :

Fichier `08-frontend-config.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-html
  namespace: myapp
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>My App on Kubernetes</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 50px; }
            .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
            .healthy { background-color: #d4edda; color: #155724; }
            .error { background-color: #f8d7da; color: #721c24; }
        </style>
    </head>
    <body>
        <h1>Welcome to My App on Kubernetes</h1>
        <p>Frontend running on Nginx in a Kubernetes cluster</p>
        <div id="status" class="status">Checking backend status...</div>
        <script>
            fetch('http://backend:5000/api/health')
                .then(r => r.json())
                .then(d => {
                    document.getElementById('status').className = 'status healthy';
                    document.getElementById('status').textContent = 'Backend is ' + d.status;
                })
                .catch(e => {
                    document.getElementById('status').className = 'status error';
                    document.getElementById('status').textContent = 'Backend error: ' + e;
                });
        </script>
    </body>
    </html>
```

Fichier `09-frontend-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: myapp
  labels:
    app: frontend
    tier: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
          readOnly: true
        env:
        - name: BACKEND_URL
          value: "http://backend:5000"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: html
        configMap:
          name: frontend-html
```

Fichier `10-frontend-service.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: myapp
  labels:
    app: frontend
spec:
  type: NodePort  # Accès externe via minikube
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080  # Port fixe pour faciliter l'accès
    protocol: TCP
    name: http
  selector:
    app: frontend
```

Appliquer :

```bash
kubectl apply -f 08-frontend-config.yaml
kubectl apply -f 09-frontend-deployment.yaml
kubectl apply -f 10-frontend-service.yaml

# Vérifier
kubectl get all -n myapp
```

### 3.8 Tester l'application

```bash
# Obtenir l'URL du frontend
minikube service frontend -n myapp --url

# Ou accéder directement
curl http://$(minikube ip):30080

# Vérifier les logs de tous les composants
kubectl logs -n myapp -l tier=web --tail=10
kubectl logs -n myapp -l tier=api --tail=10
kubectl logs -n myapp -l tier=data --tail=10
```

## Partie 4 : Utilisation de Kompose

### 4.1 Installation de Kompose

Kompose est un outil de conversion de fichiers Docker Compose vers des manifests Kubernetes.

```bash
# Télécharger Kompose
curl -L https://github.com/kubernetes/kompose/releases/download/v1.31.2/kompose-linux-amd64 -o kompose

# Rendre exécutable
chmod +x kompose

# Déplacer vers /usr/local/bin
sudo mv kompose /usr/local/bin/

# Vérifier l'installation
kompose version
```

### 4.2 Conversion automatique

```bash
# Se placer dans le répertoire contenant docker-compose.yml
cd /path/to/your/docker-compose

# Convertir vers Kubernetes
kompose convert

# Ou spécifier un répertoire de sortie
kompose convert -o kubernetes-manifests/

# Voir les fichiers générés
ls -la kubernetes-manifests/
```

**Fichiers générés par Kompose :**
- `frontend-deployment.yaml`
- `frontend-service.yaml`
- `backend-deployment.yaml`
- `backend-service.yaml`
- `database-deployment.yaml`
- `database-service.yaml`
- `db-data-persistentvolumeclaim.yaml`

### 4.3 Examiner les manifests générés

```bash
# Voir le déploiement frontend généré
cat kubernetes-manifests/frontend-deployment.yaml

# Comparer avec notre version manuelle
diff 09-frontend-deployment.yaml kubernetes-manifests/frontend-deployment.yaml
```

### 4.4 Avantages et limitations de Kompose

**Avantages :**
- Conversion rapide pour démarrer
- Bonne base de travail
- Supporte la plupart des directives Docker Compose
- Génère des manifests valides

**Limitations :**
- Ne gère pas les optimisations Kubernetes (resource limits, probes, etc.)
- Les volumes nécessitent souvent des ajustements
- Pas de gestion avancée des Secrets et ConfigMaps
- Ne crée pas d'initContainers pour les dépendances
- Labels et annotations basiques

**Recommandation :** Utilisez Kompose pour la conversion initiale, puis optimisez manuellement les manifests.

## Partie 5 : Adaptation et optimisation pour Kubernetes

### 5.1 Ajouter des health checks

Les probes sont essentielles pour la haute disponibilité :

```yaml
# Liveness probe : redémarre le conteneur si échec
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

# Readiness probe : retire du load balancing si échec
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2

# Startup probe : pour applications avec démarrage lent
startupProbe:
  httpGet:
    path: /startup
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 30  # 30 * 10 = 5 minutes max
```

### 5.2 Définir les ressources

Toujours définir les requests et limits :

```yaml
resources:
  requests:
    memory: "256Mi"  # Minimum garanti
    cpu: "250m"      # 0.25 CPU core
  limits:
    memory: "512Mi"  # Maximum autorisé
    cpu: "500m"      # 0.5 CPU core
```

**Bonnes pratiques :**
- **requests** : ressources garanties, utilisées pour le scheduling
- **limits** : ressources maximales, protègent contre les fuites mémoire
- Commencer conservateur et ajuster avec le monitoring
- CPU : throttling si limite atteinte
- Memory : pod tué (OOMKilled) si limite dépassée

### 5.3 Gérer les dépendances de démarrage

Docker Compose `depends_on` ne garantit pas que le service est prêt. En Kubernetes, utilisez `initContainers` :

```yaml
spec:
  initContainers:
  - name: wait-for-database
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        until nc -z database 5432; do
          echo "Waiting for database to be ready..."
          sleep 2
        done
        echo "Database is ready!"

  - name: wait-for-backend
    image: curlimages/curl:8.5.0
    command:
      - sh
      - -c
      - |
        until curl -f http://backend:5000/health; do
          echo "Waiting for backend to be healthy..."
          sleep 2
        done
        echo "Backend is healthy!"

  containers:
  - name: frontend
    # ... configuration du conteneur principal
```

### 5.4 Utiliser des labels et annotations

Les labels permettent l'organisation et la sélection :

```yaml
metadata:
  name: backend
  labels:
    app: myapp                    # Nom de l'application
    component: backend            # Composant spécifique
    tier: api                     # Couche architecture
    version: "1.0.0"             # Version de l'application
    environment: production       # Environnement
    managed-by: kubectl          # Outil de gestion
  annotations:
    description: "Backend API service"
    team: "backend-team"
    repository: "https://github.com/org/backend"
    documentation: "https://docs.example.com/backend"
```

### 5.5 Implémenter des stratégies de déploiement

**Rolling Update (par défaut) :**

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Nombre max de pods au-dessus de replicas pendant update
      maxUnavailable: 1  # Nombre max de pods indisponibles pendant update
```

**Recreate (pour databases ou lorsque deux versions ne peuvent coexister) :**

```yaml
spec:
  strategy:
    type: Recreate  # Supprime tous les pods avant de créer les nouveaux
```

### 5.6 Configurer l'auto-scaling

Fichier `11-backend-hpa.yaml` :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
  namespace: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale si CPU > 70%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Scale si Memory > 80%
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Attendre 5min avant de descaler
      policies:
      - type: Percent
        value: 50               # Réduire de 50% max à la fois
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100              # Doubler si nécessaire
        periodSeconds: 30
      - type: Pods
        value: 4                # Ou ajouter 4 pods max
        periodSeconds: 30
      selectPolicy: Max         # Prendre la politique la plus agressive
```

Prérequis pour HPA :

```bash
# Activer metrics-server sur minikube
minikube addons enable metrics-server

# Appliquer le HPA
kubectl apply -f 11-backend-hpa.yaml

# Vérifier
kubectl get hpa -n myapp
kubectl describe hpa backend-hpa -n myapp
```

### 5.7 Ajouter des Network Policies

Pour sécuriser les communications entre services :

Fichier `12-network-policies.yaml` :

```yaml
# Politique pour le frontend : peut communiquer avec le backend uniquement
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-netpol
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  # Autoriser DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Autoriser communication avec backend
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 5000

---
# Politique pour le backend : peut communiquer avec la database uniquement
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-netpol
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Accepter connexions depuis frontend
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 5000
  egress:
  # Autoriser DNS
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
  # Autoriser communication avec database
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432

---
# Politique pour la database : accepte uniquement depuis backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-netpol
  namespace: myapp
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  # Accepter connexions depuis backend uniquement
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 5432
```

**Note :** Les Network Policies nécessitent un plugin réseau compatible (Calico, Cilium, Weave). Sur minikube, activer avec `minikube start --cni=calico`.

## Partie 6 : Tests et validation

### 6.1 Vérifications de base

```bash
# Vérifier tous les pods sont Running
kubectl get pods -n myapp
kubectl get pods -n myapp -o wide

# Vérifier les services
kubectl get svc -n myapp

# Vérifier les PVC
kubectl get pvc -n myapp

# Vue d'ensemble
kubectl get all -n myapp
```

### 6.2 Tester la connectivité inter-services

```bash
# Tester depuis le frontend vers le backend
kubectl exec -n myapp -it deployment/frontend -- wget -qO- http://backend:5000

# Tester depuis le backend vers la database
kubectl exec -n myapp -it deployment/backend -- nc -zv database 5432

# Tester la résolution DNS
kubectl exec -n myapp -it deployment/backend -- nslookup database
```

### 6.3 Tester les health checks

```bash
# Voir les events liés aux probes
kubectl get events -n myapp --sort-by='.lastTimestamp' | grep -i probe

# Forcer un échec de liveness probe et observer le restart
kubectl exec -n myapp deployment/backend -- killall python

# Observer les restarts
kubectl get pods -n myapp -w
```

### 6.4 Tester le scaling

```bash
# Scaler manuellement
kubectl scale deployment backend -n myapp --replicas=5

# Vérifier
kubectl get pods -n myapp -l app=backend

# Tester l'auto-scaling (si HPA configuré)
# Générer de la charge
kubectl run -n myapp load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://backend:5000; done"

# Observer le scaling
kubectl get hpa -n myapp -w

# Nettoyer
kubectl delete pod load-generator -n myapp
```

### 6.5 Tester la résilience

```bash
# Supprimer un pod et observer la récréation automatique
POD_NAME=$(kubectl get pods -n myapp -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n myapp $POD_NAME

# Observer la création d'un nouveau pod
kubectl get pods -n myapp -l app=backend -w

# Tester le rolling update
kubectl set image deployment/backend -n myapp backend=python:3.12-slim

# Suivre le rollout
kubectl rollout status deployment/backend -n myapp

# Revenir en arrière si problème
kubectl rollout undo deployment/backend -n myapp
```

### 6.6 Valider la persistance des données

```bash
# Écrire des données dans la database
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "CREATE TABLE test (id serial, data text);"
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "INSERT INTO test (data) VALUES ('persistent data');"

# Vérifier les données
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "SELECT * FROM test;"

# Supprimer le pod database
kubectl delete pod -n myapp -l app=database

# Attendre que le nouveau pod soit prêt
kubectl wait --for=condition=ready pod -n myapp -l app=database --timeout=60s

# Vérifier que les données sont toujours là
kubectl exec -n myapp -it deployment/database -- psql -U admin -d myapp -c "SELECT * FROM test;"
```

## Partie 7 : Bonnes pratiques de migration

### 7.1 Checklist de migration

**Avant la migration :**

- [ ] Analyser l'architecture Docker Compose
- [ ] Identifier les services stateful vs stateless
- [ ] Lister toutes les dépendances entre services
- [ ] Documenter les volumes et leur contenu
- [ ] Noter toutes les variables d'environnement
- [ ] Vérifier les ports exposés
- [ ] Comprendre les contraintes de réseau

**Pendant la migration :**

- [ ] Créer un namespace dédié
- [ ] Convertir les secrets en Secret Kubernetes
- [ ] Convertir les variables en ConfigMap
- [ ] Créer les PVC pour les volumes
- [ ] Ajouter des health checks (liveness, readiness)
- [ ] Définir les resource requests et limits
- [ ] Configurer les stratégies de déploiement
- [ ] Gérer les dépendances avec initContainers
- [ ] Ajouter des labels significatifs
- [ ] Implémenter les Network Policies

**Après la migration :**

- [ ] Tester toutes les fonctionnalités
- [ ] Valider la persistance des données
- [ ] Vérifier les logs de tous les composants
- [ ] Tester la résilience (suppression de pods)
- [ ] Tester le scaling
- [ ] Configurer le monitoring
- [ ] Documenter l'architecture Kubernetes
- [ ] Former l'équipe aux opérations Kubernetes

### 7.2 Différences importantes à gérer

**1. Réseau**

```
Docker Compose                      Kubernetes
─────────────────────────────────────────────────────────────
Réseau bridge automatique       →   Services avec selectors
DNS automatique (nom service)   →   DNS Kubernetes (service.namespace)
Liens entre conteneurs          →   Network Policies
```

**2. Volumes**

```
Docker Compose                      Kubernetes
─────────────────────────────────────────────────────────────
Volumes nommés                  →   PersistentVolumeClaim
Bind mounts                     →   ConfigMap ou hostPath
Volumes anonymes                →   emptyDir
```

**3. Variables d'environnement**

```
Docker Compose                      Kubernetes
─────────────────────────────────────────────────────────────
environment: KEY=value          →   ConfigMap ou Secret
env_file: .env                  →   ConfigMap from-file
```

**4. Ports**

```
Docker Compose                      Kubernetes
─────────────────────────────────────────────────────────────
ports: "8080:80"               →   Service NodePort ou LoadBalancer
expose: 3000                    →   Service ClusterIP (interne)
```

### 7.3 Stratégies de migration progressive

**Option 1 : Big Bang (tout migrer d'un coup)**
- Adapté pour petites applications
- Nécessite une période de maintenance
- Plus risqué mais plus rapide

**Option 2 : Service par service**
1. Migrer d'abord les services stateless (frontend, API)
2. Puis les services stateful (databases)
3. Utiliser des URL/DNS mixtes pendant la transition
4. Moins risqué, permet des tests progressifs

**Option 3 : Blue-Green**
1. Déployer toute la stack sur Kubernetes (environnement Green)
2. Tester complètement le nouvel environnement
3. Basculer le trafic DNS vers Kubernetes
4. Garder Docker Compose en backup (environnement Blue)
5. Désactiver après validation

### 7.4 Outils complémentaires

**Pour la migration :**
- **Kompose** : Conversion Docker Compose → Kubernetes
- **Helm** : Package manager pour Kubernetes
- **Kustomize** : Gestion de configuration multi-environnements

**Pour le développement :**
- **Skaffold** : Workflow de développement automatisé
- **Tilt** : Environnement de dev local avec hot-reload
- **Telepresence** : Développement local avec connexion au cluster

**Pour le déploiement :**
- **ArgoCD** : GitOps pour Kubernetes
- **FluxCD** : Alternative à ArgoCD
- **Spinnaker** : Plateforme de déploiement continue

### 7.5 Monitoring et observabilité

Après la migration, mettez en place :

```bash
# Metrics Server (pour HPA)
minikube addons enable metrics-server

# Prometheus + Grafana (monitoring)
# Voir TP4 pour l'installation complète

# Logs centralisés
# Option 1: EFK Stack (Elasticsearch, Fluentd, Kibana)
# Option 2: ELK Stack (Elasticsearch, Logstash, Kibana)
# Option 3: Loki + Grafana
```

## Partie 8 : Exercices pratiques

### Exercice 1 : Migration d'une application WordPress

Migrer cette stack Docker Compose vers Kubernetes :

```yaml
version: '3.8'
services:
  wordpress:
    image: wordpress:latest
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: mysql
      WORDPRESS_DB_USER: wpuser
      WORDPRESS_DB_PASSWORD: wppass
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wp-content:/var/www/html/wp-content
    depends_on:
      - mysql

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wpuser
      MYSQL_PASSWORD: wppass
      MYSQL_ROOT_PASSWORD: rootpass
    volumes:
      - mysql-data:/var/lib/mysql

volumes:
  wp-content:
  mysql-data:
```

**Tâches :**
1. Créer les Secrets pour les credentials
2. Créer les PVC pour les volumes
3. Déployer MySQL avec StatefulSet (ou Deployment + Recreate)
4. Déployer WordPress avec Deployment
5. Créer les Services appropriés
6. Tester l'accès et la persistance

### Exercice 2 : Migration avec Redis Cache

Ajouter un cache Redis à l'application myapp :

```yaml
# Ajouter dans docker-compose.yml
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass redispass
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
```

**Tâches :**
1. Créer le Secret pour le mot de passe Redis
2. Créer le Deployment Redis avec PVC
3. Créer le Service ClusterIP pour Redis
4. Modifier le backend pour utiliser Redis (env var)
5. Ajouter une Network Policy pour Redis
6. Tester la connectivité depuis le backend

### Exercice 3 : Multi-environnements avec Kustomize

Créer une structure pour gérer dev, staging et production :

```
kubernetes/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── replica-patch.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
```

**Tâches :**
1. Créer la base commune
2. Créer des overlays pour chaque environnement
3. Ajuster les réplicas : dev=1, staging=2, prod=5
4. Ajuster les ressources par environnement
5. Déployer dans différents namespaces

## Partie 9 : Nettoyage

```bash
# Supprimer toutes les ressources du namespace
kubectl delete namespace myapp

# Ou supprimer ressource par ressource
kubectl delete -f 00-namespace.yaml
kubectl delete -f 01-database-secret.yaml
kubectl delete -f 02-backend-config.yaml
kubectl delete -f 03-database-pvc.yaml
kubectl delete -f 04-database-deployment.yaml
kubectl delete -f 05-database-service.yaml
kubectl delete -f 06-backend-deployment.yaml
kubectl delete -f 07-backend-service.yaml
kubectl delete -f 08-frontend-config.yaml
kubectl delete -f 09-frontend-deployment.yaml
kubectl delete -f 10-frontend-service.yaml
kubectl delete -f 11-backend-hpa.yaml
kubectl delete -f 12-network-policies.yaml

# Nettoyer le stockage
kubectl get pv
kubectl delete pv <pv-name>  # Si nécessaire
```

## Solutions des exercices

<details>
<summary>Solution Exercice 1 - WordPress</summary>

Fichier `wordpress-secret.yaml` :
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-secrets
  namespace: wordpress
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: rootpass
  MYSQL_PASSWORD: wppass
  MYSQL_USER: wpuser
  MYSQL_DATABASE: wordpress
```

Fichier `mysql-pvc.yaml` :
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

Fichier `wordpress-pvc.yaml` :
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pvc
  namespace: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Fichier `mysql-deployment.yaml` :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        envFrom:
        - secretRef:
            name: wordpress-secrets
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
          subPath: mysql
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: wordpress
spec:
  type: ClusterIP
  ports:
  - port: 3306
  selector:
    app: mysql
```

Fichier `wordpress-deployment.yaml` :
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - name: wordpress
        image: wordpress:latest
        ports:
        - containerPort: 80
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: wordpress-secrets
              key: MYSQL_USER
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: wordpress-secrets
              key: MYSQL_PASSWORD
        - name: WORDPRESS_DB_NAME
          valueFrom:
            secretKeyRef:
              name: wordpress-secrets
              key: MYSQL_DATABASE
        volumeMounts:
        - name: wordpress-storage
          mountPath: /var/www/html/wp-content
      volumes:
      - name: wordpress-storage
        persistentVolumeClaim:
          claimName: wordpress-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: wordpress
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30808
  selector:
    app: wordpress
```

Déploiement :
```bash
kubectl create namespace wordpress
kubectl apply -f wordpress-secret.yaml
kubectl apply -f mysql-pvc.yaml
kubectl apply -f wordpress-pvc.yaml
kubectl apply -f mysql-deployment.yaml
kubectl apply -f wordpress-deployment.yaml

# Accéder
minikube service wordpress -n wordpress
```
</details>

## Ressources complémentaires

### Documentation
- [Kompose - Conversion Docker Compose vers K8s](https://kompose.io/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [12 Factor App](https://12factor.net/)
- [Guide de migration Docker → Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/)

### Outils
- [Kompose](https://github.com/kubernetes/kompose) - Conversion automatique
- [Helm](https://helm.sh/) - Package manager Kubernetes
- [Kustomize](https://kustomize.io/) - Gestion de configuration
- [Skaffold](https://skaffold.dev/) - Workflow de développement
- [Lens](https://k8slens.dev/) - IDE Kubernetes

### Tutoriels
- [From Docker Compose to Kubernetes](https://kubernetes.io/blog/2018/07/23/from-docker-compose-to-kubernetes-with-kompose/)
- [Kubernetes Patterns](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/)

## Points clés à retenir

1. **Docker Compose ≠ Kubernetes** : Ce sont des outils avec des objectifs différents
2. **Kompose** aide à démarrer mais nécessite des ajustements manuels
3. **Health checks** sont essentiels en Kubernetes (liveness, readiness, startup)
4. **Resources** (requests/limits) doivent toujours être définis
5. **Secrets** pour les données sensibles, **ConfigMap** pour la configuration
6. **PersistentVolumes** pour la persistance, pas les volumes Docker
7. **InitContainers** pour gérer les dépendances de démarrage
8. **Labels** et **annotations** pour l'organisation et les métadonnées
9. **Services** pour la découverte de services et le load balancing
10. **Network Policies** pour la sécurité réseau entre composants

## Conclusion

La migration de Docker Compose vers Kubernetes nécessite plus qu'une simple conversion de fichiers. C'est l'occasion de repenser l'architecture de votre application pour tirer parti des fonctionnalités avancées de Kubernetes : haute disponibilité, scaling automatique, rolling updates, self-healing, etc.

Prenez le temps de :
- Comprendre les différences conceptuelles
- Ajouter des health checks robustes
- Définir des ressources appropriées
- Sécuriser avec Network Policies
- Tester la résilience et la persistance
- Documenter l'architecture

Avec ces bases, vous êtes prêt à déployer et gérer vos applications conteneurisées sur Kubernetes en production !

---

**Prochain TP recommandé :** [TP6 - Mise en Production et CI/CD](../tp06/README.md) pour automatiser les déploiements avec GitOps et ArgoCD.
