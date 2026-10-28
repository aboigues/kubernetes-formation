# TP02 — Manifestes

> Durée estimée : 45 min · Namespace de travail : `telemarche`
> Prérequis : TP01 (un cluster qui tourne, le namespace `telemarche` actif).

## 🎬 Le contexte

Au TP01, `kubectl create --dry-run` a écrit le manifeste à votre place. En exploitation, c'est l'inverse : on vous tend un YAML écrit par quelqu'un d'autre et il faut le **lire**, le **corriger** et comprendre ce que le cluster en fait.

Vous allez écrire trois pods à la main — l'API en deux versions et la vitrine —, regarder chaque composant du cluster entrer en action quand vous les appliquez, puis les retrouver par leurs **labels**, le mécanisme qui relie tous les objets Kubernetes entre eux.

## 🎯 Objectif vérifiable

Trois pods prêts — `api-demo` (API 1.0), `api-canari` (API 1.1) et `web-demo` (vitrine 1.0) — dont les labels permettent de les sélectionner par application, par version et par environnement. `./verify.sh` le contrôle.

> ℹ️ Ce TP utilise des **pods « nus »**, sans Deployment, pour isoler la notion de manifeste. On ne le fait jamais en production : vous allez voir pourquoi à l'étape 5.

---

## Étape 1 — Trouver un champ sans quitter le terminal

Le cluster documente son propre schéma :

```bash
kubectl explain pod | head -20
kubectl explain pod.spec.containers.ports
kubectl explain pod.spec.containers.env
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl explain pod` : la documentation d'un type, servie par l'API server de **votre** version. `| head -20` n'en garde que les 20 premières lignes.
- `kubectl explain pod.spec.containers.ports` : on descend dans les champs en les séparant par des points. Ajoutez `--recursive` pour voir tout l'arbre d'un coup.
</details>

Les variables d'environnement comprises par l'API et la vitrine sont listées dans [`apps/telemarche/README.md`](../apps/telemarche/README.md).

## Étape 2 — Compléter les manifestes

Complétez les `______` des trois fichiers de `starter/` (`# TODO 1` à `13`). Ne touchez pas aux blocs `securityContext` et `resources` : ils seront expliqués au TP06.

Avant d'appliquer, faites valider vos fichiers **par l'API server**, sans rien créer :

```bash
kubectl apply --dry-run=server -f starter/
```

## Étape 3 — Regarder le cluster travailler

Ouvrez un **second terminal** et laissez-y tourner :

```bash
kubectl get events --watch
```

Puis, dans le premier :

```bash
kubectl apply -f starter/pod-api.yaml
kubectl get pod api-demo -o wide
```

Observez les événements défiler et notez **qui** les émet :

