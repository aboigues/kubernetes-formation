#!/usr/bin/env bash
# TP13 — vérifie la supervision de Télémarché avec le vrai Prometheus : les
# pods de l'API sont collectés, leurs métriques arrivent, les règles sont
# chargées, et les deux alertes SONNENT quand on provoque leur panne.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"
PROM="/api/v1/namespaces/monitoring/services/http:monitoring-kube-prometheus-prometheus:9090/proxy"

need_cluster
k get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 \
  && k rollout status statefulset/prometheus-monitoring-kube-prometheus-prometheus -n monitoring --timeout=60s >/dev/null 2>&1 \
  || die "kube-prometheus-stack absent du namespace monitoring : refaites l'étape 1 (ou lancez ./prerequis.sh)."

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp13-verify
apply "$DIR"
apply "$HERE/outils/tableau-de-bord.yaml"

# Une requête PromQL ; affiche la première valeur, ou rien.
promql() {
  local q; q="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  k get --raw "$PROM/api/v1/query?query=$q" 2>/dev/null \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null || true
}
# État d'une alerte pour ce namespace : firing, pending, ou rien.
alerte() {
  k get --raw "$PROM/api/v1/alerts" 2>/dev/null | python3 -c '
import json,sys
etats=[a["state"] for a in json.load(sys.stdin)["data"]["alerts"]
       if a["labels"].get("alertname")==sys.argv[1] and a["labels"].get("namespace")==sys.argv[2]]
print("firing" if "firing" in etats else (etats[0] if etats else ""))' "$1" "$NS" 2>/dev/null || true
}
attendre() {   # attendre DESCRIPTION SECONDES COMMANDE… : réessaie jusqu'au succès
  local desc="$1" t="$2" i=0; shift 2
  until "$@" >/dev/null 2>&1; do
    i=$((i+10)); sleep 10
    [ "$i" -ge "$t" ] && { printf "  ${RED}✗${NC} %s (pas après %ss)\n" "$desc" "$t"; FAIL=$((FAIL+1)); return 1; }
  done
  printf "  ${GREEN}✓${NC} %s (%ss)\n" "$desc" "$i"; PASS=$((PASS+1))
}

step "La collecte"
wait_rollout api 180
wait_rollout web 120
collectes() { [ "$(promql "sum(up{namespace=\"$NS\",service=\"api\"})")" = 3 ]; }
attendre "Prometheus collecte les 3 pods de l'API" 180 collectes || true
for _ in $(seq 1 30); do svc_get web 80 /api/products >/dev/null || true; done
# Filtrer sur la route : les probes du kubelet (/healthz, /ready) sont aussi des 200.
mesure() { [ -n "$(promql "sum(telemarche_http_requests_total{namespace=\"$NS\",route=\"GET /api/products\",code=\"200\"}) >= 30")" ]; }
attendre "Les 30 appels à /api/products sont comptés, par route et par code" 120 mesure || true

step "Les règles d'alerte"
# Les règles de TOUT le cluster sont listées, celles d'un passage précédent
# comprises : ne retenir que celles de CETTE PrometheusRule. Le fichier généré
# par l'opérateur porte son UID : « <namespace>-<nom>-<uid>.yaml ».
UID_REGLES="$(jp prometheusrule/telemarche '{.metadata.uid}')"
regles() {
  k get --raw "$PROM/api/v1/rules" 2>/dev/null | python3 -c '
import json,sys
ok=any(r["name"]==sys.argv[1] for g in json.load(sys.stdin)["data"]["groups"]
       if g["file"].endswith("-"+sys.argv[2]+".yaml") for r in g["rules"])
sys.exit(0 if ok else 1)' "$1" "$UID_REGLES"
}
attendre "ConteneurRedemarreEnBoucle est chargée" 90 regles ConteneurRedemarreEnBoucle || true
attendre "TelemarcheApiIndisponible est chargée" 90 regles TelemarcheApiIndisponible || true

step "Les alertes sonnent"
apply "$HERE/pannes/stock.yaml"
sonne() { [ "$(alerte "$1")" = firing ]; }
attendre "Un conteneur en boucle de redémarrage : ConteneurRedemarreEnBoucle" 360 sonne ConteneurRedemarreEnBoucle || true
k delete -f "$HERE/pannes/stock.yaml" -n "$NS" --wait=false >/dev/null 2>&1 || true
k scale deployment/api -n "$NS" --replicas=0 >/dev/null
attendre "Plus aucun pod d'API : TelemarcheApiIndisponible" 300 sonne TelemarcheApiIndisponible || true

summary
