# TP3 - Persistance des données dans Kubernetes

## Objectifs du TP

À la fin de ce TP, vous serez capable de :
- Comprendre les différents types de volumes Kubernetes
- Créer et gérer des PersistentVolumes (PV) et PersistentVolumeClaims (PVC)
- Utiliser les StorageClasses pour le provisionnement dynamique
- Déployer une base de données avec persistance des données
- Gérer le cycle de vie des volumes
- Appliquer les bonnes pratiques de gestion du stockage

## Prérequis

- Avoir complété le TP1 et TP2
- Un cluster Kubernetes fonctionnel (**minikube** ou **kubeadm**)
- Connaissance de base des manifests YAML

**Note :** Les concepts de persistance (PV, PVC, StorageClass) sont identiques pour minikube et kubeadm. Les différences se situent principalement au niveau des provisioners de stockage disponibles.

## Partie 1 : Introduction aux volumes Kubernetes

### 1.1 Pourquoi les volumes ?

Par défaut, les données dans un conteneur sont éphémères : elles disparaissent quand le conteneur s'arrête. Les volumes Kubernetes permettent de :

- **Persister les données** au-delà du cycle de vie d'un pod
- **Partager des données** entre conteneurs d'un même pod
- **Stocker des configurations** et des secrets
- **Monter des systèmes de fichiers externes**

### 1.2 Types de volumes

Kubernetes supporte plusieurs types de volumes :

- **emptyDir** : Volume temporaire, vie du pod
- **hostPath** : Monte un répertoire du nœud (développement uniquement)
- **persistentVolumeClaim** : Demande de stockage persistant
- **configMap/secret** : Pour les configurations
- **nfs, iscsi, cephfs** : Stockage réseau
- **cloud providers** : awsElasticBlockStore, gcePersistentDisk, azureDisk

### 1.3 Volume emptyDir

Le volume le plus simple, créé quand un pod est assigné à un nœud.

Créer le fichier `01-emptydir-pod.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
  labels:
    app: demo
spec:
  containers:
  - name: writer
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "$(date): Writing data" >> /data/log.txt;
          sleep 5;
        done
    volumeMounts:
    - name: shared-storage
      mountPath: /data

  - name: reader
    image: busybox
    command: ["/bin/sh"]
    args:
      - -c
      - >
        while true; do
          echo "=== Latest logs ===";
          tail -n 5 /data/log.txt;
          sleep 10;
        done
    volumeMounts:
    - name: shared-storage
      mountPath: /data

  volumes:
  - name: shared-storage
    emptyDir: {}
```

**Exercice 1 : Tester emptyDir**

```bash
# Appliquer le manifest
kubectl apply -f 01-emptydir-pod.yaml

# Vérifier que le pod tourne
kubectl get pods

# Observer les logs du writer
kubectl logs emptydir-demo -c writer

# Observer les logs du reader
kubectl logs emptydir-demo -c reader -f

# Supprimer le pod
kubectl delete -f 01-emptydir-pod.yaml
```

**Question** : Que se passe-t-il si vous recréez le pod ? Les données sont-elles toujours là ?

## Partie 2 : Comprendre l'infrastructure de stockage Kubernetes

### 2.1 Architecture du stockage dans Kubernetes

Avant de plonger dans les PersistentVolumes, il est crucial de comprendre l'architecture globale du stockage dans Kubernetes et les différentes options disponibles en production.

#### 2.1.1 Les couches de l'architecture de stockage

```
┌─────────────────────────────────────────────────────┐
│              Application (Pod)                       │
│  Utilise le volume via un point de montage          │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│       PersistentVolumeClaim (PVC)                   │
│  Demande de stockage avec spécifications            │
│  - Taille: 10Gi                                      │
│  - Mode: ReadWriteOnce                               │
│  - StorageClass: fast-ssd                           │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│          StorageClass                                │
│  Définit le type et les paramètres du stockage      │
│  - Provisioner: csi-driver                          │
│  - Parameters: type=ssd, iops=3000                   │
│  - ReclaimPolicy: Delete                             │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│       PersistentVolume (PV)                         │
│  Ressource de stockage réelle dans le cluster       │
│  - Créé dynamiquement ou manuellement                │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│       Backend de Stockage Physique                  │
│  - Disque local (hostPath)                          │
│  - NFS / iSCSI / Ceph                               │
│  - Cloud (EBS, Azure Disk, GCE PD)                  │
│  - Distributed (Longhorn, Rook/Ceph)                │
└─────────────────────────────────────────────────────┘
```

#### 2.1.2 Types de backends de stockage en production

##### A. Stockage Local (hostPath, local)

**Cas d'usage :** Développement, tests, données temporaires haute performance

**Avantages :**
- Performance maximale (pas de latence réseau)
- Simplicité de configuration
- Coût nul

**Inconvénients :**
- Pas de haute disponibilité
- Données liées à un nœud spécifique
- Perte de données si le nœud tombe

**Exemple de scénario :**
```yaml
# Base de données de cache temporaire sur un nœud spécifique
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cache-local-pv
spec:
  capacity:
    storage: 50Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /mnt/fast-ssd/cache
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-node-1
```

**⚠️ Sécurité :** Ne jamais utiliser hostPath en production sauf cas très spécifiques. C'est une faille de sécurité majeure car cela donne accès au système de fichiers du nœud.

##### B. Stockage Réseau (NFS)

**Cas d'usage :** Partage de fichiers entre plusieurs pods, fichiers de configuration, assets statiques

**Avantages :**
- Support ReadWriteMany (plusieurs pods simultanés)
- Simplicité de mise en œuvre
- Coût modéré

**Inconvénients :**
- Performances limitées pour I/O intensif
- Point de défaillance unique (le serveur NFS)
- Latence réseau

**Architecture typique :**
```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Pod 1      │     │   Pod 2      │     │   Pod 3      │
│ (Node A)     │     │ (Node B)     │     │ (Node C)     │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       │        Network (TCP/IP - NFS)           │
       │                    │                    │
       └────────────────────┼────────────────────┘
                            │
                   ┌────────▼─────────┐
                   │  Serveur NFS     │
                   │  /exports/data   │
                   │  100Gi SSD       │
                   └──────────────────┘
```

**Exemple concret :**
```yaml
# Serveur NFS: 192.168.1.100
# Export: /exports/shared-data
# Permissions: rw,sync,no_subtree_check,no_root_squash

apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-shared-storage
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany  # Plusieurs pods peuvent lire/écrire
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs
  mountOptions:
    - hard
    - nfsvers=4.1
    - rsize=1048576
    - wsize=1048576
  nfs:
    server: 192.168.1.100
    path: "/exports/shared-data"
```

**🔒 Sécurité NFS :**
- Utiliser NFSv4.1 minimum avec Kerberos
- Configurer des exports restrictifs (pas de no_root_squash sauf nécessité)
- Isoler le réseau NFS (VLAN dédié)
- Chiffrer le trafic avec stunnel ou VPN

##### C. Stockage Block (iSCSI, Fibre Channel)

**Cas d'usage :** Bases de données, applications nécessitant des performances élevées

**Avantages :**
- Haute performance
- Support des snapshots et clones
- Fonctionnalités entreprise (réplication, déduplication)

**Inconvénients :**
- Coût élevé (SAN)
- Complexité de configuration
- Généralement ReadWriteOnce uniquement

**Architecture iSCSI :**
```
┌──────────────────────────────────────────┐
│  Cluster Kubernetes                       │
│  ┌────────┐  ┌────────┐  ┌────────┐     │
│  │Worker 1│  │Worker 2│  │Worker 3│     │
│  └───┬────┘  └───┬────┘  └───┬────┘     │
│      │ iSCSI    │ iSCSI    │ iSCSI      │
└──────┼──────────┼──────────┼─────────────┘
       │          │          │
    ┌──┴──────────┴──────────┴───┐
    │   Réseau iSCSI (VLAN)       │
    │   10Gb/s Ethernet           │
    └──────────────┬──────────────┘
                   │
         ┌─────────▼──────────┐
         │   SAN Storage       │
         │   - LUN 1: 500Gi   │
         │   - LUN 2: 1Ti     │
         │   - RAID 10        │
         │   - SSD Tier       │
         └────────────────────┘
```

**Exemple iSCSI avec authentification CHAP :**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: iscsi-pv-database
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: iscsi-fast
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2024-01.com.enterprise:storage.lun1
    lun: 1
    fsType: ext4
    readOnly: false
    chapAuthDiscovery: true
    chapAuthSession: true
    secretRef:
      name: iscsi-chap-secret
