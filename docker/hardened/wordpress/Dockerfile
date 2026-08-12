# Image durcie : wordpress:7.0-php8.5-apache
# Deux modifications, et rien d'autre :
#   1. mise à jour des paquets OS de la distribution ;
#   2. un utilisateur final NON-ROOT (DS-0002).
# L'entrypoint et la commande restent inchangés.
#
# L'UID est numérique et non un nom : `runAsNonRoot: true` demande au kubelet de
# refuser un conteneur qui tournerait en root, et il ne sait le vérifier avant
# démarrage que sur un UID numérique. Un `USER www-data` le laisserait passer.
#
# 33 = www-data, exactement le `runAsUser` qu'impose déjà
# tp02/exercice10/wordpress-app.yaml : l'image et le manifest disent enfin la même
# chose. Vérifié : Apache démarre et sert du HTTP (302 vers l'installeur).
#
# 6.8-php8.3-apache n'est plus reconstruite depuis le 2025-12-02 (CVE OS non
# corrigées en amont) ; 7.0-php8.5-apache reste activement reconstruite —
# même bascule que docker-formation (cf. son post-mortem du 17/07).
FROM wordpress:7.0-php8.5-apache
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
USER 33
