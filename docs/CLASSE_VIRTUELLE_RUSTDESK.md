# Classe virtuelle : se connecter à son poste avec RustDesk

En classe virtuelle, chaque participant travaille sur un **poste distant AlmaLinux** dans une salle de formation. On y accède de deux façons :

- **le bureau à distance RustDesk** : on voit l'écran du poste et on y ouvre un terminal. Rien d'autre à installer ;
- **SSH à travers un tunnel RustDesk** : on travaille depuis le terminal de son propre ordinateur. Le copier-coller y est plus fiable que dans le bureau à distance, et l'affichage plus net.

Le poste a une adresse privée (`192.168.<salle>.<poste>`) : il n'est **pas joignable en SSH directement** depuis Internet. Le tunnel RustDesk sert de passerelle.

## Ce qu'il vous faut

Votre **fiche d'accès**, remise par le formateur :

| Information | À quoi elle sert |
|---|---|
| ID RustDesk | identifie votre poste dans RustDesk |
| Mot de passe RustDesk | ouvre la session RustDesk (bureau ou tunnel) |
| Compte et mot de passe Linux du poste | ouvre la session SSH |

> 🔒 Ces identifiants sont personnels : ne les collez ni dans le chat de la classe, ni dans un fichier du dépôt.

## Étape 1 — Installer le client RustDesk

Téléchargez le client **de bureau** pour votre système (Windows, macOS ou Linux) depuis [rustdesk.com](https://rustdesk.com) ou les [versions publiées sur GitHub](https://github.com/rustdesk/rustdesk/releases).

Le **client web** de RustDesk (dans un navigateur) suffit pour le bureau à distance, mais ne propose **pas** le tunnel de l'étape 3.

## Étape 2 — Ouvrir le bureau à distance

1. Dans le client, saisissez l'**ID RustDesk** dans le champ « Contrôler un bureau distant », puis **Se connecter**.
2. Saisissez le **mot de passe RustDesk**.
3. Le bureau du poste s'affiche : ouvrez un terminal.

À ce stade, vous pouvez déjà suivre toute la formation. L'étape 3 est un confort, pas une obligation.

## Étape 3 — Travailler en SSH depuis votre ordinateur (facultatif)

### Créer le tunnel

1. Dans le client RustDesk, l'ID de votre poste figure maintenant dans la liste des appareils récents. Ouvrez son menu (**⋮** ou clic droit), puis choisissez **Tunnel TCP** (« TCP tunneling » en anglais).
2. Ajoutez une redirection :

   | Port local | Hôte distant | Port distant |
   |---|---|---|
   | `2222` | `127.0.0.1` | `22` |

3. Validez, saisissez le **mot de passe RustDesk**. La fenêtre du tunnel indique qu'elle **attend une connexion** : c'est normal, elle attend votre `ssh`.
4. **Laissez cette fenêtre ouverte** pendant toute la session : la fermer coupe le SSH.

### Se connecter

Depuis un terminal **de votre ordinateur** :

```bash
ssh <compte-linux>@127.0.0.1 -p 2222
```

<details>
<summary>🔍 Cette commande, option par option</summary>

- `<compte-linux>` : le compte Linux du poste, indiqué sur votre fiche (pas l'ID RustDesk).
- `127.0.0.1` : votre propre ordinateur. C'est là que RustDesk écoute, puis il relaie la connexion jusqu'au poste.
- `-p 2222` : le port local choisi pour le tunnel. SSH utilise 22 par défaut, qu'il faut donc remplacer.
</details>

Le mot de passe demandé ici est celui du **compte Linux**, pas celui de RustDesk.

### Pièges

- **Sous Windows, lancez `ssh` depuis PowerShell ou l'invite de commandes, pas depuis WSL.** RustDesk tourne sous Windows et écoute sur le `127.0.0.1` de Windows. En WSL2 (réseau NAT, le mode par défaut), `127.0.0.1` désigne la machine virtuelle Linux, pas Windows : la connexion n'atteint jamais le tunnel. `ssh` est fourni avec Windows 10 et 11.
- **Le message `Impossible de rechercher des fichiers: GDBus.Error…` après une commande inconnue est sans gravité.** AlmaLinux essaie de vous proposer le paquet qui fournit la commande, et ce service n'existe que dans une session graphique. Seule la première ligne compte : `commande inconnue`.
- **Le port 2222 est déjà pris sur votre ordinateur** : choisissez-en un autre (`2223`…), dans le tunnel **et** dans la commande `ssh`.

### Dépannage

En cas d'échec, relancez avec `ssh -v` pour obtenir le détail :

| Symptôme | Cause probable |
|---|---|
| `Connection refused` immédiat | Rien n'écoute sur le port local : la fenêtre du tunnel est fermée, ou le port saisi diffère |
| La connexion s'ouvre puis se ferme aussitôt (`Connection closed`, `kex_exchange_identification`) | Le tunnel n'atteint pas le serveur SSH du poste : hôte distant mal saisi (mettez `127.0.0.1`), ou `sshd` arrêté sur le poste. Vérifiez depuis le bureau à distance : `systemctl status sshd` |
| La commande reste bloquée sans réponse | Le tunnel n'est pas ouvert vers le poste : mot de passe RustDesk refusé, ou tunnel pas encore validé |

Si rien ne fonctionne, revenez au bureau à distance (étape 2) : il ne dépend pas du tunnel.

## Et ensuite

Une fois connecté, préparez le poste : [installer kubectl et minikube](./INSTALLER_KUBECTL_MINIKUBE.md).
