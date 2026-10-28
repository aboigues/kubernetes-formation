# TP05 — Configuration et stockage

> Durée estimée : 1 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, Service, probes) et TP04 (Job).

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

La dernière ligne vous replace dans `telemarche`. Supprimer le namespace ne change pas votre contexte, mais celui-ci a pu changer depuis le TP01 : un cluster recréé, ou un autre cluster sélectionné, repart sur `default`. Vos `kubectl apply` y partiraient alors **sans le moindre avertissement**, et l'erreur n'apparaîtrait que plus tard, loin de sa cause. Vérifiez : `kubectl config view --minify -o jsonpath='{..namespace}'; echo` doit afficher `telemarche` (une ligne vide veut dire `default`).

L'état de départ est fourni : `starter/00-web.yaml`, appliqué à l'étape 3. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Le rapport du TP04 l'a montré : l'API garde ses commandes **en mémoire, dans chaque pod**. Chaque réplica a sa vérité, et tout disparaît au premier redémarrage. Inacceptable pour une boutique.

Mission du jour : donner à Télémarché une vraie base **PostgreSQL** avec un **stockage persistant**, y raccorder l'API, et sortir de l'image tout ce qui dépend de l'environnement — l'adresse de la base, le niveau de journalisation, et surtout le **mot de passe**.

```
   Service web ──> Deployment web
          │
   Service api ──> Deployment api  <── ConfigMap api-config (variables + fichier)
          │                          <── Secret db-credentials (identifiants)
   Service db (headless) ──> StatefulSet db ──> db-0 ──> PVC donnees-db-0 ──> PV
                                 ▲
                         Job migration (/app/migrate)
```

## 🎯 Objectif vérifiable

Une base `db` (StatefulSet, volume persistant par pod), un Job `migration` réussi, et l'API raccordée par une ConfigMap et un Secret. `./verify.sh` enregistre une commande, **supprime le pod de la base puis tous les pods de l'API**, et vérifie que la commande est toujours là.

> 🔐 **Aucun Secret n'est écrit dans un fichier de ce dépôt** — `verify.sh` refuse d'ailleurs tout `kind: Secret` dans vos manifestes. Un fichier finit toujours dans Git, et Git n'oublie rien.

---

## Étape 1 — Le Secret, créé à la main

```bash
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_USER=telemarche \
  --from-literal=POSTGRES_PASSWORD='un-mot-de-passe-fictif'
```

> 🎯 **Avant de lancer la commande suivante, prédis :** le mot de passe est-il chiffré dans le cluster ?

```bash
kubectl get secret db-credentials -o yaml
kubectl get secret db-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non : il est **encodé** en base64, ce qui se décode en une commande. L'encodage sert à transporter des données binaires, pas à protéger. Ce qui protège un Secret : le **RBAC** (qui a le droit `get` sur `secrets` lit tout en clair — TP08), le **chiffrement au repos** d'etcd (configuration de l'API server), un **coffre externe** (Vault, OpenBao) et l'hygiène Git (Sealed Secrets, SOPS). Alors pourquoi un objet distinct d'une ConfigMap ? Parce qu'on peut lui appliquer des droits **différents**, et que Kubernetes le traite avec plus de précaution (jamais écrit sur le disque du nœud, masqué dans `kubectl describe`).
</details>

## Étape 2 — La configuration de l'API

Complétez `starter/api-config.yaml` (`# TODO 1` à `3`). Elle contient deux sortes de clés : des **variables** (`LOG_LEVEL`, `DB_HOST`) et un **fichier** (`application.properties`).

## Étape 3 — La base : StatefulSet et volume persistant

```bash
kubectl get storageclass          # « (default) » : la classe utilisée si la PVC n'en précise pas
```

Complétez `starter/db.yaml` (`# TODO 4` à `11`). Pour `mountPath` : à partir de la version 18, l'image `postgres` range ses données sous **`/var/lib/postgresql`** (un sous-dossier par version majeure).

