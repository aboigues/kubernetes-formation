# TP10 — Installer un cluster avec kubeadm

> Durée estimée : 2 h · Sur trois **machines** AlmaLinux 10 (pas minikube)
> Prérequis : TP01 (composants d'un cluster). Les VM du lab de formation, **ou** le lab Vagrant fourni (`lab/`) : 4 processeurs et 7 Go de mémoire libres, ce que `lab/verifier-poste.sh` contrôle.

## 🎬 Le contexte

Jusqu'ici, minikube montait le cluster pour vous. Pour la production sur site, Télémarché a reçu trois serveurs AlmaLinux. Personne ne les a préparés : à vous d'en faire un cluster Kubernetes, puis d'y vérifier que la boutique tourne.

L'outil officiel pour cela est **kubeadm**. Il ne crée pas les machines et n'installe ni le runtime, ni le réseau des pods. Il fait le cœur du travail : certificats, control plane, jonction des nœuds.

| Nœud | IP (réseau du cluster) | Rôle | Ce qui y tourne |
|---|---|---|---|
| `cp-1` | `10.30.0.11` | control plane | kube-apiserver, etcd, kube-scheduler, kube-controller-manager, kubelet, containerd |
| `worker-1` | `10.30.0.21` | nœud de travail | kubelet, containerd, kube-proxy |
| `worker-2` | `10.30.0.22` | nœud de travail | kubelet, containerd, kube-proxy |

Réseau des pods : **`10.244.0.0/16`** (Calico). Réseau des Services : `10.96.0.0/12`. Aucun des deux ne doit chevaucher celui des nœuds : en salle, les postes sont en `192.168.<salle>.<poste>`, c'est pourquoi on n'utilise **pas** le réseau par défaut de Calico, `192.168.0.0/16`.

## 🤔 Pourquoi pas kind, ou minikube, en plusieurs nœuds ?

kind (*Kubernetes in Docker*) et minikube savent monter plusieurs nœuds : c'est ce que fait le TP09, avec `minikube node add`. kind utilise même kubeadm en interne. Mais ces « nœuds » sont des **conteneurs**, sur **une seule machine**, préparés d'avance. Tout ce que ce TP vous fait faire, ils le font à votre place, ou ne le montrent pas :

| | kind, ou minikube avec le pilote Docker | Trois vraies machines (ce TP) |
|---|---|---|
| **Système** | une image de nœud toute prête : containerd, kubelet et kubeadm installés, réglages faits | à préparer sur chaque nœud (étape 2) : c'est là que naissent la plupart des pannes d'installation |
| **Noyau** | **un seul**, celui de votre poste, partagé par tous les nœuds : modules, sysctl, cgroups, swap | un par nœud, à configurer sur chacun |
| **Réseau** | un pont Docker local, une seule carte, des adresses attribuées pour vous | deux cartes, un pare-feu, l'IP annoncée à choisir (`--node-ip`), des plages qui ne doivent pas se chevaucher |
| **Installation** | `kubeadm init` et `join` lancés pour vous, configuration générée | vous écrivez la configuration et faites rejoindre les nœuds (jeton, empreinte de la CA) |
| **Pannes** | la machine tombe, tous les nœuds tombent avec elle | un nœud peut tomber, redémarrer ou perdre le réseau **seul** |
| **Exploitation** | on jette le cluster et on le recrée | certificats à renouveler, etcd à sauvegarder, versions à monter nœud par nœud |

kind reste l'outil idéal pour tester des manifestes ou faire tourner une CI sur plusieurs nœuds. Il ne vous apprend pas à **installer et exploiter** des machines. Pour cela, il faut des machines : c'est l'objet de ce TP.

## 🎯 Objectif vérifiable

Trois nœuds `Ready` en Kubernetes **v1.37.1**, un control plane sain (etcd compris), Calico sur chaque nœud, et Télémarché qui tourne sur les deux workers, sa vitrine joignant l'API d'un autre nœud. `./verify.sh` le contrôle **sur votre cluster** (étape 8).

> ⚠️ Ce TP n'est pas rejoué par la CI : elle n'a pas de machines à installer. Ses fichiers y sont seulement contrôlés (syntaxe, trous). La validation de référence est faite sur le lab Vagrant ci-dessous.

---

## Étape 1 — Les machines

**En formation**, vos trois VM sont fournies : vérifiez que `cp-1`, `worker-1` et `worker-2` se joignent par leur nom (`ping -c1 worker-1` depuis `cp-1`).

**En autonomie**, le lab Vagrant crée trois VM **nues**, sans rien de Kubernetes :

```bash
export TP="$(git rev-parse --show-toplevel)/tp10-installer-cluster"   # le TP, d'où que vous soyez dans le dépôt
cd lab
./verifier-poste.sh         # Vagrant, fournisseur, ressources, réseaux : corrigez chaque ✗ avant d'aller plus loin
vagrant up                  # 5 à 10 minutes la première fois (téléchargement de la box)
vagrant status
vagrant ssh cp-1            # « exit » pour revenir
```

> **Sous WSL2**, Vagrant refuse de travailler dans `/mnt/c/…` (il ne peut pas y garantir les permissions des fichiers), et seul le fournisseur `libvirt` (KVM) y fonctionne. Avant `./verifier-poste.sh` :
>
> ```bash
> cp -r lab ~/tp10-lab && cd ~/tp10-lab           # ou clonez le dépôt dans votre home Linux
> export VAGRANT_DEFAULT_PROVIDER=libvirt         # dans CHAQUE nouveau terminal
> ```
>
> Sans cette variable, Vagrant tente VirtualBox et s'arrête aussitôt : « Vagrant is unable to use the VirtualBox provider from the Windows Subsystem for Linux ». Les starters, eux, restent dans le dépôt : complétez-les là, `$TP` y mène (dans un nouveau terminal, refaites aussi `export TP=<chemin du dépôt>/tp10-installer-cluster`).

Chaque VM a **deux** cartes réseau : la première pour Vagrant (SSH, Internet), la seconde, en `10.30.0.0/24`, pour le cluster. Retenez-le : c'est la source du piège de l'étape 2.

## Étape 2 — Préparer chaque nœud

Le même travail sur les trois nœuds : des modules noyau, le routage, plus de swap, SELinux en mode permissif, le pare-feu, **containerd**, puis les paquets **kubeadm, kubelet, kubectl**. Ce travail est fourni, tout fait, dans `outils/preparer-noeud.sh` : lisez-le (chaque étape est commentée), puis lancez-le sur chaque nœud, avec **son** IP :

```bash
# depuis le dossier du lab, pour chaque nœud :
vagrant upload "$TP"/outils/preparer-noeud.sh /tmp/preparer-noeud.sh cp-1
vagrant ssh cp-1 -c 'sudo bash /tmp/preparer-noeud.sh 10.30.0.11'
# … puis worker-1 avec 10.30.0.21, worker-2 avec 10.30.0.22
```

Le script commence par mesurer le nœud (processeurs, mémoire, place sous `/var`) et s'arrête, sans rien installer, s'il est trop petit pour son rôle : un nom en `cp-*` réclame ce qu'exige kubeadm pour un control plane. Dans la suite du script, trois points méritent qu'on s'y arrête :

- **`br_netfilter`** : sur AlmaLinux 10, ce module n'est plus livré avec le noyau de base. Il vient de `kernel-modules-extra`, et dans la version **exacte** du noyau lancé. Le script s'en occupe.
- **`SystemdCgroup = true`** : containerd et le kubelet doivent gérer les cgroups de la même façon. Un désaccord, et le control plane redémarre en boucle : c'est la panne classique des installations kubeadm.
- **`--node-ip`** : avec deux cartes réseau, le kubelet annoncerait l'adresse de la **première**, celle de Vagrant. Sous VirtualBox, c'est la **même** sur les trois VM (`10.0.2.15`), et le cluster serait incohérent.

```bash
vagrant ssh cp-1 -c 'systemctl status kubelet --no-pager | head -5'
```

Le kubelet redémarre en boucle (`activating (auto-restart)`) : c'est **normal**, il attend sa configuration, que `kubeadm init` va écrire.

## Étape 3 — Initialiser le control plane

Complétez `starter/kubeadm-config.yaml` (`# TODO 1` à `4`), copiez-le sur `cp-1`, puis :

```bash
vagrant upload "$TP"/starter/kubeadm-config.yaml /tmp/kubeadm-config.yaml cp-1
vagrant ssh cp-1
# --- sur cp-1 ---
kubeadm config validate --config /tmp/kubeadm-config.yaml
sudo kubeadm init --config /tmp/kubeadm-config.yaml
```

Lisez la sortie, phase par phase (`[certs]`, `[kubeconfig]`, `[control-plane]`, `[etcd]`, `[upload-config]`, `[mark-control-plane]`, `[bootstrap-token]`, `[addons]`) :

1. vérifications préalables (`preflight`), téléchargement des images ;
2. création de l'**autorité de certification** et des certificats, dans `/etc/kubernetes/pki/` ;
3. écriture des kubeconfigs des composants dans `/etc/kubernetes/` ;
4. lancement du control plane en **pods statiques** : leurs manifestes sont dans `/etc/kubernetes/manifests/`, et c'est le kubelet qui les démarre, sans API server ;
5. marquage du nœud `control-plane` (label + taint), jeton de jonction, addons CoreDNS et kube-proxy.

## Étape 4 — Accéder au nouveau cluster

Toujours sur `cp-1` :

```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
ls /etc/kubernetes/manifests/
```

> 🎯 **Avant de lancer la commande suivante, prédis :** le control plane tourne. Dans quel état est le nœud `cp-1` ? Et les pods CoreDNS ?

```bash
kubectl get nodes
kubectl get pods -n kube-system -o wide
kubectl describe node cp-1 | grep -i network
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`cp-1` est **`NotReady`**, et CoreDNS reste **`Pending`**. Le message est explicite : `container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized`. kubeadm n'installe **pas** de réseau des pods. Tant qu'il n'y en a pas, le nœud refuse les pods qui en ont besoin (CoreDNS). Les pods du control plane, eux, tournent déjà : ils utilisent le réseau de la machine (`hostNetwork`), et la colonne IP montre `10.30.0.11`.
</details>

## Étape 5 — Le réseau des pods : Calico

Complétez `starter/calico.yaml` (`# TODO 5`). Le CIDR des pods déclaré à `kubeadm init` **doit** être celui que distribue le CNI. Copiez le fichier sur `cp-1`, puis installez dans cet ordre : les **types d'objets** de Calico (CRD), son **opérateur**, et seulement quand les types sont enregistrés, votre **installation** :

```bash
vagrant upload "$TP"/starter/calico.yaml /tmp/calico.yaml cp-1     # depuis le dossier du lab
vagrant ssh cp-1
# --- sur cp-1 ---
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=60s
kubectl apply -f /tmp/calico.yaml
kubectl get pods -n calico-system --watch     # Ctrl-C quand calico-node est 1/1
kubectl get nodes
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubectl create -f <URL>` : crée les objets d'un fichier lu directement à cette adresse. `create` échoue si un objet existe déjà, contrairement à `apply`.
- `kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=60s` : attend que le type `Installation` soit **enregistré** par l'API server (condition `Established`), avant de créer un objet de ce type.
- `kubectl get pods -n calico-system --watch` : suit les pods de Calico jusqu'à `Ctrl-C`.
</details>

L'ordre n'est pas décoratif. Sans `operator-crds.yaml`, c'est l'opérateur qui crée les types en démarrant, quelques secondes plus tard : `calico.yaml` arrive alors trop tôt (`no matches for kind "Installation" in version "operator.tigera.io/v1" — ensure CRDs are installed first`), et le `kubectl wait` lui-même échoue (`NotFound`).

Le fichier de l'éditeur (`custom-resources.yaml`) installe aussi l'API server de Calico, Goldmane et Whisker (observabilité des flux). Sur les VM du lab, ces composants saturent le control plane : notre `calico.yaml` ne garde que le réseau.

## Étape 6 — Joindre les workers

Sur `cp-1`, demandez la commande de jonction (le jeton expire au bout de 24 h) :

```bash
sudo kubeadm token create --print-join-command
```

Puis, sur **chaque** worker, exécutez-la en root :

```bash
vagrant ssh worker-1 -c 'sudo kubeadm join cp-1:6443 --token … --discovery-token-ca-cert-hash sha256:…'
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `kubeadm token create --print-join-command` : crée un jeton de jonction et affiche la commande `kubeadm join` complète, prête à copier.
- `vagrant ssh worker-1 -c '…'` : exécute la commande sur `worker-1` sans ouvrir de session.
- `kubeadm join cp-1:6443` : l'adresse de l'API server à rejoindre. `--token` : le jeton qui authentifie le nouveau nœud. `--discovery-token-ca-cert-hash` : l'empreinte de l'autorité de certification du cluster (voir la question ci-dessous).
</details>

> ❓ **Question** : à quoi sert `--discovery-token-ca-cert-hash` ? Que risquerait un worker qui rejoindrait le cluster avec le jeton seul ? (Indice : comment le worker sait-il qu'il parle au **vrai** `cp-1` ?)

```bash
kubectl get nodes -o wide       # sur cp-1 : trois nœuds, INTERNAL-IP en 10.30.0.x
```

## Étape 7 — Les certificats et la sauvegarde d'etcd

```bash
# --- sur cp-1 ---
sudo kubeadm certs check-expiration
```

> ❓ **Question** : les certificats des composants expirent dans **un an**, les autorités de certification dans **dix**. Que se passe-t-il le jour où `apiserver` expire ? Pourquoi un cluster mis à jour au moins une fois par an ne rencontre-t-il jamais ce problème ? (Indice : `kubeadm upgrade apply` les renouvelle.)

etcd contient **tout** l'état du cluster. Sauvegardez-le avec `etcdctl`, présent dans le pod d'etcd. Le fichier est écrit dans `/var/lib/etcd`, un dossier de la machine `cp-1` monté dans le pod :

```bash
# --- sur cp-1 ---
ETCDCTL="kubectl -n kube-system exec etcd-cp-1 -- etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key"
$ETCDCTL endpoint health
$ETCDCTL snapshot save /var/lib/etcd/sauvegarde.db
kubectl -n kube-system exec etcd-cp-1 -- etcdutl snapshot status /var/lib/etcd/sauvegarde.db -w table
sudo ls -lh /var/lib/etcd/
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `ETCDCTL="…"` : range une longue commande dans une variable, pour ne pas la retaper. `$ETCDCTL endpoint health` la déroule, suivie des arguments.
- `kubectl -n kube-system exec etcd-cp-1 -- etcdctl` : lance `etcdctl` dans le pod d'etcd, où il est installé.
- `--endpoints=https://127.0.0.1:2379` : l'adresse d'etcd, vue depuis son propre pod.
- `--cacert`, `--cert`, `--key` : etcd n'accepte que des clients munis d'un certificat. On présente celui du serveur etcd, et l'autorité qui l'a signé.
- `snapshot save` : écrit une copie cohérente de toute la base. `etcdutl snapshot status -w table` : en affiche le résumé (taille, nombre de clés, révision), sous forme de tableau.
</details>

⚠️ Une sauvegarde laissée **sur** le control plane disparaît avec lui. En production : copiez-la ailleurs, chiffrée (elle contient tous les Secrets), et **testez la restauration** (voir « Pour aller plus loin »).

## Étape 8 — Validez depuis votre poste

Récupérez le kubeconfig d'administration, en remplaçant le nom `cp-1` (inconnu de votre poste) par son IP :

```bash
# depuis le dossier du lab
vagrant ssh cp-1 -c 'sudo cat /etc/kubernetes/admin.conf' 2>/dev/null \
  | sed 's#https://cp-1:6443#https://10.30.0.11:6443#' > ~/.kube/tp10.conf
chmod 600 ~/.kube/tp10.conf
export KUBECONFIG=~/.kube/tp10.conf
kubectl get nodes
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `vagrant ssh cp-1 -c 'sudo cat /etc/kubernetes/admin.conf'` : affiche le kubeconfig d'administration de `cp-1`. `2>/dev/null` masque les avertissements de Vagrant, qui pollueraient le fichier.
- `| sed 's#ancien#nouveau#'` : remplace le nom `cp-1`, inconnu de votre poste, par son IP. Le `#` sert de séparateur à la place du `/` habituel, qui apparaît dans les URL.
- `> ~/.kube/tp10.conf` : écrit le résultat dans ce fichier. `chmod 600` le rend lisible par vous seul : il contient la clé de l'administrateur du cluster.
- `export KUBECONFIG=~/.kube/tp10.conf` : ce terminal utilise désormais ce fichier au lieu de `~/.kube/config`.
</details>

Puis, depuis le dossier du TP :

```bash
./verify.sh              # vérifie le cluster et VOS fichiers (starter/)
./verify.sh solution     # (option) avec les fichiers de référence
```

`verify.sh` contrôle les nœuds, le control plane, etcd et Calico. Ensuite il déploie Télémarché dans un namespace jetable et vérifie que la vitrine joint l'API **d'un autre nœud**, à travers le réseau des pods. Comptez 3 à 5 minutes.

## Étape 9 — Démonter

**Revenir à minikube**, depuis votre poste :

```bash
unset KUBECONFIG                # kubectl reprend ~/.kube/config, donc minikube
rm -f ~/.kube/tp10.conf         # l'accès administrateur au cluster du TP10
```

**Recommencer l'installation sans recréer les machines** (c'est aussi la seule voie sur les VM fournies en formation). Sur chaque nœud, les workers d'abord :

