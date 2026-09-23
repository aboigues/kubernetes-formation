# Cycle de Vie des Applications Kubernetes en Environnement Sécurisé

## Introduction

Ce document décrit les phases du cycle de vie d'une application Kubernetes en environnement sécurisé, de la conception au décommissionnement, avec un focus sur les outils et pratiques adaptés aux contraintes de sécurité.

## 🔄 Vue d'ensemble du Cycle de Vie

```
┌─────────────────────────────────────────────────────────────┐
│                 Application Lifecycle                        │
└─────────────────────────────────────────────────────────────┘

  1. DESIGN          2. BUILD          3. TEST
┌──────────┐      ┌──────────┐      ┌──────────┐
│ Manifests│      │ Container│      │ Security │
│ Design   │─────▶│ Build    │─────▶│ Scan     │
│ IaC      │      │ CI/CD    │      │ Testing  │
└──────────┘      └──────────┘      └──────────┘
      │                  │                  │
      │                  │                  │
      ▼                  ▼                  ▼

  4. DEPLOY        5. OPERATE        6. MONITOR
┌──────────┐      ┌──────────┐      ┌──────────┐
│ GitOps   │      │ Scaling  │      │ Metrics  │
│ ArgoCD   │─────▶│ Updates  │─────▶│ Logging  │
│ Helm     │      │ Rollback │      │ Alerts   │
└──────────┘      └──────────┘      └──────────┘
      │                  │                  │
      │                  │                  │
      ▼                  ▼                  ▼

  7. OPTIMIZE      8. RETIRE
┌──────────┐      ┌──────────┐
│ Performance     │ Graceful │
│ Costs    │      │ Shutdown │
│ Security │      │ Archive  │
└──────────┘      └──────────┘
      │                  │
      │                  │
      └──────────────────┘
             │
             ▼
      Back to DESIGN (next version)
```

## 1️⃣ Phase de Design

### Infrastructure as Code (IaC)

En environnement sécurisé, **tout doit être codifié** et versionné.

#### Structure Recommandée

```
app-project/
├── k8s/
│   ├── base/                      # Configuration de base
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml.enc        # Secrets chiffrés
│   │   └── kustomization.yaml
│   ├── overlays/
│   │   ├── dev/                   # Environnement dev
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   ├── staging/               # Environnement staging
│   │   │   ├── kustomization.yaml
│   │   │   └── patches/
│   │   └── production/            # Environnement production
│   │       ├── kustomization.yaml
│   │       ├── patches/
│   │       └── secrets.enc.yaml   # Secrets spécifiques prod
│   └── charts/                    # Helm charts alternatif
│       └── myapp/
│           ├── Chart.yaml
│           ├── values.yaml
│           ├── values-prod.yaml
│           └── templates/
├── .gitops/                       # Configuration GitOps
│   └── argocd/
│       ├── application.yaml
│       └── project.yaml
└── docs/
    ├── architecture.md
    └── runbook.md
```

#### Exemple de Kustomization

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

configMapGenerator:
  - name: app-config
    files:
      - config.properties
    options:
      disableNameSuffixHash: false

secretGenerator:
  - name: app-secrets
    envs:
      - secrets.env
    options:
      disableNameSuffixHash: false

commonLabels:
  app: myapp
  managed-by: kustomize

images:
  - name: app-image
    newName: harbor.internal.company.com/production/myapp
    newTag: v1.2.0
```

```yaml
# k8s/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

namespace: production

replicas:
  - name: myapp
    count: 5

patches:
  - path: patches/resources.yaml
  - path: patches/hpa.yaml
  - path: patches/network-policy.yaml

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - ENVIRONMENT=production
      - LOG_LEVEL=info

images:
  - name: app-image
    newName: harbor.internal.company.com/production/myapp
    newTag: v1.2.0-prod
```

### Gestion des Secrets

#### Option 1 : Sealed Secrets (Bitnami)

```bash
# Installer Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Installer kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-linux-amd64
chmod +x kubeseal-linux-amd64
sudo mv kubeseal-linux-amd64 /usr/local/bin/kubeseal

# Créer un secret
kubectl create secret generic mysecret \
  --from-literal=password=s3cr3t \
  --dry-run=client -o yaml > secret.yaml

# Sceller le secret (peut être committé dans Git)
kubeseal -f secret.yaml -w sealed-secret.yaml \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system

# Appliquer le sealed secret
kubectl apply -f sealed-secret.yaml
# Le controller créera automatiquement le secret déchiffré
```

```yaml
# sealed-secret.yaml (safe to commit)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret
  namespace: production
