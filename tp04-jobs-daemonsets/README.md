# TP04 — DaemonSet, Job et CronJob

> Durée estimée : 45 min · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, Service). L'état de départ est fourni : `starter/00-telemarche.yaml`.
> Faites place nette : `kubectl delete deployment,service,pod --all -n telemarche`

## 🎬 Le contexte

Télémarché tourne. Trois demandes arrivent de l'équipe :

- **La supervision** veut un agent sur **chaque nœud** du cluster, qui vérifie que la vitrine répond depuis ce nœud — y compris sur les nœuds ajoutés plus tard.
- **Le service commercial** veut passer un lot de **5 commandes de test**, pas plus, sans saturer l'API.
- **La direction** veut un **rapport** des commandes toutes les 5 minutes.

Aucun de ces besoins ne se traite avec un Deployment, qui maintient N pods identiques **pour toujours**. Kubernetes a un contrôleur pour chacun.

## 🎯 Objectif vérifiable

Un DaemonSet `sonde` (un pod par nœud, qui connaît son nœud), un Job `commandes` (5 réussites, 2 à la fois) et un CronJob `rapport` (toutes les 5 minutes, sans chevauchement). `./verify.sh` les déploie, attend la fin du Job et **déclenche** un rapport sans attendre la planification.

---

## Étape 1 — L'état de départ

```bash
kubectl apply -f starter/00-telemarche.yaml
kubectl rollout status deployment/api
```

## Étape 2 — Un pod par nœud : le DaemonSet

Vous en utilisez déjà sans le savoir :

```bash
kubectl get daemonsets -n kube-system
```

`kube-proxy` et le greffon réseau (`kindnet` sous minikube) doivent tourner sur **chaque** nœud : c'est le rôle d'un DaemonSet.

Complétez `starter/sonde.yaml` (`# TODO 1` et `2`). La sonde a besoin de connaître le nom de son nœud : on le lui passe par l'**API descendante** (*downward API*), qui expose des champs du pod lui-même en variables d'environnement.

Pour le `# TODO 2`, ne cherchez pas au hasard : `kubectl explain` liste les champs que l'API descendante sait exposer.

```bash
kubectl explain pod.spec.containers.env.valueFrom.fieldRef
```

Choisissez, dans la liste, celui qui contient le nom du nœud.

```bash
kubectl apply -f starter/sonde.yaml
kubectl get daemonset sonde
kubectl get pods -l app=sonde -o wide
kubectl logs -l app=sonde --tail=3
```

> ❓ **Question** : le manifeste d'un DaemonSet n'a pas de champ `replicas`. Pourquoi ?

## Étape 3 — Un lot, puis s'arrêter : le Job

Complétez `starter/commandes.yaml` (`# TODO 3` à `6`), puis observez les pods apparaître **deux par deux** :

```bash
kubectl apply -f starter/commandes.yaml
kubectl get pods -l app=commandes --watch      # Ctrl-C quand le Job est terminé
kubectl get job commandes
```

Les pods terminés restent visibles en `Completed` : on peut encore lire leurs journaux.

```bash
kubectl logs job/commandes       # le journal d'un des pods du Job
```

> ℹ️ Chaque pod réessaie sa requête quelques secondes si l'API n'est pas encore prête (`curl --retry`) : un traitement par lots doit tolérer qu'une dépendance démarre plus lentement que lui.

> ❓ **Question** : `ttlSecondsAfterFinished: 600`. Que deviendra le Job, et ses pods, dans 10 minutes ? Pourquoi est-ce utile sur un cluster qui lance des centaines de Jobs par jour ?

## Étape 4 — Planifier : le CronJob

Complétez `starter/rapport.yaml` (`# TODO 7` à `9`) et appliquez-le. Plutôt que d'attendre 5 minutes, déclenchez-le à la main :

```bash
kubectl apply -f starter/rapport.yaml
kubectl create job rapport-manuel --from=cronjob/rapport
kubectl logs job/rapport-manuel --follow
```

> 🎯 **Avant de lancer les commandes suivantes, prédis :** le Job `commandes` a passé 5 commandes. Combien le rapport en compte-t-il ? Et si vous le lancez trois fois ?

