#!/usr/bin/env bash
# Backup manuel du PVC homeassistant-config (OpenEBS local sur rpinode2).
# Crée /var/backups/homelab/homeassistant-YYYY-MM-DD/ sur le nœud.
#
# ⚠️ CRITIQUE — toute la config domotique (automations, devices, historique).
# Exécuter après scale down HA pour un tar cohérent.
set -euo pipefail

DATE="${DATE:-$(date +%F)}"
JOB_NAME="homeassistant-pvc-backup-${DATE}"
NAMESPACE="${NAMESPACE:-homeassistant}"

CONFIG_PATH="${CONFIG_PATH:-/var/openebs/local/pvc-6fa70131-cce6-4de6-bf0a-00ba4eff1bc3}"
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
          DEST=/backups/homelab/homeassistant-${DATE}
          mkdir -p "\$DEST"
          tar czf "\$DEST/homeassistant-config.tgz" -C /source/config .
          ls -lh "\$DEST"
          tar tzf "\$DEST/homeassistant-config.tgz" | head -20
          echo "Backup OK: \$DEST"
        volumeMounts:
        - name: config
          mountPath: /source/config
          readOnly: true
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
kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=3600s
kubectl logs -n "${NAMESPACE}" "job/${JOB_NAME}"
echo "Archives on ${NODE}: /var/backups/homelab/homeassistant-${DATE}/"
