# Images durcies

Sources des images publiées sur [hub.docker.com/u/telemachlearning](https://hub.docker.com/u/telemachlearning)
et utilisées par les TPs à la place des images amont.

## Pourquoi elles existent

Le scan hebdomadaire (`.github/workflows/scan-images.yml`) bloque sur les CVE de
**paquets OS**. Deux mesures ont montré que monter les tags amont ne suffit pas :

- `nginx:1.29-alpine`, le tag le plus récent qui existe, porte **13 CVE OS** — l'image
  amont est en retard sur les paquets Alpine.
- `grafana` **empire** en montant : 18 CVE en 10.0.0, 25 en 12.3.8.

Une image dérivée qui fait `apk/apk upgrade` corrige ce retard. C'est tout ce que font
ces Dockerfiles : **entrypoint, commande et utilisateur restent inchangés**.

| Image | Amont | CVE OS avant → après |
|---|---|---|
| `nginx` | `nginx:1.29-alpine` | 13 → **0** |
| `git` | `alpine/git:v2.54.0` | 17 → **0** |
| `httpd` | `httpd:2.4-alpine` | 16 → **0** |
| `trivy` | `aquasec/trivy:0.72.0` | 13 → **0** |
| `netshoot` | `nicolaka/netshoot:v0.16` | 7 → **0** |
| `curl` | `curlimages/curl:8.21.0` | 1 → **0** |
| `wordpress` | `wordpress:6.8-php8.3-apache` | 652 → **0** *(corrigeables)* |
| `hpa-example` | *(remplacement, voir plus bas)* | 801 → **0** |

`wordpress` est le seul cas où la colonne compte les CVE **corrigeables** et non le
total : l'image garde **163 CVE OS sans correctif publié** dans Debian 13, avant comme
après. Aucun `apt upgrade` ne les enlèvera, et la barrière ne bloque pas dessus — elle
ne compte que le corrigeable. Le durcissement en retire tout de même 652, dont les 401
de `linux-libc-dev` et les 53 d'ImageMagick.

## Le cas `hpa-example`

`registry.k8s.io/hpa-example` tourne sur **Debian 8 « jessie », en fin de vie depuis
2020** : ses dépôts apt sont archivés, donc `apt-get update` échoue. Elle est
**indurcissable** — d'où un remplacement plutôt qu'une image dérivée.

Son contrat tient en deux points : répondre en HTTP, et brûler du CPU pour que le HPA
ait quelque chose à mesurer. PHP n'y jouait aucun rôle. C'est donc un binaire Go
statique dans une image `scratch` : **aucun paquet OS, 0 CVE par construction**, et
jamais de re-durcissement à prévoir. 8 Mo contre 156 Mo.

⚠️ **La calibration est le point délicat.** Recopier les 1 000 001 tours de `sqrt` de
l'original donne ~2 ms par requête — Go est deux ordres de grandeur plus rapide que
PHP, et le HPA n'aurait rien à mesurer : la démo ne scalerait jamais. Le compteur est
à **20 000 000 tours**, mesuré à ~300 ms/requête contre 279 ms pour l'original.
`BURN_ITERATIONS` permet de recalibrer sans reconstruire.

Le port est **8080** et non 80, pour tourner en non-root sans `CAP_NET_BIND_SERVICE`.
Les Services des TPs exposent toujours 80 : les commandes des élèves sont inchangées.

## Ce qui n'est PAS ici, et pourquoi

- **`fluentd`** — durcissement construit et mesuré : il reste à **21 CVE**. Aucune n'a
  de correctif publié dans Debian, `apt upgrade` n'y change rien. Ne pas refaire ce test.
- **`cassandra:4.1`** (45 CVE) — 0 corrigeable, même conclusion.
- **`tensorflow/tensorflow:*-gpu`** — mesuré le 2026-07-17, **abandonnée** (elle ne
  figure plus dans aucun manifest). Ne pas la réintroduire :

  | Tag | CVE OS | dont corrigeables | Après `apt upgrade` |
  |---|---|---|---|
  | `2.18.0-gpu` | 381 | 199 | ~182 |
  | `2.21.0-gpu` | 253 | 71 | ~182 |

  Les deux tags convergent vers le même plancher de **~182 CVE Ubuntu sans correctif
  amont** : durcir ne pouvait pas la rendre verte, pour 3,8 Go à construire, publier et
  maintenir. La variante CPU n'aidait pas non plus (`2.21.0` : 252 CVE OS — les CVE sont
  dans la base Ubuntu, pas dans les couches CUDA).

  Elle servait de **décor** dans `tp09/examples/taints-tolerations-examples.yaml` : un
  Job GPU qui ne peut pas s'exécuter (aucun nœud `gpu: nvidia` dans un cluster de
  formation, et `train.py` n'existe dans aucune de ces images). Le fichier est appliqué
  en `--dry-run=client`. Ce qui enseigne la planification GPU, c'est le `nodeSelector`,
  la toleration et la ressource `nvidia.com/gpu` — pas l'image. Remplacée par
  `python:3.13-alpine` : **0 CVE, 17 Mo**, et `command: ["python", "train.py"]` reste
  cohérent.
