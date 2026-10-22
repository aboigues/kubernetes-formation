#!/usr/bin/env bash
# Helpers partagés par tous les verify.sh des TP.
# Usage : source "$(git rev-parse --show-toplevel)/scripts/lib.sh"
#
# Chaque verify.sh travaille dans SON namespace jetable (tpNN-verify), créé au
# début et supprimé à la fin : il ne touche jamais à votre namespace de travail
# (telemarche). Pour garder le namespace après coup et l'inspecter : KEEP=1.

set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"

# Couleurs (désactivées si pas de TTY, ex. CI)
if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; NC=''
fi

PASS=0
FAIL=0

step()  { printf "${BLUE}▶ %s${NC}\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
die()   { printf "${RED}✗ %s${NC}\n" "$*" >&2; exit 1; }

k() { "$KUBECTL" "$@"; }

# check "description" commande...  → exécute, valide le code retour
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${NC} %s\n" "$desc"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} %s\n" "$desc"; FAIL=$((FAIL+1))
  fi
}

# assert_eq "description" "attendu" "obtenu"
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  ${GREEN}✓${NC} %s\n" "$desc"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(attendu : « %s », obtenu : « %s »)${NC}\n" "$desc" "$expected" "$actual"; FAIL=$((FAIL+1))
  fi
}

# assert_contains "description" "aiguille" "botte de foin"
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -q -- "$needle"; then
    printf "  ${GREEN}✓${NC} %s\n" "$desc"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(attendu : « %s »)${NC}\n" "$desc" "$needle"; FAIL=$((FAIL+1))
  fi
}

# ---------------------------------------------------------------------------
# Cluster et namespace de vérification
# ---------------------------------------------------------------------------

# need_cluster : échoue tôt et clairement si kubectl ne joint aucun cluster.
need_cluster() {
  command -v "$KUBECTL" >/dev/null 2>&1 || die "kubectl introuvable dans le PATH."
  if ! k version --request-timeout=5s >/dev/null 2>&1; then
    die "Aucun cluster joignable (contexte courant : $(k config current-context 2>/dev/null || echo 'aucun')). Lancez « minikube start » (voir TP01)."
  fi
}

# verify_namespace NOM : (re)crée un namespace jetable et le supprime à la sortie.
verify_namespace() {
  NS="$1"
  cleanup_ns() {
    if [ "${KEEP:-0}" = "1" ]; then
      info "KEEP=1 : namespace $NS conservé (kubectl delete namespace $NS pour le supprimer)."
    else
      k delete namespace "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_ns EXIT
  if k get namespace "$NS" >/dev/null 2>&1; then
    k delete namespace "$NS" --wait=true --timeout=120s >/dev/null
  fi
  k create namespace "$NS" >/dev/null
}

# target_dir : résout starter|solution en chemin absolu (à côté du verify.sh).
target_dir() {
  local here="$1" target="$2"
  case "$target" in
    starter|solution) ;;
    *) die "Usage : ./verify.sh [starter|solution]" ;;
  esac
  [ -d "$here/$target" ] || die "Dossier introuvable : $here/$target"
  printf '%s/%s' "$here" "$target"
}

# no_holes DOSSIER : refuse d'aller plus loin s'il reste des trous « ______ ».
no_holes() {
  local dir="$1" holes
  holes="$(grep -rn '______' "$dir" 2>/dev/null || true)"
  if [ -n "$holes" ]; then
    printf "  ${RED}✗${NC} Il reste des trous à compléter :\n"
    printf '%s\n' "$holes" | sed "s|$dir/||; s/^/      /"
    FAIL=$((FAIL+1))
    summary
  fi
  printf "  ${GREEN}✓${NC} Aucun trou « ______ » restant\n"; PASS=$((PASS+1))
}

