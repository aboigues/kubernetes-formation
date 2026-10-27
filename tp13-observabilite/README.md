# TP13 — Observabilité : Prometheus, alertes, Grafana

> Durée estimée : 2 h · Namespace de travail : `telemarche`
> Prérequis : TP03 (Services), TP12 (Helm 4). 4 processeurs et 6 Go de mémoire pour minikube (voir ci-dessous).

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

La dernière ligne vous replace dans `telemarche`. Supprimer le namespace ne change pas votre contexte, mais celui-ci a pu changer depuis le TP01 : un cluster recréé, ou un autre cluster sélectionné, repart sur `default`. Vos `kubectl apply` y partiraient alors **sans le moindre avertissement**, et l'erreur n'apparaîtrait que plus tard, loin de sa cause. Vérifiez : `kubectl config view --minify -o jsonpath='{..namespace}'; echo` doit afficher `telemarche` (une ligne vide veut dire `default`).

L'état de départ est fourni : `starter/00-telemarche.yaml`, appliqué à l'étape 2. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Mardi, 3 h du matin : la boutique est en panne depuis deux heures, et ce sont les clients qui l'ont signalé. `kubectl logs` ne montre que le pod en cours, `kubectl top` que l'instant présent. Personne n'a été prévenu.

Mission : donner à Télémarché une **supervision**. Des **métriques** collectées et conservées, des **alertes** qui sonnent avant les clients, un **tableau de bord** qui montre l'état d'un coup d'œil.

```
   pods api ── /metrics ◀── collecte ── Prometheus ── règles ──▶ Alertmanager ──▶ (mail, chat…)
       ▲         (toutes les 15 s)        │   ▲
   ServiceMonitor « api »                 │   └── PrometheusRule « telemarche »
   (où collecter)                         ▼
   kube-state-metrics ── état des objets  Grafana ◀── ConfigMap « tableau-de-bord-telemarche »
```

## 🎯 Objectif vérifiable

Prometheus collecte les 3 pods de l'API et compte leurs requêtes par route et par code HTTP. Deux règles d'alerte sont chargées, et **elles sonnent** : `./verify.sh` provoque un conteneur qui redémarre en boucle, puis la disparition de tous les pods de l'API, et attend que chaque alerte passe à `firing`.

---

## Étape 0 — Un cluster assez grand

Votre cluster a été créé au TP01 avec 2 processeurs et 4 Go : c'est trop peu pour la pile de supervision. Or minikube ne redimensionne pas un cluster existant : relancer `minikube start --cpus=4 --memory=6g` ne fait qu'afficher un avertissement. Il faut le recréer. ⚠️ `minikube delete` détruit le cluster et tout ce qu'il contient : chaque TP fournit son état de départ, vous ne perdez rien d'utile. Si vous avez déjà créé le cluster avec 4 processeurs et 6 Go, passez à l'étape 1.

```bash
minikube delete
minikube start --kubernetes-version=v1.37.1 --cpus=4 --memory=6g
kubectl create namespace telemarche
kubectl config set-context --current --namespace=telemarche
```

## Étape 1 — Installer la pile de supervision

Le chart **kube-prometheus-stack** installe tout d'un coup : l'opérateur Prometheus, Prometheus, Alertmanager, Grafana, kube-state-metrics (l'état des objets Kubernetes) et node-exporter (les métriques des nœuds).

Lisez d'abord `monitoring-values.yaml`, puis installez. Le mot de passe de Grafana est tiré au hasard : celui que le chart fixe par défaut, `prom-operator`, est public.

```bash
helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version 92.11.0 \
  --namespace monitoring --create-namespace \
  --values monitoring-values.yaml \
  --set-string grafana.adminPassword="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" \
  --wait --timeout 10m
kubectl get pods -n monitoring
kubectl api-resources --api-group=monitoring.coreos.com
```

> Le script `./prerequis.sh` fait exactement cette étape, pour la CI ou pour repartir d'un cluster neuf.

L'opérateur ajoute de nouveaux types d'objets : **ServiceMonitor** (« où collecter »), **PrometheusRule** (« quand alerter »), et d'autres. On ne configure plus Prometheus en éditant son fichier : on déclare des objets Kubernetes, et l'opérateur s'en charge.

## Étape 2 — Ce que l'API expose

```bash
kubectl apply -f starter/00-telemarche.yaml
kubectl rollout status deployment/api
kubectl get --raw /api/v1/namespaces/telemarche/services/http:api:80/proxy/metrics
```

Trois métriques au format Prometheus, avec leurs **labels** entre accolades : `telemarche_http_requests_total{method, route, code}` (un compteur qui ne fait que monter), `telemarche_orders_total`, et `telemarche_build_info{version, stockage}`.

> 🎯 **Avant de lancer les commandes suivantes, prédis :** Prometheus tourne, l'API publie ses métriques. Les collecte-t-il déjà ?

Ouvrez Prometheus dans un **second terminal**. Attention au port local : sur AlmaLinux, **9090 est déjà pris** par Cockpit, l'interface d'administration du système.

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 19090:9090
```

Ouvrez http://localhost:19090, menu **Status → Target health**, puis cherchez `telemarche` ; ou bien, dans **Query**, exécutez `up{namespace="telemarche"}`.

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non : aucune cible, la requête ne renvoie **rien**. Prometheus ne collecte que ce qu'on lui désigne. Avec l'opérateur, cette désignation est un **ServiceMonitor**.
</details>

## Étape 3 — Le ServiceMonitor

Complétez `starter/servicemonitor.yaml` (`# TODO 1` à `4`). Un ServiceMonitor ne désigne pas des pods mais des **Services** (par leurs labels), puis un **port de ces Services, par son nom**. Regardez le Service de l'API : son port s'appelle `http`.

```bash
kubectl get service api -o jsonpath='{.spec.ports}'; echo
kubectl apply -f starter/servicemonitor.yaml
```

Au bout d'une minute environ (le temps que l'opérateur régénère la configuration et que Prometheus la recharge), les 3 pods apparaissent dans **Status → Target health**, et `up{namespace="telemarche"}` renvoie trois séries à `1`.