```bash
kubectl apply -f starter/00-web.yaml -f starter/api-config.yaml -f starter/db.yaml
kubectl rollout status statefulset/db
kubectl get statefulset,pods,pvc,pv
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl rollout status statefulset/db` : attend que le StatefulSet soit prêt, puis rend la main (vu au TP03 pour un Deployment). Un StatefulSet crée ses pods **un par un, dans l'ordre** : `db-1` n'est lancé que lorsque `db-0` est prêt.
- `kubectl get statefulset,pods,pvc,pv` : plusieurs types en une seule commande, séparés par des virgules, sans espace. Les PV n'appartiennent à aucun namespace : la commande les montre tous.
</details>

Le StatefulSet a créé la PVC `donnees-db-0` à partir de son modèle, et le provisionneur de minikube un PV pour la satisfaire. Le pod s'appelle `db-0`, pas `db-7c9d…` : son nom est **stable**, et son adresse aussi :

```bash
kubectl run dns --rm -it --restart=Never --image=busybox:1.38.0 -- \
  nslookup db-0.db.telemarche.svc.cluster.local
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `kubectl run dns` : crée un pod nommé `dns`, à partir de l'image `--image=busybox:1.38.0` (une image minuscule qui contient les outils réseau de base).
- `--restart=Never` : le pod exécute sa commande **une fois**, puis s'arrête sans être relancé.
- `-it` : branche votre terminal sur le pod (`-i` : l'entrée, `-t` : un terminal), pour voir la réponse s'afficher.
- `--rm` : supprime le pod dès qu'il a fini. Rien ne reste dans le namespace.
- `--` : la fin des options de kubectl. Ce qui suit est la commande lancée **dans** le conteneur.
- `db-0.db.telemarche.svc.cluster.local` se lit `<pod>.<service>.<namespace>.svc.<domaine du cluster>`. Ce nom par pod n'existe que parce que le Service `db` est **headless** (`clusterIP: None`) et que le StatefulSet le désigne (`serviceName: db`).
</details>

## Étape 4 — L'API, sans le schéma

Complétez `starter/api.yaml` (`# TODO 15` à `17`) : les variables viennent de la ConfigMap et du Secret (`envFrom`), le fichier `application.properties` d'un **volume** monté dans `/etc/api`.

> 🎯 **Avant de lancer la commande suivante, prédis :** vous appliquez l'API **avant** d'avoir créé les tables. Les pods vont-ils planter en boucle, rester `0/1`, ou devenir prêts ?

```bash
kubectl apply -f starter/api.yaml
sleep 20; kubectl get pods -l app=api
kubectl logs deployment/api | grep "pas prêt"
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Ils restent **`Running` mais `0/1`**, sans redémarrer. La **liveness** (`/healthz`) ne dépend pas de la base : le processus est vivant, inutile de le tuer. La **readiness** (`/ready`) vérifie que le stockage est utilisable : tant que les tables manquent, elle échoue, et le Service n'envoie **aucun trafic** à ces pods. Le journal donne la cause : `schéma absent : lancer la migration`. C'est exactement le comportement voulu — une liveness qui dépendrait de la base ferait redémarrer toute l'API en boucle à la moindre panne de PostgreSQL, sans rien réparer.
</details>

## Étape 5 — La migration : un Job

Complétez `starter/migration.yaml` (`# TODO 12` à `14`) :

```bash
kubectl apply -f starter/migration.yaml
kubectl wait --for=condition=complete job/migration --timeout=120s
kubectl logs job/migration
kubectl get pods -l app=api          # ils passent à 1/1 d'eux-mêmes
```

Ouvrez la vitrine (`minikube service web -n telemarche --url`) : le pied de page indique `stockage : postgresql`.

## Étape 6 — Les données survivent aux pods

Passez une commande, puis supprimez **tout ce qui tourne** :

```bash
kubectl port-forward service/web 8080:80 & sleep 2      # laisser au tunnel le temps de s'ouvrir
curl -s -X POST localhost:8080/api/orders -d '{"product_id": 3, "quantity": 2}'; echo
kubectl delete pod db-0
kubectl rollout restart deployment/api
kubectl rollout status statefulset/db && kubectl rollout status deployment/api
curl -s localhost:8080/api/orders; echo
kill %1
```

