# Guide d'utilisation du script de test TP4

## Description

Le script `test-tp4.sh` est un outil de test automatisé complet pour vérifier que tous les composants du TP4 (Monitoring et Logs) fonctionnent correctement.

## Composants testés

Le script vérifie les composants suivants :

1. **Metrics Server** : Installation et disponibilité des métriques
2. **Horizontal Pod Autoscaler (HPA)** : Déploiement et fonctionnement
3. **Prometheus** : Déploiement, configuration, RBAC
4. **Prometheus RBAC** : Permissions pour accéder aux métriques Kubernetes
5. **Prometheus Métriques** : Collecte des métriques cAdvisor et autres
6. **Grafana** : Déploiement et accessibilité
7. **Configuration Prometheus** : Vérification des jobs de scraping
8. **Résumé** : État global de la stack de monitoring

## Prérequis

- Un cluster Kubernetes fonctionnel (minikube ou kubeadm)
- `kubectl` installé et configuré
- `curl` et `jq` installés (pour les tests API)
- 4 Go de RAM minimum recommandés

## Installation des prérequis (si nécessaire)

```bash
# Installation de jq (Ubuntu/Debian)
sudo apt-get install jq

# Installation de jq (macOS)
brew install jq

# Installation de jq (CentOS/RHEL)
sudo yum install jq
```

## Utilisation

### Lancer tous les tests

```bash
cd tp4
./test-tp4.sh
```

### Nettoyer les ressources de test

```bash
./test-tp4.sh cleanup
```

**Note** : Le nettoyage ne supprime **pas** le namespace `monitoring` pour préserver Prometheus et Grafana.

## Interprétation des résultats

### Codes de sortie

Le script utilise des couleurs pour indiquer l'état des tests :

- 🟢 **[✓ SUCCESS]** : Test réussi
- 🔴 **[✗ ERROR]** : Test échoué
- 🟡 **[! WARNING]** : Avertissement (non bloquant)
- 🔧 **[🔧 FIX]** : Suggestion de correction

### Résumé final

À la fin de l'exécution, le script affiche un résumé :

```
╔═══════════════════════════════════════════════════════════════╗
║                    RÉSUMÉ DES TESTS                           ║
╚═══════════════════════════════════════════════════════════════╝

  Tests réussis : 15
  Tests échoués : 0
  Total         : 15

[✓ SUCCESS] ✅ Tous les tests sont passés avec succès !
```

## Commandes de correction automatiques

Lorsqu'un test échoue, le script affiche des **commandes de correction** pour résoudre le problème.

### Exemple : Metrics Server non installé

```
[✗ ERROR] Metrics Server n'est pas déployé
[🔧 FIX] Commandes de correction :
  minikube addons enable metrics-server
  # OU pour installation manuelle :
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Exemple : Prometheus non déployé

```
[✗ ERROR] Déploiement Prometheus n'existe pas
[🔧 FIX] Commandes de correction :
  kubectl apply -f /path/to/tp4/04-prometheus-deployment.yaml
```

### Exemple : Permissions RBAC manquantes

```
[✗ ERROR] Permission nodes/metrics manquante
[🔧 FIX] Vérifier que le ClusterRole contient 'nodes/metrics' dans les resources
```

## Dépannage courant

### 1. Metrics Server ne démarre pas

**Symptômes** :
- Pod Metrics Server en état `CrashLoopBackOff`
- Erreur TLS dans les logs

**Solution** :
```bash
# Vérifier les logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# Si erreur TLS, ajouter l'argument --kubelet-insecure-tls (environnement de test uniquement)
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

### 2. Prometheus ne collecte pas de métriques cAdvisor

**Symptômes** :
- Job `kubernetes-cadvisor` est DOWN dans Prometheus Targets
- Erreurs `403 Forbidden` dans les logs Prometheus

**Solution** :
```bash
# Vérifier les permissions RBAC
kubectl get clusterrole prometheus -o yaml | grep -A 10 "rules:"

# Vérifier que nonResourceURLs contient /metrics/cadvisor
kubectl get clusterrole prometheus -o yaml | grep -E "nonResourceURLs|/metrics"

# Si manquant, réappliquer la configuration
kubectl apply -f 04-prometheus-deployment.yaml
```

### 3. Grafana ne démarre pas

**Symptômes** :
- Pod Grafana en état `Pending` ou `CrashLoopBackOff`