spec:
  encryptedData:
    password: AgBvHj7qQ8hX...  # Valeur chiffrée
  template:
    metadata:
      name: mysecret
      namespace: production
    type: Opaque
```

#### Option 2 : External Secrets Operator (ESO)

```yaml
# Connecter à Vault, AWS Secrets Manager, Azure Key Vault, etc.

# 1. Créer un SecretStore
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault.internal.company.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "production-role"
          serviceAccountRef:
            name: external-secrets-sa

---
# 2. Créer un ExternalSecret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore

  target:
    name: app-secrets
    creationPolicy: Owner

  data:
    - secretKey: database_password
      remoteRef:
        key: production/database
        property: password

    - secretKey: api_key
      remoteRef:
        key: production/api
        property: key
```

### Architecture Review Checklist

Avant de passer en build, valider :

- [ ] **Sécurité** : Pas de credentials hardcodés, principe du moindre privilège
- [ ] **Haute disponibilité** : Replicas suffisants, anti-affinity rules
- [ ] **Resource limits** : CPU/Memory requests et limits définis
- [ ] **Health checks** : Liveness et readiness probes configurées
- [ ] **Network policies** : Flux réseau explicitement autorisés
- [ ] **Persistence** : PVC correctement dimensionnés, backup strategy
- [ ] **Monitoring** : ServiceMonitor ou annotations Prometheus
- [ ] **Logging** : Logs JSON structurés vers stdout/stderr

## 2️⃣ Phase de Build

### Pipeline CI/CD Sécurisé

#### Architecture CI/CD en DMZ

```
┌──────────────────────────────────────────────────────────┐
│                  Developer Workstation                    │
└───────────────────────┬──────────────────────────────────┘
                        │ git push
                        ▼
┌───────────────────────────────────────────────────────────┐
│                   GitLab/GitHub (DMZ)                     │
└───────────────────────┬───────────────────────────────────┘
                        │ webhook
                        ▼
┌───────────────────────────────────────────────────────────┐
│              CI/CD Pipeline (GitLab Runner)               │
│                                                           │
│  1. Lint & Test    2. Build      3. Scan     4. Push     │
│  ┌─────────┐    ┌─────────┐  ┌─────────┐  ┌─────────┐   │
│  │ golint  │───▶│ docker  │─▶│ Trivy   │─▶│ Harbor  │   │
│  │ pytest  │    │ build   │  │ Snyk    │  │ Push    │   │
│  └─────────┘    └─────────┘  └─────────┘  └─────────┘   │
└───────────────────────┬───────────────────────────────────┘
                        │ update manifest
                        ▼
┌───────────────────────────────────────────────────────────┐
│              GitOps Repository (Config repo)              │
└───────────────────────┬───────────────────────────────────┘
                        │ sync
                        ▼
┌───────────────────────────────────────────────────────────┐
│                     ArgoCD                                │
│                  (Continuous Deployment)                  │
└───────────────────────┬───────────────────────────────────┘
                        │ deploy
                        ▼
┌───────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (Production)              │
└───────────────────────────────────────────────────────────┘
```

#### Exemple GitLab CI/CD

```yaml
# .gitlab-ci.yml
stages:
  - lint
  - test
  - build
  - scan
  - deploy-staging
  - deploy-production

variables:
  REGISTRY: "harbor.internal.company.com"
  PROJECT: "production"
  IMAGE_NAME: "${REGISTRY}/${PROJECT}/${CI_PROJECT_NAME}"
  IMAGE_TAG: "${CI_COMMIT_SHORT_SHA}"

# Stage 1: Lint
lint-yaml:
  stage: lint
  image: cytopia/yamllint:latest
  script:
    - yamllint k8s/

lint-dockerfile:
  stage: lint
  image: hadolint/hadolint:latest-alpine
  script:
    - hadolint Dockerfile

# Stage 2: Test
unit-tests:
  stage: test
  image: python:3.12
  script:
    - pip install -r requirements.txt
    - pytest tests/ --cov=app --cov-report=xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

# Stage 3: Build
build-image:
  stage: build
  image: docker:24-dind
  services:
    - docker:24-dind
  before_script:
    - docker login -u $HARBOR_USER -p $HARBOR_PASSWORD $REGISTRY
  script:
    # Build multi-stage pour minimiser la taille
    - docker build
        --build-arg VERSION=${CI_COMMIT_TAG:-${CI_COMMIT_SHORT_SHA}}
        --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
        --build-arg VCS_REF=${CI_COMMIT_SHA}
        -t ${IMAGE_NAME}:${IMAGE_TAG}
        -t ${IMAGE_NAME}:latest
        .
    - docker push ${IMAGE_NAME}:${IMAGE_TAG}
    - docker push ${IMAGE_NAME}:latest
  only:
    - main
    - tags