La commande est toujours là, et **chaque** pod d'API la voit : il n'y a plus qu'une vérité, dans la base.

> 🎯 **Avant de lancer la commande suivante, prédis :** vous supprimez le StatefulSet **entier**. La PVC et les données disparaissent-elles avec lui ?

```bash
kubectl delete statefulset db
kubectl get pvc
kubectl apply -f starter/db.yaml && kubectl rollout status statefulset/db
kubectl port-forward service/web 8080:80 & sleep 2; curl -s localhost:8080/api/orders; echo; kill %1
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non. Les PVC créées par `volumeClaimTemplates` **survivent** au StatefulSet : c'est une sécurité délibérée, pour qu'une fausse manœuvre sur le contrôleur ne détruise pas les données. Le nouveau `db-0` retrouve **sa** PVC, `donnees-db-0`, par son nom. Pour vraiment tout effacer, il faut supprimer la PVC soi-même — et alors, la politique du PV (`kubectl get pv`, colonne `RECLAIM POLICY` : `Delete` sous minikube) décide du sort du disque. Pour une base de production : une classe en `Retain`, **et** des sauvegardes.
</details>

## Étape 7 — Changer la configuration à chaud

> 🎯 **Avant de lancer les commandes suivantes, prédis :** vous passez `LOG_LEVEL` à `debug` et `cache.ttl` à `600` dans la ConfigMap, sans toucher aux pods. Lequel des deux changements l'API verra-t-elle ?

```bash
kubectl edit configmap api-config        # LOG_LEVEL: debug, et cache.ttl=600
kubectl get --raw /api/v1/namespaces/telemarche/services/http:api:80/proxy/api/info; echo
# relancez la commande ci-dessus toutes les 15 s, pendant une à deux minutes
kubectl logs deployment/api --since=1m | grep -c level=DEBUG
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Seulement **le fichier** : `cache.ttl` passe à `600` dans `/api/info` au bout d'environ une minute (le kubelet resynchronise périodiquement les volumes de ConfigMap ; l'API relit son fichier à chaque appel). Les **variables d'environnement**, elles, sont figées au démarrage du processus : aucune ligne `DEBUG` tant que les pods ne sont pas recréés.

```bash
kubectl rollout restart deployment/api
```

Après redémarrage, les lignes `DEBUG` apparaissent. D'où la règle : une ConfigMap en variables impose un `rollout restart` ; en fichier, l'application doit savoir relire sa configuration.
</details>

## Étape 8 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` crée lui-même son Secret `db-credentials`, avec un mot de passe aléatoire, dans son namespace jetable.

---

## 💡 Indices

<details>
<summary>Un pod (<code>db-0</code>, <code>migration-…</code>, <code>api-…</code>) reste en <code>CreateContainerConfigError</code></summary>

Le kubelet n'a pas pu assembler la configuration du conteneur : il ne le démarre pas, et réessaie en boucle. La cause est dans les événements :

```bash
kubectl get events --field-selector reason=Failed -o custom-columns=POD:.involvedObject.name,MESSAGE:.message
```

Le message dit `secret "…" not found` ou `configmap "…" not found`. Lisez ce nom **lettre par lettre**, puis comparez-le à ce qui existe vraiment :

```bash
kubectl get secret,configmap
kubectl config view --minify -o jsonpath='{..namespace}'; echo     # votre namespace courant
```

- **Le nom diffère** (`db-credendials`) : la faute est dans votre manifeste. Le modèle de pod d'un Job ne se modifie pas : corrigez le fichier, puis `kubectl delete job migration` et `kubectl apply -f starter/migration.yaml`.
- **L'objet manque** : vous n'êtes pas dans le bon namespace, ou l'étape 1 n'a pas été faite ici. `kubectl get jobs,pods -A | grep migration` révèle aussi un Job appliqué par erreur dans `default`. Supprimez-le.

Toujours un doute ? Lancez le pod d'enquête (ci-dessous) : il référence les mêmes objets, avec des noms écrits sans faute. S'il démarre et pas le vôtre, l'erreur est dans votre manifeste.
</details>

