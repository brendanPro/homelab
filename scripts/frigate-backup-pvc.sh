#!/usr/bin/env bash
# Backup manuel des PVC Frigate (OpenEBS local sur rpinode2).
# Crée /var/backups/homelab/frigate-YYYY-MM-DD/ sur le nœud.
#
# Par défaut : backup config uniquement (~rapide, critique).
# Storage 700Gi : rebind PV (Retain) suffit en phase 2 ; tar optionnel (très long).
#   BACKUP_STORAGE=1 ./scripts/frigate-backup-pvc.sh
set -euo pipefail

DATE="${DATE:-$(date +%F)}"
JOB_NAME="frigate-pvc-backup-${DATE}"
NAMESPACE="${NAMESPACE:-frigate}"
BACKUP_STORAGE="${BACKUP_STORAGE:-0}"

CONFIG_PATH="${CONFIG_PATH:-/var/openebs/local/pvc-46a92f8d-414e-4b27-b9fd-5c27e63676cf}"
STORAGE_PATH="${STORAGE_PATH:-/var/openebs/local/pvc-aeee2766-b65f-4b28-8f38-67d76356b696}"
NODE="${NODE:-rpinode2}"

STORAGE_MOUNT=""
STORAGE_TAR=""
if [[ "${BACKUP_STORAGE}" == "1" ]]; then
  STORAGE_MOUNT="
        - name: storage
          mountPath: /source/storage
          readOnly: true"
  STORAGE_TAR="
          tar czf \"\$DEST/frigate-storage.tgz\" -C /source/storage ."
fi

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 604800
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        kubernetes.io/hostname: ${NODE}
      containers:
      - name: backup
        image: alpine:3.20
        command:
        - /bin/sh
        - -c
        - |
          set -eux
          DEST=/backups/homelab/frigate-${DATE}
          mkdir -p "\$DEST"
          tar czf "\$DEST/frigate-config.tgz" -C /source/config .
          ${STORAGE_TAR}
          ls -lh "\$DEST"
          tar tzf "\$DEST/frigate-config.tgz" | head -15
          echo "Backup OK: \$DEST"
        volumeMounts:
        - name: config
          mountPath: /source/config
          readOnly: true
        ${STORAGE_MOUNT}
        - name: backups
          mountPath: /backups
      volumes:
      - name: config
        hostPath:
          path: ${CONFIG_PATH}
          type: Directory
      - name: backups
        hostPath:
          path: /var/backups
          type: DirectoryOrCreate
EOF

echo "Waiting for job ${JOB_NAME}..."
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=7200s
kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}"
echo "Archives on ${NODE}: /var/backups/homelab/frigate-${DATE}/"
