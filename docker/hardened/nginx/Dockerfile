# Image durcie : nginx:1.29-alpine
# Deux modifications, et rien d'autre :
#   1. mise à jour des paquets OS de la distribution ;
#   2. un utilisateur final NON-ROOT (DS-0002).
# L'entrypoint et la commande restent inchangés.
#
# L'UID est numérique et non un nom : `runAsNonRoot: true` demande au kubelet de
# refuser un conteneur qui tournerait en root, et il ne sait le vérifier avant
# démarrage que sur un UID numérique. Un `USER nginx` le laisserait passer.
FROM nginx:1.29-alpine
RUN apk upgrade --no-cache \
    # nginx écrit son cache, son PID et ses fichiers temporaires en tant que
    # worker : sans ces chown, le master refuse de démarrer en non-root
    # (« mkdir() /var/cache/nginx/client_temp failed », puis « open() /run/nginx.pid »).
    && chown -R 101:101 /var/cache/nginx /run /etc/nginx/conf.d
# 101 = nginx
USER 101