---
apiVersion: v1
kind: Secret
metadata:
  name: iscsi-chap-secret
type: kubernetes.io/iscsi-chap
data:
  node.session.auth.username: <base64-encoded-username>
  node.session.auth.password: <base64-encoded-password>
```

##### D. Stockage Cloud (AWS EBS, Azure Disk, GCP PD)

**Cas d'usage :** Clusters sur cloud providers, applications cloud-native

**Avantages :**
- Haute disponibilité gérée par le cloud
- Snapshots automatiques
- Scaling facile
- Intégration native Kubernetes

**Inconvénients :**
- Coût par GB/mois
- Performances variables selon le type
- Lock-in du cloud provider

**Comparaison des options cloud :**

| Provider | Type | Performance | Use Case |
|----------|------|-------------|----------|
| AWS | gp3 (SSD) | 3000 IOPS baseline | Usage général |
| AWS | io2 (SSD) | Jusqu'à 64000 IOPS | Bases de données |
| AWS | st1 (HDD) | Throughput optimized | Big data, logs |
| Azure | Premium SSD | 7500+ IOPS | Production DB |
| Azure | Standard SSD | 500 IOPS | Dev/Test |
| GCP | pd-balanced | 6000 IOPS | Équilibré |
| GCP | pd-ssd | 30000 IOPS | Haute performance |

**Exemple AWS EBS avec chiffrement :**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: encrypted-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"  # Chiffrement EBS obligatoire
  kmsKeyId: "arn:aws:kms:us-east-1:123456789:key/abcd-1234"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: encrypted-gp3
  resources:
    requests:
      storage: 100Gi
```

##### E. Stockage Distribué (Ceph, Longhorn, GlusterFS)

**Cas d'usage :** Clusters on-premise nécessitant HA, multi-cloud, bare metal

**Avantages :**
- Haute disponibilité native
- Réplication automatique
- Pas de vendor lock-in
- Support RWX

**Inconvénients :**
- Complexité opérationnelle élevée
- Nécessite plusieurs nœuds (min 3)
- Overhead réseau et CPU

**Architecture Longhorn (exemple) :**
```
┌─────────────────────────────────────────────────────┐
│           Cluster Kubernetes (3+ nodes)              │
│  ┌─────────┐      ┌─────────┐      ┌─────────┐     │
│  │ Node 1  │      │ Node 2  │      │ Node 3  │     │
│  │ ┌─────┐ │      │ ┌─────┐ │      │ ┌─────┐ │     │
│  │ │Repli│ │◄────►│ │Repli│ │◄────►│ │Repli│ │     │
│  │ │ca 1 │ │      │ │ca 2 │ │      │ │ca 3 │ │     │
│  │ └─────┘ │      │ └─────┘ │      │ └─────┘ │     │
│  └─────────┘      └─────────┘      └─────────┘     │
│       │                 │                 │         │
│  ┌────▼────┐      ┌────▼────┐      ┌────▼────┐     │
│  │Disk 100G│      │Disk 100G│      │Disk 100G│     │
│  └─────────┘      └─────────┘      └─────────┘     │
└─────────────────────────────────────────────────────┘

Volume logique: 100Gi avec 3 réplicas
Si un nœud tombe, les 2 autres réplicas assurent la continuité
```

**Installation Longhorn avec sécurité renforcée :**
```bash
# Installer Longhorn avec Helm
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Configuration sécurisée
cat > longhorn-values.yaml <<EOF
defaultSettings:
  backupTarget: s3://backups@us-east-1/longhorn  # Sauvegardes S3
  defaultReplicaCount: 3  # 3 réplicas pour HA
  guaranteedInstanceManagerCPU: 12
  storageMinimalAvailablePercentage: 15
  upgradeChecker: false  # Désactiver les appels externes

ingress:
  enabled: true
  host: longhorn.internal.company.com
  tls: true
  tlsSecret: longhorn-tls
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: longhorn-basic-auth

persistence:
  defaultClass: true
  defaultClassReplicaCount: 3
  reclaimPolicy: Retain
EOF

kubectl create namespace longhorn-system
helm install longhorn longhorn/longhorn --namespace longhorn-system -f longhorn-values.yaml

# Créer l'authentification basique pour l'UI
htpasswd -c auth admin
kubectl -n longhorn-system create secret generic longhorn-basic-auth --from-file=auth
```

**Exemple de StorageClass Longhorn :**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-crypto-global
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "2880"  # 48 heures
  fromBackup: ""
  fsType: "ext4"
  dataLocality: "best-effort"  # Préférer le nœud local si possible
  # Chiffrement des volumes
  encrypted: "true"
  # paramètres de performance
  diskSelector: "ssd,fast"
  nodeSelector: "storage,production"
```

#### 2.1.3 Matrice de comparaison des solutions de stockage

| Solution | HA | Performance | Coût | Complexité | ReadWriteMany | Use Case Principal |
|----------|----|----|------|------------|---------------|-------------------|
| hostPath | ❌ | ⭐⭐⭐⭐⭐ | Gratuit | Faible | ❌ | Dev/Test uniquement |
| local | ❌ | ⭐⭐⭐⭐⭐ | Gratuit | Faible | ❌ | Cache, données temporaires |
| NFS | ⚠️ | ⭐⭐ | Faible | Moyenne | ✅ | Fichiers partagés |
| iSCSI | ⚠️ | ⭐⭐⭐⭐ | Élevé | Élevée | ❌ | Bases de données |
| AWS EBS | ✅ | ⭐⭐⭐⭐ | Moyen | Faible | ❌ | Cloud, production |
| Longhorn | ✅ | ⭐⭐⭐ | Moyen | Élevée | ✅ | On-premise, HA |
| Ceph/Rook | ✅ | ⭐⭐⭐⭐ | Moyen | Très élevée | ✅ | Enterprise, scale |

#### 2.1.4 Choisir la bonne solution de stockage

**Pour le développement local :**
```yaml
hostPath ou emptyDir
→ Rapide, simple, pas de configuration
→ ⚠️ JAMAIS en production
```

**Pour une petite application web (stateless avec assets) :**
```yaml
NFS
→ Partage facile des assets entre pods
→ Support ReadWriteMany
→ Exemple: Images uploadées, fichiers CSS/JS compilés
```

**Pour une base de données en production on-premise :**
```yaml
iSCSI (si SAN disponible) OU Longhorn/Ceph
→ Performance + HA
→ Snapshots pour backups
→ Exemple: PostgreSQL, MySQL, MongoDB
```

**Pour une application cloud-native :**
```yaml
StorageClass du cloud provider (EBS, Azure Disk, GCP PD)
→ Intégration native
→ Snapshots automatiques
→ Scaling facile
→ Exemple: Applications SaaS, microservices
```

**Pour un data lake / analytics :**
```yaml
S3 / Object Storage via CSI
→ Capacité illimitée
→ Coût optimisé
→ Accès concurrent
→ Exemple: Spark, Presto, données brutes
```

### 2.2 Concepts fondamentaux des PersistentVolumes

**PersistentVolume (PV)** :
- Ressource de stockage dans le cluster
- Indépendant du cycle de vie des pods
- Provisionné par l'administrateur ou dynamiquement

**PersistentVolumeClaim (PVC)** :
- Demande de stockage par un utilisateur
- Spécifie la taille et le mode d'accès
- Se lie automatiquement à un PV compatible

**Cycle de vie** :
1. **Provisioning** : Création du PV (statique ou dynamique)
2. **Binding** : Liaison PVC → PV
3. **Using** : Utilisation dans un pod
4. **Reclaiming** : Libération et recyclage

### 2.2 Modes d'accès

- **ReadWriteOnce (RWO)** : Lecture-écriture par un seul nœud
- **ReadOnlyMany (ROX)** : Lecture seule par plusieurs nœuds
- **ReadWriteMany (RWX)** : Lecture-écriture par plusieurs nœuds

### 2.3 Créer la StorageClass pour le provisionnement manuel

Avant de créer des PersistentVolumes avec un provisionnement manuel, nous devons créer une StorageClass appropriée. Sans cette StorageClass, le binding entre le PV et le PVC échouera.

Créer `02-storage-class-manual.yaml` :

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: manual
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

**Explications importantes** :

- **provisioner: kubernetes.io/no-provisioner** : Indique qu'il n'y a pas de provisionnement automatique. Les PV doivent être créés manuellement par un administrateur.
- **volumeBindingMode: WaitForFirstConsumer** : Le binding du PVC au PV ne se fera que lorsqu'un pod utilisera le PVC. Cela évite de lier un volume à un nœud avant de savoir où le pod sera schedulé.

```bash
# Créer la StorageClass
kubectl apply -f 02-storage-class-manual.yaml

