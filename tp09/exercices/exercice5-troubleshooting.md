# Exercice 5 : Troubleshooting d'un cluster multi-noeud

## Objectif

Apprendre à diagnostiquer et résoudre les problèmes courants dans un cluster Kubernetes multi-noeud.

## Scénarios de troubleshooting

### Scénario 1 : Un nœud est en NotReady

**Symptômes :**
```bash
$ kubectl get nodes
NAME      STATUS      ROLES    AGE   VERSION
master1   Ready       master   10d   v1.28.0
worker1   Ready       worker   10d   v1.28.0
worker2   NotReady    worker   10d   v1.28.0
worker3   Ready       worker   10d   v1.28.0
```

**Diagnostic :**

1. **Vérifier les conditions du nœud :**
```bash
kubectl describe node worker2
# Regarder la section "Conditions" :
# - MemoryPressure
# - DiskPressure
# - PIDPressure
# - Ready (False indique un problème)
```

2. **Vérifier les événements :**
```bash
kubectl get events --all-namespaces --field-selector involvedObject.name=worker2
```

3. **Se connecter au nœud et vérifier kubelet :**
```bash
ssh worker2

# Vérifier le statut de kubelet
sudo systemctl status kubelet

# Voir les logs
sudo journalctl -u kubelet -f

# Logs récents avec erreurs
sudo journalctl -u kubelet --since "10 minutes ago" -p err
```

4. **Vérifier containerd :**
```bash
sudo systemctl status containerd
sudo journalctl -u containerd -f
```

5. **Vérifier les ressources système :**
```bash
# CPU et mémoire
top
free -h

# Espace disque
df -h

# Vérifier si le disque /var est plein
du -sh /var/*
du -sh /var/lib/containerd/*
```

**Causes courantes et solutions :**

| Cause | Solution |
|-------|----------|
| kubelet ne répond pas | `sudo systemctl restart kubelet` |
| containerd arrêté | `sudo systemctl restart containerd` |
| Disque plein | Nettoyer `/var/lib/containerd`, images inutilisées |
| Problème réseau | Vérifier les interfaces réseau, CNI |
| Certificats expirés | Régénérer avec `kubeadm certs renew` |
| OOM (Out of Memory) | Augmenter RAM ou évacuer des pods |

**Solution complète :**

```bash
# Sur le nœud worker2

# 1. Vérifier et redémarrer kubelet
sudo systemctl restart kubelet
sudo systemctl status kubelet

# 2. Si problème de disque, nettoyer les images
sudo crictl rmi --prune

# 3. Nettoyer les conteneurs arrêtés
sudo crictl rm $(sudo crictl ps -a -q --state=exited)

# 4. Vérifier la connectivité réseau
ping 8.8.8.8
ping master1

# 5. Retour au control plane
kubectl get nodes
# worker2 devrait être Ready maintenant
```

---

### Scénario 2 : Des pods restent en Pending

**Symptômes :**
```bash
$ kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
app-5d4b8c7f9b-abc12     1/1     Running   0          5m
app-5d4b8c7f9b-def34     0/1     Pending   0          5m
app-5d4b8c7f9b-ghi56     0/1     Pending   0          5m
```

**Diagnostic :**

1. **Décrire le pod :**
```bash
kubectl describe pod app-5d4b8c7f9b-def34

# Regarder la section "Events" :
# - FailedScheduling
# - Messages d'erreur du scheduler
```

2. **Vérifier les ressources disponibles :**
```bash
# Ressources sur tous les nœuds
kubectl top nodes

# Détails des allocations par nœud
kubectl describe nodes | grep -A 5 "Allocated resources"

# Ressources demandées par le pod
kubectl get pod app-5d4b8c7f9b-def34 -o yaml | grep -A 10 resources
```

3. **Vérifier les taints et tolerations :**
```bash
# Taints sur les nœuds
kubectl describe nodes | grep Taints

# Tolerations du pod
kubectl get pod app-5d4b8c7f9b-def34 -o yaml | grep -A 10 tolerations
```

4. **Vérifier les affinités :**
```bash
kubectl get pod app-5d4b8c7f9b-def34 -o yaml | grep -A 20 affinity
```

5. **Vérifier les PodDisruptionBudgets :**
```bash
kubectl get pdb --all-namespaces
```

**Causes courantes :**

