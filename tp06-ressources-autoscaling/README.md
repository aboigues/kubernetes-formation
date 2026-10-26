# TP06 — Ressources et autoscaling

> Durée estimée : 1 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, Service, probes).

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes, et votre contexte reste réglé sur `telemarche`.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
```

L'état de départ est fourni : `starter/00-web.yaml`, appliqué à l'étape 1. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Télémarché prépare sa première grande opération commerciale. L'équipe veut deux garanties : que l'API **ne déborde pas** sur les autres applications du cluster, et qu'elle **ajoute des pods toute seule** quand les clients affluent, puis les retire quand ils repartent.

Deux outils pour cela : les **requests et limits**, qui disent au cluster ce que consomme un conteneur, et le **HorizontalPodAutoscaler** (HPA), qui ajuste le nombre de réplicas d'après la consommation mesurée.

```
   metrics-server ──(CPU, mémoire)──> HPA api ──(réplicas : 2 à 6)──> Deployment api
         ▲                                                              │
         └──────────── kubelet de chaque nœud <── pods api ◀────────────┘
                                                     ▲
                                        Job charge (outils/charge.yaml)
```

## 🎯 Objectif vérifiable

L'API a des requests et des limits (classe QoS `Burstable`), un HPA la pilote entre 2 et 6 réplicas, et son manifeste ne fixe plus `replicas`. `./verify.sh` lance une charge CPU et vérifie que l'API **monte à 4 réplicas prêts ou plus**.

---

## Étape 1 — Requests, limits et classes QoS

Complétez `starter/api.yaml` (`# TODO 1` à `4`), puis :

```bash
kubectl apply -f starter/00-web.yaml -f starter/api.yaml
kubectl rollout status deployment/api
```

| | Rôle | Si le conteneur dépasse |
|---|---|---|
| **requests** | ce que le **scheduler** réserve sur le nœud pour placer le pod | rien : c'est une réservation, pas un plafond |
| **limits** | le **plafond** appliqué à l'exécution | CPU : **ralenti** (*throttling*). Mémoire : **tué** (`OOMKilled`) |

> 🎯 **Avant de lancer la commande suivante, prédis :** Kubernetes range chaque pod dans une classe de qualité de service : `Guaranteed`, `Burstable` ou `BestEffort`. Dans laquelle sont les pods de l'API ? Et ceux de la vitrine ?

```bash
kubectl get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Tous en **`Burstable`** : ils ont des requests, mais des limits **plus hautes**. La classe se déduit des ressources de tous les conteneurs du pod :

| Classe | Condition | Sous pression mémoire du nœud |
|---|---|---|
| `Guaranteed` | requests **=** limits, CPU et mémoire, pour chaque conteneur | évincé en dernier |
| `Burstable` | au moins une request ou une limit | évincé selon ce qu'il consomme au-delà de ses requests |
| `BestEffort` | aucune request ni limit | évincé en premier |

Pour passer l'API en `Guaranteed`, il faudrait des requests égales aux limits (100m/100m ou 500m/500m). La bonne pratique : `Guaranteed` pour une base de données, `Burstable` avec des requests **réalistes** pour le reste. Et jamais de `BestEffort` en production : c'est d'ailleurs pourquoi tous les manifestes de ce dépôt ont leurs ressources.
</details>

## Étape 2 — Le durcissement, enfin expliqué

Depuis le TP01, chaque manifeste porte le même bloc marqué « ne pas modifier ». Voici ce qu'il fait :

| Champ | Effet | Ce qu'il empêche |
|---|---|---|
| `runAsNonRoot: true` | le kubelet **refuse de démarrer** un conteneur qui tournerait en root | qu'une image mal construite tourne en root sans qu'on le sache |
| `runAsUser` / `runAsGroup` | l'identité du processus (ici `65532`, l'utilisateur des images *distroless*) | de dépendre de l'utilisateur prévu, ou non, par l'image |
| `allowPrivilegeEscalation: false` | aucun processus ne peut gagner plus de droits que son parent (`setuid`, `sudo`) | l'escalade après une intrusion |
| `readOnlyRootFilesystem: true` | le système de fichiers du conteneur est en **lecture seule** | qu'un attaquant dépose un outil ou modifie le code ; les écritures légitimes vont dans des volumes (TP05) |
| `capabilities: drop: ["ALL"]` | retire tous les privilèges noyau restants (ouvrir un port < 1024, changer le propriétaire d'un fichier…) | l'usage de ces privilèges, dont l'application n'a pas besoin |
| `seccompProfile: RuntimeDefault` | filtre les appels système dangereux | l'exploitation de failles du noyau |
| `resources` | voir l'étape 1 | qu'un conteneur affame ses voisins |

Ces règles sont contrôlées par `trivy config` (0 alerte HIGH/CRITICAL sur tout le dépôt, vérifié par la CI).

> 🎯 **Avant de lancer la commande suivante, prédis :** `pannes/racine.yaml` lance l'image `busybox` (qui démarre en root par défaut) avec `runAsNonRoot: true`, mais **sans** `runAsUser`. Que va-t-il se passer : le pod tourne en root, il tourne sous un autre utilisateur, ou il ne démarre pas ?

```bash
kubectl apply -f pannes/racine.yaml
kubectl get pod racine
kubectl describe pod racine | grep -A2 Warning
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Il **ne démarre pas** : `CreateContainerConfigError`, avec `container has runAsNonRoot and image will run as root`. `runAsNonRoot` ne **change** pas l'utilisateur, il **vérifie** : avant de lancer le conteneur, le kubelet lit l'utilisateur qu'il obtiendra et refuse si c'est root. Pour corriger, ajoutez un `runAsUser` non nul (par exemple `65532`), ou mieux, utilisez une image prévue pour tourner sans root.