# Vérifier la création
kubectl get storageclass manual
kubectl describe storageclass manual
```

**Note** : Cette étape est cruciale. Sans cette StorageClass, vous obtiendrez une erreur lors du binding du PVC car Kubernetes ne trouvera pas la StorageClass "manual" référencée dans les manifests.

### 2.4 Créer un PersistentVolume

Créer `03-persistent-volume.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-demo
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "/mnt/data"
```

**Exercice 2 : Créer un PV**

**Avec minikube :**
```bash
# Créer le répertoire sur le nœud minikube
minikube ssh "sudo mkdir -p /mnt/data"
```

**Avec kubeadm :**
```bash
# Créer le répertoire sur chaque worker (adapter le nom d'utilisateur et l'IP)
ssh user@worker-node-1 "sudo mkdir -p /mnt/data"
ssh user@worker-node-2 "sudo mkdir -p /mnt/data"

# Ou sur tous les nœuds si vous autorisez le scheduling sur le master
for node in master-node worker-node-1 worker-node-2; do
  ssh user@$node "sudo mkdir -p /mnt/data"
done
```

**Création du PV (identique pour minikube et kubeadm) :**
```bash
# Créer le PV
kubectl apply -f 03-persistent-volume.yaml

# Vérifier le PV
kubectl get pv
kubectl describe pv pv-demo
```

Vous devriez voir le statut **Available**.

### 2.5 Créer un PersistentVolumeClaim

Créer `04-persistent-volume-claim.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-demo
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
```

**Note importante sur le binding** :

Le PVC va chercher un PV compatible avec les critères suivants :
- Même `storageClassName` (ici: "manual")
- Mode d'accès compatible (ici: ReadWriteOnce)
- Capacité suffisante (ici: 500Mi, le PV a 1Gi donc c'est OK)

⚠️ **Problème courant** : Si vous voyez le PVC rester en état "Pending" indéfiniment, vérifiez que :
1. La StorageClass "manual" a bien été créée (section 2.3)
2. Un PV avec `storageClassName: manual` existe et est en état "Available"
3. Les modes d'accès et la capacité correspondent

Sans la StorageClass "manual", le binding échouera et vous verrez une erreur du type : "storageclass.storage.k8s.io 'manual' not found".

**Exercice 3 : Créer un PVC**

```bash
# Créer le PVC
kubectl apply -f 04-persistent-volume-claim.yaml

# Vérifier le PVC
kubectl get pvc
kubectl describe pvc pvc-demo

# Revérifier le PV
kubectl get pv
```

Le PV devrait maintenant être **Bound** au PVC.

### 2.6 Utiliser le PVC dans un Pod

Créer `05-pod-with-pvc.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-pvc
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: persistent-storage
      mountPath: /usr/share/nginx/html

  volumes:
  - name: persistent-storage
    persistentVolumeClaim:
      claimName: pvc-demo
```

**Exercice 4 : Tester la persistance**

```bash
# Créer le pod
kubectl apply -f 05-pod-with-pvc.yaml

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod/pod-with-pvc --timeout=60s

# Écrire un fichier HTML dans le volume
kubectl exec pod-with-pvc -- sh -c 'echo "<h1>Persistent Data!</h1>" > /usr/share/nginx/html/index.html'

# Vérifier avec port-forward
kubectl port-forward pod/pod-with-pvc 8080:80 &
curl localhost:8080
pkill -f "port-forward"

# Supprimer le pod
kubectl delete pod pod-with-pvc

# Recréer le pod
kubectl apply -f 05-pod-with-pvc.yaml

# Attendre que le pod soit prêt
kubectl wait --for=condition=ready pod/pod-with-pvc --timeout=60s

# Vérifier que les données sont toujours là
kubectl exec pod-with-pvc -- cat /usr/share/nginx/html/index.html
```

Les données persistent malgré la suppression du pod !

## Partie 3 : StorageClass et provisionnement dynamique

### 3.1 Qu'est-ce qu'une StorageClass ?

Une StorageClass permet de définir différentes classes de stockage avec provisionnement automatique des PV.

**Avantages** :
- Pas besoin de créer les PV manuellement
- Provisionnement à la demande
- Différentes classes pour différents besoins (SSD, HDD, etc.)

### 3.2 StorageClass par défaut

```bash
# Lister les StorageClasses disponibles
kubectl get storageclass

# Décrire la StorageClass par défaut
kubectl describe storageclass standard
```

**Avec minikube :** La StorageClass `standard` utilise le provisioner `k8s.io/minikube-hostpath`.

**Avec kubeadm :** La StorageClass par défaut dépend de votre installation. Avec l'installation de base kubeadm, **aucune StorageClass** n'est créée par défaut. Vous devez :
- Soit installer un provisioner comme [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- Soit utiliser un provisioner cloud si vous êtes sur un cloud provider
- Soit créer manuellement les PV (provisionnement statique)

**Installation de local-path-provisioner pour kubeadm :**
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml

# Définir comme StorageClass par défaut
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Vérifier
kubectl get storageclass
```

### 3.3 Créer une StorageClass personnalisée

**Pour minikube :**

Créer `06-storage-class-minikube.yaml` :

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: k8s.io/minikube-hostpath
parameters:
  type: pd-ssd
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

**Pour kubeadm (avec local-path-provisioner) :**

Créer `06-storage-class-kubeadm.yaml` :

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
# Créer la StorageClass (adapter le nom du fichier selon votre environnement)
kubectl apply -f 06-storage-class-minikube.yaml  # Pour minikube
# OU
kubectl apply -f 06-storage-class-kubeadm.yaml   # Pour kubeadm

# Vérifier
kubectl get storageclass
```

### 3.4 PVC avec provisionnement dynamique

Créer `07-dynamic-pvc.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
```

**Exercice 5 : Provisionnement dynamique**

```bash
# Créer le PVC
kubectl apply -f 07-dynamic-pvc.yaml

# Observer la création automatique du PV
kubectl get pvc dynamic-pvc
kubectl get pv

# Un PV a été créé automatiquement !
```

## Partie 4 : Cas pratique - Base de données MySQL

### 4.1 Déploiement MySQL avec persistance

Créer `08-mysql-deployment.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
stringData:
  mysql-root-password: "MotDePasseSecurise123"
  mysql-database: "app_db"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  labels:
    app: mysql
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
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-root-password
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-database
        volumeMounts:
        - name: mysql-storage
          mountPath: /var/lib/mysql
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      volumes:
      - name: mysql-storage
        persistentVolumeClaim:
          claimName: mysql-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
  clusterIP: None  # Headless service
```

**Exercice 6 : Déployer MySQL**

```bash
# Appliquer le manifest complet
kubectl apply -f 08-mysql-deployment.yaml

# Vérifier les ressources créées
kubectl get pvc mysql-pvc
kubectl get deployment mysql
kubectl get pods -l app=mysql
kubectl get svc mysql

# Attendre que MySQL soit prêt
kubectl wait --for=condition=ready pod -l app=mysql --timeout=120s

# Voir les logs de MySQL
kubectl logs -l app=mysql
```

### 4.2 Tester MySQL

```bash
# Se connecter à MySQL
kubectl exec -it deployment/mysql -- mysql -uroot -pMotDePasseSecurise123

# Dans le shell MySQL, exécuter :
# SHOW DATABASES;
# USE app_db;
# CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(50));
# INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob');
# SELECT * FROM users;
# EXIT;
```

**Exercice 7 : Vérifier la persistance**

```bash
# Supprimer le pod MySQL
kubectl delete pod -l app=mysql

# Attendre que le deployment recrée le pod
kubectl wait --for=condition=ready pod -l app=mysql --timeout=120s

# Se reconnecter
kubectl exec -it deployment/mysql -- mysql -uroot -pMotDePasseSecurise123

# Vérifier que les données sont toujours là :
# USE app_db;
# SELECT * FROM users;
# EXIT;
```

Les données ont survécu à la suppression du pod !

### 4.3 Client MySQL pour tester

Créer `09-mysql-client.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql-client
spec:
  containers:
  - name: mysql-client
    image: mysql:8.0
    command: ['sh', '-c', 'sleep 3600']
```

```bash
# Créer le client
kubectl apply -f 09-mysql-client.yaml

# Se connecter depuis le client
kubectl exec -it mysql-client -- mysql -h mysql -uroot -pMotDePasseSecurise123

