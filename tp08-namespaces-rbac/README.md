# TP08 — Namespaces, quotas et RBAC

> Durée estimée : 1 h 15 · Namespace de travail : `telemarche`
> Prérequis : TP03 (Deployment), TP06 (requests et limits).

**Avant de commencer, faites place nette.** Repartez d'un namespace vide : les objets laissés par les TP précédents fausseraient vos résultats. La suppression prend quelques secondes, et votre contexte reste réglé sur `telemarche`.

```bash
kubectl delete namespace telemarche --ignore-not-found
kubectl create namespace telemarche
```

L'état de départ est fourni : `starter/00-telemarche.yaml`, appliqué à l'étape 1. Il crée ou met à jour les objets qu'il décrit, et rien d'autre : `kubectl apply` ne supprime jamais un objet absent de ses fichiers. Il ne remplace donc pas la place nette.

## 🎬 Le contexte

Télémarché ne sera bientôt plus seule sur le cluster : l'équipe logistique arrive, avec ses propres applications. Deux règles s'imposent avant de partager :

1. **Un budget par équipe.** Une application qui s'emballe ne doit pas consommer tout le cluster.
2. **Le moindre privilège.** L'outil de supervision de Télémarché doit pouvoir **lire** l'état des pods, mais rien d'autre : ni supprimer, ni lire les mots de passe.

```
   namespace telemarche
   ├── ResourceQuota budget      le total que l'équipe peut réserver
   ├── LimitRange defauts        les valeurs par défaut, conteneur par conteneur
   │
   ├── ServiceAccount supervision ──┐
   ├── Role lecture-pods ───────────┤ RoleBinding supervision-lecture
   │     pods, pods/log : get, list, watch
   └── Pod supervision  (porte l'identité supervision)
```

## 🎯 Objectif vérifiable

Un quota et une LimitRange actifs dans le namespace, et un ServiceAccount `supervision` qui **liste les pods et lit leurs journaux, et rien d'autre**. `./verify.sh` le contrôle avec `kubectl auth can-i`, puis depuis le pod lui-même, avec son propre jeton.

---

## Étape 1 — Le namespace, unité de partage

Un namespace regroupe les objets d'une équipe ou d'une application. C'est à son niveau que s'appliquent les quotas et la plupart des droits.

```bash
kubectl get namespaces
kubectl config set-context --current --namespace=telemarche     # si ce n'est pas déjà fait (TP01)
kubectl apply -f starter/00-telemarche.yaml
kubectl api-resources --namespaced=false | head     # ce qui n'appartient à AUCUN namespace
```

Les nœuds, les PersistentVolumes, les StorageClasses, les namespaces eux-mêmes : ces objets sont **globaux** au cluster.

## Étape 2 — Le budget : ResourceQuota

Complétez `starter/quota.yaml` (`# TODO 1` à `3`), puis :

```bash
kubectl apply -f starter/quota.yaml
kubectl describe resourcequota budget
```

La colonne `Used` compte **déjà** les pods en place : le quota s'applique à tout le namespace, pas seulement aux nouveaux objets.

> 🎯 **Avant de lancer la commande suivante, prédis :** vous lancez un pod **sans aucune ressource** (pas de requests, pas de limits). Le quota a de la marge. Le pod est-il créé ?

```bash
kubectl run essai --image=busybox:1.38.0 --restart=Never -- sleep 3600
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Il est **refusé**, et le message dit pourquoi : `failed quota: budget: must specify limits.memory for: essai; requests.cpu for: essai; requests.memory for: essai`. Dès qu'un quota porte sur `requests.memory`, le cluster ne sait plus décompter un pod qui n'en déclare pas : il le rejette. Le refus a lieu à l'**admission**, avant même que le pod existe. Il n'y a donc aucun pod en erreur à inspecter : le message est dans la réponse à votre commande.
</details>

## Étape 3 — Les valeurs par défaut : LimitRange

Complétez `starter/limitrange.yaml` (`# TODO 4` et `5`), puis relancez exactement la même commande :

```bash
kubectl apply -f starter/limitrange.yaml
kubectl run essai --image=busybox:1.38.0 --restart=Never -- sleep 3600
kubectl get pod essai -o jsonpath='{.spec.containers[0].resources}'; echo
```

