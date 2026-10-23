#!/usr/bin/env bash
# Prérequis du cluster pour ce TP (ce que l'étape 1 vous fait faire à la main) :
# Prometheus, Alertmanager et Grafana, par le chart kube-prometheus-stack.
# La CI l'exécute avant verify.sh ; vous pouvez le lancer aussi.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHART_VERSION=92.11.0

# Un mot de passe Grafana aléatoire, jamais écrit dans un fichier du dépôt.
MDP="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version "$CHART_VERSION" \
  --namespace monitoring --create-namespace \
  --values "$HERE/monitoring-values.yaml" \
  --set-string grafana.adminPassword="$MDP" \
  --wait --timeout 10m
echo "Grafana : utilisateur admin, mot de passe dans le Secret monitoring-grafana (étape 1 du README)."