# Dans MySQL :
# USE app_db;
# SELECT * FROM users;
# EXIT;
```

## Partie 5 : Gestion avancée du stockage

### 5.1 Expansion de volume

L'expansion de volume permet d'augmenter la taille d'un PVC existant sans recréer le volume. Cette fonctionnalité dépend de deux conditions :

1. La StorageClass doit avoir `allowVolumeExpansion: true`
2. Le driver de stockage doit supporter l'expansion

**Étape 1 : Vérifier que la StorageClass permet l'expansion**

```bash
# Vérifier la StorageClass standard de minikube
kubectl get storageclass standard -o yaml | grep allowVolumeExpansion
```

**Important** : Si `allowVolumeExpansion` n'est pas présent ou est `false`, vous avez deux options :

**Option A** : Utiliser la StorageClass `fast-storage` créée dans la partie 3.3 qui supporte l'expansion :

```bash
# Créer un nouveau PVC avec fast-storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: expandable-pvc
spec:
  storageClassName: fast-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF

# Vérifier que le PVC est bien créé
kubectl get pvc expandable-pvc

# Éditer le PVC pour augmenter la taille
kubectl edit pvc expandable-pvc

# Modifier storage: 2Gi en storage: 5Gi
# Sauvegarder et quitter

# Vérifier l'expansion
kubectl get pvc expandable-pvc
kubectl describe pvc expandable-pvc
```

**Option B** : Activer l'expansion sur la StorageClass standard (si vous avez les permissions) :

```bash
# Éditer la StorageClass standard
kubectl patch storageclass standard -p '{"allowVolumeExpansion": true}'

# Vérifier la modification
kubectl get storageclass standard -o yaml | grep allowVolumeExpansion

# Maintenant vous pouvez éditer le PVC dynamic-pvc
kubectl edit pvc dynamic-pvc

# Modifier storage: 2Gi en storage: 5Gi
# Sauvegarder et quitter

# Vérifier l'expansion
kubectl get pvc dynamic-pvc
kubectl describe pvc dynamic-pvc
```

**Note** : L'expansion de volume peut nécessiter un redémarrage du pod utilisant le PVC pour que la nouvelle taille soit reconnue par le système de fichiers.

#### 5.1.1 Troubleshooting : La taille n'a pas changé

Si après l'expansion du PVC, la taille ne se reflète pas dans le pod, voici les étapes de diagnostic et résolution :

**Étape 1 : Vérifier le statut du PVC**

```bash
# Vérifier l'état de l'expansion
kubectl get pvc <nom-du-pvc>
kubectl describe pvc <nom-du-pvc>

# Chercher des messages comme :
# - "Waiting for user to (re-)start a pod to finish file system resize"
# - "FileSystemResizePending"
```

**Étape 2 : Vérifier la taille dans le pod**

```bash
# Vérifier la taille actuelle du volume dans le pod
kubectl exec <nom-du-pod> -- df -h <point-de-montage>

# Exemple avec le PVC monté sur /data :
kubectl exec my-pod -- df -h /data
```

**Solutions selon le problème identifié :**

**Solution 1 : Redémarrer le pod (le plus courant)**

```bash
# Si c'est un pod autonome
kubectl delete pod <nom-du-pod>
kubectl apply -f <fichier-du-pod>.yaml

# Si c'est un Deployment
kubectl rollout restart deployment <nom-du-deployment>

# Attendre que le nouveau pod soit prêt
kubectl wait --for=condition=ready pod -l app=<label> --timeout=120s

# Vérifier à nouveau la taille
kubectl exec <nom-du-pod> -- df -h <point-de-montage>
```

**Solution 2 : Redimensionner manuellement le système de fichiers**

Si le redémarrage du pod ne suffit pas, il faut redimensionner manuellement le système de fichiers :

```bash
# Pour un système de fichiers ext4
kubectl exec <nom-du-pod> -- resize2fs <device>

# Exemple avec le device par défaut
kubectl exec my-pod -- sh -c 'df -h /data && resize2fs $(df /data | tail -1 | cut -d" " -f1) && df -h /data'

# Pour un système de fichiers XFS
kubectl exec <nom-du-pod> -- xfs_growfs <point-de-montage>

# Exemple
kubectl exec my-pod -- xfs_growfs /data
```

**Solution 3 : Vérifier les conditions du PVC**

```bash
# Afficher les détails complets du PVC
kubectl get pvc <nom-du-pvc> -o yaml

# Chercher dans status.conditions pour des erreurs
# Vérifier status.capacity vs spec.resources.requests.storage
```

**Solution 4 : Vérifier les logs du contrôleur**

```bash
# Vérifier les logs du provisioner de stockage
kubectl logs -n kube-system -l app=storage-provisioner

# Pour minikube spécifiquement
minikube logs | grep -i "resize\|expand"
```

**Exemple complet de test d'expansion :**

```bash
# 1. Créer un pod de test avec le PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-expansion
spec:
  containers:
  - name: busybox
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: expandable-pvc
EOF

# 2. Vérifier la taille initiale
kubectl exec test-expansion -- df -h /data

# 3. Étendre le PVC
kubectl patch pvc expandable-pvc -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'

# 4. Vérifier le statut de l'expansion
kubectl describe pvc expandable-pvc

# 5. Redémarrer le pod
kubectl delete pod test-expansion
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-expansion
spec:
  containers:
  - name: busybox
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: expandable-pvc
EOF

# 6. Attendre et vérifier la nouvelle taille
kubectl wait --for=condition=ready pod/test-expansion --timeout=60s
kubectl exec test-expansion -- df -h /data

# Nettoyage
kubectl delete pod test-expansion
```

**Limitations connues :**

- Certains drivers de stockage ne supportent que l'expansion en ligne (sans redémarrage)
- D'autres nécessitent obligatoirement un redémarrage du pod
- L'expansion n'est jamais possible en réduction (shrink), seulement en augmentation
- Le provisioner `k8s.io/minikube-hostpath` supporte l'expansion mais nécessite un redémarrage

### 5.2 Installation du driver CSI

Pour utiliser des fonctionnalités avancées comme les snapshots de volumes, il est nécessaire d'installer le driver CSI (Container Storage Interface).

**Pourquoi installer le CSI driver ?**

Le driver CSI `csi-hostpath-driver` permet :
- La création de snapshots de volumes
- La restauration de volumes à partir de snapshots
- Le clonage de volumes
- Une gestion plus avancée du stockage

#### Option A : Avec minikube

```bash
# Activer l'addon csi-hostpath-driver sur minikube
minikube addons enable csi-hostpath-driver

# Vérifier que l'addon est activé
minikube addons list | grep csi-hostpath-driver

# Attendre que les pods CSI soient prêts
kubectl wait --for=condition=ready pod -n kube-system -l app=csi-hostpath-driver --timeout=120s
```

#### Option B : Avec kubeadm

**Installation manuelle du csi-hostpath-driver :**

```bash
# Cloner le repo du driver CSI hostpath
git clone https://github.com/kubernetes-csi/csi-driver-host-path.git
cd csi-driver-host-path

# Déployer le driver
./deploy/kubernetes-latest/deploy.sh

# Vérifier le déploiement
kubectl get pods -n default | grep csi

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=csi-hostpathplugin --timeout=120s
```

**Alternative : Utiliser le manifest direct :**

```bash
# Installer les CRDs pour les snapshots
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Installer le snapshot controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

# Installer le driver hostpath
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master/deploy/kubernetes-latest/hostpath/csi-hostpath-driverinfo.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master/deploy/kubernetes-latest/hostpath/csi-hostpath-plugin.yaml
```

**Vérification de l'installation**

```bash
# Vérifier les pods CSI dans kube-system
kubectl get pods -n kube-system | grep csi

# Vérifier la VolumeSnapshotClass créée automatiquement
kubectl get volumesnapshotclass

# Vérifier le driver CSI
kubectl get csidrivers
```

Vous devriez voir :
- Les pods `csi-hostpath-driver-*` en état `Running`
- Une `VolumeSnapshotClass` nommée `csi-hostpath-snapclass`
- Le driver `hostpath.csi.k8s.io` dans la liste des CSI drivers

**Note** : Sur minikube, le driver CSI utilise également le stockage local du nœud, mais offre des fonctionnalités supplémentaires par rapport au provisioner standard.

### 5.3 Politiques de réclamation (Reclaim Policies)

Les PV ont différentes politiques de réclamation :

- **Retain** : Conserver les données après suppression du PVC
- **Delete** : Supprimer le PV et les données (défaut pour provisionnement dynamique)
- **Recycle** : Effacer les données et rendre le PV disponible (obsolète)

Créer `10-pv-retain.yaml` :

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-retain
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: "/mnt/data-retain"
```

