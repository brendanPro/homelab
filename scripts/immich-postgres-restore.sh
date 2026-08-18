#!/usr/bin/env bash
# Restore d'un dump Immich dans le Postgres 16 (pod temporaire).
# Docs Immich : search_path public,pg_catalog + transaction unique.
set -euo pipefail

NAMESPACE="${NAMESPACE:-infra}"
DEPLOY="${DEPLOY:-immich-postgres-pg16}"
DATE="${DATE:-$(date +%F)}"
DUMP_FILE="${DUMP_FILE:-${HOME}/backups/homelab/immich-postgres-${DATE}/dump.sql.gz}"

if [[ ! -f "${DUMP_FILE}" ]]; then
  echo "Dump introuvable: ${DUMP_FILE}" >&2
  exit 1
fi

echo "==> Restore ${DUMP_FILE} vers ${NAMESPACE}/${DEPLOY}"
gunzip --stdout "${DUMP_FILE}" \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | kubectl exec -i -n "${NAMESPACE}" "deploy/${DEPLOY}" -- \
      psql --dbname=immich --username=postgres --single-transaction --set ON_ERROR_STOP=on

echo "Restore OK"
