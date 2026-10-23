#!/usr/bin/env bash
# TP07 — vérifie le Gateway « entree » (namespace traefik) et la HTTPRoute de
# Télémarché : vitrine, API, canari par en-tête et canari pondéré à 10 %.
# Les requêtes partent d'un pod client, comme celles d'un vrai client passé
# par le Service de Traefik.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"
ENTREE="http://traefik.traefik.svc"

need_cluster
k get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1 \
  && k rollout status deployment/traefik -n traefik --timeout=60s >/dev/null 2>&1 \
  || die "Gateway API ou Traefik absents : refaites l'étape 1 (ou lancez ./prerequis.sh)."

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp07-verify
# Le Gateway appartient à l'exploitant : il vit dans le namespace de Traefik.
apply_gateway() {
  local out
  if ! out="$(k apply -n traefik -f "$DIR/gateway.yaml" 2>&1)"; then
    printf "  ${RED}✗${NC} kubectl apply du Gateway a échoué :\n"; printf '%s\n' "$out" | sed 's/^/      /'
    FAIL=$((FAIL+1)); summary
  fi
  printf '  %s (namespace traefik)\n' "$out"
}
apply_gateway
apply "$DIR/00-telemarche.yaml"
apply "$DIR/route.yaml"

step "L'état de départ"
wait_rollout api 180
wait_rollout api-canari 180
wait_rollout web 120

step "Le Gateway et la route"
check "Le Gateway entree est programmé par Traefik" \
  k wait --for=condition=Programmed gateway/entree -n traefik --timeout=60s
assert_eq "Il écoute en HTTP sur le port 8000" "HTTP/8000" \
  "$(k get gateway/entree -n traefik -o jsonpath='{.spec.listeners[0].protocol}/{.spec.listeners[0].port}' 2>/dev/null || true)"
route_cond() { jp httproute/telemarche "{.status.parents[0].conditions[?(@.type==\"$1\")].status}"; }
for _ in $(seq 1 20); do [ "$(route_cond Accepted)" = "True" ] && break; sleep 2; done
assert_eq "La route est acceptée par le Gateway (Accepted)" "True" "$(route_cond Accepted)"
assert_eq "Tous ses Services existent (ResolvedRefs)" "True" "$(route_cond ResolvedRefs)"
assert_eq "Elle sert telemarche.local" "telemarche.local" "$(jp httproute/telemarche '{.spec.hostnames[0]}')"
# Votre propre route (namespace telemarche) sert peut-être déjà ce nom : à
# règles égales, la plus ancienne l'emporte. La vérification passe donc par
# un nom qui n'appartient qu'à elle.
HOTE="$NS.local"
k patch httproute/telemarche -n "$NS" --type=merge -p "{\"spec\":{\"hostnames\":[\"$HOTE\"]}}" >/dev/null

step "Le trafic, vu d'un client"
k apply -n "$NS" -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: client
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: client
      image: telemachlearning/curl:8.21.0
      command: ["sleep", "600"]
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {cpu: 100m, memory: 32Mi}
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
EOF
wait_pod_ready client 60
cli() { k exec -n "$NS" client -- curl -s -m 5 "$@" 2>/dev/null || true; }
assert_contains "/ sert la vitrine" "<title>Télémarché</title>" "$(cli -H "Host: $HOTE" "$ENTREE/")"
assert_eq "Un autre nom de domaine : 404" "404" "$(cli -o /dev/null -w '%{http_code}' -H 'Host: inconnu.local' "$ENTREE/")"
CANARI=0
for _ in 1 2 3 4 5; do
  cli -H "Host: $HOTE" -H 'X-Canari: oui' "$ENTREE/api/info" | grep -q '"version":"1.1"' && CANARI=$((CANARI+1))
done
assert_eq "Avec X-Canari: oui, toujours la 1.1 (5 sur 5)" "5" "$CANARI"
V11=0; V10=0
for _ in $(seq 1 100); do
  case "$(cli -H "Host: $HOTE" "$ENTREE/api/info")" in
    *'"version":"1.1"'*) V11=$((V11+1)) ;;
    *'"version":"1.0"'*) V10=$((V10+1)) ;;
  esac
done
check "Sans en-tête, environ 10 % de 1.1 (obtenu : $V11 sur 100, et $V10 en 1.0)" \
  test "$V11" -ge 5 -a "$V11" -le 20 -a "$((V10+V11))" -eq 100

summary
