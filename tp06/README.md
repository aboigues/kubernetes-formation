# TP6 - Mise en Production et CI/CD avec Kubernetes

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Déployer et gérer des applications avec Helm
- Configurer des Ingress Controllers pour l'exposition des services
- Mettre en place un pipeline CI/CD avec GitHub Actions
- Implémenter des stratégies de déploiement avancées (Blue-Green, Canary)
- Gérer les environnements (dev, staging, production)
- Appliquer les bonnes pratiques de mise en production
- Automatiser les déploiements Kubernetes
- Utiliser GitOps avec ArgoCD
- Implémenter le versioning et les rollbacks automatiques

## Prérequis

- Avoir complété les TP1 à TP5
- Un cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)
- Connaissance des concepts de base de Kubernetes
- Compte GitHub (pour le CI/CD) **OU** voir l'alternative Tekton ci-dessous

**Note pour kubeadm :** Les outils CI/CD (Tekton, ArgoCD) fonctionnent de manière identique. Pour les registry d'images, référez-vous au [guide kubeadm](../docs/KUBEADM_SETUP.md) pour configurer un registry Docker interne.
- Compréhension de Docker et des conteneurs

> **Note importante** : Si vous ne souhaitez pas créer de compte GitHub, consultez le fichier [ALTERNATIVE_SANS_GITHUB.md](./ALTERNATIVE_SANS_GITHUB.md) qui explique comment mettre en place un pipeline CI/CD complet avec **Tekton**, directement dans votre cluster Kubernetes, sans aucun service externe.

## Choix de votre solution CI/CD

Ce TP propose **deux approches** pour le CI/CD :

### Option 1 : GitHub Actions (recommandé pour la découverte)
- **Avantages** : Interface intuitive, intégration GitHub, gratuit pour usage personnel
- **Inconvénients** : Nécessite un compte GitHub
- **Documentation** : Voir Partie 3 de ce README

### Option 2 : Tekton (recommandé pour l'apprentissage Kubernetes)
- **Avantages** : Kubernetes-native, aucun compte externe, contrôle total
- **Inconvénients** : Plus technique, nécessite plus de configuration
- **Documentation** : Voir [ALTERNATIVE_SANS_GITHUB.md](./ALTERNATIVE_SANS_GITHUB.md)

**Les deux approches couvrent les mêmes fonctionnalités** : tests automatiques, build Docker, scan de sécurité, et déploiement sur Kubernetes.

## Partie 1 : Introduction à Helm

### 1.1 Qu'est-ce que Helm ?

**Helm** est le gestionnaire de packages pour Kubernetes. Il permet de :
- Packager des applications Kubernetes
- Partager des configurations
- Gérer les versions et releases
- Simplifier les déploiements complexes

**Concepts clés** :
- **Chart** : Package Helm (collection de fichiers YAML)
- **Release** : Instance d'un Chart déployé
- **Repository** : Collection de Charts
- **Values** : Configuration paramétrable

### 1.2 Installation de Helm

```bash
# Télécharger et installer Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Vérifier l'installation
helm version

# Ajouter des repositories populaires
helm repo add stable https://charts.helm.sh/stable
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Lister les repositories
helm repo list

# Rechercher des charts
helm search repo nginx
helm search repo wordpress
```

### 1.3 Utiliser un Chart Helm

**Exercice 1 : Déployer une application avec Helm**

```bash
# Chercher le chart WordPress
helm search repo wordpress

# Voir les informations du chart
helm show chart bitnami/wordpress
helm show values bitnami/wordpress

# Installer WordPress
helm install my-wordpress bitnami/wordpress \
  --set wordpressUsername=admin \
  --set wordpressPassword=admin123 \
  --set mariadb.auth.rootPassword=secretpassword

# Lister les releases
helm list

# Voir le status
helm status my-wordpress

# Obtenir les informations de connexion
helm get notes my-wordpress

# Accéder à WordPress
kubectl get svc my-wordpress
minikube service my-wordpress --url
```

**Exercice 2 : Gérer les releases**

```bash
# Voir l'historique
helm history my-wordpress

# Mettre à jour la release
helm upgrade my-wordpress bitnami/wordpress \
  --set replicaCount=2

# Rollback
helm rollback my-wordpress 1

# Désinstaller
helm uninstall my-wordpress

# Vérifier la suppression
helm list
kubectl get all
```

### 1.4 Créer votre propre Chart

**Exercice 3 : Créer un Chart personnalisé**