```bash
kubectl delete pod racine
```
</details>

## Étape 3 — Diagnostiquer deux pannes de ressources

Deux équipes signalent un problème. Appliquez leurs manifestes **sans les lire** :

```bash
kubectl apply -f pannes/export.yaml -f pannes/inventaire.yaml
kubectl get pods -l 'app in (export,inventaire)' --watch     # Ctrl-C au bout d'une minute
```

Menez l'enquête avec `kubectl describe pod` (sections **Last State** et **Events**) et `kubectl logs`.

> ❓ **Questions** :
> 1. `export` redémarre sans arrêt. Que disent `Reason` et `Exit Code` ? Pourquoi `kubectl logs --previous` ne donne-t-il aucune ligne de journal ?
> 2. `inventaire` ne démarre jamais. Dans quel état est-il, et quel composant de Kubernetes se plaint ?
> 3. Pour chacun : faut-il modifier l'application, le manifeste, ou le cluster ?

<details>
<summary>💡 Les réponses</summary>

1. **`OOMKilled`, code 137** (128 + 9 : le signal `SIGKILL`). Le conteneur demande 100 Mo de mémoire au démarrage (`MEMORY_BALLAST_MB`) pour une limite de 64 Mi : le noyau le tue **avant** qu'il ait écrit la moindre ligne. Correction : une limite adaptée au vrai besoin, ou une application plus sobre. Ne pas confondre avec une **éviction** (`Evicted`), où c'est le **nœud** qui manque de mémoire.
2. **`Pending`**, et c'est le **scheduler** qui se plaint : `0/1 nodes are available: 1 Insufficient cpu`. La request (64 cœurs) dépasse ce qu'un nœud peut offrir. Pas de journal : le conteneur n'a jamais été créé. Correction : une request réaliste, ou des nœuds plus gros.
3. Les deux se corrigent dans le **manifeste**, après avoir mesuré la consommation réelle (étape 4).

```bash
kubectl delete -f pannes/export.yaml -f pannes/inventaire.yaml
```
</details>

## Étape 4 — Mesurer : metrics-server

Le HPA a besoin de **mesures**. Sur minikube, metrics-server est un addon :

```bash
minikube addons enable metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io      # AVAILABLE passe à True au bout d'une minute environ
kubectl top nodes
kubectl top pods --sort-by=cpu
```

metrics-server interroge le kubelet de chaque nœud et ne garde que la **dernière** mesure. Ce n'est pas un outil de supervision : ni historique, ni alertes (c'est le rôle de Prometheus, TP13).

## Étape 5 — L'autoscaling horizontal

Complétez `starter/hpa.yaml` (`# TODO 6` à `11`), puis :

```bash
kubectl apply -f starter/hpa.yaml
kubectl get hpa api --watch          # Ctrl-C quand TARGETS affiche un pourcentage
```

`TARGETS` compare la consommation moyenne à la cible, **en pourcentage de la request** : sans request CPU, le HPA ne peut rien calculer (`<unknown>`). Toutes les 15 secondes, il applique : `réplicas souhaités = réplicas actuels × consommation mesurée / cible`.

Lancez la charge fournie (quatre pods qui appellent `/api/charge` pendant 3 minutes) et regardez le HPA réagir :

```bash
kubectl apply -f outils/charge.yaml
kubectl get hpa api --watch
```

