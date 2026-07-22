#!/usr/bin/env bash
# Backup manuel du PVC zigbee2mqtt-data (OpenEBS local sur rpinode2).
# Crée /var/backups/homelab/zigbee2mqtt-YYYY-MM-DD/ sur le nœud.
#
# Contenu critique : configuration.yaml, devices.yaml, groups.yaml, clé réseau Zigbee.
# Exécuter idéalement après scale down z2m (voir runbook phase 2).
set -euo pipefail

DATE="${DATE:-$(date +%F)}"
JOB_NAME="zigbee2mqtt-pvc-backup-${DATE}"
NAMESPACE="${NAMESPACE:-zigbee2mqtt}"

DATA_PATH="${DATA_PATH:-/var/openebs/local/pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307}"
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
          DEST=/backups/homelab/zigbee2mqtt-${DATE}
          mkdir -p "\$DEST"
          tar czf "\$DEST/zigbee2mqtt-data.tgz" -C /source/data .
          ls -lh "\$DEST"
          tar tzf "\$DEST/zigbee2mqtt-data.tgz" | head -20
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
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=300s
kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}"
echo "Archives on ${NODE}: /var/backups/homelab/zigbee2mqtt-${DATE}/"
