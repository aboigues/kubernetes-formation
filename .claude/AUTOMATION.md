# Automatisation et CI/CD - Kubernetes Formation

Ce document décrit l'infrastructure d'automatisation mise en place pour garantir la qualité et la maintenance du projet.

## 🚀 Vue d'ensemble

Le projet kubernetes-formation dispose maintenant de deux niveaux d'automatisation :

1. **Session Start Hook** : Vérifications locales automatiques à chaque session Claude
2. **GitHub Actions** : CI/CD complet avec tests d'intégration sur GitHub

## 📋 Session Start Hook

### Emplacement
`.claude/hooks/session-start.sh`

### Exécution
Le hook s'exécute automatiquement au début de chaque session Claude et effectue les vérifications suivantes :

### ✅ Vérifications effectuées

#### 1. Versions des outils Kubernetes
- **kubectl** : Vérifie la version (recommandé >= 1.29)
- **minikube** : Détecte la présence et la version
- **helm** : Requis pour TP6
- **yq, yamllint** : Outils de validation YAML

**Alertes** :
- ⚠️ Si kubectl < v1.29 → recommandation de mise à jour
- ⚠️ Si outils manquants → liste des installations nécessaires

#### 2. État du cluster Kubernetes
- Vérifie l'accessibilité du cluster
- Affiche la version du serveur Kubernetes
- Compte le nombre de nœuds
- **Détecte le version skew** entre client et serveur
  - ✅ Acceptable : kubectl ±1 version mineure du serveur
  - ⚠️ Problématique : écart > 1 version mineure

#### 3. Validation des manifests YAML

**Syntaxe YAML** :
- Validation Python de tous les fichiers .yaml/.yml
- Détection des erreurs de syntaxe
- Couverture : tp1-tp9 + docs/
- Total : ~135 fichiers validés

**APIs Kubernetes dépréciées** :
Le hook détecte automatiquement **8 types d'APIs obsolètes** (synchronisé avec GitHub Actions) :

| API Dépréciée | Statut | Remplacement |
|---------------|--------|--------------|
| `extensions/v1beta1` | ❌ SUPPRIMÉ | `apps/v1` |
| `apps/v1beta1` | ❌ SUPPRIMÉ | `apps/v1` |
| `apps/v1beta2` | ❌ SUPPRIMÉ | `apps/v1` |
| `policy/v1beta1` (PDB) | ⚠️ Déprécié | `policy/v1` |
| `autoscaling/v2beta1` | ⚠️ Déprécié | `autoscaling/v2` |
| `autoscaling/v2beta2` | ⚠️ Déprécié | `autoscaling/v2` |
| `batch/v1beta1` (CronJob) | ⚠️ Déprécié | `batch/v1` |
| `networking.k8s.io/v1beta1` | ⚠️ Déprécié | `networking.k8s.io/v1` |

**Note** : Dernière synchronisation hook/workflow : 2025-12-15

#### 4. Vérification GitHub Actions
- Vérifie si les workflows sont déployés
- Détecte les versions obsolètes des actions :
  - `actions/checkout@v3` → v4 disponible
  - `actions/setup-python@v4` → v5 disponible
  - `azure/setup-kubectl@v3` → v4 disponible

#### 5. Scripts de test disponibles
- Liste tous les scripts `test-*.sh`
- Vérifie les permissions d'exécution
- Suggère les tests à exécuter si cluster disponible :
  - `tp05/test-tp5.sh` - Tests RBAC et sécurité
  - `tp08/test-tp8.sh` - Tests réseau
  - `tp09/test-tp9.sh` - Tests multi-nœuds

#### 6. Statistiques du projet
- Compte des fichiers par type (YAML, Markdown, scripts)
- Nombre de TPs
- Branche Git courante
- Détection des modifications non commitées

### 📊 Exemple de sortie

```
╔════════════════════════════════════════════════════════════╗
║  Kubernetes Formation - Session Start Verification        ║
╚════════════════════════════════════════════════════════════╝

▶ 1. Kubernetes Tooling Versions
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ kubectl is installed
  Version: v1.29.0
✓ minikube is installed
  Version: v1.32.0
✓ helm is installed
  Version: v3.13.0

▶ 3. YAML Manifest Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Found 124 YAML manifest files

✓ All YAML files are valid and up-to-date

▶ 7. Summary & Recommendations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ All checks passed!
```

