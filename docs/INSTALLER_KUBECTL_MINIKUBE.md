# Préparer son poste : kubectl et minikube

Ce guide prépare un poste **Linux** (AlmaLinux en salle ou en [classe virtuelle](./CLASSE_VIRTUELLE_RUSTDESK.md), ou WSL2) pour les TP. Comptez 5 minutes. Il faut un compte avec `sudo` et un accès à Internet.

## Étape 1 — Récupérer le dépôt et contrôler le poste

```bash
git clone https://github.com/aboigues/kubernetes-formation.git
cd kubernetes-formation
./scripts/preflight.sh
```

`preflight.sh` ne modifie rien : il liste ce qui manque. Sur un poste neuf, on obtient typiquement :

```
  ✓ Docker joignable (29.4.0)
  ✗ kubectl absent : …
  ✗ minikube absent : …
  ⚠ helm absent : nécessaire seulement au TP12
```

Si **Docker** est en ✗, arrêtez-vous et prévenez le formateur : minikube en dépend, et son installation sort du cadre de ce guide.

## Étape 2 — Installer kubectl et minikube

Copiez le bloc entier :

```bash
ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')

# kubectl : la dernière 1.37.x, alignée sur le cluster des TP
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable-1.37.txt)/bin/linux/$ARCH/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# minikube : la dernière version publiée
curl -LO "https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-$ARCH"
sudo install -m 0755 "minikube-linux-$ARCH" /usr/local/bin/minikube && rm "minikube-linux-$ARCH"

hash -r
kubectl version --client     # attendu : v1.37.x
minikube version             # attendu : v1.39.0 ou plus
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- `ARCH=$(uname -m | sed …)` : l'architecture du processeur (`x86_64`, `aarch64`), traduite dans le vocabulaire des téléchargements Kubernetes (`amd64`, `arm64`).
- `curl -Ls …/stable-1.37.txt` : renvoie le numéro de la dernière version 1.37.x publiée. Le `curl -LO` qui l'entoure télécharge le binaire de cette version ; `-L` suit les redirections, `-O` garde le nom du fichier.
- `…/releases/latest/download/…` : GitHub redirige vers le binaire de la dernière version de minikube.
- `sudo install -m 0755 <fichier> /usr/local/bin/…` : copie le binaire dans un dossier du `PATH` et le rend exécutable (`0755` : lecture et exécution pour tous, écriture pour le propriétaire).
- `hash -r` : le shell oublie les chemins de commandes qu'il avait mémorisés, utile si une ancienne version existait ailleurs.
</details>

Relancez le contrôle :

```bash
./scripts/preflight.sh
```

Attendu : plus aucun ✗. Les ⚠ sur `helm`, TELEMACH et « aucun cluster joignable » sont normaux à ce stade.

## Étape 3 — Vérifier que minikube démarre

C'est le seul test qui prouve que tout fonctionne (accès aux registres d'images, Docker, réseau) :

```bash
minikube start --kubernetes-version=v1.37.1 --cpus=2 --memory=4g
kubectl get nodes
```

Attendu : un nœud `minikube` en `Ready`. Le premier démarrage télécharge environ 1 Go et prend quelques minutes.

C'est exactement la commande du TP01 : vous pouvez laisser ce cluster tourner et commencer le TP.

## Étape 4 — Helm (seulement pour le TP12)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
helm version                 # attendu : v4.x
```

Le script officiel de Helm détecte l'architecture, télécharge la dernière version 4 et l'installe dans `/usr/local/bin` (il demande le mot de passe `sudo`).

## Pièges

- **`Impossible de rechercher des fichiers: GDBus.Error…`** après une commande inconnue, en SSH : sans gravité. AlmaLinux tente de proposer le paquet manquant, et ce service n'existe qu'en session graphique. Seule la ligne `commande inconnue` compte.
- **L'ancienne version répond toujours**, un alias masque le binaire, un ancien cluster garde son ancienne version de Kubernetes : voir les pièges de la section [Installer ou mettre à jour kubectl et minikube](../README.md#installer-ou-mettre-à-jour-kubectl-et-minikube) du README.
- **`minikube start` échoue sur `--kubernetes-version=v1.39.0`** : minikube 1.39 est la version de l'outil, le cluster des TP tourne en Kubernetes **1.37**. Gardez la commande ci-dessus.
