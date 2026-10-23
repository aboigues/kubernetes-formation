# TP11 — Network Policies

> Durée estimée : 1 h 15 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Services, DNS). Un cluster dont le plugin réseau **applique** les NetworkPolicies (étape 1). L'état de départ est fourni : `starter/00-telemarche.yaml`.
> Faites place nette : `kubectl delete deployment,service,statefulset,job,cronjob,daemonset,hpa,networkpolicy --all -n telemarche`

## 🎬 Le contexte

Un audit de sécurité tombe : « **n'importe quel pod du cluster peut appeler l'API de Télémarché** ». C'est vrai. Par défaut, le réseau d'un cluster Kubernetes est entièrement ouvert : tout pod joint tout pod, quel que soit son namespace. Qu'un pod soit compromis, n'importe lequel, et il atteint l'API, la base, et l'API server.

Mission : appliquer le principe du **moindre privilège** au réseau. On interdit tout, puis on ouvre exactement ce dont Télémarché a besoin.

```
                      ┌──────────── namespace telemarche ─────────────┐
   client  ──:8080──> │  web  ──:8080──>  api                          │
 (n'importe où)       │   │                ▲                           │
                      │   └──:53──> DNS    ✗ tout autre pod            │
                      │  (kube-system)     ✗ tout autre namespace      │
                      │  ✗ aucune autre sortie (ni Internet, ni API server)
                      └───────────────────────────────────────────────┘
```

## 🎯 Objectif vérifiable

Quatre NetworkPolicies dans le namespace. `./verify.sh` envoie de **vrais paquets** depuis deux pods clients, l'un dans un autre namespace et l'autre dans le vôtre sans label. Résultat attendu : la vitrine répond à tous et joint l'API ; l'API ne répond qu'à la vitrine ; aucun pod ne sort vers l'API server.

---

## Étape 1 — Un plugin réseau qui applique les politiques

Une NetworkPolicy n'est qu'une **déclaration**. C'est le plugin réseau (CNI) qui l'applique, ou pas. Le CNI par défaut de minikube, **kindnet**, ne les applique **pas** : vos politiques seraient acceptées par l'API server… puis ignorées, sans le moindre avertissement.

Créez un second cluster, avec **Calico**, sans toucher au premier :

```bash
minikube start -p reseau --cni=calico
kubectl config current-context                  # reseau
kubectl get pods -n kube-system -l k8s-app=calico-node     # Running, un par nœud
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

> Pour revenir ensuite au premier cluster : `kubectl config use-context minikube`. Pour supprimer celui-ci : `minikube delete -p reseau`.

## Étape 2 — Constater : tout est ouvert

```bash
kubectl apply -f starter/00-telemarche.yaml
kubectl rollout status deployment/api

# Deux « clients » de test : l'un dans un autre namespace, l'autre dans le vôtre, sans label particulier
kubectl create namespace dehors
kubectl run client -n dehors --image=telemachlearning/curl:8.21.0 --command -- sleep infinity
kubectl run pirate --image=telemachlearning/curl:8.21.0 --command -- sleep infinity
kubectl wait --for=condition=Ready pod/pirate
kubectl wait --for=condition=Ready pod/client -n dehors

# Une petite fonction pour tester : « essai <namespace> <pod> <url> »
essai() { kubectl exec -n "$1" "$2" -- curl -s -o /dev/null -m 5 --retry 2 --retry-connrefused -w "%{http_code}\n" "${@:3}" || echo "bloqué"; }

essai dehors client http://web.telemarche.svc.cluster.local/
essai dehors client http://api.telemarche.svc.cluster.local/api/info
essai telemarche pirate http://api/api/info
essai telemarche pirate -k https://kubernetes.default.svc
```

Tout répond (l'API server répond `403`, mais il **répond** : la connexion aboutit). C'est ce que l'audit reproche.

> Le `--retry` n'est pas décoratif : le résolveur DNS de l'image (musl, Alpine) rate parfois la **toute première** requête d'un pod. Ce n'est pas une politique réseau qui bloque.

## Étape 3 — Tout interdire

Complétez `starter/01-tout-interdire.yaml` (`# TODO 1` à `3`).

> 🎯 **Avant de lancer les commandes suivantes, prédis :** une fois cette politique appliquée, la vitrine répond-elle encore aux clients ? Et ses pods restent-ils `Ready`, alors que leurs probes sont des requêtes HTTP ?

```bash
kubectl apply -f starter/01-tout-interdire.yaml
essai dehors client http://web.telemarche.svc.cluster.local/
kubectl rollout restart deployment/web
kubectl rollout status deployment/web
kubectl get pods -l app=web
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

La vitrine ne répond **plus** (`bloqué` : le délai expire, les paquets sont jetés sans réponse). Ses pods restent pourtant **`Ready`**, même ceux qu'on vient de recréer : les probes viennent du **kubelet**, sur le nœud du pod, et Calico laisse toujours passer ce trafic local. Une NetworkPolicy filtre le trafic **entre pods** (et vers l'extérieur), pas la surveillance du nœud.

Retenez la forme : `podSelector: {}` désigne **tous** les pods du namespace, et une politique sans aucune règle `ingress` ni `egress` n'autorise **rien**. Les politiques ne font qu'**ajouter** des autorisations : il n'existe pas de règle « deny » à écrire, l'interdiction vient de ce qu'aucune politique n'autorise.
</details>

## Étape 4 — Rouvrir le nécessaire : DNS et vitrine

Complétez `starter/02-dns.yaml` (`# TODO 4` et `5`) et `starter/03-web.yaml` (`# TODO 6` et `7`), puis :