### 5.4 Snapshots de volumes (avancé)

Les snapshots permettent de créer des sauvegardes ponctuelles de vos volumes. Grâce au driver CSI installé dans la section précédente, vous pouvez maintenant créer des snapshots.

**Installation de la VolumeSnapshotClass sur minikube**

Sur minikube, même après avoir activé l'addon `csi-hostpath-driver`, la `VolumeSnapshotClass` nécessaire pour créer des snapshots n'est pas automatiquement créée. Il faut activer un addon supplémentaire.

```bash
# Activer l'addon volumesnapshots (qui inclut csi-hostpath-snapclass)
minikube addons enable volumesnapshots

# Vérifier que l'addon est activé
minikube addons list | grep volumesnapshots

# Vérifier que la VolumeSnapshotClass a été créée
kubectl get volumesnapshotclass

# Vous devriez voir : csi-hostpath-snapclass
```

**Alternative : Créer manuellement la VolumeSnapshotClass**

Si l'addon `volumesnapshots` n'est pas disponible, vous pouvez créer manuellement la VolumeSnapshotClass :

```bash
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-hostpath-snapclass
driver: hostpath.csi.k8s.io
deletionPolicy: Delete
EOF

# Vérifier la création
kubectl get volumesnapshotclass
kubectl describe volumesnapshotclass csi-hostpath-snapclass
```

**Note importante** : Sans la VolumeSnapshotClass, vous obtiendrez une erreur lors de la création de snapshots indiquant que la classe n'existe pas.

**Création d'un snapshot**

Créer `11-volume-snapshot.yaml` :

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-snapshot
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: mysql-pvc
```

**Exercice 8 : Créer et utiliser un snapshot**

```bash
# 1. Créer le snapshot du PVC MySQL
kubectl apply -f 11-volume-snapshot.yaml

# 2. Vérifier le snapshot
kubectl get volumesnapshot
kubectl describe volumesnapshot mysql-snapshot

# 3. Restaurer depuis un snapshot - créer un nouveau PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc-restored
spec:
  storageClassName: csi-hostpath-sc
  dataSource:
    name: mysql-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# 4. Vérifier le nouveau PVC
kubectl get pvc mysql-pvc-restored
```

**Note** : Les snapshots sont utiles pour :
- Sauvegardes avant modifications importantes
- Clonage rapide de volumes
- Tests et développement
- Récupération après incident

## Partie 6 : Bonnes pratiques

### 6.1 Bonnes pratiques générales

1. **Utiliser le provisionnement dynamique** quand possible
   - Évite la gestion manuelle des PV
   - Simplifie les déploiements

2. **Définir des limites de ressources**
   - Spécifier la taille exacte nécessaire
   - Éviter le gaspillage de stockage

3. **Choisir le bon mode d'accès**
   - RWO pour bases de données
   - RWX pour applications multi-nœuds

4. **Utiliser des StorageClasses appropriées**
   - SSD pour performance
   - HDD pour stockage économique

5. **Sauvegarder régulièrement**
   - Utiliser des snapshots
   - Exporter les données critiques

### 6.2 Sécurité du stockage - Guide complet

La sécurité du stockage est critique dans Kubernetes. Un volume mal configuré peut exposer des données sensibles, compromettre le cluster ou donner accès au système de fichiers de l'hôte.

#### 6.2.1 Chiffrement des données

##### A. Chiffrement at-rest (données au repos)

**🔒 Règle d'or :** Toutes les données sensibles doivent être chiffrées au repos, que ce soit dans le cloud ou on-premise.

**Option 1 : Chiffrement au niveau du cloud provider**

```yaml
# AWS EBS avec chiffrement KMS
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: encrypted-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: "arn:aws:kms:us-east-1:123456789:key/your-key-id"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

```yaml
# Azure Disk avec chiffrement
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: encrypted-premium
provisioner: disk.csi.azure.com
parameters:
  storageaccounttype: Premium_LRS
  kind: Managed
  diskEncryptionSetID: "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/diskEncryptionSets/{des}"
allowVolumeExpansion: true
```

```yaml
# GCP Persistent Disk avec chiffrement CMEK
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: encrypted-pd-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  disk-encryption-kms-key: "projects/PROJECT_ID/locations/LOCATION/keyRings/RING_NAME/cryptoKeys/KEY_NAME"
allowVolumeExpansion: true
```

**Option 2 : Chiffrement au niveau de l'application (LUKS)**

```yaml
# StatefulSet avec init container pour chiffrement LUKS
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: secure-database
spec:
  serviceName: secure-db
  replicas: 1
  selector:
    matchLabels:
      app: secure-db
  template:
    metadata:
      labels:
        app: secure-db
    spec:
      # Init container pour configurer LUKS
      initContainers:
      - name: luks-setup
        image: alpine:latest
        command:
        - sh
        - -c
        - |
          apk add --no-cache cryptsetup
          if [ ! -e /dev/mapper/encrypted ]; then
            echo "Setting up LUKS encryption..."
            # Récupérer la clé depuis un Secret
            LUKS_KEY=$(cat /secrets/luks-key)
            echo -n "$LUKS_KEY" | cryptsetup luksFormat /dev/xvdf -
            echo -n "$LUKS_KEY" | cryptsetup luksOpen /dev/xvdf encrypted -
            mkfs.ext4 /dev/mapper/encrypted
          else
            echo "LUKS already configured"
          fi
        securityContext:
          privileged: true  # Nécessaire pour cryptsetup
        volumeMounts:
        - name: luks-key
          mountPath: /secrets
          readOnly: true
        - name: raw-storage
          mountPath: /dev/xvdf

      containers:
      - name: database
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: encrypted-storage
          mountPath: /var/lib/postgresql/data
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true

      volumes:
      - name: luks-key
        secret:
          secretName: luks-encryption-key
      - name: raw-storage
        persistentVolumeClaim:
          claimName: raw-pvc
      - name: encrypted-storage
        emptyDir: {}
```

##### B. Chiffrement in-transit (données en transit)

Pour NFS et autres protocoles réseau:

```yaml
# NFS avec stunnel pour chiffrement TLS
apiVersion: v1
kind: ConfigMap
metadata:
  name: stunnel-config
data:
  stunnel.conf: |
    [nfs]
    client = yes
    accept = 127.0.0.1:2049
    connect = nfs-server.internal:2050
    cert = /etc/stunnel/certs/client.pem
    key = /etc/stunnel/certs/client.key
    CAfile = /etc/stunnel/certs/ca.pem
    verify = 2
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-nfs-client
spec:
  containers:
  # Sidecar stunnel pour chiffrer le trafic NFS
  - name: stunnel
    image: dweomer/stunnel:latest
    volumeMounts:
    - name: stunnel-config
      mountPath: /etc/stunnel/stunnel.conf
      subPath: stunnel.conf
    - name: stunnel-certs
      mountPath: /etc/stunnel/certs
      readOnly: true
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      capabilities:
        drop:
        - ALL

  # Application qui utilise NFS via stunnel
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: secure-nfs
      mountPath: /data

  volumes:
  - name: stunnel-config
    configMap:
      name: stunnel-config
  - name: stunnel-certs
    secret:
      secretName: stunnel-tls-certs
  - name: secure-nfs
    nfs:
      server: 127.0.0.1  # Via stunnel local
      path: /exports/data
```

#### 6.2.2 Contrôle d'accès et permissions

##### A. SecurityContext pour les volumes

**🔒 Règle :** Toujours spécifier un SecurityContext pour contrôler les permissions des volumes.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod-with-volume
spec:
  # SecurityContext au niveau Pod
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000  # Groupe propriétaire des volumes montés
    fsGroupChangePolicy: "OnRootMismatch"
    seccompProfile:
      type: RuntimeDefault

  containers:
  - name: app
    image: nginx:alpine
    # SecurityContext au niveau container
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: true

    volumeMounts:
    - name: data
      mountPath: /data
      readOnly: false  # Lecture-écriture
    - name: config
      mountPath: /etc/nginx/conf.d
      readOnly: true  # Lecture seule pour les configs
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run

  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data
  - name: config
    configMap:
      name: nginx-config
      defaultMode: 0440  # r--r-----
  - name: cache
    emptyDir:
      sizeLimit: 500Mi
  - name: run
    emptyDir:
      medium: Memory  # tmpfs pour les fichiers runtime
      sizeLimit: 100Mi
