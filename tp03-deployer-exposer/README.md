# TP03 — Déployer et exposer

> Durée estimée : 2 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP01 et TP02.

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

La dernière ligne vous replace dans `telemarche`. Supprimer le namespace ne change pas votre contexte, mais celui-ci a pu changer depuis le TP01 : un cluster recréé, ou un autre cluster sélectionné, repart sur `default`. Vos `kubectl apply` y partiraient alors **sans le moindre avertissement**, et l'erreur n'apparaîtrait que plus tard, loin de sa cause. Vérifiez : `kubectl config view --minify -o jsonpath='{..namespace}'; echo` doit afficher `telemarche` (une ligne vide veut dire `default`).

## 🎬 Le contexte

La vitrine tourne, mais elle affiche « l'API ne répond pas ». L'équipe de développement livre enfin l'**API** de Télémarché, en version `1.0`, et déjà une `1.1` est annoncée pour la semaine prochaine.

Votre mission : déployer l'API et la vitrine pour qu'elles se trouvent l'une l'autre, ouvrir la vitrine aux clients, puis **passer l'API en 1.1 sans qu'un seul client ne voie d'erreur**. Et, comme toujours en exploitation, réparer ce que d'autres ont cassé.

```
          navigateur
              │ NodePort
              ▼
       Service web ──> Deployment web (2 pods)
              │ http://api
              ▼
       Service api ──> Deployment api (3 pods, probes)
```

## 🎯 Objectif vérifiable

Les Deployments `api` (3 réplicas, probes de démarrage, de disponibilité et de vie, mise à jour sans baisse de capacité) et `web` (2 réplicas), exposés par un Service `api` interne et un Service `web` `NodePort`. `./verify.sh` les déploie, vérifie que la vitrine joint l'API **par son nom DNS**, puis **rejoue lui-même** une mise à jour 1.0 → 1.1 sous trafic : **aucune requête ne doit échouer**.

---

## Étape 1 — Compléter les manifestes

Ouvrez `starter/api.yaml` et `starter/web.yaml` et complétez les `______` (`# TODO 1` à `13`). Chaque fichier contient **deux objets** séparés par `---` : le Deployment et son Service.

Pour les probes, l'API expose deux points d'entrée (voir [`apps/telemarche/README.md`](../apps/telemarche/README.md)) :

| Chemin | Répond 200 quand… |
|---|---|
| `/healthz` | le processus est vivant (démarrage terminé) |
| `/ready` | il peut recevoir du trafic : démarré, pas en cours d'arrêt, stockage joignable |

```bash
kubectl apply --dry-run=server -f starter/
kubectl apply -f starter/
kubectl get deployment,replicaset,pods,service
```

> ❓ **Question** : `kubectl get pods` montre `0/1` pendant quelques secondes pour chaque pod de l'API, puis `1/1`. Quelle probe décide de ce passage ? Que se passerait-il sans elle ?

## Étape 2 — Le Service et la découverte

