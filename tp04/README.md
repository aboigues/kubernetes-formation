# TP4 - Monitoring et Gestion des Logs dans Kubernetes

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Comprendre l'observabilité dans Kubernetes
- Installer et utiliser Metrics Server pour la collecte de métriques
- Utiliser le Dashboard Kubernetes pour la visualisation
- Collecter et analyser les logs des pods
- Déployer Prometheus et Grafana pour le monitoring avancé
- Créer des dashboards personnalisés
- Mettre en place des alertes
- Appliquer les bonnes pratiques de monitoring

## Prérequis

- Avoir complété les TP1, TP2 et TP3
- Un cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)
- 4 Go de RAM minimum (pour Prometheus et Grafana)
- Connaissance des Deployments et Services

**Note pour kubeadm :** Les outils de monitoring (Metrics Server, Dashboard, Prometheus) s'installent de la même manière. Consultez le [guide kubeadm - Partie 11](../docs/KUBEADM_SETUP.md#partie-11--addons-et-fonctionnalités-complémentaires) pour les équivalences des addons minikube.

## Partie 1 : Introduction à l'observabilité

### 1.1 Les trois piliers de l'observabilité

L'observabilité repose sur trois piliers :

1. **Métriques (Metrics)** : Données numériques agrégées
   - CPU, mémoire, réseau
   - Requêtes par seconde
   - Temps de réponse

2. **Logs** : Enregistrements d'événements
   - Logs applicatifs
   - Logs système
   - Logs d'audit

3. **Traces** : Suivi des requêtes distribuées
   - Temps de traitement
   - Propagation entre services
   - Identification des goulots d'étranglement

### 1.2 Architecture de monitoring Kubernetes

```
┌─────────────────────────────────────────────────────┐
│                   Grafana (Visualisation)           │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              Prometheus (Collecte)                  │
└──────────────────────┬──────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼────┐   ┌────▼────┐   ┌───▼─────┐
    │ Node    │   │ Pods    │   │ cAdvisor│
    │ Exporter│   │ Metrics │   │         │
    └─────────┘   └─────────┘   └─────────┘
```

## Partie 2 : Metrics Server

### 2.1 Qu'est-ce que Metrics Server ?

Metrics Server collecte les métriques de ressources (CPU, mémoire) des nœuds et pods via l'API kubelet.

### 2.2 Installation de Metrics Server

```bash
# Activer l'addon metrics-server dans minikube
minikube addons enable metrics-server

# Vérifier le déploiement
kubectl get deployment metrics-server -n kube-system

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s
```

### 2.3 Utiliser les métriques

**Exercice 1 : Métriques de base**

```bash
# Voir l'utilisation des nœuds
kubectl top nodes

# Créer un déploiement de test
kubectl create deployment nginx-test --image=nginx:alpine --replicas=3

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=nginx-test --timeout=60s

# Voir l'utilisation des pods
kubectl top pods

# Métriques d'un namespace spécifique
kubectl top pods -n kube-system

# Trier par consommation CPU
kubectl top pods --sort-by=cpu

# Trier par consommation mémoire
kubectl top pods --sort-by=memory
```

**Note** : Les métriques peuvent prendre 1-2 minutes pour apparaître après l'installation.

### 2.4 Horizontal Pod Autoscaler (HPA)

Le HPA ajuste automatiquement le nombre de replicas basé sur les métriques.

Créer `01-hpa-demo.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: php-apache
  template:
    metadata:
      labels:
        app: php-apache
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
spec:
  selector:
    app: php-apache
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: php-apache-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: php-apache
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

**Exercice 2 : Tester l'autoscaling**

```bash
# Appliquer le manifest
kubectl apply -f 01-hpa-demo.yaml

# Vérifier le HPA
kubectl get hpa

# Observer l'état initial
kubectl get hpa php-apache-hpa -w &

# Dans un autre terminal, générer de la charge
kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

# Observer le scaling (attendre 2-3 minutes)
kubectl get pods -l app=php-apache -w

# Après quelques minutes, arrêter le générateur de charge
kubectl delete pod load-generator

# Observer le scale down (prend environ 5 minutes)
kubectl get hpa php-apache-hpa -w

# Arrêter le watch en background du début de l'exercice
# (Si vous avez lancé le premier watch avec &)
pkill -f "kubectl.*hpa.*php-apache-hpa"
```

## Partie 3 : Dashboard Kubernetes

### 3.1 Activer le Dashboard

```bash
# Activer le dashboard dans minikube
minikube addons enable dashboard

# Vérifier le déploiement
kubectl get pods -n kubernetes-dashboard

# Lancer le dashboard
minikube dashboard
```

Le dashboard s'ouvre automatiquement dans votre navigateur.

### 3.2 Explorer le Dashboard

**Fonctionnalités principales** :
- Vue d'ensemble du cluster
- État des déploiements, pods, services
- Utilisation des ressources (CPU, mémoire)
- Logs des pods
- Exécution de commandes dans les pods
- Édition des ressources

**Exercice 3 : Navigation dans le Dashboard**

1. Naviguez vers "Workloads" → "Deployments"
2. Sélectionnez le namespace "default"
3. Cliquez sur un déploiement
4. Explorez les informations affichées
5. Cliquez sur "Pods" et sélectionnez un pod
6. Consultez les logs du pod
7. Essayez la fonction "Exec" pour ouvrir un shell

## Partie 4 : Gestion des Logs

### 4.1 Logs avec kubectl

```bash
# Voir les logs d'un pod
kubectl logs <pod-name>

# Logs en temps réel (-f = follow)
kubectl logs -f <pod-name>

# Logs d'un conteneur spécifique dans un pod multi-conteneurs
kubectl logs <pod-name> -c <container-name>

# Logs du conteneur précédent (en cas de crash)
kubectl logs <pod-name> --previous

# Dernières N lignes
kubectl logs <pod-name> --tail=50

# Logs depuis X minutes
kubectl logs <pod-name> --since=5m

