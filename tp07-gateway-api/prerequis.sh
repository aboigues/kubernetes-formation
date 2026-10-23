#!/usr/bin/env bash
# Prérequis du cluster pour ce TP (ce que l'étape 1 vous fait faire à la main) :
# les CRD de la Gateway API, puis Traefik installé par Helm dans le namespace traefik.
# La CI l'exécute avant verify.sh ; vous pouvez le lancer aussi.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_API_VERSION=v1.6.3
TRAEFIK_CHART_VERSION=42.1.3

kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
helm upgrade --install traefik traefik --repo https://traefik.github.io/charts \
  --version "$TRAEFIK_CHART_VERSION" --namespace traefik --create-namespace \
  --values "$HERE/traefik-values.yaml" --wait --timeout 5m
