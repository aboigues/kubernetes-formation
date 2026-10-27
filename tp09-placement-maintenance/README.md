# TP09 — Placement et maintenance

> Durée estimée : 1 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, probes). Un poste qui supporte **3 nœuds minikube** (4 processeurs et 6 Go de mémoire libres conseillés).

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

La dernière ligne vous replace dans `telemarche`. Supprimer le namespace ne change pas votre contexte, mais celui-ci a pu changer depuis le TP01 : un cluster recréé, ou un autre cluster sélectionné, repart sur `default`. Vos `kubectl apply` y partiraient alors **sans le moindre avertissement**, et l'erreur n'apparaîtrait que plus tard, loin de sa cause. Vérifiez : `kubectl config view --minify -o jsonpath='{..namespace}'; echo` doit afficher `telemarche` (une ligne vide veut dire `default`).

L'état de départ est fourni : `starter/00-web.yaml`, appliqué à l'étape 2. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Télémarché grandit : le cluster passe à **trois nœuds**. Trois questions se posent aussitôt à l'exploitant :

1. **Où vont les pods ?** Trois réplicas de l'API sur le même nœud, c'est une seule panne pour tout perdre.
2. **Comment réserver un nœud ?** Le service de stock a besoin du nœud au disque rapide, et ce nœud ne doit servir qu'à lui.
3. **Comment faire la maintenance d'un nœud** (mise à jour du système, redémarrage) **sans couper la boutique ?**

```
   minikube             minikube-m02           minikube-m03   disque=ssd, taint dedie=stock:NoSchedule
   ┌──────────┐         ┌──────────┐           ┌──────────┐
   │ api      │         │ api      │           │ stock    │   ← toleration + nodeSelector
   │ web      │         │ api  web │           │          │
   └──────────┘         └──────────┘           └──────────┘
        ▲ anti-affinité : les pods d'API s'évitent      PDB api : minAvailable 2
```

## 🎯 Objectif vérifiable

L'API répartie sur deux nœuds, le stock seul sur le nœud réservé, et un PodDisruptionBudget qui garde toujours 2 pods d'API disponibles. `./verify.sh` **draine pour de vrai** le nœud qui porte le plus de pods d'API, interroge l'API pendant toute l'opération, et exige **zéro requête en échec** et **jamais moins de 2 pods prêts**.

---

## Étape 1 — Trois nœuds

```bash
minikube node add          # minikube-m02
minikube node add          # minikube-m03
kubectl get nodes -o wide
kubectl describe node minikube | grep -A3 Taints
```

> Sous minikube, le nœud `minikube` est à la fois control plane **et** nœud de travail : il n'a pas de taint. Sur un cluster installé avec kubeadm (TP10), le control plane porte `node-role.kubernetes.io/control-plane:NoSchedule` et ne reçoit pas les applications.

Le script `./prerequis.sh` fait les étapes 1 et 3, pour la CI ou pour repartir d'un cluster neuf.

## Étape 2 — Répartir l'API : l'anti-affinité

Complétez `starter/api.yaml` (`# TODO 1` et `2`), puis :

```bash
kubectl apply -f starter/00-web.yaml -f starter/api.yaml
kubectl get pods -l app=api -o wide          # colonne NODE
```

La règle dit : « évite, si possible, un nœud (`topologyKey: kubernetes.io/hostname`) où tourne déjà un pod `app=api` ». Elle est **préférée** (`preferred…`) et non **obligatoire** (`required…`) : avec 3 réplicas et 2 nœuds disponibles (le troisième sera bientôt réservé), une règle obligatoire laisserait le troisième pod `Pending`.

`IgnoredDuringExecution` : la règle compte au **placement** seulement. Un pod déjà en place n'est jamais déplacé parce que la situation a changé.

## Étape 3 — Réserver un nœud : label et taint

```bash
kubectl label node minikube-m03 disque=ssd
kubectl taint node minikube-m03 dedie=stock:NoSchedule
kubectl get nodes -L disque
```

Le **label** décrit le nœud (on peut le choisir). Le **taint** le protège : plus aucun pod ne peut y être placé, sauf ceux qui le **tolèrent**.

Complétez `starter/stock.yaml` (`# TODO 3` à `6`) : une toleration pour le taint, un `nodeSelector` pour le label.

> 🎯 **Avant de lancer la commande suivante, prédis :** un collègue propose de garder **seulement** la toleration (sans `nodeSelector`), puis, au contraire, **seulement** le `nodeSelector` (sans toleration). Où iraient les pods de stock dans chaque cas ?

```bash
kubectl apply -f starter/stock.yaml
kubectl get pods -l app=stock -o wide
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

- **Toleration seule** : les pods peuvent aller **n'importe où**, `minikube-m03` compris. Une toleration **autorise** un nœud, elle n'y **envoie** pas. Avec 6 réplicas, on en trouve sur les trois nœuds.
- **nodeSelector seul** : le pod reste **`Pending`**. Le seul nœud qui a le label est protégé par un taint qu'il ne tolère pas : `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match Pod's node affinity/selector`.

D'où la règle pour **dédier** des nœuds : un taint (pour écarter les autres) **et** une affinité ou un `nodeSelector` (pour attirer les siens). Les deux dans le même manifeste, comme dans `stock.yaml`.
</details>

## Étape 4 — Le PodDisruptionBudget

Complétez `starter/pdb.yaml` (`# TODO 7` à `9`), puis :

```bash
kubectl apply -f starter/pdb.yaml
kubectl get pdb api           # ALLOWED DISRUPTIONS : 1
```

Un PDB limite les **interruptions volontaires** : le drain d'un nœud, la mise à jour d'un cluster. Il ne protège **pas** d'une panne, car un nœud qui s'éteint ne demande la permission à personne.