```bash
kubectl get events --field-selector involvedObject.name=api-demo \
  -o custom-columns=SOURCE:.source.component,RAISON:.reason,MESSAGE:.message
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `kubectl get events` : les événements du namespace, que les composants publient chaque fois qu'ils agissent sur un objet.
- `--field-selector involvedObject.name=api-demo` : un filtre sur un **champ** de l'objet, appliqué par l'API server (`-l` filtre sur les labels). `involvedObject` est l'objet dont parle l'événement : ici, on ne garde que ceux du pod `api-demo`.
- `\` en fin de ligne : la commande continue sur la ligne suivante.
- `-o custom-columns=TITRE:chemin,…` : un tableau à la carte. Chaque colonne s'écrit avec un titre, deux-points, puis le chemin du champ dans l'objet. Pas d'espace autour des virgules.
  - `.source.component` : le composant qui a émis l'événement ;
  - `.reason` : le motif, en un mot (`Pulled`, `Started`…) ;
  - `.message` : le texte complet.

Pour trouver d'autres chemins : `kubectl get events -o yaml`, ou `kubectl explain event`.
</details>

> ❓ **Question** : reliez chaque ligne à un composant du cours. Qui a choisi le nœud ? Qui a lancé le conteneur ? Pourquoi aucun événement ne vient-il de l'API server ni d'etcd ?

Comparez maintenant ce que **vous** avez écrit et ce que le cluster a **ajouté** :

```bash
kubectl get pod api-demo -o yaml | less
```

Repérez `spec` (votre état désiré, complété de valeurs par défaut) et `status` (l'état observé, écrit par le kubelet : `podIP`, `conditions`, `containerStatuses`…).

## Étape 4 — Retrouver les objets par leurs labels

```bash
kubectl apply -f starter/
kubectl get pods --show-labels
kubectl get pods -L app.kubernetes.io/version,environnement
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `--show-labels` : ajoute une colonne avec **tous** les labels de chaque pod.
- `-L clé1,clé2` : une colonne par clé choisie, avec la valeur du label (vide s'il est absent). Plus lisible quand les labels sont nombreux.
</details>

Sélectionnez :

```bash
kubectl get pods -l app=api                                  # par application
kubectl get pods -l app=api,environnement=production         # ET logique
kubectl get pods -l 'environnement in (recette, production)' # ensemble de valeurs
kubectl get pods -l 'app.kubernetes.io/version!=1.0'         # négation
```

Un label se modifie à chaud :

```bash
kubectl label pod api-canari environnement=recette --overwrite
kubectl get pods -l environnement=recette
kubectl label pod api-canari environnement=production --overwrite   # on remet
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl label pod api-canari environnement=recette` : pose le label sur l'objet. `--overwrite` est obligatoire quand la clé existe déjà : sans lui, kubectl refuse de changer la valeur.
- `kubectl get pods -l environnement=recette` : `-l` (*selector*) ne garde que les objets qui portent ce label.
- Pour retirer un label : la clé suivie d'un `-`, soit `kubectl label pod api-canari environnement-`.
</details>

> ❓ **Question** : un Service (TP03) choisit les pods vers lesquels envoyer le trafic avec un sélecteur de labels. Que se passerait-il si vous retiriez le label `app=api` d'un pod en production ?

## Étape 5 — Un pod nu n'est pas réparé

> 🎯 **Avant de lancer la commande suivante, prédis :** au TP01, un pod supprimé revenait aussitôt. Et ici ?

```bash
kubectl delete pod api-demo
sleep 5; kubectl get pods
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Il **ne revient pas**. Au TP01, ce n'était pas le pod qui se recréait : c'était son **ReplicaSet** qui constatait un manque et créait un remplaçant. Un pod nu n'a aucun contrôleur au-dessus de lui (`kubectl get pod web-demo -o jsonpath='{.metadata.ownerReferences}'` est vide) : personne ne surveille son état désiré. C'est pourquoi on déploie toujours une application avec un **Deployment** — sujet du TP03.
</details>

Réappliquez pour la suite : `kubectl apply -f starter/pod-api.yaml`.

## Étape 6 — Les commandes de l'exploitant

```bash
kubectl describe pod api-demo          # détail + événements récents (en bas)
kubectl logs api-demo                  # journaux du conteneur
kubectl port-forward pod/api-demo 8080:8080
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl describe pod api-demo` : un résumé lisible de l'objet, avec à la fin ses événements récents.
- `kubectl logs api-demo` : ce que le conteneur écrit sur sa sortie standard. `-f` pour suivre en direct, `--previous` pour le conteneur d'avant un redémarrage.
- `kubectl port-forward pod/api-demo 8080:8080` : ouvre un tunnel du port `8080` de **votre poste** (à gauche) vers le port `8080` du pod (à droite), en passant par l'API server. La commande reste au premier plan tant que le tunnel est ouvert.
</details>

Dans un autre terminal : `curl -s localhost:8080/api/info`. Arrêtez le `port-forward` avec `Ctrl-C`.

> 🎯 **Avant de lancer la commande suivante, prédis :** pouvez-vous ouvrir un shell dans le conteneur de l'API ?

```bash
kubectl exec -it api-demo -- sh
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `kubectl exec api-demo` : lance une commande **dans** le conteneur d'un pod qui tourne déjà.
- `-it` : branche votre terminal sur la commande (`-i` : l'entrée, `-t` : un terminal), indispensable pour un shell interactif.
- `--` : la fin des options de kubectl. Ce qui suit, ici `sh`, est la commande exécutée dans le conteneur.
</details>

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non : `exec: "sh": executable file not found in $PATH`. L'image de l'API est **distroless** : elle ne contient que le binaire de l'application, ni shell, ni `ls`, ni `curl`. C'est voulu — moins d'outils, c'est moins de failles et moins de prise pour un attaquant. Pour inspecter un tel pod, on lui **adjoint** un conteneur d'outils avec `kubectl debug` : ce sera au TP03.
</details>

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>« cannot unmarshal number into Go struct field ObjectMeta.metadata.labels of type string »</summary>

En YAML, `1.0` est un **nombre**. Or la valeur d'un label est toujours une chaîne : écrivez `"1.0"`, entre guillemets. Même piège avec `true`, `yes`, `no` ou `0755`.
</details>

<details>
<summary>Le pod est en <code>ErrImagePull</code> ou <code>ImagePullBackOff</code></summary>

Le nom ou l'étiquette de l'image est faux. `kubectl describe pod <nom>` affiche, en bas, l'image exacte que le kubelet a tenté de tirer.
</details>

<details>
<summary>« the namespace from the provided object does not match »</summary>

Un manifeste du dépôt ne fixe **jamais** `metadata.namespace` : c'est la commande (`-n`, ou le namespace du contexte) qui décide. N'en ajoutez pas.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Objets Kubernetes et champs obligatoires** : https://kubernetes.io/docs/concepts/overview/working-with-objects/
- **Labels et sélecteurs** : https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
- **Labels recommandés (`app.kubernetes.io/*`)** : https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/
- **Namespaces** : https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- **Cycle de vie d'un pod** : https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

---

## 🚀 Pour aller plus loin

1. **Annotations.** `kubectl annotate pod api-demo equipe=exploitation` : quelle différence avec un label ? Peut-on sélectionner des pods par annotation ?
2. **Sélecteurs de champs.** `kubectl get pods --field-selector status.phase=Running` : sur quels champs fonctionnent-ils, et pourquoi pas sur tous ?
3. **`kubectl explain --recursive`.** `kubectl explain pod.spec --recursive | less` : combien de champs un pod accepte-t-il ? Lesquels sont obligatoires ?
4. **Plusieurs objets, un fichier.** Fusionnez les trois manifestes en un seul fichier séparé par `---`. Qu'est-ce qui change pour `kubectl apply` et `kubectl delete -f` ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