| Cause | Vérification | Solution |
|-------|--------------|----------|
| Ressources insuffisantes | `kubectl top nodes` | Ajouter des nœuds ou réduire les requests |
| Taints non tolérés | `kubectl describe nodes \| grep Taints` | Ajouter tolerations ou supprimer taint |
| NodeSelector impossible | `kubectl get pod -o yaml` | Corriger le label ou labelliser les nœuds |
| Affinité non satisfaite | Events du pod | Ajuster l'affinité (required → preferred) |
| PVC non disponible | `kubectl get pvc` | Créer PV ou vérifier StorageClass |

**Exemples de résolution :**

**Cas 1 : Ressources insuffisantes**
```bash
# Identifier le problème
kubectl describe pod app-5d4b8c7f9b-def34
# Events: 0/3 nodes are available: 3 Insufficient cpu.

# Solutions :
# Option 1 : Réduire les requests
kubectl edit deployment app
# Modifier resources.requests.cpu

# Option 2 : Ajouter un nœud
# (procédure d'ajout de nœud)

# Option 3 : Scaler down d'autres apps
kubectl scale deployment other-app --replicas=2
```

**Cas 2 : Taint non toléré**
```bash
# Identifier
kubectl describe pod app-5d4b8c7f9b-def34
# Events: 0/3 nodes are available: 3 node(s) had taint {key: value}

# Solution 1 : Ajouter toleration
kubectl edit deployment app
# Ajouter dans spec.template.spec:
# tolerations:
# - key: "key"
#   operator: "Equal"
#   value: "value"
#   effect: "NoSchedule"

# Solution 2 : Supprimer le taint
kubectl taint nodes worker1 key-
```

**Cas 3 : NodeSelector impossible**
```bash
# Identifier
kubectl describe pod app-5d4b8c7f9b-def34
# Events: 0/3 nodes are available: 3 node(s) didn't match node selector.

# Vérifier le selector requis
kubectl get pod app-5d4b8c7f9b-def34 -o jsonpath='{.spec.nodeSelector}'

# Vérifier les labels des nœuds
kubectl get nodes --show-labels

# Solution : Labelliser un nœud
kubectl label nodes worker1 disktype=ssd
```

---

### Scénario 3 : Un nœud consomme 100% CPU

**Symptômes :**
```bash
$ kubectl top nodes
NAME      CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
master1   500m         25%    2000Mi          50%
worker1   4000m        100%   3000Mi          75%
worker2   600m         30%    2500Mi          62%
```

**Diagnostic :**

1. **Identifier les pods sur le nœud :**
```bash
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=worker1

# Trier par utilisation CPU
kubectl top pods --all-namespaces --sort-by=cpu | grep worker1
```

2. **Analyser chaque pod consommateur :**
```bash
# Détails du pod
kubectl describe pod <pod-name> -n <namespace>

# Logs du pod
kubectl logs <pod-name> -n <namespace>

# Si plusieurs conteneurs
kubectl logs <pod-name> -n <namespace> -c <container-name>

# Statistiques
kubectl top pod <pod-name> -n <namespace>
```

3. **Vérifier les limites de ressources :**
```bash
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 resources
```

4. **Vérifier les processus sur le nœud :**
```bash
ssh worker1
top
# Identifier les processus consommateurs
```

**Solutions :**

**Solution 1 : Limiter les ressources du pod**
```yaml
# Éditer le deployment
kubectl edit deployment <name> -n <namespace>

# Ajouter des limites :
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "1000m"    # Maximum 1 CPU
            memory: "1Gi"
```

**Solution 2 : Scaler horizontalement**
```bash
# Augmenter le nombre de replicas
kubectl scale deployment <name> -n <namespace> --replicas=5

# Configurer HPA (Horizontal Pod Autoscaler)
kubectl autoscale deployment <name> --cpu-percent=50 --min=3 --max=10
```

**Solution 3 : Évacuer et rééquilibrer**
```bash
# Cordon + Drain
kubectl cordon worker1
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data

# Les pods seront redistribués
kubectl get pods -o wide

# Après vérification, uncordon
kubectl uncordon worker1
```

**Solution 4 : Ajouter des affinités pour répartir**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - myapp
              topologyKey: kubernetes.io/hostname
```

---

### Scénario 4 : etcd ne répond plus sur un master

**Symptômes :**
```bash
$ kubectl get nodes
The connection to the server 192.168.1.100:6443 was refused

