# Velero - Kubernetes Backup and Restore

Velero is an open-source tool to safely backup and restore, perform disaster recovery, and migrate Kubernetes cluster resources and persistent volumes.

## Features

- **Backup & Restore**: Back up your entire cluster or specific namespaces
- **Disaster Recovery**: Quickly recover from infrastructure loss or data corruption
- **Migration**: Move applications between clusters
- **Scheduled Backups**: Automated backups with retention policies
- **Volume Snapshots**: Support for CSI snapshots and file-system backups

## Installation

### 1. Install Velero CRDs

First, install the Custom Resource Definitions:

```bash
kubectl apply -f https://raw.githubusercontent.com/vmware-tanzu/velero/v1.13.0/config/crd/v1/crds.yaml
```

Or follow the instructions in `crds.yaml`

### 2. Configure Storage Backend

Velero needs a storage backend to store backups. The default configuration uses MinIO (S3-compatible storage).

**Option A: Using MinIO (included)**

The BackupStorageLocation is configured to use MinIO at `http://minio.minio.svc.cluster.local:9000`

**Option B: Using Cloud Storage (AWS S3, GCS, Azure)**

Update `base/backupstoragelocation.yaml` with your cloud provider settings and create a secret:

```bash
kubectl create secret generic cloud-credentials \
  --namespace velero \
  --from-file=cloud=./credentials-velero
```

### 3. Deploy Velero

```bash
kubectl apply -k homelab/apps/velero
```

### 4. Verify Installation

```bash
kubectl get pods -n velero
kubectl get backupstoragelocations -n velero
kubectl get volumesnapshotlocations -n velero
```

## Usage

### Install Velero CLI

Download the Velero CLI from [GitHub releases](https://github.com/vmware-tanzu/velero/releases):

```bash
# For Linux ARM64 (Raspberry Pi)
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-arm64.tar.gz
tar -xvf velero-v1.13.0-linux-arm64.tar.gz
sudo mv velero-v1.13.0-linux-arm64/velero /usr/local/bin/
```

### Create Backups

**Manual backup of entire cluster:**
```bash
velero backup create full-cluster-backup --wait
```

**Backup specific namespace:**
```bash
velero backup create homeassistant-backup --include-namespaces homeassistant --wait
```

**Backup with volume snapshots:**
```bash
velero backup create jellyfin-backup \
  --include-namespaces media \
  --snapshot-volumes \
  --default-volumes-to-fs-backup
```

### Schedule Automated Backups

**Deploy example schedules:**

```bash
# Daily backups at 2 AM
kubectl apply -f homelab/apps/velero/examples/daily-backup.yaml

# Weekly full backups on Sunday at 3 AM
kubectl apply -f homelab/apps/velero/examples/weekly-full-backup.yaml

# Critical apps every 6 hours
kubectl apply -f homelab/apps/velero/examples/critical-apps-backup.yaml
```

**Create custom schedule:**
```bash
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces '*' \
  --exclude-namespaces velero,kube-system \
  --ttl 720h
```

### Restore from Backup

**List available backups:**
```bash
velero backup get
```

**Restore from backup:**
```bash
velero restore create --from-backup daily-backup-20250115020000
```

**Restore specific namespace:**
```bash
velero restore create --from-backup full-cluster-backup \
  --include-namespaces homeassistant
```

**Restore to different namespace:**
```bash
velero restore create --from-backup homeassistant-backup \
  --namespace-mappings homeassistant:homeassistant-restore
```

### Monitor Backups and Restores

```bash
# Check backup status
velero backup describe BACKUP_NAME
velero backup logs BACKUP_NAME

# Check restore status
velero restore describe RESTORE_NAME
velero restore logs RESTORE_NAME

# View schedules
velero schedule get
```

## Volume Backup Methods

Velero supports two methods for backing up volumes:

### 1. CSI Snapshots (Recommended for Rook-Ceph)

Uses Kubernetes CSI to create storage-level snapshots. Requires:
- VolumeSnapshotClass configured for `rook-ceph.rbd.csi.ceph.com`
- `--snapshot-volumes` flag in backup

### 2. File-System Backup (Restic/Kopia)

Uses file-system level backup with restic. Useful for:
- PVCs that don't support CSI snapshots
- Cross-cluster restores
- Requires `--default-volumes-to-fs-backup` flag

## Configuration for Rook-Ceph

To use CSI snapshots with Rook-Ceph, create a VolumeSnapshotClass:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-rbdplugin-snapclass
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: rook-ceph.rbd.csi.ceph.com
deletionPolicy: Delete
parameters:
  clusterID: rook-ceph
  csi.storage.k8s.io/snapshotter-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/snapshotter-secret-namespace: rook-ceph
```

## Backup Best Practices

1. **Regular Schedules**: Set up automated daily and weekly backups
2. **Test Restores**: Regularly test restore procedures to ensure backups work
3. **Off-site Storage**: Use cloud storage or remote MinIO for disaster recovery
4. **Retention Policy**: Configure appropriate TTL to manage storage costs
5. **Critical Apps**: More frequent backups for critical applications
6. **Volume Backups**: Always include volumes for stateful applications
7. **Pre/Post Hooks**: Use backup hooks for database consistency

## Troubleshooting

### Check Velero logs
```bash
kubectl logs -n velero -l app.kubernetes.io/name=velero
```

### Backup fails
```bash
# Check backup details
velero backup describe BACKUP_NAME --details

# Check backup logs
velero backup logs BACKUP_NAME
```

### Storage location issues
```bash
# Check storage location status
kubectl get backupstoragelocations -n velero
kubectl describe backupstoragelocation default -n velero
```

### Volume snapshot issues
```bash
# Verify VolumeSnapshotClass exists
kubectl get volumesnapshotclass

# Check snapshot status
kubectl get volumesnapshot -A
```

## Resources

- [Velero Documentation](https://velero.io/docs/)
- [Velero GitHub](https://github.com/vmware-tanzu/velero)
- [Velero Plugins](https://velero.io/plugins/)
- [Backup Hooks Documentation](https://velero.io/docs/main/backup-hooks/)

## Integration with This Homelab

Velero is configured to:
- Backup all application namespaces
- Use Rook-Ceph CSI snapshots for volume backups
- Store backups in MinIO (or cloud storage if configured)
- Automatically backup critical applications more frequently
- Retain daily backups for 30 days, weekly backups for 90 days

