# QUICKSTART - Claude - kubernetes-lab

## Début de session

```bash
# 1. Retrouver contexte
conversation_search: "kubernetes-lab"

# 2. Cloner
cd /home/claude
git clone https://TOKEN@github.com/aboigues/kubernetes-formation.git
cd kubernetes-formation

# 3. Lire instructions
cat .claude/INSTRUCTIONS.md

# 4. Lire contexte
cat .claude/CONTEXT.md
```

## Workflow standard

```bash
# Modifier selon demande
# ...

# Mettre à jour contexte
echo "## Session $(date +%Y-%m-%d)" >> .claude/CONTEXT.md
echo "- [Changements]" >> .claude/CONTEXT.md

# Push
git add .
git commit -m "Session $(date +%Y-%m-%d): Description"
git push origin main

# Outputs
cp -r . /mnt/user-data/outputs/kubernetes-lab/
```

## Règles essentielles

- Toujours partir de la dernière version Git
- Mettre à jour CONTEXT.md
- Messages de commit clairs
- Documenter les changements importants

## Repository

https://github.com/aboigues/kubernetes-formation.git

---

## Préparation à la Certification CKAD

### Qu'est-ce que la CKAD ?

La **CKAD (Certified Kubernetes Application Developer)** est une certification pratique de la Cloud Native Computing Foundation (CNCF) qui valide les compétences pour concevoir, construire, configurer et déployer des applications cloud-native sur Kubernetes.

### Format de l'examen

- **Durée** : 2 heures
- **Type** : Performance-based (ligne de commande uniquement)
- **Score** : 66% minimum pour réussir
- **Environnement** : Clusters Kubernetes préconfigurés
- **Accès** : Documentation officielle Kubernetes autorisée

### Domaines couverts (CKAD 2024)

1. **Application Design and Build (20%)**
   - Définir et construire des images de conteneurs
   - Choisir et utiliser un Job ou CronJob
   - Comprendre les stratégies de déploiement multi-conteneurs

2. **Application Deployment (20%)**
   - Utiliser les primitives Kubernetes pour déployer des applications
   - Comprendre les Deployments et les stratégies de rollout
   - Utiliser Helm pour gérer les packages

3. **Application Observability and Maintenance (15%)**
   - Comprendre les probes (liveness, readiness, startup)
   - Surveiller, logger et déboguer les applications
   - Utiliser les métriques

4. **Application Environment, Configuration and Security (25%)**
   - Découvrir et utiliser les ressources (ConfigMaps, Secrets)
   - Comprendre SecurityContexts
   - Définir les resource requirements et limits
   - Comprendre les ServiceAccounts

5. **Services and Networking (20%)**
   - Démontrer la compréhension des Services et NetworkPolicies
   - Utiliser Ingress pour exposer les applications
   - Comprendre la connectivité réseau entre Pods

### Corrélation avec nos TPs

| TP | Domaines CKAD couverts | Compétences clés |
|----|-----------------------|------------------|
| **TP1** | Application Deployment (20%) | Déploiements, ReplicaSets, Pods |
| **TP2** | Services & Networking (20%) | Services, ClusterIP, NodePort, LoadBalancer |
| **TP3** | Application Environment (25%) | ConfigMaps, Secrets, Variables d'environnement |
| **TP4** | Application Observability (15%) | Health checks, Liveness/Readiness probes |
| **TP5** | Application Environment (25%) | Ressources limits/requests, Quotas, LimitRanges |
| **TP6** | Application Build & Deploy (20%) | CI/CD, Stratégies de déploiement, Rolling updates |

### Parcours d'entraînement CKAD

#### Phase 1 : Fondamentaux (Semaines 1-2)
```bash
# Compléter dans l'ordre
1. tp01/README.md
2. tp02/README.md
3. tp03/README.md

# Objectif : Maîtriser kubectl et les ressources de base
```

#### Phase 2 : Observabilité et Sécurité (Semaines 3-4)
```bash
4. tp04/README.md
5. tp05/README.md

# Objectif : Debugging, probes, resource management
```

#### Phase 3 : Production Ready (Semaines 5-6)
```bash
6. tp06/README.md

# Objectif : Déploiements avancés, stratégies de release
```

### Commandes essentielles CKAD

