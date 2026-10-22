# Télémarché — l'application fil rouge

Deux images, construites depuis ce dossier et publiées sur Docker Hub :

| Image | Rôle | Port |
|---|---|---|
| `telemachlearning/telemarche-web:<version>` | la vitrine : page statique + relais de `/api/` vers l'API | 8080 |
| `telemachlearning/telemarche-api:<version>` | l'API catalogue et commandes ; contient aussi `/app/migrate` | 8080 |

Versions publiées : **`1.0`** et **`1.1`** (identiques hormis le numéro affiché : de quoi observer une mise à jour). La `1.2` n'existe **pas**, volontairement (panne n° 1 du TP03).

Les deux images sont *distroless* : ni shell, ni gestionnaire de paquets, utilisateur non-root `65532`. Elles tournent avec `readOnlyRootFilesystem: true` sans aucun volume.

## L'API

### Points d'entrée

| Chemin | Rôle |
|---|---|
| `GET /healthz` | **vivant** : 200 dès la fin du démarrage. Ne dépend jamais de la base |
| `GET /ready` | **prêt** : 200 si démarré, pas en cours d'arrêt, et stockage joignable (schéma présent) ; 503 sinon |
| `GET /version` | `{"service":"api","version":"1.0"}` |
| `GET /metrics` | métriques Prometheus (`telemarche_http_requests_total`, `telemarche_orders_total`, `telemarche_build_info`) |
| `GET /api/info` | version, nom du pod, mode de stockage, configuration lue |
| `GET /api/products`, `GET /api/products/{id}` | le catalogue |
| `GET /api/orders`, `POST /api/orders` | les commandes (`{"product_id": 1, "quantity": 2}`) |
| `GET /api/charge?ms=200` | occupe un cœur pendant `ms` millisecondes (1000 au plus) : pour l'autoscaling |

Pendant le démarrage, tout `/api/…` répond **503** : sans readiness probe, ces erreurs atteignent les clients.

À la réception de `SIGTERM`, `/ready` passe à 503 et l'API continue de servir pendant `SHUTDOWN_SECONDS`, le temps que le Service la retire : c'est ce qui rend un rolling update sans coupure.

### Variables d'environnement

| Variable | Défaut | Effet |
|---|---|---|
| `PORT` | `8080` | port d'écoute |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` ou `error`. **Toute autre valeur arrête le programme** (code 1) |
| `DB_HOST` | *(vide)* | vide : stockage **en mémoire** (perdu au redémarrage, propre à chaque pod) ; renseigné : **PostgreSQL** |
| `DB_PORT`, `DB_NAME` | `5432`, `telemarche` | connexion PostgreSQL |
| `DB_USER` ou `POSTGRES_USER` | `telemarche` | utilisateur (le premier défini l'emporte) |
| `DB_PASSWORD` ou `POSTGRES_PASSWORD` | *(vide)* | mot de passe |
| `CONFIG_FILE` | `/etc/api/application.properties` | fichier `clé=valeur` facultatif, **relu à chaque appel** de `/api/info` |
| `STARTUP_SECONDS` | `3` | durée du démarrage simulé |
| `SHUTDOWN_SECONDS` | `5` | délai de vidange après `SIGTERM` |
| `MEMORY_BALLAST_MB` | `0` | mémoire réservée au démarrage : pour provoquer un `OOMKilled` |

Les noms `POSTGRES_USER` / `POSTGRES_PASSWORD` sont acceptés pour qu'un même Secret serve à l'image `postgres` et à l'API.

### Migration

`/app/migrate` (même binaire) crée les tables et le catalogue de départ, puis se termine en code 0. Elle est idempotente. Tant qu'elle n'a pas tourné, l'API en mode PostgreSQL reste **non prête** (`/ready` : « schéma absent »).

## La vitrine

| Variable | Défaut | Effet |
|---|---|---|
| `PORT` | `8080` | port d'écoute |
| `API_URL` | `http://api` | où relayer `/api/…` ; le nom est résolu par le DNS du cluster **à chaque requête** |
| `LOG_LEVEL` | `info` | comme l'API |

Points d'entrée : `/` (la page), `/healthz`, `/ready`, `/version`, et `/api/…` relayé. Chaque requête relayée ouvre une **nouvelle connexion** vers l'API, ce qui rend visible la répartition de charge du Service.

## Construire

```bash
cd apps/telemarche
docker build --target api --build-arg VERSION=1.0 -t telemachlearning/telemarche-api:1.0 .
docker build --target web --build-arg VERSION=1.0 -t telemachlearning/telemarche-web:1.0 .
minikube image load telemachlearning/telemarche-api:1.0 telemachlearning/telemarche-web:1.0
```

La CI construit les deux versions et les charge dans son cluster avant chaque `verify.sh` ; le workflow `telemarche-images.yml` les publie sur Docker Hub.
