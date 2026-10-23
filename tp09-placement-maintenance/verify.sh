#!/usr/bin/env bash
# TP09 — vérifie le placement (API répartie, stock sur son nœud réservé), puis
# draine un nœud qui porte l'API et mesure le service pendant l'opération :
# aucune requête en échec, jamais moins de 2 pods d'API prêts.
# ⚠️ Le drain est réel : le nœud est vidé de TOUS ses pods, puis remis en service.
source "$(git rev-parse --show-toplevel)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

need_cluster
SSD="$(k get nodes -l disque=ssd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ "$(k get nodes -o name | grep -c .)" -ge 3 ] && [ -n "$SSD" ] \
  && k get node "$SSD" -o jsonpath='{.spec.taints[*].key}={.spec.taints[*].value}' | grep -q 'dedie=stock' \
  || die "Il faut 3 nœuds, dont un étiqueté disque=ssd et marqué dedie=stock:NoSchedule : étapes 1 et 3 (ou ./prerequis.sh)."

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
verify_namespace tp09-verify
apply "$DIR"

step "Le placement"
wait_rollout api 180
wait_rollout web 120
wait_rollout stock 120
nodes_of() { k get pods -n "$NS" -l "app=$1" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null || true; }
assert_eq "Le stock tourne sur le nœud réservé ($SSD)" "$SSD" "$(nodes_of stock | sort -u | xargs)"
assert_eq "Ni l'API ni la vitrine sur le nœud réservé" "0" "$( { nodes_of api; nodes_of web; } | grep -cx "$SSD" || true)"
assert_eq "L'API est répartie sur 2 nœuds" "2" "$(nodes_of api | sort -u | grep -c .)"

step "Le budget d'interruptions"
assert_eq "minAvailable = 2" "2" "$(jp pdb/api '{.spec.minAvailable}')"
for _ in $(seq 1 15); do [ "$(jp pdb/api '{.status.disruptionsAllowed}')" = "1" ] && break; sleep 2; done
assert_eq "Une seule interruption permise à la fois" "1" "$(jp pdb/api '{.status.disruptionsAllowed}')"

step "Drainer un nœud sans coupure"
# Le nœud cible : celui qui porte le plus de pods d'API (hors nœud réservé).
CIBLE="$(nodes_of api | grep -vx "$SSD" | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')"
info "Nœud drainé : $CIBLE ($(nodes_of api | grep -cx "$CIBLE") pod(s) d'API)"
trap 'k uncordon "$CIBLE" >/dev/null 2>&1 || true; cleanup_ns' EXIT
MESURE="$(mktemp)"
(
  while [ ! -f "$MESURE.stop" ]; do
    if svc_get api 80 /api/info >/dev/null; then r=ok; else r=ko; fi
    echo "$r $(jp deployment/api '{.status.readyReplicas}')" >>"$MESURE"
    sleep 0.3
  done
) &
SONDE=$!
sleep 3
if k drain "$CIBLE" --ignore-daemonsets --delete-emptydir-data --timeout=240s >/dev/null 2>&1; then
  printf "  ${GREEN}✓${NC} Le drain de %s a abouti\n" "$CIBLE"; PASS=$((PASS+1))
else
  printf "  ${RED}✗${NC} Le drain de %s n'a pas abouti en 4 minutes\n" "$CIBLE"; FAIL=$((FAIL+1))
fi
k rollout status deployment/api -n "$NS" --timeout=120s >/dev/null 2>&1 || true
sleep 3
touch "$MESURE.stop"; wait "$SONDE" 2>/dev/null || true
TOTAL="$(grep -c . "$MESURE")"
assert_eq "Aucune requête en échec pendant le drain ($TOTAL envoyées)" "0" "$(grep -c '^ko' "$MESURE" || true)"
MIN="$(awk '{print ($2==""?0:$2)}' "$MESURE" | sort -n | head -1)"
check "Jamais moins de 2 pods d'API prêts (minimum observé : $MIN)" test "${MIN:-0}" -ge 2
assert_eq "Plus aucun pod d'API sur le nœud drainé" "0" "$(nodes_of api | grep -cx "$CIBLE" || true)"
rm -f "$MESURE" "$MESURE.stop"
k uncordon "$CIBLE" >/dev/null
info "$CIBLE remis en service (uncordon)."

summary
