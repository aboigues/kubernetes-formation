# TP14 — Projet final : la mise en production de Télémarché

> Durée estimée : 1 h 30 à 2 h · Namespace de travail : `telemarche`
> Prérequis : TP03 (diagnostic), TP04 (Job), TP05 (configuration et stockage). Pour la suite (« Pour aller plus loin ») : TP06 à TP13.
> Faites place nette : `kubectl delete deployment,service,statefulset,job,cronjob,daemonset,hpa,pvc --all -n telemarche`

## 🎬 Le contexte

Vendredi, 17 h. L'équipe a préparé la mise en production complète de Télémarché : la vitrine, l'API, PostgreSQL avec son volume, la configuration, la migration du schéma. Le responsable a appliqué les manifestes, constaté que « ça ne marche pas », et il est parti en week-end.

Vous êtes d'astreinte. **Cinq incidents** se cachent dans `starter/`. Certains se voient tout de suite, d'autres n'apparaissent qu'une fois les précédents corrigés. Votre mission : remettre la boutique en service **et** rendre un rapport qui permette à l'équipe de ne plus refaire ces erreurs.

```
   web ──> Service api ──> Deployment api (3)  <── ConfigMap api-config
                                 │            <── Secret db-credentials
                                 ▼
   Job migration ──────> Service db ──> StatefulSet db ──> PVC donnees-db-0
```

## 🎯 Objectif vérifiable

Télémarché fonctionne de bout en bout : une commande passée par la vitrine est enregistrée dans PostgreSQL, puis relue. Et `starter/rapport.md` décrit les cinq incidents : symptôme, commande de diagnostic, cause, correction. `./verify.sh` contrôle les deux, et désigne l'incident en cause quand un contrôle échoue.

## 📏 Les règles du jeu

1. **Ne lisez pas `solution/`**, et ne comparez pas les fichiers : en astreinte, il n'y a pas de corrigé. Diagnostiquez avec `kubectl`.
2. **Un incident à la fois** : observez, formulez une hypothèse, corrigez **dans le fichier** (pas avec `kubectl edit` : le fichier est la source de vérité), réappliquez, vérifiez.
3. **Notez au fur et à mesure** dans `rapport.md`. Un incident non documenté reviendra.

---

## Démarrer

```bash
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_USER=telemarche \
  --from-literal=POSTGRES_PASSWORD='un-mot-de-passe-fictif'
kubectl apply -f starter/
kubectl get all,pvc
```

## La méthode de l'exploitant

Toujours dans cet ordre, du plus large au plus précis :

| Question | Commande |
|---|---|
| Qu'est-ce qui ne va pas ? | `kubectl get pods,pvc,jobs` : colonnes `STATUS`, `READY`, `RESTARTS` |
| Que dit Kubernetes ? | `kubectl describe <objet>` : la section **Events**, en bas |
| Que dit l'application ? | `kubectl logs <pod>` et `kubectl logs <pod> --previous` |
| Le trafic arrive-t-il ? | `kubectl get endpointslices -l kubernetes.io/service-name=<service>` |
| Tout le namespace, dans l'ordre | `kubectl get events --sort-by=.lastTimestamp` |

Avant de corriger, demandez-vous : **cette modification est-elle acceptée telle quelle**, ou faut-il recréer l'objet ? Certains champs ne se modifient pas une fois l'objet créé : Kubernetes vous le dira, lisez son message.

---

## 💡 Indices progressifs

Ouvrez un indice seulement après avoir cherché. Chacun a deux niveaux : une piste, puis la nature du problème. La correction exacte reste à trouver.

<details>
<summary>La base reste <code>Pending</code></summary>

**Piste** : un pod `Pending` n'a pas trouvé où s'installer. Qu'attend-il ? `kubectl describe pod db-0`, puis l'objet dont il parle.

<details>
<summary>Niveau 2</summary>