```bash
for i in 1 2 3; do kubectl create job rapport-$i --from=cronjob/rapport; done
sleep 10; for i in 1 2 3; do kubectl logs job/rapport-$i; done
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Rarement 5, et pas toujours le même nombre. L'API stocke ses commandes **en mémoire, dans chaque pod** : les 5 commandes ont été réparties entre les 3 pods par le Service, et chaque rapport interroge **un seul** pod — celui que le Service a choisi pour cette requête. Le rapport l'affiche : « enregistrée(s) par : api-… ».

C'est le défaut de toute application qui garde son état dans ses pods : chaque réplica a sa vérité, et tout disparaît au redémarrage (`kubectl rollout restart deployment/api`, puis relancez un rapport). Le TP05 le corrige avec une vraie base de données.
</details>

Faites le ménage : `kubectl delete job rapport-manuel rapport-1 rapport-2 rapport-3`.

## Étape 5 — Diagnostiquer un Job qui échoue

Un collègue a lancé un import qui « n'en finit pas d'échouer ». Appliquez-le **sans le lire** :

```bash
kubectl apply -f pannes/import.yaml
kubectl get job import --watch      # Ctrl-C quand STATUS passe à Failed
```

Menez l'enquête : `kubectl get pods -l app=import`, `kubectl logs <pod>`, `kubectl describe job import` (section **Events**).

> ❓ **Question** : combien de pods le Job a-t-il créés avant d'abandonner ? Quel champ fixe ce nombre ? Pourquoi les intervalles entre deux tentatives s'allongent-ils ?

## Étape 6 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>« spec.template.spec.restartPolicy: Required value: valid values: "OnFailure", "Never" »</summary>

Un Job ne peut pas utiliser `Always` (le défaut des pods) : un pod qui redémarrerait toujours ne se terminerait jamais. Les valeurs admises sont `Never` (le Job crée un nouveau pod à chaque échec) et `OnFailure` (le kubelet relance le conteneur dans le même pod).
</details>

<details>
<summary>« did not find expected alphabetic or numeric character » ou « expected exactly 5 fields »</summary>

`schedule` suit la syntaxe cron à 5 champs : minute, heure, jour du mois, mois, jour de la semaine. « Toutes les 5 minutes » s'écrit `"*/5 * * * *"` — **entre guillemets**, sinon le `*` initial est pris pour un alias YAML et le fichier ne se lit même pas. L'heure est celle du **contrôleur** (UTC par défaut), réglable par `spec.timeZone`.
</details>

<details>
<summary>Diagnostic de l'import</summary>

Les journaux disent `curl: (22) The requested URL returned error: 404` : le produit `42` n'existe pas (`/api/products` en liste 6). Le Job a créé `backoffLimit + 1 = 3` pods, avec un délai croissant entre les tentatives (10 s, 20 s, 40 s… plafonné à 6 minutes), puis s'est déclaré `Failed` (`BackoffLimitExceeded`). Réessayer ne sert à rien quand l'erreur est dans la donnée : corrigez le `product_id`, supprimez le Job (`kubectl delete job import` — un Job terminé ne se relance pas) et réappliquez.
</details>

---

## 📖 Où chercher (documentation officielle)

- **DaemonSet** : https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
- **Job** (dont `completions`, `parallelism`, `backoffLimit`) : https://kubernetes.io/docs/concepts/workloads/controllers/job/
- **CronJob** : https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
- **API descendante (downward API)** : https://kubernetes.io/docs/concepts/workloads/pods/downward-api/

---

## 🚀 Pour aller plus loin

1. **Un nœud de plus.** `minikube node add`, puis `kubectl get pods -o wide` : la sonde s'est installée seule sur le nouveau nœud.
   > 🎯 Et les 3 pods de l'API, se sont-ils répartis sur le nouveau nœud ? (Réponse : non. Un Deployment ne déplace jamais des pods qui fonctionnent ; seuls les **nouveaux** pods profitent du nœud. Vérifiez, puis retirez le nœud : `minikube node delete <nom>`.)
2. **Le control plane.** Sur un cluster kubeadm, le nœud de control plane porte une *taint* `node-role.kubernetes.io/control-plane:NoSchedule` : la sonde n'y tournera pas sans `tolerations`. Pourquoi est-ce souvent ce que l'on veut… et pas pour un agent de journaux ? (Taints : TP09.)
3. **Suspendre.** `kubectl patch cronjob rapport -p '{"spec":{"suspend":true}}'` : à quoi cela sert-il pendant une maintenance ?
4. **Jobs indexés.** Avec `completionMode: Indexed`, chaque pod reçoit `JOB_COMPLETION_INDEX` (0 à 4) : de quoi découper un gros traitement en tranches.

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