**Solution** :
```bash
# Vérifier l'état du pod
kubectl describe pod -n monitoring -l app=grafana

# Vérifier les logs
kubectl logs -n monitoring -l app=grafana

# Si problème de ressources, vérifier les requests/limits
kubectl get pod -n monitoring -l app=grafana -o jsonpath='{.items[0].spec.containers[0].resources}'
```

### 4. HPA ne peut pas lire les métriques

**Symptômes** :
- HPA affiche `<unknown>` pour les métriques CPU
- Message "unable to get metrics"

**Solution** :
```bash
# Vérifier que Metrics Server fonctionne
kubectl top nodes
kubectl top pods

# Si kubectl top ne fonctionne pas, attendre 1-2 minutes après l'installation de Metrics Server

# Vérifier l'état de l'API metrics
kubectl get apiservice v1beta1.metrics.k8s.io

# Vérifier les logs Metrics Server
kubectl logs -n kube-system -l k8s-app=metrics-server --tail=50
```

## Tests spécifiques

### Tester uniquement Prometheus

```bash
# Exécuter les tests Prometheus manuellement
cd tp4

# Test 3: Déploiement
kubectl get deployment prometheus -n monitoring

# Test 4: RBAC
kubectl auth can-i get nodes/metrics --as=system:serviceaccount:monitoring:prometheus

# Test 5: Métriques
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'
```

### Tester uniquement Grafana

```bash
# Vérifier l'état
kubectl get pods -n monitoring -l app=grafana

# Accéder à l'interface
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Ouvrir dans le navigateur : http://localhost:3000
# Credentials: admin / admin123
```

## Validation manuelle complémentaire

Après l'exécution du script, effectuez ces vérifications manuelles :

### 1. Vérifier les targets Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Ouvrir http://localhost:9090/targets et vérifier que :
- ✅ `kubernetes-nodes` est UP
- ✅ `kubernetes-cadvisor` est UP
- ✅ `kubernetes-pods` est UP (si pods annotés présents)

### 2. Tester des requêtes PromQL

Dans l'interface Prometheus (Graph), tester :

```promql
# Métriques disponibles
up

# CPU par pod
sum(rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m])) by (pod, namespace)

# Mémoire par pod
sum(container_memory_usage_bytes{container!="",container!="POD"}) by (pod, namespace)

# Nombre de pods
count(container_memory_usage_bytes{container!="",container!="POD"}) by (namespace)
```

### 3. Configurer Grafana

1. Se connecter à Grafana (admin/admin123)
2. Ajouter Prometheus comme source de données :
   - URL: `http://prometheus.monitoring.svc.cluster.local:9090`
   - Cliquer sur "Save & Test"
3. Importer un dashboard :
   - Dashboard ID: **315** (Kubernetes cluster monitoring)
   - Sélectionner la source Prometheus

### 4. Tester l'autoscaling HPA

```bash
# Générer de la charge
kubectl run load-generator --image=busybox --restart=Never -- \
  /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

# Observer le scaling (dans un autre terminal)
kubectl get hpa php-apache-hpa -w

# Après 2-3 minutes, le nombre de replicas devrait augmenter
kubectl get pods -l app=php-apache

# Arrêter la charge
kubectl delete pod load-generator

# Observer le scale down (environ 5 minutes)
```

## Ressources complémentaires

### Documentation TP4

- [README principal du TP4](./README.md)
- [Configuration Prometheus](./04-prometheus-deployment.yaml)
- [Configuration Grafana](./05-grafana-deployment.yaml)

### Dashboards Grafana recommandés

- **315** : Kubernetes cluster monitoring
- **747** : Kubernetes Deployment metrics
- **6417** : Kubernetes Cluster (Prometheus)
- **8588** : Kubernetes Deployment Statefulset Daemonset metrics

### Guides externes

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

## Désinstallation complète

Pour supprimer complètement la stack de monitoring :

```bash
# Supprimer le namespace monitoring (supprime Prometheus et Grafana)
kubectl delete namespace monitoring

# Supprimer les ClusterRole et ClusterRoleBinding
kubectl delete clusterrole prometheus
kubectl delete clusterrolebinding prometheus

# Désactiver Metrics Server (minikube)
minikube addons disable metrics-server

# Supprimer l'application HPA de test
kubectl delete -f 01-hpa-demo.yaml
```

## Support et contributions

Pour signaler un bug ou suggérer une amélioration :
1. Ouvrir une issue sur le repository GitHub
2. Fournir les logs d'exécution du script
3. Indiquer la version de Kubernetes et l'environnement (minikube/kubeadm)

---

**Dernière mise à jour** : 2025-12-16
**Version du script** : 1.0