## 🔄 GitHub Actions CI/CD

### Emplacement
`.github/workflows/test-kubernetes-manifests.yml`

### Déclencheurs
- **Push** sur branches : `main`, `claude/**`
- **Pull Requests** vers `main`

### 🎯 Jobs du workflow

#### 1. `validate-yaml-syntax`
- **Outil** : yamllint
- **Cible** : Tous les TPs (tp3-tp9)
- **Configuration** :
  - Max 120 caractères par ligne (warning)
  - Indentation : 2 espaces
  - Document-start désactivé

#### 2. `check-deprecated-apis` ⭐ NOUVEAU
- **Détection automatique des APIs obsolètes**
- Scanne tous les fichiers YAML
- Identifie les APIs :
  - ❌ Supprimées (REMOVED)
  - ⚠️ Dépréciées (DEPRECATED)
- **Ne fait pas échouer le build** (warning uniquement)
- Affiche un rapport détaillé

#### 3. `validate-kubernetes-manifests`
- **Outils** : kubeconform v0.6.6 + kubectl v1.29.0
- **Validations** :
  - Conformité avec les schémas Kubernetes
  - kubectl dry-run pour tous les manifests
- **Cible** : Tous les TPs (tp3-tp9)

#### 4. `test-tp3-storage`
- **Cluster** : Minikube v1.29.0
- **Tests d'intégration** :
  - emptyDir volumes
  - PersistentVolume
  - PersistentVolumeClaim
  - Pods avec PVC
- **Cleanup** : Automatique avec `if: always()`

#### 5. `test-tp5-security` ⭐ NOUVEAU
- **Script** : `tp05/test-tp5.sh`
- **Tests** :
  - RBAC (Roles, RoleBindings)
  - ServiceAccounts
  - Secrets
  - Security Contexts
  - Network Policies

#### 6. `test-tp8-networking` ⭐ NOUVEAU
- **Script** : `tp08/test-tp8.sh`
- **Tests** :
  - Types de services (ClusterIP, NodePort, etc.)
  - Résolution DNS
  - Network Policies
  - Architecture multi-tiers

#### 7. `test-tp9-multi-node` ⭐ NOUVEAU
- **Script** : `tp09/test-tp9.sh`
- **Tests** :
  - Node affinity
  - Taints et tolerations
  - PodDisruptionBudgets
  - Haute disponibilité

#### 8. `validate-readme-manifests`
- **Extraction** : Tous les blocs YAML des READMEs
- **Validation** : Syntaxe YAML + ressources Kubernetes
- **Couverture** : tp1-tp9 (tous les TPs)
- **Résumé** : Nombre total de blocs et ressources K8s

#### 9. `lint-readme`
- Vérifie la présence de tous les README (tp1-tp9)
- Détecte les blocs de code non fermés
- Compte les lignes de documentation

#### 10. `security-scan` ⭐ NOUVEAU
- **Outil** : Trivy (Aqua Security)
- **Type** : Scan de configuration
- **Sévérités** : CRITICAL, HIGH
- **Intégration** : GitHub Security Tab (SARIF)
- **Format** : Rapports de sécurité uploadés automatiquement

### 📈 Améliorations apportées

| Aspect | Avant | Après |
|--------|-------|-------|
| **TPs testés** | TP3 uniquement | TP3, TP5, TP8, TP9 |
| **Versions** | kubectl 1.28 | kubectl 1.29 (latest) |
| **Python** | 3.11 | 3.12 (latest) |
| **Kubeconform** | 0.6.4 | 0.6.6 (latest) |
| **Vérif. obsolescence** | ❌ Aucune | ✅ Complète |
| **Scan sécurité** | ❌ Aucun | ✅ Trivy |
| **Tests auto** | 1 TP | 4 TPs |

## 🔐 Détection d'obsolescence

### Pourquoi c'est important ?

Les APIs Kubernetes évoluent rapidement :
- Kubernetes 1.16 : Suppression de plusieurs APIs beta
- Kubernetes 1.22 : Suppression d'APIs largement utilisées
- Kubernetes 1.25+ : Migrations continues

**Sans vérification** :
- ❌ Les manifests deviennent incompatibles
- ❌ Les déploiements échouent sans avertissement
- ❌ Les étudiants apprennent des pratiques obsolètes