- **`grafana`, `postgres`, `adminer`, `cadvisor`, `jenkins`** — publiées et maintenues
  ailleurs, hors de ce dépôt. (`wordpress` était dans ce cas jusqu'au 2026-07-27 : sa
  source est désormais versionnée ici, parce que le rebuild mensuel ne peut reconstruire
  que ce dont il a le Dockerfile.)

## Images à ne PAS monter — le bump est contre-productif

Mesuré le 2026-07-17. La barrière ne compte que les CVE **OS** : une image à 0 CVE OS
est verte même si le scan complet lui trouve des CVE de binaires.

- **`docker.elastic.co/elasticsearch/elasticsearch:8.17.7`** (et Kibana, qui doit rester
  aligné) — **0 CVE OS aujourd'hui, donc verte**. Monter la ferait *rougir* :
  `8.19.10` introduit 2 CVE OS Ubuntu, `9.2.4` bascule sur une base RedHat à 25 CVE OS
  (dont 14 sans correctif). Le scan complet ne gagnerait que 7 CVE. Ne pas monter.
- **`telemachlearning/netshoot:v0.16`** — déjà la dernière version amont. Ses ~167 CVE
  sont dans les binaires Go des outils qu'elle embarque, pas dans l'OS : 0 CVE OS.
- **`postgres:15/17-alpine`, `mysql:8.4`, `cassandra:4.1`** — tags roulants déjà à jour.
  Leurs CVE viennent de binaires Go embarqués (`gosu`), pas des paquets OS.

## Un durcissement se périme — d'où le rebuild mensuel

**Une image durcie est une photo, pas un état.** `apk/apt upgrade` applique les
correctifs disponibles le jour du build ; dès que la distribution en publie d'autres,
l'image publiée est en retard sans que rien n'ait changé ici.

Ce n'est pas théorique : `netshoot` et `wordpress`, publiées à **0 CVE OS corrigeable
le 2026-07-16**, en portaient **15 et 3 le 2026-07-27** — onze jours.

`.github/workflows/rebuild-hardened-images.yml` reconstruit et republie donc toutes ces
images **le 1er de chaque mois** (et à la demande). Il tourne à 02:00 UTC, avant le
premier scan hebdomadaire possible. Il exige les secrets `DOCKERHUB_USERNAME` et
`DOCKERHUB_TOKEN`, avec droit d'écriture sur l'org `telemachlearning`.

⚠️ **`--no-cache --pull` n'est pas une précaution, c'est la condition du durcissement.**
Sans eux, Docker réutilise le layer `apk/apt upgrade` du build précédent : l'image
reconstruite est **identique** à l'ancienne et le rebuild est un no-op silencieux.
Mesuré le 2026-07-27 sur `netshoot` — 15 CVE avant, **15 après avec cache**, 0 sans.
`build.sh` les passe systématiquement.

## Construire et publier

```bash
# Construire une image (--no-cache --pull, voir ci-dessus)
docker build --no-cache --pull -t telemachlearning/nginx:1.29-alpine docker/hardened/nginx/

# Toutes, avec vérification et mesure
./docker/hardened/build.sh

# Publier (droits sur l'org telemachlearning requis)
./docker/hardened/build.sh --push
```

`build.sh` affiche `corrigeables/total` et **sort en échec si une image garde des CVE
OS corrigeables** — exactement ce sur quoi la barrière de `scan-images.yml` bloquera.
Le chiffre qui décide est le premier : le total inclut des CVE sans correctif publié,
sur lesquelles ni le durcissement ni la barrière n'ont prise.

**Convention de tag : le tag reflète celui de l'amont** (`nginx:1.29-alpine`,
`trivy:0.72.0`). `hpa-example` est versionnée à part (`1.0.0`) puisqu'elle ne dérive
d'aucune image amont.

**Toujours mesurer avant d'adopter une image durcie** — elle n'est pas forcément à 0 :

```bash
trivy image --scanners vuln --pkg-types os --severity CRITICAL,HIGH <image>
```
