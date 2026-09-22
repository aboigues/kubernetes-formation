# Fiche de révision — Quiz Kubernetes (formation DEVOPS-010)

Points clés à réviser avant les 3 quiz d'évaluation post-formation (dépôt `telemach-learning`,
`scaleway/quiz-results/quizzes.py` — source unique de vérité des quiz). Ne reprend pas les
questions telles quelles, seulement les notions qu'elles testent, regroupées par thème.

## Quiz 1 — Fondations & architecture

Control plane, composants du cluster, kubectl, Pods et Namespaces.

- **etcd** : base clé-valeur distribuée, source de vérité de l'état du cluster. Tous les autres
  composants la consultent/modifient via l'API server.
- **kube-scheduler** : décide sur quel nœud placer un nouveau Pod (ressources, affinité,
  taints/tolerations).
- **kubelet** : agent sur chaque worker node, fait correspondre l'état réel des conteneurs à
  l'état désiré, en pilotant le container runtime (containerd, CRI-O).
- **kube-proxy** : maintient les règles réseau (iptables/IPVS) qui routent le trafic vers les
  Pods d'un Service.
- **kind** : crée un cluster local en utilisant des conteneurs Docker comme « nœuds » — pratique
  pour la formation/CI. minikube est l'alternative à VM/conteneur unique.
- **kubectl describe pod** : première commande de diagnostic — événements, conditions, volumes
  montés (à distinguer de `kubectl get pod`, plus sommaire).
- **Pod** : plus petite unité de déploiement (jamais un conteneur isolé directement) — un ou
  plusieurs conteneurs partageant réseau et IP.
- **Namespace** : cloisonnement logique des ressources au sein d'un même cluster (multi-équipes,
  multi-environnements), avec quotas et RBAC distincts.
- **kubectl get pods -A** (`--all-namespaces`) : liste les Pods de tous les namespaces.
- **ImagePullBackOff** : image introuvable ou authentification au registry échouée — retry avec
  backoff exponentiel.

## Quiz 2 — Workloads, réseau & configuration

Deployments, StatefulSets, Services, Gateway API, ConfigMaps, Secrets et volumes.

- **Deployment vs StatefulSet** : Pods interchangeables sans état vs identité stable (nom,
  stockage) pour chaque réplique — adapté aux applications avec état (bases de données).
- **DaemonSet** : une copie du Pod sur chaque nœud (ou sous-ensemble), typique pour un agent de
  log ou de monitoring.
- **CronJob vs Job** : le Job exécute une tâche ponctuelle jusqu'à complétion ; le CronJob crée
  des Jobs selon une syntaxe cron (tâche récurrente planifiée).
- **Rolling update** : remplacement progressif des anciens Pods par les nouveaux, encadré par
  `maxUnavailable`/`maxSurge`, service disponible en continu, rollback possible.
- **Types de Service** : `ClusterIP` (défaut, interne au cluster uniquement) vs `NodePort` /
  `LoadBalancer` (exposition externe).
- **Découverte de service** : CoreDNS résout le nom d'un Service (`api` ou
  `api.namespace.svc.cluster.local`) — pas besoin de connaître l'IP du Pod.
- **Gateway API** : sépare la ressource d'infra (`Gateway`, gérée par la plateforme) du routage
  applicatif (`HTTPRoute`, géré par les équipes) — complète/remplace l'Ingress historique.
- **NetworkPolicy** : contrôle quels Pods peuvent communiquer entre eux (segmentation, moindre
  privilège) — sans elle, tous les Pods du cluster peuvent se joindre par défaut.
- **Secret vs ConfigMap** : les données sensibles (mots de passe, clés) vont dans un Secret ; la
  configuration non sensible dans un ConfigMap.
- **PV / PVC** : le `PersistentVolume` représente le stockage provisionné, le
  `PersistentVolumeClaim` est la demande faite par un Pod — les données survivent à la recréation
  du Pod.

## Quiz 3 — Helm & observabilité

Charts Helm, releases, rollback, Prometheus, Grafana, Loki et diagnostic.

- **Chart Helm** : package Kubernetes — manifestes YAML templatisés + `values.yaml` de
  paramètres, versionné et réutilisable.
- **helm install vs helm create** : `install` crée une nouvelle release dans le cluster ;
  `create` génère le squelette d'un nouveau chart local.
- **Personnaliser un chart** : surcharger `values.yaml` via `--set` ou `-f mes-values.yaml`, sans
  modifier les templates du chart.
- **helm rollback** : restaure une révision antérieure d'une release à partir de l'historique
  conservé par Helm.
- **Prometheus** : collecte des métriques en mode pull (scrute des endpoints `/metrics`), stocke
  des séries temporelles.
- **Grafana** : ne collecte rien lui-même — visualise sous forme de tableaux de bord les données
  de sources comme Prometheus ou Loki.
- **Loki** : centralise les logs indexés par labels (namespace, pod, app...) plutôt que par texte
  intégral — plus léger qu'une stack ELK, s'intègre à Grafana.
- **kubectl top pods** : consommation CPU/mémoire en temps réel (nécessite `metrics-server`) —
  premier réflexe de diagnostic de performance.
- **CrashLoopBackOff** : première commande à utiliser → `kubectl logs <pod>` (`--previous` si le
  conteneur a déjà redémarré), avant de creuser probes/ressources.
- **GitOps (ArgoCD/FluxCD)** : l'état désiré du cluster est décrit dans un dépôt Git ; un
  contrôleur réconcilie en continu le cluster avec ce dépôt (traçabilité, rollback via Git,
  déploiement continu).
