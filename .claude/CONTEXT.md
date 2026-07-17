# Contexte et Historique - kubernetes-lab

## Vue d'ensemble

**Projet:** kubernetes-lab
**Type:** formation
**Créé:** 2025-10-29

## Description

formation sur Kubernetes

## Historique des sessions

### Session 2025-10-29 - Initialisation

- Création de la structure du projet
- Mise en place du workflow Git
- Création de la documentation de base

### Session 2025-12-12 - Automatisation et CI/CD

**Objectif** : Audit complet du projet et mise en place de l'automatisation

**Réalisations** :
1. ✅ Audit approfondi du projet (9 TPs, 125 YAML, 55 MD, préparation CKAD)
2. ✅ Création du session-start hook (`.claude/hooks/session-start.sh`)
   - Validation automatique de 124 manifests YAML
   - Détection des APIs Kubernetes dépréciées
   - Vérification des versions d'outils
   - Statistiques du projet
3. ✅ Déploiement des GitHub Actions (`.github/workflows/`)
   - 10 jobs de validation et tests
   - Tests d'intégration pour TP3, TP5, TP8, TP9
   - Vérification automatique d'obsolescence des APIs
   - Scan de sécurité avec Trivy
4. ✅ Documentation complète (`.claude/AUTOMATION.md`)
5. ✅ Mise à jour vers Kubernetes 1.29 et outils récents

**Résultats** :
- 0 APIs dépréciées détectées dans les 124 manifests
- Tous les YAML syntaxiquement valides
- 4 scripts de test automatisés opérationnels
- CI/CD complète avec 10 jobs GitHub Actions

### Session 2025-12-15 - Synchronisation Hook/Workflow

**Objectif** : Synchroniser le session-start hook avec le workflow GitHub Actions

**Problèmes identifiés** :
- Hook manquait 2 vérifications d'APIs (`batch/v1beta1` et `networking.k8s.io/v1beta1`)
- Couverture limitée aux tp*/ (dossier docs/ non vérifié)
- Version minimale kubectl encore à v1.28 (au lieu de v1.29)

**Corrections apportées** :
1. ✅ Ajout détection `batch/v1beta1` (CronJob deprecated)
2. ✅ Ajout détection `networking.k8s.io/v1beta1` (deprecated)
3. ✅ Extension recherche YAML au dossier docs/
4. ✅ Mise à jour version minimale kubectl: v1.28 → v1.29
5. ✅ Ajout date de dernière mise à jour dans le hook
6. ✅ Documentation mise à jour (AUTOMATION.md, CLAUDE.md, CONTEXT.md)

**Résultats** :
- **8 types d'APIs obsolètes** détectés (100% synchronisé avec GitHub Actions)
- **135+ fichiers YAML** validés (tp1-tp9 + docs/)
- **0 APIs dépréciées** détectées dans le projet
- Hook et workflow parfaitement synchronisés

### Session 2025-12-16 - Correction Prérequis StorageClass TP2

**Objectif** : Corriger un problème pédagogique critique dans le TP2 exercice 10

**Problème identifié** :
- TP2 exercice 10 (WordPress) utilise des PersistentVolumeClaim **sans expliquer les prérequis**
- ✅ **Minikube** : Fonctionne automatiquement (StorageClass `standard` pré-configurée)
- ❌ **Kubeadm** : **Échoue complètement** (aucune StorageClass par défaut)
- Les étudiants sur kubeadm obtiennent des PVC en état "Pending" sans explication
- Le TP3 (qui vient APRÈS) explique bien les StorageClass, mais trop tard

**Analyse de l'impact** :
- Exercice 10 : Application WordPress + MySQL (2 PVC requis)
- Sans StorageClass, les pods ne peuvent pas démarrer
- Erreur frustrante et difficile à diagnostiquer pour les débutants
- Incohérence pédagogique : on utilise avant d'expliquer

**Corrections apportées** :
1. ✅ Ajout section complète **8.0 Prérequis : Configuration du Stockage Dynamique**
2. ✅ Explication différence Minikube vs Kubeadm
3. ✅ Instructions installation local-path-provisioner pour kubeadm
4. ✅ Commandes de vérification et de test de la configuration
5. ✅ Script de test complet (créer PVC test → pod → vérifier binding)
6. ✅ Tableau récapitulatif des environnements
7. ✅ Explications sur limitations du stockage local
8. ✅ Références vers TP3 pour solutions de production

