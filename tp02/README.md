# TP2 - Maîtriser les Manifests Kubernetes

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Comprendre la structure des fichiers YAML Kubernetes
- Écrire vos propres manifests pour différentes ressources
- Valider et tester vos configurations YAML
- Utiliser les labels et selectors efficacement
- Gérer la configuration avec ConfigMaps et Secrets
- Appliquer les bonnes pratiques de rédaction de manifests

## Prérequis

- Avoir complété le TP1
- Un cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)
- Un éditeur de texte (vim, nano, VS Code, etc.)

**Note :** Les manifests YAML sont identiques que vous utilisiez minikube ou kubeadm. Les différences se situent uniquement au niveau de l'accès aux services (voir TP1, Partie 5.2).

## Partie 1 : Anatomie d'un manifest Kubernetes

### 1.1 Structure de base

Tous les manifests Kubernetes suivent la même structure de base :

```yaml
apiVersion: <groupe>/<version>  # Version de l'API Kubernetes
kind: <Type>                    # Type de ressource
metadata:                       # Métadonnées
  name: <nom>
  labels:
    key: value
spec:                          # Spécification de la ressource
  # Configuration spécifique au type
```

### 1.2 Les champs essentiels

**apiVersion** : Détermine quelle version de l'API utiliser
- `v1` : pour Pod, Service, ConfigMap, Secret
- `apps/v1` : pour Deployment, StatefulSet, DaemonSet
- `batch/v1` : pour Job, CronJob

**kind** : Type de ressource à créer
- Pod, Service, Deployment, ConfigMap, Secret, etc.

**metadata** : Informations sur la ressource
- `name` : Nom unique dans le namespace
- `labels` : Paires clé-valeur pour identifier et sélectionner les ressources
- `namespace` : Namespace où créer la ressource (défaut: default)
- `annotations` : Métadonnées non-identifiantes

**spec** : Définit l'état désiré de la ressource

### 1.3 Validation d'un manifest

```bash
# Vérifier la syntaxe sans créer la ressource
kubectl apply -f mon-fichier.yaml --dry-run=client

# Valider côté serveur
kubectl apply -f mon-fichier.yaml --dry-run=server

# Afficher le YAML d'une ressource existante
kubectl get deployment nginx-demo -o yaml

# Expliquer la structure d'une ressource
kubectl explain pod
kubectl explain pod.spec
kubectl explain pod.spec.containers
```

## Partie 2 : Les Pods - La plus petite unité

### 2.1 Pod simple

Créer un fichier `01-simple-pod.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
    env: dev
spec:
  containers:
  - name: nginx
    image: nginx:1.24
    ports:
    - containerPort: 80
```

**Exercice 1 : Votre premier Pod**

1. Créez le fichier ci-dessus
2. Validez-le avec `--dry-run=client`
3. Appliquez-le avec `kubectl apply`
4. Vérifiez son statut avec `kubectl get pods`
5. Consultez ses détails avec `kubectl describe pod nginx-pod`

```bash
# Commandes à exécuter
kubectl apply -f 01-simple-pod.yaml --dry-run=client
kubectl apply -f 01-simple-pod.yaml
kubectl get pods
kubectl describe pod nginx-pod
```

### 2.2 Pod avec ressources limitées

Créer `02-pod-with-resources.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp-pod
  labels:
    app: webapp
spec:
  containers:
  - name: webapp
    image: httpd:2.4
    ports:
    - containerPort: 80
    resources:
      requests:      # Ressources minimales garanties
        memory: "64Mi"
        cpu: "250m"
      limits:        # Ressources maximales
        memory: "128Mi"
        cpu: "500m"
```

**Exercice 2 : Pod avec contraintes de ressources**

1. Créez ce fichier
2. Appliquez-le
3. Vérifiez les ressources allouées : `kubectl describe pod webapp-pod`
4. Observez la section "Requests" et "Limits"

### 2.3 Pod multi-conteneurs

Créer `03-multi-container-pod.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-pod
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html

  - name: content-generator
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "Hello from Kubernetes - $(date)" > /data/index.html;
          sleep 10;
        done
    volumeMounts:
    - name: shared-data
      mountPath: /data

  volumes:
  - name: shared-data
    emptyDir: {}
```

**Exercice 3 : Pod avec sidecar**

1. Créez et appliquez ce manifest
2. Vérifiez que les 2 conteneurs tournent : `kubectl get pod multi-container-pod`
3. Consultez les logs de chaque conteneur :
   ```bash
   kubectl logs multi-container-pod -c nginx
   kubectl logs multi-container-pod -c content-generator
   ```
4. Testez l'application avec un port-forward :
   ```bash
   kubectl port-forward pod/multi-container-pod 8080:80
   curl localhost:8080
   ```

## Partie 3 : Deployments - Gestion des réplicas

### 3.1 Deployment de base

Créer `04-deployment-basic.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  labels:
    app: web
spec:
  replicas: 3
  selector:
    matchLabels:      # DOIT correspondre aux labels du template
      app: web
      env: prod
  template:           # Template du Pod
    metadata:
      labels:
        app: web
        env: prod
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        ports:
        - containerPort: 80
```

**Exercice 4 : Déploiement avec réplicas**

1. Créez ce deployment
2. Vérifiez les pods créés : `kubectl get pods -l app=web`
3. Supprimez un pod manuellement et observez la recréation automatique
4. Modifiez le nombre de replicas dans le fichier à 5
5. Réappliquez : `kubectl apply -f 04-deployment-basic.yaml`

### 3.2 Deployment avec stratégie de mise à jour

Créer `05-deployment-strategy.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rolling-deployment
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Nombre de pods supplémentaires pendant la mise à jour
      maxUnavailable: 1  # Nombre de pods indisponibles pendant la mise à jour
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
        image: nginx:1.24
        ports:
        - containerPort: 80
        livenessProbe:    # Vérification que le conteneur est vivant
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:   # Vérification que le conteneur est prêt
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

**Exercice 5 : Rolling Update**

1. Créez ce deployment
2. Surveillez les pods : `kubectl get pods -l app=rolling-app -w`
3. Dans un autre terminal, mettez à jour l'image :
   ```bash
   kubectl set image deployment/rolling-deployment app=nginx:1.25
   ```
4. Observez le rolling update en cours
5. Consultez l'historique : `kubectl rollout history deployment/rolling-deployment`
6. Effectuez un rollback : `kubectl rollout undo deployment/rolling-deployment`

### 3.3 Historisation des versions (Revision History)

Kubernetes maintient automatiquement un historique des révisions de vos Deployments. Cet historique vous permet de :
- **Consulter** les changements appliqués au fil du temps
- **Revenir** à une version antérieure en cas de problème
- **Auditer** les modifications apportées

#### 3.3.1 Consulter l'historique des révisions

```bash
# Afficher l'historique complet d'un deployment
kubectl rollout history deployment/rolling-deployment

# Résultat exemple :
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         kubectl set image deployment/rolling-deployment app=nginx:1.25
# 3         kubectl set image deployment/rolling-deployment app=nginx:1.24
```

**Astuce** : Pour que la colonne `CHANGE-CAUSE` soit remplie automatiquement, utilisez l'annotation `kubernetes.io/change-cause` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rolling-deployment
  annotations:
    kubernetes.io/change-cause: "Déploiement initial avec nginx 1.24"
spec:
  # ... reste de la configuration
```

Ou ajoutez-la lors de l'application :
```bash
kubectl apply -f deployment.yaml --record  # ⚠️ Option deprecated mais encore utilisée
# Ou mieux, utilisez l'annotation directement dans le manifest
```

#### 3.3.2 Détails d'une révision spécifique

Pour voir les détails d'une révision particulière :

```bash
# Afficher les détails de la révision 2
kubectl rollout history deployment/rolling-deployment --revision=2

# Résultat : affiche la configuration complète du Deployment à cette révision
```