# apply FICHIER|DOSSIER : applique dans le namespace de vérification.
apply() {
  local out
  if ! out="$(k apply -n "$NS" -f "$1" 2>&1)"; then
    printf "  ${RED}✗${NC} kubectl apply a échoué :\n"
    printf '%s\n' "$out" | sed 's/^/      /'
    FAIL=$((FAIL+1))
    summary
  fi
  printf '%s\n' "$out" | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
# Attentes et requêtes
# ---------------------------------------------------------------------------

# wait_rollout DEPLOYMENT [TIMEOUT_S] : attend la fin du déploiement.
wait_rollout() {
  local name="$1" timeout="${2:-120}"
  if k rollout status "deployment/$name" -n "$NS" --timeout="${timeout}s" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${NC} Deployment %s disponible\n" "$name"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} Deployment %s pas disponible après %ss\n" "$name" "$timeout"; FAIL=$((FAIL+1))
    debug_pods
  fi
}

# wait_pod_ready POD [TIMEOUT_S]
wait_pod_ready() {
  local name="$1" timeout="${2:-120}"
  if k wait --for=condition=Ready "pod/$name" -n "$NS" --timeout="${timeout}s" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${NC} Pod %s prêt\n" "$name"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${NC} Pod %s pas prêt après %ss\n" "$name" "$timeout"; FAIL=$((FAIL+1))
    debug_pods
  fi
}

# svc_get SERVICE PORT CHEMIN : requête HTTP vers un Service, relayée par
# l'API server (aucun port-forward, aucun pod de test à lancer).
svc_get() {
  k get --raw "/api/v1/namespaces/$NS/services/http:$1:$2/proxy$3" --request-timeout=5s 2>/dev/null
}

# pod_get POD PORT CHEMIN : idem, directement vers un pod.
pod_get() {
  k get --raw "/api/v1/namespaces/$NS/pods/http:$1:$2/proxy$3" --request-timeout=5s 2>/dev/null
}

# wait_svc_http SERVICE PORT CHEMIN [TIMEOUT_S] : attend une réponse 2xx.
wait_svc_http() {
  local svc="$1" port="$2" path="$3" timeout="${4:-60}" i=0
  until svc_get "$svc" "$port" "$path" >/dev/null; do
    i=$((i+2)); sleep 2
    if [ "$i" -ge "$timeout" ]; then
      printf "  ${RED}✗${NC} Service %s:%s%s ne répond pas après %ss\n" "$svc" "$port" "$path" "$timeout"; FAIL=$((FAIL+1))
      return 1
    fi
  done
  printf "  ${GREEN}✓${NC} Service %s:%s%s répond\n" "$svc" "$port" "$path"; PASS=$((PASS+1))
}

# wait_pod_http POD PORT CHEMIN [TIMEOUT_S] : attend qu'un pod réponde en 2xx.
# Un pod « Ready » n'a pas forcément fini de démarrer : sans readiness probe,
# Kubernetes le déclare prêt dès que son conteneur tourne.
wait_pod_http() {
  local pod="$1" port="$2" path="$3" timeout="${4:-60}" i=0
  until pod_get "$pod" "$port" "$path" >/dev/null; do
    i=$((i+2)); sleep 2
    if [ "$i" -ge "$timeout" ]; then
      printf "  ${RED}✗${NC} Pod %s:%s%s ne répond pas après %ss\n" "$pod" "$port" "$path" "$timeout"; FAIL=$((FAIL+1))
      return 1
    fi
  done
}

# jp RESSOURCE EXPRESSION_JSONPATH : lit un champ (vide si absent).
jp() { k get "$1" -n "$NS" -o "jsonpath=$2" 2>/dev/null || true; }

# debug_pods : après un échec, affiche ce qu'un exploitant regarderait.
debug_pods() {
  warn "Pistes de diagnostic (namespace $NS) :"
  k get pods -n "$NS" -o wide 2>/dev/null | sed 's/^/      /' || true
  k get events -n "$NS" --sort-by=.lastTimestamp 2>/dev/null | tail -8 | sed 's/^/      /' || true
}

# Bilan final : code de sortie non nul si au moins un échec
summary() {
  echo "-----------------------------------------"
  if [ "$FAIL" -eq 0 ]; then
    printf "${GREEN}✅ TP validé : %d vérification(s) réussie(s).${NC}\n" "$PASS"
    exit 0
  else
    printf "${RED}❌ TP non validé : %d échec(s) sur %d.${NC}\n" "$FAIL" "$((PASS+FAIL))"
    printf "   Relancez avec KEEP=1 pour garder le namespace de vérification et l'inspecter.\n"
    printf "   Un message kubectl obscur ? Voir l'annexe TELEMACH (ANNEXE-TELEMACH.md).\n"
    exit 1
  fi
}
