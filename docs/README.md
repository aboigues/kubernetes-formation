# Documentation Kubernetes Formation

Cette section contient l'ensemble de la documentation complémentaire du projet kubernetes-formation. Ces guides couvrent des sujets avancés, des références pratiques et des scénarios de déploiement spécifiques.

## Table des matières

- [Démarrage et Installation](#démarrage-et-installation)
- [Guides de Référence](#guides-de-référence)
- [Sécurité et Environnements Avancés](#sécurité-et-environnements-avancés)
- [Gestion des Secrets](#gestion-des-secrets)

---

## Démarrage et Installation

### [CLASSE_VIRTUELLE_RUSTDESK.md](./CLASSE_VIRTUELLE_RUSTDESK.md)
Se connecter à son poste de formation distant : bureau à distance RustDesk, puis SSH à travers un tunnel RustDesk.

### [INSTALLER_KUBECTL_MINIKUBE.md](./INSTALLER_KUBECTL_MINIKUBE.md)
Préparer un poste Linux neuf : kubectl, minikube, premier `minikube start`, Helm pour le TP12.

### [GETTING_STARTED.md](./GETTING_STARTED.md)
Guide de démarrage rapide pour la formation Kubernetes.

**Contenu :**
- Introduction au projet
- Prérequis nécessaires
- Installation et configuration
- Exemples d'utilisation
- Troubleshooting de base

### [KUBEADM_SETUP.md](./KUBEADM_SETUP.md)
Guide complet d'installation d'un cluster Kubernetes avec kubeadm.

**Contenu :**
- Différences entre minikube et kubeadm
- Prérequis matériels (master + workers)
- Installation pas à pas d'un cluster multi-nœuds
- Configuration du réseau (CNI plugins)
- Déploiement production-ready

**Cas d'usage :** Installation de clusters Kubernetes en production ou environnement de test réaliste.

### [WINDOWS_SETUP.md](./WINDOWS_SETUP.md)
Instructions spécifiques pour configurer l'environnement Kubernetes sous Windows.

**Contenu :**
- Installation des outils sur Windows
- Configuration de WSL2 (Windows Subsystem for Linux)
- Docker Desktop et alternatives
- Minikube sous Windows

---

## Guides de Référence

### [KUBECTL_KUBEADM_MINIKUBE_REFERENCE.md](./KUBECTL_KUBEADM_MINIKUBE_REFERENCE.md)
Référence complète des commandes kubectl, kubeadm et minikube.

**Contenu :**
- Commandes kubectl essentielles
- Options et flags avancés
- Commandes kubeadm pour la gestion de cluster
- Commandes minikube pour le développement local
- Exemples pratiques et use cases

**Utilisation :** Aide-mémoire et référence rapide pour tous les TPs.

### [KUBERNETES_RESOURCES_SCHEMA.md](./KUBERNETES_RESOURCES_SCHEMA.md)
Schémas visuels complets de l'architecture et des ressources Kubernetes.

**Contenu :**
- Architecture globale d'un cluster Kubernetes
- Hiérarchie et relations entre les ressources
- Diagrammes du Control Plane et Worker Nodes
- Ressources par catégorie (workloads, réseau, stockage, etc.)
- Flux de déploiement

**Utilisation :** Comprendre visuellement l'architecture Kubernetes et les interactions entre composants.

### [JOBS_CRONJOBS.md](./JOBS_CRONJOBS.md)
Guide détaillé sur les Jobs et CronJobs Kubernetes.

**Contenu :**
- Différence entre Jobs et CronJobs
- Configuration et options
- Patterns de parallélisation
- Gestion des échecs et retry
- Exemples pratiques (batch processing, tâches planifiées)

### [TIPS_AND_TRICKS.md](./TIPS_AND_TRICKS.md)
Astuces et bonnes pratiques pour travailler efficacement avec Kubernetes.

**Contenu :**
- Raccourcis et alias utiles
- Techniques de debugging
- Optimisations de workflow
- Commandes avancées
- Pièges courants à éviter

### [APPLICATION_LIFECYCLE.md](./APPLICATION_LIFECYCLE.md)
Guide sur le cycle de vie des applications dans Kubernetes.

**Contenu :**
- Déploiement d'applications
- Rolling updates et rollbacks
- Stratégies de mise à jour (RollingUpdate, Recreate)
- Gestion des versions
- Blue/Green et Canary deployments

---

## Sécurité et Environnements Avancés

### [SECURE_CLUSTER_MANAGEMENT.md](./SECURE_CLUSTER_MANAGEMENT.md)
Gestion d'un cluster Kubernetes en environnement hautement sécurisé.

**Contenu :**
- Principes de sécurité en environnement hermétique
- Architecture en DMZ (Zone Démilitarisée)
- Isolation réseau stricte
- Contrôle des flux réseau
- Network Policies avancées
- Audit et logging en environnement sécurisé

**Cas d'usage :** Clusters en DMZ, environnements réglementés, infrastructures critiques.

### [AIRGAP_DEPLOYMENT.md](./AIRGAP_DEPLOYMENT.md)
Déploiement Kubernetes dans un environnement totalement déconnecté (air-gapped).

**Contenu :**
- Définition et caractéristiques d'un environnement air-gapped
- Cas d'usage (militaire, gouvernement, industriel)
- Architecture de déploiement déconnecté
- Stratégies de transfert d'images et binaires
- Gestion des mises à jour sans Internet
- Registres d'images privés pré-chargés
- PKI interne et certificats

**Cas d'usage :** Environnements militaires, systèmes critiques, laboratoires isolés.

### [IMAGE_REGISTRY_DMZ.md](./IMAGE_REGISTRY_DMZ.md)
Mise en place et gestion d'un registre d'images privé en environnement DMZ.

**Contenu :**
- Pourquoi un registre privé (sécurité, conformité, performance)
- Architecture de registre en DMZ
- Solutions de registre (Harbor, Nexus, Registry)
- Scan de vulnérabilités automatique
- Politique de rétention et gouvernance
- Synchronisation avec registres publics
- Mirror et cache de Docker Hub

**Cas d'usage :** Environnements sécurisés nécessitant un contrôle total des images.

---

## Gestion des Secrets

### [OPENBAO_KUBERNETES.md](./OPENBAO_KUBERNETES.md)
Guide complet d'intégration d'OpenBao (fork open-source de Vault) avec Kubernetes.

**Contenu :**
- Introduction à OpenBao et comparaison avec Secrets K8s natifs
- Installation via Helm
- Configuration et initialisation
- Authentification Kubernetes native (ServiceAccount)
- Injection de secrets dans les Pods
- Rotation automatique des secrets
- Haute disponibilité
- Cas d'usage pratiques
- Troubleshooting

**Cas d'usage :** Gestion centralisée et sécurisée des secrets, rotation automatique, audit complet.

---

## Navigation

### Par niveau de difficulté

**Débutant :**
- [GETTING_STARTED.md](./GETTING_STARTED.md)
- [WINDOWS_SETUP.md](./WINDOWS_SETUP.md)
- [KUBECTL_KUBEADM_MINIKUBE_REFERENCE.md](./KUBECTL_KUBEADM_MINIKUBE_REFERENCE.md)
- [TIPS_AND_TRICKS.md](./TIPS_AND_TRICKS.md)

**Intermédiaire :**
- [KUBEADM_SETUP.md](./KUBEADM_SETUP.md)
- [KUBERNETES_RESOURCES_SCHEMA.md](./KUBERNETES_RESOURCES_SCHEMA.md)
- [JOBS_CRONJOBS.md](./JOBS_CRONJOBS.md)
- [APPLICATION_LIFECYCLE.md](./APPLICATION_LIFECYCLE.md)

**Avancé :**
- [SECURE_CLUSTER_MANAGEMENT.md](./SECURE_CLUSTER_MANAGEMENT.md)
- [IMAGE_REGISTRY_DMZ.md](./IMAGE_REGISTRY_DMZ.md)
- [OPENBAO_KUBERNETES.md](./OPENBAO_KUBERNETES.md)
- [AIRGAP_DEPLOYMENT.md](./AIRGAP_DEPLOYMENT.md)

### Par cas d'usage

**Développement local :**
- [GETTING_STARTED.md](./GETTING_STARTED.md)
- [WINDOWS_SETUP.md](./WINDOWS_SETUP.md)
- [TIPS_AND_TRICKS.md](./TIPS_AND_TRICKS.md)

**Production standard :**
- [KUBEADM_SETUP.md](./KUBEADM_SETUP.md)
- [APPLICATION_LIFECYCLE.md](./APPLICATION_LIFECYCLE.md)
- [OPENBAO_KUBERNETES.md](./OPENBAO_KUBERNETES.md)

**Environnements sécurisés/réglementés :**
- [SECURE_CLUSTER_MANAGEMENT.md](./SECURE_CLUSTER_MANAGEMENT.md)
- [IMAGE_REGISTRY_DMZ.md](./IMAGE_REGISTRY_DMZ.md)
- [AIRGAP_DEPLOYMENT.md](./AIRGAP_DEPLOYMENT.md)

---

## Contribution

Ces documents sont maintenus dans le cadre de la formation Kubernetes. Pour toute suggestion d'amélioration ou correction :

1. Vérifier la cohérence avec les TPs (tp1-tp9)
2. Maintenir les schémas ASCII à jour
3. Inclure des exemples pratiques
4. Tester les commandes avant de documenter

## Validation

Tous les manifests YAML présents dans cette documentation sont automatiquement validés par :
- Session-start hook local (`.claude/hooks/session-start.sh`)
- GitHub Actions CI/CD (`.github/workflows/test-kubernetes-manifests.yml`)

**État actuel :**
- Manifests validés : Tous
- APIs dépréciées détectées : Aucune
- Version Kubernetes cible : 1.29+

---

**Note :** Pour revenir au projet principal, consultez le [README racine](../README.md).