```bash
# Créer un nouveau chart
helm create my-app

# Structure du chart
tree my-app/
# my-app/
# ├── Chart.yaml          # Métadonnées du chart
# ├── values.yaml         # Valeurs par défaut
# ├── templates/          # Templates Kubernetes
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   ├── ingress.yaml
# │   ├── _helpers.tpl
# │   └── NOTES.txt
# └── charts/             # Dépendances

# Examiner les fichiers
cat my-app/Chart.yaml
cat my-app/values.yaml
```

Modifier `my-app/Chart.yaml` :

```yaml
apiVersion: v2
name: my-app
description: Une application web simple
type: application
version: 0.1.0
appVersion: "1.0"
keywords:
  - web
  - demo
maintainers:
  - name: Your Name
    email: your.email@example.com
```

Modifier `my-app/values.yaml` :

```yaml
replicaCount: 2

image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: "1.25-alpine"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: "nginx"
  annotations: {}
  hosts:
    - host: myapp.local
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}
```

Modifier `my-app/templates/deployment.yaml` (avec configurations de sécurité) :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 101
          capabilities:
            drop:
            - ALL
        ports:
        - name: http
          containerPort: 80
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

> **Note de sécurité** : Ce deployment inclut les bonnes pratiques de sécurité Kubernetes :
> - `runAsNonRoot: true` - Exécution en tant qu'utilisateur non-root (nginx UID 101)
> - `readOnlyRootFilesystem: true` - Système de fichiers racine en lecture seule
> - Volumes `emptyDir` pour les répertoires nécessitant l'écriture (/tmp, /var/cache/nginx, /var/run)
> - `allowPrivilegeEscalation: false` - Pas d'élévation de privilèges
> - `capabilities: drop: ALL` - Suppression de toutes les capabilities Linux
> - `seccompProfile: RuntimeDefault` - Profil Seccomp par défaut

Les autres templates générés par `helm create` sont déjà fonctionnels (`service.yaml`, `ingress.yaml`, `hpa.yaml`, `_helpers.tpl`). Vous pouvez les consulter avec :

```bash
cat my-app/templates/service.yaml
cat my-app/templates/ingress.yaml
cat my-app/templates/hpa.yaml
cat my-app/templates/_helpers.tpl
```

Le fichier `_helpers.tpl` contient les fonctions Helm réutilisables (comme `my-app.fullname`, `my-app.labels`, `my-app.selectorLabels`) utilisées dans les templates.

**Exercice 4 : Déployer votre Chart**

```bash
# Valider le chart
helm lint my-app

# Générer les manifests (dry-run)
helm template my-app ./my-app

# Installer le chart
helm install my-release ./my-app

# Vérifier le déploiement
kubectl get all
helm list

# Mettre à jour avec des valeurs personnalisées
helm upgrade my-release ./my-app \
  --set replicaCount=3 \
  --set image.tag=1.26-alpine

# Créer un fichier de valeurs personnalisées
cat > custom-values.yaml <<EOF
replicaCount: 3
image:
  tag: "1.26-alpine"
resources:
  limits:
    memory: 256Mi
  requests:
    memory: 128Mi
EOF

# Utiliser le fichier de valeurs
helm upgrade my-release ./my-app -f custom-values.yaml

# Packager le chart
helm package my-app
# Crée: my-app-0.1.0.tgz
```

### 1.5 Helm avec plusieurs environnements

Créer `values-dev.yaml` :

```yaml
replicaCount: 1
image:
  tag: "latest"
resources:
  limits:
    memory: 128Mi
  requests:
    memory: 64Mi
```

Créer `values-prod.yaml` :

```yaml
replicaCount: 3
image:
  tag: "1.25-alpine"
resources:
  limits:
    memory: 512Mi
  requests:
    memory: 256Mi
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

```bash
# Déployer en dev
helm install my-app-dev ./my-app -f values-dev.yaml

# Déployer en prod
helm install my-app-prod ./my-app -f values-prod.yaml

# Lister les releases
helm list
```

## Partie 2 : Ingress Controllers

### 2.1 Qu'est-ce qu'un Ingress ?

Un **Ingress** expose les routes HTTP/HTTPS depuis l'extérieur du cluster vers les services internes.

**Avantages** :
- Un seul point d'entrée
- Load balancing
- SSL/TLS termination
- Name-based virtual hosting
- Path-based routing

### 2.2 Installation de NGINX Ingress Controller

```bash
# Activer l'addon ingress dans minikube
minikube addons enable ingress

# Vérifier l'installation
kubectl get pods -n ingress-nginx

# Attendre que le controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Vérifier le service
kubectl get svc -n ingress-nginx
```

### 2.3 Créer un Ingress simple

**Exercice 5 : Déployer une application avec Ingress**

Créer `01-app-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-app-service
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
```

Créer `02-ingress-simple.yaml` :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
```