**Avec notre système** :
- ✅ Détection précoce des problèmes
- ✅ Suggestions de migration automatiques
- ✅ Contenu toujours à jour
- ✅ Apprentissage des meilleures pratiques

### Fréquence de vérification

| Niveau | Quand | Outils |
|--------|-------|--------|
| **Local** | Chaque session Claude | session-start.sh |
| **Git** | Chaque commit/PR | GitHub Actions |
| **Continue** | Push sur branches | Workflow complet |
| **Hebdomadaire** | Lundi 04:00 UTC | scan-images.yml (CVE des images) |

## 🔎 Scan hebdomadaire des images

### Emplacement
`.github/workflows/scan-images.yml`

### Pourquoi un workflow séparé

Le job `security-scan` du workflow principal fait un `trivy config` : il détecte les
**misconfigurations des manifests** (securityContext manquant, etc.). Il ne regarde
**pas le contenu des images**. Les CVE des images (`postgres:15-alpine`, `grafana/grafana:10.2.0`…)
apparaissent sans qu'on touche au code : d'où un scan **périodique** plutôt que sur commit.

### Déclencheurs
- **Schedule** : tous les lundis à `0 4 * * 1` (**UTC** — GitHub n'accepte pas d'autre fuseau,
  soit 05:00 à Paris en hiver / 06:00 en été)
- **Manuel** : bouton "Run workflow" (`workflow_dispatch`)
- **Push** : uniquement si le scan lui-même est modifié

> ⚠️ GitHub **désactive les workflows planifiés après 60 jours sans activité** sur le dépôt.
> Si le scan ne tourne plus, le réactiver dans l'onglet Actions.

### Jobs

| Job | Rôle |
|-----|------|
| `list-images` | Extrait les images des manifests → matrice |
| `scan-image` | Un job Trivy par image (5 en parallèle max), SARIF → onglet Security |
| `report` | Agrège tous les rapports en un tableau récapitulatif |

### Extraction des images

`.github/scripts/extract-images.py` **parse le YAML** au lieu de faire un `grep image:`.
C'est nécessaire : `tp03/14-network-storage-examples-secure.yaml` contient un
`image: pv-data-001` qui est une **image RBD Ceph**, pas une image de conteneur.
Le script ne retient que les champs `image` sous `containers`, `initContainers`,
`ephemeralContainers`, `steps` et `sidecars`.

Sont écartées automatiquement :
- les images avec variables non résolues (`node:$(params.node-version)-alpine`)
- les images fictives listées dans `.github/image-scan-ignore.txt` (`myapp:1.0.0`,
  `taskflow-backend:latest`…) : elles n'existent sur aucun registre

**Toute nouvelle image d'exemple dans un TP doit être ajoutée à l'ignore-list**, sinon le
scan échouera en tentant de la puller.

```bash
# Vérifier localement ce qui sera scanné (et ce qui est écarté)
python3 .github/scripts/extract-images.py --verbose
```

### Politique de résultat : bloquant sur HIGH et CRITICAL

Le scan **échoue** (exit 1) dès qu'une vulnérabilité HIGH ou CRITICAL est trouvée, sur
n'importe quelle image. C'est cohérent avec l'objectif du projet : 0 vulnérabilité
HIGH/CRITICAL (voir `SECURITY.md`).

L'échec est porté par le job **`report`**, pas par les scans individuels. C'est
volontaire : mettre `exit-code: '1'` sur l'étape Trivy interromprait le job avant
l'upload SARIF, et on perdrait les résultats dans l'onglet Security au moment précis
où il y a quelque chose à voir. Le job `report` échoue à la fin, une fois toutes les
données collectées et le tableau publié.

```bash
# Reproduire la décision en local
python3 .github/scripts/image-scan-report.py reports --fail-on CRITICAL,HIGH
# exit 0 = aucune vulnérabilité bloquante | exit 1 = scan en échec
```

**Conséquence à assumer** : un HIGH publié sur une image amont rend le scan rouge le
lundi suivant, même sans commit. C'est le comportement voulu (une CVE apparaît sans
qu'on touche au code), mais cela demande de traiter les alertes pour que le rouge garde
son sens.