## Étape 4 — Interroger : PromQL

Envoyez un peu de trafic, puis essayez ces requêtes dans l'onglet **Query** :

```bash
for i in $(seq 50); do kubectl get --raw /api/v1/namespaces/telemarche/services/http:web:80/proxy/api/products >/dev/null; done
```

| Requête | Ce qu'elle répond |
|---|---|
| `telemarche_http_requests_total{namespace="telemarche"}` | les compteurs bruts, une série par pod, route et code |
| `rate(telemarche_http_requests_total{namespace="telemarche"}[1m])` | le **débit** par seconde, moyenné sur 1 minute |
| `sum by (route) (rate(telemarche_http_requests_total{namespace="telemarche"}[1m]))` | le débit par route, tous pods confondus |
| `sum by (code) (rate(telemarche_http_requests_total{namespace="telemarche"}[5m]))` | le débit par code HTTP : les 5xx sont-ils là ? |
| `kube_deployment_status_replicas_available{namespace="telemarche"}` | les réplicas disponibles, vus par kube-state-metrics |

> ❓ **Questions** :
> 1. Pourquoi ne jamais afficher un compteur brut (`…_total`) sur un graphique, mais toujours son `rate()` ?
> 2. Dans la répartition par route, d'où viennent les `GET /healthz` et `GET /ready`, alors que personne ne les appelle ?

## Étape 5 — Les alertes

Complétez `starter/alertes.yaml` (`# TODO 5` à `7`) : deux règles, l'une sur les redémarrages, l'autre sur la disparition de l'API.

```bash
kubectl apply -f starter/alertes.yaml
```

Dans Prometheus, menu **Alerts** : vos deux règles sont là, `inactive`. Elles côtoient des dizaines d'autres, livrées par le chart.

> 🎯 **Avant de lancer la commande suivante, prédis :** l'équipe livre son « service de stock ». Combien de temps avant qu'une alerte sonne, et laquelle ?

```bash
kubectl apply -f pannes/stock.yaml
kubectl get pods -l app=stock --watch        # Ctrl-C au bout de 2 minutes
```

Suivez **Alerts** : une alerte passe `pending` (la condition est vraie, mais pas encore depuis `for: 1m`), puis `firing`.

<details>
<summary>💡 Vérifie ta prédiction</summary>

Le pod redémarre en boucle (`CrashLoopBackOff`). `ConteneurRedemarreEnBoucle` passe `firing` au bout de **2 minutes** environ : le temps d'accumuler plus de 2 redémarrages (Kubernetes espace les relances : 10 s, 20 s, 40 s…), puis la minute du `for`. Vous verrez aussi `KubePodCrashLooping` arriver, une règle **livrée par le chart** : avant d'écrire une alerte, regardez celles qui existent déjà.

La cause, maintenant : `kubectl logs deployment/stock --previous` → `configuration invalide : LOG_LEVEL="bavard" (valeurs acceptées : debug, info, warn, error)`. L'alerte dit **que** ça va mal, les journaux disent **pourquoi**.

```bash
kubectl delete -f pannes/stock.yaml
```
</details>

> 🎯 **Avant de lancer les commandes suivantes, prédis :** un collègue propose une alerte plus simple pour l'API : « `sum by (namespace) (up{service="api"}) == 0` : plus aucun pod ne répond ». Vous coupez l'API. Son alerte sonnera-t-elle ?

```bash
kubectl scale deployment api --replicas=0
sleep 60
```

Dans **Query**, comparez `sum by (namespace) (up{service="api"}) == 0` et `kube_deployment_status_replicas_available{deployment="api"} == 0`.

