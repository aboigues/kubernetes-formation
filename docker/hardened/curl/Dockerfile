# Image durcie : curlimages/curl:8.21.0
# Seule modification : mise à jour des paquets OS de la distribution.
# Ni l'entrypoint, ni la commande, ni l'utilisateur ne sont modifiés.
FROM curlimages/curl:8.21.0
USER root
RUN apk upgrade --no-cache
USER curl_user
