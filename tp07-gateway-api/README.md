# TP07 — Gateway API avec Traefik

> Durée estimée : 1 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, Service). **Helm 4** installé.

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

La dernière ligne vous replace dans `telemarche`. Supprimer le namespace ne change pas votre contexte, mais celui-ci a pu changer depuis le TP01 : un cluster recréé, ou un autre cluster sélectionné, repart sur `default`. Vos `kubectl apply` y partiraient alors **sans le moindre avertissement**, et l'erreur n'apparaîtrait que plus tard, loin de sa cause. Vérifiez : `kubectl config view --minify -o jsonpath='{..namespace}'; echo` doit afficher `telemarche` (une ligne vide veut dire `default`).

L'état de départ est fourni : `starter/00-telemarche.yaml`, appliqué à l'étape 3. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Jusqu'ici, la vitrine était exposée par un `NodePort` : un port exotique sur chaque nœud, aucun nom de domaine, et aucun moyen de dire « `/api` va à l'API, le reste à la vitrine ». Pour une boutique en ligne, il faut un vrai **point d'entrée HTTP**.

Et l'équipe veut tester l'**API 1.1** sur une petite partie des clients avant de la généraliser : un déploiement **canari**.

La réponse de Kubernetes : la **Gateway API**, qui succède à l'Ingress. Elle sépare les rôles en trois objets :

```
  GatewayClass « traefik »      quel contrôleur ?         ← installée avec Traefik (étape 1)
        │
  Gateway « entree »            quel point d'entrée ?     ← l'exploitant, namespace traefik (étape 2)
        │   port 8000, routes de tous les namespaces
        │
  HTTPRoute « telemarche »      quelles routes ?          ← l'équipe applicative, namespace telemarche (étape 3)
        │   telemarche.local
        ├── /api + X-Canari: oui ───────────> Service api-canari (1.1)
        ├── /api ──────── 90 % ─────────────> Service api        (1.0)
        │          └───── 10 % ─────────────> Service api-canari (1.1)
        └── le reste ───────────────────────> Service web
```

## 🎯 Objectif vérifiable

Un Gateway `entree` programmé par Traefik, une HTTPRoute `telemarche` acceptée, et un trafic conforme : la vitrine sur `/`, la 1.1 pour qui envoie `X-Canari: oui`, et **environ 10 %** de 1.1 pour les autres. `./verify.sh` le mesure sur 100 requêtes.

---

## Étape 1 — Installer le contrôleur (le rôle de l'exploitant)

La Gateway API n'est **pas** intégrée à Kubernetes : ce sont des types d'objets (CRD) à installer, puis un **contrôleur** qui les lit et route le trafic. Ici, Traefik.

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml
kubectl api-resources --api-group=gateway.networking.k8s.io

helm upgrade --install traefik traefik --repo https://traefik.github.io/charts \
  --version 42.1.3 --namespace traefik --create-namespace \
  --values traefik-values.yaml --wait
kubectl get pods,svc -n traefik
kubectl get gatewayclass
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl apply --server-side -f https://…/v1.6.3/standard-install.yaml` : kubectl lit le fichier directement à cette adresse. Ce sont les CRD de la Gateway API publiées par le projet, version 1.6.3, canal `standard` (les types stables). `--server-side` : c'est l'API server qui fusionne les changements et retient qui gère chaque champ. Sans cette option, kubectl recopie l'objet entier dans une annotation limitée à 256 Ko. Le CRD HTTPRoute y tient de justesse (environ 240 Ko) : un peu plus gros, il serait refusé. D'où l'option, que la documentation de la Gateway API donne d'office.
- `kubectl api-resources --api-group=gateway.networking.k8s.io` : les types que le cluster connaît dans ce groupe. Si `Gateway`, `HTTPRoute` et `GatewayClass` y figurent, les CRD sont bien enregistrés. La colonne `NAMESPACED` indique `false` pour `GatewayClass`, qui vaut pour tout le cluster.
- `helm upgrade --install traefik traefik` : installe la **release** `traefik` (le nom de *votre* installation) à partir du **chart** `traefik`. `upgrade --install` installe si la release est absente et la met à jour sinon : la commande peut se relancer sans risque.
  - `--repo https://traefik.github.io/charts` : prend le chart dans ce dépôt, sans `helm repo add` préalable.
  - `--version 42.1.3` : la version du **chart**, pas celle de Traefik (ce chart installe Traefik v3.7.16).
  - `--namespace traefik --create-namespace` : installe dans le namespace `traefik`, et le crée s'il n'existe pas.
  - `--values traefik-values.yaml` : vos réglages, qui remplacent les valeurs par défaut du chart.
  - `--wait` : ne rend la main que lorsque les pods sont prêts.

  Helm est vu en détail au TP12.
