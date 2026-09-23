# Feuille de route — Nouvelle génération du dépôt (v2)

> Statut : **chantier acté, non programmé** — à lancer quand le temps le permettra.
> Décidé le 23/09/2026, à l'issue de la session de formation DEVOPS-010 du 21 au 23 septembre 2026.

Ce dépôt va être transformé en profondeur. Pour que les utilisateurs sachent qu'ils changent de
génération, la refonte sera publiée sous forme d'une **nouvelle release majeure (v2.0)**, et l'état
actuel sera figé dans une release **v1** préalable.

---

## Pourquoi une v2

Retours après la session de septembre 2026 :

1. **Les exercices ne permettent pas de vraiment progresser.** Les TP fournissent des manifests
   YAML déjà complets et des README de 1 000 à 3 400 lignes qui mêlent cours et solutions : le
   stagiaire applique et recopie plus qu'il ne construit.
2. **L'écart entre les supports de formation et le dépôt est trop important.** Le programme compte
   6 modules en 3 jours, le dépôt 11 TP qui ne s'y superposent pas (voir « Alignement » ci-dessous).

Le dépôt [`aboigues/docker-formation`](https://github.com/aboigues/docker-formation), construit sur une
autre philosophie, s'est révélé nettement plus efficace : **des fichiers à compléter soi-même**,
vérifiés par un script. C'est le modèle retenu pour la v2.

## Le modèle à reproduire (docker-formation)

| | docker-formation (modèle) | kubernetes-formation (v1, actuel) |
|---|---|---|
| Format d'un TP | `README.md` + `starter/` + `solution/` + `verify.sh` | `README.md` + `exerciceNN/` avec les YAML complets + `test-tpN.sh` |
| Travail du stagiaire | compléter des fichiers à trous (`______`, `# TODO n`, indice en commentaire) | appliquer ou recopier des manifests fournis |
| Validation | `./verify.sh [starter\|solution]` : un seul script pour l'essai et la correction, bibliothèque commune `scripts/lib.sh` | scripts de test non reliés à un exercice à compléter |
| README | 130 à 310 lignes : contexte, objectif vérifiable, étapes, indices, « où chercher », pour aller plus loin | 1 000 à 3 400 lignes : cours complet et solutions intégrées |
| Enchaînement | fil rouge applicatif réutilisé d'un TP à l'autre | TP largement indépendants |
| Nommage | `tpNN-theme` (`tp07-compose`...) | `tpNN` seul |
| Docs transverses | `BONNES-PRATIQUES.md`, `POST-MORTEM.md` | `AMELIORATIONS.md`, `GUIDE_UTILISATEUR.md`, `docs/` |

## Cible v2

Chaque TP devient :

```
tpNN-theme/
  README.md     contexte, objectif vérifiable, étapes, indices, où chercher, pour aller plus loin
  starter/      manifests à trous : un « # TODO » par notion du module, avec indice
  solution/     manifests complets
  verify.sh     déploie starter/ ou solution/ sur un cluster local et contrôle l'objectif
```

- `verify.sh` contrôle un **objectif observable** : Pod `Ready`, Service joignable, rollout terminé,
  Secret monté, PVC lié, release Helm installée, cible Prometheus active...
- Le **cours sort des README** : il vit dans les supports de formation. Le README ne garde que ce qui
  sert à faire l'exercice.
- Un **fil rouge applicatif** traverse les TP : une même application que l'on déploie, expose,
  configure, rend persistante, package avec Helm puis supervise.
- Une bibliothèque commune `scripts/lib.sh` (attente de rollout, requêtes HTTP, messages d'étape),
  sur le modèle de docker-formation.

## Alignement sur le programme (6 modules, 3 jours)

| Module du programme | TP v1 concernés | Écart constaté |
|---|---|---|
| M1 — Architecture (3 h) | tp01 | OK |
| M2 — Workloads (5 h) | tp02 | OK |
| M3 — Services et Gateway API (4 h) | tp08, tp11 | tp08 dépasse largement M3 |
| M4 — Configuration, Secrets, Volumes (4 h) | tp02 (partiel), tp03 | OK |
| M5 — Helm (3 h) | tp06 | tp06 (Helm + CI/CD + ArgoCD) dépasse largement M5 |
| M6 — Monitoring (2 h) | tp04 | OK |
| Hors programme | tp05 (RBAC), tp07 (Compose vers K8s), tp09 (multi-nœud), tp10 (synthèse), `ckad-preparation` | à classer en « pour aller plus loin » |

Objectif v2 : un parcours principal qui colle aux 6 modules, et un parcours « pour aller plus loin »
clairement séparé.

## Actions

### Avant la refonte
- [ ] Publier une release **v1.x** figeant l'état actuel. Des stagiaires ont reçu des recommandations
      qui citent les TP par leur numéro actuel (tp02 à tp11, `ckad-preparation`) : la release v1 leur
      garantit un point d'accès stable.
- [ ] Faire le point sur `AMELIORATIONS.md` (décembre 2025) : garder ce qui reste pertinent, archiver le reste.

### Refonte
- [ ] Définir le fil rouge applicatif et le découpage des TP du parcours principal (un TP par notion clé des 6 modules).
- [ ] Créer `scripts/lib.sh` et le gabarit de TP (README, starter, solution, verify.sh).
- [ ] **TP pilote** : convertir un premier TP (tp02, manifests) au nouveau format et le valider avant de généraliser.
- [ ] Convertir les autres TP du parcours principal.
- [ ] Reclasser les TP hors programme dans un parcours « pour aller plus loin », au même format.
- [ ] Adapter la CI : exécuter `verify.sh solution` pour chaque TP.
- [ ] Ajouter `BONNES-PRATIQUES.md` et `POST-MORTEM.md` sur le modèle de docker-formation.

### Publication
- [ ] Réécrire le README principal : parcours, prérequis, table de correspondance v1 vers v2.
- [ ] Publier la release **v2.0** avec des notes expliquant le changement de génération et renvoyant vers v1 pour l'ancien format.
- [ ] Mettre à jour les supports de formation (références aux TP).