```bash
sudo kubeadm reset -f           # défait init ou join : control plane, etcd, certificats, configuration du kubelet
sudo rm -rf /etc/cni/net.d      # la configuration de Calico, que reset ne touche pas
rm -f ~/.kube/config            # sur cp-1 : l'accès copié à l'étape 4
sudo reboot                     # efface les interfaces et règles réseau laissées par Calico et kube-proxy
```

La préparation de l'étape 2 (containerd, paquets) reste en place : reprenez à l'étape 3.

**Supprimer le lab Vagrant**, depuis le dossier du lab :

```bash
vagrant destroy -f              # les trois VM et leurs disques
vagrant status                  # « not created » pour les trois
```

**Récupérer aussi la place de la box** (environ 500 Mo, retéléchargée au prochain `vagrant up`) :

```bash
vagrant box remove almalinux/10
# Avec libvirt, la box a aussi été copiée dans le stockage de libvirt :
virsh -c qemu:///system vol-list default | grep almalinux
virsh -c qemu:///system vol-delete --pool default <nom affiché par la commande précédente>
```

---

## 💡 Indices

<details>
<summary><code>kubeadm init</code> s'arrête aux vérifications préalables</summary>

Lisez la ligne `[ERROR …]`. Les plus fréquentes : `NumCPU` (le control plane veut 2 processeurs), `Swap` (le swap est encore actif : `swapon --show`), `FileContent--proc-sys-net-ipv4-ip_forward` (le script de l'étape 2 n'est pas allé au bout : relancez-le), `CRI` (containerd ne répond pas : `sudo systemctl status containerd`).
</details>

