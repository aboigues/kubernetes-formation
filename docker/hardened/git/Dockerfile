# Image durcie : alpine/git:v2.54.0
# Deux modifications, et rien d'autre :
#   1. mise à jour des paquets OS de la distribution ;
#   2. un utilisateur final NON-ROOT (DS-0002).
# L'entrypoint et la commande restent inchangés.
#
# L'UID est numérique et non un nom : `runAsNonRoot: true` demande au kubelet de
# refuser un conteneur qui tournerait en root, et il ne sait le vérifier avant
# démarrage que sur un UID numérique. Un `USER nginx` le laisserait passer.
FROM alpine/git:v2.54.0
RUN apk upgrade --no-cache
# 65534 = nobody. Aucun chown nécessaire : vérifié, `git --version` fonctionne.
USER 65534
