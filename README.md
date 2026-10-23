# ☸️ Formation Kubernetes — Travaux Pratiques

![TP — vérification](https://github.com/aboigues/kubernetes-formation/actions/workflows/ci.yml/badge.svg)

> Une formation [**Telemach Learning**](https://www.telemach-learning.fr). Ce dépôt sert **deux** formations :
>
> - **DEVOPS-012** — [Kubernetes : déployer et exploiter un cluster](https://www.telemach-learning.fr/formations/devops-012-kubernetes-deployer-exploiter-cluster.html) (2 jours)
> - **DEVOPS-010** — [Orchestration de conteneurs avec Kubernetes](https://www.telemach-learning.fr/formations/devops-010-kubernetes-orchestration.html) (3 jours)
>
> Le cours est dans les supports de formation. **Ce dépôt contient uniquement les TP.**

Ici, on **apprend en faisant** : chaque TP part de manifestes à trous que vous complétez vous-même, et un script vérifie que l'objectif est atteint — pas de copier/coller passif.

> 🚧 **Dépôt en cours de refonte (v2).** Les TP au nouveau format sont listés ci-dessous ; les dossiers `tp04/` à `tp11/` sont l'**ancienne génération**, retirée au fur et à mesure. L'état complet d'avant la refonte reste disponible : voir [Ancienne génération (v1)](#-ancienne-génération-v1).

---

## 🎯 Comment fonctionnent les TP

Chaque TP est un dossier autonome :

```
tpNN-theme/
├── README.md      ← le guide pas à pas (commencez TOUJOURS par là)
├── starter/       ← les manifestes À COMPLÉTER (cherchez les « ______ » et les « # TODO »)
├── solution/      ← la solution de référence (à consulter en dernier recours)
└── verify.sh      ← le script de validation (le même que la CI)
```

### La règle d'or

> **Si ce n'est pas testé par GitHub Actions, ça ne fonctionne pas.**

Chaque TP a une **cible vérifiable** : un rollout terminé, un Service qui répond, une mise à jour **sans une seule requête en échec**… `verify.sh` le contrôle sur un vrai cluster, et la CI l'exécute sur chaque `solution/`, dans un minikube identique au vôtre : la pastille verte prouve que le TP est réalisable de bout en bout.

### Votre méthode de travail

1. **Lisez le `README.md`** du TP en entier avant de taper la moindre commande.
2. **Travaillez dans `starter/`** : complétez les `______`, guidés par les `# TODO`.
3. **Validez vous-même** : `./verify.sh` depuis le dossier du TP.
4. **Bloqué ?** Relisez les « Indices », puis seulement en dernier recours, regardez `solution/`.
5. **En avance ?** Faites la section **🚀 Pour aller plus loin**.

Les sections **🎯 Avant de lancer la commande suivante, prédis…** vous demandent de parier sur le comportement de Kubernetes **avant** de l'observer. Prenez le temps de répondre : c'est là qu'on apprend le plus.

---

## 🛒 Le fil rouge : Télémarché

Tous les TP font vivre la même application, **Télémarché**, la boutique en ligne de produits frais de Telemach :

| Composant | Image | Arrive au |
|---|---|---|
| **web** — la vitrine | `telemachlearning/telemarche-web` | TP01 |
| **api** — catalogue et commandes | `telemachlearning/telemarche-api` | TP02 |
| **db** — PostgreSQL persistante | `postgres` | TP05 |

On la déploie, l'expose, la met à jour sans coupure, la configure, la rend persistante, la dimensionne, la protège, la package et la supervise. Ses images sont construites depuis [`apps/telemarche/`](apps/telemarche/README.md), qui documente aussi ses points d'entrée et ses variables.

Chaque TP fournit son **état de départ** : vous pouvez faire un TP sans avoir fait les précédents, dans l'ordre de l'une ou l'autre formation.

---

## 📚 Les TP

| TP | Sujet | Statut |
|----|-------|--------|
| [TP01](tp01-premier-cluster/) | Premier cluster : minikube, composants, impératif puis déclaratif | ✅ |
| [TP02](tp02-manifestes/) | Manifestes : écrire, valider, labels et sélecteurs | ✅ |
| [TP03](tp03-deployer-exposer/) | Déployer et exposer : Deployment, probes, Services, DNS, rolling update, diagnostic | ✅ |
| [TP04](tp04-jobs-daemonsets/) | DaemonSet, Job et CronJob : sonde par nœud, lot de commandes, rapport planifié | ✅ |
| [TP05](tp05-config-stockage/) | Configuration et stockage : ConfigMap, Secret, PVC, StatefulSet PostgreSQL, Job de migration | ✅ |
| [TP06](tp06-ressources-autoscaling/) | Ressources et autoscaling : requests/limits, QoS, `OOMKilled`, durcissement, HPA | ✅ |
| TP07 | Gateway API (Traefik) | 🚧 |
| TP08 | Namespaces, quotas et RBAC | 🚧 |
| TP09 | Placement et maintenance : affinités, taints, `drain`, PodDisruptionBudget | 🚧 |
| TP10 | Installer un cluster avec kubeadm | 🚧 |
| TP11 | Network Policies | 🚧 |
| TP12 | Helm | 🚧 |
| TP13 | Observabilité : Prometheus, Grafana, journaux | 🚧 |
| TP14 | Projet final : exploiter Télémarché et résoudre des incidents | 🚧 |

### Parcours DEVOPS-012 — déployer et exploiter un cluster (2 jours)

| Jour | Module | Atelier | TP |
|---|---|---|---|
| 1 | M1 — Découvrir Kubernetes | « Premier cluster » | TP01 |
| 1 | M2 — Architecture et manifestes | « Manifestes » | TP02 |
| 1 | M3 — Déployer et exposer une application | « Déployer et exposer » | TP03 (+ TP04) |
| 2 | M4 — Configuration et stockage | « Configuration et stockage » | TP05 |
| 2 | M5 — Kubernetes en production | « Production » | TP06 → TP07 → TP08 → TP09 |
| 2 | M6 — Déployer un cluster Kubernetes | « Installer un cluster » | TP10 |
| bonus | Pour aller plus loin | — | TP12 (Helm), TP13 (observabilité), TP11, TP14 |

### Parcours DEVOPS-010 — orchestration de conteneurs (3 jours)

| Jour | Module | TP |
|---|---|---|
| 1 | M1 — Architecture Kubernetes | TP01, TP02 |
| 1 | M2 — Workloads | TP03, TP04, TP06 |
| 2 | M3 — Services et Gateway API | TP07, TP11 |
| 2 | M4 — Configuration, Secrets, Volumes, RBAC | TP05, TP08 |
| 3 | M5 — Helm | TP12 |
| 3 | M6 — Observabilité | TP13 |
| 3 | Synthèse et incidents | TP14 |
| bonus | Pour aller plus loin | TP09, TP10 |

---

## ✅ Prérequis

- **Linux, WSL2 ou macOS**, avec un shell `bash` ; 2 processeurs et 4 Go de mémoire libres au minimum
- **Docker** (le driver de minikube)
- **minikube 1.39** ou plus récent, et **kubectl 1.36 à 1.38** (les TP ciblent Kubernetes **1.37**)
- `git` et `curl` ; **Helm 4** pour le TP12

Contrôlez votre poste — le script ne modifie rien :

```bash
./scripts/preflight.sh
```

Lab de référence : **AlmaLinux**, minikube (un nœud, puis plusieurs pour TP09), kubeadm pour TP10.

---

## 🤖 Tester en local comme la CI

Depuis n'importe quel dossier de TP :

```bash
cd tp03-deployer-exposer
./verify.sh              # votre travail (starter/)
./verify.sh solution     # la solution de référence
```

`verify.sh` déploie dans un namespace **jetable** (`tpNN-verify`) qu'il supprime ensuite : il ne touche jamais à votre namespace de travail `telemarche`. Pour garder ce namespace et l'inspecter après un échec : `KEEP=1 ./verify.sh`.

La CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) fait exactement la même chose, et vérifie en plus que chaque `starter/` **échoue** — un starter qui passerait ne laisserait rien à apprendre.

---

## 🧭 Conventions

- Votre namespace de travail est **`telemarche`** (créé au TP01). Les manifestes ne fixent **jamais** `metadata.namespace` : c'est la commande qui décide.
- Les images sont toujours en **version figée**, jamais `latest`.
- Les manifestes sont **durcis dès le TP01** (non-root, système de fichiers en lecture seule, ressources bornées) : 0 alerte HIGH/CRITICAL de `trivy config`. Le pourquoi est expliqué au TP06.
- Les commandes destructrices sont **toujours signalées** dans les README.
- Les mots de passe des TP sont **fictifs** et ne doivent jamais être réutilisés ailleurs.

---

## 🧑‍🏫 L'assistant TELEMACH (facultatif)

[TELEMACH](https://github.com/aboigues/telemach-plugin-kubectl) est un plugin `kubectl`, développé par le formateur, qui explique **en français** les erreurs de `kubectl` et les pods qui ne démarrent pas. Installation et usage pendant les TP : [ANNEXE-TELEMACH.md](ANNEXE-TELEMACH.md).

---

## 📦 Ancienne génération (v1)

Avant la refonte, le dépôt proposait 11 TP au format « manifestes complets » (`tp01/` à `tp11/`) et une préparation CKAD. Cet état est figé dans la release **[v1.0.0](https://github.com/aboigues/kubernetes-formation/tree/v1.0.0)** : les liens que vous avez reçus vers d'anciens TP y fonctionnent toujours.

| v1 | Remplacé par |
|---|---|
| `tp01` — premier déploiement | TP01 |
| `tp02` — manifestes (pods, deployments, services, WordPress) | TP02, TP03 (WordPress → TP05) |
| `tp03` — persistance | TP05 |
| `tp04` — monitoring et logs | TP06 (HPA), TP13 |
| `tp05` — sécurité et RBAC | TP08, TP11 |
| `tp06` — production, Helm, CI/CD | TP12 |
| `tp07` — migration Compose → Kubernetes | — (v1) |
| `tp08` — réseau | TP03, TP11 |
| `tp09` — multi-nœud | TP09 |
| `tp10` — projet de synthèse | TP14 |
| `tp11` — Gateway API | TP07 |

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

🌐 [www.telemach-learning.fr](https://www.telemach-learning.fr)

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