- `kubectl get pods,svc -n traefik` : deux types en une commande, séparés par une virgule, sans espace.
- `kubectl get gatewayclass` : pas de `-n`, une GatewayClass n'appartient à aucun namespace.
</details>

Lisez `traefik-values.yaml` : Traefik y lit **uniquement** la Gateway API, et ne crée **pas** de Gateway par défaut, puisque c'est vous qui allez l'écrire. La GatewayClass `traefik` doit être `ACCEPTED: True`.

> Le script `./prerequis.sh` fait exactement cette étape, pour la CI ou pour repartir d'un cluster neuf.

## Étape 2 — Le Gateway : ouvrir le point d'entrée

Complétez `starter/gateway.yaml` (`# TODO 1` à `3`). Il appartient à l'exploitant : il vit dans le namespace de **Traefik**, pas dans celui de l'application.

```bash
kubectl apply -n traefik -f starter/gateway.yaml
kubectl get gateway -n traefik      # PROGRAMMED : True
```

Le port `8000` est celui du **point d'entrée** `web` de Traefik, à l'intérieur de son pod. De l'extérieur, le Service `traefik` le publie sur le port 80.

## Étape 3 — La HTTPRoute : les routes de l'équipe

Déployez l'état de départ (vitrine, API 1.0, API canari 1.1), puis complétez `starter/route.yaml` (`# TODO 4` à `10`) :

```bash
kubectl apply -f starter/00-telemarche.yaml
kubectl apply -f starter/route.yaml
kubectl get httproute
kubectl describe httproute telemarche | grep -A20 "Status:"
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl describe httproute telemarche | grep -A20 "Status:"` : dans le résumé de la route, la ligne `Status:` et les 20 suivantes (`-A20`), là où le contrôleur écrit son verdict.
</details>

Deux conditions à lire dans le statut, écrites par Traefik : **`Accepted`** (le Gateway accepte la route) et **`ResolvedRefs`** (tous les Services cités existent).

Pour joindre le Gateway depuis votre poste, ouvrez un tunnel vers le Service de Traefik **dans un second terminal** :

```bash
kubectl port-forward -n traefik svc/traefik 8000:80
```

```bash
curl -H 'Host: telemarche.local' http://localhost:8000/ | grep title
curl -H 'Host: telemarche.local' http://localhost:8000/api/info; echo
curl -i -H 'Host: autre.local' http://localhost:8000/ | head -1
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl port-forward -n traefik svc/traefik 8000:80` : un tunnel de votre port `8000` vers le port `80` du Service de Traefik.
- `curl -H 'Host: telemarche.local' http://localhost:8000/` : la requête part vers le tunnel, mais annonce le nom `telemarche.local` dans l'en-tête `Host` (`-H` ajoute un en-tête). C'est sur ce nom que le Gateway choisit la route.
- `| grep title` : ne garde que la ligne du titre de la page.
- `curl -i … | head -1` : `-i` affiche aussi les en-têtes de la réponse, et `head -1` n'en garde que la première ligne, celle du code HTTP (`HTTP/1.1 200 OK`, `404`…).
</details>

