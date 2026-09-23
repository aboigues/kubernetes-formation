# Guide des Exercices - TP6

Ce document contient des instructions pour tester tous les exercices du TP6.

## Prérequis

Avant de commencer, assurez-vous d'avoir:

- **minikube** installé et démarré
- **kubectl** configuré
- **helm** installé (v3+)
- Un cluster Kubernetes fonctionnel

```bash
# Démarrer minikube
minikube start --cpus=2 --memory=4096

# Activer les addons nécessaires
minikube addons enable metrics-server

# Gateway API : CRDs + NGINX Gateway Fabric (voir tp06/README.md §2.2 pour le détail)
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.7.2" | kubectl apply -f -
helm install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --create-namespace --namespace nginx-gateway --set nginx.service.type=NodePort
```

## Test Rapide

Pour tester tous les exercices rapidement:

```bash
cd tp6
./test-all.sh
```

## Tests par Section

### 1. Helm - Exercices 1 à 4

#### Exercice 3-4: Chart personnalisé

```bash
# Valider le chart
helm lint 01-helm/my-app/

# Générer les manifests (dry-run)
helm template my-app ./01-helm/my-app

# Installer le chart
helm install my-release ./01-helm/my-app

# Vérifier l'installation
helm list
kubectl get all

# Mettre à jour avec des valeurs personnalisées
helm upgrade my-release ./01-helm/my-app -f 01-helm/custom-values.yaml

# Utiliser les valeurs pour différents environnements
helm install my-app-dev ./01-helm/my-app -f 01-helm/my-app/values-dev.yaml
helm install my-app-prod ./01-helm/my-app -f 01-helm/my-app/values-prod.yaml

# Désinstaller
helm uninstall my-release
```

### 2. Gateway API - Exercices 5 et 6

> ingress-nginx est retiré depuis mars 2026 : ces exercices utilisent la Gateway API avec
> NGINX Gateway Fabric. Voir `tp06/README.md` Partie 2 pour le détail et §2.7 pour un rappel
> de l'Ingress classique (connaissance CKAD, non déployé ici).

#### Exercice 5: Gateway + HTTPRoute simple

```bash
# Déployer l'application
kubectl apply -f 02-gateway-api/01-app-deployment.yaml

# Créer le Gateway (une seule fois, partagé par tous les exercices suivants)
kubectl apply -f 02-gateway-api/02-gateway.yaml

# Créer la HTTPRoute
kubectl apply -f 02-gateway-api/03-httproute-simple.yaml

# Vérifier
kubectl get gateway main-gateway
kubectl get httproute web-app-route
kubectl describe httproute web-app-route

# Ajouter l'entrée dans /etc/hosts
echo "$(minikube ip) myapp.local" | sudo tee -a /etc/hosts

# Tester
curl http://myapp.local
```

#### Exercice 6: HTTPRoute avec TLS

```bash
# Créer un certificat auto-signé
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=myapp.local/O=myapp"

# Créer le Secret TLS référencé par le listener https du Gateway
kubectl create secret tls myapp-tls \
  --cert=tls.crt \
  --key=tls.key

# Appliquer la HTTPRoute TLS
kubectl apply -f 02-gateway-api/05-httproute-tls.yaml

# Tester HTTPS
curl -k https://myapp.local
```

#### Multi-service HTTPRoute

```bash
# Déployer frontend et API
kubectl apply -f 02-gateway-api/04-httproute-multi-service.yaml

# Tester les routes
curl http://myapp.local/
curl http://myapp.local/api
```

#### HTTPRoute avancée

```bash
# Appliquer avec filtres CORS / en-têtes / timeouts (natifs, canal standard)
kubectl apply -f 02-gateway-api/06-httproute-advanced.yaml

# Tester avec headers
curl -v http://myapp.local
```

### 3. Stratégies de Déploiement - Exercice 7

#### Rolling Update

```bash
# Déployer
kubectl apply -f 03-deployment-strategies/06-rolling-update.yaml

# Observer le rollout
kubectl rollout status deployment/rolling-app

# Mettre à jour l'image
kubectl set image deployment/rolling-app app=hashicorp/http-echo:latest

# Observer en direct
watch kubectl get pods

# Voir l'historique
kubectl rollout history deployment/rolling-app

# Rollback
kubectl rollout undo deployment/rolling-app
```

#### Blue-Green Deployment

```bash
# Déployer blue et green
kubectl apply -f 03-deployment-strategies/07-blue-green.yaml

# Vérifier que le service pointe vers blue
kubectl get svc myapp-service -o yaml | grep version

# Tester
minikube service myapp-service --url
curl http://$(minikube service myapp-service --url)

# Switch vers green
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"green"}}}'

# Tester à nouveau
curl http://$(minikube service myapp-service --url)

# Rollback vers blue
kubectl patch service myapp-service -p '{"spec":{"selector":{"version":"blue"}}}'
```

#### Canary Deployment

```bash
# Déployer stable (90%) et canary (10%)
kubectl apply -f 03-deployment-strategies/08-canary.yaml

# Tester plusieurs fois (10% canary, 90% stable)
for i in {1..20}; do
  curl http://$(minikube service myapp-service --url)
  sleep 1
done

# Augmenter progressivement le canary
kubectl scale deployment app-canary --replicas=3
kubectl scale deployment app-stable --replicas=7

# Si tout va bien, promouvoir canary
kubectl scale deployment app-canary --replicas=10
kubectl scale deployment app-stable --replicas=0

# Ou rollback en cas de problème
kubectl scale deployment app-canary --replicas=0
kubectl scale deployment app-stable --replicas=10
```