Cette commande vous montre :
- La configuration complète du Pod template
- Les images utilisées
- Les variables d'environnement
- Les annotations et labels

#### 3.3.3 Le paramètre `revisionHistoryLimit`

Par défaut, Kubernetes conserve les **10 dernières révisions** d'un Deployment. Ce nombre est configurable via le paramètre `revisionHistoryLimit` dans le spec du Deployment.

**Exemple avec limite d'historique personnalisée** :

Créer `05b-deployment-revision-history.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-history
  annotations:
    kubernetes.io/change-cause: "Déploiement initial v1.0"
spec:
  replicas: 3
  revisionHistoryLimit: 5  # Conserve seulement les 5 dernières révisions

  selector:
    matchLabels:
      app: history-app

  template:
    metadata:
      labels:
        app: history-app
        version: v1.0
    spec:
      containers:
      - name: app
        image: nginx:1.24
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```

**Impact de `revisionHistoryLimit` :**

| Valeur | Comportement | Cas d'usage |
|--------|--------------|-------------|
| `0` | Aucun historique conservé | ❌ Déconseillé - impossible de faire un rollback |
| `1-3` | Historique minimal | Environnements de dev/test avec peu d'espace |
| `5-10` | Historique standard | ⭐ Recommandé pour la plupart des cas |
| `15-20` | Historique étendu | Production critique avec besoin d'audit |
| `>20` | Historique très étendu | ⚠️ Peut consommer beaucoup de ressources etcd |

#### 3.3.4 Exercice pratique : Gestion de l'historique

**Exercice 5b : Manipuler l'historique des révisions**

1. **Créez le deployment avec historique limité** :
   ```bash
   kubectl apply -f 05b-deployment-revision-history.yaml
   ```

2. **Effectuez plusieurs mises à jour** en changeant l'annotation `change-cause` :
   ```bash
   # Mise à jour 1
   kubectl set image deployment/app-with-history app=nginx:1.25
   kubectl annotate deployment/app-with-history \
     kubernetes.io/change-cause="Mise à jour vers nginx 1.25" --overwrite

   # Mise à jour 2
   kubectl set image deployment/app-with-history app=nginx:1.26
   kubectl annotate deployment/app-with-history \
     kubernetes.io/change-cause="Mise à jour vers nginx 1.26" --overwrite

   # Mise à jour 3
   kubectl set image deployment/app-with-history app=nginx:alpine
   kubectl annotate deployment/app-with-history \
     kubernetes.io/change-cause="Migration vers nginx alpine" --overwrite
   ```

3. **Consultez l'historique** :
   ```bash
   kubectl rollout history deployment/app-with-history
   ```

   Résultat attendu :
   ```
   REVISION  CHANGE-CAUSE
   1         Déploiement initial v1.0
   2         Mise à jour vers nginx 1.25
   3         Mise à jour vers nginx 1.26
   4         Migration vers nginx alpine
   ```

4. **Examinez une révision spécifique** :
   ```bash
   kubectl rollout history deployment/app-with-history --revision=2
   ```

5. **Revenez à une révision précédente** :
   ```bash
   # Revenir à la révision 2 (nginx:1.25)
   kubectl rollout undo deployment/app-with-history --to-revision=2

   # Vérifier que le rollback s'est bien effectué
   kubectl rollout history deployment/app-with-history
   kubectl describe deployment app-with-history | grep Image
   ```

6. **Testez la limite d'historique** :
   ```bash
   # Effectuez 10 nouvelles mises à jour
   for i in {1..10}; do
     kubectl set image deployment/app-with-history app=nginx:1.24
     kubectl set image deployment/app-with-history app=nginx:1.25
   done

   # Vérifiez que seules les 5 dernières révisions sont conservées
   kubectl rollout history deployment/app-with-history
   # Vous devriez voir seulement 5 révisions
   ```

#### 3.3.5 Modifier la limite d'historique d'un Deployment existant

Pour modifier `revisionHistoryLimit` sur un Deployment existant :

**Méthode 1 : Via kubectl patch**
```bash
kubectl patch deployment rolling-deployment \
  -p '{"spec":{"revisionHistoryLimit":15}}'
```

**Méthode 2 : Via kubectl edit**
```bash
kubectl edit deployment rolling-deployment
# Modifiez la ligne revisionHistoryLimit dans l'éditeur
```

**Méthode 3 : Via le fichier YAML**
```bash
# Modifiez le fichier YAML en ajoutant/changeant revisionHistoryLimit
# Puis réappliquez :
kubectl apply -f deployment.yaml
```

#### 3.3.6 Bonnes pratiques pour l'historique

✅ **Recommandations** :

1. **Définir une limite appropriée** selon l'environnement :
   ```yaml
   # Développement
   revisionHistoryLimit: 3

   # Staging
   revisionHistoryLimit: 5

   # Production
   revisionHistoryLimit: 10
   ```

2. **Toujours documenter les changements** avec `change-cause` :
   ```yaml
   metadata:
     annotations:
       kubernetes.io/change-cause: "Fix bug #1234 - correction du timeout"
   ```

3. **Surveiller l'utilisation d'etcd** :
   ```bash
   # Vérifier la taille totale des révisions
   kubectl get replicasets -l app=history-app
   ```

4. **Nettoyer les anciennes révisions manuellement** si nécessaire :
   ```bash
   # Réduire temporairement la limite pour forcer le nettoyage
   kubectl patch deployment app-with-history -p '{"spec":{"revisionHistoryLimit":2}}'

   # Les anciennes révisions seront automatiquement supprimées
   ```

5. **Automatiser les rollbacks avec des critères** :
   - Utiliser des health checks (liveness/readiness probes)
   - Mettre en place des alertes de monitoring
   - Considérer l'utilisation de Flagger pour les rollbacks automatiques

❌ **À éviter** :

- `revisionHistoryLimit: 0` en production (impossible de rollback)
- Valeurs trop élevées (>20) sans justification (consommation mémoire etcd)
- Négliger les annotations `change-cause` (historique illisible)
- Effectuer trop de déploiements successifs sans validation

#### 3.3.7 Cas d'usage avancés

**Stratégie de rollback automatique avec timeout** :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auto-rollback-app
spec:
  replicas: 3
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600  # Si le déploiement prend > 10 min, il est marqué comme failed

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime

  selector:
    matchLabels:
      app: auto-rollback

  template:
    metadata:
      labels:
        app: auto-rollback
    spec:
      containers:
      - name: app
        image: nginx:1.24
        readinessProbe:  # Crucial pour détecter les déploiements problématiques
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
```

**Monitoring des révisions** :

```bash
# Créer un script de surveillance
cat > watch-revisions.sh << 'EOF'
#!/bin/bash
DEPLOYMENT=$1

while true; do
  echo "=== $(date) ==="
  echo "Révisions actuelles :"
  kubectl rollout history deployment/$DEPLOYMENT
  echo ""
  echo "Statut du déploiement :"
  kubectl rollout status deployment/$DEPLOYMENT
  echo "================================"
  sleep 30
done
EOF

chmod +x watch-revisions.sh
./watch-revisions.sh rolling-deployment
```

## Partie 4 : Services - Exposition des applications

### 4.1 Service ClusterIP

Créer `06-service-clusterip.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-service
spec:
  type: ClusterIP    # Accessible uniquement dans le cluster
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80         # Port du service
    targetPort: 80   # Port du conteneur
```

### 4.2 Service NodePort

Créer `07-service-nodeport.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-service
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080  # Port accessible sur chaque nœud (30000-32767)
```

### 4.3 Service avec annotations

Créer `08-service-complete.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-service
  annotations:
    description: "Service principal de l'application"
  labels:
    env: production
spec:
  type: NodePort
  selector:
    app: web
    env: prod
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80
  sessionAffinity: ClientIP  # Maintenir la session sur le même pod
