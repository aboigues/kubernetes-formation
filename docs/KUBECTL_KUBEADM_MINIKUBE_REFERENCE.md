# Référence des commandes Kubernetes

Ce document présente les commandes essentielles pour **kubectl**, **kubeadm** et **minikube**, trois outils fondamentaux de l'écosystème Kubernetes.

## Table des matières

1. [Introduction et contexte d'utilisation](#introduction-et-contexte-dutilisation)
2. [kubectl - Outil de gestion du cluster](#kubectl---outil-de-gestion-du-cluster)
3. [kubeadm - Outil d'installation de cluster](#kubeadm---outil-dinstallation-de-cluster)
4. [minikube - Cluster Kubernetes local](#minikube---cluster-kubernetes-local)
5. [Workflows courants](#workflows-courants)

---

## Introduction et contexte d'utilisation

### kubectl

**kubectl** est l'outil en ligne de commande pour interagir avec un cluster Kubernetes. C'est votre interface principale pour :
- Déployer et gérer des applications
- Inspecter et manipuler des ressources
- Consulter les logs et déboguer
- Gérer la configuration du cluster

**Contexte d'utilisation :** Utilisé quotidiennement pour toute opération sur un cluster Kubernetes (développement, test, production).

### kubeadm

**kubeadm** est l'outil officiel pour créer et gérer des clusters Kubernetes de production. Il permet de :
- Initialiser un cluster (nœud control plane)
- Ajouter des nœuds workers
- Gérer les mises à jour du cluster
- Maintenir les certificats

**Contexte d'utilisation :** Installation et maintenance de clusters multi-nœuds pour des environnements de test, staging ou production.

### minikube

**minikube** est un outil pour créer et gérer un cluster Kubernetes local mono-nœud. Idéal pour :
- Développement et tests en local
- Apprentissage de Kubernetes
- Valider des manifests avant déploiement
- CI/CD sur environnement isolé

**Contexte d'utilisation :** Environnement de développement local, formation, prototypage rapide.

---

## kubectl - Outil de gestion du cluster

### Configuration et contexte

```bash
# Afficher la configuration kubectl
kubectl config view

# Lister les contextes disponibles
kubectl config get-contexts

# Utiliser un contexte spécifique
kubectl config use-context <context-name>

# Définir le namespace par défaut
kubectl config set-context --current --namespace=<namespace>

# Afficher le contexte actuel
kubectl config current-context
```

### Informations sur le cluster

```bash
# Informations générales du cluster
kubectl cluster-info

# Lister les nœuds
kubectl get nodes
kubectl get nodes -o wide

# Détails d'un nœud
kubectl describe node <node-name>

# Vérifier la santé des composants
kubectl get componentstatuses
```

### Gestion des Pods

```bash
# Lister les pods
kubectl get pods
kubectl get pods -o wide
kubectl get pods --all-namespaces
kubectl get pods -n <namespace>

# Détails d'un pod
kubectl describe pod <pod-name>

# Logs d'un pod
kubectl logs <pod-name>
kubectl logs <pod-name> -f              # Suivre les logs en temps réel
kubectl logs <pod-name> --previous      # Logs du conteneur précédent
kubectl logs <pod-name> -c <container>  # Logs d'un conteneur spécifique

# Exécuter une commande dans un pod
kubectl exec <pod-name> -- <command>
kubectl exec -it <pod-name> -- /bin/bash  # Shell interactif

# Copier des fichiers
kubectl cp <pod-name>:/path/to/file /local/path
kubectl cp /local/path <pod-name>:/path/to/file

# Supprimer un pod
kubectl delete pod <pod-name>
kubectl delete pod <pod-name> --grace-period=0 --force  # Suppression forcée
```

### Gestion des Deployments

```bash
# Créer un deployment
kubectl create deployment <name> --image=<image>
kubectl create deployment <name> --image=<image> --replicas=3

# Lister les deployments
kubectl get deployments
kubectl get deploy

# Détails d'un deployment
kubectl describe deployment <name>

# Mettre à jour l'image d'un deployment
kubectl set image deployment/<name> <container>=<new-image>

# Scaler un deployment
kubectl scale deployment <name> --replicas=5

# Autoscaling
kubectl autoscale deployment <name> --min=2 --max=10 --cpu-percent=80

# Supprimer un deployment
kubectl delete deployment <name>
```

### Gestion des Services

```bash
# Créer un service
kubectl expose deployment <name> --type=NodePort --port=80
kubectl expose deployment <name> --type=LoadBalancer --port=80

# Lister les services
kubectl get services
kubectl get svc

# Détails d'un service
kubectl describe service <name>

# Supprimer un service
kubectl delete service <name>
```

### Rolling Updates et Rollbacks

```bash
# Mettre à jour une image
kubectl set image deployment/<name> <container>=<image>:<tag>

# Vérifier le statut du rollout
kubectl rollout status deployment/<name>

# Historique des rollouts
kubectl rollout history deployment/<name>

# Rollback vers la version précédente
kubectl rollout undo deployment/<name>

# Rollback vers une révision spécifique
kubectl rollout undo deployment/<name> --to-revision=<number>

# Mettre en pause un rollout
kubectl rollout pause deployment/<name>

# Reprendre un rollout
kubectl rollout resume deployment/<name>

# Redémarrer un deployment
kubectl rollout restart deployment/<name>
```

### Gestion des fichiers YAML (Manifests)

```bash
# Appliquer un manifest
kubectl apply -f <file.yaml>
kubectl apply -f <directory>/

# Créer des ressources
kubectl create -f <file.yaml>

# Supprimer des ressources
kubectl delete -f <file.yaml>

# Valider un manifest sans l'appliquer
kubectl apply -f <file.yaml> --dry-run=client
kubectl apply -f <file.yaml> --dry-run=server

# Afficher les différences avant application
kubectl diff -f <file.yaml>

# Obtenir un manifest existant en YAML
kubectl get deployment <name> -o yaml
kubectl get pod <name> -o yaml > pod.yaml
```

### ConfigMaps et Secrets

```bash
# Créer un ConfigMap
kubectl create configmap <name> --from-literal=key=value
kubectl create configmap <name> --from-file=<file>

# Lister les ConfigMaps
kubectl get configmaps
kubectl get cm

# Détails d'un ConfigMap
kubectl describe configmap <name>
kubectl get configmap <name> -o yaml

# Créer un Secret
kubectl create secret generic <name> --from-literal=password=secret
kubectl create secret generic <name> --from-file=<file>

# Lister les Secrets
kubectl get secrets

# Décoder un secret
kubectl get secret <name> -o jsonpath='{.data.password}' | base64 -d
```

### Namespaces

```bash
# Lister les namespaces
kubectl get namespaces
kubectl get ns

# Créer un namespace
kubectl create namespace <name>

# Supprimer un namespace
kubectl delete namespace <name>

# Lister les ressources dans un namespace
kubectl get all -n <namespace>
```

### Labels et Selectors

```bash
# Ajouter un label
kubectl label pod <pod-name> env=prod

# Modifier un label existant
kubectl label pod <pod-name> env=dev --overwrite

# Supprimer un label
kubectl label pod <pod-name> env-

# Filtrer par label
kubectl get pods -l env=prod
kubectl get pods -l 'env in (prod,dev)'
kubectl get pods -l env!=test
```

### Debugging et troubleshooting

```bash
# Événements du cluster
kubectl get events
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get events -n <namespace>

# Décrire une ressource (affiche les événements)
kubectl describe <resource-type> <name>

# Logs multiples pods
kubectl logs -l app=myapp

# Port forwarding pour tester localement
kubectl port-forward pod/<pod-name> 8080:80
kubectl port-forward service/<service-name> 8080:80

# Proxy vers l'API Kubernetes
kubectl proxy --port=8001

# Top (utilisation CPU/Mémoire)
kubectl top nodes
kubectl top pods
kubectl top pods -n <namespace>

# Lister toutes les ressources
kubectl get all
kubectl get all --all-namespaces

# Obtenir l'API resources disponibles
kubectl api-resources

# Expliquer une ressource
kubectl explain pod
kubectl explain deployment.spec
```

### Commandes avancées

```bash
# Patch une ressource
kubectl patch deployment <name> -p '{"spec":{"replicas":5}}'

# Éditer une ressource directement
kubectl edit deployment <name>

# Remplacer une ressource
kubectl replace -f <file.yaml>

# Attendre qu'une condition soit remplie
kubectl wait --for=condition=Ready pod/<pod-name>
kubectl wait --for=condition=available deployment/<name>

# Cordon/Drain (maintenance des nœuds)
kubectl cordon <node-name>      # Empêche de nouveaux pods
kubectl drain <node-name>       # Évacue les pods
kubectl uncordon <node-name>    # Réactive le nœud

# Taint un nœud
kubectl taint nodes <node-name> key=value:NoSchedule
kubectl taint nodes <node-name> key=value:NoSchedule-  # Retirer
```

---

## kubeadm - Outil d'installation de cluster

### Initialisation d'un cluster

```bash
# Initialiser un nœud master (control plane)
kubeadm init

# Avec configuration réseau spécifique
kubeadm init --pod-network-cidr=10.244.0.0/16

# Avec plusieurs control planes (HA)
kubeadm init --control-plane-endpoint="loadbalancer:6443" --upload-certs

# Générer le fichier de configuration
kubeadm config print init-defaults > kubeadm-config.yaml
kubeadm init --config kubeadm-config.yaml

# Afficher le token de join
kubeadm token create --print-join-command
```

### Rejoindre un cluster

```bash
# Rejoindre en tant que worker
kubeadm join <control-plane-host>:<port> --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Rejoindre en tant que control plane (HA)
kubeadm join <control-plane-host>:<port> --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane --certificate-key <key>
```

### Gestion des tokens

```bash
# Lister les tokens
kubeadm token list

# Créer un nouveau token
kubeadm token create

# Créer un token avec TTL
kubeadm token create --ttl 2h

# Supprimer un token
kubeadm token delete <token>

# Générer la commande join complète
kubeadm token create --print-join-command
```

### Gestion des certificats

```bash
# Vérifier l'expiration des certificats
kubeadm certs check-expiration

# Renouveler tous les certificats
kubeadm certs renew all

# Renouveler un certificat spécifique
kubeadm certs renew apiserver
kubeadm certs renew front-proxy-client
```

### Mise à jour du cluster

```bash
# Planifier la mise à jour
kubeadm upgrade plan

# Appliquer la mise à jour (premier control plane)
kubeadm upgrade apply v1.28.0

# Appliquer sur les autres control planes
kubeadm upgrade node

# Appliquer sur les workers
kubeadm upgrade node
```

### Configuration et maintenance

```bash
# Afficher la configuration
kubeadm config view

# Afficher les images nécessaires
kubeadm config images list

# Télécharger les images en avance
kubeadm config images pull

# Réinitialiser un nœud (suppression cluster)
kubeadm reset

# Réinitialiser avec nettoyage complet
kubeadm reset --force
```

### Troubleshooting

```bash
# Vérifier les prérequis
kubeadm init phase preflight

# Vérifier l'état du cluster
kubectl get nodes
kubectl get pods -n kube-system

# Logs des composants
journalctl -u kubelet
journalctl -u containerd
```

---

## minikube - Cluster Kubernetes local

### Démarrage et arrêt

```bash
# Démarrer minikube
minikube start

# Démarrer avec configuration spécifique
minikube start --driver=docker
minikube start --driver=virtualbox
minikube start --cpus=4 --memory=8192
minikube start --kubernetes-version=v1.28.0

# Démarrer avec plusieurs nœuds
minikube start --nodes=3

# Arrêter minikube
minikube stop

# Supprimer le cluster
minikube delete

# Supprimer tous les clusters
minikube delete --all
```

### Gestion du cluster

```bash
# Statut du cluster
minikube status

# Profils multiples
minikube start -p cluster1
minikube start -p cluster2
minikube profile list
minikube profile cluster1

# Mettre en pause le cluster
minikube pause

# Reprendre le cluster
minikube unpause

# SSH dans le nœud
minikube ssh
minikube ssh -n node2  # Multi-node
```

### Dashboard et addons

```bash
# Ouvrir le dashboard Kubernetes
minikube dashboard

# Lister les addons disponibles
minikube addons list

# Activer un addon
minikube addons enable metrics-server
minikube addons enable ingress
minikube addons enable dashboard
minikube addons enable registry

# Désactiver un addon
minikube addons disable ingress

# Addons populaires
minikube addons enable metrics-server    # Métriques CPU/RAM
minikube addons enable ingress          # Ingress NGINX ⚠️ projet retiré depuis mars 2026, voir TP6 pour la Gateway API
minikube addons enable dashboard        # Dashboard web
minikube addons enable registry         # Registry Docker local
minikube addons enable storage-provisioner  # Provisionneur de stockage
```

### Services et accès

```bash
# Obtenir l'URL d'un service
minikube service <service-name>
minikube service <service-name> --url

# Lister tous les services avec URLs
minikube service list

# Tunnel pour les LoadBalancer
minikube tunnel  # Nécessite les droits admin

# IP du cluster
minikube ip
```

### Registry Docker

```bash
# Utiliser le Docker daemon de minikube
eval $(minikube docker-env)

# Revenir au Docker local
eval $(minikube docker-env -u)

# Construire une image directement dans minikube
eval $(minikube docker-env)
docker build -t myapp:latest .

# Cache d'images
minikube cache add nginx:latest
minikube cache list
```

### Logs et debugging

```bash
# Logs de minikube
minikube logs

# Logs de la dernière heure
minikube logs --length=60m

# Suivre les logs en temps réel
minikube logs -f

# Informations système
minikube kubectl -- get nodes
minikube kubectl -- get pods -A
```

### Configuration et optimisation

```bash
# Afficher la configuration
minikube config view

# Définir des valeurs par défaut
minikube config set cpus 4
minikube config set memory 8192
minikube config set driver docker

# Voir les valeurs configurables
minikube config --help

# Mettre à jour minikube
minikube update-check
```

### Gestion multi-nœuds

```bash
# Démarrer avec plusieurs nœuds
minikube start --nodes=3

# Ajouter un nœud
minikube node add

# Lister les nœuds
minikube node list

# Supprimer un nœud
minikube node delete <node-name>

# SSH dans un nœud spécifique
minikube ssh -n <node-name>
```

### Volumes et montages

```bash
# Monter un dossier local
minikube mount /host/path:/minikube/path

# Créer un PV basé sur le système hôte
# (utiliser hostPath dans les manifests avec /data)
```

### Commandes utiles

```bash
# Version de minikube et kubectl
minikube version
minikube kubectl version

# Mettre à jour kubectl
minikube kubectl -- version

# Réinitialiser complètement
minikube delete --all --purge

# Aide
minikube --help
minikube start --help
```

---

## Workflows courants

### 1. Développement local avec minikube

```bash
# Démarrer l'environnement
minikube start --cpus=4 --memory=8192
minikube addons enable metrics-server
minikube addons enable ingress

# Utiliser le Docker de minikube
eval $(minikube docker-env)

# Builder l'image
docker build -t myapp:latest .

# Déployer
kubectl apply -f deployment.yaml

# Tester
minikube service myapp --url

# Voir les logs
kubectl logs -l app=myapp -f

# Arrêter
minikube stop
```

### 2. Installation cluster multi-nœuds avec kubeadm

```bash
# Sur le nœud master
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configurer kubectl
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Installer le réseau (exemple avec Flannel)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Obtenir la commande join
kubeadm token create --print-join-command

# Sur les workers
kubeadm join <master-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

# Vérifier
kubectl get nodes
```

### 3. Déploiement d'application avec kubectl

```bash
# Créer le namespace
kubectl create namespace myapp

# Appliquer les manifests
kubectl apply -f configmap.yaml -n myapp
kubectl apply -f secret.yaml -n myapp
kubectl apply -f deployment.yaml -n myapp
kubectl apply -f service.yaml -n myapp

# Vérifier le déploiement
kubectl get all -n myapp
kubectl rollout status deployment/myapp -n myapp

# Consulter les logs
kubectl logs -l app=myapp -n myapp -f

# Scaler
kubectl scale deployment myapp --replicas=5 -n myapp
```

### 4. Mise à jour d'application

```bash
# Mettre à jour l'image
kubectl set image deployment/myapp app=myapp:v2 -n myapp

# Suivre le rollout
kubectl rollout status deployment/myapp -n myapp

# Vérifier l'historique
kubectl rollout history deployment/myapp -n myapp

# Rollback si problème
kubectl rollout undo deployment/myapp -n myapp
```

### 5. Debugging d'application

```bash
# Voir les événements
kubectl get events -n myapp --sort-by=.metadata.creationTimestamp

# Décrire le pod problématique
kubectl describe pod <pod-name> -n myapp

# Voir les logs
kubectl logs <pod-name> -n myapp
kubectl logs <pod-name> -n myapp --previous  # Logs du conteneur crashé

# Exécuter des commandes dans le pod
kubectl exec -it <pod-name> -n myapp -- /bin/sh

# Vérifier les ressources
kubectl top pods -n myapp
kubectl top nodes

# Port forward pour tester
kubectl port-forward pod/<pod-name> 8080:80 -n myapp
```

### 6. Maintenance d'un nœud

```bash
# Empêcher de nouveaux pods
kubectl cordon <node-name>

# Évacuer les pods existants
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Effectuer la maintenance (mise à jour OS, etc.)
# ...

# Réactiver le nœud
kubectl uncordon <node-name>

# Vérifier
kubectl get nodes
```

### 7. Sauvegarde et restauration

```bash
# Exporter les ressources
kubectl get all --all-namespaces -o yaml > backup.yaml

# Sauvegarder etcd (sur le master)
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Restaurer
kubectl apply -f backup.yaml
```

---

## Ressources complémentaires

### Documentation officielle

- [kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)
- [kubeadm Reference](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

### Alias utiles

Ajoutez ces alias à votre `.bashrc` ou `.zshrc` :

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias kl='kubectl logs'
alias kex='kubectl exec -it'
alias ka='kubectl apply -f'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'

# Minikube
alias mk='minikube'
alias mks='minikube start'
alias mkst='minikube status'
alias mkd='minikube dashboard'
```

### Autocomplétion

```bash
# Bash
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

# Zsh
echo 'source <(kubectl completion zsh)' >>~/.zshrc
echo 'alias k=kubectl' >>~/.zshrc
echo 'compdef __start_kubectl k' >>~/.zshrc
```

---

## Conclusion

Ce document de référence couvre les commandes essentielles pour travailler avec Kubernetes :

- **kubectl** : Votre outil quotidien pour gérer le cluster et les applications
- **kubeadm** : Pour créer et maintenir des clusters de production
- **minikube** : Pour le développement local et l'apprentissage

Pour aller plus loin, consultez les TPs de cette formation qui mettent en pratique ces commandes dans des scénarios réels.
