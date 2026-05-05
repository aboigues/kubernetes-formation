# TP11 - Kubernetes Gateway API : le successeur d'Ingress

## Objectifs du TP

Ce TP vous permettra de maîtriser la Gateway API Kubernetes, successeur officiel de l'Ingress. Vous apprendrez :

- Comprendre les limites de l'Ingress et pourquoi la Gateway API le remplace
- Maîtriser le modèle de rôles (GatewayClass, Gateway, HTTPRoute)
- Implémenter des stratégies de routage avancées (header, chemin, poids)
- Réaliser un déploiement canary sans changer votre code applicatif
- Configurer la terminaison TLS au niveau du Gateway
- Comprendre les différences avec Ingress et migrer des manifests existants

**Durée estimée :** 5-7 heures
**Niveau :** Intermédiaire à Avancé

## Prérequis

- Avoir complété le TP8 (réseau Kubernetes et Services)
- Cluster Kubernetes ≥ 1.28 (Gateway API v1 stable)
- kubectl installé et configuré
- helm installé (pour déployer l'implémentation)
- Notions de DNS, HTTP et TLS

## Table des matières

- [Partie 1 : Pourquoi remplacer l'Ingress ?](#partie-1--pourquoi-remplacer-lingress-)
- [Partie 2 : Architecture et modèle de rôles](#partie-2--architecture-et-modèle-de-rôles)
- [Partie 3 : Installation et mise en place](#partie-3--installation-et-mise-en-place)
- [Partie 4 : GatewayClass et Gateway](#partie-4--gatewayclass-et-gateway)
- [Partie 5 : HTTPRoute — routage basique](#partie-5--httproute--routage-basique)
- [Partie 6 : Routage avancé](#partie-6--routage-avancé)
- [Partie 7 : Traffic splitting et canary deployments](#partie-7--traffic-splitting-et-canary-deployments)
- [Partie 8 : TLS et sécurité](#partie-8--tls-et-sécurité)
- [Partie 9 : Migration depuis Ingress](#partie-9--migration-depuis-ingress)
- [Exercices pratiques](#exercices-pratiques)

---

## Partie 1 : Pourquoi remplacer l'Ingress ?

### 1.1 Les limites de l'Ingress

L'Ingress a été introduit en Kubernetes 1.1 et a très bien servi pendant des années. Mais il souffre de plusieurs limitations structurelles.

**L'annotation hell**

Pour faire du routage par header avec nginx Ingress, il fallait écrire :

```yaml
annotations:
  nginx.ingress.kubernetes.io/canary: "true"
  nginx.ingress.kubernetes.io/canary-weight: "20"
  nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"
```

Ces annotations sont propres à nginx. La même configuration avec Traefik est différente. Résultat : vous êtes verrouillé sur votre implémentation.

**Pas de RBAC natif**

Avec l'Ingress, n'importe quel développeur peut modifier les règles de routage globales du cluster. Il n'existe pas de séparation native entre la configuration de l'infrastructure (qui écoute sur quel port, quel certificat) et les règles applicatives.

**Expressivité limitée**

L'Ingress ne supporte nativement que :
- Le routage par hostname
- Le routage par chemin (PathPrefix)

Tout le reste (header matching, traffic splitting, redirection, réécriture) passe par des annotations non standardisées.

### 1.2 Ce que la Gateway API apporte

| Fonctionnalité | Ingress | Gateway API |
|---|---|---|
| Routage par chemin | ✅ via annotation | ✅ natif |
| Routage par header | ⚠️ vendor annotation | ✅ natif |
| Traffic splitting | ⚠️ vendor annotation | ✅ natif (weights) |
| Réécriture d'URL | ⚠️ vendor annotation | ✅ natif (filtres) |
| TLS | ✅ basique | ✅ avancé |
| RBAC natif | ❌ | ✅ via modèle de rôles |
| Protocoles | HTTP/HTTPS | HTTP, HTTPS, gRPC, TCP, TLS |
| Portabilité | ❌ vendor lock-in | ✅ API standardisée |

**Statut de stabilité :**
- `GatewayClass`, `Gateway`, `HTTPRoute` → **GA (v1)** depuis Kubernetes 1.28
- `GRPCRoute` → **GA (v1)** depuis Kubernetes 1.31
- `TCPRoute`, `TLSRoute` → **Expérimental** (v1alpha2)

---

## Partie 2 : Architecture et modèle de rôles

### 2.1 Trois personas, trois ressources

La Gateway API est conçue autour d'une séparation claire des responsabilités :

```
┌─────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE PROVIDER                       │
│          (équipe plateforme, cloud provider)                     │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │  GatewayClass                                            │  │
│   │  - Définit quel controller gère les Gateways             │  │
│   │  - Cluster-scoped (pas de namespace)                     │  │
│   │  - Ex: nginx, envoy, cilium, istio                       │  │
│   └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CLUSTER OPERATOR                            │
│          (SRE, équipe ops)                                       │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │  Gateway                                                 │  │
│   │  - Configure les listeners (port, protocole, TLS)        │  │
│   │  - Définit quels namespaces peuvent attacher des routes  │  │
│   │  - Namespaced (souvent dans un namespace dédié)          │  │
│   └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    APPLICATION DEVELOPER                         │
│          (équipes applicatives)                                  │
│                                                                  │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│   │  HTTPRoute   │  │  GRPCRoute   │  │  TCPRoute (alpha)    │  │
│   │  - Règles    │  │  - gRPC      │  │  - TCP/TLS           │  │
│   │    de routage│  │    routing   │  │    passthrough       │  │
│   └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Flux d'une requête

```
Client HTTP
    │
    ▼
┌───────────────────────────────────────────────────────────┐
│  Gateway (Load Balancer)                                  │
│  listener: port 80 (HTTP)                                 │
│  listener: port 443 (HTTPS) ← terminaison TLS ici        │
└───────────────────────────────────────────────────────────┘
    │
    │  parentRef → Gateway
    ▼
┌───────────────────────────────────────────────────────────┐
│  HTTPRoute                                                │
│  rules:                                                   │
│    - match: path=/api/*  → backend-v1:80                 │
│    - match: header X-Beta=true → backend-v2:80           │
│    - default            → backend-v1:80 (90%) +          │
│                            backend-v2:80 (10%)           │
└───────────────────────────────────────────────────────────┘
    │
    ▼
Service Kubernetes → Pods
```

---

## Partie 3 : Installation et mise en place

### 3.1 Installer les CRDs Gateway API

Les CRDs sont indépendants de l'implémentation. Ils définissent les types GatewayClass, Gateway, HTTPRoute, etc.

```bash
# Canal standard (GatewayClass, Gateway, HTTPRoute, GRPCRoute)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# Vérifier les CRDs installées
kubectl get crd | grep gateway.networking.k8s.io
```

Vous devriez voir :
```
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

### 3.2 Installer une implémentation

La Gateway API est une spécification — il faut une implémentation concrète. Deux options populaires :

**Option A : nginx Gateway Fabric (recommandé pour ce TP)**

nginx Gateway Fabric est le successeur officiel du nginx Ingress Controller.

```bash
# Installer nginx Gateway Fabric
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/default/deploy.yaml

# Vérifier l'installation
kubectl get pods -n nginx-gateway
kubectl get gatewayclass nginx
```

**Option B : Envoy Gateway**

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.3.0 \
  -n envoy-gateway-system \
  --create-namespace

# Vérifier
kubectl get pods -n envoy-gateway-system
kubectl get gatewayclass eg
```

**Option C : Cilium (si utilisé comme CNI)**

```bash
# Activer Gateway API dans Cilium
helm upgrade cilium cilium/cilium \
  --set gatewayAPI.enabled=true

kubectl get gatewayclass cilium
```

### 3.3 Préparer l'environnement de TP

```bash
# Créer le namespace de travail
kubectl apply -f examples/01-namespace.yaml

# Vérifier
kubectl get namespace tp11
```

---

## Partie 4 : GatewayClass et Gateway

### 4.1 GatewayClass

La `GatewayClass` est l'équivalent de l'`IngressClass`. Elle est cluster-scoped et désigne quel controller prend en charge les Gateways.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: gateway.nginx.org/nginx-gateway-controller
```

```bash
# Appliquer
kubectl apply -f examples/02-gatewayclass.yaml

# Vérifier le statut
kubectl get gatewayclass nginx
# ACCEPTED = le controller a pris en charge la GatewayClass

kubectl describe gatewayclass nginx
```

**Points clés :**
- Une seule `GatewayClass` par implémentation
- Le champ `controllerName` est défini par le fabricant de l'implémentation
- `ACCEPTED` dans `STATUS` confirme que le controller est actif

### 4.2 Gateway

La `Gateway` configure ce que le load balancer doit écouter : ports, protocoles, et restrictions d'accès.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: tp11
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same     # Seules les routes du même namespace peuvent s'attacher
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: tls-secret
    allowedRoutes:
      namespaces:
        from: Same
```

**La politique `allowedRoutes` :**

| Valeur | Comportement |
|---|---|
| `Same` | Seul le namespace du Gateway peut attacher des routes |
| `All` | Tous les namespaces peuvent attacher des routes |
| `Selector` | Seuls les namespaces matchant les labels peuvent attacher des routes |

```bash
# Appliquer
kubectl apply -f examples/03-gateway.yaml

# Vérifier (PROGRAMMED = infrastructure provisionnée)
kubectl get gateway -n tp11
kubectl describe gateway main-gateway -n tp11

# Obtenir l'IP externe du Gateway
kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}'
```

**Exercice 4.1 :**

```bash
# Décrire le Gateway et identifier dans le statut :
# 1. L'adresse IP assignée
# 2. Les listeners actifs
# 3. Le nombre de routes attachées
kubectl describe gateway main-gateway -n tp11
```

---

## Partie 5 : HTTPRoute — routage basique

### 5.1 Structure d'une HTTPRoute

L'HTTPRoute est la ressource que le développeur applicatif manipule au quotidien. Elle s'attache à un Gateway via `parentRefs`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ma-route
  namespace: tp11
spec:
  parentRefs:
  - name: main-gateway      # Gateway cible
    namespace: tp11
    sectionName: http        # Listener spécifique (optionnel)
  hostnames:
  - "app.example.com"        # Filtrage par hostname (optionnel)
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: backend-v1
      port: 80
```

### 5.2 Types de matching de chemin

| Type | Exemple | Comportement |
|---|---|---|
| `Exact` | `/api/users` | Correspond exactement à ce chemin |
| `PathPrefix` | `/api` | Correspond à `/api`, `/api/users`, `/api/v2/...` |
| `RegularExpression` | `/api/v[0-9]+` | Expression régulière (support selon implémentation) |

### 5.3 Déployer les backends et la route basique

```bash
# Déployer les services backend
kubectl apply -f examples/04-backend-v1.yaml
kubectl apply -f examples/05-backend-v2.yaml

# Vérifier les pods
kubectl get pods -n tp11
kubectl get services -n tp11

# Appliquer la route basique
kubectl apply -f examples/06-httproute-basic.yaml

# Vérifier le statut de la route
kubectl get httproute -n tp11
kubectl describe httproute basic-routing -n tp11
```

**Tester le routage :**

```bash
# Récupérer l'IP du Gateway
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Tester les différents chemins
curl -H "Host: app.example.com" http://$GW_IP/api
curl -H "Host: app.example.com" http://$GW_IP/web
curl -H "Host: app.example.com" http://$GW_IP/
```

**Exercice 5.1 : Observer le statut d'attachement**

```bash
# Une route bien configurée doit afficher "Accepted: True" et "ResolvedRefs: True"
kubectl describe httproute basic-routing -n tp11 | grep -A 5 "Conditions"

# Que se passe-t-il si vous référencez un Service qui n'existe pas ?
# Modifier temporairement backendRefs pour pointer vers "inexistant:80"
# Observer le changement de statut
```

---

## Partie 6 : Routage avancé

### 6.1 Routage par header

Le routage par header permet de l'A/B testing ou du routage conditionnel sans toucher à l'infrastructure.

```yaml
rules:
- matches:
  - headers:
    - name: X-Version
      value: v2
  backendRefs:
  - name: backend-v2
    port: 80
- backendRefs:          # Règle par défaut (pas de match = toutes les autres requêtes)
  - name: backend-v1
    port: 80
```

**Important :** Les règles sont évaluées dans l'ordre. La première qui matche gagne.

```bash
kubectl apply -f examples/07-httproute-header-routing.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Sans header → v1
curl -H "Host: ab.example.com" http://$GW_IP/

# Avec header → v2
curl -H "Host: ab.example.com" -H "X-Version: v2" http://$GW_IP/
```

### 6.2 Autres types de matching

**Par query parameter :**

```yaml
matches:
- queryParams:
  - name: debug
    value: "true"
```

**Par méthode HTTP :**

```yaml
matches:
- method: POST
```

**Combinaison de critères (ET logique) :**

```yaml
matches:
- path:
    type: PathPrefix
    value: /api
  headers:
  - name: X-Env
    value: staging
  method: POST
```

**Plusieurs entrées dans `matches` (OU logique) :**

```yaml
matches:
- path:
    type: Exact
    value: /health
- path:
    type: Exact
    value: /ping
```

### 6.3 Filtres (transformations)

**Réécriture de chemin :**

```yaml
filters:
- type: URLRewrite
  urlRewrite:
    path:
      type: ReplacePrefixMatch
      replacePrefixMatch: /api    # /old-api/users → /api/users
```

**Redirection :**

```yaml
filters:
- type: RequestRedirect
  requestRedirect:
    scheme: https
    statusCode: 301
```

**Ajout de headers :**

```yaml
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    add:
    - name: X-Forwarded-Source
      value: gateway
    remove:
    - X-Internal-Debug
```

```bash
kubectl apply -f examples/09-httproute-rewrite.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Tester la réécriture : /old-api → /api
curl -v -H "Host: rewrite.example.com" http://$GW_IP/old-api/users

# Tester la redirection
curl -v -H "Host: rewrite.example.com" http://$GW_IP/redirect
```

**Exercice 6.1 : Combiner les filtres**

Créer une HTTPRoute qui :
1. Accepte les requêtes sur `/legacy/*`
2. Réécrit le chemin vers `/v2/*`
3. Ajoute le header `X-Migrated: true`

---

## Partie 7 : Traffic splitting et canary deployments

### 7.1 Le concept de weight

Chaque `backendRef` accepte un champ `weight`. La somme des poids dans une règle détermine la distribution du trafic.

```yaml
rules:
- backendRefs:
  - name: backend-v1
    port: 80
    weight: 90    # 90/(90+10) = 90% du trafic
  - name: backend-v2
    port: 80
    weight: 10    # 10/(90+10) = 10% du trafic
```

Si `weight` est omis, sa valeur par défaut est `1`.

### 7.2 Déploiement canary progressif

Le canary deployment consiste à envoyer un faible pourcentage du trafic vers la nouvelle version, observer les métriques, puis progressivement augmenter.

```
Étape 1 : 100%/0%   → baseline, tout sur v1
Étape 2 :  80%/20%  → canary early adopters
Étape 3 :  50%/50%  → validation à mi-chemin
Étape 4 :   0%/100% → bascule complète vers v2
Rollback :  si anomalie, revenir à 100%/0% immédiatement
```

```bash
kubectl apply -f examples/08-httproute-canary.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Simuler 20 requêtes et compter la distribution
for i in $(seq 1 20); do
  curl -s -H "Host: canary.example.com" http://$GW_IP/ | grep -o 'v[12]'
done | sort | uniq -c
# Résultat attendu : ~18 v1, ~2 v2

# Modifier le weight à 50/50
kubectl patch httproute canary-routing -n tp11 --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'

# Tester à nouveau
for i in $(seq 1 20); do
  curl -s -H "Host: canary.example.com" http://$GW_IP/ | grep -o 'v[12]'
done | sort | uniq -c
```

### 7.3 Combinaison canary + header routing

Une stratégie plus fine : exposer la nouvelle version uniquement aux utilisateurs qui ont opté pour le programme bêta.

```yaml
rules:
# Les beta-testeurs voient v2
- matches:
  - headers:
    - name: X-Beta-User
      value: "true"
  backendRefs:
  - name: backend-v2
    port: 80

# 10% du reste voit aussi v2 (canary passif)
- backendRefs:
  - name: backend-v1
    port: 80
    weight: 90
  - name: backend-v2
    port: 80
    weight: 10
```

**Exercice 7.1 : Blue/Green avec bascule instantanée**

```bash
# Déployer deux environnements : blue (v1) et green (v2)
# Créer une HTTPRoute qui envoie tout vers blue

# Pour basculer vers green, modifier le weight :
kubectl patch httproute <nom-route> -n tp11 --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":0},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":100}]'

# La bascule est quasi-instantanée (pas de redéploiement nécessaire)
```

---

## Partie 8 : TLS et sécurité

### 8.1 Terminaison TLS

La terminaison TLS se configure au niveau du `Gateway`, pas de la route. Le certificat est référencé depuis un Secret Kubernetes.

```bash
# Créer un certificat auto-signé pour les tests
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=secure.example.com" \
  -addext "subjectAltName=DNS:secure.example.com"

# Créer le Secret
kubectl create secret tls tls-secret \
  --cert=tls.crt \
  --key=tls.key \
  -n tp11

# Vérifier
kubectl get secret tls-secret -n tp11
```

Le listener HTTPS est déjà défini dans `examples/03-gateway.yaml`. L'HTTPRoute TLS s'attache au listener `https` via `sectionName` :

```bash
kubectl apply -f examples/10-httproute-tls.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Tester HTTPS (--insecure car certificat auto-signé)
curl -k -H "Host: secure.example.com" https://$GW_IP/
```

### 8.2 ReferenceGrant : accès cross-namespace

Par défaut, un `Gateway` dans `namespace-a` ne peut pas référencer un `Secret` dans `namespace-b`. Le `ReferenceGrant` permet d'autoriser explicitement cet accès.

```yaml
# Dans le namespace qui contient le Secret
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-gateway-tls
  namespace: cert-store          # Namespace du Secret
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: Gateway
    namespace: infra             # Namespace du Gateway autorisé
  to:
  - group: ""
    kind: Secret
    name: wildcard-tls           # Nom du Secret autorisé
```

Le même mécanisme s'applique quand une HTTPRoute dans `app-namespace` veut cibler un Service dans `shared-services`.

### 8.3 Redirect HTTP → HTTPS automatique

```yaml
# Route sur le listener HTTP qui redirige tout vers HTTPS
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-redirect
  namespace: tp11
spec:
  parentRefs:
  - name: main-gateway
    namespace: tp11
    sectionName: http         # Listener HTTP
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
```

---

## Partie 9 : Migration depuis Ingress

### 9.1 Correspondance des concepts

| Ingress | Gateway API | Notes |
|---|---|---|
| `IngressClass` | `GatewayClass` | Cluster-scoped dans les deux cas |
| `Ingress` | `Gateway` + `HTTPRoute` | Séparation infrastructure/applicatif |
| `spec.rules[].host` | `spec.hostnames` | Dans HTTPRoute |
| `spec.rules[].http.paths` | `spec.rules[].matches` | Même logique |
| `spec.tls` | Listener `HTTPS` dans Gateway | TLS géré au niveau Gateway |
| annotations vendor | Filtres natifs | Portables entre implémentations |

### 9.2 Exemple de migration

**Avant (Ingress) :**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /api/$2
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /old-api(/|$)(.*)
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 80
```

**Après (Gateway API) :**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: default
spec:
  parentRefs:
  - name: main-gateway
    namespace: infra
  hostnames:
  - "app.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /old-api
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /api
    backendRefs:
    - name: backend
      port: 80
```

**Ce qui change :**
- Plus d'annotation `rewrite-target` : le filtre `URLRewrite` est portable
- La configuration TLS sort de l'Ingress et va dans le Gateway
- L'opérateur contrôle la politique d'accès via `allowedRoutes`

### 9.3 Coexistence Ingress et Gateway API

Pendant la migration, les deux peuvent coexister dans le même cluster. Un Service peut être ciblé simultanément par un Ingress existant et une HTTPRoute.

```bash
# Vérifier les deux types de ressources
kubectl get ingress -A
kubectl get httproute -A
```

---

## Exercices pratiques

### Exercice 1 : Gateway simple avec deux services

**Objectif :** Exposer un frontend et une API sur le même hostname avec des chemins distincts.

```bash
kubectl apply -f exercices/exercice-1-simple-gateway.yaml
```

Compléter les sections `<COMPLÉTER>` dans le fichier puis valider :

```bash
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Doit répondre "frontend"
curl -H "Host: exercice1.example.com" http://$GW_IP/

# Doit répondre {"service":"api","version":"1.0"}
curl -H "Host: exercice1.example.com" http://$GW_IP/api/
```

**Questions :**
1. Que se passe-t-il si vous intervertissez l'ordre des règles ?
2. Comment restreindre l'accès à `/api/*` aux seules requêtes avec le header `Authorization` ?

### Exercice 2 : Canary deployment progressif

**Objectif :** Simuler les 3 étapes d'un déploiement canary en modifiant uniquement les weights.

```bash
kubectl apply -f exercices/exercice-2-canary-deployment.yaml
```

```bash
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Script de test de distribution
check_distribution() {
  local total=20
  echo "=== Distribution sur $total requêtes ==="
  for i in $(seq 1 $total); do
    curl -s -H "Host: canary-ex.example.com" http://$GW_IP/ 2>/dev/null
  done | sort | uniq -c
}

# Étape 1 : 100% stable (weights: 100/0)
check_distribution

# Étape 2 : 80% stable, 20% canary — modifier le fichier et appliquer
# kubectl apply -f exercices/exercice-2-canary-deployment.yaml
check_distribution

# Étape 3 : 100% canary (weights: 0/100)
check_distribution
```

**Questions :**
1. La distribution est-elle exactement 80/20 ou approximative ? Pourquoi ?
2. Comment implémenteriez-vous un rollback automatique si les erreurs dépassent 5% ?

### Exercice 3 : HTTPRoute cross-namespace avec ReferenceGrant

**Objectif :** Permettre à une HTTPRoute dans `team-a` de cibler un Service dans `shared-services`.

```bash
# Créer les namespaces
kubectl create namespace team-a
kubectl create namespace shared-services

# Déployer le service partagé dans shared-services
kubectl run shared-api --image=nginx:1.27-alpine -n shared-services --port=80
kubectl expose pod shared-api --port=80 -n shared-services

# TODO : Créer le ReferenceGrant dans shared-services
# TODO : Créer l'HTTPRoute dans team-a qui cible shared-api dans shared-services
```

**Questions :**
1. Que se passe-t-il si vous appliquez l'HTTPRoute sans le ReferenceGrant ?
2. À quoi sert la granularité `name` dans le ReferenceGrant ?

---

## Nettoyage

```bash
# Supprimer toutes les ressources du TP
kubectl delete namespace tp11
kubectl delete namespace team-a
kubectl delete namespace shared-services

# Supprimer la GatewayClass (cluster-scoped)
kubectl delete gatewayclass nginx

# Optionnel : désinstaller l'implémentation
kubectl delete -f https://raw.githubusercontent.com/nginxinc/nginx-gateway-fabric/v1.5.1/deploy/default/deploy.yaml

# Supprimer les CRDs Gateway API
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

---

## Récapitulatif

| Concept | Ressource | Qui la gère |
|---|---|---|
| Type d'implémentation | `GatewayClass` | Infrastructure provider |
| Listeners (ports, TLS) | `Gateway` | Cluster operator |
| Règles de routage HTTP | `HTTPRoute` | Développeur applicatif |
| Règles gRPC | `GRPCRoute` | Développeur applicatif |
| Autorisation cross-namespace | `ReferenceGrant` | Owner du namespace cible |

**Points clés à retenir :**
- La Gateway API est **stable (GA)** depuis Kubernetes 1.28 — utilisable en production
- Le **traffic splitting natif** (`weight`) remplace les annotations canary vendor-specific
- Les **filtres** (`URLRewrite`, `RequestRedirect`, `RequestHeaderModifier`) sont portables entre implémentations
- `allowedRoutes` sur le Gateway implémente le RBAC réseau sans configuration RBAC supplémentaire
- Un même `Service` peut être ciblé par plusieurs HTTPRoutes simultanément

## Ressources

- [Kubernetes Gateway API — Documentation officielle](https://gateway-api.sigs.k8s.io/)
- [Guide de migration depuis Ingress](https://gateway-api.sigs.k8s.io/guides/migrating-from-ingress/)
- [nginx Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/)
- [Envoy Gateway](https://gateway.envoyproxy.io/)
- [Implementations disponibles](https://gateway-api.sigs.k8s.io/implementations/)