```bash
kubectl apply -f starter/02-dns.yaml -f starter/03-web.yaml
essai dehors client http://web.telemarche.svc.cluster.local/
essai dehors client http://web.telemarche.svc.cluster.local/api/info
```

La page répond. Mais `/api/info` est toujours bloqué : la vitrine a le droit de **sortir** vers l'API, mais l'API n'a pas le droit de la **recevoir**. Une connexion entre deux pods d'un namespace protégé demande **deux** autorisations : une sortie (`egress`) chez l'appelant, et une entrée (`ingress`) chez l'appelé.

> ❓ **Questions** :
> 1. Pourquoi `02-dns.yaml` est-il indispensable ? Que se passerait-il sans lui, alors que l'API est autorisée ? (Indice : la vitrine appelle `http://api`, un **nom**.)
> 2. `# TODO 7` demande `8080`, alors que le Service `api` écoute sur `80`. Pourquoi ? (Indice : à quel moment la traduction « Service → pod » a-t-elle lieu, par rapport au filtrage ?)

## Étape 5 — L'API ne répond qu'à la vitrine

Complétez `starter/04-api.yaml` (`# TODO 8`), puis rejouez tous les essais de l'étape 2 :

```bash
kubectl apply -f starter/04-api.yaml
essai dehors client http://web.telemarche.svc.cluster.local/api/info      # 200 : par la vitrine
essai dehors client http://api.telemarche.svc.cluster.local/api/info      # bloqué
essai telemarche pirate http://api/api/info                               # bloqué
essai telemarche pirate -k https://kubernetes.default.svc                 # bloqué
kubectl get networkpolicy
```

## Étape 6 — Ce qu'une politique réseau ne protège pas

> 🎯 **Avant de lancer les commandes suivantes, prédis :** un pod pirate est lancé **avec le label `app=web`**. Joint-il l'API ?

```bash
kubectl run faux-web --labels=app=web --image=telemachlearning/curl:8.21.0 --command -- sleep infinity
kubectl wait --for=condition=Ready pod/faux-web
essai telemarche faux-web http://api/api/info
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

**Oui, `200`.** Une NetworkPolicy reconnaît les pods à leurs **labels**, et un label ne prouve rien : quiconque peut créer un pod dans le namespace peut se faire passer pour la vitrine. La protection réseau repose donc aussi sur le **RBAC** (TP08) : qui a le droit de créer des pods ici ? Pour une vraie identité entre services, on ajoute un *service mesh* (mTLS, comme Istio ou Linkerd) ou les politiques fondées sur l'identité de Cilium.

```bash
kubectl delete pod faux-web pirate
kubectl delete namespace dehors
```
</details>

## Étape 7 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` refuse de tourner sans Calico : sur kindnet, il « réussirait » à appliquer des politiques qui ne protègent rien.

---

## 💡 Indices

<details>
<summary>Tout est encore ouvert après mes politiques</summary>

Le plugin réseau ne les applique pas : `kubectl get pods -n kube-system -l k8s-app=calico-node` doit lister des pods `Running`. Sinon, vous êtes sur le cluster kindnet : `kubectl config current-context`, et voyez l'étape 1.
</details>

<details>
<summary><code>/api/info</code> reste bloqué, alors que la page s'affiche</summary>

Il faut les deux autorisations : l'`egress` de `web` vers `app: api` **sur le port 8080** (`03-web.yaml`), **et** l'`ingress` de `api` depuis `app: web` (`04-api.yaml`). Le journal de la vitrine le confirme : `kubectl logs deployment/web | grep injoignable`.
</details>

<details>
<summary>Plus rien ne résout : <code>Could not resolve host</code></summary>

La sortie vers le DNS est fermée. `02-dns.yaml` doit viser le namespace `kube-system` (label `kubernetes.io/metadata.name`) **et** les pods `k8s-app: kube-dns`, sur le port 53 en UDP et en TCP. Notez la forme : `namespaceSelector` et `podSelector` dans **le même** élément de `to` (un « ET »), pas dans deux éléments séparés (un « OU »).
</details>

---

## 📖 Où chercher (documentation officielle)

- **Network Policies** : https://kubernetes.io/docs/concepts/services-networking/network-policies/
- **Déclarer une Network Policy** (pas à pas) : https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/
- **Calico et les politiques Kubernetes** : https://docs.tigera.io/calico/latest/network-policy/get-started/kubernetes-policy/
- **Éditeur visuel de politiques** (Cilium) : https://editor.networkpolicy.io/

---

## 🚀 Pour aller plus loin

1. **L'erreur du « OU ».** Dans `02-dns.yaml`, séparez `namespaceSelector` et `podSelector` en **deux** éléments de la liste `to` (deux tirets). Que devient la règle ? Qui peut maintenant joindre qui, sur le port 53 ?
2. **Ouvrir la vitrine à un seul namespace.** Restreignez l'`ingress` de `web` au namespace `traefik` (TP07). Que deviennent les essais du client `dehors` ?
3. **Une sortie vers Internet.** Autorisez l'API à joindre `https://pkgs.k8s.io` (règle `ipBlock`). Pourquoi est-ce fragile ? Que propose Calico (`GlobalNetworkPolicy` avec noms de domaine) ou Cilium (`toFQDNs`) ?
4. **Le trafic de la base.** Avec la base du TP05, écrivez la politique qui n'autorise que l'API et le Job de migration à joindre `db` sur le port 5432.

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