<details>
<summary>Le pod démarre, mais une variable manque ou la base est injoignable</summary>

`envFrom` importe les clés **présentes** dans la ConfigMap et le Secret, sans rien vérifier : une clé mal nommée (`POSTGRES_PASWORD`) ne provoque aucune erreur, la variable est juste absente. Pour voir ce qu'un pod reçoit vraiment, lancez un **pod d'enquête**. Il reçoit la configuration exactement comme l'API, dit ce qu'il a reçu (sans afficher les valeurs), teste `db:5432`, puis reste ouvert 30 minutes :

```bash
kubectl apply -f outils/enquete.yaml
kubectl logs -f enquete                 # le rapport ; Ctrl+C pour sortir
kubectl exec -it enquete -- sh          # fouiller soi-même : env | sort, nc -zv db 5432
kubectl delete -f outils/enquete.yaml
```

Pourquoi un pod à part ? L'image de l'API est distroless : on ne peut pas y ouvrir de shell (TP02). Un conteneur en `CreateContainerConfigError` n'a jamais démarré : `kubectl exec` échoue. Quant à `kubectl debug` (TP03), il ajoute bien un conteneur d'outils au pod, mais **sans** les variables du conteneur visé. Il ne montre donc pas ce que l'API reçoit.
</details>

<details>
<summary>La PVC reste <code>Pending</code></summary>

`kubectl describe pvc donnees-db-0`. Pas de StorageClass par défaut ? (`kubectl get storageclass`) Sur minikube, l'addon `storage-provisioner` doit être actif : `minikube addons list | grep storage`.
</details>

<details>
<summary>PostgreSQL redémarre en boucle : « Permission denied » ou « Read-only file system »</summary>

Le système de fichiers du conteneur est en lecture seule (`readOnlyRootFilesystem`) : PostgreSQL ne peut écrire que dans ses volumes. Vérifiez que le volume de données est monté sur `/var/lib/postgresql`, et que `/var/run/postgresql` et `/tmp` ont leur `emptyDir`. `fsGroup: 70` donne au groupe `postgres` le droit d'écrire sur le volume.
</details>

<details>
<summary>La migration échoue : « password authentication failed »</summary>

Le Secret a changé **après** la première initialisation de la base. L'image `postgres` ne lit `POSTGRES_PASSWORD` qu'à la création du volume ; ensuite, le mot de passe est celui stocké dans les données. En TP : supprimez le StatefulSet **et** la PVC `donnees-db-0`, puis recommencez.
</details>

---

## 📖 Où chercher (documentation officielle)

- **ConfigMaps** : https://kubernetes.io/docs/concepts/configuration/configmap/
- **Secrets** (et leurs limites) : https://kubernetes.io/docs/concepts/configuration/secret/
- **Bonnes pratiques pour les Secrets** : https://kubernetes.io/docs/concepts/security/secrets-good-practices/
- **Volumes persistants** : https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- **StatefulSets** : https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- **Image `postgres`** (variables, dossier de données) : https://hub.docker.com/_/postgres

---

## 🚀 Pour aller plus loin

1. **Plusieurs réplicas ?** `kubectl scale statefulset db --replicas=2` : observez l'ordre de création (`db-0` d'abord, puis `db-1`) et la nouvelle PVC. Pourquoi cela ne fait-il **pas** une base répliquée ? (Il faut un opérateur, CloudNativePG par exemple.) Revenez à 1 réplica.
2. **Une ConfigMap immuable.** Ajoutez `immutable: true` : que répond `kubectl edit` ? Pourquoi est-ce utile sur un gros cluster (indice : la charge de surveillance du kubelet) ?
3. **Le mode `ReadWriteOncePod`.** Quelle garantie apporte-t-il de plus que `ReadWriteOnce` pour une base de données ?
4. **Une sauvegarde planifiée.** Écrivez un CronJob (TP04) qui lance `pg_dump` contre `db` chaque nuit, avec l'image `postgres:18.6-alpine` et les identifiants du Secret. Où écrire le fichier pour qu'il survive au pod ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