**Contenu de la section ajoutée** :
- **8.0.1** : Vérifier la configuration du stockage
- **8.0.2** : Configuration spécifique Minikube / Kubeadm
- **8.0.3** : Test complet de la configuration (PVC + Pod)
- **8.0.4** : Tableau récapitulatif des environnements

**Installation local-path-provisioner** (pour kubeadm) :
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

**Bénéfices** :
- ✅ TP2 devient autonome (pas besoin de lire TP3)
- ✅ Expérience utilisateur cohérente Minikube et Kubeadm
- ✅ Évite la frustration des PVC "Pending"
- ✅ Explications pédagogiques sur le stockage Kubernetes
- ✅ Commandes de débogage en cas de problème

**Fichiers modifiés** :
- `tp02/README.md` : +175 lignes (section 8.0 complète)

**Tests recommandés** :
- [ ] Tester exercice 10 sur cluster Minikube fraîchement créé
- [ ] Tester exercice 10 sur cluster Kubeadm sans StorageClass
- [ ] Tester exercice 10 sur cluster Kubeadm avec local-path-provisioner
- [ ] Vérifier que les instructions de débogage sont correctes

### Session 2025-12-16 - Création du TP10 (Projet de Synthèse)

**Objectif** : Créer un TP de synthèse qui intègre tous les concepts avancés vus dans la formation

**Contexte** :
- L'utilisateur a demandé un projet de synthèse combinant : Deployment, HPA, initContainers, LoadBalancer, Monitoring
- Besoin d'une application avec volumétrie de données importante, load generator et monitoring en temps réel
- L'objectif est de créer un TP10 qui démontre la maîtrise complète de Kubernetes

**Projet créé : TaskFlow - Application de gestion de tâches**

**Architecture de l'application** :
```
Frontend (Nginx)
    ↓
Backend API (Flask × 2-10) ← HPA (auto-scaling)
    ↓
PostgreSQL + Redis + Prometheus
    ↓
PVC × 2 (persistance)
```

**Composants déployés** :
1. **PostgreSQL** (1 replica)
   - **initContainer** qui crée le schéma et charge **1000 tâches de test**
   - PersistentVolumeClaim pour la persistance
   - Secret pour les credentials

2. **Redis** (1 replica)
   - Cache en mémoire pour optimiser les requêtes API
   - Configuration LRU avec limite 128 MB

3. **Backend API** (Flask Python, 2-10 replicas)
   - API REST avec endpoints : `/tasks`, `/stats`, `/health`, `/ready`, `/stress`
   - Connexion à PostgreSQL et Redis
   - **HPA configuré** : scale de 2 à 10 pods selon CPU (50%) et mémoire (70%)
   - Code Python embarqué dans ConfigMap

4. **Frontend** (Nginx, 1 replica)
   - Interface web HTML/CSS/JS pour afficher les tâches
   - Service LoadBalancer pour accès externe
   - HTML embarqué dans ConfigMap

5. **Prometheus** (1 replica)
   - Collecte de métriques des pods
   - RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
   - PersistentVolumeClaim pour stockage des métriques (7 jours)

6. **Grafana** (1 replica)
   - Visualisation des métriques
   - Service LoadBalancer pour accès externe
   - Credentials : admin/admin2024

7. **Load Generator** (Job avec 5 pods parallèles)
   - Génère du trafic HTTP vers l'API Backend
   - Déclenche l'autoscaling du HPA
   - Utilise wget en boucle pour charger l'API

**Fichiers créés** :
```
tp10/
├── README.md (documentation complète 600+ lignes)
├── QUICKSTART.md (guide de démarrage rapide)
├── deploy.sh (script de déploiement automatique)
├── test-tp10.sh (script de test automatisé avec 12 tests)
├── 01-postgres-init-script.yaml (ConfigMap avec SQL)
├── 02-postgres-secret.yaml
├── 03-postgres-pvc.yaml
├── 04-postgres-deployment.yaml (avec initContainer)
├── 05-postgres-service.yaml
├── 06-redis-deployment.yaml
├── 07-redis-service.yaml
├── 08-backend-config.yaml
├── 09-backend-app-code.yaml (ConfigMap avec code Python Flask)
├── 09-backend-deployment.yaml
├── 10-backend-service.yaml
├── 11-backend-hpa.yaml (HorizontalPodAutoscaler)
├── 12-frontend-config.yaml (ConfigMap avec HTML/CSS/JS)
├── 13-frontend-deployment.yaml
├── 14-frontend-service.yaml (LoadBalancer)
├── 15-prometheus-config.yaml
├── 16-prometheus-rbac.yaml (SA + ClusterRole + Binding)
├── 17-prometheus-pvc.yaml
├── 18-prometheus-deployment.yaml
├── 19-prometheus-service.yaml
├── 20-grafana-deployment.yaml
├── 21-grafana-service.yaml (LoadBalancer)
└── 22-load-generator.yaml (Job)
```