```

##### B. Isolation des volumes avec SELinux/AppArmor

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: selinux-secured-pod
  annotations:
    # AppArmor profile (sur Ubuntu/Debian)
    container.apparmor.security.beta.kubernetes.io/app: localhost/k8s-apparmor-example
spec:
  securityContext:
    # SELinux (sur RHEL/CentOS)
    seLinuxOptions:
      level: "s0:c123,c456"
      role: "object_r"
      type: "svirt_sandbox_file_t"
      user: "system_u"

  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: data
      mountPath: /data
    securityContext:
      seLinuxOptions:
        level: "s0:c123,c456"

  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: selinux-pvc
```

#### 6.2.3 Limitation des ressources et quotas

##### A. ResourceQuotas pour le stockage

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: production
spec:
  hard:
    # Limite le nombre de PVC
    persistentvolumeclaims: "10"

    # Limite la capacité totale demandée
    requests.storage: "500Gi"

    # Limite par StorageClass
    requests.storage.storageclass.storage.k8s.io/fast-ssd: "100Gi"
    requests.storage.storageclass.storage.k8s.io/standard: "400Gi"

    # Limite le nombre de PVC par classe
    persistentvolumeclaims.storageclass.storage.k8s.io/fast-ssd: "5"
```

##### B. LimitRange pour les PVC

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: storage-limits
  namespace: production
spec:
  limits:
  - type: PersistentVolumeClaim
    max:
      storage: 100Gi  # Taille max par PVC
    min:
      storage: 1Gi    # Taille min par PVC
    default:
      storage: 10Gi   # Taille par défaut
```

#### 6.2.4 Network Policies pour le stockage

```yaml
# Limiter l'accès au serveur NFS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nfs-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      role: nfs-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    # Seulement les pods avec ce label peuvent accéder au NFS
    - podSelector:
        matchLabels:
          access-nfs: "true"
    # Seulement depuis le namespace production
    - namespaceSelector:
        matchLabels:
          name: production
    ports:
    - protocol: TCP
      port: 2049
    - protocol: TCP
      port: 111
```

#### 6.2.5 Audit et surveillance

##### A. Audit des accès aux volumes

```yaml
# Configuration d'audit pour surveiller les accès aux volumes
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Auditer toutes les opérations sur les PV/PVC
- level: RequestResponse
  resources:
  - group: ""
    resources: ["persistentvolumes", "persistentvolumeclaims"]

# Auditer les modifications de StorageClass
- level: RequestResponse
  resources:
  - group: "storage.k8s.io"
    resources: ["storageclasses"]
  verbs: ["create", "update", "patch", "delete"]

# Auditer les accès aux Secrets (souvent utilisés pour les credentials de stockage)
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
  verbs: ["get", "list", "watch"]
```

##### B. Monitoring de l'utilisation du stockage

```yaml
# ServiceMonitor pour Prometheus (avec kube-state-metrics)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: storage-monitoring
spec:
  selector:
    matchLabels:
      app: kube-state-metrics
  endpoints:
  - port: http-metrics
    interval: 30s

---
# PrometheusRule pour alertes de stockage
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: storage-alerts
spec:
  groups:
  - name: storage
    interval: 30s
    rules:
    # Alerte si PVC presque plein
    - alert: PVCAlmostFull
      expr: |
        (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} presque plein"
        description: "Le PVC {{ $labels.persistentvolumeclaim }} est utilisé à {{ $value | humanizePercentage }}"

    # Alerte si PVC en état Pending
    - alert: PVCPending
      expr: |
        kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} en attente de binding"

    # Alerte si PV pas utilisé depuis longtemps
    - alert: UnusedPV
      expr: |
        kube_persistentvolume_status_phase{phase="Available"} == 1
      for: 7d
      labels:
        severity: info
      annotations:
        summary: "PV {{ $labels.persistentvolume }} non utilisé depuis 7 jours"
```

#### 6.2.6 Checklist de sécurité pour le stockage

##### ✅ Avant de déployer en production

**Chiffrement:**
- [ ] Données at-rest chiffrées (KMS, LUKS, ou chiffrement provider)
- [ ] Données in-transit chiffrées (TLS, stunnel pour NFS)
- [ ] Rotation des clés de chiffrement configurée

**Accès et permissions:**
- [ ] SecurityContext défini avec runAsNonRoot: true
- [ ] fsGroup et fsGroupChangePolicy configurés
- [ ] Volumes en readOnly quand possible
- [ ] Pas de hostPath en production (sauf cas exceptionnel documenté)
- [ ] Pas de volumes montés avec privileged: true

**Isolation:**
- [ ] NetworkPolicies limitant l'accès aux backends de stockage
- [ ] Namespaces séparés pour environnements différents
- [ ] RBAC limitant qui peut créer/modifier les PV/PVC
- [ ] SELinux ou AppArmor configuré

**Quotas et limites:**
- [ ] ResourceQuota défini par namespace
- [ ] LimitRange configuré pour les PVC
- [ ] Taille maximale des PVC limitée

**Sauvegardes et récupération:**
- [ ] Snapshots réguliers configurés
- [ ] Backup hors cluster (S3, backup système)
- [ ] Plan de disaster recovery testé
- [ ] ReclaimPolicy appropriée (Retain pour production)

**Monitoring:**
- [ ] Métriques de stockage collectées
- [ ] Alertes configurées (espace disque, PVC pending, etc.)
- [ ] Audit logs activés pour les opérations sensibles
- [ ] Dashboard de visualisation déployé

**Documentation:**
- [ ] Architecture de stockage documentée
- [ ] Procédures de backup/restore documentées
- [ ] Politique de rétention définie
- [ ] Contacts et escalade en cas d'incident

##### ❌ Anti-patterns à éviter

```yaml
# ❌ MAUVAIS : hostPath avec accès root
apiVersion: v1
kind: Pod
metadata:
  name: dangerous-pod
spec:
  containers:
  - name: app
    image: myapp
    securityContext:
      privileged: true  # ❌ Accès complet au système
    volumeMounts:
    - name: host-root
      mountPath: /host
  volumes:
  - name: host-root
    hostPath:
      path: /  # ❌ Monte la racine de l'hôte !
      type: Directory
```

```yaml
# ❌ MAUVAIS : Secret en clair dans le YAML
apiVersion: v1
kind: Secret
metadata:
  name: bad-secret
type: Opaque
stringData:
  password: "SuperSecretPassword123"  # ❌ En clair dans Git !
```

```yaml
# ❌ MAUVAIS : PVC sans limite de taille
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: unlimited-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1000Ti  # ❌ Demande énorme sans justification
  storageClassName: expensive-ssd
```

```yaml
# ❌ MAUVAIS : Volume partagé entre namespaces sans contrôle
apiVersion: v1
kind: PersistentVolume
metadata:
  name: shared-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: nfs-server
    path: /shared  # ❌ Accessible depuis tous les namespaces
  # ❌ Pas de restrictions d'accès
```

##### ✅ Bonnes pratiques

```yaml
# ✅ BON : Pod sécurisé avec volume
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: production
spec:
  serviceAccountName: limited-sa
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault

  containers:
  - name: app
    image: myapp:1.2.3  # ✅ Version précise
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL

    volumeMounts:
    - name: data
      mountPath: /data
    - name: tmp
      mountPath: /tmp

    resources:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"

  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: encrypted-pvc  # ✅ PVC avec chiffrement
  - name: tmp
    emptyDir:
      sizeLimit: 100Mi  # ✅ Limite de taille
```

```yaml
# ✅ BON : StorageClass sécurisée avec chiffrement
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: secure-storage
  labels:
    environment: production
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  encrypted: "true"  # ✅ Chiffrement activé
  kmsKeyId: "arn:aws:kms:region:account:key/key-id"
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain  # ✅ Prevent accidental data loss
```

```yaml
# ✅ BON : RBAC restrictif pour le stockage
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pvc-user
  namespace: production
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]  # ✅ Read-only pour les utilisateurs
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["create", "delete"]
  resourceNames: []  # ✅ Pas de delete sans review
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pvc-admin
  namespace: production
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["*"]  # ✅ Full access pour les admins seulement
```

### 6.3 Monitoring du stockage

```bash
# Vérifier l'utilisation des PV
kubectl get pv

# Vérifier l'utilisation des PVC
kubectl get pvc --all-namespaces

# Décrire un PVC pour voir l'utilisation
kubectl describe pvc mysql-pvc

# Voir l'utilisation dans un pod
kubectl exec <pod-name> -- df -h /mount/path
```