```

**Exercice 6 : Création de services**

1. Créez les trois types de services ci-dessus
2. Vérifiez avec : `kubectl get services`
3. Testez l'accès au service NodePort :

   **Avec minikube :**
   ```bash
   curl http://$(minikube ip):30080
   ```

   **Avec kubeadm :**
   ```bash
   # Récupérer l'IP d'un nœud
   NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
   curl http://$NODE_IP:30080
   ```

4. Affichez les endpoints : `kubectl get endpoints`
5. Décrivez le service : `kubectl describe service app-service`

## Partie 5 : ConfigMaps et Secrets

### 5.1 ConfigMap simple

Créer `09-configmap.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  # Données de configuration sous forme clé-valeur
  database_url: "postgres://db:5432/myapp"
  log_level: "info"
  max_connections: "100"

  # Configuration multi-lignes
  app.conf: |
    server {
      listen 80;
      server_name localhost;

      location / {
        root /usr/share/nginx/html;
        index index.html;
      }
    }
```

### 5.2 Secret

Créer `10-secret.yaml` :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
type: Opaque
stringData:  # Les données seront automatiquement encodées en base64
  username: admin
  password: supersecret123
  api-key: abcd1234efgh5678
```

### 5.3 Pod utilisant ConfigMap et Secret

Créer `11-pod-with-config.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: configured-app
spec:
  containers:
  - name: app
    image: nginx:alpine

    # Variables d'environnement depuis ConfigMap
    env:
    - name: DATABASE_URL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: database_url

    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: log_level

    # Variables d'environnement depuis Secret
    - name: USERNAME
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: username

    - name: PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secret
          key: password

    # Monter le ConfigMap comme volume
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config

    # Monter le Secret comme volume
    - name: secret-volume
      mountPath: /etc/secret
      readOnly: true

  volumes:
  - name: config-volume
    configMap:
      name: app-config

  - name: secret-volume
    secret:
      secretName: app-secret
```

**Exercice 7 : Configuration externalisée**

1. Créez le ConfigMap et le Secret
2. Créez le Pod qui les utilise
3. Vérifiez les variables d'environnement :
   ```bash
   kubectl exec configured-app -- env | grep -E "(DATABASE_URL|USERNAME)"
   ```
4. Vérifiez les fichiers montés :
   ```bash
   kubectl exec configured-app -- ls /etc/config
   kubectl exec configured-app -- cat /etc/config/app.conf
   kubectl exec configured-app -- ls /etc/secret
   ```

### 5.4 ⚠️ LIMITES DE SÉCURITÉ DES SECRETS KUBERNETES

**IMPORTANT :** Les Secrets Kubernetes ne sont PAS une solution de sécurité robuste par défaut. Voici les limites critiques à connaître :

#### 5.4.1 Encodage vs Chiffrement

```bash
# Les Secrets sont encodés en base64, PAS chiffrés
echo "supersecret123" | base64
# Résultat : c3VwZXJzZWNyZXQxMjM=

# Ils peuvent être décodés facilement
echo "c3VwZXJzZWNyZXQxMjM=" | base64 -d
# Résultat : supersecret123
```

**⚠️ Risque :** N'importe qui ayant accès au manifest YAML peut décoder les secrets encodés en base64.

#### 5.4.2 Stockage en clair dans etcd

**Par défaut**, les Secrets sont stockés **en clair** dans etcd (la base de données de Kubernetes).

```bash
# Vérifier si l'encryption at rest est activée
kubectl get secret app-secret -o yaml

# Le champ 'data' contient les valeurs en base64 seulement
```

**⚠️ Risque :**
- Toute personne ayant accès à etcd peut lire tous les secrets
- Les backups etcd contiennent les secrets en clair
- Un compromis du serveur etcd expose tous les secrets

**Solution :** Activer l'[Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) dans la configuration du cluster.

#### 5.4.3 Accès via l'API Kubernetes

```bash
# Toute personne avec les permissions RBAC appropriées peut lire les secrets
kubectl get secret app-secret -o yaml
kubectl get secret app-secret -o jsonpath='{.data.password}' | base64 -d
```

**⚠️ Risque :**
- Un compte de service compromis avec les bonnes permissions peut lire tous les secrets
- Les permissions par défaut peuvent être trop permissives

**Bonnes pratiques :**
```yaml
# Limiter l'accès aux secrets avec RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-secret"]  # Limiter à des secrets spécifiques
  verbs: ["get"]
```

#### 5.4.4 Secrets montés comme volumes

Quand un Secret est monté comme volume dans un Pod :

```bash
# Le secret est écrit en clair sur le disque du nœud
kubectl exec configured-app -- cat /etc/secret/password
# Affiche : supersecret123
```

**⚠️ Risques :**
- Les fichiers sont visibles sur le système de fichiers du nœud (dans `/var/lib/kubelet/pods/...`)
- Un accès SSH au nœud permet de lire les secrets
- Les secrets restent sur le disque même après la suppression du Pod

#### 5.4.5 Secrets dans les variables d'environnement

```yaml
env:
- name: PASSWORD
  valueFrom:
    secretKeyRef:
      name: app-secret
      key: password
```

**⚠️ Risques CRITIQUES :**
- Les variables d'environnement sont visibles dans `kubectl describe pod`
- Elles apparaissent dans les logs système et d'audit
- Les processus enfants héritent des variables d'environnement
- Elles peuvent être loguées involontairement par l'application

```bash
# Les variables d'environnement sont visibles !
kubectl exec configured-app -- env | grep PASSWORD
# Affiche : PASSWORD=supersecret123

# Elles apparaissent aussi dans describe
kubectl describe pod configured-app
# On peut voir les références aux secrets (mais pas les valeurs directement)
```

**Recommandation :** Préférer les volumes aux variables d'environnement pour les secrets sensibles.

#### 5.4.6 Secrets dans Git

**❌ JAMAIS faire cela :**
```yaml
# Ne JAMAIS commiter ce fichier dans Git !
apiVersion: v1
kind: Secret
metadata:
  name: bad-secret
stringData:
  password: "supersecret123"  # Visible dans l'historique Git !
```

**⚠️ Risques :**
- Une fois dans Git, le secret reste dans l'historique même si supprimé
- Les forks et clones du dépôt contiennent le secret
- Les outils d'analyse de code peuvent détecter et signaler les secrets

**Bonnes pratiques :**
```bash
# Ajouter les fichiers de secrets au .gitignore
echo "*-secret.yaml" >> .gitignore
echo "secrets/" >> .gitignore
```

#### 5.4.7 Solutions alternatives plus sécurisées

Pour une sécurité renforcée, considérez ces solutions :

**1. Sealed Secrets (Bitnami)**
```bash
# Les secrets sont chiffrés et peuvent être stockés dans Git
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: mysecret
spec:
  encryptedData:
    password: AgBpDH7X9k2... # Chiffré, safe pour Git
```

**2. External Secrets Operator**
```yaml
# Synchronise les secrets depuis un gestionnaire externe
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secret
spec:
  secretStoreRef:
    name: vault-backend
  target:
    name: app-secret
  data:
  - secretKey: password
    remoteRef:
      key: secret/data/myapp
      property: password
```

**3. HashiCorp Vault**
- Gestionnaire de secrets dédié
- Chiffrement, rotation automatique, audit
- Intégration avec Kubernetes via CSI driver

**4. Cloud Provider Secret Managers**
- AWS Secrets Manager
- Azure Key Vault
- Google Secret Manager

#### 5.4.8 Checklist de sécurité pour les Secrets

Avant d'utiliser un Secret en production :

- [ ] ❌ Ne pas commiter les Secrets dans Git
- [ ] ✅ Activer l'encryption at rest dans etcd
- [ ] ✅ Utiliser RBAC pour limiter l'accès aux Secrets
- [ ] ✅ Préférer les volumes aux variables d'environnement
- [ ] ✅ Auditer régulièrement les accès aux Secrets
- [ ] ✅ Utiliser des namespaces pour l'isolation
- [ ] ✅ Considérer des solutions externes (Vault, Sealed Secrets)
- [ ] ✅ Activer les logs d'audit Kubernetes
- [ ] ✅ Rotation régulière des secrets
- [ ] ✅ Scanner les dépôts Git pour détecter les secrets exposés

