# Image durcie : aquasec/trivy:0.72.0
# Seule modification : mise à jour des paquets OS de la distribution.
# Ni l'entrypoint, ni la commande, ni l'utilisateur ne sont modifiés.
FROM aquasec/trivy:0.72.0
USER root
RUN apk upgrade --no-cache
USER root
