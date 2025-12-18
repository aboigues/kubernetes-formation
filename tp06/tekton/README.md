# Tekton CI/CD - Quick Start

Ce dossier contient tous les fichiers nécessaires pour mettre en place un pipeline CI/CD avec Tekton, sans avoir besoin de compte GitHub.

## Structure

```
tekton/
├── tasks/              # Tasks individuelles (git clone, tests, build, etc.)
├── pipelines/          # Pipelines complets (CI et CD)
├── runs/               # Exemples de PipelineRun pour exécuter les pipelines
├── install-tekton.sh   # Script d'installation automatique
└── README.md           # Ce fichier
```

## Installation rapide

```bash
# Exécuter le script d'installation
./install-tekton.sh
```

Ce script va :
1. Installer Tekton Pipelines
2. Installer Tekton Triggers
3. Installer le Tekton Dashboard
4. Créer un registry Docker local
5. Appliquer toutes les Tasks et Pipelines

## Accéder au Dashboard

```bash
# Exposer le Dashboard
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097

# Ouvrir dans le navigateur
open http://localhost:9097
```

## Exécuter le pipeline CI

### Option 1 : Via kubectl

```bash
# Modifier le fichier runs/ci-pipelinerun-example.yaml avec vos paramètres
# Puis exécuter :
kubectl create -f runs/ci-pipelinerun-example.yaml

# Suivre les logs
kubectl logs -f $(kubectl get pods -l tekton.dev/pipelineRun --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

### Option 2 : Via tkn CLI (si installé)

```bash
tkn pipeline start ci-pipeline \
  --param git-url=https://github.com/votre-username/votre-repo.git \
  --param git-revision=main \
  --param image-name=localhost:5000/my-app \
  --param image-tag=v1.0.0 \
  --workspace name=shared-workspace,volumeClaimTemplateFile=workspace-template.yaml \
  --showlog
```

## Exécuter le pipeline CD

```bash
# Modifier runs/cd-pipelinerun-example.yaml avec vos paramètres
kubectl create -f runs/cd-pipelinerun-example.yaml

# Ou via tkn
tkn pipeline start cd-pipeline \
  --param git-url=https://github.com/votre-username/votre-repo.git \
  --param git-revision=main \
  --param release-name=my-app \
  --param chart-path=helm/my-app \
  --param namespace=production \
  --param image-repository=localhost:5000/my-app \
  --param image-tag=v1.0.0 \
  --param deployment-name=my-app \
  --showlog
```

## Lister les ressources

```bash
# Lister les Tasks
kubectl get tasks

# Lister les Pipelines
kubectl get pipelines

# Lister les PipelineRuns
kubectl get pipelineruns

# Voir les détails d'un PipelineRun
tkn pipelinerun describe <pipelinerun-name>

# Voir les logs
tkn pipelinerun logs <pipelinerun-name> -f
```

## Nettoyer les anciens runs

```bash
# Supprimer les PipelineRuns terminés
kubectl delete pipelinerun --all

# Ou garder les 5 derniers
tkn pipelinerun delete --keep 5
```

## Registry Docker local

Un registry Docker local est installé automatiquement pour stocker vos images sans avoir besoin d'un compte Docker Hub ou GitHub Container Registry.

```bash
# Obtenir l'URL du registry
kubectl get svc registry

# Utiliser localhost:5000 dans vos paramètres de pipeline
# Exemple : image-name=localhost:5000/my-app
```

## Troubleshooting

### Le pipeline échoue au clone Git

```bash
# Vérifier que l'URL Git est accessible
git clone <votre-url>

# Si repository privé, créer un Secret avec les credentials
kubectl create secret generic git-credentials \
  --from-literal=username=<username> \
  --from-literal=password=<token>
```

### Le build Docker échoue

```bash
# Vérifier que le Dockerfile existe
# Vérifier les logs du pod kaniko
kubectl logs -l tekton.dev/task=docker-build
```

### Le déploiement Helm échoue

```bash
# Vérifier que le chart Helm est valide
helm lint ./helm/my-app

# Vérifier les logs
kubectl logs -l tekton.dev/task=helm-deploy
```

## Documentation complète

Pour une documentation complète, voir [../ALTERNATIVE_SANS_GITHUB.md](../ALTERNATIVE_SANS_GITHUB.md)

## Ressources

- [Documentation Tekton](https://tekton.dev/docs/)
- [Tekton Catalog](https://hub.tekton.dev/) - Tasks réutilisables
- [Tekton CLI](https://github.com/tektoncd/cli)