L'en-tête `Host` choisit la route : c'est ce que ferait un navigateur si `telemarche.local` pointait vers le cluster (pour essayer : ajoutez `127.0.0.1 telemarche.local` à `/etc/hosts`, puis ouvrez http://telemarche.local:8000).

## Étape 4 — Le canari

> 🎯 **Avant de lancer la commande suivante, prédis :** sur 20 appels à `/api/info` sans en-tête particulier, combien répondront en version `1.1` ? Et sur 20 appels avec `X-Canari: oui` ?

```bash
for i in $(seq 20); do curl -s -H 'Host: telemarche.local' http://localhost:8000/api/info | grep -o '"version":"[0-9.]*"'; done | sort | uniq -c
for i in $(seq 20); do curl -s -H 'Host: telemarche.local' -H 'X-Canari: oui' http://localhost:8000/api/info | grep -o '"version":"[0-9.]*"'; done | sort | uniq -c
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `for i in $(seq 20); do …; done` : répète la requête 20 fois (`seq 20` produit les nombres de 1 à 20).
- `curl -s` : sans barre de progression. `-H 'X-Canari: oui'`, dans la seconde ligne, ajoute l'en-tête qui désigne les testeurs.
- `grep -o '"version":"[0-9.]*"'` : `-o` n'affiche que le morceau qui correspond au motif, ici le champ `version` de la réponse JSON.
- `| sort | uniq -c` : trie les 20 lignes, puis compte combien de fois chacune apparaît.
</details>

<details>
<summary>💡 Vérifie ta prédiction</summary>

Sans en-tête : **2 sur 20** environ (`weight: 90` et `weight: 10`). Avec Traefik, la répartition est même très régulière : un tirage pondéré tourniquet, pas un tirage au hasard. Avec `X-Canari: oui` : **20 sur 20**. Les règles sont évaluées de la plus **précise** à la plus générale, quel que soit leur ordre dans le fichier : la règle « chemin `/api` **et** en-tête » l'emporte sur « chemin `/api` seul ».

Remarquez que la pondération ne dépend **pas** du nombre de pods : `api` a 2 réplicas, `api-canari` 1 seul, et la part de la 1.1 reste de 10 %. Avec un simple Service qui regrouperait les trois pods, la part de la 1.1 serait d'un tiers, et on ne pourrait la régler qu'en changeant le nombre de pods.

Pour généraliser la 1.1 : passez les poids à `0` et `100`, appliquez, vérifiez. Revenez ensuite à `90` / `10`.
</details>

## Étape 5 — Qui a le droit de s'attacher au Gateway ?

> 🎯 **Avant de lancer la commande suivante, prédis :** l'exploitant retire le bloc `allowedRoutes` du Gateway, en pensant revenir à « la valeur par défaut ». Le site continue-t-il de répondre ?

```bash
kubectl patch gateway entree -n traefik --type=json -p '[{"op":"remove","path":"/spec/listeners/0/allowedRoutes"}]'
curl -i -H 'Host: telemarche.local' http://localhost:8000/ | head -1
kubectl get httproute telemarche -o jsonpath='{.status.parents[0].conditions[0]}'; echo
kubectl get gateway entree -n traefik -o jsonpath='{.status.listeners[0].attachedRoutes}'; echo
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl patch gateway entree -n traefik --type=json -p '[…]'` : modifie l'objet sur place, sans fichier. `--type=json` attend une liste d'opérations au format *JSON Patch* : ici, `remove` (supprimer) le champ situé au chemin `/spec/listeners/0/allowedRoutes`, c'est-à-dire le bloc `allowedRoutes` du premier écouteur.
- `-o jsonpath='{.status.parents[0].conditions[0]}'` : la première condition que le premier Gateway parent a écrite dans le statut de la route.
- `-o jsonpath='{.status.listeners[0].attachedRoutes}'` : le nombre de routes rattachées au premier écouteur du Gateway.
</details>

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non : **404**. Par défaut, un Gateway n'accepte que les routes de **son propre** namespace (`from: Same`). La route passe en `Accepted: False`, raison `NotAllowedByListeners`, et le Gateway compte `0` route attachée. C'est voulu : l'exploitant décide **qui** peut publier sur son point d'entrée (`All`, `Same`, ou une liste de namespaces choisis par labels avec `Selector`). Les équipes, elles, ne peuvent pas modifier le Gateway.

```bash
kubectl apply -n traefik -f starter/gateway.yaml      # on remet allowedRoutes
```
</details>

## Étape 6 — Diagnostiquer une route en erreur

Le marketing a publié sa page promotionnelle. Appliquez sa route **sans la lire** :

```bash
kubectl apply -f pannes/promo.yaml
curl -i -H 'Host: promo.telemarche.local' http://localhost:8000/ | head -1
```

Menez l'enquête avec `kubectl get httproute` et `kubectl describe httproute promo`.

> ❓ **Questions** : quel code HTTP le client reçoit-il, et pourquoi pas un 404 ? Laquelle des deux conditions est fausse, et que dit son message ? Que faudrait-il changer, et qui (l'exploitant ou l'équipe) doit le faire ?

```bash
kubectl delete -f pannes/promo.yaml
```

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` applique votre Gateway dans le namespace `traefik` et votre route dans son namespace jetable. Il interroge le Gateway depuis un pod client, sous un nom de domaine qui lui est propre, pour ne jamais tomber sur **votre** route du namespace `telemarche`.

---

## 💡 Indices

<details>
<summary>La route n'a <strong>aucun</strong> statut (<code>Status</code> vide dans <code>describe</code>)</summary>

Aucun contrôleur ne l'a prise en charge : son `parentRefs` désigne un Gateway qui n'existe pas. Sans `namespace`, `parentRefs` cherche le Gateway **dans le namespace de la route** ; or `entree` est dans `traefik`. Vérifiez `name` et `namespace` (`# TODO 4` et `5`).
</details>

<details>
<summary><code>Accepted: False</code>, raison <code>NotAllowedByListeners</code></summary>

Le Gateway n'accepte pas les routes de votre namespace : voyez l'étape 5 (`allowedRoutes`, `# TODO 3`).
</details>

<details>
<summary>Le Gateway reste <code>PROGRAMMED: Unknown</code> ou <code>False</code></summary>

`kubectl describe gateway entree -n traefik`. Le `gatewayClassName` doit être celui de `kubectl get gatewayclass` ; le port doit être celui d'un point d'entrée de Traefik (`8000` pour `web`). Traefik tourne-t-il ? `kubectl logs -n traefik deployment/traefik`.
</details>

<details>
<summary><code>curl</code> : « Connection refused » sur localhost:8000</summary>

Le `port-forward` n'est plus actif (il s'arrête si le pod Traefik redémarre) : relancez-le dans le second terminal.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Gateway API** (concepts, rôles) : https://gateway-api.sigs.k8s.io/concepts/api-overview/
- **HTTPRoute** (correspondances, poids, précédence des règles) : https://gateway-api.sigs.k8s.io/api-types/httproute/
- **Déploiement canari avec la Gateway API** : https://gateway-api.sigs.k8s.io/guides/traffic-splitting/
- **Traefik et la Gateway API** : https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/
- **De l'Ingress à la Gateway API** : https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/

---

## 🚀 Pour aller plus loin

1. **Une redirection.** Ajoutez une règle qui redirige `/boutique` vers `/` avec un filtre `RequestRedirect` (code 301). Vérifiez avec `curl -i`.
2. **Réécrire un en-tête.** Avec un filtre `RequestHeaderModifier`, ajoutez `X-Passe-Par: gateway` à toutes les requêtes envoyées à l'API. Comment le vérifier sans modifier l'API ? (Indice : `/api/info` ne l'affiche pas, mais un pod `traefik/whoami` le ferait.)
3. **Restreindre par labels.** Remplacez `from: All` par `from: Selector`, avec un `selector` sur le label `kubernetes.io/metadata.name: telemarche`. Qu'arrive-t-il à la route de `verify.sh` ?
4. **HTTPS.** Créez un certificat autosigné (`openssl req -x509 …`), rangez-le dans un Secret de type `kubernetes.io/tls` du namespace `traefik`, et ajoutez au Gateway un listener `HTTPS` sur le port `8443` qui y fait référence.

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
