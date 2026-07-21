#!/usr/bin/env bash
# Backup manuel des PVC Mosquitto (OpenEBS local sur rpinode2).
# Crée /var/backups/homelab/mosquitto-YYYY-MM-DD/ sur le nœud.
set -euo pipefail

DATE="${DATE:-$(date +%F)}"
JOB_NAME="mosquitto-pvc-backup-${DATE}"
NAMESPACE="${NAMESPACE:-mosquitto}"

DATA_PATH="${DATA_PATH:-/var/openebs/local/pvc-70636937-f37e-4d01-b8d4-3173e015f6ce}"
LOG_PATH="${LOG_PATH:-/var/openebs/local/pvc-a7ae9490-b146-4f64-9436-1146196dca64}"
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
          DEST=/backups/homelab/mosquitto-${DATE}
          mkdir -p "\$DEST"
          tar czf "\$DEST/mosquitto-data.tgz" -C /source/data .
          tar czf "\$DEST/mosquitto-log.tgz" -C /source/log .
          ls -lh "\$DEST"
          echo "Backup OK: \$DEST"
        volumeMounts:
        - name: data
          mountPath: /source/data
          readOnly: true
        - name: log
          mountPath: /source/log
          readOnly: true
        - name: backups
          mountPath: /backups
      volumes:
      - name: data
        hostPath:
          path: ${DATA_PATH}
          type: Directory
      - name: log
        hostPath:
          path: ${LOG_PATH}
          type: Directory
      - name: backups
        hostPath:
          path: /var/backups
          type: DirectoryOrCreate
EOF

echo "Waiting for job ${JOB_NAME}..."
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=300s
kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}"
echo "Archives on ${NODE}: /var/backups/homelab/mosquitto-${DATE}/"
