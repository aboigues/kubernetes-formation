# Image durcie : wordpress:6.8-php8.3-apache
# Seule modification : mise à jour des paquets OS de la distribution.
# Ni l'entrypoint, ni la commande, ni l'utilisateur ne sont modifiés.
FROM wordpress:6.8-php8.3-apache
USER root
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
USER root