# Stage 4: Security Scan
scan-trivy:
  stage: scan
  image: aquasec/trivy:latest
  script:
    # Scanner l'image depuis Harbor
    - trivy image
        --severity CRITICAL,HIGH
        --exit-code 1
        --no-progress
        ${IMAGE_NAME}:${IMAGE_TAG}
  dependencies:
    - build-image
  only:
    - main
    - tags

scan-secrets:
  stage: scan
  image: trufflesecurity/trufflehog:latest
  script:
    - trufflehog git file://. --only-verified --fail
  allow_failure: false

# Stage 5: Deploy to Staging
deploy-staging:
  stage: deploy-staging
  image: bitnami/kubectl:latest
  script:
    # Update image tag in kustomization
    - cd k8s/overlays/staging
    - kustomize edit set image app-image=${IMAGE_NAME}:${IMAGE_TAG}

    # Commit to GitOps repo (alternative: use ArgoCD Image Updater)
    - git config user.name "GitLab CI"
    - git config user.email "ci@company.com"
    - git add kustomization.yaml
    - git commit -m "chore: update staging to ${IMAGE_TAG}"
    - git push https://oauth2:${GITLAB_TOKEN}@gitlab.internal.company.com/gitops/app-config.git HEAD:main
  environment:
    name: staging
    url: https://app-staging.company.com
  only:
    - main

# Stage 6: Deploy to Production (manual approval)
deploy-production:
  stage: deploy-production
  image: bitnami/kubectl:latest
  script:
    - cd k8s/overlays/production
    - kustomize edit set image app-image=${IMAGE_NAME}:${IMAGE_TAG}

    - git config user.name "GitLab CI"
    - git config user.email "ci@company.com"
    - git add kustomization.yaml
    - git commit -m "chore: update production to ${IMAGE_TAG}"
    - git push https://oauth2:${GITLAB_TOKEN}@gitlab.internal.company.com/gitops/app-config.git HEAD:main
  environment:
    name: production
    url: https://app.company.com
  when: manual  # Require manual approval
  only:
    - tags    # Only tagged releases to production
```

### Build Sécurisé

#### Dockerfile Multi-Stage

```dockerfile
# Stage 1: Build
FROM python:3.12-slim AS builder

WORKDIR /build

# Install dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Runtime
FROM python:3.12-slim

# Créer utilisateur non-root
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copier uniquement les dépendances installées
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .

# Ajouter le répertoire local bin au PATH
ENV PATH=/home/appuser/.local/bin:$PATH

# Ne pas exécuter en tant que root
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:8080/health')"

# Labels pour traçabilité
LABEL org.opencontainers.image.source="https://gitlab.internal.company.com/app/myapp"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"

EXPOSE 8080

CMD ["python", "app.py"]
```

## 3️⃣ Phase de Test

### Tests de Sécurité

```yaml
# k8s-security-test.yaml
# Utiliser conftest (OPA) pour policy-as-code

apiVersion: v1
kind: ConfigMap
metadata:
  name: conftest-policies
data:
  security.rego: |
    package main

    deny[msg] {
      input.kind == "Deployment"
      not input.spec.template.spec.securityContext.runAsNonRoot
      msg = "Containers must not run as root"
    }

    deny[msg] {
      input.kind == "Deployment"
      container := input.spec.template.spec.containers[_]
      not container.securityContext.readOnlyRootFilesystem
      msg = sprintf("Container %s must use read-only root filesystem", [container.name])
    }

    deny[msg] {
      input.kind == "Deployment"
      container := input.spec.template.spec.containers[_]
      not container.resources.limits.memory
      msg = sprintf("Container %s must have memory limit", [container.name])
    }
```

Test avec conftest :
```bash
# Installer conftest
wget https://github.com/open-policy-agent/conftest/releases/download/v0.45.0/conftest_0.45.0_Linux_x86_64.tar.gz
tar xzf conftest_0.45.0_Linux_x86_64.tar.gz
sudo mv conftest /usr/local/bin/

# Tester les manifests
conftest test k8s/base/deployment.yaml -p policy/security.rego

# Exemple de sortie :
# FAIL - k8s/base/deployment.yaml - Containers must not run as root
# FAIL - k8s/base/deployment.yaml - Container webapp must use read-only root filesystem
```

### Tests d'Intégration

```bash
# test-integration.sh
#!/bin/bash
set -euo pipefail

