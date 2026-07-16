# Image durcie : httpd:2.4-alpine
# Seule modification : mise à jour des paquets OS de la distribution.
# Ni l'entrypoint, ni la commande, ni l'utilisateur ne sont modifiés.
FROM httpd:2.4-alpine
USER root
RUN apk upgrade --no-cache
USER root