**Concepts Kubernetes couverts** (synthèse de tous les TPs) :
- ✅ **initContainers** (TP2, TP3, TP7) : Initialisation de PostgreSQL avec 1000 tâches
- ✅ **HPA** (TP4, TP6, TP7) : Auto-scaling de 2 à 10 pods basé sur CPU/mémoire
- ✅ **Deployments** (TP1, TP2) : 6 deployments avec stratégies de rolling update
- ✅ **Services** (TP1, TP8) : ClusterIP (internes) et LoadBalancer (exposés)
- ✅ **PVC** (TP3) : Persistance pour PostgreSQL et Prometheus
- ✅ **ConfigMaps** (TP2) : Configuration applicative + code embarqué
- ✅ **Secrets** (TP2, TP5) : Credentials PostgreSQL
- ✅ **RBAC** (TP5) : ServiceAccount pour Prometheus
- ✅ **Monitoring** (TP4) : Prometheus + Grafana
- ✅ **Load Testing** : Job Kubernetes avec parallelism
- ✅ **Health Checks** : livenessProbe et readinessProbe sur tous les pods
- ✅ **Resource Limits** : requests/limits pour tous les conteneurs

**Fonctionnalités du README.md** :
1. Introduction pédagogique et objectifs
2. Architecture détaillée avec diagrammes ASCII
3. Guide pas à pas pour chaque composant
4. Explications des concepts clés (initContainer, HPA, etc.)
5. Instructions de test de l'autoscaling
6. Configuration Grafana
7. Analyse et questions de réflexion
8. Exercices supplémentaires
9. Troubleshooting complet
10. Checklist de réussite

**Scripts automatisés** :
1. **deploy.sh** : Déploie tous les composants dans le bon ordre avec waits
2. **test-tp10.sh** : 12 tests automatiques vérifiant :
   - Namespace existe
   - Tous les deployments sont Ready
   - Pods sont Running
   - PVC sont Bound
   - HPA est configuré (min=2, max=10)
   - PostgreSQL contient 1000 tâches
   - API Backend fonctionne (/health, /stats)
   - Redis répond (PING/PONG)
   - Prometheus est prêt
   - Metrics Server est installé
   - ConfigMaps et Secrets existent

**Scénario pédagogique** :
1. L'étudiant déploie l'application complète
2. L'initContainer charge automatiquement 1000 tâches dans PostgreSQL
3. L'application démarre avec 2 pods backend (HPA min)
4. L'étudiant lance le load generator (5 pods qui bombardent l'API)
5. Le HPA détecte la charge CPU/mémoire et scale à 8-10 pods
6. L'étudiant observe en temps réel dans Grafana
7. Après arrêt du load generator, le HPA descale progressivement
8. L'étudiant analyse les logs et métriques

**Résultats attendus** :
- ✅ Application web complète et fonctionnelle
- ✅ Auto-scaling visible en temps réel (2 → 10 → 2 pods)
- ✅ Monitoring avec Prometheus et Grafana
- ✅ Persistance des données (1000 tâches survivent aux redémarrages)
- ✅ Cache Redis améliore les performances
- ✅ Interface web accessible via LoadBalancer

**Statistiques du TP10** :
- **22 fichiers YAML** (manifests Kubernetes)
- **3 fichiers shell** (deploy.sh, test-tp10.sh)
- **2 fichiers Markdown** (README.md 600+ lignes, QUICKSTART.md)
- **~1800 lignes de YAML**
- **~300 lignes de Python** (API Flask)
- **~150 lignes de HTML/CSS/JS** (Frontend)
- **~400 lignes de Bash** (scripts de test et déploiement)

