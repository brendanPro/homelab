# Velero Setup Guide

Quick setup guide for Velero backup and restore system.

## Prerequisites

Before installing Velero, ensure you have:

1. **Storage Backend** - One of the following:
   - MinIO running in your cluster (S3-compatible)
   - AWS S3 bucket
   - Google Cloud Storage
   - Azure Blob Storage

2. **Rook-Ceph** - For CSI snapshots (already installed in this cluster)

3. **Velero CLI** - Download from [GitHub releases](https://github.com/vmware-tanzu/velero/releases)

## Quick Installation

### Option 1: Automated Installation (Recommended)

```bash
cd homelab/apps/velero
./install.sh
```

### Option 2: Manual Installation

1. **Install CRDs:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v1/crds.yaml
   ```

2. **Deploy Velero:**
   ```bash
   kubectl apply -k homelab/apps/velero
   ```

3. **Verify Installation:**
   ```bash
   kubectl get pods -n velero
   kubectl get backupstoragelocations -n velero
   ```

## Configure Storage Backend

### Using MinIO (Default)

If you have MinIO running, update the endpoint in `base/backupstoragelocation.yaml`:

```yaml
spec:
  config:
    s3Url: http://minio.minio.svc.cluster.local:9000
```

Create MinIO credentials secret:

```bash
kubectl create secret generic cloud-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=YOUR_MINIO_ACCESS_KEY
aws_secret_access_key=YOUR_MINIO_SECRET_KEY"
```

Update `base/backupstoragelocation.yaml` to use the secret:

```yaml
spec:
  credential:
    name: cloud-credentials
    key: cloud
```

### Using AWS S3

1. Create AWS credentials file:
   ```bash
   cat > credentials-velero <<EOF
   [default]
   aws_access_key_id=YOUR_AWS_ACCESS_KEY_ID
   aws_secret_access_key=YOUR_AWS_SECRET_ACCESS_KEY
   EOF
   ```

2. Create secret:
   ```bash
   kubectl create secret generic cloud-credentials \
     --namespace velero \
     --from-file=cloud=./credentials-velero
   ```

3. Update `base/backupstoragelocation.yaml`:
   ```yaml
   spec:
     provider: aws
     objectStorage:
       bucket: your-bucket-name
       prefix: velero
     config:
       region: us-east-1
     credential:
       name: cloud-credentials
       key: cloud
   ```

## Deploy Backup Schedules

### Daily Backups
```bash
kubectl apply -f homelab/apps/velero/examples/daily-backup.yaml
```

### Weekly Full Backups
```bash
kubectl apply -f homelab/apps/velero/examples/weekly-full-backup.yaml
```

### Critical Apps Backup (every 6 hours)
```bash
kubectl apply -f homelab/apps/velero/examples/critical-apps-backup.yaml
```

## Install Velero CLI

### Linux ARM64 (Raspberry Pi)
```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-arm64.tar.gz
tar -xvf velero-v1.13.0-linux-arm64.tar.gz
sudo mv velero-v1.13.0-linux-arm64/velero /usr/local/bin/
velero version
```

### Linux AMD64
```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/
velero version
```

## Common Operations

### Create Manual Backup
```bash
# Backup entire cluster
velero backup create full-backup

# Backup specific namespace
velero backup create homeassistant-backup --include-namespaces homeassistant

# Backup with volumes
velero backup create media-backup \
  --include-namespaces media \
  --snapshot-volumes \
  --default-volumes-to-fs-backup
```

### List Backups
```bash
velero backup get
```

### Restore from Backup
```bash
# Restore entire backup
velero restore create --from-backup full-backup

# Restore specific namespace
velero restore create --from-backup full-backup \
  --include-namespaces homeassistant
```

### Monitor Status
```bash
# Check backup status
velero backup describe BACKUP_NAME

# Check restore status
velero restore describe RESTORE_NAME

# View logs
kubectl logs -n velero -l app.kubernetes.io/name=velero
```

## Verification Steps

After installation, verify:

1. **Velero pod is running:**
   ```bash
   kubectl get pods -n velero
   ```

2. **BackupStorageLocation is available:**
   ```bash
   kubectl get backupstoragelocations -n velero
   ```

3. **VolumeSnapshotClass exists:**
   ```bash
   kubectl get volumesnapshotclass
   ```

4. **Create test backup:**
   ```bash
   velero backup create test --include-namespaces default
   velero backup describe test
   ```

## Troubleshooting

### Pod not starting
```bash
kubectl describe pod -n velero -l app.kubernetes.io/name=velero
kubectl logs -n velero -l app.kubernetes.io/name=velero
```

### BackupStorageLocation unavailable
```bash
kubectl describe backupstoragelocation default -n velero
```

Check:
- Storage backend (MinIO/S3) is accessible
- Credentials are correct
- Bucket exists

### Backup fails
```bash
velero backup describe BACKUP_NAME --details
velero backup logs BACKUP_NAME
```

## References

- [Velero Documentation](https://velero.io/docs/)
- [Velero GitHub](https://github.com/vmware-tanzu/velero)
- [Backup Hooks](https://velero.io/docs/main/backup-hooks/)
- [CSI Snapshot Support](https://velero.io/docs/main/csi/)