> ❓ **Question** : d'où viennent les ressources affichées ? Et les pods de l'API, créés **avant** la LimitRange : leurs ressources ont-elles changé ? (`kubectl get pod -l app=api -o jsonpath='{.items[0].spec.containers[0].resources}'`)

<details>
<summary>💡 La réponse</summary>

Le pod `essai` a reçu `100m` / `64Mi` de requests et `500m` / `128Mi` de limits : la LimitRange les a **écrites dans le pod** au moment de sa création. Les pods de l'API, eux, n'ont pas bougé. La LimitRange agit à l'admission, comme le quota, donc seulement sur les **nouveaux** pods. Elle évite les rejets de l'étape 2, mais ne dispense pas de déclarer des ressources réalistes : des valeurs par défaut ne connaissent pas votre application.

```bash
kubectl delete pod essai
```
</details>

## Étape 4 — Dépasser le budget

> 🎯 **Avant de lancer la commande suivante, prédis :** le quota autorise 10 pods. Vous demandez 12 réplicas de l'API. Que répond `kubectl scale` ? Combien de réplicas seront prêts, et où lirez-vous l'explication ?

```bash
kubectl scale deployment api --replicas=12
kubectl get deployment api
kubectl describe resourcequota budget | grep pods
kubectl get events --field-selector reason=FailedCreate | tail -2
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`kubectl scale` répond `scaled` **sans broncher** : il a seulement changé un nombre dans le Deployment. Ce sont ensuite les créations de pods par le **ReplicaSet** que le quota refuse. Le Deployment plafonne à `8/12` (les 2 pods de la vitrine occupent le reste). `kubectl describe deployment` signale seulement la condition `ReplicaFailure  True  FailedCreate`, sans le détail. Le détail est dans les événements du ReplicaSet : `exceeded quota: budget, requested: pods=1, used: pods=10, limited: pods=10`. C'est un réflexe d'exploitant : quand un Deployment n'atteint pas son nombre de réplicas, lire les événements du **ReplicaSet**.

```bash
kubectl scale deployment api --replicas=3
```
</details>

## Étape 5 — Les droits : ServiceAccount, Role, RoleBinding

Qui êtes-vous pour le cluster ?

```bash
kubectl auth whoami
```

Sous minikube, vous êtes `minikube-user`, membre du groupe `system:masters`, qui a **tous** les droits. Kubernetes ne gère pas de comptes de personnes : il fait confiance à un certificat, un jeton ou un fournisseur d'identité externe (OIDC). En revanche, il gère des **ServiceAccounts**, les identités des applications.

Complétez `starter/supervision.yaml` (`# TODO 6` à `10`), puis :

```bash
kubectl apply -f starter/supervision.yaml
kubectl get serviceaccount,role,rolebinding
```

> 🎯 **Avant de lancer les commandes suivantes, prédis** la réponse (`yes` ou `no`) de chacune :