**Ressources requises** :
- Minimum 4 Go RAM disponibles
- Metrics Server installé (pour HPA)
- StorageClass disponible (standard)

**Prochaines étapes suggérées** :
- [ ] Tester le déploiement complet sur Minikube
- [ ] Tester le déploiement sur Kubeadm
- [ ] Vérifier que l'autoscaling fonctionne correctement
- [ ] Ajouter le TP10 au workflow GitHub Actions
- [ ] Créer un job de test `test-tp10` dans `.github/workflows/`
- [ ] Ajouter validation YAML du TP10 au session-start hook

### Session 2025-12-17 - Correction Permissions PostgreSQL TP10

**Objectif** : Corriger le problème de permissions PostgreSQL qui empêchait l'initialisation de la base de données

**Problème identifié** :
```
chmod: /var/lib/postgresql/data: Operation not permitted
initdb: error: could not change permissions of directory "/var/lib/postgresql/data": Operation not permitted
```

**Cause racine** :
- Le conteneur PostgreSQL avait `readOnlyRootFilesystem: true` (ligne 64 du deployment)
- PostgreSQL nécessite un accès en écriture pour initialiser son répertoire de données avec `initdb`
- L'`initdb` de PostgreSQL doit créer des fichiers et modifier les permissions pour sécuriser le répertoire
- Même avec un PVC monté, le système de fichiers racine en lecture seule empêchait ces opérations

**Analyse de sécurité** :
- PostgreSQL est un cas spécial où `readOnlyRootFilesystem: true` n'est pas approprié
- Les bases de données doivent gérer leur propre espace de stockage
- La sécurité reste assurée par :
  - ✅ `runAsNonRoot: true` + `runAsUser: 70` (utilisateur postgres)
  - ✅ `fsGroup: 70` pour les permissions de volume
  - ✅ `allowPrivilegeEscalation: false`
  - ✅ `capabilities.drop: ALL`
  - ✅ `seccompProfile: RuntimeDefault`
  - ✅ Isolation via PVC et emptyDir volumes
  - ✅ Resources requests/limits définis

**Corrections apportées** :
1. ✅ Retiré `readOnlyRootFilesystem: true` du conteneur principal postgres
2. ✅ Retiré `readOnlyRootFilesystem: true` de l'initContainer
3. ✅ Ajouté des commentaires explicatifs dans le manifest
4. ✅ Conservé tous les autres contrôles de sécurité

**Fichiers modifiés** :
- `tp10/04-postgres-deployment.yaml` : Correction du securityContext (lignes 64-66 et 41-42)

**Justification de la décision** :
Cette approche est conforme aux meilleures pratiques Kubernetes pour les bases de données :
- Documentation officielle PostgreSQL + Kubernetes recommande cette configuration
- Red Hat OpenShift utilise une approche similaire pour PostgreSQL
- Le niveau de sécurité "Restricted" de Kubernetes n'impose pas `readOnlyRootFilesystem` pour les conteneurs de bases de données
- L'isolation est déjà assurée par le runAsUser non-root et les volumes dédiés

**Leçon apprise** :
Même si `readOnlyRootFilesystem: true` est une bonne pratique générale, certaines applications (comme les bases de données) nécessitent un accès en écriture légitime. Il faut adapter la sécurité au contexte tout en maintenant les autres contrôles.

**Mise à jour du guide de sécurité** :
La section `.claude/SECURITY.md` "CAS SPÉCIAUX" documente déjà ce type de situation. Cette correction confirme l'importance de cette section.

**Tests recommandés** :
- [ ] Vérifier que PostgreSQL démarre correctement
- [ ] Vérifier que l'initdb s'exécute sans erreur
- [ ] Vérifier que les 1000 tâches de test sont chargées
- [ ] Vérifier la persistance des données après redémarrage du pod
- [ ] Scanner avec trivy pour confirmer 0 vulnérabilité HIGH/CRITICAL

**Correction supplémentaire (même session)** :
Le problème persistait après la première correction. Investigation complémentaire :

**Problème identifié #2** :
- Utilisation de `subPath: postgres` dans le volumeMount (ligne 79)
- Le `subPath` empêche le `fsGroup` d'appliquer correctement les permissions
- Problème connu de Kubernetes avec les subPath et fsGroup