<details>
<summary>Le control plane redémarre en boucle après <code>kubeadm init</code></summary>

Le suspect n° 1 est un désaccord de cgroups entre containerd et le kubelet. `grep SystemdCgroup /etc/containerd/config.toml` doit répondre `true`, et `cgroupDriver: systemd` doit figurer dans `kubeadm-config.yaml`. Pour recommencer proprement : `sudo kubeadm reset -f`, corrigez, puis relancez `kubeadm init`.
</details>

<details>
<summary>Les nœuds annoncent tous la même IP, ou une IP en 10.20.x / 10.0.2.15</summary>

Le `--node-ip` est absent ou faux : `cat /etc/sysconfig/kubelet` sur le nœud. Relancez `preparer-noeud.sh` avec l'IP **de ce nœud** (étape 2), puis `sudo systemctl restart kubelet`.
</details>

<details>
<summary><code>kubeadm join</code> : « token id … is invalid » ou expiré</summary>

Le jeton vit 24 h. Redemandez la commande sur `cp-1` : `sudo kubeadm token create --print-join-command`.
</details>

<details>
<summary>calico-node reste <code>0/1</code> pendant de longues minutes</summary>

`kubectl describe pod -n calico-system <pod>` : `BGP not established` au début est normal (les nœuds se découvrent). Si les probes expirent (`timed out after 5s`), le control plane manque de ressources : `free -m` et `uptime` sur `cp-1`. Il lui faut 3 Go de mémoire.
</details>

