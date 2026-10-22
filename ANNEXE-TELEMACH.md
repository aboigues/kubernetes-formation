# Annexe — TELEMACH, l'assistant pédagogique de kubectl

> Facultatif. Les TP se font entièrement sans lui ; il aide à comprendre **pourquoi** une commande échoue.
> Projet : [aboigues/telemach-plugin-kubectl](https://github.com/aboigues/telemach-plugin-kubectl) — en **pré-version** (`0.1.0-rc.2` au 22/10/2026) : ses messages peuvent encore évoluer.

Quand une commande `kubectl` échoue, TELEMACH explique **en français** ce qui s'est passé : le concept Kubernetes en jeu, la cause probable et la correction, avec la commande prête à copier. Il ne modifie jamais rien : il se contente de lire.

```text
$ kubectl telemach diagnose service/panne-4 -n telemarche
✖ Le Service « panne-4 » ne désigne aucun pod, son selector ne correspond aux labels d'aucun pod.

   ✔ type               ClusterIP
   ✖ selector           app=panne4 : aucun pod

📘 Concept — label selector
   Un Service ne connaît pas ses pods par leur nom : il envoie le trafic aux
   pods dont les labels satisfont son selector. […]

🔎 Cause probable
   Aucun pod du namespace telemarche ne porte les labels « app=panne4 ». Les
   pods les plus proches portent « app=panne-4 […] »
```

*(sortie réelle de la panne n° 4 du TP03)*

## Installer (Linux, WSL2)

```bash
VERSION=0.1.0-rc.2
ARCH=$(uname -m); case "$ARCH" in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
FICHIER=kubectl-telemach_${VERSION}_linux_${ARCH}
curl -fsSLO "https://github.com/aboigues/telemach-plugin-kubectl/releases/download/v${VERSION}/${FICHIER}"
curl -fsSLO "https://github.com/aboigues/telemach-plugin-kubectl/releases/download/v${VERSION}/checksums.txt"
sha256sum --check --ignore-missing checksums.txt     # doit afficher « OK »
install -m 0755 -D "$FICHIER" ~/.local/bin/kubectl-telemach
kubectl telemach version
```

macOS, mises à jour et désinstallation : voir le [README du plugin](https://github.com/aboigues/telemach-plugin-kubectl#installation).

Pour que chaque erreur `kubectl` soit expliquée **automatiquement**, ajoutez à la fin de `~/.bashrc` (ou `~/.zshrc`, avec `zsh`) puis ouvrez un nouveau terminal :

```bash
eval "$(kubectl-telemach shell-init bash)"
```

## S'en servir pendant les TP

| Situation | Commande | TP où c'est utile |
|---|---|---|
| Vérifier un manifeste **avant** de l'appliquer (sans cluster) | `kubectl telemach check -f starter/` | tous, dès le TP01 |
| Un pod ne démarre pas (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) | `kubectl telemach diagnose pod/<nom>` | TP03, étape 7 |
| Un Service ne répond pas | `kubectl telemach diagnose service/<nom>` | TP03, étape 7 |
| Un rollout ne finit pas | `kubectl telemach diagnose deployment/<nom>` | TP03, étapes 4 et 5 |
| Revoir la dernière explication | `kubectl telemach last` | — |
| Approfondir, avec un exercice | `kubectl telemach deepen --exercise` | — |

> 💡 Bon réflexe : **diagnostiquez d'abord vous-même** (`describe`, `logs`, `get endpointslices`), puis comparez avec TELEMACH. L'objectif reste de savoir lire Kubernetes sans lui.

---

<div align="center">

**[Telemach Learning](https://www.telemach-learning.fr)** — Formations DevOps, Cloud & Conteneurs

</div>
