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
| `hpa-example` | *(remplacement, voir plus bas)* | 801 → **0** |

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
- **`wordpress`, `grafana`, `postgres`, `adminer`, `cadvisor`, `jenkins`** — publiées et
  maintenues ailleurs, hors de ce dépôt.

## Construire et publier

```bash
# Construire une image
docker build -t telemachlearning/nginx:1.29-alpine docker/hardened/nginx/

# Toutes, avec vérification et mesure
./docker/hardened/build.sh

# Publier (droits sur l'org telemachlearning requis)
./docker/hardened/build.sh --push
```

**Convention de tag : le tag reflète celui de l'amont** (`nginx:1.29-alpine`,
`trivy:0.72.0`). `hpa-example` est versionnée à part (`1.0.0`) puisqu'elle ne dérive
d'aucune image amont.

**Toujours mesurer avant d'adopter une image durcie** — elle n'est pas forcément à 0 :

```bash
trivy image --scanners vuln --pkg-types os --severity CRITICAL,HIGH <image>
```