```bash
SA=system:serviceaccount:telemarche:supervision
kubectl auth can-i list pods        --as=$SA
kubectl auth can-i get pods/log     --as=$SA
kubectl auth can-i delete pods      --as=$SA
kubectl auth can-i get secrets      --as=$SA
kubectl auth can-i list pods -n default --as=$SA
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`yes`, `yes`, puis `no`, `no`, `no`. RBAC n'a **pas de règle d'interdiction** : tout ce qui n'est pas explicitement accordé est refusé. Le Role ne cite ni `delete` ni `secrets`, donc ni l'un ni l'autre. Et un **Role** (comme son RoleBinding) ne vaut que dans **son** namespace : pour `default`, il faudrait un autre RoleBinding là-bas, ou une ClusterRole attribuée par un ClusterRoleBinding (à manier avec précaution : elle vaut alors partout).

`--as` est l'**usurpation d'identité** : vous testez les droits d'un autre sans son jeton. C'est le moyen le plus sûr de vérifier un RBAC avant de le confier à une application. Pour tout voir d'un coup : `kubectl auth can-i --list --as=$SA`.
</details>

Remarquez le RoleBinding : son sujet n'a pas de `namespace`. Pour un ServiceAccount, il est alors cherché dans le namespace du RoleBinding. `kubectl create rolebinding … --serviceaccount=telemarche:supervision` l'écrirait explicitement.

## Étape 6 — Du côté du pod

Le pod `supervision` porte l'identité `supervision` : Kubernetes y monte un **jeton** signé, que le pod présente à l'API server. L'outil fourni `/outils/appel` s'en sert :

```bash
kubectl exec supervision -- /outils/appel GET pods
kubectl exec supervision -- /outils/appel GET secrets
kubectl exec supervision -- /outils/appel DELETE pods/supervision
kubectl exec supervision -- /outils/appel GET pods default
```

`200` pour la lecture des pods, `403` (*Forbidden*) pour tout le reste : le pod n'a **que** les droits de son ServiceAccount, et le RBAC s'applique à un vrai jeton exactement comme à `--as`.

> ❓ **Question** : l'API et la vitrine n'appellent **jamais** l'API server. Pourtant, `kubectl get pod -l app=api -o yaml | grep -A3 serviceaccount` montre qu'elles reçoivent aussi un jeton, celui du ServiceAccount `default`. Pourquoi est-ce un risque, et quel champ du pod l'éviterait ? (Voir la documentation des ServiceAccounts : `automountServiceAccountToken`.)

## Étape 7 — Validez, puis rendez le budget

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

⚠️ Avant de passer au TP suivant, retirez le budget de votre namespace : 10 pods ne suffiraient pas, par exemple, à l'autoscaling du TP06.

```bash
kubectl delete resourcequota budget
kubectl delete limitrange defauts
```

---

## 💡 Indices

<details>
<summary><code>can-i</code> répond <code>no</code> à tout, même à <code>list pods</code></summary>

Le RoleBinding ne relie pas les bons objets. `kubectl describe rolebinding supervision-lecture` : le `Role` doit être `lecture-pods`, et le sujet le ServiceAccount `supervision`. Un nom mal orthographié n'est **pas** une erreur pour Kubernetes : un RoleBinding peut désigner un Role ou un ServiceAccount qui n'existe pas (encore).
</details>

<details>
<summary><code>get pods/log</code> répond <code>no</code> alors que <code>get pods</code> répond <code>yes</code></summary>

Les journaux sont une **sous-ressource** : `pods/log` doit figurer explicitement dans `resources`. Même chose pour `pods/exec`, et c'est heureux : le droit d'entrer dans un conteneur ne doit pas venir avec le simple droit de le voir.
</details>

<details>
<summary>Le pod <code>supervision</code> est refusé : <code>exceeded quota</code></summary>

Le quota de 10 pods est déjà atteint, sans doute par un `scale` de l'étape 4 qui n'a pas été annulé : `kubectl scale deployment api --replicas=3`, puis réappliquez.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Namespaces** : https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- **ResourceQuota** : https://kubernetes.io/docs/concepts/policy/resource-quotas/
- **LimitRange** : https://kubernetes.io/docs/concepts/policy/limit-range/
- **RBAC** : https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- **ServiceAccounts** : https://kubernetes.io/docs/concepts/security/service-accounts/
- **Bonnes pratiques RBAC** : https://kubernetes.io/docs/concepts/security/rbac-good-practices/

---

## 🚀 Pour aller plus loin

1. **Couper le jeton inutile.** Ajoutez `automountServiceAccountToken: false` aux pods de l'API et de la vitrine. Vérifiez que le jeton n'est plus monté, puis qu'elles fonctionnent toujours.
2. **Un rôle prêt à l'emploi.** Kubernetes fournit des ClusterRoles génériques : `view`, `edit`, `admin`. Attribuez `view` à `supervision` **dans le namespace** par un RoleBinding. Peut-elle lire les Secrets ? (`kubectl describe clusterrole view`.)
3. **Un accès pour un humain.** Créez un certificat client pour une utilisatrice `alice` du groupe `logistique` (CertificateSigningRequest), donnez au groupe le rôle `edit` dans un namespace `logistique`, et testez avec `--as=alice --as-group=logistique`.
4. **Le quota de l'équipe logistique.** Créez le namespace `logistique` avec un quota de 4 pods et `count/deployments.apps: "2"`. Que se passe-t-il au troisième Deployment ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