<details>
<summary>💡 Vérifie ta prédiction</summary>

**Jamais.** Sans pod, il n'y a plus de cible ; sans cible, plus de série `up` du tout. La requête ne renvoie pas `0`, elle ne renvoie **rien**, et une alerte sans résultat ne sonne pas. L'alerte se tait précisément dans le cas le plus grave. kube-state-metrics, lui, publie l'état du Deployment **même à 0** réplica : c'est pourquoi `TelemarcheApiIndisponible` s'appuie sur lui (`# TODO 6`), et elle passe `firing` au bout de 1 à 2 minutes. À retenir : **une alerte doit être testée en provoquant sa panne**, c'est exactement ce que fait `verify.sh`.

```bash
kubectl scale deployment api --replicas=3
```
</details>

Les alertes partent vers **Alertmanager**, qui les regroupe, les déduplique et les envoie (mail, chat…). Pour le voir : `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093`, puis http://localhost:9093.

## Étape 6 — Grafana : un tableau de bord versionné

```bash
kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Connectez-vous sur http://localhost:3000 (utilisateur `admin`). Explorez les tableaux de bord livrés : **Kubernetes / Compute Resources / Namespace (Pods)**, avec le namespace `telemarche`.

Puis ajoutez celui de Télémarché, écrit **comme du code**, dans une ConfigMap :

```bash
kubectl apply -f outils/tableau-de-bord.yaml
```

Une minute plus tard, **Dashboards → Télémarché** apparaît, sans un clic. Le sidecar de Grafana charge toute ConfigMap qui porte le label `grafana_dashboard`. Le tableau de bord se relit, se versionne et se déploie comme le reste de l'application.

## Étape 7 — Et les journaux ?

```bash
kubectl logs -l app=api --prefix --tail=3          # les 3 pods à la fois
kubectl logs -l app=api --prefix --since=5m | grep -c level=INFO
```

> ❓ **Question** : un pod a planté puis a été remplacé hier soir. Où sont passés ses journaux ? Qu'apporterait une collecte centralisée (Loki, voir « Pour aller plus loin ») ?

## Étape 8 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` interroge Prometheus par son API HTTP, provoque les deux pannes et attend les deux alertes : comptez 5 minutes.

---

## 💡 Indices

<details>
<summary>Le ServiceMonitor est créé, mais aucune cible n'apparaît</summary>

Trois suspects, dans l'ordre : le `selector` ne désigne pas les labels **du Service** (`kubectl get svc --show-labels`) ; le `port` n'est pas le **nom** du port du Service (`http`, pas `80` ni `8080`) ; Prometheus n'adopte pas ce ServiceMonitor (voyez `serviceMonitorSelectorNilUsesHelmValues` dans `monitoring-values.yaml`).
</details>

<details>
<summary>Ma règle n'apparaît pas dans <strong>Alerts</strong></summary>

`kubectl get prometheusrule` doit la lister. Une erreur de syntaxe PromQL la fait rejeter : `kubectl logs -n monitoring statefulset/prometheus-monitoring-kube-prometheus-prometheus -c config-reloader --tail=20`.
</details>

<details>
<summary>Le port-forward vers 19090 répond « address already in use »</summary>

Un autre port-forward tourne déjà (`jobs`, `ps aux | grep port-forward`). Et ne remplacez pas 19090 par 9090 sur AlmaLinux : c'est le port de Cockpit.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Prometheus, les bases** : https://prometheus.io/docs/introduction/overview/
- **PromQL** : https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Règles d'alerte** : https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/
- **Prometheus Operator** (ServiceMonitor, PrometheusRule) : https://prometheus-operator.dev/docs/developer/getting-started/
- **kube-prometheus-stack** : https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- **Métriques de kube-state-metrics** : https://github.com/kubernetes/kube-state-metrics/tree/main/docs/metrics

---

## 🚀 Pour aller plus loin

1. **Le taux d'erreur.** Écrivez une alerte qui sonne quand plus de 5 % des requêtes de l'API répondent en 5xx sur 5 minutes. Comment la déclencher ? (Indice : pendant son démarrage, l'API répond 503 sur `/api/…`.)
2. **Envoyer les alertes quelque part.** Configurez un récepteur Alertmanager (un webhook vers un pod `traefik/whoami`, par exemple) et vérifiez qu'il reçoit `ConteneurRedemarreEnBoucle`.
3. **Les journaux centralisés.** Installez Loki et Alloy (charts `grafana/loki` et `grafana/alloy`), ajoutez Loki comme source de données dans Grafana, et retrouvez les journaux d'un pod supprimé.
4. **Superviser le HPA du TP06.** Rejouez la charge du TP06 et affichez `kube_horizontalpodautoscaler_status_current_replicas` à côté du débit de requêtes. Le HPA réagit-il avant ou après la hausse du débit ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
