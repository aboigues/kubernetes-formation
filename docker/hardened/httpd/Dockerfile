# Image durcie : httpd:2.4-alpine
# Deux modifications, et rien d'autre :
#   1. mise à jour des paquets OS de la distribution ;
#   2. un utilisateur final NON-ROOT (DS-0002).
# L'entrypoint et la commande restent inchangés.
#
# L'UID est numérique et non un nom : `runAsNonRoot: true` demande au kubelet de
# refuser un conteneur qui tournerait en root, et il ne sait le vérifier avant
# démarrage que sur un UID numérique. Un `USER nginx` le laisserait passer.
FROM httpd:2.4-alpine
RUN apk upgrade --no-cache \
    # httpd écrit son PID dans logs/ au démarrage : sans ce chown, il échoue sur
    # « could not create /usr/local/apache2/logs/httpd.pid ».
    && chown -R 82:82 /usr/local/apache2/logs
# 82 = www-data (Alpine)
USER 82
