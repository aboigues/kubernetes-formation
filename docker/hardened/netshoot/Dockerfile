# Image durcie : nicolaka/netshoot:v0.16
# Deux modifications, et rien d'autre :
#   1. mise à jour des paquets OS de la distribution ;
#   2. un utilisateur final NON-ROOT (DS-0002).
# L'entrypoint et la commande restent inchangés.
#
# L'UID est numérique et non un nom : `runAsNonRoot: true` demande au kubelet de
# refuser un conteneur qui tournerait en root, et il ne sait le vérifier avant
# démarrage que sur un UID numérique. Un `USER nginx` le laisserait passer.
FROM nicolaka/netshoot:v0.16
RUN apk upgrade --no-cache
# 65534 = nobody. Vérifié : `ping` et `curl` fonctionnent en non-root. Les outils
# qui exigent CAP_NET_RAW ou CAP_NET_ADMIN (tcpdump en mode promiscuité, iptables)
# demandent que le manifest les accorde explicitement — c'est le bon endroit pour
# ce choix, pas l'image.
USER 65534