#### A/B Testing avec la Gateway API

```bash
kubectl apply -f 03-deployment-strategies/09-ab-testing.yaml

# Le trafic est réparti: 70% vers v1, 30% vers v2
```

### 4. Bonnes Pratiques de Production

#### Health Checks

```bash
# Déployer avec toutes les probes
kubectl apply -f 04-production-best-practices/12-health-checks.yaml

# Vérifier les probes
kubectl describe pod -l app=production-app
```

#### Pod Disruption Budget

```bash
# Créer le PDB
kubectl apply -f 04-production-best-practices/13-pdb.yaml

# Vérifier
kubectl get pdb
kubectl describe pdb my-app-pdb
```

#### HorizontalPodAutoscaler

```bash
# Créer le HPA
kubectl apply -f 04-production-best-practices/14-hpa.yaml

# Voir le status
kubectl get hpa
kubectl describe hpa my-app-hpa

# Générer de la charge pour tester
kubectl run -it --rm load-generator --image=busybox -- /bin/sh
# Dans le shell: while true; do wget -q -O- http://my-app-service; done

# Observer l'autoscaling (dans un autre terminal)
watch kubectl get hpa,pods
```

### 5. GitOps avec Kustomize

#### Structure GitOps

```bash
# Voir le manifest pour dev
kubectl kustomize 07-gitops-structure/overlays/dev

# Voir le manifest pour staging
kubectl kustomize 07-gitops-structure/overlays/staging

# Voir le manifest pour production
kubectl kustomize 07-gitops-structure/overlays/production

# Appliquer directement
kubectl apply -k 07-gitops-structure/overlays/dev
kubectl apply -k 07-gitops-structure/overlays/staging
kubectl apply -k 07-gitops-structure/overlays/production

# Voir les différences
kubectl diff -k 07-gitops-structure/overlays/production
```

### 6. ArgoCD (nécessite ArgoCD installé)

```bash
# Installer ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod --all -n argocd --timeout=300s

# Exposer l'UI ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Récupérer le mot de passe
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# Créer l'application (pointe sur ce dépôt public, aucune modification requise)
# Parcours guidé complet : README.md, Partie 5.3
kubectl apply -f 05-argocd/10-argocd-application.yaml
```

### 7. Application Exemple

#### Build et déploiement local

```bash
# Construire l'image directement dans le nœud minikube
# (fonctionne avec les runtimes docker et containerd, le défaut depuis minikube v1.39 ;
#  l'ancien "eval $(minikube docker-env) + docker build" échoue sous containerd)
minikube image build -t my-kubernetes-app:v1 sample-app/
minikube image ls | grep my-kubernetes-app

# Créer un déploiement de test
# Tag v1 et non latest : avec :latest, Kubernetes force imagePullPolicy: Always
# et tente de télécharger l'image sur Docker Hub (ErrImagePull) au lieu
# d'utiliser celle du cache de minikube.
kubectl create deployment my-app --image=my-kubernetes-app:v1
kubectl expose deployment my-app --port=3000
kubectl port-forward svc/my-app 3000:3000

# Tester
curl http://localhost:3000
curl http://localhost:3000/health
```

## Nettoyage

Pour nettoyer toutes les ressources créées:

```bash
# Supprimer tous les déploiements
kubectl delete deployment --all
kubectl delete service --all
kubectl delete httproute --all
kubectl delete gateway --all
kubectl delete hpa --all
kubectl delete pdb --all

# Désinstaller les releases Helm
helm uninstall my-release || true
helm uninstall my-app-dev || true
helm uninstall my-app-prod || true

# Supprimer ArgoCD
kubectl delete namespace argocd || true

# Ou tout supprimer et redémarrer minikube
minikube delete
minikube start
```

## Validation des fichiers

Pour valider la syntaxe de tous les fichiers YAML sans les appliquer:

```bash
# Valider les fichiers Helm
helm lint 01-helm/my-app/

# Valider les fichiers Kubernetes
kubectl apply --dry-run=client -f 02-gateway-api/
kubectl apply --dry-run=client -f 03-deployment-strategies/
kubectl apply --dry-run=client -f 04-production-best-practices/

# Valider Kustomize
kubectl kustomize 07-gitops-structure/overlays/dev
kubectl kustomize 07-gitops-structure/overlays/staging
kubectl kustomize 07-gitops-structure/overlays/production
```

## Notes

- Tous les fichiers ont été testés et validés
- Les exercices peuvent être exécutés indépendamment
- Pour les exercices CI/CD, vous devrez adapter les workflows GitHub Actions à votre repository
- Pour ArgoCD, les Applications pointent sur ce dépôt public ; un fork n'est nécessaire que pour modifier Git (README, étape 6 de la section 5.3)

## Ressources

- [Documentation Helm](https://helm.sh/docs/)
- [Documentation Gateway API](https://gateway-api.sigs.k8s.io/)
- [Documentation NGINX Gateway Fabric](https://docs.nginx.com/nginx-gateway-fabric/)
- [Documentation Ingress NGINX](https://kubernetes.github.io/ingress-nginx/) (archivé, projet retiré depuis mars 2026)
- [Documentation ArgoCD](https://argo-cd.readthedocs.io/)
- [Documentation Kustomize](https://kustomize.io/)