La PVC ne trouve pas de quoi se provisionner. Comparez ce qu'elle demande avec `kubectl get storageclass`. Puis lisez attentivement la réponse de `kubectl apply` à votre correction : un StatefulSet ne change pas son modèle de volume après coup. Il faudra le supprimer, **ainsi que la PVC**, puis réappliquer.
</details>
</details>

<details>
<summary>La base est en <code>CreateContainerConfigError</code></summary>

**Piste** : le conteneur n'a même pas démarré. C'est donc sa **configuration** qui pose problème, pas l'application. Les Events de `db-0` nomment l'objet en cause.

<details>
<summary>Niveau 2</summary>

Comparez ce que le StatefulSet demande au Secret avec ce que contient le Secret : `kubectl get secret db-credentials -o jsonpath='{.data}'`. Et après votre correction, si `db-0` ne bouge toujours pas : un StatefulSet ne remplace pas un pod qui n'a **jamais** été prêt. Supprimez ce pod, et le StatefulSet le recréera avec la nouvelle version.
</details>
</details>

<details>
<summary>Le Job <code>migration</code> échoue</summary>

**Piste** : `StartError` signifie que le conteneur a été créé, mais que son processus n'a pas pu démarrer. `kubectl describe pod -l app=migration` donne la raison exacte.

<details>
<summary>Niveau 2</summary>

Le message vient de l'environnement d'exécution : le programme demandé n'existe pas dans l'image. Le README de l'application (`apps/telemarche/README.md`, section « Migration ») donne le bon chemin. Comme pour le StatefulSet, le modèle de pod d'un Job ne se modifie pas : supprimez le Job, puis réappliquez-le.
</details>
</details>

<details>
<summary>Les pods de l'API restent <code>0/1</code></summary>

**Piste** : `Running` mais pas `Ready`, et aucun redémarrage : c'est la **readiness** qui échoue, pas la liveness. Avant la migration, c'est normal (« schéma absent »). Après ?

<details>
<summary>Niveau 2</summary>

Lisez le code HTTP dans les Events : `kubectl get events --field-selector reason=Unhealthy`. Un 503 veut dire « pas encore prêt », mais un 404 ? Comparez avec les points d'entrée documentés dans `apps/telemarche/README.md`.
</details>
</details>

<details>
<summary>Tout est <code>Running</code>, mais la vitrine affiche « API injoignable »</summary>

**Piste** : les pods vont bien, c'est le **chemin** jusqu'à eux qui est coupé. Le Service `api` a-t-il des pods derrière lui ?

<details>
<summary>Niveau 2</summary>

`kubectl get endpointslices -l kubernetes.io/service-name=api` : aucune adresse. Un Service trouve ses pods par son `selector`. Comparez-le avec `kubectl get pods --show-labels`.
</details>
</details>

---

## Validez

```bash
./verify.sh              # vos manifestes et votre rapport (dossier starter/)
./verify.sh solution     # (option) la référence, à ouvrir APRÈS : comparez votre rapport au sien
```

---

## 🚀 Pour aller plus loin : rendre Télémarché prêt pour la production

La boutique fonctionne, mais elle n'est pas encore robuste. Chaque point mobilise un TP :

1. **Encaisser les pics** (TP06) : requests et limits réalistes, puis un HPA sur l'API, sans `replicas` dans le manifeste.
2. **Survivre à une maintenance** (TP09) : un PodDisruptionBudget, et l'anti-affinité des pods de l'API.
3. **Cloisonner le réseau** (TP11) : seule l'API joint la base, seule la vitrine joint l'API.
4. **Publier proprement** (TP07) : une HTTPRoute `telemarche.local` à la place du Service exposé.
5. **Packager** (TP12) : transformez ces manifestes en chart, avec des values de développement et de production.
6. **Être prévenu avant les clients** (TP13) : un ServiceMonitor et une alerte qui aurait détecté **chacun** des cinq incidents de ce TP. Lesquels une alerte pouvait-elle voir, et lesquels seulement un test de bout en bout ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