# Logs avec timestamps
kubectl logs <pod-name> --timestamps
```

### 4.2 Application de démonstration avec logs

Créer `02-logging-demo.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-generator
spec:
  replicas: 2
  selector:
    matchLabels:
      app: log-generator
  template:
    metadata:
      labels:
        app: log-generator
    spec:
      containers:
      - name: logger
        image: busybox
        command: ["/bin/sh"]
        args:
          - -c
          - >
            while true; do
              echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Application running - Request ID: $RANDOM";
              sleep 2;
              if [ $((RANDOM % 10)) -eq 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Something went wrong!";
              fi
            done
```

**Exercice 4 : Analyser les logs**

```bash
# Déployer l'application
kubectl apply -f 02-logging-demo.yaml

# Lister les pods
kubectl get pods -l app=log-generator

# Voir les logs d'un pod
POD_NAME=$(kubectl get pods -l app=log-generator -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD_NAME

# Suivre les logs en temps réel
kubectl logs -f $POD_NAME

# Rechercher les erreurs
kubectl logs $POD_NAME | grep ERROR

# Logs de tous les pods avec le label app=log-generator
kubectl logs -l app=log-generator --all-containers=true

# Logs depuis les 5 dernières minutes
kubectl logs $POD_NAME --since=5m
```

### 4.3 Logging multi-conteneurs

Créer `03-multi-container-logging.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-log-pod
spec:
  containers:
  - name: frontend
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "[FRONTEND] Handling request at $(date)";
          sleep 3;
        done

  - name: backend
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "[BACKEND] Processing data at $(date)";
          sleep 5;
        done

  - name: cache
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "[CACHE] Cache hit/miss at $(date)";
          sleep 4;
        done
```

**Exercice 5 : Logs multi-conteneurs**

```bash
# Créer le pod
kubectl apply -f 03-multi-container-logging.yaml

# Voir les logs de chaque conteneur
kubectl logs multi-log-pod -c frontend
kubectl logs multi-log-pod -c backend
kubectl logs multi-log-pod -c cache

# Suivre les logs de plusieurs conteneurs en parallèle (dans des terminaux séparés)
kubectl logs -f multi-log-pod -c frontend
kubectl logs -f multi-log-pod -c backend
kubectl logs -f multi-log-pod -c cache

# Astuce : Utiliser stern pour voir tous les logs
# Installation de stern (optionnel)
# Télécharger la dernière version : https://github.com/stern/stern/releases/latest
# Exemple pour Linux amd64 :
# wget https://github.com/stern/stern/releases/latest/download/stern_linux_amd64.tar.gz
# tar xzf stern_linux_amd64.tar.gz
# sudo mv stern /usr/local/bin/
# stern --version

# Utilisation de stern (si installé)
# stern multi-log-pod
```

## Partie 5 : Prometheus et Grafana

### 5.1 Architecture Prometheus

Prometheus est un système de monitoring et d'alerte open-source :
- **Collecte** : Scrape les métriques des cibles
- **Stockage** : Base de données time-series
- **Requêtes** : Langage PromQL
- **Alertes** : Règles d'alerte configurables

### 5.2 Installation de Prometheus

**Note importante sur les endpoints Prometheus** :

Le job `kubernetes-service-endpoints` est configuré pour découvrir automatiquement les services via le service discovery de Kubernetes. **IMPORTANT** : Sans les `relabel_configs` appropriés, Prometheus tenterait de scraper **tous** les endpoints de services dans le cluster (kube-dns, kube-apiserver, etc.), ce qui génère des centaines d'erreurs HTTP 404 car la plupart n'exposent pas de métriques Prometheus.

La configuration ci-dessus filtre uniquement les services qui ont l'annotation `prometheus.io/scrape: "true"` et utilise les annotations suivantes :
- `prometheus.io/scrape: "true"` : Active le scraping pour ce service
- `prometheus.io/port: "<port>"` : Port où les métriques sont exposées
- `prometheus.io/path: "<path>"` : Chemin des métriques (par défaut `/metrics`)

**Note importante sur les permissions RBAC** :

Prometheus utilise le **service discovery** de Kubernetes pour découvrir automatiquement les targets (nœuds, pods, services). Pour cela, il a besoin de permissions RBAC spécifiques :

| Permission | Ressource | Usage |
|------------|-----------|-------|
| `get`, `list`, `watch` | `nodes`, `nodes/proxy`, `nodes/metrics` | Découvrir les nœuds et accéder aux métriques kubelet |
| `get` | `/metrics`, `/metrics/cadvisor` (nonResourceURLs) | Accéder aux endpoints de métriques |
| `get`, `list`, `watch` | `pods`, `services`, `endpoints`, `namespaces` | Service discovery pour pods et services |
| `get`, `list`, `watch` | `ingresses` (networking.k8s.io) | Découvrir les ingresses |

Sans ces permissions, Prometheus ne pourra pas :
- ✗ Collecter les métriques cAdvisor (CPU, mémoire des conteneurs)
- ✗ Découvrir automatiquement les pods annotés
- ✗ Scraper les métriques des nœuds

Créer `04-prometheus-deployment.yaml` :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    scrape_configs:
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)

      - job_name: 'kubernetes-cadvisor'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __metrics_path__
            replacement: /metrics/cadvisor

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

      - job_name: 'kubernetes-service-endpoints'
        kubernetes_sd_configs:
          - role: endpoints
        relabel_configs:
          # Ne garder que les services annotés avec prometheus.io/scrape=true
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          # Utiliser le chemin spécifié dans l'annotation prometheus.io/path (par défaut /metrics)
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          # Utiliser le port spécifié dans l'annotation prometheus.io/port
          - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          # Copier les labels du service
          - action: labelmap
            regex: __meta_kubernetes_service_label_(.+)
          # Ajouter le namespace comme label
          - source_labels: [__meta_kubernetes_namespace]
            target_label: kubernetes_namespace
          # Ajouter le nom du service comme label
          - source_labels: [__meta_kubernetes_service_name]
            target_label: kubernetes_name
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v3
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus'
          - '--web.console.libraries=/usr/share/prometheus/console_libraries'
          - '--web.console.templates=/usr/share/prometheus/consoles'
        ports:
        - containerPort: 9090
          name: web
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus
        - name: prometheus-storage
          mountPath: /prometheus
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: prometheus
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - nodes/metrics
  - services
  - endpoints
  - pods
  - namespaces
  verbs: ["get", "list", "watch"]
- nonResourceURLs:
  - /metrics
  - /metrics/cadvisor
  verbs: ["get"]
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
```

**Exercice 6 : Déployer Prometheus**

```bash
# Appliquer la configuration
kubectl apply -f 04-prometheus-deployment.yaml

# Vérifier le déploiement
kubectl get all -n monitoring

# Attendre que Prometheus soit prêt
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s

# Obtenir l'URL de Prometheus
minikube service prometheus -n monitoring --url

# Ou avec port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Accédez à Prometheus via `http://localhost:9090` (si vous utilisez port-forward).

### 5.3 Vérifier que Prometheus fonctionne

Avant d'explorer les métriques, vérifions que Prometheus collecte bien les données.

**Exercice 6.1 : Vérifications de base**

```bash
# 1. Vérifier l'état du pod Prometheus
kubectl get pods -n monitoring -l app=prometheus

# 2. Vérifier les logs de Prometheus pour détecter les erreurs
kubectl logs -n monitoring -l app=prometheus --tail=50

# 3. Vérifier que la configuration est bien chargée
kubectl logs -n monitoring -l app=prometheus | grep -i "Server is ready"

# 4. Tester l'accès à l'interface web (si port-forward actif)
curl -s http://localhost:9090/-/healthy
# Devrait retourner : Prometheus is Healthy.

# 5. Vérifier l'état de l'API Prometheus
curl -s http://localhost:9090/api/v1/status/config | jq '.status'
# Devrait retourner : "success"
```

**Exercice 6.2 : Vérifier les targets (cibles de collecte)**

Les "targets" sont les endpoints que Prometheus scrape pour collecter les métriques.

```bash
# Via curl (nécessite port-forward actif sur 9090)
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'

# Vérifier combien de targets sont UP
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="up") | .labels.job' | sort | uniq -c
```

**Via l'interface web** (recommandé pour débutants) :
1. Ouvrez `http://localhost:9090` dans votre navigateur
2. Allez dans **Status → Targets**
3. Vérifiez que les jobs suivants sont **UP** (en bleu) :
   - `kubernetes-nodes`
   - `kubernetes-cadvisor`
   - `kubernetes-pods` (si vous avez des pods annotés)
   - `kubernetes-service-endpoints`

**Diagnostic des problèmes courants :**

```bash
# 1. Vérifier que le ServiceAccount existe
kubectl get serviceaccount prometheus -n monitoring

# 2. Vérifier le ClusterRole et ses permissions
kubectl get clusterrole prometheus -o yaml

# Vérifier spécifiquement les permissions importantes :
kubectl get clusterrole prometheus -o jsonpath='{.rules[*].resources}' | grep -E "nodes/metrics|namespaces"
# Devrait retourner : nodes/metrics et namespaces

# 3. Vérifier que le ClusterRoleBinding lie bien le SA au ClusterRole
kubectl get clusterrolebinding prometheus -o yaml

# 4. Vérifier les événements du namespace monitoring pour des erreurs d'autorisation
kubectl get events -n monitoring --sort-by='.lastTimestamp' | grep -i "forbidden\|unauthorized\|permission"

# 5. Tester l'autorisation depuis le ServiceAccount Prometheus
kubectl auth can-i list nodes --as=system:serviceaccount:monitoring:prometheus
# Devrait retourner : yes

kubectl auth can-i get nodes/metrics --as=system:serviceaccount:monitoring:prometheus
# Devrait retourner : yes

kubectl auth can-i get pods --as=system:serviceaccount:monitoring:prometheus
# Devrait retourner : yes

# 6. Vérifier les logs Prometheus pour des erreurs d'autorisation
kubectl logs -n monitoring -l app=prometheus --tail=100 | grep -i "forbidden\|unauthorized\|401\|403"

# 7. Tester manuellement l'accès à l'API Kubernetes depuis le pod Prometheus
PROMETHEUS_POD=$(kubectl get pod -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring $PROMETHEUS_POD -- wget -O- --no-check-certificate \
  --header="Authorization: Bearer $(kubectl exec -n monitoring $PROMETHEUS_POD -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  https://kubernetes.default.svc.cluster.local:443/api/v1/nodes 2>&1 | head -n 20
# Ne devrait PAS retourner d'erreur 403 Forbidden
```

**Erreurs courantes et solutions :**

| Erreur | Cause | Solution |
|--------|-------|----------|
| `server returned HTTP status 403 Forbidden` | Permissions RBAC manquantes | Vérifier que le ClusterRole contient `nodes/metrics`, `namespaces`, et `nonResourceURLs` |
| `Target down` pour kubernetes-cadvisor | Pas d'accès à `/metrics/cadvisor` | Ajouter `nonResourceURLs: ["/metrics", "/metrics/cadvisor"]` dans le ClusterRole |
| `server returned HTTP status 401 Unauthorized` | ServiceAccount non lié au ClusterRole | Vérifier le ClusterRoleBinding |
| `Failed to list *v1.Node` | Permission manquante sur les nodes | Ajouter `nodes` dans les resources du ClusterRole |

**Exercice 6.3 : Vérifier que les métriques sont collectées**

```bash
# Via curl (avec port-forward actif)
# Vérifier que des métriques cAdvisor existent
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | {job: .metric.job, instance: .metric.instance, value: .value[1]}'

# Compter le nombre de séries métriques collectées
curl -s 'http://localhost:9090/api/v1/query?query=count({__name__=~".+"})' | jq '.data.result[0].value[1]'

# Vérifier les métriques CPU des conteneurs
curl -s 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total' | jq '.data.result | length'
# Devrait retourner un nombre > 0

# Vérifier les métriques mémoire des conteneurs
curl -s 'http://localhost:9090/api/v1/query?query=container_memory_usage_bytes' | jq '.data.result | length'
# Devrait retourner un nombre > 0
```

**Via l'interface web** :
1. Ouvrez `http://localhost:9090`
2. Allez dans **Graph**
3. Tapez `up` dans la barre de requête et cliquez sur **Execute**
4. Vous devriez voir plusieurs targets avec la valeur `1` (UP)

**Exercice 6.4 : Vérifier la collecte des métriques cAdvisor**

```bash
# Lister les jobs actifs dans Prometheus
curl -s 'http://localhost:9090/api/v1/label/job/values' | jq '.data[]'

# Vérifier les métriques du job kubernetes-cadvisor
curl -s 'http://localhost:9090/api/v1/query?query=up{job="kubernetes-cadvisor"}' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

# Tester une requête CPU simple
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m]))' | jq '.data.result[0].value'
```

**Checklist de vérification :**

- [ ] Le pod Prometheus est en état `Running`
- [ ] Le ServiceAccount `prometheus` existe dans le namespace `monitoring`
- [ ] Le ClusterRole `prometheus` contient les permissions pour `nodes/metrics`, `namespaces`, et `nonResourceURLs`
- [ ] Le ClusterRoleBinding lie bien le ServiceAccount au ClusterRole
- [ ] `kubectl auth can-i get nodes/metrics --as=system:serviceaccount:monitoring:prometheus` retourne `yes`
- [ ] Aucune erreur dans les logs Prometheus (pas de 403 Forbidden)
- [ ] L'endpoint `/api/v1/targets` montre des targets UP
- [ ] Les jobs `kubernetes-nodes` et `kubernetes-cadvisor` sont UP
- [ ] La requête `up` retourne des résultats
- [ ] La requête `container_cpu_usage_seconds_total` retourne des métriques
- [ ] L'interface web est accessible sur http://localhost:9090

**Si tout est OK, passez à l'exploration des métriques ! ✅**

### 5.4 Explorer Prometheus

**Note importante sur les métriques cAdvisor** :

Les métriques comme `container_cpu_usage_seconds_total` et `container_memory_usage_bytes` sont collectées par cAdvisor (Container Advisor) qui est intégré dans kubelet.

Points importants :
- Ces métriques utilisent le label `container` (et non `pod`)
- Le container "POD" représente le conteneur infrastructure et doit être filtré
- Les conteneurs vides doivent être exclus avec `container!=""`
- Les requêtes doivent généralement agréger par `pod` et `namespace`

#### 5.3.1 Guide complet : Utiliser `container_cpu_usage_seconds_total`

La métrique `container_cpu_usage_seconds_total` est **la métrique principale pour surveiller l'utilisation CPU** dans Kubernetes. C'est un **compteur cumulatif** (counter) qui représente le temps CPU total consommé par un conteneur en secondes.

**🔑 Règles essentielles à respecter** :

1. **Toujours utiliser `rate()`** : La métrique est cumulative, il faut calculer le taux de variation
   ```promql
   rate(container_cpu_usage_seconds_total[5m])
   ```

2. **Filtrer le conteneur infrastructure** : `container!="POD"`
   ```promql
   container_cpu_usage_seconds_total{container!="POD"}
   ```

3. **Exclure les conteneurs vides** : `container!=""`
   ```promql
   container_cpu_usage_seconds_total{container!="",container!="POD"}
   ```

4. **Agréger par pod et namespace** : Utiliser `sum()` et `by()`
   ```promql
   sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)
   ```

**📊 Exemples pratiques** :

```promql
# 1. Utilisation CPU par pod (en cores) - REQUÊTE STANDARD
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)

# 2. Top 5 des pods les plus gourmands en CPU
topk(5, sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod))

# 3. CPU total utilisé dans un namespace spécifique
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring",container!="",container!="POD"}[5m]))

# 4. CPU total du cluster (tous les pods)
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m]))

# 5. CPU par conteneur (détail fin)
rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])

# 6. Moyenne CPU des replicas d'un déploiement
avg(rate(container_cpu_usage_seconds_total{pod=~"nginx-.*",container!="",container!="POD"}[5m]))
```

**💡 Comprendre les résultats** :

- Résultat = **0.5** → Le pod utilise **0.5 core** (50% d'un CPU)
- Résultat = **1.2** → Le pod utilise **1.2 cores** (plus d'un CPU complet)
- Résultat = **0.001** → Le pod utilise **0.1%** d'un CPU (très peu)

**🎯 Cas d'usage courants** :

```promql
# Identifier les pods au-dessus d'un seuil (0.8 cores)
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace) > 0.8

# Comparer avec les requests (nécessite kube-state-metrics)
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)
/
sum(kube_pod_container_resource_requests{resource="cpu"}) by (pod, namespace)

# CPU par node
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (node)
```

**⚠️ Erreurs courantes à éviter** :

| ❌ Erreur | ✅ Correct |
|-----------|-----------|
| `container_cpu_usage_seconds_total` | `rate(container_cpu_usage_seconds_total[5m])` |
| `rate(...[10s])` (intervalle trop court) | `rate(...[5m])` (minimum 1-5 minutes) |
| Sans filtrer `container!="POD"` | `{container!="",container!="POD"}` |
| Pas d'agrégation (trop de séries) | `sum(...) by (pod, namespace)` |

**Exercice 7 : Requêtes PromQL**

Dans l'interface web de Prometheus :

```promql
# Voir tous les pods
up

# Utilisation CPU des conteneurs (métrique brute)
container_cpu_usage_seconds_total

# ⭐ MEILLEURE PRATIQUE : CPU par pod (en cores)
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)

# Utilisation mémoire
container_memory_usage_bytes

# Mémoire utilisée par pod
sum(container_memory_usage_bytes{container!="",container!="POD"}) by (pod, namespace)

# Nombre de conteneurs par pod et namespace
count(container_memory_usage_bytes{container!="",container!="POD"}) by (pod, namespace)

# Note: Pour des métriques plus complètes sur l'état du cluster (comme kube_pod_info),
# installez kube-state-metrics (voir section Outils complémentaires)

# Taux de requêtes HTTP (si métriques disponibles)
rate(http_requests_total[5m])

# Top 10 pods par CPU
topk(10, sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace))

# Pods utilisant plus de 50% d'un core
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace) > 0.5
```

### 5.5 Installation de Grafana

Créer `05-grafana-deployment.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:10.0.0
        ports:
        - containerPort: 3000
          name: web
        env:
        - name: GF_SECURITY_ADMIN_USER
          value: "admin"
        - name: GF_SECURITY_ADMIN_PASSWORD
          value: "admin123"
        - name: GF_USERS_ALLOW_SIGN_UP
          value: "false"
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: grafana-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  type: NodePort
  selector:
    app: grafana
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30300
```

**Exercice 8 : Déployer Grafana**

```bash
# Appliquer la configuration
kubectl apply -f 05-grafana-deployment.yaml

# Vérifier le déploiement
kubectl get pods -n monitoring

# Attendre que Grafana soit prêt
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s

# Obtenir l'URL de Grafana
minikube service grafana -n monitoring --url

# Ou avec port-forward
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Accédez à Grafana via `http://localhost:3000`
- **Username** : admin
- **Password** : admin123

### 5.6 Configurer Grafana avec Prometheus

**Exercice 9 : Ajouter Prometheus comme source de données**

1. Connectez-vous à Grafana
2. Cliquez sur "Configuration" (⚙️) → "Data Sources"
3. Cliquez sur "Add data source"
4. Sélectionnez "Prometheus"
5. Configurez :
   - **URL** : `http://prometheus.monitoring.svc.cluster.local:9090`
   - Cliquez sur "Save & Test"

### 5.7 Créer un Dashboard

**Exercice 10 : Dashboard personnalisé**

1. Cliquez sur "+" → "Dashboard" → "Add new panel"
2. Dans "Query", sélectionnez "Prometheus"
3. Entrez une requête PromQL :
   ```promql
   sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)
   ```
4. Configurez la visualisation (Graph, Gauge, Table, etc.)
5. Définissez un titre : "CPU Usage per Pod (cores)"
6. Cliquez sur "Apply"
7. Ajoutez d'autres panels :
   - Mémoire : `sum(container_memory_usage_bytes{container!="",container!="POD"}) by (pod, namespace)`
   - Réseau reçu : `sum(rate(container_network_receive_bytes_total{container!="",container!="POD"}[5m])) by (pod, namespace)`
   - Réseau transmis : `sum(rate(container_network_transmit_bytes_total{container!="",container!="POD"}[5m])) by (pod, namespace)`

8. Sauvegardez le dashboard : "Save dashboard" (💾)

### 5.8 Importer des dashboards pré-configurés

**Exercice 11 : Importer un dashboard**

1. Dans Grafana, cliquez sur "+" → "Import"
2. Entrez un ID de dashboard (ex: **315** pour Kubernetes cluster monitoring)
3. Cliquez sur "Load"
4. Sélectionnez la source de données Prometheus
5. Cliquez sur "Import"

**Dashboards recommandés** :
- **315** : Kubernetes cluster monitoring (Prometheus)
- **747** : Kubernetes Deployment metrics
- **6417** : Kubernetes Cluster (Prometheus)
- **8588** : Kubernetes Deployment Statefulset Daemonset metrics

## Partie 6 : Application instrumentée

### 6.1 Application avec métriques Prometheus

Créer `06-instrumented-app.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: monitoring
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: quay.io/brancz/prometheus-example-app:v0.6.0
        ports:
        - containerPort: 8080
          name: metrics
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: monitoring
spec:
  selector:
    app: demo-app
  ports:
  - port: 8080
    targetPort: 8080
```

**Exercice 12 : Déployer et monitorer l'application**

```bash
# Déployer l'application
kubectl apply -f 06-instrumented-app.yaml

# Vérifier le déploiement
kubectl get pods -n monitoring -l app=demo-app

# Accéder aux métriques
kubectl port-forward -n monitoring svc/demo-app 8080:8080 &
curl http://localhost:8080/metrics
pkill -f "port-forward.*8080"

# Dans Prometheus (après quelques minutes), vérifier que les métriques sont collectées
# Requête : up{job="kubernetes-pods", app="demo-app"}
```

Dans Grafana, créez un panel avec :
```promql
rate(http_requests_total{job="kubernetes-pods"}[5m])
```

## Partie 7 : Alerting

### 7.1 Règles d'alerte Prometheus

Créer `07-prometheus-rules.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
  namespace: monitoring
data:
  alert.rules: |
    groups:
    - name: example
      interval: 30s
      rules:
      # Alerte si un pod est down
      - alert: PodDown
        expr: up{job="kubernetes-pods"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} is down"
          description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been down for more than 1 minute."

      # Alerte sur CPU élevé
      - alert: HighCPUUsage
        expr: sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace) > 0.8
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.namespace }}/{{ $labels.pod }}"
          description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has high CPU usage (> 0.8 cores)"

      # Alerte sur mémoire élevée
      - alert: HighMemoryUsage
        expr: container_memory_usage_bytes{pod!=""} > 500000000
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.pod }}"
          description: "Pod {{ $labels.pod }} is using more than 500MB of memory"
```

**Exercice 13 : Configurer les règles d'alerte**

```bash
# Appliquer les règles
kubectl apply -f 07-prometheus-rules.yaml

# Vérifier que la ConfigMap est créée
kubectl get configmap prometheus-rules -n monitoring
```

Maintenant, il faut mettre à jour le déploiement Prometheus pour charger ces règles.

Créer `07-prometheus-with-rules.yaml` (mise à jour du déploiement) :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      containers:
      - name: prometheus
        image: prom/prometheus:v3
        args:
          - '--config.file=/etc/prometheus/prometheus.yml'
          - '--storage.tsdb.path=/prometheus'
          - '--web.console.libraries=/usr/share/prometheus/console_libraries'
          - '--web.console.templates=/usr/share/prometheus/consoles'
          - '--web.enable-lifecycle'
        ports:
        - containerPort: 9090
          name: web
        volumeMounts:
        - name: prometheus-config
          mountPath: /etc/prometheus
        - name: prometheus-rules
          mountPath: /etc/prometheus-rules
        - name: prometheus-storage
          mountPath: /prometheus
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
      volumes:
      - name: prometheus-config
        configMap:
          name: prometheus-config
      - name: prometheus-rules
        configMap:
          name: prometheus-rules
      - name: prometheus-storage
        emptyDir: {}
```

Mettre à jour également la ConfigMap Prometheus pour inclure les règles :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - '/etc/prometheus-rules/alert.rules'

    scrape_configs:
      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)

      - job_name: 'kubernetes-cadvisor'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __metrics_path__
            replacement: /metrics/cadvisor

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

      - job_name: 'kubernetes-service-endpoints'
        kubernetes_sd_configs:
          - role: endpoints
        relabel_configs:
          # Ne garder que les services annotés avec prometheus.io/scrape=true
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          # Utiliser le chemin spécifié dans l'annotation prometheus.io/path (par défaut /metrics)
          - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          # Utiliser le port spécifié dans l'annotation prometheus.io/port
          - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          # Copier les labels du service
          - action: labelmap
            regex: __meta_kubernetes_service_label_(.+)
          # Ajouter le namespace comme label
          - source_labels: [__meta_kubernetes_namespace]
            target_label: kubernetes_namespace
          # Ajouter le nom du service comme label
          - source_labels: [__meta_kubernetes_service_name]
            target_label: kubernetes_name
```

Appliquer les modifications :

```bash
# Appliquer d'abord les règles d'alerte
kubectl apply -f 07-prometheus-rules.yaml

# Mettre à jour la ConfigMap et le déploiement Prometheus avec les règles
kubectl apply -f 07-prometheus-with-rules.yaml

# Attendre que le pod redémarre
kubectl rollout status deployment/prometheus -n monitoring

# Vérifier que Prometheus a bien chargé les règles
kubectl logs -n monitoring -l app=prometheus | grep -i "Loading configuration file"
```

### 7.2 Visualiser les alertes

Dans l'interface Prometheus :
1. Allez dans "Alerts"
2. Vous verrez les règles d'alerte configurées
3. Les alertes actives apparaîtront en rouge

## Partie 8 : Logging avancé — Stack EFK complète

### 8.1 Architecture EFK

La stack EFK centralise les logs de tous les pods du cluster dans une interface unique :

```
┌─────────────────────────────────────────────────────────┐
│  Chaque nœud                                            │
│  ┌──────────┐   /var/log/containers/*.log               │
│  │  Fluentd │──────────────────────────────────────┐    │
│  │ DaemonSet│  collecte + enrichissement metadata  │    │
│  └──────────┘                                      │    │
└────────────────────────────────────────────────────┼────┘
                                                     │
                                                     ▼
                                    ┌─────────────────────────┐
                                    │  Elasticsearch          │
                                    │  namespace: logging     │
                                    │  stockage + indexation  │
                                    └────────────┬────────────┘
                                                 │
                                                 ▼
                                    ┌─────────────────────────┐
                                    │  Kibana                 │
                                    │  namespace: logging     │
                                    │  visualisation + search │
                                    └─────────────────────────┘
```

**Composants** :
- **Elasticsearch** : base de données orientée document, indexe et stocke les logs
- **Fluentd** : agent de collecte déployé en DaemonSet (un pod par nœud), lit les fichiers de logs et les envoie vers Elasticsearch enrichis de métadonnées Kubernetes (pod, namespace, labels)
- **Kibana** : interface web pour explorer, filtrer et visualiser les logs

> **Note** : `xpack.security` est désactivé dans cette configuration pour simplifier le TP. En production, activer l'authentification et le chiffrement TLS.

---

### 8.2 Déployer Elasticsearch

> **Prérequis — `vm.max_map_count`**
>
> Elasticsearch exige que le paramètre noyau `vm.max_map_count` soit ≥ 262144 sur chaque nœud.
> À configurer **avant** de déployer, selon votre environnement :
>
> ```bash
> # minikube
> minikube ssh -- 'sudo sysctl -w vm.max_map_count=262144'
>
> # kind
> docker exec -it $(docker ps -qf name=kind) sysctl -w vm.max_map_count=262144
>
> # kubeadm / bare metal (sur chaque nœud)
> sudo sysctl -w vm.max_map_count=262144
> echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
> sudo sysctl --system
> ```

**Exercice 14 : Déployer Elasticsearch**

```bash
kubectl apply -f 09-elasticsearch.yaml

# Attendre que le pod soit prêt (l'initialisation prend ~60s)
kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=120s

# Vérifier l'état du cluster
kubectl get statefulset elasticsearch -n logging
kubectl get pods -n logging -l app=elasticsearch

# Tester l'API Elasticsearch depuis le cluster
kubectl run curl-test --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- \
  curl -s http://elasticsearch.logging.svc.cluster.local:9200/_cluster/health | head -c 200
```

**✅ Attendu :** `"status":"green"` ou `"status":"yellow"` (nœud unique → yellow est normal)

```bash
# Accès local via port-forward
kubectl port-forward svc/elasticsearch 9200:9200 -n logging &
curl http://localhost:9200/_cluster/health?pretty
```

---

### 8.3 Déployer Kibana

**Exercice 15 : Déployer Kibana**

```bash
kubectl apply -f 10-kibana.yaml

# Attendre que le pod soit prêt (l'initialisation prend ~60s)
kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=120s

# Vérifier
kubectl get deployment kibana -n logging
kubectl get pods -n logging -l app=kibana
```

```bash
# Accès à l'interface Kibana
kubectl port-forward svc/kibana 5601:5601 -n logging
# Ouvrir http://localhost:5601 dans un navigateur
```

---

### 8.4 Déployer Fluentd (connecté à Elasticsearch)

**Exercice 16 : Déployer Fluentd**

```bash
kubectl apply -f 08-fluentd-daemonset.yaml

# Vérifier le DaemonSet (un pod par nœud)
kubectl get daemonset fluentd -n kube-system
kubectl get pods -n kube-system -l app=fluentd

# Vérifier que Fluentd envoie bien vers Elasticsearch (pas d'erreurs)
FLUENTD_POD=$(kubectl get pods -n kube-system -l app=fluentd -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n kube-system $FLUENTD_POD --tail=30

# Vérifier les index créés dans Elasticsearch
kubectl run curl-test --image=curlimages/curl:8.11.1 --rm -it --restart=Never -- \
  curl -s http://elasticsearch.logging.svc.cluster.local:9200/_cat/indices?v
```

**✅ Attendu :** des index `fluentd-kubernetes.*-YYYYMMDD` apparaissent après quelques secondes.

**Erreurs fréquentes :**

```bash
# Si Fluentd ne peut pas joindre Elasticsearch
kubectl describe pod $FLUENTD_POD -n kube-system | grep -A 5 "Events"

# Vérifier la résolution DNS depuis kube-system
kubectl run dns-test --image=busybox:1.37 --rm -it --restart=Never -n kube-system -- \
  nslookup elasticsearch.logging.svc.cluster.local
```

---

### 8.5 Vérifier le pipeline et explorer dans Kibana

**Exercice 17 : Explorer les logs dans Kibana**

```bash
# Accéder à Kibana
kubectl port-forward svc/kibana 5601:5601 -n logging
```

Dans Kibana (`http://localhost:5601`) :

1. **Créer un Data View** : menu ☰ → *Management* → *Data Views* → *Create data view*
   - Name : `fluentd-kubernetes`
   - Index pattern : `fluentd-kubernetes.*`
   - Timestamp field : `@timestamp`
   - Cliquer *Save data view to Kibana*

2. **Explorer les logs** : menu ☰ → *Discover*
   - Sélectionner le Data View `fluentd-kubernetes`
   - Filtrer par namespace : chercher `kubernetes.namespace_name : default`
   - Filtrer par pod : `kubernetes.pod_name : <nom-du-pod>`

3. **Vérifier le pipeline bout-en-bout** :

```bash
# Générer des logs depuis un pod de test
kubectl run log-test --image=busybox:1.37 --restart=Never -- \
  sh -c 'for i in $(seq 1 10); do echo "Log de test $i - $(date)"; sleep 1; done'

# Dans Kibana → Discover, chercher : "Log de test"
# Les logs doivent apparaître dans les secondes qui suivent
```

**Questions :**
1. Quelle est la latence entre l'émission d'un log et son apparition dans Kibana ?
2. Quels champs Kubernetes sont automatiquement ajoutés par le filtre `kubernetes_metadata` ?
3. Comment filtrer les logs d'un seul namespace dans Kibana ?

---

### 8.6 Nettoyage

```bash
kubectl delete -f 08-fluentd-daemonset.yaml
kubectl delete -f 10-kibana.yaml
kubectl delete -f 09-elasticsearch.yaml
kubectl delete namespace logging
```

## Partie 9 : Bonnes pratiques

### 9.1 Monitoring

1. **Définir des SLIs/SLOs**
   - Service Level Indicators : Métriques clés (latence, disponibilité)
   - Service Level Objectives : Objectifs quantifiés (99.9% uptime)

2. **Métriques à surveiller**
   - Utilisation CPU et mémoire
   - Latence des requêtes
   - Taux d'erreur
   - Saturation réseau/disque

3. **Alertes pertinentes**
   - Éviter les fausses alertes
   - Alerter sur les symptômes, pas sur les causes
   - Définir des seuils réalistes
   - Inclure des runbooks dans les alertes

4. **Rétention des données**
   - Définir une politique de rétention
   - Archiver les métriques anciennes
   - Utiliser l'agrégation pour les données historiques

### 9.2 Logging

1. **Niveaux de logs structurés**
   ```
   DEBUG : Informations de débogage détaillées
   INFO  : Événements généraux
   WARN  : Situations potentiellement problématiques
   ERROR : Erreurs nécessitant une attention
   FATAL : Erreurs critiques causant l'arrêt
   ```

2. **Format de logs structuré**
   ```json
   {
     "timestamp": "2025-10-29T10:30:00Z",
     "level": "INFO",
     "service": "api-backend",
     "message": "Request processed",
     "request_id": "abc-123",
     "duration_ms": 45
   }
   ```

3. **Logs à collecter**
   - Logs applicatifs
   - Logs système
   - Logs d'audit
   - Logs de sécurité

4. **Rotation des logs**
   - Limiter la taille des logs
   - Archiver les logs anciens
   - Utiliser logrotate

### 9.3 Ressources

```yaml
# Toujours définir des resource requests et limits
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

## Partie 10 : Exercices pratiques complets

### Exercice Final 1 : Monitoring d'une application web

**Mission** : Déployer une application web complète avec monitoring

1. Déployez une application (nginx, redis, postgresql)
2. Configurez Prometheus pour collecter les métriques
3. Créez un dashboard Grafana avec :
   - CPU et mémoire par service
   - Nombre de pods par service
   - Latence des requêtes (si disponible)
4. Configurez des alertes pour :
   - Pod down
   - CPU > 80%
   - Mémoire > 90%

### Exercice Final 2 : Debugging avec les logs

**Scénario** : Une application crash régulièrement

1. Déployez cette application buggy :

```bash
kubectl apply -f 09-buggy-app.yaml
```

2. Analysez les logs pour identifier le problème
3. Utilisez `kubectl describe` pour voir les événements
4. Corrigez l'application (ajoutez un restart loop)
5. Vérifiez que l'application redémarre automatiquement

### Exercice Final 3 : Dashboard personnalisé

Créez un dashboard Grafana complet pour votre cluster :

1. **Panel 1** : Cluster overview
   - Nombre de nœuds
   - Nombre total de pods
   - Pods par namespace

2. **Panel 2** : Ressources
   - CPU total utilisé vs disponible
   - Mémoire totale utilisée vs disponible

3. **Panel 3** : Top pods
   - Top 10 pods par CPU
   - Top 10 pods par mémoire

4. **Panel 4** : Network
   - Bande passante entrante
   - Bande passante sortante

5. **Panel 5** : Alerts
   - Nombre d'alertes actives
   - Liste des alertes

## Partie 11 : Nettoyage

```bash
# Supprimer les déploiements de test
kubectl delete deployment nginx-test
kubectl delete deployment php-apache
kubectl delete hpa php-apache-hpa
kubectl delete service php-apache
kubectl delete deployment log-generator
kubectl delete pod multi-log-pod

# Supprimer le namespace monitoring (supprime tout dedans)
kubectl delete namespace monitoring

# Désactiver les addons (optionnel)
minikube addons disable metrics-server
minikube addons disable dashboard

# Vérifier
kubectl get all -n monitoring
```

## Résumé

Dans ce TP, vous avez appris à :

- Installer et utiliser Metrics Server
- Configurer l'autoscaling horizontal (HPA)
- Utiliser le Dashboard Kubernetes
- Collecter et analyser les logs avec kubectl
- Déployer Prometheus pour la collecte de métriques
- Créer des dashboards avec Grafana
- Configurer des alertes
- Appliquer les bonnes pratiques de monitoring

### Concepts clés

- **Métriques** : Données numériques sur l'état du système
- **Logs** : Enregistrements d'événements
- **Prometheus** : Système de monitoring time-series
- **Grafana** : Plateforme de visualisation
- **HPA** : Autoscaling basé sur les métriques
- **PromQL** : Langage de requête Prometheus
- **Alerting** : Notification sur conditions définies

## Ressources complémentaires

### Documentation officielle

- [Kubernetes Monitoring Architecture](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Logging](https://kubernetes.io/docs/concepts/cluster-administration/logging/)

### Guides avancés

- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [EFK Stack Installation](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Loki (alternative à EFK)](https://grafana.com/docs/loki/latest/)
- [Jaeger (Distributed Tracing)](https://www.jaegertracing.io/docs/)

### Dashboards Grafana

- [Grafana Dashboard Repository](https://grafana.com/grafana/dashboards/)
- Dashboard ID 315 : Kubernetes cluster monitoring
- Dashboard ID 747 : Kubernetes Deployment metrics
- Dashboard ID 6417 : Kubernetes Cluster

### Outils complémentaires

- **kube-state-metrics** : Métriques sur l'état des ressources K8s
  - Fournit des métriques comme `kube_pod_info`, `kube_deployment_status_replicas`, etc.
  - Installation : `kubectl apply -f https://github.com/kubernetes/kube-state-metrics/releases/download/v2.10.0/standard.yaml`
  - Nécessite d'ajouter un scrape config dans Prometheus pour le job `kube-state-metrics`

- **node-exporter** : Métriques hardware et OS
  - Fournit des métriques détaillées sur les nœuds (CPU, disque, réseau, etc.)
  - Déployé généralement via un DaemonSet

- **Alertmanager** : Gestion avancée des alertes
  - Permet de router, grouper et gérer les notifications d'alertes
  - Intégration avec Slack, Email, PagerDuty, etc.

- **Thanos** : Stockage long terme pour Prometheus
  - Permet de conserver les métriques sur de longues périodes
  - Offre une vue unifiée de plusieurs instances Prometheus

## Prochaines étapes

Félicitations ! Vous maîtrisez maintenant le monitoring et la gestion des logs dans Kubernetes.

Continuez votre apprentissage avec :
- **TP5** (à venir) : Mise en production et bonnes pratiques
- **Helm** : Gestionnaire de packages Kubernetes
- **GitOps** : Déploiement continu avec ArgoCD/Flux
- **Service Mesh** : Istio, Linkerd

## Questions de révision

1. Quelle est la différence entre Metrics Server et Prometheus ?
2. Comment fonctionne l'Horizontal Pod Autoscaler ?
3. Quels sont les trois piliers de l'observabilité ?
4. Comment voir les logs d'un conteneur qui a crashé ?
5. Qu'est-ce que PromQL ?
6. Pourquoi utiliser Grafana en plus de Prometheus ?
7. Quelle est la différence entre logs et métriques ?
8. Comment configurer une alerte dans Prometheus ?

## Solutions des questions

<details>
<summary>Cliquez pour voir les réponses</summary>

1. Metrics Server collecte uniquement CPU/mémoire pour kubectl top et HPA. Prometheus collecte des métriques plus détaillées avec rétention et requêtes avancées.
2. HPA surveille les métriques (CPU, mémoire, custom) et ajuste automatiquement le nombre de replicas entre min et max définis.
3. Métriques (données numériques agrégées), Logs (événements), Traces (suivi de requêtes distribuées).
4. `kubectl logs <pod-name> --previous` pour voir les logs du conteneur précédent avant le crash.
5. Prometheus Query Language : langage de requête pour interroger les métriques time-series.
6. Grafana offre une meilleure visualisation, des dashboards personnalisables, et peut agréger plusieurs sources de données.
7. Logs = événements discrets avec contexte. Métriques = valeurs numériques agrégées dans le temps.
8. Créer une ConfigMap avec des règles d'alerte en YAML, la monter dans Prometheus, et définir expr, for, labels, annotations.

</details>

---

**Durée estimée du TP :** 6-8 heures
**Niveau :** Intermédiaire/Avancé

**Excellent travail ! Vous êtes maintenant prêt à monitorer efficacement vos clusters Kubernetes !**
