#!/usr/bin/env bash
# Contrôle préalable du poste avant les TP : outils, versions, ressources.
# Usage : ./scripts/preflight.sh      (ne modifie rien, se contente de lire)
set -uo pipefail

K8S_TARGET="1.37"      # version mineure de Kubernetes des TP
MINIKUBE_MIN="1.39.0"  # version de minikube avec laquelle les TP sont testés
CPU_MIN=2
MAJ="voir « Installer ou mettre à jour kubectl et minikube » dans le README"
MEM_MIN_GO=4

if [ -t 1 ]; then G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m'; else G=''; R=''; Y=''; N=''; fi
OK=0; KO=0; WARN=0
ok()   { printf "  ${G}✓${N} %s\n" "$*"; OK=$((OK+1)); }
ko()   { printf "  ${R}✗${N} %s\n" "$*"; KO=$((KO+1)); }
warn() { printf "  ${Y}⚠${N} %s\n" "$*"; WARN=$((WARN+1)); }

# version_ge A B : vrai si A >= B (versions x.y.z)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

echo "▶ Outils"
for t in git curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t présent"; else ko "$t absent"; fi
done

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then ok "Docker joignable ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
  else ko "Docker installé mais injoignable (démon arrêté ? utilisateur hors du groupe docker ?)"; fi
else
  ko "docker absent (requis par le driver docker de minikube)"
fi

if command -v kubectl >/dev/null 2>&1; then
  KV="$(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"v\([0-9.]*\).*/\1/p' | head -1)"
  KMINOR="$(printf '%s' "$KV" | cut -d. -f2)"; TMINOR="$(printf '%s' "$K8S_TARGET" | cut -d. -f2)"
  if [ -z "$KV" ]; then ko "kubectl présent mais sa version est illisible (un alias vers microk8s ou minikube ?)"
  elif [ $((KMINOR - TMINOR)) -ge -1 ] && [ $((KMINOR - TMINOR)) -le 1 ]; then ok "kubectl $KV (compatible avec Kubernetes $K8S_TARGET)"
  else ko "kubectl $KV : trop éloigné de Kubernetes $K8S_TARGET (écart toléré : une version mineure) ; $MAJ"; fi
else
  ko "kubectl absent : $MAJ"
fi

if command -v minikube >/dev/null 2>&1; then
  MV="$(minikube version --short 2>/dev/null | sed 's/^v//')"
  if version_ge "$MV" "$MINIKUBE_MIN"; then ok "minikube $MV"
  else ko "minikube $MV : version $MINIKUBE_MIN ou plus récente requise ; $MAJ"; fi
else
  ko "minikube absent : $MAJ"
fi

if command -v helm >/dev/null 2>&1; then ok "helm $(helm version --short 2>/dev/null) (TP12)"
else warn "helm absent : nécessaire seulement au TP12"; fi

if command -v kubectl-telemach >/dev/null 2>&1; then ok "TELEMACH présent (facultatif)"
else warn "TELEMACH absent : facultatif, voir ANNEXE-TELEMACH.md"; fi

echo "▶ Ressources"
CPUS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)"
if [ "$CPUS" -ge "$CPU_MIN" ]; then ok "$CPUS processeurs"; else ko "$CPUS processeur(s) : $CPU_MIN au minimum"; fi
if [ -r /proc/meminfo ]; then
  MEM_GO=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
  if [ "$MEM_GO" -ge "$MEM_MIN_GO" ]; then ok "$MEM_GO Go de mémoire disponible"
  else warn "$MEM_GO Go de mémoire disponible : $MEM_MIN_GO Go recommandés (fermez des applications)"; fi
fi

echo "▶ Cluster"
if command -v kubectl >/dev/null 2>&1 && kubectl version --request-timeout=5s >/dev/null 2>&1; then
  ok "cluster joignable (contexte : $(kubectl config current-context))"
else
  warn "aucun cluster joignable pour l'instant : normal avant le TP01 (minikube start)"
fi

echo "-----------------------------------------"
if [ "$KO" -eq 0 ]; then
  printf "${G}✅ Poste prêt%s.${N}\n" "$( [ "$WARN" -gt 0 ] && echo " ($WARN avertissement(s))")"
else
  printf "${R}❌ %d point(s) bloquant(s) à corriger avant les TP.${N}\n" "$KO"; exit 1
fi