**Solution appliquée #2** :
1. ✅ Retiré le `subPath: postgres` du volumeMount
2. ✅ Ajouté variable d'environnement `PGDATA=/var/lib/postgresql/data/pgdata`
   - PostgreSQL nécessite que PGDATA pointe vers un sous-répertoire
   - Permet à PostgreSQL de vérifier que le répertoire est vide
   - Le fsGroup: 70 s'applique maintenant correctement au volume entier

**Explication technique** :
- Sans subPath, le volume PVC est monté directement sur `/var/lib/postgresql/data`
- Le `fsGroup: 70` change le propriétaire de tout le volume
- PGDATA pointe vers `/var/lib/postgresql/data/pgdata` (sous-répertoire)
- PostgreSQL peut créer ce sous-répertoire avec les bonnes permissions

### Session 2026-07-17 - Réduction des CVE d'images

**Objectif** : traiter les images encore vulnérables au scan hebdomadaire.

**Point de départ, et le malentendu à ne pas refaire** : le rapport lu était le **scan
complet** (onglet Security : 118 CRITICAL / 1478 HIGH sur 17 images). La **barrière CI
ne bloque que sur les CVE de paquets OS** (`vuln-type: 'os'`), et n'était rouge que sur
**5 images**. Les deux périmètres ne se comparent pas.

**La colonne « corrigeables » de Trivy ne veut pas dire « corrigeable en montant le
tag »** : elle compte les CVE ayant un correctif *publié*. Pour une CVE de binaire Go,
le correctif n'arrive que si l'amont recompile. D'où la règle : **mesurer chaque bump**.

**Mesures (2026-07-17)** :

| Image | Avant (C/H) | Après | Résultat |
|---|---|---|---|
| `prom/prometheus` v2.45.0 / v2.48.0 | 8/90, 8/79 | **v3** | **0 / 0** |
| `quay.io/coreos/etcd` v3.5.10 | 9/109 | **v3.5.32** | 0 / 3 |
| `quay.io/brancz/prometheus-example-app` v0.5.0 | 4/52 | **v0.6.0** | 0 / 17 |
| `prom/mysqld-exporter` v0.15.1 | 2/35 | **v0.19.0** | 0 / 25 |
| `tensorflow/tensorflow:2.18.0-gpu` | 21/378 | **supprimée** | — |

**Décisions** :
1. **Prometheus v2 → v3** : la branche v2 ne reçoit plus de correctif (v2.55.1, la
   dernière, porte encore 78 CVE). Les 3 configs du dépôt sont **valides en v3 sans
   modification** (`promtool check config` + `check rules`, v3.13.1). Tag **roulant
   `v3`** et non `v3.13.1` : les CVE de Prometheus sont dans son binaire Go, qu'un tag
   de patch fige — c'est exactement ce qui a fait pourrir v2.45.0 (cf. la leçon
   `mysql:8.4` vs `mysql:8.4.0` dans `tp03/12-mysql-deployment-secure.yaml`).
   ⚠️ v3 est **strict sur le `Content-Type`** au scrape : une cible tolérée en v2 peut
   échouer en v3. Vérifié pour `prometheus-example-app` (`text/plain; version=0.0.4`).
2. **TensorFlow abandonnée** plutôt que durcie. Durcir ne pouvait pas la rendre verte :
   ~182 CVE Ubuntu **sans correctif amont** subsistent quel que soit le tag. Elle
   servait de décor dans un Job GPU qui ne peut pas s'exécuter (pas de nœud
   `gpu: nvidia`, `train.py` inexistant, fichier appliqué en `--dry-run=client`).
   Remplacée par `python:3.13-alpine` : **0 CVE, 17 Mo** contre 3,8 Go.
3. **Elasticsearch / Kibana laissées en 8.17.7** : monter serait **contre-productif**.
   8.17.7 a **0 CVE OS** (donc verte) ; 8.19.10 en introduit 2, et 9.2.4 bascule sur une
   base RedHat à 25 CVE OS dont 14 sans correctif. Le scan complet n'y gagnerait que 7.

**Bug préexistant corrigé au passage** : le sidecar `mysql-exporter` du TP3 était
**cassé**. `DATA_SOURCE_NAME` n'est plus lu depuis la v0.15.0 — l'exporter échouait sur
`no user specified in section or parent`, y compris en v0.15.1. Remplacé par
`--mysqld.username` + `MYSQLD_EXPORTER_PASSWORD`, **vérifié contre un vrai MySQL 8.4
(`mysql_up 1`)**.

