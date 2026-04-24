# Formation Kubernetes

![Test Kubernetes Manifests](https://github.com/aboigues/kubernetes-formation/actions/workflows/test-kubernetes-manifests.yml/badge.svg)

Formation complète et pratique sur Kubernetes avec des TPs progressifs pour apprendre le déploiement, la gestion et l'orchestration de conteneurs.

## Description

Ce projet propose une formation Kubernetes structurée en travaux pratiques (TP) permettant d'acquérir progressivement les compétences essentielles pour déployer et gérer des applications conteneurisées sur Kubernetes.

**Type:** Formation pratique

**Environnement:** AlmaLinux avec minikube (ou Windows avec Minikube/WSL2)

## Prérequis

### Pour Linux (AlmaLinux recommandé)
- Machine Linux (AlmaLinux recommandé) ou machine virtuelle
- 2 CPU minimum
- 2 Go de RAM minimum
- 20 Go d'espace disque
- Accès root ou sudo
- Connexion Internet pour télécharger les outils et images

### Pour Windows
- **[📘 Guide d'installation Kubernetes sur Windows](docs/WINDOWS_SETUP.md)** - Instructions complètes pour Minikube et kubeadm sur Windows
- Windows 10/11 avec support de virtualisation
- 4 Go de RAM minimum (8 Go recommandé)
- 20 Go d'espace disque
- Docker Desktop, Hyper-V, ou WSL2
- Droits administrateur

## Table des matières

### Travaux pratiques

- **[TP1 - Premier déploiement Kubernetes avec Minikube](tp01/README.md)**

  Installation, configuration et premiers pas avec Kubernetes sur AlmaLinux

- **[TP2 - Maîtriser les Manifests Kubernetes](tp02/README.md)**

  Apprentissage approfondi de la rédaction de manifests YAML

- **[TP3 - Persistance des données dans Kubernetes](tp03/README.md)**

  Gestion des volumes et du stockage persistant

- **[TP4 - Monitoring et Gestion des Logs](tp04/README.md)**

  Observabilité, métriques, logs et alertes dans Kubernetes

- **[TP5 - Sécurité et RBAC](tp05/README.md)**

  Sécurisation des clusters, contrôle d'accès et bonnes pratiques

- **[TP6 - Mise en Production et CI/CD](tp06/README.md)**

  Déploiement automatisé, GitOps, Helm et stratégies de mise en production

- **[TP7 - Migration Docker Compose vers Kubernetes](tp07/README.md)**

  Migration d'applications existantes, conversion avec Kompose et bonnes pratiques

- **[TP8 - Réseau Kubernetes : Services, DNS et Connectivité](tp08/README.md)**

  Maîtrise approfondie du réseau Kubernetes, Services, DNS et NetworkPolicies

- **[TP9 - Gestion Multi-Noeud de Kubernetes](tp09/README.md)**

  Architecture et gestion de clusters multi-noeuds, haute disponibilité, maintenance et stratégies de planification

- **[TP10 - Projet de Synthèse : Application TaskFlow avec Auto-scaling et Monitoring](tp10/README.md)**

  Projet de synthèse intégrant tous les concepts : HPA, initContainers, Monitoring (Prometheus/Grafana), Load Testing

### Préparation Certification CKAD

- **[🎓 CKAD Preparation - Exercices et Examens Blancs](ckad-preparation/README.md)**

  Ressources complètes pour préparer la certification CKAD (Certified Kubernetes Application Developer) :
  - 65+ exercices couvrant tous les domaines CKAD
  - Examens blancs chronométrés
  - Cheatsheet des commandes essentielles
  - Plan d'entraînement sur 6 semaines
  - Solutions détaillées et explications

### Documentation complémentaire

- [Installation rapide](#installation-rapide)
- [Structure du projet](#structure-du-projet)
- [Commandes kubectl essentielles](#commandes-kubectl-essentielles)
- **[📊 Schéma des Ressources Kubernetes](docs/KUBERNETES_RESOURCES_SCHEMA.md)** - Schéma complet et visuel de toutes les ressources Kubernetes (Namespace, Deployment, Pod, Service, etc.)
- **[⌨️ Référence kubectl, kubeadm, minikube](docs/KUBECTL_KUBEADM_MINIKUBE_REFERENCE.md)** - Guide complet des commandes essentielles et contextes d'utilisation
- **[🚀 Tips & Tricks Kubernetes](docs/TIPS_AND_TRICKS.md)** - Astuces, bonnes pratiques et techniques avancées pour être plus productif
- **[💻 Guide d'installation Windows](docs/WINDOWS_SETUP.md)** - Installation complète de Kubernetes sur Windows (Minikube, kubeadm, WSL2)
- **[📘 Guide Jobs et CronJobs](docs/JOBS_CRONJOBS.md)** - Guide complet sur les tâches batch et planifiées
- **[🔧 Guide kubeadm Setup](docs/KUBEADM_SETUP.md)** - Installation d'un cluster multi-nœuds avec kubeadm
- [Ressources complémentaires](#ressources-complémentaires)
- [Workflow avec Claude](#workflow-avec-claude)

---

## Vue d'ensemble des TPs

### TP1 - Premier déploiement Kubernetes avec Minikube

📁 **[Accéder au TP1](tp01/README.md)**

Apprenez les bases de Kubernetes en installant et configurant un environnement local avec minikube. Ce TP couvre :
- Installation de Docker, kubectl et minikube sur AlmaLinux
- Démarrage et gestion d'un cluster Kubernetes local
- Déploiement de votre première application
- Exposition et scaling des applications
- Utilisation des fichiers YAML
- Rolling updates et rollbacks

**Durée estimée :** 3-4 heures
**Niveau :** Débutant

### TP2 - Maîtriser les Manifests Kubernetes

📁 **[Accéder au TP2](tp02/README.md)**

Maîtrisez l'écriture de manifests YAML Kubernetes et les bonnes pratiques de déploiement. Ce TP couvre :
- Structure et anatomie des manifests Kubernetes
- Création de Pods, Deployments et Services
- Gestion de la configuration avec ConfigMaps et Secrets
- Utilisation avancée des labels et selectors
- **Sidecar containers natifs (K8s 1.29+)** — `initContainers` avec `restartPolicy: Always`
- Namespaces et organisation des ressources
- Validation, tests et debugging
- Bonnes pratiques de production

**Durée estimée :** 5-6 heures
**Niveau :** Intermédiaire

### TP3 - Persistance des données dans Kubernetes

📁 **[Accéder au TP3](tp03/README.md)**

Apprenez à gérer le stockage persistant et les volumes dans Kubernetes. Ce TP couvre :
- Types de volumes (emptyDir, hostPath, PVC)
- PersistentVolumes et PersistentVolumeClaims
- StorageClasses et provisionnement dynamique
- Modes d'accès et politiques de réclamation
- Déploiement de bases de données avec persistance
- Expansion de volumes et snapshots
- Bonnes pratiques de gestion du stockage

**Durée estimée :** 4-5 heures
**Niveau :** Intermédiaire

### TP4 - Monitoring et Gestion des Logs

📁 **[Accéder au TP4](tp04/README.md)**

Maîtrisez l'observabilité et le monitoring de vos clusters Kubernetes. Ce TP couvre :
- Les trois piliers de l'observabilité (métriques, logs, traces)
- Installation et utilisation de Metrics Server
- Horizontal Pod Autoscaler (HPA)
- Dashboard Kubernetes
- Collecte et analyse des logs avec kubectl
- Déploiement de Prometheus pour le monitoring
- Création de dashboards avec Grafana
- Configuration d'alertes
- Introduction aux stacks EFK/ELK
- Bonnes pratiques de monitoring et logging

**Durée estimée :** 5-6 heures
**Niveau :** Intermédiaire/Avancé

### TP5 - Sécurité et RBAC

📁 **[Accéder au TP5](tp05/README.md)**

Maîtrisez la sécurité et le contrôle d'accès dans Kubernetes. Ce TP couvre :
- ServiceAccounts et identités
- RBAC : Roles, ClusterRoles, RoleBindings
- Security Contexts et Pod Security Standards
- Network Policies pour l'isolation réseau
- Gestion sécurisée des Secrets
- Audit et logging de sécurité
- Scanner de vulnérabilités d'images
- **ValidatingAdmissionPolicy avec CEL (K8s 1.30+)** — contrôles déclaratifs sans webhook
- Admission Controllers
- Bonnes pratiques de sécurité en production

**Durée estimée :** 6-8 heures
**Niveau :** Avancé

### TP6 - Mise en Production et CI/CD

📁 **[Accéder au TP6](tp06/README.md)**

Maîtrisez le déploiement en production et l'automatisation avec Kubernetes. Ce TP couvre :
- Helm : Charts, releases et gestionnaire de packages
- Ingress Controllers : NGINX Ingress, routing HTTP/HTTPS
- **Gateway API (K8s 1.31+)** — le successeur de l'Ingress avec séparation des rôles
- CI/CD : Pipelines avec GitHub Actions
- Stratégies de déploiement : Rolling, Blue-Green, Canary
- GitOps : Déploiement continu avec ArgoCD
- Gestion d'environnements multiples (dev, staging, prod)
- HPA, PDB et haute disponibilité
- Sealed Secrets et gestion sécurisée de la configuration
- Kustomize pour la configuration multi-environnements
- Monitoring, alertes et bonnes pratiques de production

**Durée estimée :** 8-10 heures
**Niveau :** Avancé

### TP7 - Migration Docker Compose vers Kubernetes

📁 **[Accéder au TP7](tp07/README.md)**

Apprenez à migrer vos applications Docker Compose existantes vers Kubernetes. Ce TP couvre :
- Comprendre les différences entre Docker Compose et Kubernetes
- Analyse d'une stack Docker Compose existante
- Conversion manuelle des services en manifests Kubernetes
- Utilisation de Kompose pour automatiser la conversion
- Adaptation et optimisation pour l'environnement Kubernetes
- Gestion des volumes, secrets et configuration
- InitContainers pour les dépendances de démarrage
- Health checks et resource management
- Stratégies de migration progressive
- Outils et bonnes pratiques de migration

**Durée estimée :** 4-5 heures
**Niveau :** Intermédiaire

### TP8 - Réseau Kubernetes : Services, DNS et Connectivité

📁 **[Accéder au TP8](tp08/README.md)**

Maîtrisez en profondeur le réseau Kubernetes avec une approche pratique et progressive. Ce TP couvre :
- Modèle réseau Kubernetes et Container Network Interface (CNI)
- Services : ClusterIP, NodePort, LoadBalancer, ExternalName, Headless
- DNS Kubernetes et service discovery (CoreDNS)
- Endpoints et EndpointSlices
- NetworkPolicies pour la sécurité réseau (ingress, egress)
- Session affinity et load balancing
- Débogage réseau avec outils appropriés (tcpdump, netshoot)
- **Gateway API (K8s 1.31+)** — GatewayClass, Gateway, HTTPRoute, canary avancé
- Architectures réseau multi-tiers et multi-tenancy
- Cas pratiques et exercices progressifs

**Durée estimée :** 6-8 heures
**Niveau :** Intermédiaire à Avancé

### TP9 - Gestion Multi-Noeud de Kubernetes

📁 **[Accéder au TP9](tp09/README.md)**

Maîtrisez la gestion de clusters Kubernetes multi-noeuds pour la production. Ce TP couvre :
- Architecture d'un cluster multi-noeud (control planes, workers, etcd)
- Installation avec kubeadm et configuration HA
- Gestion du cycle de vie des nœuds (ajout, suppression, maintenance)
- Opérations de maintenance : cordon, drain, uncordon
- Haute disponibilité du control plane et load balancing
- Labels, selectors et NodeSelectors pour la planification
- Taints et Tolerations pour l'isolation des workloads
- Affinité et anti-affinité de nœuds et de pods
- PodDisruptionBudgets pour la disponibilité
- Upgrade de clusters et gestion des versions
- Monitoring, troubleshooting et résolution de problèmes
- Sauvegardes et restauration d'etcd

**Durée estimée :** 8-10 heures
**Niveau :** Avancé

### TP10 - Projet de Synthèse : Application TaskFlow avec Auto-scaling et Monitoring

📁 **[Accéder au TP10](tp10/README.md)**

Projet de synthèse qui intègre tous les concepts avancés des TPs précédents dans une application complète. Ce TP couvre :
- Déploiement d'une stack applicative multi-tiers (Frontend, Backend API, PostgreSQL, Redis)
- **HorizontalPodAutoscaler (HPA)** : Auto-scaling basé sur CPU/mémoire (2-10 replicas)
- **initContainers** : Initialisation de base de données avec 1000 tâches de test
- **Services** : ClusterIP pour composants internes, LoadBalancer pour exposition
- **Volumes (PVC)** : Persistance des données pour PostgreSQL et Prometheus
- **ConfigMaps et Secrets** : Configuration externalisée et gestion sécurisée des credentials
- **Monitoring** : Prometheus pour collecte de métriques et Grafana pour visualisation
- **Load Testing** : Générateur de charge pour observer l'autoscaling en action
- **RBAC** : ServiceAccounts pour Prometheus
- Architecture complète : Frontend (Nginx) → Backend API (Flask) → PostgreSQL + Redis + Prometheus + Grafana

**Durée estimée :** 3-4 heures
**Niveau :** Synthèse (tous les TPs précédents)

---

## Installation rapide

```bash
# Cloner le repository
git clone https://github.com/aboigues/kubernetes-formation.git
cd kubernetes-formation

# Accéder au TP1 pour commencer
cd tp1
cat README.md
```

## Repository

```
https://github.com/aboigues/kubernetes-formation.git
```

## Structure du projet

```
kubernetes-formation/
├── README.md                  # Ce fichier
├── tp01/                       # TP1 - Premier déploiement
│   └── README.md             # Guide complet du TP1
├── tp02/                       # TP2 - Manifests Kubernetes
│   └── README.md             # Guide complet du TP2
├── tp03/                       # TP3 - Persistance des données
│   └── README.md             # Guide complet du TP3
├── tp04/                       # TP4 - Monitoring et Logs
│   └── README.md             # Guide complet du TP4
├── tp05/                       # TP5 - Sécurité et RBAC
│   └── README.md             # Guide complet du TP5
├── tp06/                       # TP6 - Mise en Production et CI/CD
│   └── README.md             # Guide complet du TP6
├── tp07/                       # TP7 - Migration Docker Compose vers Kubernetes
│   ├── README.md             # Guide complet du TP7
│   ├── QUICKSTART.md         # Guide de démarrage rapide
│   ├── docker-compose-app/   # Application exemple avec Docker Compose
│   ├── kubernetes-manifests/ # Manifests Kubernetes correspondants
│   ├── frontend/             # Fichiers frontend
│   └── backend/              # Fichiers backend
├── tp08/                       # TP8 - Réseau Kubernetes
│   └── README.md             # Guide complet du TP8
├── tp09/                       # TP9 - Gestion Multi-Noeud
│   ├── README.md             # Guide complet du TP9
│   ├── examples/             # Exemples de manifests (affinités, taints, PDB)
│   └── exercices/            # Exercices pratiques
├── tp10/                      # TP10 - Projet de Synthèse TaskFlow
│   ├── README.md             # Guide complet du TP10
│   ├── QUICKSTART.md         # Guide de démarrage rapide
│   ├── deploy.sh             # Script de déploiement automatique
│   ├── test-tp10.sh          # Script de test automatisé
│   ├── 01-postgres-*.yaml    # Manifests PostgreSQL (init, secret, PVC, deployment, service)
│   ├── 06-redis-*.yaml       # Manifests Redis
│   ├── 08-backend-*.yaml     # Manifests Backend API (config, code, deployment, service, HPA)
│   ├── 12-frontend-*.yaml    # Manifests Frontend (config, deployment, service)
│   ├── 15-prometheus-*.yaml  # Manifests Prometheus (config, RBAC, PVC, deployment, service)
│   ├── 20-grafana-*.yaml     # Manifests Grafana (deployment, service)
│   └── 22-load-generator.yaml # Job de génération de charge
├── ckad-preparation/          # 🎓 Préparation Certification CKAD
│   ├── README.md             # Guide principal CKAD
│   ├── cheatsheet.md         # Commandes essentielles
│   ├── exercises/            # 65+ exercices par domaine
│   ├── practice-exam/        # Examens blancs
│   └── solutions/            # Solutions détaillées
├── .claude/                   # Configuration et instructions
│   ├── INSTRUCTIONS.md        # Instructions pour Claude
│   ├── QUICKSTART.md          # Guide de démarrage rapide (avec section CKAD)
│   └── CONTEXT.md             # Contexte et historique
├── docs/                      # Documentation complémentaire
├── examples/                  # Exemples de manifests YAML
│   ├── deployments/          # Exemples de déploiements
│   ├── services/             # Exemples de services
│   └── configs/              # Exemples de ConfigMaps et Secrets
└── exercises/                 # Solutions des exercices
```

## Démarrage

1. **Cloner le repository**
   ```bash
   git clone https://github.com/aboigues/kubernetes-formation.git
   cd kubernetes-formation
   ```

2. **Commencer par le TP1**
   ```bash
   cd tp1
   less README.md
   ```

3. **Suivre les instructions d'installation**
   - Commencer par la Partie 1 du TP1 pour installer l'environnement
   - Suivre les parties progressivement

4. **Réaliser les exercices pratiques**
   - Chaque TP contient des exercices avec solutions

## Tests automatiques

Cette formation intègre des tests automatiques via GitHub Actions pour garantir la qualité des manifests Kubernetes.

### Ce qui est testé

- **Validation YAML** : Syntaxe de tous les fichiers YAML du TP3
- **Validation Kubernetes** : Conformité des manifests avec les schémas Kubernetes
- **Tests d'intégration** : Déploiement réel sur Minikube (TP3)
- **Extraction README** : Validation de ~163 manifests contenus dans les README
- **Qualité documentation** : Vérification de la structure des README

### Statut par TP

| TP | Fichiers YAML testés | Tests d'intégration | Manifests README validés |
|----|----------------------|---------------------|--------------------------|
| TP1 | - | - | ~3 manifests |
| TP2 | - | - | ~35 manifests |
| TP3 | ✅ 9 fichiers | ✅ Tests Minikube | ~14 manifests |
| TP4 | - | - | ~23 manifests |
| TP5 | - | - | ~45 manifests |
| TP6 | - | - | ~43 manifests |
| TP7 | 13 fichiers | - | Application complète |

Pour plus de détails sur les tests, consultez [.github/workflows/README.md](.github/workflows/README.md).

## Concepts clés couverts

**Fondamentaux :**
- **Conteneurisation** : Docker, containerd, Podman
- **Orchestration** : Kubernetes (v1.32+) et minikube
- **Pods & Deployments** : Unité de base, gestion déclarative
- **Services** : Exposition et découverte (ClusterIP, NodePort, LoadBalancer)
- **ConfigMaps & Secrets** : Gestion sécurisée de la configuration

**Intermédiaire :**
- **Volumes & Stockage** : PV, PVC, StorageClasses, snapshots
- **Scaling** : Horizontal Pod Autoscaler (HPA), scaling manuel
- **Rolling updates & Rollback** : Mises à jour sans interruption
- **Sidecar containers natifs** : K8s 1.29+ `initContainers` avec `restartPolicy: Always`
- **RBAC** : Roles, ClusterRoles, ServiceAccounts, Pod Security Standards

**Avancé :**
- **Gateway API (K8s 1.31+)** : GatewayClass, Gateway, HTTPRoute — successeur de l'Ingress
- **ValidatingAdmissionPolicy (K8s 1.30+)** : Contrôles déclaratifs via CEL sans webhook
- **Network Policies** : Isolation réseau, ingress/egress rules
- **Monitoring** : Prometheus, Grafana, Metrics Server
- **CI/CD & GitOps** : GitHub Actions, ArgoCD, Helm, Kustomize
- **Multi-nœuds** : Taints, tolerations, affinités, haute disponibilité
- **Migration** : Docker Compose → Kubernetes avec Kompose

## Commandes kubectl essentielles

```bash
# Informations sur le cluster
kubectl cluster-info
kubectl get nodes

# Gestion des déploiements
kubectl create deployment <name> --image=<image>
kubectl get deployments
kubectl describe deployment <name>
kubectl delete deployment <name>

# Gestion des pods
kubectl get pods
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- /bin/bash

# Gestion des services
kubectl expose deployment <name> --type=NodePort --port=80
kubectl get services
kubectl describe service <name>

# Scaling
kubectl scale deployment <name> --replicas=3

# Mises à jour
kubectl set image deployment/<name> <container>=<image>
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>

# Fichiers YAML
kubectl apply -f <file.yaml>
kubectl delete -f <file.yaml>

# Informations générales
kubectl get all
kubectl get events
```

## Ressources complémentaires

### Documentation officielle
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

### Tutoriels interactifs
- [Kubernetes Tutorials](https://kubernetes.io/docs/tutorials/)
- [Katacoda Kubernetes Scenarios](https://www.katacoda.com/courses/kubernetes)

### Concepts avancés (à explorer après les TPs)
- Ingress Controllers et Ingress Resources
- StatefulSets pour applications avec état
- DaemonSets pour déploiements sur tous les nœuds
- **[Jobs et CronJobs](docs/JOBS_CRONJOBS.md)** pour tâches batch et planifiées
- Helm (gestionnaire de packages)
- Service Mesh (Istio, Linkerd)
- GitOps (ArgoCD, FluxCD)
- Custom Resource Definitions (CRDs)
- Operators

## Progression recommandée

1. **TP1** : Bases de Kubernetes et premier déploiement ✅
2. **TP2** : Maîtrise des manifests YAML ✅
3. **TP3** : Persistance des données ✅
4. **TP4** : Monitoring et logs ✅
5. **TP5** : Sécurité et RBAC ✅
6. **TP6** : Mise en production et CI/CD ✅
7. **TP7** : Migration Docker Compose vers Kubernetes ✅
8. **TP8** : Réseau Kubernetes : Services, DNS et Connectivité ✅
9. **TP9** : Gestion Multi-Noeud de Kubernetes ✅
10. **TP10** : Projet de Synthèse - Application TaskFlow avec Auto-scaling et Monitoring ✅

## Workflow avec Claude

### Nouvelle session

1. Claude recherche le contexte avec `conversation_search`
2. Clone le repo
3. Lit `.claude/INSTRUCTIONS.md`
4. Itère sur le code existant
5. Commit et push les modifications

### Commandes Git

```bash
# Cloner
git clone https://TOKEN@github.com/aboigues/kubernetes-formation.git

# Voir l'historique
git log --oneline

# Pousser les modifications
git add .
git commit -m "Description"
git push origin main
```

## Contribution

Ce projet est en développement continu. Les contributions sont les bienvenues :

- Signaler des bugs ou problèmes
- Proposer des améliorations
- Ajouter de nouveaux TPs
- Améliorer la documentation

## Licence

Ce projet de formation est fourni à des fins éducatives.

## Auteur

**Créé par:** aboigues
**Avec l'aide de:** Claude (Anthropic)
**Date de création:** 2025-10-29

---

**Bon apprentissage Kubernetes !**