## Partie 7 : Exercices pratiques

### Exercice Final 1 : Déployer MySQL avec sécurité renforcée

Utilisez le fichier `12-mysql-deployment-secure.yaml` pour déployer MySQL avec toutes les bonnes pratiques de sécurité.

**Objectifs :**
- Comprendre les SecurityContext et leur impact sur les volumes
- Implémenter des NetworkPolicies pour isoler la base de données
- Utiliser des init containers pour préparer les volumes
- Configurer des probes de santé
- Monitorer l'utilisation du stockage

**Étapes :**

```bash
# 1. Créer un namespace dédié
kubectl create namespace production

# 2. Appliquer le déploiement sécurisé
kubectl apply -f 12-mysql-deployment-secure.yaml

# 3. Vérifier le déploiement
kubectl get all -n production -l app=mysql
kubectl get pvc -n production
kubectl get networkpolicies -n production

# 4. Vérifier les SecurityContext
kubectl describe pod -n production -l app=mysql | grep -A 10 "Security Context"

# 5. Tester la connexion (créer un pod client autorisé)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mysql-client
  namespace: production
  labels:
    access-mysql: "true"  # Important pour la NetworkPolicy
spec:
  containers:
  - name: mysql-client
    image: mysql:8.0
    command: ['sh', '-c', 'sleep 3600']
  securityContext:
    runAsNonRoot: true
    runAsUser: 999
EOF

# 6. Se connecter à MySQL
kubectl exec -it -n production mysql-client -- mysql -h mysql-secure-svc -uroot -pVotreMotDePasseComplexe!2024

# Dans MySQL:
# SHOW DATABASES;
# USE app_production;
# CREATE TABLE test_security (id INT PRIMARY KEY, data VARCHAR(100));
# INSERT INTO test_security VALUES (1, 'Données sécurisées');
# SELECT * FROM test_security;
# EXIT;

# 7. Vérifier la persistance: supprimer le pod MySQL
kubectl delete pod -n production -l app=mysql

# 8. Attendre la recréation et vérifier les données
kubectl wait --for=condition=ready pod -n production -l app=mysql --timeout=120s
kubectl exec -it -n production mysql-client -- mysql -h mysql-secure-svc -uroot -pVotreMotDePasseComplexe!2024 -e "SELECT * FROM app_production.test_security;"

# 9. Vérifier les métriques (si Prometheus installé)
kubectl port-forward -n production svc/mysql-secure-svc 9104:9104 &
curl localhost:9104/metrics | grep mysql_
pkill -f "port-forward"

# 10. Nettoyage
kubectl delete namespace production
```

**Questions de réflexion :**
1. Pourquoi utilise-t-on `fsGroup: 999` dans le SecurityContext ?
2. Quel est l'avantage d'une NetworkPolicy pour MySQL ?
3. Pourquoi `readOnlyRootFilesystem: true` n'est pas possible pour MySQL ?
4. Comment les init containers améliorent-ils la sécurité ?

### Exercice Final 2 : Comparer différentes StorageClasses

Utilisez le fichier `13-storage-class-examples-secure.yaml` pour comprendre les différences entre les types de stockage.

**Objectifs :**
- Comprendre les paramètres de chaque StorageClass
- Apprendre à choisir la bonne classe selon le cas d'usage
- Implémenter des quotas et limites
- Configurer le chiffrement

**Étapes :**

```bash
# 1. Analyser les StorageClasses disponibles
kubectl get storageclass
kubectl describe storageclass standard

# 2. Créer une StorageClass personnalisée (adapter selon votre environnement)
# Pour minikube:
cat > my-storage-class.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-encrypted
  labels:
    environment: production
provisioner: k8s.io/minikube-hostpath
parameters:
  type: local
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF

kubectl apply -f my-storage-class.yaml

# 3. Créer des PVC avec différentes StorageClasses
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-standard
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-fast-encrypted
spec:
  storageClassName: fast-encrypted
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# 4. Comparer les PV créés
kubectl get pv
kubectl describe pv | grep -E "Name:|StorageClass:|Reclaim Policy:"

# 5. Appliquer des quotas (créer un namespace de test)
kubectl create namespace quota-test
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: quota-test
spec:
  hard:
    requests.storage: "20Gi"
    persistentvolumeclaims: "5"
EOF

# 6. Tester le quota
kubectl get resourcequota -n quota-test storage-quota

# Essayer de créer 6 PVC de 5Gi chacun (devrait échouer au 5ème)
for i in {1..6}; do
  kubectl apply -n quota-test -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-test-$i
spec:
  storageClassName: standard
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
done

# Vérifier les erreurs
kubectl describe resourcequota -n quota-test storage-quota

# 7. Nettoyage
kubectl delete namespace quota-test
kubectl delete pvc pvc-standard pvc-fast-encrypted
```

**Questions de réflexion :**
1. Quelle est la différence entre `volumeBindingMode: Immediate` et `WaitForFirstConsumer` ?
2. Pourquoi utiliser `reclaimPolicy: Retain` en production ?
3. Comment le chiffrement est-il configuré dans les différents clouds ?
4. Quel est l'impact des quotas sur la gestion des ressources ?

### Exercice Final 3 : Stockage réseau et partage de données

Utilisez le fichier `14-network-storage-examples-secure.yaml` pour explorer les options de stockage réseau.

**Objectifs :**
- Configurer un stockage NFS partagé
- Comprendre les modes d'accès (RWO, ROX, RWX)
- Implémenter le partage de données entre pods
- Sécuriser l'accès au stockage réseau

**Étapes :**

```bash
# 1. Déployer un serveur NFS de test (UNIQUEMENT pour dev/test)
kubectl create namespace storage-system
kubectl apply -f 14-network-storage-examples-secure.yaml

# Attendre que le serveur NFS soit prêt
kubectl wait --for=condition=ready pod -n storage-system -l app=nfs-server --timeout=120s

# 2. Vérifier le service NFS
kubectl get svc -n storage-system nfs-server
kubectl describe svc -n storage-system nfs-server

# 3. Créer un PV NFS pointant vers notre serveur
NFS_SERVER_IP=$(kubectl get svc -n storage-system nfs-server -o jsonpath='{.spec.clusterIP}')

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-test-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: ${NFS_SERVER_IP}
    path: "/"
  mountOptions:
    - nfsvers=4.1
    - hard
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  storageClassName: ""
  volumeName: nfs-test-pv
EOF

# 4. Déployer un writer (écrit des fichiers)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-writer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-writer
  template:
    metadata:
      labels:
        app: nfs-writer
    spec:
      containers:
      - name: writer
        image: busybox
        command:
        - sh
        - -c
        - |
          while true; do
            echo "\$(date): Message from writer" >> /data/shared.log
            sleep 5
          done
        volumeMounts:
        - name: nfs-storage
          mountPath: /data
      volumes:
      - name: nfs-storage
        persistentVolumeClaim:
          claimName: nfs-test-pvc
EOF

# 5. Déployer plusieurs readers (lisent les fichiers)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-reader
spec:
  replicas: 3  # 3 replicas qui lisent en même temps
  selector:
    matchLabels:
      app: nfs-reader
  template:
    metadata:
      labels:
        app: nfs-reader
    spec:
      containers:
      - name: reader
        image: busybox
        command:
        - sh
        - -c
        - |
          while true; do
            echo "=== Latest logs from \$(hostname) ==="
            tail -n 3 /data/shared.log
            sleep 10
          done
        volumeMounts:
        - name: nfs-storage
          mountPath: /data
          readOnly: true  # Lecture seule
      volumes:
      - name: nfs-storage
        persistentVolumeClaim:
          claimName: nfs-test-pvc
EOF

# 6. Vérifier que les readers lisent les données du writer
kubectl logs -l app=nfs-reader --tail=10

# 7. Vérifier le partage: écrire depuis un reader (devrait échouer car readOnly)
READER_POD=$(kubectl get pod -l app=nfs-reader -o jsonpath='{.items[0].metadata.name}')
kubectl exec $READER_POD -- sh -c 'echo "test" >> /data/shared.log' 2>&1 | grep "Read-only"

# 8. Vérifier que tous les readers voient les mêmes données
for pod in $(kubectl get pods -l app=nfs-reader -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Pod: $pod ==="
  kubectl exec $pod -- tail -n 2 /data/shared.log
done

# 9. Test de performance: écrire beaucoup de données
WRITER_POD=$(kubectl get pod -l app=nfs-writer -o jsonpath='{.items[0].metadata.name}')
kubectl exec $WRITER_POD -- sh -c 'dd if=/dev/zero of=/data/testfile bs=1M count=100'

# 10. Vérifier l'utilisation du stockage
kubectl exec $WRITER_POD -- df -h /data

# 11. Nettoyage
kubectl delete deployment nfs-writer nfs-reader
kubectl delete pvc nfs-test-pvc
kubectl delete pv nfs-test-pv
kubectl delete namespace storage-system
```

