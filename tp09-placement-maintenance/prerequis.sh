#!/usr/bin/env bash
# Prérequis du cluster pour ce TP (ce que les étapes 1 et 3 vous font faire à
# la main) : trois nœuds, dont le troisième, au « disque rapide », est réservé
# au service de stock. La CI l'exécute avant verify.sh ; vous pouvez le lancer aussi.
set -euo pipefail
while [ "$(kubectl get nodes -o name | wc -l)" -lt 3 ]; do
  minikube node add
done
kubectl wait --for=condition=Ready nodes --all --timeout=180s
N3="$(kubectl get nodes -o name | sort | sed -n 3p)"
kubectl label --overwrite "$N3" disque=ssd
kubectl taint --overwrite nodes "${N3#node/}" dedie=stock:NoSchedule
kubectl get nodes -L disque