```bash
# Appliquer
kubectl apply -f 01-app-deployment.yaml
kubectl apply -f 02-ingress-simple.yaml

# Vérifier l'Ingress
kubectl get ingress
kubectl describe ingress web-app-ingress

# Obtenir l'IP de minikube
minikube ip

# Ajouter l'entrée dans /etc/hosts
echo "$(minikube ip) myapp.local" | sudo tee -a /etc/hosts

# Tester
curl http://myapp.local
```

### 2.4 Ingress avec plusieurs services

**Important** : Avant de continuer, supprimez les ressources précédentes pour éviter les conflits d'Ingress sur le même host :

```bash
# Supprimer les ressources de l'exercice précédent
kubectl delete -f 01-app-deployment.yaml
kubectl delete -f 02-ingress-simple.yaml
```

Créer `03-multi-service-ingress.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:latest
        args:
        - "-text=API Response"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-service
spec:
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
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
      - name: frontend
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-service-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

```bash
# Appliquer
kubectl apply -f 03-multi-service-ingress.yaml

# Tester les routes
curl http://myapp.local/
curl http://myapp.local/api
```

### 2.5 Ingress avec TLS/SSL

**Exercice 6 : Configurer HTTPS**

**Important** : Supprimez l'Ingress précédent pour éviter les conflits :

```bash
# Supprimer l'Ingress de l'exercice 2.4
kubectl delete ingress multi-service-ingress
```

```bash
# Créer un certificat auto-signé
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=myapp.local/O=myapp"

# Créer un Secret TLS
kubectl create secret tls myapp-tls \
  --cert=tls.crt \
  --key=tls.key

# Vérifier le secret
kubectl get secret myapp-tls
```

Créer `04-ingress-tls.yaml` :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app-ingress-tls
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.local
    secretName: myapp-tls
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
```

```bash
# Appliquer
kubectl apply -f 04-ingress-tls.yaml

# Tester HTTPS
curl -k https://myapp.local
```

### 2.6 Ingress avancé avec annotations

**Note importante sur la sécurité** : L'annotation `configuration-snippet` est désactivée par défaut dans les versions récentes de NGINX Ingress Controller pour des raisons de sécurité (risque d'injection de configuration). Cette section montre comment utiliser des annotations sûres.

Créer d'abord un ConfigMap pour les headers personnalisés `05-custom-headers.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-headers
  namespace: default
data:
  X-Custom-Header: "MyValue"
  X-Application: "Kubernetes-Demo"
  X-Environment: "Production"
```

Créer `05-ingress-advanced.yaml` :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: advanced-ingress
  annotations:
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    # Sticky sessions
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "route"
    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE"
    # Timeouts
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    # Custom headers (méthode sécurisée)
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Custom-Header: MyValue";
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
```

**Si vous obtenez l'erreur "configuration-snippet annotation cannot be used"**, c'est normal ! Voici deux solutions :

**Solution A : Approche sécurisée recommandée (sans configuration-snippet)**

Supprimez l'annotation `configuration-snippet` et utilisez seulement les annotations sûres :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: advanced-ingress
  annotations:
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    # Sticky sessions
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/session-cookie-name: "route"
    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, DELETE"
    # Timeouts
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-app-service
            port:
              number: 80
```

**Solution B : Activer l'annotation (usage pédagogique uniquement)**

Pour les besoins de formation, vous pouvez activer les snippets dans le controller :

```bash
# Éditer le ConfigMap du controller
kubectl edit configmap -n ingress-nginx ingress-nginx-controller

# Ajouter cette ligne dans la section 'data:'
allow-snippet-annotations: "true"

# Redémarrer le controller
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Attendre que le controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**⚠️ Avertissement** : L'option `allow-snippet-annotations: "true"` **NE DOIT PAS** être utilisée en production car elle représente un risque de sécurité.

## Partie 3 : CI/CD avec GitHub Actions

### 3.1 Introduction au CI/CD

**CI/CD** : Continuous Integration / Continuous Deployment

**Bénéfices** :
- Déploiements automatisés
- Tests automatiques
- Déploiements rapides et fiables
- Rollbacks facilités
- Traçabilité des changements

### 3.2 Structure du projet

```
my-app/
├── .github/
│   └── workflows/
│       ├── ci.yml           # Tests et build
│       └── cd.yml           # Déploiement
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── helm/
│   └── my-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── src/
│   └── app.js
├── Dockerfile
└── README.md
```

### 3.3 Créer un Dockerfile

Créer `Dockerfile` :

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

USER node