#### 5.4.9 Exemple de vérification de sécurité

```bash
# Vérifier les permissions sur les secrets
kubectl auth can-i get secrets --as=system:serviceaccount:default:default

# Lister tous les secrets dans un namespace
kubectl get secrets -n default

# Auditer qui a accès aux secrets
kubectl get rolebindings,clusterrolebindings -A -o json | \
  jq '.items[] | select(.roleRef.kind=="Role" or .roleRef.kind=="ClusterRole") |
  select(.subjects[]?.kind=="ServiceAccount")'

# Vérifier si l'encryption at rest est configurée
# (nécessite l'accès au serveur API)
kubectl get configmap -n kube-system kube-apiserver-config -o yaml | grep -i encrypt
```

#### 5.4.10 Résumé des risques

| Risque | Niveau | Mitigation |
|--------|--------|------------|
| Secrets en base64 seulement | 🔴 Critique | Utiliser des solutions de chiffrement |
| Stockage en clair dans etcd | 🔴 Critique | Activer encryption at rest |
| Accès via API K8s | 🟡 Moyen | RBAC strict + audit |
| Secrets dans variables env | 🟡 Moyen | Préférer les volumes |
| Secrets dans Git | 🔴 Critique | .gitignore + Git scanning |
| Secrets sur disque nœud | 🟡 Moyen | Sécuriser l'accès SSH aux nœuds |

**Conclusion :** Les Secrets Kubernetes sont un mécanisme de base pour gérer les données sensibles, mais ils nécessitent des mesures de sécurité supplémentaires pour une utilisation en production. Pour des environnements critiques, privilégiez des solutions dédiées comme Vault ou les gestionnaires de secrets cloud.

## Partie 6 : Labels et Selectors - Maîtrise complète

### 6.1 Introduction aux labels

Les **labels** sont des paires clé-valeur attachées aux objets Kubernetes (Pods, Services, Deployments, etc.). Ils sont fondamentaux pour :
- **Organiser** : Grouper et catégoriser les ressources
- **Sélectionner** : Identifier des ensembles de ressources
- **Connecter** : Lier les Services aux Pods, les Deployments aux Pods, etc.
- **Filtrer** : Interroger et manipuler des groupes de ressources

**Syntaxe et contraintes :**
```yaml
labels:
  key: value              # Format de base
  app: nginx              # Nom d'application
  env: production         # Environnement
  version: v1.2.3         # Version
  tier: frontend          # Tier architectural
```

