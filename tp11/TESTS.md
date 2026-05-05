# Guide de validation du TP11 - Kubernetes Gateway API

Ce document fournit un guide complet pour tester et valider tous les exercices du TP11.

## Prérequis

- Cluster Kubernetes ≥ 1.28
- CRDs Gateway API installées (standard channel v1.2.1+)
- Une implémentation active (nginx Gateway Fabric, Envoy Gateway, ou Cilium)
- kubectl installé et configuré

## Vérification de l'environnement

### 1. Vérifier les CRDs Gateway API

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

**✅ Attendu :** au minimum ces 5 CRDs présentes :
```
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
grpcroutes.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
referencegrants.gateway.networking.k8s.io
```

### 2. Vérifier l'implémentation (nginx Gateway Fabric)

```bash
kubectl get pods -n nginx-gateway
kubectl get gatewayclass nginx
```

**✅ Attendu :**
- Pods `nginx-gateway-*` en `Running`
- GatewayClass `nginx` avec `ACCEPTED: True`

### 3. Préparer l'environnement

```bash
kubectl apply -f examples/01-namespace.yaml
kubectl get namespace tp11
```

---

## Tests Partie 4 : GatewayClass et Gateway

### Test 4.1 : Créer la GatewayClass

```bash
kubectl apply -f examples/02-gatewayclass.yaml
kubectl get gatewayclass nginx
```

**✅ Attendu :** `ACCEPTED: True`

```bash
# Si ACCEPTED reste False
kubectl describe gatewayclass nginx | grep -A 5 "Conditions"
# Vérifier que le controller est bien en cours d'exécution
```

### Test 4.2 : Créer le Gateway

```bash
kubectl apply -f examples/03-gateway.yaml
kubectl get gateway -n tp11
```

**✅ Attendu :** `PROGRAMMED: True` et une adresse IP dans la colonne `ADDRESS`

```bash
# Récupérer l'IP pour les tests suivants
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GW_IP"

# Inspecter les listeners
kubectl describe gateway main-gateway -n tp11 | grep -A 20 "Listeners"
```

---

## Tests Partie 5 : HTTPRoute basique

### Test 5.1 : Déployer les backends

```bash
kubectl apply -f examples/04-backend-v1.yaml
kubectl apply -f examples/05-backend-v2.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod -l app=backend -n tp11 --timeout=90s

# Vérifier
kubectl get pods -n tp11
kubectl get services -n tp11
```

**✅ Attendu :** pods `backend-v1-*` et `backend-v2-*` en `Running`

### Test 5.2 : Routage par chemin

```bash
kubectl apply -f examples/06-httproute-basic.yaml
kubectl get httproute -n tp11

# Vérifier l'attachement au Gateway
kubectl describe httproute basic-routing -n tp11 | grep -A 10 "Conditions"
```

**✅ Attendu :** `Accepted: True` et `ResolvedRefs: True`

```bash
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Test chemin /api
curl -s -H "Host: app.example.com" http://$GW_IP/api
# ✅ Attendu : réponse de backend-v1

# Test chemin /web
curl -s -H "Host: app.example.com" http://$GW_IP/web
# ✅ Attendu : réponse de backend-v1

# Test chemin /
curl -s -H "Host: app.example.com" http://$GW_IP/
# ✅ Attendu : réponse de backend-v1
```

---

## Tests Partie 6 : Routage avancé

### Test 6.1 : Routage par header (A/B testing)

```bash
kubectl apply -f examples/07-httproute-header-routing.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Sans header X-Version : doit aller vers v1
curl -s -H "Host: ab.example.com" http://$GW_IP/
# ✅ Attendu : "v1"

# Avec header X-Version: v2 : doit aller vers v2
curl -s -H "Host: ab.example.com" -H "X-Version: v2" http://$GW_IP/
# ✅ Attendu : "v2"

# Header avec valeur différente : doit aller vers v1
curl -s -H "Host: ab.example.com" -H "X-Version: v1" http://$GW_IP/
# ✅ Attendu : "v1" (la règle header match uniquement "v2")
```

### Test 6.2 : Filtres — réécriture de chemin et redirection

```bash
kubectl apply -f examples/09-httproute-rewrite.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Test réécriture : /old-api/* doit être réécrit en /api/*
curl -v -H "Host: rewrite.example.com" http://$GW_IP/old-api/users 2>&1 | grep -E "< HTTP|Location|v1"
# ✅ Attendu : réponse 200, la requête est reçue sur /api/users côté backend

# Test redirection
curl -v -H "Host: rewrite.example.com" http://$GW_IP/redirect 2>&1 | grep -E "< HTTP|Location"
# ✅ Attendu : HTTP 301, Location: https://rewrite.example.com/redirect
```

---

## Tests Partie 7 : Traffic splitting

### Test 7.1 : Distribution canary 90/10

```bash
kubectl apply -f examples/08-httproute-canary.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

echo "=== Test distribution 90/10 (30 requêtes) ==="
for i in $(seq 1 30); do
  curl -s -H "Host: canary.example.com" http://$GW_IP/ 2>/dev/null || echo "error"
done | grep -o 'v[12]' | sort | uniq -c
```