CMD ["node", "app.js"]
```

Créer `app.js` :

```javascript
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Kubernetes!',
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV || 'development'
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(port, () => {
  console.log(`App listening on port ${port}`);
});
```

Créer `package.json` :

```json
{
  "name": "my-kubernetes-app",
  "version": "1.0.0",
  "description": "Sample app for Kubernetes deployment",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "test": "echo \"Error: no test specified\" && exit 0"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
```

### 3.4 GitHub Actions - Pipeline CI

Créer `.github/workflows/ci.yml` :

```yaml
name: CI Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Set up Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18'

    - name: Install dependencies
      run: npm ci

    - name: Run tests
      run: npm test

    - name: Lint code
      run: npm run lint || echo "No lint configured"

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - uses: actions/checkout@v3

    - name: Log in to Container Registry
      uses: docker/login-action@v2
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v4
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=semver,pattern={{version}}
          type=sha

    - name: Build and push Docker image
      uses: docker/build-push-action@v4
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}

    - name: Image scan with Trivy
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy results
      uses: github/codeql-action/upload-sarif@v2
      if: always()
      with:
        sarif_file: 'trivy-results.sarif'
```

### 3.5 GitHub Actions - Pipeline CD

Créer `.github/workflows/cd.yml` :

```yaml
name: CD Pipeline

on:
  push:
    branches: [ main ]
    tags:
      - 'v*'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
    - uses: actions/checkout@v3

    - name: Set up kubectl
      uses: azure/setup-kubectl@v3
      with:
        version: 'v1.28.0'

    - name: Configure Kubernetes
      run: |
        mkdir -p ~/.kube
        echo "${{ secrets.KUBE_CONFIG }}" | base64 -d > ~/.kube/config

    - name: Set up Helm
      uses: azure/setup-helm@v3
      with:
        version: 'v3.12.0'

    - name: Deploy with Helm
      run: |
        helm upgrade --install my-app ./helm/my-app \
          --namespace production \
          --create-namespace \
          --set image.repository=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }} \
          --set image.tag=${{ github.sha }} \
          --wait \
          --timeout 5m

    - name: Verify deployment
      run: |
        kubectl rollout status deployment/my-app -n production
        kubectl get pods -n production

    - name: Run smoke tests
      run: |
        kubectl run smoke-test --image=curlimages/curl:latest --rm -i --restart=Never \
          -- curl -f http://my-app-service.production.svc.cluster.local/health

  notify:
    needs: deploy
    runs-on: ubuntu-latest
    if: always()
    steps:
    - name: Send notification
      run: |
        echo "Deployment completed with status: ${{ needs.deploy.result }}"
        # Ajouter ici l'intégration avec Slack, Discord, etc.
```

### 3.6 Secrets Kubernetes dans GitHub

```bash
# Créer un kubeconfig pour GitHub Actions
# Option 1: Utiliser votre kubeconfig existant
cat ~/.kube/config | base64

# Option 2: Créer un ServiceAccount dédié
kubectl create serviceaccount github-actions -n default
kubectl create clusterrolebinding github-actions \
  --clusterrole=cluster-admin \
  --serviceaccount=default:github-actions

# Créer le kubeconfig pour le ServiceAccount
# (voir script ci-dessous)
```

Script pour générer un kubeconfig :

```bash
#!/bin/bash
SERVICE_ACCOUNT=github-actions
NAMESPACE=default
CLUSTER_NAME=$(kubectl config current-context)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

SECRET_NAME=$(kubectl get serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE -o jsonpath='{.secrets[0].name}')
CA=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d)

cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CA}
    server: ${SERVER}
contexts:
- name: ${SERVICE_ACCOUNT}@${CLUSTER_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: ${SERVICE_ACCOUNT}
current-context: ${SERVICE_ACCOUNT}@${CLUSTER_NAME}
users:
- name: ${SERVICE_ACCOUNT}
  user:
    token: ${TOKEN}
EOF
```

**Configurer les secrets GitHub** :
1. Aller dans Settings > Secrets and variables > Actions
2. Ajouter `KUBE_CONFIG` avec le contenu base64 du kubeconfig

## Partie 4 : Stratégies de déploiement

### 4.1 Rolling Update (par défaut)

Déploiement progressif, remplace les pods un par un.

Créer `06-rolling-update.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rolling-app
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Nombre de pods supplémentaires
      maxUnavailable: 1  # Nombre de pods indisponibles
  selector:
    matchLabels:
      app: rolling-app
  template:
    metadata:
      labels:
        app: rolling-app
        version: v1
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Version 1"]
        ports:
        - containerPort: 5678
        readinessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 5
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: rolling-app-service
spec:
  selector:
    app: rolling-app
  ports:
  - port: 80
    targetPort: 5678
```

```bash
# Déployer
kubectl apply -f 06-rolling-update.yaml

# Observer le rollout
kubectl rollout status deployment/rolling-app

# Mettre à jour l'image
kubectl set image deployment/rolling-app app=hashicorp/http-echo:latest --record

# Ou modifier le déploiement
kubectl edit deployment rolling-app
# Changer args: ["-text=Version 2"]

# Observer la mise à jour en direct
watch kubectl get pods

# Voir l'historique
kubectl rollout history deployment/rolling-app

# Rollback
kubectl rollout undo deployment/rolling-app
```

### 4.2 Blue-Green Deployment

Deux environnements identiques, switch instantané.

Créer `07-blue-green.yaml` :

```yaml
# Blue deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Blue Version"]
        ports:
        - containerPort: 5678
---
# Green deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Green Version"]
        ports:
        - containerPort: 5678
---
# Service pointant vers blue
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp
    version: blue  # Changer vers green pour switch
  ports:
  - port: 80
    targetPort: 5678
  type: LoadBalancer
```

**Exercice 7 : Blue-Green Deployment**

```bash
# Déployer blue et green
kubectl apply -f 07-blue-green.yaml

# Tester la version blue
curl http://$(minikube ip):$(kubectl get svc myapp-service -o jsonpath='{.spec.ports[0].nodePort}')

# Switch vers green
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"green"}}}'