**Règles de nommage :**
- Clés : max 63 caractères (préfixe optionnel jusqu'à 253 caractères + `/`)
- Valeurs : max 63 caractères
- Caractères autorisés : alphanumériques, `-`, `_`, `.`
- Doit commencer et finir par un caractère alphanumérique

### 6.2 matchLabels : Sélection simple

`matchLabels` effectue une correspondance **exacte** sur toutes les paires clé-valeur spécifiées (AND logique).

**Exemple 1 : Deployment avec matchLabels simple**

Créer `12a-deployment-matchlabels.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-deployment
  labels:
    app: webapp
    tier: frontend
spec:
  replicas: 3
  selector:
    matchLabels:      # Sélection EXACTE
      app: webapp     # Le pod DOIT avoir app=webapp
      tier: frontend  # ET tier=frontend
  template:
    metadata:
      labels:
        app: webapp
        tier: frontend
        version: v1.0.0      # Labels supplémentaires OK
        environment: prod    # mais matchLabels doit correspondre
    spec:
      containers:
      - name: webapp
        image: nginx:1.24
        ports:
        - containerPort: 80
        # Contexte de sécurité
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: webapp-service
spec:
  selector:
    app: webapp       # Sélectionne TOUS les pods avec app=webapp
    tier: frontend    # ET tier=frontend
  ports:
  - port: 80
    targetPort: 80
```

**⚠️ Règle CRITIQUE :** Les labels du `selector.matchLabels` **DOIVENT** être un sous-ensemble des labels du `template.metadata.labels`. Sinon, le Deployment ne pourra pas gérer ses Pods.

**Exemple d'erreur courante :**
```yaml
spec:
  selector:
    matchLabels:
      app: webapp      # ❌ ERREUR !
  template:
    metadata:
      labels:
        app: different-name  # Ne correspond pas !
```

### 6.3 matchExpressions : Sélection avancée

`matchExpressions` permet des sélections plus complexes avec des opérateurs avancés.

**Syntaxe :**
```yaml
selector:
  matchExpressions:
  - key: <label-key>
    operator: <In|NotIn|Exists|DoesNotExist>
    values: [<val1>, <val2>, ...]  # Requis pour In et NotIn, interdit pour Exists et DoesNotExist
```

### 6.4 Les 4 opérateurs de matchExpressions

#### Opérateur 1 : `In`
Sélectionne les ressources où la clé existe ET la valeur est dans la liste.

**Exemple : Déploiement multi-environnements**

Créer `12b-matchexpressions-in.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-env-app
spec:
  replicas: 3
  selector:
    matchExpressions:
    - key: environment
      operator: In
      values: ["staging", "production"]  # Pods avec env=staging OU env=production
    - key: app
      operator: In
      values: ["myapp"]                  # ET app=myapp
  template:
    metadata:
      labels:
        app: myapp
        environment: production  # Correspond car "production" est dans la liste
        tier: backend
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

**Cas d'usage :** Gérer plusieurs environnements avec un seul Service.

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: multi-env-service
spec:
  selector:
    app: myapp
    # Ce service cible les pods staging ET production
  ports:
  - port: 80
```

#### Opérateur 2 : `NotIn`
Sélectionne les ressources où la clé existe ET la valeur n'est PAS dans la liste.

**Exemple : Exclure les environnements de test**

Créer `12c-matchexpressions-notin.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-only-app
spec:
  replicas: 2
  selector:
    matchExpressions:
    - key: environment
      operator: NotIn
      values: ["dev", "test"]  # Exclut dev et test
    - key: app
      operator: In
      values: ["critical-app"]
  template:
    metadata:
      labels:
        app: critical-app
        environment: production  # OK car pas dans [dev, test]
        criticality: high
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

**Cas d'usage :** NetworkPolicies pour bloquer le trafic vers les environnements non-production.

#### Opérateur 3 : `Exists`
Sélectionne les ressources où la clé existe, **peu importe sa valeur**.

**Exemple : Tous les pods avec un label de monitoring**

Créer `12d-matchexpressions-exists.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: monitored-app
spec:
  replicas: 2
  selector:
    matchExpressions:
    - key: monitoring
      operator: Exists  # Peu importe la valeur : monitoring=true, monitoring=enabled, etc.
    - key: app
      operator: In
      values: ["monitored-app"]
  template:
    metadata:
      labels:
        app: monitored-app
        monitoring: enabled  # N'importe quelle valeur fonctionne
        team: platform
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

**Cas d'usage :**
- Sélectionner tous les pods qui doivent être monitorés (peu importe la solution de monitoring)
- Identifier les ressources qui doivent être sauvegardées

#### Opérateur 4 : `DoesNotExist`
Sélectionne les ressources où la clé **n'existe PAS**.

**Exemple : Pods sans environnement spécifié (fallback)**

Créer `12e-matchexpressions-doesnotexist.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: default-env-app
spec:
  replicas: 1
  selector:
    matchExpressions:
    - key: environment
      operator: DoesNotExist  # Pods sans label "environment"
    - key: app
      operator: In
      values: ["legacy-app"]
  template:
    metadata:
      labels:
        app: legacy-app
        # Pas de label "environment"
        legacy: "true"
    spec:
      containers:
      - name: app
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

**Cas d'usage :**
- Identifier les ressources non étiquetées (pour audit)
- Appliquer des politiques par défaut aux ressources sans configuration spécifique

### 6.5 Combinaison : matchLabels + matchExpressions

Vous pouvez combiner `matchLabels` et `matchExpressions` - toutes les conditions doivent être satisfaites (AND logique).

**Exemple : Sélection hybride complexe**

Créer `12f-hybrid-selector.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hybrid-selector-app
spec:
  replicas: 3
  selector:
    matchLabels:          # Correspondance exacte
      app: myapp
      tier: backend
    matchExpressions:     # Conditions avancées
    - key: environment
      operator: In
      values: ["staging", "production"]
    - key: version
      operator: Exists    # Doit avoir un label version
    - key: deprecated
      operator: DoesNotExist  # Ne doit PAS être déprécié
  template:
    metadata:
      labels:
        app: myapp                # ✓ matchLabels
        tier: backend             # ✓ matchLabels
        environment: production   # ✓ In [staging, production]
        version: v2.1.0           # ✓ Exists
        # deprecated: "true"      # ✓ DoesNotExist (commenté = n'existe pas)
    spec:
      containers:
      - name: backend
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

### 6.6 Labels recommandés par Kubernetes

Kubernetes recommande un ensemble de labels standardisés pour une meilleure interopérabilité.

**Labels recommandés officiels :**

Créer `12g-recommended-labels.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: best-practice-app
  labels:
    # Labels recommandés par Kubernetes
    app.kubernetes.io/name: nginx           # Nom de l'application
    app.kubernetes.io/instance: nginx-prod  # Instance unique
    app.kubernetes.io/version: "1.24.0"     # Version actuelle
    app.kubernetes.io/component: webserver  # Composant dans l'archi
    app.kubernetes.io/part-of: ecommerce    # Application parente
    app.kubernetes.io/managed-by: kubectl   # Outil de gestion
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: nginx
      app.kubernetes.io/instance: nginx-prod
  template:
    metadata:
      labels:
        # Même structure de labels
        app.kubernetes.io/name: nginx
        app.kubernetes.io/instance: nginx-prod
        app.kubernetes.io/version: "1.24.0"
        app.kubernetes.io/component: webserver
        app.kubernetes.io/part-of: ecommerce
        app.kubernetes.io/managed-by: kubectl
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        ports:
        - name: http
          containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/instance: nginx-prod
    app.kubernetes.io/component: webserver
spec:
  selector:
    app.kubernetes.io/name: nginx
    app.kubernetes.io/instance: nginx-prod
  ports:
  - port: 80
    targetPort: http
```

**Tableau des labels recommandés :**

| Label | Description | Exemple |
|-------|-------------|---------|
| `app.kubernetes.io/name` | Nom de l'application | `mysql`, `wordpress` |
| `app.kubernetes.io/instance` | Instance unique | `mysql-prod`, `wordpress-dev` |
| `app.kubernetes.io/version` | Version actuelle | `5.7.21`, `1.0.0` |
| `app.kubernetes.io/component` | Rôle dans l'architecture | `database`, `cache`, `frontend` |
| `app.kubernetes.io/part-of` | Application parente | `ecommerce`, `blog-platform` |
| `app.kubernetes.io/managed-by` | Outil de gestion | `helm`, `kubectl`, `argocd` |

### 6.7 Exercices pratiques

**Exercice 8a : Manipulation avec les selectors**

```bash
# 1. Créer des ressources avec différents labels
kubectl apply -f 12a-deployment-matchlabels.yaml
kubectl apply -f 12b-matchexpressions-in.yaml
kubectl apply -f 12c-matchexpressions-notin.yaml

# 2. Lister tous les pods (toutes les applications)
kubectl get pods --show-labels

# 3. Sélectionner les pods avec app=webapp
kubectl get pods -l app=webapp

# 4. Sélectionner les pods avec environment in (production, staging)
kubectl get pods -l 'environment in (production,staging)'

# 5. Sélectionner les pods qui ont le label monitoring (peu importe la valeur)
kubectl get pods -l monitoring

# 6. Sélectionner les pods qui N'ONT PAS le label deprecated
kubectl get pods -l '!deprecated'

# 7. Combinaison : app=myapp ET environment=production
kubectl get pods -l 'app=myapp,environment=production'

# 8. Combinaison avec exclusion : app=myapp ET environment NOT IN (dev, test)
kubectl get pods -l 'app=myapp,environment notin (dev,test)'
```

**Exercice 8b : Modifier les labels dynamiquement**

```bash
# Ajouter un label à un pod
kubectl label pod <pod-name> tested=true

# Modifier un label existant (--overwrite requis)
kubectl label pod <pod-name> environment=staging --overwrite

# Supprimer un label (suffixe -)
kubectl label pod <pod-name> tested-

# Ajouter un label à tous les pods d'un deployment
kubectl label pods -l app=webapp team=platform

# Vérifier les changements
kubectl get pods --show-labels
```

**Exercice 8c : Services et selectors**

Créer `12h-service-selector-test.yaml` :

```yaml
# Déploiement frontend
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
      tier: frontend
  template:
    metadata:
      labels:
        app: myapp
        tier: frontend
        version: v1.0.0
    spec:
      containers:
      - name: nginx
        image: nginx:1.24-alpine
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run
      volumes:
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
---
# Déploiement backend
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      tier: backend
  template:
    metadata:
      labels:
        app: myapp
        tier: backend
        version: v1.0.0
    spec:
      containers:
      - name: api
        image: httpd:2.4-alpine
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
---
# Service pour frontend uniquement
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  selector:
    app: myapp
    tier: frontend  # Sélectionne UNIQUEMENT les pods frontend
  ports:
  - port: 80
    targetPort: 80
---
# Service pour backend uniquement
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  selector:
    app: myapp
    tier: backend  # Sélectionne UNIQUEMENT les pods backend
  ports:
  - port: 80
    targetPort: 80
---
# Service pour TOUTE l'application (frontend + backend)
apiVersion: v1
kind: Service
metadata:
  name: app-service
spec:
  selector:
    app: myapp  # Sélectionne TOUS les pods avec app=myapp (frontend ET backend)
  ports:
  - port: 80
    targetPort: 80
```

**Tester les selectors de Service :**

```bash
# Appliquer les ressources
kubectl apply -f 12h-service-selector-test.yaml

# Vérifier les endpoints de chaque service
kubectl get endpoints

# Frontend service doit avoir 2 endpoints (2 replicas frontend)
kubectl get endpoints frontend-service

# Backend service doit avoir 3 endpoints (3 replicas backend)
kubectl get endpoints backend-service

# App service doit avoir 5 endpoints (2 frontend + 3 backend)
kubectl get endpoints app-service

# Afficher les détails
kubectl describe service frontend-service
kubectl describe service backend-service
kubectl describe service app-service
```

**Exercice 8d : Debugging des selectors**

Fichier avec erreur `12i-buggy-selector.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: buggy-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp      # ❌ ERREUR
      tier: frontend  # ❌ ERREUR
  template:
    metadata:
      labels:
        app: different-app  # Ne correspond PAS au selector !
        tier: backend       # Ne correspond PAS au selector !
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

**Mission :**
1. Essayez d'appliquer ce manifest : `kubectl apply -f 12i-buggy-selector.yaml`
2. Lisez le message d'erreur
3. Identifiez le problème
4. Corrigez le manifest

### 6.8 Cas d'usage avancés

**Cas 1 : Canary Deployment avec labels**

```yaml
# Version stable (90% du trafic)
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
        version: v1.0.0
    spec:
      containers:
      - name: app
        image: myapp:1.0.0
---
# Version canary (10% du trafic)
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
        version: v2.0.0
    spec:
      containers:
      - name: app
        image: myapp:2.0.0
---
# Service qui distribue le trafic sur les deux versions
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp  # Sélectionne stable ET canary
  ports:
  - port: 80
```

**Cas 2 : Affinity rules avec labels**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
        tier: cache
    spec:
      # Anti-affinité : Ne pas placer 2 pods cache sur le même nœud
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - cache
            topologyKey: kubernetes.io/hostname
      containers:
      - name: redis
        image: redis:7-alpine
```

### 6.9 Bonnes pratiques

✅ **À FAIRE :**

1. **Utiliser des labels cohérents** dans toute l'organisation
   ```yaml
   labels:
     app: myapp
     environment: production
     team: platform
     cost-center: engineering
   ```

2. **Préférer les labels recommandés** par Kubernetes
   ```yaml
   labels:
     app.kubernetes.io/name: nginx
     app.kubernetes.io/instance: nginx-prod
   ```

3. **S'assurer de la correspondance selector ↔ labels**
   ```yaml
   selector:
     matchLabels:
       app: myapp  # ✓ Doit correspondre
   template:
     metadata:
       labels:
         app: myapp  # ✓ aux labels du template
   ```

4. **Utiliser des labels pour la facturation** (cloud)
   ```yaml
   labels:
     billing/team: platform
     billing/project: ecommerce
   ```

5. **Documenter la stratégie de labeling** de votre organisation

❌ **À ÉVITER :**

1. **Labels trop longs ou complexes**
   ```yaml
   labels:
     this-is-a-very-long-label-name-that-is-hard-to-type: value  # ❌
   ```

2. **Valeurs changeantes** (timestamps, IDs aléatoires)
   ```yaml
   labels:
     created-at: "2024-01-15T10:30:00Z"  # ❌ Change à chaque déploiement
   ```

3. **Informations sensibles dans les labels**
   ```yaml
   labels:
     api-key: secret123  # ❌ Les labels sont visibles !
   ```

4. **Selectors trop permissifs**
   ```yaml
   selector:
     matchLabels:
       app: myapp  # ⚠️ Peut sélectionner trop de pods
   ```

5. **Oublier de mettre à jour les selectors lors des modifications**

### 6.10 Résumé des selectors

| Type | Syntaxe | Use Case |
|------|---------|----------|
| **matchLabels** | `key: value` | Sélection simple et exacte |
| **In** | `operator: In, values: [v1, v2]` | Sélectionner parmi plusieurs valeurs |
| **NotIn** | `operator: NotIn, values: [v1, v2]` | Exclure certaines valeurs |
| **Exists** | `operator: Exists` | Vérifier la présence d'un label |
| **DoesNotExist** | `operator: DoesNotExist` | Vérifier l'absence d'un label |

**Commandes essentielles :**

```bash
# Afficher les labels
kubectl get pods --show-labels

# Filtrer par label égalité
kubectl get pods -l app=myapp

# Filtrer par label inégalité
kubectl get pods -l app!=myapp

# Filtrer In
kubectl get pods -l 'environment in (prod,staging)'

# Filtrer NotIn
kubectl get pods -l 'environment notin (dev,test)'

# Filtrer Exists
kubectl get pods -l environment

# Filtrer DoesNotExist
kubectl get pods -l '!environment'

# Combinaisons
kubectl get pods -l 'app=myapp,environment=prod'

# Ajouter/Modifier/Supprimer labels
kubectl label pod <name> key=value
kubectl label pod <name> key=value --overwrite
kubectl label pod <name> key-
```

## Partie 7 : Namespaces et organisation

### 7.1 Création de namespaces

Créer `13-namespaces.yaml` :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: development
  labels:
    environment: dev

---
apiVersion: v1
kind: Namespace
metadata:
  name: staging
  labels:
    environment: staging

---
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    environment: prod
```

### 7.2 Ressources dans un namespace spécifique

Créer `14-app-in-namespace.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: development  # Spécifier le namespace
spec:
  replicas: 2
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
        image: nginx:alpine

---
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
  namespace: development
spec:
  selector:
    app: myapp
  ports:
  - port: 80
```

**Exercice 9 : Travailler avec les namespaces**

1. Créez les namespaces
2. Listez-les : `kubectl get namespaces`
3. Déployez l'application dans development
4. Listez les pods dans ce namespace :
   ```bash
   kubectl get pods -n development
   ```
5. Définissez development comme namespace par défaut :
   ```bash
   kubectl config set-context --current --namespace=development
   ```
6. Maintenant les commandes utilisent ce namespace automatiquement :
   ```bash
   kubectl get pods  # Affiche les pods de development
   ```

## Partie 8 : Exercices pratiques complets

### 8.0 Prérequis : Configuration du Stockage Dynamique

**⚠️ IMPORTANT** : Les exercices de cette section utilisent des **PersistentVolumeClaim (PVC)** qui nécessitent une **StorageClass** configurée dans votre cluster.

#### 8.0.1 Vérifier la configuration du stockage

Avant de commencer, vérifiez que votre cluster dispose d'une StorageClass par défaut :

```bash
# Vérifier les StorageClass disponibles
kubectl get storageclass

# Vous devriez voir au moins une StorageClass avec (default) à côté
```

**Résultat attendu :**
```
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
```

#### 8.0.2 Configuration spécifique par environnement

##### 🎯 Avec Minikube (Prêt à l'emploi)

**Minikube est déjà configuré !** La StorageClass `standard` est automatiquement disponible avec le provisioner `k8s.io/minikube-hostpath`.

```bash
# Vérifier (déjà configuré)
kubectl get storageclass standard

# Résultat attendu :
# NAME                 PROVISIONER                RECLAIMPOLICY
# standard (default)   k8s.io/minikube-hostpath   Delete
```

✅ **Vous pouvez passer directement à l'exercice 10.**

##### 🔧 Avec Kubeadm (Configuration requise)

**Attention !** Un cluster kubeadm "vanilla" **N'A PAS** de StorageClass par défaut. Vous devez installer un provisioner de stockage.

**Vérifier l'absence de StorageClass :**
```bash
kubectl get storageclass
# Résultat probable : No resources found
```

**Solution : Installer local-path-provisioner**

Le [local-path-provisioner](https://github.com/rancher/local-path-provisioner) de Rancher est une solution simple et efficace pour le stockage local :

```bash
# 1. Installer le provisioner
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# 2. Attendre que le déploiement soit prêt
kubectl wait --namespace local-path-storage \
  --for=condition=ready pod \
  --selector=app=local-path-provisioner \
  --timeout=90s

# 3. Définir comme StorageClass par défaut
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# 4. Vérifier la configuration
kubectl get storageclass
```

**Résultat attendu :**
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

**Explication des paramètres :**
- **Provisioner** : `rancher.io/local-path` crée automatiquement des répertoires locaux sur les nœuds
- **ReclaimPolicy: Delete** : Les données sont supprimées quand le PVC est détruit
- **VolumeBindingMode: WaitForFirstConsumer** : Le volume n'est créé que lorsqu'un pod l'utilise (optimise le placement)
- **Chemin de stockage par défaut** : `/opt/local-path-provisioner/` sur chaque nœud

**Limitations à connaître :**
- ⚠️ Les données sont stockées localement sur un seul nœud
- ⚠️ Pas de haute disponibilité (si le nœud tombe, les données sont perdues)
- ⚠️ Pas de support ReadWriteMany (RWX)
- ✅ Convient pour le développement, les tests et les applications avec ReadWriteOnce (RWO)

**Alternative pour la production :** Pour un environnement de production on-premise, considérez des solutions comme :
- **Longhorn** : Stockage distribué avec réplication (voir TP3)
- **Ceph/Rook** : Stockage objet et block distribué
- **NFS** : Pour le partage de fichiers (ReadWriteMany)

#### 8.0.3 Tester la configuration

Une fois la StorageClass configurée, testez-la rapidement :

```bash
# Créer un PVC de test
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF

# Vérifier le statut (doit être Pending ou Bound)
kubectl get pvc test-pvc

# Créer un pod utilisant ce PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: test-storage
      mountPath: /data
  volumes:
  - name: test-storage
    persistentVolumeClaim:
      claimName: test-pvc
EOF

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod/test-pod --timeout=60s

# Vérifier que le PVC est maintenant Bound
kubectl get pvc test-pvc

# Le statut doit être : STATUS = Bound

# Nettoyer
kubectl delete pod test-pod
kubectl delete pvc test-pvc
```

**Résultat attendu :**
```
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES
test-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   100Mi      RWO
```

✅ **Si le PVC est en état "Bound", votre configuration est correcte !**

❌ **Si le PVC reste en "Pending"**, vérifiez :
1. Qu'une StorageClass par défaut existe : `kubectl get storageclass`
2. Les logs du provisioner :
   - Minikube : `kubectl logs -n kube-system -l component=storage-provisioner`
   - Kubeadm (local-path) : `kubectl logs -n local-path-storage -l app=local-path-provisioner`

#### 8.0.4 Récapitulatif

| Environnement | StorageClass par défaut | Action requise |
|---------------|-------------------------|----------------|
| **Minikube** | ✅ Oui (`standard`) | Aucune |
| **Kubeadm** | ❌ Non | Installer local-path-provisioner |
| **Cloud (EKS, GKE, AKS)** | ✅ Oui (propre au provider) | Aucune (généralement) |

**Vous êtes maintenant prêt pour l'exercice 10 !** 🚀

---

### Exercice 10 : Application complète WordPress

Créez une application WordPress avec MySQL en écrivant les manifests pour :

1. **Namespace** : `wordpress-app`

2. **Secret** pour MySQL :
   - Nom : `mysql-secret`
   - Clés : `password` avec valeur `wordpress123`

3. **PersistentVolumeClaim** pour MySQL :
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: mysql-pvc
     namespace: wordpress-app
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 1Gi
   ```

4. **Deployment MySQL** :
   - Image : `mysql:8.0`
   - 1 replica
   - Variables d'environnement : `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE=wordpress`
   - Volume monté sur `/var/lib/mysql`
   - Port : 3306

5. **Service MySQL** :
   - Type : ClusterIP
   - Port : 3306

6. **PersistentVolumeClaim** pour WordPress

7. **Deployment WordPress** :
   - Image : `wordpress:6.4-apache`
   - 2 replicas
   - Variables d'environnement : `WORDPRESS_DB_HOST=mysql-service`, `WORDPRESS_DB_USER=root`, `WORDPRESS_DB_PASSWORD` (depuis le secret), `WORDPRESS_DB_NAME=wordpress`
   - Port : 80

8. **Service WordPress** :
   - Type : NodePort
   - Port : 80

**Validation :**
```bash
kubectl apply -f wordpress-namespace.yaml
kubectl apply -f wordpress-secret.yaml
kubectl apply -f wordpress-mysql.yaml
kubectl apply -f wordpress-app.yaml

# Attendre que tout soit prêt
kubectl wait --for=condition=ready pod -l app=mysql -n wordpress-app --timeout=120s
kubectl wait --for=condition=ready pod -l app=wordpress -n wordpress-app --timeout=120s
```

**Accès à WordPress :**

Avec minikube :
```bash
minikube service wordpress-service -n wordpress-app
```

Avec kubeadm :
```bash
# Récupérer le NodePort et l'IP d'un nœud
NODE_PORT=$(kubectl get svc wordpress-service -n wordpress-app -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "WordPress accessible à : http://$NODE_IP:$NODE_PORT"
```

### Exercice 11 : Application avec microservices

Créez une stack applicative complète :

**Architecture :**
- Frontend (Nginx) → Backend API (Node.js) → Database (PostgreSQL) → Cache (Redis)

**Contraintes :**
- Utiliser des labels cohérents pour l'ensemble
- Le frontend doit être accessible via NodePort
- Backend, Database et Redis doivent être en ClusterIP
- Utiliser des ConfigMaps pour la configuration
- Utiliser des Secrets pour les mots de passe
- Définir des ressources requests/limits
- Ajouter des probes (liveness et readiness)
- Organiser dans un namespace dédié

**Structure suggérée :**
```
microservices/
├── 00-namespace.yaml
├── 01-configmaps.yaml
├── 02-secrets.yaml
├── 03-redis.yaml
├── 04-database.yaml
├── 05-backend.yaml
└── 06-frontend.yaml
```

### Exercice 12 : Job et CronJob

Créer `15-job.yaml` :

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: database-backup
spec:
  template:
    spec:
      containers:
      - name: backup
        image: busybox
        command: ["/bin/sh"]
        args:
          - -c
          - >
            echo "Starting backup..." &&
            echo "Backing up database..." &&
            sleep 10 &&
            echo "Backup completed successfully!"
      restartPolicy: OnFailure
  backoffLimit: 3
```

Créer `16-cronjob.yaml` :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-job
spec:
  schedule: "*/5 * * * *"  # Toutes les 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: busybox
            command: ["/bin/sh"]
            args:
              - -c
              - >
                echo "Running cleanup at $(date)" &&
                echo "Cleaning temporary files..." &&
                sleep 5 &&
                echo "Cleanup done!"
          restartPolicy: OnFailure
```

**Exercice :**
1. Créez le Job et surveillez son exécution : `kubectl get jobs -w`
2. Consultez les logs : `kubectl logs job/database-backup`
3. Créez le CronJob
4. Listez les CronJobs : `kubectl get cronjobs`
5. Attendez quelques minutes et listez les jobs créés : `kubectl get jobs`
6. Suspendez le CronJob : `kubectl patch cronjob cleanup-job -p '{"spec":{"suspend":true}}'`

## Partie 9 : Validation et bonnes pratiques

### 9.1 Outils de validation

**Validation avec kubectl :**
```bash
# Dry-run côté client
kubectl apply -f manifest.yaml --dry-run=client -o yaml

# Dry-run côté serveur (validation plus stricte)
kubectl apply -f manifest.yaml --dry-run=server

# Validation de la syntaxe YAML
kubectl apply -f manifest.yaml --validate=true

# Diff avant application
kubectl diff -f manifest.yaml
```

**Validation avec kubeval :**
```bash
# Installation
wget https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
tar xf kubeval-linux-amd64.tar.gz
sudo mv kubeval /usr/local/bin

# Utilisation
kubeval manifest.yaml
kubeval *.yaml
```

**Validation avec kube-score :**
```bash
# Installation
wget https://github.com/zegl/kube-score/releases/download/v1.17.0/kube-score_1.17.0_linux_amd64
chmod +x kube-score_1.17.0_linux_amd64
sudo mv kube-score_1.17.0_linux_amd64 /usr/local/bin/kube-score

# Utilisation
kube-score score manifest.yaml
```

### 9.2 Bonnes pratiques

**1. Toujours spécifier les versions d'images**
```yaml
# Mauvais
image: nginx

# Bon
image: nginx:1.24.0
```

**2. Définir les ressources requests et limits**
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "250m"
  limits:
    memory: "128Mi"
    cpu: "500m"
```

**3. Utiliser des labels cohérents**
```yaml
labels:
  app.kubernetes.io/name: myapp
  app.kubernetes.io/instance: myapp-prod
  app.kubernetes.io/version: "1.0.0"
  app.kubernetes.io/component: frontend
  app.kubernetes.io/part-of: ecommerce
  app.kubernetes.io/managed-by: kubectl
```

**4. Ajouter des health checks**
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

**5. Utiliser des namespaces pour l'isolation**

**6. Ne jamais commiter les secrets en clair**

**7. Documenter avec des annotations**
```yaml
metadata:
  annotations:
    description: "Service principal pour l'API backend"
    contact: "team-backend@example.com"
    documentation: "https://docs.example.com/api"
```

### 9.3 Template de manifest complet

Créer `template-complete.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: complete-app
  namespace: production
  labels:
    app.kubernetes.io/name: complete-app
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: api
  annotations:
    description: "Template complet d'une application Kubernetes"
spec:
  replicas: 3

  # Stratégie de déploiement
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0

  selector:
    matchLabels:
      app.kubernetes.io/name: complete-app

  template:
    metadata:
      labels:
        app.kubernetes.io/name: complete-app
        app.kubernetes.io/version: "1.0.0"

    spec:
      # Contraintes de placement
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                  - complete-app
              topologyKey: kubernetes.io/hostname

      containers:
      - name: app
        image: nginx:1.24.0

        ports:
        - name: http
          containerPort: 80
          protocol: TCP

        # Variables d'environnement
        env:
        - name: LOG_LEVEL
          value: "info"
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: database_url
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secret
              key: password

        # Ressources
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"

        # Health checks
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        # Security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL

        # Volumes
        volumeMounts:
        - name: config
          mountPath: /etc/config
          readOnly: true
        - name: cache
          mountPath: /var/cache/nginx
        - name: run
          mountPath: /var/run

      volumes:
      - name: config
        configMap:
          name: app-config
      - name: cache
        emptyDir: {}
      - name: run
        emptyDir: {}
```

## Partie 10 : Tests et debugging

### 10.1 Commandes de test

```bash
# Appliquer et surveiller
kubectl apply -f manifest.yaml && kubectl get pods -w

# Tester la connectivité
kubectl run test-pod --image=busybox -it --rm -- wget -qO- http://service-name

# Port-forward pour tester localement
kubectl port-forward deployment/myapp 8080:80

# Exécuter des commandes dans un pod
kubectl exec -it pod-name -- /bin/sh

# Copier des fichiers depuis/vers un pod
kubectl cp pod-name:/path/to/file ./local-file
kubectl cp ./local-file pod-name:/path/to/file

# Afficher les événements
kubectl get events --sort-by='.lastTimestamp'

# Debug d'un pod qui ne démarre pas
kubectl describe pod pod-name
kubectl logs pod-name
kubectl logs pod-name --previous  # Logs du conteneur précédent
```

### 10.2 Exercice de debugging

**Fichier avec erreurs** `17-buggy-manifest.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: buggy-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: buggy
  template:
    metadata:
      labels:
        app: wrong-label  # Bug 1: Label ne correspond pas au selector
    spec:
      containers:
      - name: app
        image: ngin:latest  # Bug 2: Image incorrecte
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "1Gi"
            cpu: "2000m"  # Bug 3: Ressources trop élevées (unrealistic)
          limits:
            memory: "512Mi"  # Bug 4: Limit < Request
            cpu: "1000m"
```

**Mission :**
1. Essayez d'appliquer ce manifest
2. Identifiez toutes les erreurs
3. Corrigez-les une par une
4. Validez que l'application fonctionne

### 10.3 Checklist de validation

Avant d'appliquer un manifest, vérifiez :

- [ ] La syntaxe YAML est correcte (indentation, guillemets)
- [ ] Les labels du selector correspondent aux labels des pods
- [ ] Les versions d'images sont spécifiées
- [ ] Les ressources requests sont définies
- [ ] Les limits sont >= aux requests
- [ ] Les ports sont corrects
- [ ] Les noms de ConfigMaps/Secrets existent
- [ ] Les volumes montés correspondent aux volumes déclarés
- [ ] Les probes sont configurées si nécessaire
- [ ] Le namespace existe (si spécifié)
- [ ] Validation avec `--dry-run=server` réussit

## Solutions des exercices

<details>
<summary>Solution Exercice 10 : WordPress complet</summary>

**wordpress-namespace.yaml**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: wordpress-app
```

**wordpress-secret.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: wordpress-app
type: Opaque
stringData:
  password: wordpress123
```

**wordpress-mysql.yaml**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
  namespace: wordpress-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress-app
spec:
  replicas: 1
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
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: wordpress
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
  namespace: wordpress-app
spec:
  type: ClusterIP
  selector:
    app: mysql
  ports:
  - port: 3306
```

**wordpress-app.yaml**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pvc
  namespace: wordpress-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress-app
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
        image: wordpress:6.4-apache
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql-service
        - name: WORDPRESS_DB_USER
          value: root
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: WORDPRESS_DB_NAME
          value: wordpress
        ports:
        - containerPort: 80
        volumeMounts:
        - name: wordpress-storage
          mountPath: /var/www/html
      volumes:
      - name: wordpress-storage
        persistentVolumeClaim:
          claimName: wordpress-pvc

---
apiVersion: v1
kind: Service
metadata:
  name: wordpress-service
  namespace: wordpress-app
spec:
  type: NodePort
  selector:
    app: wordpress
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

**Déploiement :**
```bash
kubectl apply -f wordpress-namespace.yaml
kubectl apply -f wordpress-secret.yaml
kubectl apply -f wordpress-mysql.yaml
kubectl apply -f wordpress-app.yaml

# Attendre que tout soit prêt
kubectl wait --for=condition=ready pod -l app=mysql -n wordpress-app --timeout=120s
kubectl wait --for=condition=ready pod -l app=wordpress -n wordpress-app --timeout=120s

# Accéder à WordPress
# Avec minikube :
minikube service wordpress-service -n wordpress-app

# Avec kubeadm :
NODE_PORT=$(kubectl get svc wordpress-service -n wordpress-app -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "http://$NODE_IP:$NODE_PORT"
```
</details>

<details>
<summary>Solution Exercice de debugging</summary>

**Version corrigée** `17-buggy-manifest-fixed.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: buggy-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: buggy  # Correction 1: Doit correspondre au label du pod
  template:
    metadata:
      labels:
        app: buggy  # Correction 1: Label corrigé
    spec:
      containers:
      - name: app
        image: nginx:1.24  # Correction 2: Nom d'image corrigé avec version spécifique
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"  # Correction 3: Ressources réalistes
            cpu: "100m"
          limits:
            memory: "256Mi"  # Correction 4: Limits > Requests
            cpu: "500m"
```
</details>

## Ressources complémentaires

### Documentation
- API Reference Kubernetes : https://kubernetes.io/docs/reference/kubernetes-api/
- YAML Specification : https://yaml.org/spec/
- Best Practices : https://kubernetes.io/docs/concepts/configuration/overview/

### Outils utiles
- **kubectl explain** : Documentation intégrée
- **kubeval** : Validation de manifests
- **kube-score** : Analyse de qualité
- **yamllint** : Linter YAML
- **VS Code** : Extension Kubernetes pour l'auto-complétion

### Exemples de manifests
```bash
# Obtenir le YAML d'une ressource existante
kubectl get deployment nginx -o yaml > example-deployment.yaml

# Générer un template
kubectl create deployment test --image=nginx --dry-run=client -o yaml
kubectl create service clusterip test --tcp=80:80 --dry-run=client -o yaml
```

## Points clés à retenir

1. **Structure** : Tous les manifests suivent apiVersion, kind, metadata, spec
2. **Labels** : Essentiels pour lier les ressources (Services → Pods)
3. **Validation** : Toujours utiliser `--dry-run` avant d'appliquer
4. **Ressources** : Définir requests et limits pour une meilleure gestion
5. **Health checks** : Liveness et readiness probes pour la fiabilité
6. **Configuration** : Externaliser avec ConfigMaps et Secrets
7. **Namespaces** : Organiser et isoler les ressources
8. **Documentation** : Utiliser labels et annotations pour la traçabilité
9. **Versions** : Toujours spécifier les versions d'images
10. **Tests** : Valider avec plusieurs outils avant de déployer en production

## Prochaines étapes

Après avoir maîtrisé les manifests, vous pouvez explorer :
- **Helm** : Gestionnaire de packages pour Kubernetes
- **Kustomize** : Personnalisation de manifests
- **GitOps** : Déploiement automatisé avec ArgoCD ou Flux
- **StatefulSets** : Pour les applications avec état
- **DaemonSets** : Déploiement sur tous les nœuds
- **Ingress** : Gestion avancée du trafic HTTP/HTTPS
- **Network Policies** : Sécurité réseau
- **RBAC** : Contrôle d'accès