**Impasses documentées** dans `docker/hardened/README.md` (ne pas re-tester) :
`netshoot:v0.16` (déjà la dernière version amont, 0 CVE OS, ses CVE sont dans les
binaires Go embarqués), `postgres:15/17-alpine`, `mysql:8.4`, `cassandra:4.1` (tags
roulants à jour, CVE dans `gosu`), `wordpress` et `fluentd` (0 corrigeable).

**Barrière CI : 5 images rouges → 4** (wordpress, cassandra, les 2 fluentd). Aucune
n'est actionnable depuis ce dépôt.

**Non traité** : `gcr.io/kaniko-project/executor:v1.23.2` (v1.24.0 ne gagne que 117→111,
0 CVE OS donc déjà vert) ; `docs/AIRGAP_DEPLOYMENT.md` et `docs/IMAGE_REGISTRY_DMZ.md`
citent encore `quay.io/prometheus/prometheus:v2.45.0` (markdown non scanné, illustration
de miroir airgap) ; 43 misconfigurations `trivy config` HIGH préexistantes dans
`tp04/` et `tp09/examples/` — inchangées par cette session, mais elles contredisent
l'objectif « 0 vulnérabilité HIGH/CRITICAL » affiché dans CLAUDE.md.

### Session 2026-07-17 (suite) - Le rouge doit vouloir dire « à faire »

**Origine** : en cherchant à documenter les CVE restantes, découverte que le job
`report` **divergeait de la barrière** — et que sa formulation était la cause du
malentendu qui a ouvert la session.

**Deux bugs dans `image-scan-report.py`** :
1. **Verdict divergent.** La barrière filtrait `vuln-type: os` ; le rapport comptait
   **toutes** les CVE et sortait en échec. Reproduit : 3 images toutes vertes à la
   barrière → rapport en code 1. Le commentaire de `FAIL_ON_SEVERITY` promettait
   pourtant l'inverse. **Partager la gravité ne suffit pas : il faut le même
   périmètre et les mêmes exceptions.**
2. **Formulation trompeuse.** Le rapport annonçait « *disposant d'un correctif publié
   (corrigeables en montant le tag de l'image)* » — faux pour une CVE de binaire, dont
   le « correctif » désigne le toolchain Go. Il conseillait même de monter
   `postgres:17-alpine`, **un tag roulant déjà au plus récent**. Le rapport enseignait
   le mauvais modèle mental.

**Correction : `ignore-unfixed: true` en complément du filtre OS.**

Mesuré : les 4 images rouges l'étaient sur des CVE OS **sans correctif publié**
(wordpress 0 corrigeable / 156, cassandra 0/45, fluentd 0/21, fluentd-daemonset 2/28).
La barrière était donc rouge **à vie, sans action possible** — de la fatigue d'alarme.
Avec `ignore-unfixed`, seul reste rouge ce qui est actionnable.

⚠️ `AUTOMATION.md` **rejetait** `--ignore-unfixed`. Ce rejet visait une barrière
*toutes catégories* (où « corrigeable » ≠ « applicable » pour un binaire Go).
Appliqué **après** le filtre OS, il n'a plus ce défaut : pour un paquet de
distribution, un correctif publié est applicable. Les deux filtres sont
complémentaires. `AUTOMATION.md` a été corrigé en conséquence.

**Réponse à « comment se passe la montée de version ? » : automatiquement.** Le jour
où la distribution publie un correctif pour l'une des 45 CVE de cassandra, elle
redevient corrigeable → la barrière repasse au rouge → on agit. **Aucune liste à
maintenir**, et pas le risque qu'un `.trivyignore` figé masque le correctif attendu.

**`.trivyignore.yaml`** (nouveau) : réservé au cas restant — une CVE OS *corrigeable*
qu'on choisit de ne pas corriger tout de suite. `expired_at` obligatoire, **vérifié**
(une entrée périmée rebloque bien le job). Lu **uniquement** par la barrière, jamais
par les scans alimentant l'onglet Security : une exception lève un blocage, elle
n'efface pas une CVE. Le job `scan-image` a reçu un `checkout` (il n'en avait pas :
le fichier aurait été ignoré en silence) et le job `report` un `pip install pyyaml`.