**✅ Attendu :** environ 27 réponses v1, 3 réponses v2 (±3 de tolérance)

### Test 7.2 : Bascule progressive

```bash
GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

check_distribution() {
  local label=$1
  echo "=== $label ==="
  for i in $(seq 1 20); do
    curl -s -H "Host: canary.example.com" http://$GW_IP/ 2>/dev/null
  done | grep -o 'v[12]' | sort | uniq -c
}

# 50/50
kubectl patch httproute canary-routing -n tp11 --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}]'
sleep 2
check_distribution "50% v1 / 50% v2"

# Bascule complète vers v2
kubectl patch httproute canary-routing -n tp11 --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":0},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":100}]'
sleep 2
check_distribution "0% v1 / 100% v2"

# Rollback vers v1
kubectl patch httproute canary-routing -n tp11 --type='json' \
  -p='[{"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":100},
       {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":0}]'
sleep 2
check_distribution "Rollback : 100% v1"
```

---

## Tests Partie 8 : TLS

### Test 8.1 : Terminaison TLS

```bash
# Créer le certificat auto-signé
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=secure.example.com" 2>/dev/null

kubectl create secret tls tls-secret \
  --cert=/tmp/tls.crt \
  --key=/tmp/tls.key \
  -n tp11 --dry-run=client -o yaml | kubectl apply -f -

# Appliquer la route TLS
kubectl apply -f examples/10-httproute-tls.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Tester HTTPS
curl -k -s -H "Host: secure.example.com" https://$GW_IP/
# ✅ Attendu : réponse de backend-v1

# Vérifier le certificat
echo | openssl s_client -connect $GW_IP:443 -servername secure.example.com 2>/dev/null | \
  openssl x509 -noout -subject
# ✅ Attendu : subject=CN=secure.example.com
```

---

## Tests des exercices

### Exercice 1 : Gateway simple

```bash
kubectl apply -f exercices/exercice-1-simple-gateway.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Test frontend
RESULT=$(curl -s -H "Host: exercice1.example.com" http://$GW_IP/)
if echo "$RESULT" | grep -q "frontend"; then
  echo "✅ Frontend OK"
else
  echo "❌ Frontend KO — réponse : $RESULT"
fi

# Test API
RESULT=$(curl -s -H "Host: exercice1.example.com" http://$GW_IP/api/)
if echo "$RESULT" | grep -q "api"; then
  echo "✅ API OK"
else
  echo "❌ API KO — réponse : $RESULT"
fi
```

### Exercice 2 : Canary deployment

```bash
kubectl apply -f exercices/exercice-2-canary-deployment.yaml

GW_IP=$(kubectl get gateway main-gateway -n tp11 -o jsonpath='{.status.addresses[0].value}')

# Étape 1 : tout en stable
echo "Étape 1 — attendu : 100% stable"
for i in $(seq 1 10); do
  curl -s -H "Host: canary-ex.example.com" http://$GW_IP/ 2>/dev/null
done | sort | uniq -c

# ✅ Attendu : 10 "stable", 0 "canary"
```

---

## Diagnostic et dépannage

### Route non attachée au Gateway

```bash
kubectl describe httproute <nom-route> -n tp11 | grep -A 15 "Parents"
```

Causes fréquentes :
- `sectionName` incorrect (ne correspond pas à un listener du Gateway)
- Le namespace de la route n'est pas autorisé par `allowedRoutes` du Gateway
- La GatewayClass n'est pas en `ACCEPTED: True`

### Service non résolu (ResolvedRefs: False)

```bash
kubectl describe httproute <nom-route> -n tp11 | grep -A 5 "ResolvedRefs"
```

Causes fréquentes :
- Le Service référencé n'existe pas dans le namespace
- Le port référencé ne correspond pas au port exposé par le Service
- Cross-namespace sans `ReferenceGrant`

### Gateway non programmed

```bash
kubectl describe gateway main-gateway -n tp11 | grep -A 10 "Conditions"
kubectl get events -n tp11 --sort-by='.lastTimestamp'
```

### Tester la connectivité réseau depuis un pod

```bash
kubectl run debug --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
  --rm -it -n tp11 -- sh

# Dans le pod :
nslookup backend-v1.tp11.svc.cluster.local
wget -qO- http://backend-v1.tp11.svc.cluster.local/
```

---

## Résumé des validations

| Partie | Test | Validation |
|---|---|---|
| 4.1 | GatewayClass | `ACCEPTED: True` |
| 4.2 | Gateway | `PROGRAMMED: True` + IP assignée |
| 5.2 | HTTPRoute basique | `Accepted: True` + `ResolvedRefs: True` |
| 6.1 | Routage par header | v2 avec header, v1 sans |
| 6.2 | URLRewrite | /old-api → /api transparent |
| 7.1 | Traffic splitting | Distribution ≈ 90%/10% |
| 7.2 | Bascule canary | Rollback en < 2s |
| 8.1 | TLS | HTTPS opérationnel, CN correct |
| Ex.1 | Exercice 1 | frontend sur /, api sur /api |
| Ex.2 | Exercice 2 | Distribution correcte à chaque étape |