---

## 📖 Où chercher (documentation officielle)

- **Installer kubeadm** : https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- **Créer un cluster avec kubeadm** : https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- **Runtimes de conteneurs** (containerd, cgroups) : https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- **Configuration de kubeadm (v1beta4)** : https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/
- **Certificats** : https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/
- **Sauvegarder et restaurer etcd** : https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- **Calico sur un cluster kubeadm** : https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises

---

## 🚀 Pour aller plus loin

1. **Restaurer etcd.** Supprimez un Deployment, puis restaurez `sauvegarde.db` avec `etcdutl snapshot restore` vers un **nouveau** dossier, et faites pointer le manifeste `/etc/kubernetes/manifests/etcd.yaml` dessus. Le Deployment revient-il ?
2. **Une mise à jour de version.** Recommencez le lab avec `K8S_VERSION` réglée sur la dernière 1.36 dans `outils/preparer-noeud.sh`, puis montez en 1.37 : sur `cp-1`, `kubeadm upgrade plan` puis `kubeadm upgrade apply`, et sur chaque nœud, l'un après l'autre, `drain` (TP09), `kubeadm upgrade node`, mise à jour du kubelet, `uncordon`.
3. **Un control plane hautement disponible.** Pourquoi `controlPlaneEndpoint` est-il un **nom** (`cp-1:6443`) et pas une IP ? Que faudrait-il pour ajouter `cp-2` et `cp-3` (`kubeadm join --control-plane`, répartiteur de charge, nombre impair de membres etcd) ?
4. **Le pare-feu activé.** Démarrez firewalld sur les trois nœuds (`sudo systemctl enable --now firewalld`), relancez `preparer-noeud.sh`, et vérifiez que le cluster fonctionne toujours. Quels ports a-t-il ouverts, et pour qui ?

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

© 2026 Telemach Learning — DEVOPS-012 · DEVOPS-010

</div>
