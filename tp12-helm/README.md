# TP12 — Helm : packager Télémarché

> Durée estimée : 1 h 30 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment, Service). **Helm 4** (`helm version` → `v4.x`).
> Faites place nette : `kubectl delete deployment,service,statefulset,job,cronjob,daemonset,hpa --all -n telemarche`

## 🎬 Le contexte

Télémarché s'installe maintenant dans trois environnements : le poste du développeur, la recette, la production. Même application, mais pas les mêmes réglages : 1 réplica d'API en développement, 3 en production ; journaux bavards ici, sobres là-bas. Maintenir trois copies des manifestes, c'est la garantie qu'elles divergent.

**Helm** résout ce problème. Les manifestes deviennent des **templates**, les différences entre environnements des **values**, et chaque installation une **release** versionnée, qu'on peut mettre à jour et ramener en arrière.

```
   Chart « telemarche »                         Releases (dans le cluster)
   ├── Chart.yaml       version, appVersion      telemarche   révision 1, 2, 3…
   ├── values.yaml      réglages par défaut  ──> demo         révision 1
   ├── values-prod.yaml surcharges de prod
   └── templates/       manifestes à trous {{ .Values.… }}
```

## 🎯 Objectif vérifiable

Un chart qui passe `helm lint`, dont les values de production donnent 3 réplicas d'API, et dont une release vit tout son cycle : installation, montée en 1.1, retour arrière. Une seconde release du même chart cohabite avec la première dans le même namespace. `./verify.sh` vérifie tout cela sur un vrai cluster.

---

## Étape 1 — Le chart, de près

```bash
helm version                        # v4.x
tree starter/telemarche             # ou : find starter/telemarche
cat starter/telemarche/Chart.yaml
```

Deux versions, à ne pas confondre :

| Champ | Ce qu'il versionne | Quand le monter |
|---|---|---|
| `version` | le **chart** (ses templates, ses values) | à chaque modification du chart |
| `appVersion` | l'**application** déployée par défaut | quand on livre une nouvelle version de Télémarché |

Lisez `templates/_helpers.tpl` : on y **définit** une fois les noms, les labels et le bloc de durcissement, que les templates **incluent** (`include "telemarche.labels" .`). C'est ce qui garde les templates lisibles.

## Étape 2 — Écrire les templates

Complétez `starter/telemarche/templates/api.yaml` et `web.yaml` (`# TODO 1` à `4`), puis `values.yaml` (`# TODO 5`).

Un template lit ses données dans trois objets :

| Objet | Contenu | Exemple |
|---|---|---|
| `.Values` | `values.yaml`, plus les `-f` et `--set` | `{{ .Values.api.replicas }}` |
| `.Release` | la release en cours | `{{ .Release.Name }}`, `{{ .Release.Revision }}` |
| `.Chart` | `Chart.yaml` | `{{ .Chart.AppVersion }}` |

```bash
helm lint starter/telemarche
helm template essai starter/telemarche | less        # le YAML final, sans rien installer
```

> 🎯 **Avant de lancer la commande suivante, prédis :** vous rendez le chart sous le nom de release `boutique`. Comment s'appelle le Service de l'API ? Et vers quelle adresse la vitrine envoie-t-elle ses appels `/api/` ?

```bash
helm template boutique starter/telemarche | grep -E "^  name:|API_URL" -A1 | grep -v "^--"
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`boutique-api` et `boutique-web`, et la vitrine appelle `http://boutique-api`. Les noms sont **calculés à partir de la release** (`telemarche.nom` dans `_helpers.tpl`). C'est indispensable : sans ce préfixe, deux installations du même chart dans un namespace se disputeraient les mêmes noms. Le `# TODO 4` en découle : écrire `http://api` en dur ferait parler la vitrine de **n'importe quelle** release à une API qui n'existe pas.
</details>

## Étape 3 — Installer, mettre à jour, revenir en arrière

```bash
helm install telemarche starter/telemarche --wait
helm list
helm status telemarche              # affiche aussi les NOTES du chart (templates/NOTES.txt)
helm get manifest telemarche | head -20
kubectl get --raw /api/v1/namespaces/telemarche/services/http:telemarche-web:80/proxy/api/info; echo
```

Livrez la version 1.1, sans toucher au chart :

```bash
helm upgrade telemarche starter/telemarche --set api.image.tag=1.1 --wait
sleep 8; kubectl get --raw /api/v1/namespaces/telemarche/services/http:telemarche-web:80/proxy/api/info; echo
helm history telemarche
```

(Le `sleep 8` laisse les anciens pods finir leur vidange : ils servent encore quelques secondes après la fin de `--wait`.)

> 🎯 **Avant de lancer la commande suivante, prédis :** vous revenez à la révision 1. Après le rollback, quel numéro de révision affiche `helm history` ?

```bash
helm rollback telemarche 1 --wait
helm history telemarche
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

La révision **3**, avec la description `Rollback to 1`. Un rollback ne remonte pas le temps, il **rejoue** le contenu de la révision 1 sous un nouveau numéro. L'historique reste linéaire et complet : on sait toujours qui a déployé quoi, et dans quel ordre, retours arrière compris.
</details>

## Étape 4 — La faute de frappe silencieuse

> 🎯 **Avant de lancer la commande suivante, prédis :** vous voulez 3 réplicas d'API, mais vous tapez `api.replica` au lieu de `api.replicas`. Que répond Helm ?

```bash
helm upgrade telemarche starter/telemarche --set api.replica=3 --wait
kubectl get deployment telemarche-api
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`Release "telemarche" has been upgraded. Happy Helming!`, et l'API reste à **1** réplica. Helm accepte n'importe quelle clé : `api.replica` est une valeur que personne ne lit, voilà tout. C'est le piège classique des `--set` en production. La parade : un fichier `values.schema.json` dans le chart, que Helm vérifie à chaque `install` et `upgrade` (voir « Pour aller plus loin »).
</details>

