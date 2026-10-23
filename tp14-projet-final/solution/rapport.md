# Rapport d'incidents — mise en production de Télémarché

> Un incident par ligne, dans l'ordre où vous les avez rencontrés. Pour chacun : ce que vous avez **vu**, la commande qui vous l'a **montré**, la **cause**, et la **correction** apportée. `verify.sh` refuse un rapport incomplet.

| # | Symptôme observé | Commande de diagnostic | Cause | Correction |
|---|---|---|---|---|
| 1 | `db-0` et la PVC `donnees-db-0` restent `Pending` | `kubectl describe pvc donnees-db-0` | la StorageClass `ssd-rapide` n'existe pas dans le cluster | `storageClassName: standard` ; supprimer le StatefulSet et la PVC (le modèle de volume est immuable), puis réappliquer |
| 2 | `db-0` en `CreateContainerConfigError` | `kubectl describe pod db-0` (Events) | la clé `POSTGRES_PASS` n'existe pas dans le Secret `db-credentials` | `key: POSTGRES_PASSWORD` ; supprimer le pod `db-0` bloqué pour que le StatefulSet le recrée |
| 3 | Les pods du Job `migration` sont en `StartError`, le Job finit en échec | `kubectl describe pod -l app=migration` (`exec: "/app/migrer": stat /app/migrer: no such file or directory`) | la commande `/app/migrer` n'existe pas dans l'image | `command: ["/app/migrate"]` ; supprimer puis réappliquer le Job (son modèle de pod est immuable) |
| 4 | Les pods de l'API restent `0/1`, le rollout ne finit jamais | `kubectl describe pod -l app=api` (`Readiness probe failed: HTTP probe failed with statuscode: 404`) | la readiness probe interroge `/readyz`, un chemin qui n'existe pas | `path: /ready` |
| 5 | La vitrine répond, mais `/api/…` échoue : « API injoignable » | `kubectl get endpointslices -l kubernetes.io/service-name=api` (aucune adresse) | le Service `api` sélectionne `app: telemarche-api`, un label qu'aucun pod ne porte | `selector: app: api` |
