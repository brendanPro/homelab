#!/usr/bin/env bash
# Backup manuel du PVC vaultwarden-pvc (OpenEBS local sur rpinode2).
# Crée /var/backups/homelab/vaultwarden-YYYY-MM-DD/ sur le nœud.
#
# ⚠️ CRITIQUE — tous les mots de passe du coffre.
# Exécuter après scale down Vaultwarden pour un tar cohérent.
set -euo pipefail

DATE="${DATE:-$(date +%F)}"
JOB_NAME="vaultwarden-pvc-backup-${DATE}"
NAMESPACE="${NAMESPACE:-vaultwarden}"

DATA_PATH="${DATA_PATH:-/var/openebs/local/pvc-fc24a55b-5a3b-410e-a4b8-f5be7222f862}"
NODE="${NODE:-rpinode2}"

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
          DEST=/backups/homelab/vaultwarden-${DATE}
          mkdir -p "\$DEST"
          tar czf "\$DEST/vaultwarden-data.tgz" -C /source/data .
          ls -lh "\$DEST"
          tar tzf "\$DEST/vaultwarden-data.tgz" | head -20
          echo "Backup OK: \$DEST"
        volumeMounts:
        - name: data
          mountPath: /source/data
          readOnly: true
        - name: backups
          mountPath: /backups
      volumes:
      - name: data
        hostPath:
          path: ${DATA_PATH}
          type: Directory
      - name: backups
        hostPath:
          path: /var/backups
          type: DirectoryOrCreate
EOF

echo "Waiting for job ${JOB_NAME}..."
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=3600s
kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}"
echo "Archives on ${NODE}: /var/backups/homelab/vaultwarden-${DATE}/"