> 🎯 **Avant de lancer la commande suivante, prédis :** pendant que le HPA a monté l'API à 6 réplicas, un collègue réapplique `starter/api.yaml`, qui contient toujours `replicas: 2` (`# TODO 5`). Que devient l'API ?

```bash
kubectl apply -f starter/api.yaml
kubectl get deployment api --watch      # Ctrl-C après 30 secondes
kubectl get events --field-selector involvedObject.name=api | tail -4
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Elle **tombe à 2 réplicas sur-le-champ** : `kubectl apply` impose la valeur du fichier, et **4 pods sont arrêtés** en pleine charge. Une quinzaine de secondes plus tard, le HPA mesure la surcharge et remonte à 6. Les événements montrent l'aller-retour : `Scaled down … from 6 to 2`, puis `Scaled up … from 2 to 6`. Avec un déploiement automatisé qui réapplique les manifestes, ce yoyo se répéterait à chaque livraison.

La règle : **quand un HPA pilote un Deployment, le manifeste ne fixe plus `replicas`**. Faites le `# TODO 5` maintenant : supprimez la ligne.

⚠️ Mais ne réappliquez pas tout de suite. `kubectl apply` compare le fichier à la **dernière version appliquée** (annotation `kubectl.kubernetes.io/last-applied-configuration`) : un champ qui y figurait et qui disparaît du fichier est **supprimé** de l'objet, et `replicas` retombe à sa valeur par défaut, **1**. Retirez d'abord le champ de cette mémoire, puis appliquez :

```bash
kubectl apply set-last-applied -f starter/api.yaml   # l'annotation oublie « replicas », l'objet ne change pas
kubectl apply -f starter/api.yaml                    # le nombre de réplicas ne bouge plus
```
</details>

## Étape 6 — La descente

Laissez la charge se terminer (`kubectl get job charge` : `Complete`), et continuez d'observer `kubectl get hpa api --watch`.

> ❓ **Question** : le HPA monte en quelques dizaines de secondes. Combien de temps met-il à redescendre à 2 ? Quel champ de `hpa.yaml` règle ce délai, et pourquoi est-il plus long par défaut (5 minutes) en production ?

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` attend metrics-server, puis lance lui-même la charge : comptez 4 minutes.

---

## 💡 Indices

<details>
<summary><code>TARGETS</code> reste à <code>&lt;unknown&gt;</code></summary>

Trois causes possibles : metrics-server n'est pas prêt (`kubectl get apiservice v1beta1.metrics.k8s.io`, attendez une minute après l'avoir activé) ; les pods viennent de démarrer (la première mesure prend jusqu'à une minute) ; ou il manque la **request CPU** dans le Deployment. `kubectl describe hpa api` donne la raison exacte dans ses conditions.
</details>

<details>
<summary>Le HPA ne dépasse pas quelques réplicas, ou de nouveaux pods restent <code>Pending</code></summary>

Le HPA ajoute des **pods**, pas des **nœuds**. Si le nœud n'a plus de CPU à réserver (`kubectl describe node | grep -A6 "Allocated resources"`), les nouveaux pods attendent. Sur un vrai cluster, c'est le rôle du *Cluster Autoscaler* d'ajouter des nœuds.
</details>

<details>
<summary><code>kubectl top</code> répond « Metrics API not available »</summary>

metrics-server n'est pas installé ou pas encore prêt : refaites l'étape 4.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Requests et limits** : https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
- **Classes QoS** : https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/
- **HorizontalPodAutoscaler** : https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- **Contexte de sécurité** : https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- **Pod Security Standards** (le niveau `restricted` correspond au bloc de durcissement) : https://kubernetes.io/docs/concepts/security/pod-security-standards/

---

## 🚀 Pour aller plus loin

1. **Le throttling CPU.** Passez la limite CPU de l'API à `100m`, relancez la charge : que deviennent les temps de réponse de `/api/charge?ms=200` ? Et le pourcentage affiché par le HPA ?
2. **Autoscaler sur la mémoire.** Ajoutez une seconde métrique `memory` au HPA. Pourquoi est-ce rarement une bonne idée pour une application qui ne rend jamais sa mémoire ?
3. **Une montée plus prudente.** Avec `spec.behavior.scaleUp.policies`, limitez la montée à **un pod par minute**. Observez la différence avec la charge.
4. **Le niveau `restricted`.** Étiquetez le namespace `pod-security.kubernetes.io/enforce=restricted`, puis lancez un pod sans aucun durcissement : `kubectl run essai --image=busybox:1.38.0 -- sleep 60`. Qui refuse le pod cette fois, et à quel moment ? Et `pannes/racine.yaml`, est-il refusé au même endroit ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