Le rapport distingue les vulnérabilités **corrigeables** (un correctif existe → monter le
tag suffit) des autres. C'est la colonne à regarder en premier : les non-corrigeables
demandent un changement d'image ou une acceptation du risque.

**Pour ajuster le seuil**, modifier `--fail-on` dans le job `report` de
`scan-images.yml` :
- `--fail-on CRITICAL` → seuls les CRITICAL bloquent
- (sans `--fail-on`) → scan purement informatif, ne bloque jamais

## 🛠️ Utilisation

### En local

```bash
# Exécuter le hook manuellement
./.claude/hooks/session-start.sh

# Rendre exécutable si nécessaire
chmod +x ./.claude/hooks/session-start.sh
```

### Sur GitHub

Les workflows s'exécutent automatiquement :
1. À chaque push sur main ou branches claude/**
2. À chaque Pull Request vers main
3. Résultats visibles dans l'onglet "Actions"

### Badge de statut

Ajoutez au README :
```markdown
![CI](https://github.com/aboigues/kubernetes-formation/workflows/Test%20Kubernetes%20Manifests/badge.svg)
```

## 📊 Métriques actuelles

**État du projet au 2025-12-15** :
- ✅ 135+ manifests YAML validés (tp1-tp9 + docs/)
- ✅ 0 APIs dépréciées détectées
- ✅ 63 fichiers Markdown
- ✅ 9 TPs complets
- ✅ 7 scripts de test automatisés
- ✅ 12 jobs GitHub Actions (incluant test-tp1, test-tp2)
- ✅ Scan hebdomadaire des CVE sur ~38 images (scan-images.yml)

## 🎯 Règles de qualité

### Avant chaque commit
1. ✅ Tous les YAML doivent être syntaxiquement valides
2. ✅ Aucune API dépréciée ou supprimée
3. ✅ Tous les READMEs doivent exister
4. ✅ Les blocs de code doivent être fermés

### Avant chaque release
1. ✅ Tous les tests d'intégration passent
2. ✅ Aucune vulnérabilité CRITICAL/HIGH
3. ✅ Versions d'outils à jour
4. ✅ Documentation synchronisée

## 🔄 Maintenance

### Mise à jour des versions recommandées

Éditer `.claude/hooks/session-start.sh` :
```bash
# Ligne ~80 : Vérifier version kubectl
if [[ "$major_minor" < "v1.30" ]] && [[ "$major_minor" != "unknown" ]]; then
    echo -e "  ${YELLOW}⚠ kubectl version is older than 1.30, consider upgrading${NC}"
fi
```

### Ajouter une nouvelle API dépréciée

Dans le hook **ET** dans le workflow GitHub Actions :
```bash
if grep -q "apiVersion: nouvelle/v1beta1" "$file" 2>/dev/null; then
    echo -e "${YELLOW}⚠${NC} nouvelle/v1beta1 is deprecated (use nouvelle/v1)"
    file_has_issues=1
fi
```

### Ajouter un nouveau TP aux tests

Éditer `.github/workflows/test-kubernetes-manifests.yml` :
```yaml
test-tp10-nouvelle-fonctionnalite:
  name: Test TP10 - Nouvelle Fonctionnalité
  runs-on: ubuntu-latest
  steps:
    - name: Checkout code
      uses: actions/checkout@v4
    - name: Set up Minikube
      uses: medyagh/setup-minikube@latest
      with:
        kubernetes-version: 'v1.29.0'
    - name: Run TP10 tests
      run: |
        chmod +x tp10/test-tp10.sh
        cd tp10
        ./test-tp10.sh
```

## 📚 Ressources

- [Kubernetes API Deprecation Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
- [kubeconform](https://github.com/yannh/kubeconform)
- [yamllint](https://yamllint.readthedocs.io/)
- [Trivy Security Scanner](https://github.com/aquasecurity/trivy)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## 🎉 Conclusion

Ce système d'automatisation garantit :
- ✅ **Qualité** : Validation continue de tous les manifests
- ✅ **Modernité** : Détection automatique des APIs obsolètes
- ✅ **Sécurité** : Scan des vulnérabilités
- ✅ **Fiabilité** : Tests d'intégration sur 4 TPs
- ✅ **Maintenabilité** : Détection précoce des problèmes
- ✅ **Excellence pédagogique** : Contenu toujours à jour avec les meilleures pratiques
