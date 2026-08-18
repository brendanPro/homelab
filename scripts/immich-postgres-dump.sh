#!/usr/bin/env bash
# Dump logique de la DB Immich (Postgres 14) — procédure officielle Immich.
# Sortie locale : ~/backups/homelab/immich-postgres-YYYY-MM-DD/dump.sql.gz
#
# ⚠️ Ne dump pas les photos (PVC library). Métadonnées DB uniquement.
set -euo pipefail

NAMESPACE="${NAMESPACE:-infra}"
DEPLOY="${DEPLOY:-immich-postgres}"
DATE="${DATE:-$(date +%F)}"
DEST_DIR="${DEST_DIR:-${HOME}/backups/homelab/immich-postgres-${DATE}}"
DUMP_FILE="${DEST_DIR}/dump.sql.gz"

mkdir -p "${DEST_DIR}"

echo "==> Dump Immich postgres depuis ${NAMESPACE}/${DEPLOY}"
kubectl exec -n "${NAMESPACE}" "deploy/${DEPLOY}" -- \
  pg_dump --clean --if-exists --dbname=immich --username=postgres \
  | gzip > "${DUMP_FILE}"

ls -lh "${DUMP_FILE}"
gzip -t "${DUMP_FILE}"
echo "Dump OK: ${DUMP_FILE}"