## Étape 5 — Drainer un nœud

Dans un **second terminal**, regardez l'API pendant toute l'opération :

```bash
kubectl get pods -l app=api -o wide --watch
```

Puis, dans le premier, prenez le nœud qui porte deux pods d'API (adaptez le nom) :

```bash
kubectl cordon minikube-m02          # plus aucun nouveau pod sur ce nœud
kubectl get nodes                    # STATUS : Ready,SchedulingDisabled
kubectl drain minikube-m02 --ignore-daemonsets --delete-emptydir-data
```

Observez l'ordre : un pod d'API est expulsé, son remplaçant démarre **ailleurs**, et c'est seulement quand il est prêt que le second est expulsé. Le PDB n'autorise qu'**une** interruption à la fois. `--ignore-daemonsets` : les pods des DaemonSets (réseau, `kube-proxy`) restent, puisqu'ils seraient recréés sur place.

```bash
# … la maintenance du nœud aurait lieu ici …
kubectl uncordon minikube-m02
kubectl get pods -l app=api -o wide
```

> ❓ **Question** : après `uncordon`, les pods d'API reviennent-ils sur `minikube-m02` ? Pourquoi ? Que faudrait-il faire pour rééquilibrer ? (Indice : `kubectl rollout restart`.)

## Étape 6 — Deux drains qui bloquent

> 🎯 **Avant de lancer les commandes suivantes, prédis :** un collègue « renforce » le PDB à `minAvailable: 3`, pour 3 réplicas. Que fait le drain ?

```bash
kubectl patch pdb api --type=merge -p '{"spec":{"minAvailable":3}}'
kubectl get pdb api
kubectl drain minikube-m02 --ignore-daemonsets --delete-emptydir-data --timeout=30s
kubectl get nodes
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Il **attend indéfiniment** : `ALLOWED DISRUPTIONS` vaut `0`, chaque expulsion est refusée (`Cannot evict pod as it would violate the pod's disruption budget`) et réessayée toutes les 5 secondes, jusqu'au `--timeout`. Un PDB égal au nombre de réplicas interdit **toute** maintenance. Et remarquez : après l'échec, le nœud reste **`SchedulingDisabled`**. Un drain raté ne défait pas le `cordon`.

```bash
kubectl uncordon minikube-m02
kubectl patch pdb api --type=merge -p '{"spec":{"minAvailable":2}}'
```
</details>

Second cas : quelqu'un a lancé un pod de dépannage **sans contrôleur**, directement sur ce nœud :

```bash
kubectl run debug --image=busybox:1.38.0 --overrides='{"spec":{"nodeName":"minikube-m02"}}' -- sleep 3600
kubectl drain minikube-m02 --ignore-daemonsets --delete-emptydir-data --timeout=30s
```

> ❓ **Question** : que répond le drain, et pourquoi refuse-t-il ce pod alors qu'il expulse sans hésiter ceux de l'API ? Que ferait `--force`, et qu'adviendrait-il du pod `debug` ? Terminez par `kubectl uncordon minikube-m02` et `kubectl delete pod debug`.

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

⚠️ `verify.sh` **draine réellement** un nœud de votre cluster (tous ses pods, y compris ceux du namespace `telemarche`), puis le remet en service, même en cas d'échec.

Puis revenez à un seul nœud : les deux nœuds de plus consomment de la mémoire, et `minikube-m03` garde sa taint.

```bash
minikube node delete minikube-m03 && minikube node delete minikube-m02
kubectl get nodes                # un seul nœud : minikube
```

---

## 💡 Indices

<details>
<summary>Les 3 pods d'API sont sur le même nœud</summary>

L'anti-affinité est examinée au **placement** : si les pods existaient avant la règle, ou si un seul nœud était disponible à ce moment-là, ils restent où ils sont. `kubectl rollout restart deployment api` les recrée, et donc les replace.
</details>

<details>
<summary>Le pod de stock reste <code>Pending</code></summary>

`kubectl describe pod -l app=stock`, section **Events**. `untolerated taint` : la toleration ne correspond pas au taint, alors comparez clé, valeur et effet avec `kubectl describe node minikube-m03 | grep Taints`. `didn't match Pod's node affinity/selector` : le label manque (`kubectl get nodes -L disque`).
</details>

<details>
<summary><code>verify.sh</code> s'arrête : « Il faut 3 nœuds… »</summary>

Refaites l'étape 1 et l'étape 3, ou lancez `./prerequis.sh`.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Placer les pods sur les nœuds** (nodeSelector, affinités) : https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
- **Taints et tolerations** : https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- **Topology spread constraints** : https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
- **Drainer un nœud** : https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
- **PodDisruptionBudget** : https://kubernetes.io/docs/tasks/run-application/configure-pdb/

---

## 🚀 Pour aller plus loin

1. **Une répartition stricte.** Remplacez l'anti-affinité par une `topologySpreadConstraints` (`maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`). Passez à 4 réplicas : comment se répartissent-ils ? Et à 5, si un nœud est cordonné ?
2. **L'effet `NoExecute`.** Posez `kubectl taint node minikube-m02 panne=oui:NoExecute`. Que deviennent les pods déjà présents ? Ajoutez au stock une toleration avec `tolerationSeconds: 30` : que se passe-t-il au bout de 30 s ?
3. **`maxUnavailable` plutôt que `minAvailable`.** Pourquoi `maxUnavailable: 1` est-il souvent préférable quand un HPA (TP06) fait varier le nombre de réplicas ?
4. **Un PDB pour la base.** Pour un StatefulSet à une seule instance (le `db` du TP05), quel PDB choisir, et quelle conséquence a-t-il sur la maintenance ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
