# TP01 — Premier cluster

> Durée estimée : 45 min · Namespace de travail : `telemarche`
> Prérequis : poste contrôlé par `./scripts/preflight.sh` (voir le [README principal](../README.md#-prérequis)).

## 🎬 Le contexte

Telemach lance **Télémarché**, sa boutique en ligne de produits frais. Les développeurs livrent des images de conteneurs ; à vous, l'équipe d'exploitation, de les faire tourner sur Kubernetes.

Premier jalon : disposer d'un cluster qui marche, comprendre ce qui tourne dedans, et y déployer la **vitrine** (`web`) — d'abord à coups de commandes, puis proprement, à partir d'un fichier.

## 🎯 Objectif vérifiable

Un cluster minikube dont le nœud et le DNS sont prêts, et une vitrine décrite **en mode déclaratif** : un Deployment `web` de 3 réplicas en version figée `1.0`, exposé par un Service `NodePort`. `./verify.sh` le contrôle.

---

## Étape 1 — Démarrer le cluster

```bash
minikube start --kubernetes-version=v1.37.1 --cpus=2 --memory=4g
kubectl get nodes -o wide
kubectl cluster-info
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `minikube start` : crée le cluster. `--kubernetes-version` fixe la version de Kubernetes (celle de la formation) ; `--cpus` et `--memory` taillent la machine qui le porte.
- `kubectl get nodes -o wide` : les nœuds, avec des colonnes en plus (`-o wide`) : adresse IP, système, runtime de conteneurs.
- `kubectl cluster-info` : l'adresse de l'API server, celle à laquelle kubectl parle.
</details>

`minikube start` crée une machine (un conteneur Docker, par défaut), y installe Kubernetes, puis écrit l'adresse du cluster et vos identifiants dans `~/.kube/config`.

```bash
kubectl config get-contexts      # les clusters connus de kubectl, et celui qui est actif (*)
kubectl version                  # versions du client ET du serveur
```

> ❓ **Question** : `kubectl version` affiche deux versions. Laquelle est celle du cluster ? Que risque-t-on si elles s'écartent de plus d'une version mineure ?

## Étape 2 — Explorer ce qui tourne

```bash
kubectl get namespaces
kubectl get pods -n kube-system -o wide
```

Vous reconnaissez les composants du cours : `etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager` (le *control plane*), et `kube-proxy`, `coredns`, le greffon réseau.

> 🎯 **Avant de lancer la commande suivante, prédis :** ces pods du control plane sont-ils créés par un Deployment, comme une application ordinaire ? Si oui, qui crée le Deployment de l'API server… alors que l'API server n'existe pas encore ?

```bash
kubectl get pods -n kube-system \
  -o custom-columns='NOM:.metadata.name,PROPRIETAIRE:.metadata.ownerReferences[0].kind'
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `-n kube-system` : le namespace des composants du cluster.
- `\` en fin de ligne : la commande continue sur la ligne suivante.
- `-o custom-columns='TITRE:chemin,…'` : un tableau à la carte. Chaque colonne s'écrit avec un titre, deux-points, puis le chemin du champ dans l'objet. Les apostrophes empêchent le shell d'interpréter les crochets.
- `.metadata.ownerReferences[0].kind` : `ownerReferences` est la liste des objets qui ont créé celui-ci. `[0]` prend le premier, `.kind` donne son type. `<none>` s'affiche quand le champ n'existe pas.
</details>

<details>
<summary>💡 Vérifie ta prédiction</summary>

`etcd`, `kube-apiserver`, `kube-scheduler` et `kube-controller-manager` ont pour propriétaire **`Node`** : ce sont des **static pods**. Le kubelet les lance lui-même à partir de fichiers posés sur le nœud (`/etc/kubernetes/manifests/`), sans rien demander à l'API — c'est ce qui permet au cluster de démarrer. Il publie ensuite un « reflet » (*mirror pod*) dans l'API pour que vous puissiez les voir.

`coredns` appartient à un `ReplicaSet` (donc à un Deployment), `kube-proxy` et le greffon réseau à un `DaemonSet` : eux sont des objets ordinaires, créés **après** le démarrage de l'API.

```bash
minikube ssh -- sudo ls /etc/kubernetes/manifests
```
</details>

*(Facultatif)* le tableau de bord : `minikube dashboard` (il reste au premier plan ; `Ctrl-C` pour le quitter).

## Étape 3 — Un namespace pour Télémarché

```bash
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
kubectl config view --minify | grep namespace
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl config set-context --current --namespace=telemarche` : modifie votre **contexte** courant, c'est-à-dire le trio cluster + utilisateur + namespace que kubectl utilise, rangé dans `~/.kube/config`. Le namespace par défaut devient `telemarche`. Rien ne change dans le cluster : c'est un réglage de **votre** kubectl.
- `kubectl config view --minify` : n'affiche que le contexte courant. `| grep namespace` ne garde que la ligne qui contient « namespace ».
</details>

Toutes vos commandes visent désormais `telemarche` sans `-n`.

## Étape 4 — Mode impératif : dire à Kubernetes quoi faire

```bash
kubectl create deployment web --image=telemachlearning/telemarche-web:1.0
kubectl get pods --watch            # Ctrl-C quand le pod est Running
kubectl scale deployment web --replicas=3
kubectl expose deployment web --type=NodePort --port=80 --target-port=8080
kubectl get deployment,replicaset,pods,service
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl create deployment web --image=…` : crée un Deployment nommé `web`, qui lance des pods à partir de cette image.
- `kubectl get pods --watch` : reste ouvert et affiche chaque changement d'état (`-w` en abrégé).
- `kubectl scale deployment web --replicas=3` : demande trois pods au lieu d'un.
- `kubectl expose deployment web --type=NodePort --port=80 --target-port=8080` : crée un Service devant les pods du Deployment. Il écoute sur le port `80` et transmet au port `8080` des conteneurs. `NodePort` ouvre en plus un port sur le nœud (voir l'étape 5).
- `kubectl get deployment,replicaset,pods,service` : plusieurs types en une commande, séparés par des virgules, sans espace.
</details>

Ouvrez la vitrine :

```bash
minikube service web -n telemarche --url
```

> ℹ️ Sous **Docker Desktop ou WSL2**, cette commande ouvre un tunnel et **reste au premier plan** : copiez l'URL affichée et ouvrez un **second terminal**. Sous Linux natif, elle rend la main tout de suite.

La page s'affiche… et annonce que **l'API ne répond pas**. C'est normal : il n'y a pas encore d'API. Elle arrive au TP03.

> 🎯 **Avant de lancer la commande suivante, prédis :** vous supprimez un des trois pods. Combien de pods `web` restera-t-il dix secondes plus tard ? Le même nom reviendra-t-il ?

```bash
kubectl delete pod "$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')"
kubectl get pods -l app=web
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `kubectl get pods -l app=web` : seulement les pods qui portent le label `app=web`.
- `-o jsonpath='{.items[0].metadata.name}'` : extrait un seul champ de la réponse, ici le nom (`.metadata.name`) du premier (`[0]`) élément de la liste (`.items`).
- `"$( … )"` : le shell exécute d'abord la commande entre parenthèses et met son résultat à la place. `kubectl delete pod` reçoit donc le nom d'un pod. Les guillemets protègent ce résultat.
</details>

<details>
<summary>💡 Vérifie ta prédiction</summary>

Toujours **trois**, dont un tout jeune (colonne `AGE`) avec un **nouveau nom**. Vous n'avez pas « redémarré » un pod : le ReplicaSet a constaté 2 pods au lieu des 3 voulus et en a **créé un autre**. C'est la boucle de réconciliation : on décrit un état, Kubernetes le maintient. Un pod n'est jamais réparé, il est **remplacé** — d'où l'importance de ne rien stocker d'important à l'intérieur.
</details>

## Étape 5 — Mode déclaratif : décrire l'état voulu

Le mode impératif est rapide mais ne laisse **aucune trace** : impossible de relire, versionner ou rejouer ce que vous avez fait. Repartez de zéro :

```bash
kubectl delete service web
kubectl delete deployment web
```

Une commande impérative sait **générer** un manifeste de départ, sans rien créer :

```bash
kubectl create deployment web --image=telemachlearning/telemarche-web:1.0 \
  --replicas=3 --port=8080 --dry-run=client -o yaml
```

Même chose pour le Service que `kubectl expose` avait créé à l'étape 4 :

```bash
kubectl create service nodeport web --tcp=80:8080 --dry-run=client -o yaml
```

<details>
<summary>🔍 Ces deux commandes, option par option</summary>

- `--dry-run=client` : kubectl construit l'objet **sans l'envoyer** au cluster : rien n'est créé.
- `-o yaml` : affiche cet objet en YAML. Vous obtenez un manifeste de départ.
- `--replicas=3 --port=8080` : se retrouvent dans `spec.replicas` et dans le `containerPort` du conteneur.
- `kubectl create service nodeport web --tcp=80:8080` : un Service de type NodePort nommé `web`. `--tcp=PORT:PORT_CIBLE` joue le rôle de `--port` et `--target-port` dans `kubectl expose`.
</details>

> ℹ️ Un **Service** donne une adresse stable devant des pods qui, eux, changent de nom et d'IP à chaque remplacement (vous l'avez vu à l'étape 4). Il choisit ses pods par leurs **labels** (`selector`). Le type **`NodePort`** ouvre en plus un port sur le nœud, ce qui permet à `minikube service` de l'atteindre depuis votre poste. Pas besoin d'en savoir plus ici : les Services sont le sujet du TP03.

Gardez ces deux sorties sous les yeux et complétez les `______` de **`starter/web.yaml`** et **`starter/web-service.yaml`** (`# TODO 1` à `8`). Le bloc `securityContext` et les `resources` sont déjà écrits : ne les touchez pas, ils seront expliqués au TP06.

Puis appliquez le **dossier** entier :

```bash
kubectl apply -f starter/
kubectl get deployment,pods,service
```

## Étape 6 — Faire évoluer le fichier, pas le cluster

Passez `replicas` à `4` dans `starter/web.yaml`, puis **avant** d'appliquer :

```bash
kubectl diff -f starter/web.yaml     # ce qui changerait, sans rien changer
kubectl apply -f starter/web.yaml
```

> ℹ️ `kubectl diff` sort en **code 1** quand il trouve une différence : ce n'est pas une erreur, c'est le signal « il y a quelque chose à appliquer ».

> ❓ **Question** : `kubectl diff` montre d'autres champs que `replicas` (par exemple `generation`). Qui les a écrits, et pourquoi ne figurent-ils pas dans votre fichier ?

Remettez `replicas: 3` et réappliquez : c'est le fichier qui fait foi.

## Étape 7 — Validez

Depuis le dossier du TP :

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` déploie vos fichiers dans un namespace **jetable** (`tp01-verify`) puis le supprime : votre namespace `telemarche` n'est jamais touché.

---

## 💡 Indices

<details>
<summary><code>minikube start</code> s'arrête : « 403 API rate limit exceeded »</summary>

Quand la version demandée (`--kubernetes-version`) est plus récente que la liste que connaît minikube, celui-ci vérifie qu'elle existe en interrogeant l'API de GitHub, sans s'authentifier. Cette API limite les requêtes anonymes à 60 par heure **et par adresse IP**. En salle, tous les postes sortent souvent par la même adresse : la limite saute vite. La version existe bien, c'est la vérification qui échoue. Ajoutez `--force`, qui laisse minikube passer outre :

```bash
minikube start --kubernetes-version=v1.37.1 --cpus=2 --memory=4g --force
```

`minikube start` affiche aussi « Specified Kubernetes version … is newer than the newest supported version » : c'est un simple avertissement.
</details>

<details>
<summary>« no matches for kind "______" » ou « error converting YAML to JSON »</summary>

Il reste un trou. `verify.sh` les liste avec leur numéro de ligne avant même d'appeler le cluster.
</details>

<details>
<summary>« selector does not match template labels »</summary>

`spec.selector.matchLabels` doit être **inclus** dans `spec.template.metadata.labels`. Le Deployment ne gère que les pods qui portent ces labels.
</details>

<details>
<summary>Le Service existe mais la page ne répond pas</summary>

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
```

Aucune adresse ? Le `selector` du Service ne correspond à aucun pod. Des adresses, mais pas de réponse ? Le `targetPort` ne correspond pas au port d'écoute du conteneur : lisez `kubectl logs deployment/web`.
</details>

---

## 📖 Où chercher (documentation officielle)

- **minikube, démarrage** : https://minikube.sigs.k8s.io/docs/start/
- **Composants d'un cluster** : https://kubernetes.io/docs/concepts/overview/components/
- **Static pods** : https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/
- **Gestion impérative et déclarative** : https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/
- **Aide-mémoire kubectl** : https://kubernetes.io/docs/reference/kubectl/quick-reference/

---

## 🚀 Pour aller plus loin

1. **Le kubeconfig.** Ouvrez `~/.kube/config` : repérez `clusters`, `users` et `contexts`. Que contient le champ `certificate-authority` et à quoi sert-il ?
2. **Le dialogue avec l'API.** `kubectl get pods -v=6` affiche les requêtes HTTP envoyées à l'API server. Quelle URL correspond à `kubectl get pods` ?
3. **`kubectl explain`.** `kubectl explain deployment.spec.replicas` : la documentation vient du cluster lui-même, donc de **sa** version.
4. **Ménage.** `minikube stop` arrête le cluster sans le détruire ; `minikube delete` le détruit. Lequel utiliser en fin de journée ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