# Ou
Error from server: etcdserver: request timed out
```

**Diagnostic :**

1. **Vérifier les pods etcd :**
```bash
# Sur un master qui fonctionne
kubectl get pods -n kube-system | grep etcd

# Si kubectl ne fonctionne pas, vérifier directement
ssh master1
sudo crictl ps | grep etcd
```

2. **Vérifier la santé d'etcd :**
```bash
# Sur un master
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health

# Vérifier tous les membres
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list
```

3. **Vérifier les logs etcd :**
```bash
# Via journalctl
sudo journalctl -u etcd -f

# Via crictl
sudo crictl logs <etcd-container-id>
```

4. **Vérifier l'espace disque :**
```bash
df -h /var/lib/etcd
```

**Causes et solutions :**

| Cause | Vérification | Solution |
|-------|--------------|----------|
| Membre etcd down | `member list` | Redémarrer le conteneur |
| Perte de quorum | `member list` | Redémarrer les membres |
| Disque plein | `df -h` | Nettoyer ou agrandir |
| Corruption de données | Logs etcd | Restaurer depuis backup |
| Problème réseau | `ping` entre masters | Vérifier firewall/réseau |
| Certificats expirés | Logs | `kubeadm certs renew` |

**Solutions détaillées :**

**Solution 1 : Redémarrer etcd**
```bash
# Sur le master problématique
ssh master1

# Redémarrer le conteneur
sudo crictl stop <etcd-container-id>
# kubelet le redémarrera automatiquement

# Ou redémarrer kubelet
sudo systemctl restart kubelet
```

**Solution 2 : Retirer et rajouter un membre**
```bash
# Sur un master fonctionnel

# Lister les membres
sudo ETCDCTL_API=3 etcdctl member list

# Retirer le membre problématique
sudo ETCDCTL_API=3 etcdctl member remove <member-id>

# Sur le nœud à réintégrer
sudo kubeadm reset
sudo rm -rf /var/lib/etcd

# Rejoindre le cluster
sudo kubeadm join --control-plane ...
```

**Solution 3 : Restaurer depuis backup**
```bash
# ⚠️ ATTENTION : Arrête le cluster !

# Sur tous les masters, arrêter etcd
sudo systemctl stop kubelet

# Sur un master, restaurer
sudo ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore \
  --name=master1 \
  --initial-cluster=master1=https://192.168.1.10:2380,master2=https://192.168.1.11:2380,master3=https://192.168.1.12:2380 \
  --initial-advertise-peer-urls=https://192.168.1.10:2380

# Déplacer les données
sudo rm -rf /var/lib/etcd
sudo mv /var/lib/etcd-restore /var/lib/etcd

# Redémarrer
sudo systemctl start kubelet

# Répéter sur les autres masters avec leurs paramètres
```

---

## Commandes de diagnostic essentielles

### Nœuds
```bash
kubectl get nodes
kubectl describe node <node-name>
kubectl top nodes
kubectl get events --field-selector involvedObject.name=<node-name>
```

### Pods
```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl top pod <pod-name>
```

### Cluster
```bash
kubectl cluster-info
kubectl get componentstatuses
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Sur un nœud
```bash
sudo systemctl status kubelet
sudo systemctl status containerd
sudo journalctl -u kubelet -f
sudo crictl ps
sudo crictl images
top
df -h
```

## Checklist de troubleshooting

- [ ] Vérifier l'état des nœuds : `kubectl get nodes`
- [ ] Vérifier les events : `kubectl get events --all-namespaces`
- [ ] Vérifier les ressources : `kubectl top nodes`
- [ ] Vérifier les pods : `kubectl get pods --all-namespaces`
- [ ] Vérifier les logs kubelet sur le nœud problématique
- [ ] Vérifier l'espace disque : `df -h`
- [ ] Vérifier la connectivité réseau
- [ ] Vérifier les certificats : `kubeadm certs check-expiration`
- [ ] Vérifier etcd (clusters HA)
- [ ] Vérifier les taints et labels

## Outils utiles

- **kubectl** : CLI principal
- **crictl** : Interaction avec le container runtime
- **etcdctl** : Gestion d'etcd
- **journalctl** : Logs systemd
- **netshoot** : Pod de debug réseau
  ```bash
  kubectl run netshoot --rm -it --image=nicolaka/netshoot -- /bin/bash
  ```

## Ressources

- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [Debug Pods](https://kubernetes.io/docs/tasks/debug/debug-application/)
- [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)
- [Debug Cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