## Étape 5 — Un environnement, un fichier de values

Complétez `starter/telemarche/values-prod.yaml` (`# TODO 6` et `7`). Il ne contient que ce qui **diffère** de `values.yaml`.

```bash
helm template essai starter/telemarche -f starter/telemarche/values-prod.yaml | grep -E "replicas|LOG_LEVEL" -A1
helm upgrade telemarche starter/telemarche -f starter/telemarche/values-prod.yaml --wait
helm get values telemarche          # ce que VOUS avez fourni
helm get values telemarche --all    # tout ce qui a servi au rendu
```

Installez une seconde release, avec les values par défaut, dans le même namespace :

```bash
helm install demo starter/telemarche --wait
kubectl get deployments          # telemarche-api, telemarche-web, demo-api, demo-web
helm list
```

## Étape 6 — Helm 4 et les modifications manuelles

> 🎯 **Avant de lancer les commandes suivantes, prédis :** pendant un incident, un collègue a monté l'API à 5 réplicas **à la main**. Vous relancez ensuite le déploiement habituel. Que se passe-t-il ?

```bash
kubectl scale deployment telemarche-api --replicas=5
helm upgrade telemarche starter/telemarche -f starter/telemarche/values-prod.yaml --wait
helm history telemarche | tail -2
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Le déploiement **échoue** : `conflict with "kubectl" with subresource "scale" using apps/v1: .spec.replicas`, et la révision est marquée `failed`. Helm 4 applique ses objets **côté serveur** (*server-side apply*) : l'API server sait quel outil a écrit chaque champ, et refuse qu'un autre l'écrase sans le dire. Helm 3, lui, écrasait la modification sans un mot, et le correctif d'urgence disparaissait au déploiement suivant.

Deux sorties possibles : intégrer le changement au chart (le réglage devient officiel), ou reprendre la main en connaissance de cause :

```bash
helm upgrade telemarche starter/telemarche -f starter/telemarche/values-prod.yaml --force-conflicts --wait
kubectl get deployment telemarche-api        # de nouveau 3 réplicas, ceux de values-prod.yaml
```

La règle d'exploitation : **un objet géré par Helm ne se modifie pas à la main**. Ou alors, la modification est rapportée dans le chart aussitôt l'incident clos.
</details>

## Étape 7 — Validez, puis rangez

```bash
./verify.sh              # teste VOTRE chart (dossier starter/)
./verify.sh solution     # (option) le chart de référence
helm uninstall demo telemarche
```

---

## 💡 Indices

<details>
<summary><code>helm lint</code> : « parse error … function "______" not defined » ou « unexpected »</summary>

Il reste un trou dans un template, ou une accolade mal fermée. Chaque expression s'écrit `{{ … }}`. Le `.` initial de `.Values` est obligatoire.
</details>

<details>
<summary><code>helm install</code> : « cannot re-use a name that is still in use »</summary>

Une release de ce nom existe déjà dans le namespace : `helm list`. Utilisez `helm upgrade --install`, qui installe ou met à jour selon le cas.
</details>

<details>
<summary>La vitrine affiche « API injoignable »</summary>

`API_URL` (`# TODO 4`) doit désigner le Service de l'API **de la même release** : `kubectl get deployment <release>-web -o yaml | grep -A1 API_URL`, à comparer avec `kubectl get svc`.
</details>

<details>
<summary><code>helm upgrade</code> échoue sur un conflit, alors que personne n'a touché à rien</summary>

Un autre outil gère peut-être le même champ, un HPA (TP06) par exemple, qui écrit `spec.replicas`. Quand un HPA pilote le Deployment, le template ne doit pas fixer `replicas`, exactement comme au TP06.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Démarrer avec Helm** : https://helm.sh/docs/intro/using_helm/
- **Les templates** (objets intégrés, fonctions) : https://helm.sh/docs/chart_template_guide/
- **Bonnes pratiques des charts** : https://helm.sh/docs/chart_best_practices/
- **Ce qui change dans Helm 4** : https://helm.sh/docs/overview/
- **Server-side apply** (propriété des champs) : https://kubernetes.io/docs/reference/using-api/server-side-apply/

---

## 🚀 Pour aller plus loin

1. **Valider les values.** Écrivez un `values.schema.json` qui exige `api.replicas` (entier, au moins 1) et interdit les clés inconnues (`"additionalProperties": false`). Rejouez la faute de frappe de l'étape 4 : que répond Helm cette fois ?
2. **Redémarrer quand la configuration change.** Ajoutez une ConfigMap au chart (TP05), puis l'annotation `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}` au template du pod. Pourquoi un `helm upgrade` qui ne change que la ConfigMap redémarre-t-il maintenant les pods ?
3. **Distribuer le chart.** `helm package starter/telemarche`, puis poussez l'archive dans un registre OCI (`helm push … oci://…`) et installez-la depuis là.
4. **Un test de release.** Ajoutez `templates/tests/test-api.yaml` (un pod `curl` avec l'annotation `helm.sh/hook: test`) qui appelle `/api/info`, puis lancez `helm test telemarche`.

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