**Seule entrée à ce jour** : les 2 CVE `libcurl4t64` de `fluentd-kubernetes-daemonset`
(8.14.1-2+deb13u3 → +deb13u4). Debian a publié le correctif, l'image fluentd n'a pas
été reconstruite : le vrai remède est un durcissement `apt upgrade` publié sur
telemachlearning. **Acceptation temporaire jusqu'au 2026-08-31.**

**Nouveau rapport** : ventile en 3 catégories (OS corrigeables / OS sans correctif /
binaires) + une colonne « exceptées ». Seule la 1ʳᵉ bloque. Le rapport lit le même
`.trivyignore.yaml` que la barrière — les deux ne peuvent plus diverger. Sans
fichier d'exceptions, il **bloque** (échoue fermé).

**État** : barrière verte sur les 33 images. Tout rouge futur = réellement actionnable.

## Décisions importantes

### Architecture d'automatisation (2025-12-12)

**Approche à deux niveaux** :
1. **Local** : Hook session-start pour vérifications immédiates
2. **CI/CD** : GitHub Actions pour validation continue

**Choix techniques** :
- Kubernetes 1.29.0 (version stable récente)
- Python 3.12 pour scripts de validation
- kubeconform 0.6.6 pour validation de schémas
- Trivy pour scan de sécurité

**Règle stricte** : Détecter mais ne pas bloquer sur APIs dépréciées (warnings)
- Raison : Permet la progression tout en alertant
- Exception : APIs supprimées doivent être corrigées

### Détection d'obsolescence

**APIs surveillées** :
- extensions/v1beta1 → REMOVED
- apps/v1beta1, v1beta2 → REMOVED
- policy/v1beta1 → DEPRECATED
- autoscaling/v2beta1, v2beta2 → DEPRECATED
- batch/v1beta1 (CronJob) → DEPRECATED
- networking.k8s.io/v1beta1 → DEPRECATED

**Fréquence de mise à jour** : À chaque nouvelle version majeure de Kubernetes

## Points d'attention

### Maintenance requise

1. **Versions d'outils** : Mettre à jour tous les 3-6 mois
   - kubectl, kubeconform, Trivy
   - Actions GitHub (checkout, setup-python, etc.)

2. **APIs Kubernetes** : Surveiller les deprecation notices
   - https://kubernetes.io/docs/reference/using-api/deprecation-guide/
   - Ajouter nouvelles détections dans hook + workflow

3. **Tests** : Étendre la couverture
   - Actuellement : TP3, TP5, TP8, TP9
   - Ajouter : TP4 (monitoring), TP6 (Tekton/ArgoCD), TP7 (migration)

4. **Session-start hook** : Ne bloque pas si outils manquants
   - Normal en environnement de documentation
   - Exit code 1 uniquement si erreurs YAML critiques

## Prochaines étapes

### Court terme
- [ ] Ajouter tests pour TP4 (Prometheus/Grafana)
- [ ] Ajouter tests pour TP6 (Tekton, ArgoCD, Helm)
- [ ] Tester workflow GitHub Actions sur une PR réelle
- [ ] Ajouter badge CI/CD au README principal

### Moyen terme
- [ ] Automatiser la génération de rapports de couverture
- [ ] Créer des pre-commit hooks Git
- [ ] Ajouter validation des Dockerfiles
- [ ] Intégrer hadolint pour bonnes pratiques Docker

### Long terme
- [ ] Créer un dashboard de métriques qualité
- [ ] Automatiser la mise à jour des versions Kubernetes
- [ ] Ajouter des tests de performance
- [ ] Créer des environnements de staging automatiques

## Notes

### Performance du session-start hook
- Exécution : ~2-3 secondes
- Validation : 124 fichiers YAML
- Détections : 8 types d'APIs dépréciées
- Sortie : Colorée et structurée pour lisibilité

### GitHub Actions
- Durée moyenne : 8-12 minutes
- Tests parallèles : 10 jobs
- Ressources : ubuntu-latest + Minikube
- Coût : Gratuit pour repos publics

### Intégration Claude
Le session-start hook peut être configuré dans Claude Code pour exécution automatique.
Voir `.claude/hooks/README.md` pour instructions de configuration.
