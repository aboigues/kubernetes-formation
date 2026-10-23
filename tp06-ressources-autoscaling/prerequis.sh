#!/usr/bin/env bash
# Prérequis du cluster pour ce TP (ce que l'étape 4 vous fait faire à la main).
# La CI l'exécute avant verify.sh ; vous pouvez le lancer aussi.
set -euo pipefail
minikube addons enable metrics-server