Un Service ne « contient » pas de pods : il en **sélectionne**, et tient à jour la liste de leurs adresses.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=api
kubectl get pods -l app=api -o wide          # comparez les IP
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl get endpointslices -l kubernetes.io/service-name=api` : les EndpointSlices contiennent la liste des adresses d'un Service. Kubernetes leur pose ce label pour indiquer à quel Service elles appartiennent : c'est ainsi qu'on les retrouve.
- `kubectl get pods -l app=api -o wide` : les pods de l'API, avec leur IP et leur nœud (`-o wide`).
</details>

Lancez un pod d'outils jetable et cherchez l'API comme le fait la vitrine :

```bash
kubectl run debug --rm -it --restart=Never --image=busybox:1.38.0 -- sh
# dans le pod :
nslookup api
wget -qO- http://api/ready
env | grep ^API_
exit
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl run debug --image=busybox:1.38.0` : crée un pod nommé `debug`, à partir d'une image minuscule qui contient les outils réseau de base (`nslookup`, `wget`).
- `--restart=Never` : un pod simple, qui ne sera pas relancé quand sa commande se termine.
- `-it` : branche votre terminal sur le pod. `--rm` : le supprime dès que vous en sortez, rien ne reste.
- `-- sh` : la commande lancée dans le conteneur, ici un shell.
- Dans le pod : `nslookup api` interroge le DNS du cluster ; `wget -qO- URL` affiche une page sans l'enregistrer (`-q` : silencieux, `-O-` : vers l'écran) ; `env | grep ^API_` affiche les variables qui commencent par `API_`.
</details>

> ❓ **Question** : `nslookup api` affiche d'abord des `NXDOMAIN` puis trouve `api.telemarche.svc.cluster.local`. D'où viennent les noms essayés ? (indice : `cat /etc/resolv.conf` dans le pod, ligne `search`.)

Ouvrez la vitrine (`minikube service web -n telemarche --url`, dans un second terminal sous Docker Desktop ou WSL2) : elle affiche maintenant le catalogue, et le pod d'API qui a répondu.

> 🎯 **Avant de recharger la page plusieurs fois, prédis :** le nom du pod d'API affiché change-t-il à chaque rafraîchissement ? Toujours dans le même ordre ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Il change, **sans ordre fixe**. `kube-proxy` répartit chaque **nouvelle connexion** au hasard entre les pods prêts du Service — ce n'est pas un tourniquet. La vitrine ouvre une connexion par requête vers l'API (elle est réglée ainsi exprès) ; un client qui garde sa connexion ouverte (*keep-alive*) parlerait au contraire **toujours au même pod**. C'est une source classique de répartition déséquilibrée.
</details>

## Étape 3 — Envoyer du trafic, en continu

Pour juger une mise à jour, il faut des clients. Lancez-en un, **dans** le cluster :

```bash
kubectl apply -f outils/trafic.yaml
kubectl logs -f trafic
```

Chaque ligne est une requête qui traverse la vitrine jusqu'à l'API : heure, code HTTP, version, pod. Une erreur est préfixée de `!!`. Laissez ce terminal ouvert.

## Étape 4 — Mettre à jour sans coupure

Dans un autre terminal :

```bash
kubectl annotate deployment/api kubernetes.io/change-cause="version initiale 1.0"
kubectl set image deployment/api api=telemachlearning/telemarche-api:1.1
kubectl annotate deployment/api kubernetes.io/change-cause="passage en 1.1" --overwrite
kubectl rollout status deployment/api
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl annotate deployment/api kubernetes.io/change-cause="…"` : pose une **annotation** (une note libre, sans effet sur le fonctionnement) sur le Deployment. Celle-ci, `change-cause`, est reprise par `kubectl rollout history` pour dire **pourquoi** chaque révision existe. `--overwrite` : remplacer la valeur déjà posée.
- `kubectl set image deployment/api api=…:1.1` : change l'image du conteneur **nommé** `api` dans le modèle de pod. Modifier le modèle déclenche une mise à jour progressive.
- `kubectl rollout status deployment/api` : suit cette mise à jour en direct et ne rend la main qu'une fois terminée, quand tous les pods tournent la nouvelle version et sont prêts. Dans un script, la commande suivante attend donc la fin du déploiement.
- `deployment/api` : la forme `type/nom`, équivalente à `deployment api`.
</details>

Regardez le terminal `trafic` : les réponses `1.1` apparaissent, se mêlent aux `1.0`, puis les remplacent. Aucune ligne `!!`.

```bash
kubectl rollout history deployment/api
kubectl get replicaset -l app=api      # l'ancien ReplicaSet est gardé, à 0 pod
```

> 🎯 **Avant de lancer la commande suivante, prédis :** vous passez l'API à 4 réplicas. Une révision 3 apparaît-elle dans l'historique ?

```bash
kubectl scale deployment/api --replicas=4
kubectl rollout history deployment/api
kubectl scale deployment/api --replicas=3
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non. Une révision correspond à un nouveau **modèle de pod** (`spec.template`) : image, variables, probes… Le nombre de réplicas est en dehors du modèle : le changer adapte le ReplicaSet courant sans en créer un autre.
</details>

Revenez en arrière :

```bash
kubectl rollout undo deployment/api
kubectl rollout status deployment/api
```

> ❓ **Question** : `rollout undo` affiche un avertissement sur `last-applied-configuration`. Que deviendrait votre retour arrière au prochain `kubectl apply -f starter/` ? Quelle est donc la vraie façon de revenir en arrière quand on travaille en déclaratif ?

## Étape 5 — Casser pour comprendre

Retirez temporairement les **trois probes** de `starter/api.yaml` et passez `maxUnavailable` à `1`, appliquez, puis relancez une mise à jour en surveillant `trafic` :

```bash
kubectl apply -f starter/api.yaml
kubectl set image deployment/api api=telemachlearning/telemarche-api:1.1
```

Des lignes `!!` apparaissent : des pods qui démarrent encore reçoivent du trafic, et la capacité baisse pendant la bascule. **Restaurez** vos probes et `maxUnavailable: 0`, puis réappliquez.

## Étape 6 — Inspecter un pod sans shell

L'image de l'API est distroless (TP02, étape 6). Adjoignez-lui un conteneur d'outils qui partage ses processus et son réseau :

