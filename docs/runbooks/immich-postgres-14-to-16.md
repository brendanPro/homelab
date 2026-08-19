# Runbook — Immich Postgres 14 → 16

> **Ne pas merger une PR Renovate qui bump seulement le tag Postgres.**
> Un data directory PG14 est incompatible avec un serveur PG16
> (`FATAL: database files are incompatible with server`).
> Vu en prod le 2026-08-18 après le merge de [#18](https://github.com/brendanPro/homelab/pull/18)
> (rollback : commit `2267fbe`).

## Pourquoi pas un bump in-place

| Élément | Valeur actuelle |
|---------|-----------------|
| Image | `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` |
| Cible | `16-vectorchord0.4.3-pgvectors0.2.0` |
| PVC | `immich-postgres` (OpenEBS local, **Retain**, rpinode1) |
| Taille DB | ~166 MiB (2026-08-18) |
| Extensions | `vchord 0.4.3`, `vector 0.8.1` — **déjà VectorChord**, pas de migration pgvecto.rs |

Procédure alignée sur [Backup and Restore Immich](https://immich.app/docs/administration/backup-and-restore) :
dump logique → **nouveau** data dir PG16 vide → restore.

Le PVC `immich-postgres` (PG14) n’est **jamais** monté sous l’image 16.

## Prérequis

- [ ] Fenêtre ~20 min (Immich UI down pendant dump + cutover)
- [ ] Context kubectl homelab (`kubernetes-admin@kubernetes`)
- [ ] ArgoCD : pouvoir suspendre l’app `immich`
- [ ] Espace disque local pour le dump (~50 MiB gzip)
- [ ] Manifests `apps/infra/immich/migration/` présents (hors ArgoCD)

## Rollback à tout moment (avant suppression du PVC 14)

1. Remettre `claimName: immich-postgres` et le tag `14-vectorchord0.4.3-pgvectors0.2.0`
2. Scale `immich-postgres-pg16` à 0 si encore présent
3. Push / unsuspend ArgoCD

Le PV OpenEBS PG14 reste tant que le PVC n’est pas prune.

---

## Procédure

### 0. État de référence

```bash
kubectl config current-context   # kubernetes-admin@kubernetes
kubectl get pods -n infra -l app.kubernetes.io/name=immich
kubectl exec -n infra deploy/immich-postgres -- \
  psql -U postgres -d immich -c "SELECT version();"
kubectl exec -n infra deploy/immich-postgres -- \
  psql -U postgres -d immich -c "SELECT extname, extversion FROM pg_extension ORDER BY 1;"
```

Noter : version Postgres 14, `vchord`, nombre d’assets :

```bash
kubectl exec -n infra deploy/immich-postgres -- \
  psql -U postgres -d immich -c "SELECT count(*) AS assets FROM asset;"
```

### 1. Suspendre ArgoCD

Évite que selfHeal remette le replica du server pendant le dump.

```bash
kubectl patch application immich -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 2. Geler les écritures (scale down server)

Le ML peut rester up (pas de writes SQL métier). Redis inchangé.

```bash
kubectl scale deployment immich-server -n infra --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/component=server -n infra --timeout=120s
```

### 3. Dump PG14

```bash
./scripts/immich-postgres-dump.sh
```

Attend : `~/backups/homelab/immich-postgres-$(date +%F)/dump.sql.gz` + `gzip -t` OK.

### 4. Démarrer PG16 sur un PVC neuf

Le dossier `migration/` n’est **pas** dans l’Application ArgoCD.

```bash
kubectl apply -k apps/infra/immich/migration
kubectl rollout status -n infra deployment/immich-postgres-pg16 --timeout=180s
```

Vérifier un data dir **16** (pas d’erreur “initialized by PostgreSQL version 14”) :

```bash
kubectl logs -n infra deploy/immich-postgres-pg16 --tail=30
kubectl exec -n infra deploy/immich-postgres-pg16 -- \
  psql -U postgres -d immich -c "SELECT version();"
```

### 5. Restore dans PG16

```bash
./scripts/immich-postgres-restore.sh
```

Contrôles :

```bash
kubectl exec -n infra deploy/immich-postgres-pg16 -- \
  psql -U postgres -d immich -c "SELECT extname, extversion FROM pg_extension ORDER BY 1;"
kubectl exec -n infra deploy/immich-postgres-pg16 -- \
  psql -U postgres -d immich -c "SELECT count(*) AS assets FROM asset;"
```

Les counts doivent matcher l’étape 0. Extensions : `vchord` + `vector` présents.

### 6. Cutover GitOps (un seul commit)

Dans `apps/infra/immich/base/` :

1. Ajouter `- pvc-postgres-pg16.yaml` dans `kustomization.yaml` `resources:`
2. Tag postgres → `16-vectorchord0.4.3-pgvectors0.2.0`
3. Dans `deploy-postgres.yaml` : `claimName: immich-postgres-pg16`

**Garder** `pvc-postgres.yaml` (PG14) dans les resources — `Prune=false` n’est pas sur l’ancien PVC, donc **ne pas retirer** ce fichier tant que le rollback est possible. ArgoCD ne le detachera pas du PV.

Le Deployment `immich-postgres` (labels `component: postgres`) pointe alors vers le PVC 16. Le Service existant `immich-postgres` ne change pas.

Push → réactiver ArgoCD **ou** apply ciblé puis unsuspend :

```bash
# après push, réactiver
kubectl patch application immich -n platform --type merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": { "prune": true, "selfHeal": true },
      "syncOptions": ["CreateNamespace=true"]
    }
  }
}'
argocd app sync immich   # si le CLI est dispo
```

Attendre le rollout :

```bash
kubectl rollout status -n infra deployment/immich-postgres --timeout=180s
kubectl get pods -n infra | grep immich-postgres
```

Le pod principal doit tourner l’image **16** et être Ready. Le pod `immich-postgres-pg16` (temporaire) peut alors être retiré.

### 7. Retirer le Postgres temporaire + remonter Immich

```bash
kubectl delete -k apps/infra/immich/migration
# le PVC pg16 doit RESTER (Bound par le deploy principal) :
# si kustomize delete le PVC, NE PAS confirmer — le PVC est aussi dans base/
# En pratique `kubectl delete -k migration` tente de supprimer le PVC listé.
# Donc supprimer seulement deploy + svc temporaires :
kubectl delete deploy,svc -n infra immich-postgres-pg16
```

Ne **pas** `kubectl delete -k apps/infra/immich/migration` après cutover : ce kustomize référence le PVC pg16.

```bash
kubectl scale deployment immich-server -n infra --replicas=1
kubectl rollout status -n infra deployment/immich-server --timeout=180s
```

Vérifs :

- UI Immich (Tailscale) : login, bibliothèque, un asset
- `kubectl logs -n infra deploy/immich-server --tail=50` : pas d’erreur DB
- `kubectl exec -n infra deploy/immich-postgres -- psql -U postgres -d immich -c "SHOW server_version;"`

### 8. Observation puis ménage PG14

Garder le PVC `immich-postgres` (PG14) jusqu’à validation UI — **fait 2026-08-19**.

1. Retirer `pvc-postgres.yaml` des `resources:` et supprimer le fichier
2. `kubectl delete pvc immich-postgres -n infra` (le **PV** reste grâce à `Retain`)
3. Optionnel : libérer l’espace disque sur rpinode1  
   `/var/openebs/local/pvc-f7cd7aa7-734b-4e4a-a3c2-f087575fa964`

---

## Interdit

- Merger Renovate `ghcr.io/immich-app/postgres` **major** sans ce runbook
- Monter le PVC PG14 sous une image 16
- `prune` / delete du PVC PG14 avant validation UI + observation
- `helm` (kustomize uniquement)

## Fichiers

| Chemin | Rôle |
|--------|------|
| `apps/infra/immich/migration/` | Overlay hors ArgoCD (PG16 temporaire). Copie du PVC aussi dans `base/pvc-postgres-pg16.yaml` (ajoutée aux `resources:` au cutover). |
| `scripts/immich-postgres-dump.sh` | `pg_dump \| gzip` |
| `scripts/immich-postgres-restore.sh` | restore officiel Immich |
