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

Toutes vos commandes visent désormais `telemarche` sans `-n`.

## Étape 4 — Mode impératif : dire à Kubernetes quoi faire

```bash
kubectl create deployment web --image=telemachlearning/telemarche-web:1.0
kubectl get pods --watch            # Ctrl-C quand le pod est Running
kubectl scale deployment web --replicas=3
kubectl expose deployment web --type=NodePort --port=80 --target-port=8080
kubectl get deployment,replicaset,pods,service
```

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

Gardez cette sortie sous les yeux et complétez les `______` de **`starter/web.yaml`** et **`starter/web-service.yaml`** (`# TODO 1` à `8`). Le bloc `securityContext` et les `resources` sont déjà écrits : ne les touchez pas, ils seront expliqués au TP06.

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