```bash
POD=$(kubectl get pod -l app=api -o jsonpath='{.items[0].metadata.name}')
kubectl debug -it "$POD" --image=busybox:1.38.0 --target=api -- sh
# dans le conteneur éphémère :
ps                                  # le processus /app/api est visible (PID 1)
wget -qO- localhost:8080/version    # même réseau que l'API
ls /proc/1/root/app                 # et même ses fichiers
exit
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `POD=$(kubectl get pod -l app=api -o jsonpath='{.items[0].metadata.name}')` : range le nom du premier pod de l'API dans la variable `POD` (même mécanique qu'au TP01, étape 4).
- `kubectl debug -it "$POD"` : ajoute au pod un **conteneur éphémère**, et vous y connecte.
- `--image=busybox:1.38.0` : l'image de ce conteneur, qui apporte les outils absents de l'image distroless.
- `--target=api` : le fait entrer dans l'espace de processus du conteneur `api`. Sans cette option, il partagerait le réseau du pod mais pas ses processus : `ps` ne montrerait pas l'API.
- `-- sh` : la commande lancée dans le conteneur éphémère.
</details>

> ℹ️ Un conteneur éphémère **ne peut pas être retiré** d'un pod : il disparaît avec lui. C'est un outil de diagnostic, pas une façon de déployer.

## Étape 7 — Diagnostiquer quatre pannes

Quatre collègues vous signalent un problème. Appliquez leurs déploiements, **sans les lire** :

```bash
kubectl apply -f pannes/
```

Pour chacun, suivez la méthode du cours — `get pods`, `describe` (section **Events**), `logs` / `logs --previous`, `get endpointslices` — et notez **le symptôme, la cause et la correction**.

| Panne | Ce que dit le collègue |
|---|---|
| `panne-1` | « le nouveau pod ne démarre jamais » |
| `panne-2` | « le pod redémarre sans arrêt » |
| `panne-3` | « le pod reste en attente » |
| `panne-4` | « les pods tournent, mais le Service ne répond pas » |

Corrigez chaque fichier, réappliquez, vérifiez, puis faites le ménage : `kubectl delete -f pannes/`.

## Étape 8 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

Puis arrêtez le client : `kubectl delete -f outils/trafic.yaml`.

---

## 💡 Indices

<details>
<summary>Le rollout reste bloqué sur « 1 out of 3 new replicas have been updated »</summary>

Le nouveau pod n'arrive jamais à `READY 1/1`. `kubectl describe pod <nouveau pod>` : une probe échoue-t-elle (`Readiness probe failed`) ? Sur quel chemin, quel port ?
</details>

<details>
<summary>La vitrine affiche « API injoignable »</summary>

Trois suspects, dans l'ordre : `API_URL` (le nom du Service, `http://api`) ; le `selector` du Service `api` (`kubectl get endpointslices -l kubernetes.io/service-name=api` doit lister 3 adresses) ; son `targetPort`.
</details>

<details>
<summary>Correction des pannes</summary>

| Panne | Symptôme | Cause | Correction |
|---|---|---|---|
| 1 | `ErrImagePull` puis `ImagePullBackOff` | l'étiquette `1.2` n'existe pas dans le registre | revenir à une version publiée (`1.1`) |
| 2 | `CrashLoopBackOff`, `Exit Code 1` | `logs --previous` : `LOG_LEVEL="bavard"` est refusé | une valeur acceptée (`info`) |
| 3 | `Pending`, `FailedScheduling … Insufficient memory` | `requests.memory: 64Gi`, plus que le nœud | une demande réaliste (`32Mi`) |
| 4 | pods `1/1`, Service sans adresse | sélecteur `app: panne4` ≠ label `app: panne-4` | aligner le sélecteur du Service |

</details>

---

## 📖 Où chercher (documentation officielle)

- **Deployments, rolling update, rollback** : https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- **Probes** : https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- **Services** : https://kubernetes.io/docs/concepts/services-networking/service/
- **DNS des Services et des pods** : https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- **Déboguer un pod (dont `kubectl debug`)** : https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/

---

## 🚀 Pour aller plus loin

1. **Déploiement progressif à la main.** `kubectl rollout pause` juste après un `set image`, observez le mélange 1.0 / 1.1 dans `trafic`, puis `kubectl rollout resume`.
2. **L'arrêt propre.** Supprimez un pod d'API pendant que `trafic` tourne : aucune erreur. Lisez ses derniers journaux (`kubectl logs <pod>` avant qu'il ne disparaisse) : que fait l'API entre la réception de `SIGTERM` et son arrêt ? À quoi sert `terminationGracePeriodSeconds` ?
3. **`Recreate`.** Passez la stratégie de `api` à `type: Recreate` et refaites une mise à jour. Combien de lignes `!!` ?
4. **Délai de progression.** Lancez `kubectl set image deployment/api api=telemachlearning/telemarche-api:1.2` avec `progressDeadlineSeconds: 60` : que dit `kubectl rollout status` au bout d'une minute ? Kubernetes revient-il en arrière tout seul ?
5. **DaemonSet, Job, CronJob.** Ce sont les autres contrôleurs du module : ils font l'objet du [TP04](../tp04-jobs-daemonsets/).

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