# Tester la version green
curl http://$(minikube ip):$(kubectl get svc myapp-service -o jsonpath='{.spec.ports[0].nodePort}')

# Rollback vers blue
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"blue"}}}'
```

### 4.3 Canary Deployment

Déployer progressivement vers un sous-ensemble d'utilisateurs.

Créer `08-canary.yaml` :

```yaml
# Stable version (90%)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Stable Version"]
        ports:
        - containerPort: 5678
---
# Canary version (10%)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Canary Version"]
        ports:
        - containerPort: 5678
---
# Service commun
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp  # Sélectionne stable + canary
  ports:
  - port: 80
    targetPort: 5678
```

```bash
# Déployer
kubectl apply -f 08-canary.yaml

# Tester plusieurs fois (10% canary, 90% stable)
for i in {1..20}; do
  curl http://$(minikube service myapp-service --url)
  sleep 1
done

# Augmenter le canary progressivement
kubectl scale deployment app-canary --replicas=3
kubectl scale deployment app-stable --replicas=7

# Si tout va bien, promouvoir canary
kubectl scale deployment app-canary --replicas=10
kubectl scale deployment app-stable --replicas=0

# Ou rollback en cas de problème
kubectl scale deployment app-canary --replicas=0
```

### 4.4 A/B Testing avec Ingress

Créer `09-ab-testing.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
      version: v1
  template:
    metadata:
      labels:
        app: myapp
        version: v1
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Version 1"]
        ports:
        - containerPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-v2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
      version: v2
  template:
    metadata:
      labels:
        app: myapp
        version: v2
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:latest
        args: ["-text=Version 2 - New Feature"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app-v1-service
spec:
  selector:
    app: myapp
    version: v1
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app-v2-service
spec:
  selector:
    app: myapp
    version: v2
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ab-testing-ingress
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "30"  # 30% vers v2
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-v2-service
            port:
              number: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: main-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-v1-service
            port:
              number: 80
```

## Partie 5 : GitOps avec ArgoCD

### 5.1 Introduction à GitOps

**GitOps** : Git comme source de vérité pour l'infrastructure et les applications.

**Principes** :
- Déclaratif : Infrastructure as Code
- Versionné : Tout dans Git
- Automatique : Déploiements automatiques
- Réconciliation continue : État désiré vs état actuel

### 5.2 Installation d'ArgoCD

```bash
# Créer le namespace
kubectl create namespace argocd

# Installer ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Exposer l'UI ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Récupérer le mot de passe initial
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# Installer le CLI ArgoCD (optionnel)
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login avec le CLI
argocd login localhost:8080 --username admin --insecure
```

### 5.3 Créer une application ArgoCD

**Exercice 8 : Déployer avec ArgoCD**

Structure du repo Git :

```
my-gitops-repo/
├── apps/
│   └── my-app/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── kustomization.yaml
└── README.md
```

Créer `10-argocd-application.yaml` :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/username/my-gitops-repo.git
    targetRevision: HEAD
    path: apps/my-app

  destination:
    server: https://kubernetes.default.svc
    namespace: default

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

```bash
# Créer l'application
kubectl apply -f 10-argocd-application.yaml

# Ou via le CLI
argocd app create my-app \
  --repo https://github.com/username/my-gitops-repo.git \
  --path apps/my-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated

# Voir les applications
argocd app list

# Voir les détails
argocd app get my-app

# Synchroniser manuellement
argocd app sync my-app

# Voir l'historique
argocd app history my-app
```

### 5.4 GitOps avec Helm

Créer `11-argocd-helm-app.yaml` :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-helm-app
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/username/my-gitops-repo.git
    targetRevision: HEAD
    path: helm/my-app
    helm:
      releaseName: my-app
      values: |
        replicaCount: 3
        image:
          tag: "v1.0.0"
        resources:
          limits:
            memory: 256Mi

  destination:
    server: https://kubernetes.default.svc
    namespace: production

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 5.5 Environnements multiples avec ArgoCD

Structure du repo :

```
my-gitops-repo/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   └── patch-deployment.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── patch-deployment.yaml
│   └── production/
│       ├── kustomization.yaml
│       └── patch-deployment.yaml
└── README.md
```

`base/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app: my-app
```

`overlays/dev/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

bases:
- ../../base

patchesStrategicMerge:
- patch-deployment.yaml

commonLabels:
  environment: dev
```

`overlays/dev/patch-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: app
        image: myapp:dev-latest
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```

Créer les applications ArgoCD pour chaque environnement :

```bash
# Dev
argocd app create my-app-dev \
  --repo https://github.com/username/my-gitops-repo.git \
  --path overlays/dev \
  --dest-namespace dev \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated

# Staging
argocd app create my-app-staging \
  --repo https://github.com/username/my-gitops-repo.git \
  --path overlays/staging \
  --dest-namespace staging \
  --dest-server https://kubernetes.default.svc \
  --sync-policy automated

# Production (sync manuel)
argocd app create my-app-prod \
  --repo https://github.com/username/my-gitops-repo.git \
  --path overlays/production \
  --dest-namespace production \
  --dest-server https://kubernetes.default.svc
```

## Partie 6 : Bonnes pratiques de production

### 6.1 Health checks et probes

Créer `12-health-checks.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: production-app
  template:
    metadata:
      labels:
        app: production-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80

        # Startup probe - vérifie le démarrage initial
        startupProbe:
          httpGet:
            path: /health
            port: 80
          failureThreshold: 30
          periodSeconds: 10

        # Liveness probe - redémarre si unhealthy
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        # Readiness probe - retire du load balancing si not ready
        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3

        # Resource limits
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

        # Security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
```

### 6.2 Pod Disruption Budgets

Créer `13-pdb.yaml` :

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2  # Minimum 2 pods doivent rester disponibles
  selector:
    matchLabels:
      app: my-app
---
# Alternative: maxUnavailable
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb-max
spec:
  maxUnavailable: 1  # Maximum 1 pod peut être indisponible
  selector:
    matchLabels:
      app: my-app
```

### 6.3 HorizontalPodAutoscaler

Créer `14-hpa.yaml` :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 4
        periodSeconds: 15
      selectPolicy: Max
```

```bash
# Installer Metrics Server si pas déjà fait
minikube addons enable metrics-server

# Créer le HPA
kubectl apply -f 14-hpa.yaml

# Voir le status
kubectl get hpa
kubectl describe hpa my-app-hpa

# Générer de la charge
kubectl run -it --rm load-generator --image=busybox -- /bin/sh
# while true; do wget -q -O- http://my-app-service; done

# Observer l'autoscaling
watch kubectl get hpa,pods
```

### 6.4 Configuration managée avec Kustomize

Structure :

```
kustomize/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── replica-patch.yaml
    │   └── config-patch.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        └── kustomization.yaml
```

`base/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
- configmap.yaml

commonLabels:
  app: my-app
  managed-by: kustomize

configMapGenerator:
- name: app-config
  literals:
  - LOG_LEVEL=info
  - MAX_CONNECTIONS=100
```

`overlays/production/kustomization.yaml` :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

bases:
- ../../base

replicas:
- name: my-app
  count: 5

images:
- name: my-app
  newTag: v1.2.3

configMapGenerator:
- name: app-config
  behavior: merge
  literals:
  - LOG_LEVEL=warn
  - MAX_CONNECTIONS=500

patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: my-app
  spec:
    template:
      spec:
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

```bash
# Build et voir le résultat
kubectl kustomize overlays/production

# Appliquer directement
kubectl apply -k overlays/production

# Voir les différences
kubectl diff -k overlays/production
```

### 6.5 Secrets management avec Sealed Secrets

```bash
# Installer Sealed Secrets Controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Installer kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Créer un secret normal
kubectl create secret generic my-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > secret.yaml

# Sceller le secret
kubeseal -f secret.yaml -w sealed-secret.yaml

# Le sealed secret peut être commité dans Git
cat sealed-secret.yaml

# Appliquer le sealed secret
kubectl apply -f sealed-secret.yaml

# Le controller va créer le secret déchiffré
kubectl get secret my-secret -o yaml
```

Créer `15-sealed-secret.yaml` :

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-sealed-secret
  namespace: default
spec:
  encryptedData:
    password: AgBqF7V8h+RjT...  # Chiffré
    api-key: AgCUF3G9i+SkU...   # Chiffré
  template:
    metadata:
      name: my-secret
    type: Opaque
```

### 6.6 Backup et Disaster Recovery

**Velero pour les backups**

```bash
# Installer Velero
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xvf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Configurer Velero (exemple avec MinIO local)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000

# Créer un backup
velero backup create my-backup --include-namespaces default

# Lister les backups
velero backup get

# Restaurer depuis un backup
velero restore create --from-backup my-backup

# Backup automatique
velero schedule create daily-backup --schedule="0 2 * * *" --include-namespaces production
```

## Partie 7 : Monitoring en production

### 7.1 Prometheus et Grafana

```bash
# Ajouter le repo Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Installer kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi

# Accéder à Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Credentials par défaut: admin / prom-operator
```

### 7.2 Métriques personnalisées

Créer `16-servicemonitor.yaml` :

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  labels:
    app: my-app
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### 7.3 Alertes Prometheus

Créer `17-prometheus-rules.yaml` :

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: monitoring
spec:
  groups:
  - name: my-app
    interval: 30s
    rules:
    - alert: HighErrorRate
      expr: |
        rate(http_requests_total{status=~"5.."}[5m]) > 0.05
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High error rate detected"
        description: "Error rate is {{ $value }} for {{ $labels.instance }}"

    - alert: PodCrashLooping
      expr: |
        rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod is crash looping"
        description: "Pod {{ $labels.pod }} is restarting frequently"

    - alert: HighMemoryUsage
      expr: |
        container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage"
        description: "Memory usage is above 90% for {{ $labels.pod }}"
```

## Partie 8 : Exercices pratiques finaux

### Exercice Final 1 : Pipeline CI/CD complet

**Objectif** : Créer un pipeline complet de A à Z

**Tâches** :
1. Créer une application Node.js avec tests
2. Écrire un Dockerfile optimisé
3. Créer un Chart Helm
4. Configurer GitHub Actions (CI + CD)
5. Déployer sur 3 environnements (dev, staging, prod)
6. Implémenter un déploiement Canary
7. Configurer le monitoring et les alertes

### Exercice Final 2 : GitOps avec ArgoCD

**Objectif** : Implémenter GitOps

**Tâches** :
1. Installer ArgoCD
2. Créer un repository GitOps
3. Structurer avec Kustomize (base + overlays)
4. Créer des applications ArgoCD pour chaque environnement
5. Tester la synchronisation automatique
6. Implémenter un rollback

### Exercice Final 3 : Production-ready deployment

**Objectif** : Déployer une application production-ready

**Requirements** :
- HPA configuré
- Pod Disruption Budget
- Resource limits
- Probes (liveness, readiness, startup)
- Network Policies
- Security Context
- Sealed Secrets
- Ingress avec TLS
- Monitoring avec ServiceMonitor
- Alertes configurées

## Partie 9 : Nettoyage

```bash
# Supprimer les déploiements de test
kubectl delete deployment --all
kubectl delete service --all
kubectl delete ingress --all

# Supprimer ArgoCD
kubectl delete namespace argocd

# Supprimer Prometheus
helm uninstall prometheus -n monitoring
kubectl delete namespace monitoring

# Supprimer Sealed Secrets
kubectl delete -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Désactiver les addons
minikube addons disable ingress
minikube addons disable metrics-server

# Supprimer tout
minikube delete
```

## Résumé

Dans ce TP, vous avez appris à :

- **Helm** : Gérer des applications avec des Charts
- **Ingress** : Exposer des services avec routing avancé
- **CI/CD** : Automatiser les déploiements avec GitHub Actions ou Tekton
- **Stratégies de déploiement** : Rolling, Blue-Green, Canary
- **GitOps** : Déployer avec ArgoCD
- **Production** : HPA, PDB, health checks, monitoring
- **Secrets** : Sealed Secrets pour Git
- **Kustomize** : Gérer plusieurs environnements

> **Alternative sans compte GitHub** : Voir [ALTERNATIVE_SANS_GITHUB.md](./ALTERNATIVE_SANS_GITHUB.md) pour utiliser Tekton au lieu de GitHub Actions.

### Concepts clés

- **Helm** : Package manager pour Kubernetes
- **Chart** : Package Helm contenant les ressources K8s
- **Ingress** : Routage HTTP/HTTPS vers les services
- **CI/CD** : Automatisation des tests et déploiements
- **GitOps** : Git comme source de vérité
- **ArgoCD** : Outil de déploiement continu GitOps
- **Canary** : Déploiement progressif avec une petite portion de trafic
- **Blue-Green** : Deux environnements, switch instantané
- **HPA** : Autoscaling horizontal basé sur les métriques
- **PDB** : Budget d'interruption pour la haute disponibilité

## Ressources complémentaires

### Documentation officielle

- [Helm Documentation](https://helm.sh/docs/)
- [Ingress NGINX](https://kubernetes.github.io/ingress-nginx/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Tekton](https://tekton.dev/docs/) - Alternative CI/CD sans compte GitHub
- [Kustomize](https://kustomize.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

### Outils

- **Helm** : Gestionnaire de packages
- **ArgoCD** : GitOps continuous delivery
- **FluxCD** : Alternative GitOps
- **Kustomize** : Template-free customization
- **Sealed Secrets** : Chiffrement de secrets
- **Velero** : Backup et restore
- **Trivy** : Scanner de vulnérabilités
- **Kubeseal** : CLI pour Sealed Secrets

### CI/CD

- **GitHub Actions** : CI/CD natif GitHub
- **GitLab CI** : CI/CD GitLab
- **Jenkins X** : CI/CD cloud-native
- **Tekton** : Framework CI/CD Kubernetes-native
- **Spinnaker** : Continuous delivery multi-cloud

### GitOps

- **ArgoCD** : Continuous delivery déclaratif
- **FluxCD** : GitOps toolkit
- **Jenkins X** : GitOps pour CI/CD

## Prochaines étapes

Félicitations ! Vous maîtrisez maintenant Kubernetes de bout en bout.

**Pour aller plus loin** :
- **Service Mesh** : Istio, Linkerd pour mTLS, observabilité
- **Operators** : Créer vos propres contrôleurs
- **Multi-cluster** : Gérer plusieurs clusters
- **Serverless** : Knative pour serverless sur K8s
- **Platform Engineering** : Construire une plateforme interne

**Certifications** :
- **CKA** : Certified Kubernetes Administrator
- **CKAD** : Certified Kubernetes Application Developer
- **CKS** : Certified Kubernetes Security Specialist

## Questions de révision

1. Qu'est-ce qu'un Chart Helm ?
2. Quelle est la différence entre un Ingress et un Service ?
3. Qu'est-ce que GitOps ?
4. Expliquez la différence entre Blue-Green et Canary
5. Qu'est-ce qu'un HorizontalPodAutoscaler ?
6. Comment fonctionnent les Sealed Secrets ?
7. Quels sont les trois types de probes Kubernetes ?
8. Qu'est-ce qu'un Pod Disruption Budget ?
9. Comment Kustomize diffère-t-il de Helm ?
10. Quel est le rôle d'ArgoCD dans GitOps ?

## Solutions des questions

<details>
<summary>Cliquez pour voir les réponses</summary>

1. **Chart Helm** : Package contenant tous les fichiers YAML nécessaires pour déployer une application sur Kubernetes, avec des valeurs paramétrables.

2. **Ingress vs Service** : Le Service expose des pods au sein du cluster. L'Ingress expose des services HTTP/HTTPS à l'extérieur avec routing, load balancing et TLS.

3. **GitOps** : Pratique où Git est la source de vérité pour l'infrastructure et les applications. Les changements sont appliqués automatiquement depuis Git.

4. **Blue-Green vs Canary** : Blue-Green = deux environnements complets, switch instantané à 100%. Canary = déploiement progressif vers un sous-ensemble croissant d'utilisateurs.

5. **HorizontalPodAutoscaler** : Contrôleur qui ajuste automatiquement le nombre de replicas d'un Deployment/ReplicaSet basé sur des métriques (CPU, mémoire, custom).

6. **Sealed Secrets** : Secrets chiffrés pouvant être stockés dans Git. Le controller les déchiffre dans le cluster pour créer des Secrets Kubernetes normaux.

7. **Trois types de probes** : Liveness (redémarre si fail), Readiness (retire du LB si fail), Startup (attente du démarrage initial).

8. **Pod Disruption Budget** : Limite le nombre de pods pouvant être simultanément indisponibles lors d'évictions volontaires (maintenance, drain).

9. **Kustomize vs Helm** : Kustomize = patches et overlays sans templating. Helm = templating complet avec logique et packaging.

10. **ArgoCD dans GitOps** : Surveille Git, compare l'état désiré avec l'état actuel du cluster, et synchronise automatiquement (reconciliation).

</details>

---

**Durée estimée du TP :** 8-10 heures
**Niveau :** Avancé

**Félicitations ! Vous êtes maintenant prêt à déployer des applications Kubernetes en production !**