NAMESPACE="test-${CI_COMMIT_SHORT_SHA}"

echo "Creating test namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE}

# Apply manifests
kubectl apply -k k8s/overlays/staging -n ${NAMESPACE}

# Wait for deployment
kubectl rollout status deployment/myapp -n ${NAMESPACE} --timeout=5m

# Run tests
kubectl run test-pod \
  --image=harbor.internal.company.com/tools/curl:latest \
  --restart=Never \
  --namespace=${NAMESPACE} \
  --command -- sh -c "
    curl -f http://myapp:8080/health || exit 1
    curl -f http://myapp:8080/api/v1/status || exit 1
  "

# Wait for test pod
kubectl wait --for=condition=completed pod/test-pod -n ${NAMESPACE} --timeout=2m

# Check test results
if kubectl logs test-pod -n ${NAMESPACE} | grep -q "error"; then
  echo "Integration tests failed"
  exit 1
fi

echo "Integration tests passed"

# Cleanup
kubectl delete namespace ${NAMESPACE}
```

## 4️⃣ Phase de Deploy

### GitOps avec ArgoCD

#### Installation ArgoCD

```bash
# Créer namespace
kubectl create namespace argocd

# Installer ArgoCD
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Exposer l'interface (pour DMZ, utiliser Ingress avec TLS)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Récupérer le mot de passe initial
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Se connecter via CLI
argocd login <ARGOCD_SERVER>
argocd account update-password
```

#### Configuration ArgoCD Application

```yaml
# .gitops/argocd/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-production
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: production

  source:
    repoURL: https://gitlab.internal.company.com/gitops/app-config.git
    targetRevision: main
    path: k8s/overlays/production

  destination:
    server: https://kubernetes.default.svc
    namespace: production

  syncPolicy:
    automated:
      prune: true      # Supprimer les ressources supprimées du Git
      selfHeal: true   # Corriger automatiquement les drifts
      allowEmpty: false

    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true

    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  # Health checks personnalisés
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # Ignorer si HPA modifie les replicas

  # Notifications sur erreurs
  revisionHistoryLimit: 10
```

#### ArgoCD Project pour Isolation

```yaml
# .gitops/argocd/project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production applications

  # Repos sources autorisés
  sourceRepos:
    - https://gitlab.internal.company.com/gitops/app-config.git

  # Destinations autorisées
  destinations:
    - namespace: production
      server: https://kubernetes.default.svc
    - namespace: monitoring
      server: https://kubernetes.default.svc

  # Ressources autorisées
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: 'rbac.authorization.k8s.io'
      kind: ClusterRole
    - group: 'rbac.authorization.k8s.io'
      kind: ClusterRoleBinding

  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  # Deny certain resources
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange
```

### Stratégies de Déploiement

#### Rolling Update (par défaut)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2        # 2 pods supplémentaires pendant l'update
      maxUnavailable: 1  # Maximum 1 pod indisponible
  template:
    spec:
      containers:
      - name: app
        image: harbor.internal.company.com/production/myapp:v1.2.0
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

#### Blue/Green

```yaml
# Service pointe vers blue ou green
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue  # Changer vers green pour switch
  ports:
  - port: 80
    targetPort: 8080

---
# Deployment Blue (version actuelle)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 5
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
        image: harbor.internal.company.com/production/myapp:v1.1.0

---
# Deployment Green (nouvelle version)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 5
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
        image: harbor.internal.company.com/production/myapp:v1.2.0
```

Switch :
```bash
# Basculer vers green
kubectl patch service myapp -p '{"spec":{"selector":{"version":"green"}}}'

# Vérifier que tout fonctionne

# Si OK, supprimer blue
kubectl delete deployment myapp-blue

# Si problème, rollback vers blue
kubectl patch service myapp -p '{"spec":{"selector":{"version":"blue"}}}'
```

#### Canary avec Argo Rollouts

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 10    # 10% vers nouvelle version
      - pause: {duration: 5m}
      - setWeight: 30    # 30% vers nouvelle version
      - pause: {duration: 5m}
      - setWeight: 50    # 50% vers nouvelle version
      - pause: {duration: 5m}
      - setWeight: 100   # 100% vers nouvelle version

      # Rollback automatique si métriques dégradées
      analysis:
        templates:
        - templateName: success-rate
        startingStep: 1
        args:
        - name: service-name
          value: myapp

  selector:
    matchLabels:
      app: myapp

  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: harbor.internal.company.com/production/myapp:v1.2.0
```

## 5️⃣ Phase d'Opération

### Scaling

#### Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp

  minReplicas: 3
  maxReplicas: 20

  metrics:
  # CPU
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

  # Memory
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80

  # Métrique custom (Prometheus)
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"

  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Attendre 5min avant scale down
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60  # Réduire max 50% par minute

    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30  # Doubler max tous les 30s
      - type: Pods
        value: 5
        periodSeconds: 30  # Ajouter max 5 pods tous les 30s
      selectPolicy: Max
```

#### Vertical Pod Autoscaler (VPA)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp

  updatePolicy:
    updateMode: "Auto"  # Ou "Recreate", "Initial", "Off"

  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 2Gi
      controlledResources: ["cpu", "memory"]
```

### Rolling Updates

```bash
# Update de l'image
kubectl set image deployment/myapp \
  app=harbor.internal.company.com/production/myapp:v1.3.0 \
  -n production

# Surveiller le rollout
kubectl rollout status deployment/myapp -n production

# Voir l'historique
kubectl rollout history deployment/myapp -n production

# Rollback vers version précédente
kubectl rollout undo deployment/myapp -n production

# Rollback vers une révision spécifique
kubectl rollout undo deployment/myapp -n production --to-revision=3

# Pause d'un rollout
kubectl rollout pause deployment/myapp -n production

# Reprendre un rollout
kubectl rollout resume deployment/myapp -n production
```

## 6️⃣ Phase de Monitoring

Voir [SECURE_CLUSTER_MANAGEMENT.md](SECURE_CLUSTER_MANAGEMENT.md#📊-monitoring-et-logging-en-environnement-sécurisé) pour détails complets.

### Golden Signals

```promql
# 1. Latency (temps de réponse)
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{job="myapp"}[5m])
)

# 2. Traffic (requêtes par seconde)
rate(http_requests_total{job="myapp"}[5m])

# 3. Errors (taux d'erreur)
rate(http_requests_total{job="myapp",status=~"5.."}[5m])
/
rate(http_requests_total{job="myapp"}[5m])

# 4. Saturation (utilisation ressources)
avg(container_memory_usage_bytes{pod=~"myapp-.*"})
/
avg(container_spec_memory_limit_bytes{pod=~"myapp-.*"})
```

## 7️⃣ Phase d'Optimisation

### Analyse des Coûts

```bash
# Utiliser kubectl-cost (kubecost)
kubectl cost deployment myapp -n production

# Identifier les ressources sur-provisionnées
kubectl top pods -n production
kubectl describe vpa myapp-vpa -n production
```

### Optimisation Performance

```yaml
# Utiliser topology spread constraints
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: myapp
```

## 8️⃣ Phase de Retirement

### Procédure de Décommissionnement

```bash
# 1. Arrêter les nouveaux déploiements
argocd app set myapp-production --sync-policy none

# 2. Scaler à 0 replicas
kubectl scale deployment myapp --replicas=0 -n production

# 3. Archiver les données
kubectl exec -it myapp-db-0 -n production -- \
  pg_dump -U postgres myapp > backup-final-$(date +%Y%m%d).sql

# 4. Supprimer les ressources
kubectl delete -k k8s/overlays/production

# 5. Archiver dans Git
git tag -a "archived-$(date +%Y%m%d)" -m "Application retired"
git push origin --tags

# 6. Documenter
echo "Application retired on $(date)" >> docs/CHANGELOG.md
```

## 📋 Checklist Complète

### Design
- [ ] Manifests dans Git
- [ ] Secrets externalisés (Vault/Sealed Secrets)
- [ ] Resource limits définis
- [ ] Health checks configurés
- [ ] Network policies définies

### Build
- [ ] CI/CD automatisé
- [ ] Scan de sécurité automatique
- [ ] Tests unitaires passent
- [ ] Image multi-stage optimisée

### Deploy
- [ ] GitOps (ArgoCD) configuré
- [ ] Stratégie de déploiement définie
- [ ] Rollback plan documenté

### Operate
- [ ] HPA/VPA configuré
- [ ] Monitoring en place
- [ ] Alerting configuré
- [ ] Runbook disponible

### Retire
- [ ] Données archivées
- [ ] Documentation à jour
- [ ] Ressources cloud supprimées

## 📚 Références

- [The Twelve-Factor App](https://12factor.net/)
- [GitOps with ArgoCD](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)

## Articles Complémentaires

- [Gestion de Cluster Sécurisé](SECURE_CLUSTER_MANAGEMENT.md)
- [Registres d'Images en DMZ](IMAGE_REGISTRY_DMZ.md)
- [Déploiement Air-Gapped](AIRGAP_DEPLOYMENT.md)