**Questions de réflexion :**
1. Quelle est la différence entre ReadWriteOnce et ReadWriteMany ?
2. Pourquoi monter le volume en readOnly pour les readers ?
3. Quels sont les avantages et inconvénients du NFS ?
4. Comment sécuriser davantage l'accès au serveur NFS ?

### Exercice Final 4 : Application web avec Redis et persistance

Créez un déploiement complet avec :
- Un StatefulSet Redis avec PVC
- Un service pour exposer Redis
- Un deployment d'application web qui utilise Redis
- Vérifiez la persistance des données Redis

**Solution :**

```bash
# 1. Déployer Redis avec persistance
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
data:
  redis.conf: |
    appendonly yes
    appendfsync everysec
    save 900 1
    save 300 10
    save 60 10000
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: redis
        image: redis:7-alpine
        command:
        - redis-server
        - /etc/redis/redis.conf
        ports:
        - containerPort: 6379
          name: redis
        volumeMounts:
        - name: data
          mountPath: /data
        - name: config
          mountPath: /etc/redis
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: redis-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
  clusterIP: None
EOF

# 2. Attendre que Redis soit prêt
kubectl wait --for=condition=ready pod -l app=redis --timeout=120s

# 3. Tester Redis et insérer des données
kubectl exec -it redis-0 -- redis-cli SET mykey "Hello from Kubernetes Storage TP!"
kubectl exec -it redis-0 -- redis-cli GET mykey

# 4. Vérifier la persistance: supprimer le pod
kubectl delete pod redis-0

# 5. Attendre la recréation
kubectl wait --for=condition=ready pod redis-0 --timeout=120s

# 6. Vérifier que les données sont toujours là
kubectl exec -it redis-0 -- redis-cli GET mykey

# 7. Déployer une application web qui utilise Redis
kubectl apply -f - <<EOF
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
      - name: app
        image: redis:7-alpine
        command:
        - sh
        - -c
        - |
          while true; do
            COUNTER=\$(redis-cli -h redis.default.svc.cluster.local INCR page_views)
            echo "Page views: \$COUNTER"
            sleep 2
          done
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

# 8. Observer les compteurs
kubectl logs -l app=web-app --tail=5

# 9. Nettoyage
kubectl delete deployment web-app
kubectl delete statefulset redis
kubectl delete svc redis
kubectl delete pvc data-redis-0
kubectl delete configmap redis-config
```

### Exercice Final 5 : Migration et backup de données

1. Créez un pod avec un PVC
2. Écrivez des données dans le volume
3. Créez un snapshot (si disponible)
4. Simulez une catastrophe (suppression du pod et du PVC)
5. Restaurez depuis le snapshot
6. Vérifiez que les données sont intactes

**Solution :**

```bash
# 1. Créer un PVC et un pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data
EOF

# 2. Attendre et écrire des données importantes
kubectl wait --for=condition=ready pod/data-pod --timeout=60s
kubectl exec data-pod -- sh -c 'echo "Données critiques - backup test" > /data/important.txt'
kubectl exec data-pod -- sh -c 'date >> /data/important.txt'
kubectl exec data-pod -- cat /data/important.txt

# 3. Créer un snapshot (si CSI driver supporte les snapshots)
# Vérifier si les VolumeSnapshotClass existent
kubectl get volumesnapshotclass

# Si disponible:
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: app-data-snapshot
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: app-data
EOF

# Attendre que le snapshot soit prêt
sleep 10
kubectl get volumesnapshot app-data-snapshot

# 4. Sauvegarder manuellement si snapshots non disponibles
kubectl exec data-pod -- tar czf /data/backup.tar.gz /data/important.txt
kubectl cp data-pod:/data/backup.tar.gz ./backup.tar.gz

# 5. Simuler une catastrophe
kubectl delete pod data-pod
kubectl delete pvc app-data

# 6. Restaurer depuis le snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-restored
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  dataSource:
    name: app-data-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: 1Gi
EOF

# Ou restaurer manuellement
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-restored
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-pod-restored
spec:
  containers:
  - name: app
    image: busybox
    command: ['sh', '-c', 'sleep 3600']
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: app-data-restored
EOF

# Copier le backup
kubectl wait --for=condition=ready pod/data-pod-restored --timeout=60s
kubectl cp ./backup.tar.gz data-pod-restored:/data/backup.tar.gz
kubectl exec data-pod-restored -- tar xzf /data/backup.tar.gz -C /

# 7. Vérifier les données restaurées
kubectl exec data-pod-restored -- cat /data/important.txt

# 8. Nettoyage
kubectl delete pod data-pod-restored
kubectl delete pvc app-data-restored
kubectl delete volumesnapshot app-data-snapshot 2>/dev/null || true
rm -f backup.tar.gz
```

## Partie 8 : Nettoyage

```bash
# Supprimer tous les pods, deployments et services
kubectl delete deployment mysql
kubectl delete service mysql
kubectl delete pod mysql-client
kubectl delete pod pod-with-pvc
kubectl delete pod emptydir-demo

# Supprimer les PVC
kubectl delete pvc mysql-pvc
kubectl delete pvc dynamic-pvc
kubectl delete pvc pvc-demo

# Supprimer les PV (si Retain)
kubectl delete pv pv-demo

# Supprimer les StorageClasses personnalisées
kubectl delete storageclass fast-storage

# Supprimer les secrets
kubectl delete secret mysql-secret

# Vérifier que tout est nettoyé
kubectl get all
kubectl get pvc
kubectl get pv
```

## Résumé

Dans ce TP, vous avez appris à :

- Utiliser différents types de volumes (emptyDir, hostPath, PVC)
- Créer et gérer des PersistentVolumes et PersistentVolumeClaims
- Utiliser le provisionnement dynamique avec StorageClasses
- Déployer une base de données avec persistance
- Appliquer les bonnes pratiques de gestion du stockage

### Concepts clés

- **Volume** : Abstraction de stockage
- **PV** : Ressource de stockage cluster-wide
- **PVC** : Demande de stockage par un utilisateur
- **StorageClass** : Classe de stockage avec provisionnement dynamique
- **Modes d'accès** : RWO, ROX, RWX
- **Reclaim Policy** : Retain, Delete, Recycle

## Ressources complémentaires

### Documentation officielle
- [Volumes Kubernetes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

### Tutoriels avancés
- [CSI Drivers](https://kubernetes-csi.github.io/docs/)
- [Rook (stockage distribué)](https://rook.io/)
- [Longhorn (stockage cloud-native)](https://longhorn.io/)

### Prochaines étapes

Félicitations ! Vous maîtrisez maintenant la persistance des données dans Kubernetes.

Passez au **TP4** pour apprendre le monitoring et la gestion des logs.

## Questions de révision

1. Quelle est la différence entre un Volume et un PersistentVolume ?
2. Quand utiliser emptyDir vs PVC ?
3. Qu'est-ce que le provisionnement dynamique ?
4. Quels sont les trois modes d'accès disponibles ?
5. Que se passe-t-il avec une Reclaim Policy "Delete" ?
6. Pourquoi utiliser un Headless Service pour MySQL ?
7. Comment vérifier qu'un volume est correctement monté dans un pod ?
8. Quelle est la différence entre requests et limits pour le stockage ?

## Solutions des questions

<details>
<summary>Cliquez pour voir les réponses</summary>

1. Un Volume est lié au cycle de vie d'un pod, un PV est une ressource cluster-wide indépendante
2. emptyDir pour données temporaires partagées entre conteneurs, PVC pour données persistantes
3. Création automatique de PV à la demande via une StorageClass
4. ReadWriteOnce, ReadOnlyMany, ReadWriteMany
5. Le PV et les données sont supprimés automatiquement
6. Pour accès direct aux pods sans load balancing
7. `kubectl describe pod <name>` et vérifier la section Mounts
8. Pour le stockage, requests = taille demandée, limits n'existe pas (la taille est fixe)

</details>

---

**Durée estimée du TP :** 4-5 heures
**Niveau :** Intermédiaire

**Bon travail !**