```bash
# Vitesse et efficacité
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"

# Génération rapide de manifests
k run nginx --image=nginx $do > pod.yaml
k create deploy webapp --image=nginx --replicas=3 $do > deploy.yaml
k expose deploy webapp --port=80 --target-port=80 $do > svc.yaml
k create configmap app-config --from-literal=key=value $do > cm.yaml
k create secret generic app-secret --from-literal=password=secret $do > secret.yaml
k create job test --image=busybox $do -- /bin/sh -c "echo hello" > job.yaml
k create cronjob test --image=busybox --schedule="*/5 * * * *" $do -- /bin/sh -c "echo hello" > cj.yaml

# Debugging rapide
k describe pod <pod-name>
k logs <pod-name> [-c container-name]
k exec -it <pod-name> -- /bin/sh
k get events --sort-by=.metadata.creationTimestamp

# Édition en place
k edit deploy <deployment-name>
k set image deploy/<name> container=image:tag
k scale deploy/<name> --replicas=5
k rollout status deploy/<name>
k rollout undo deploy/<name>
```

### Stratégies pour l'examen

1. **Gestion du temps**
   - 2h pour ~15-20 questions = 6-8 min/question
   - Commencer par les questions faciles (quick wins)
   - Marquer les difficiles pour y revenir

2. **Configuration initiale**
   ```bash
   # Premier réflexe à l'examen
   alias k=kubectl
   export do="--dry-run=client -o yaml"
   source <(kubectl completion bash)
   complete -F __start_kubectl k
   ```

3. **Documentation autorisée**
   - kubernetes.io/docs
   - kubernetes.io/blog
   - github.com/kubernetes

   **Favoris à préparer** :
   - Pod spec reference
   - Service spec
   - Ingress examples
   - Resource limits
   - Network policies
   - Security context

4. **Vérification systématique**
   ```bash
   # Toujours vérifier après création
   k get <resource> -o wide
   k describe <resource> <name>
   k logs <pod-name>
   ```

5. **Patterns de correction**
   - Question demande "fix" → k describe pour voir les events
   - Problème réseau → Vérifier Services et NetworkPolicies
   - Pod CrashLoop → Vérifier logs et probes
   - Permission denied → Vérifier RBAC et SecurityContext

### Exercices type CKAD

#### Exercice 1 : Multi-container Pod
```yaml
# Créer un Pod avec :
# - Container nginx sur port 80
# - Sidecar busybox qui log toutes les 5s
# - Volume partagé entre les deux
```

#### Exercice 2 : Rolling Update
```bash
# 1. Déployer nginx:1.19 avec 3 replicas
# 2. Update vers nginx:1.20 avec maxSurge=1 et maxUnavailable=0
# 3. Vérifier le rollout progressif
```

#### Exercice 3 : Configuration et Secrets
```bash
# 1. Créer ConfigMap avec config.json
# 2. Créer Secret avec credentials
# 3. Monter les deux dans un Pod
# 4. Ajouter variables d'env depuis ConfigMap
```

#### Exercice 4 : Network Policy
```yaml
# Créer NetworkPolicy qui :
# - Autorise ingress uniquement depuis les Pods avec label app=frontend
# - Sur port 8080
# - Vers Pods avec label app=backend
```

### Ressources complémentaires

- **Documentation officielle** : https://kubernetes.io/docs/
- **CKAD Curriculum** : https://github.com/cncf/curriculum
- **Killer.sh** : Simulateur d'examen (2 sessions incluses avec l'inscription)
- **Kubernetes By Example** : https://kubernetesbyexample.com/
- **Practice** : https://github.com/dgkanatsios/CKAD-exercises

### Checklist avant l'examen

- [ ] Compléter tous les TPs du repository
- [ ] Maîtriser kubectl (create, get, describe, edit, delete, logs, exec)
- [ ] Savoir générer des manifests avec --dry-run=client -o yaml
- [ ] Connaître les patterns multi-conteneurs (sidecar, init, adapter)
- [ ] Comprendre les probes (liveness, readiness, startup)
- [ ] Savoir déboguer un Pod qui ne démarre pas
- [ ] Maîtriser ConfigMaps et Secrets (create, mount, env)
- [ ] Comprendre Services et leur fonctionnement
- [ ] Savoir créer et appliquer des NetworkPolicies
- [ ] Connaître les stratégies de déploiement (RollingUpdate, Recreate)
- [ ] Pratiquer avec Killer.sh (au moins 2x)
- [ ] Vérifier setup technique (ID, webcam, environnement calme)

### Tips finaux

1. **Vitesse avant perfection** : L'examen est chronométré, privilégier les solutions qui marchent
2. **YAML minimal** : Utiliser --dry-run puis éditer, ne pas écrire from scratch
3. **Vérifier toujours** : Un k get/describe/logs après chaque création
4. **Lire attentivement** : Les questions précisent le namespace, le nom, etc.
5. **Context switching** : Chaque question peut être sur un cluster différent (kubectl config use-context)

---

**Bonne préparation ! La pratique régulière avec ces TPs est la clé du succès à la CKAD.**
