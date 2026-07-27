# Image durcie : curlimages/curl:8.21.0
# Seule modification : mise à jour des paquets OS de la distribution.
# L'entrypoint et la commande restent inchangés.
#
# Seule image durcie dont l'amont tourne DÉJÀ en non-root : il faut donc repasser
# root le temps du `apk upgrade`, puis restaurer l'utilisateur d'origine.
FROM curlimages/curl:8.21.0
USER root
RUN apk upgrade --no-cache
# 100 = curl_user, l'utilisateur de l'amont. Écrit en numérique et non par son nom :
# `runAsNonRoot: true` demande au kubelet de refuser un conteneur qui tournerait en
# root, et il ne sait le vérifier avant démarrage que sur un UID numérique.
USER 100
