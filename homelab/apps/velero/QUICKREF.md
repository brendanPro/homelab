# Velero Quick Reference

Essential Velero commands for daily operations.

## Backup Operations

```bash
# Create backup
velero backup create NAME [flags]

# Backup entire cluster
velero backup create full-cluster

# Backup specific namespace
velero backup create NAME --include-namespaces NAMESPACE

# Backup multiple namespaces
velero backup create NAME --include-namespaces ns1,ns2,ns3

# Backup with labels
velero backup create NAME --selector "app=myapp"

# Backup excluding namespaces
velero backup create NAME --exclude-namespaces kube-system,velero

# Backup with volume snapshots
velero backup create NAME --snapshot-volumes

# Backup with file-system backup
velero backup create NAME --default-volumes-to-fs-backup

# List backups
velero backup get

# Describe backup
velero backup describe NAME [--details]

# Download backup logs
velero backup logs NAME

# Delete backup
velero backup delete NAME
```

## Restore Operations

```bash
# Restore from backup
velero restore create --from-backup BACKUP_NAME

# Restore to different namespace
velero restore create --from-backup BACKUP_NAME \
  --namespace-mappings old-ns:new-ns

# Restore specific resources
velero restore create --from-backup BACKUP_NAME \
  --include-resources deployments,services

# Restore excluding resources
velero restore create --from-backup BACKUP_NAME \
  --exclude-resources secrets,configmaps

# List restores
velero restore get

# Describe restore
velero restore describe NAME [--details]

# Download restore logs
velero restore logs NAME

# Delete restore
velero restore delete NAME
```

## Schedule Operations

```bash
# Create schedule
velero schedule create NAME --schedule="CRON_EXPRESSION" [flags]

# Daily at 2 AM
velero schedule create daily --schedule="0 2 * * *"

# Every 6 hours
velero schedule create frequent --schedule="0 */6 * * *"

# Weekly on Sunday at 3 AM
velero schedule create weekly --schedule="0 3 * * 0"

# List schedules
velero schedule get

# Describe schedule
velero schedule describe NAME

# Pause schedule
velero schedule pause NAME

# Unpause schedule
velero schedule unpause NAME

# Delete schedule
velero schedule delete NAME
```

## Backup Storage Locations

```bash
# List backup storage locations
velero backup-location get

# Describe backup storage location
velero backup-location describe NAME

# Set default backup storage location
velero backup-location set NAME --default
```

## Volume Snapshot Locations

```bash
# List volume snapshot locations
velero snapshot-location get

# Describe volume snapshot location
velero snapshot-location describe NAME
```

## Common Flags

### Backup Flags
```
--include-namespaces          Namespaces to include
--exclude-namespaces          Namespaces to exclude
--include-resources           Resources to include (e.g., pods,services)
--exclude-resources           Resources to exclude
--include-cluster-resources   Include cluster-scoped resources
--labels                      Labels to apply to backup
--selector                    Label selector to filter resources
--snapshot-volumes            Create volume snapshots (CSI)
--default-volumes-to-fs-backup Use file-system backup for volumes
--ttl                         Backup retention time (e.g., 24h, 30d)
--wait                        Wait for backup to complete
--storage-location            Backup storage location to use
--volume-snapshot-locations   Volume snapshot locations to use
```

### Restore Flags
```
--include-namespaces          Namespaces to restore
--exclude-namespaces          Namespaces to exclude
--include-resources           Resources to restore
--exclude-resources           Resources to exclude
--namespace-mappings          Map old namespaces to new (old:new)
--label-selector              Label selector to filter resources
--restore-volumes             Restore volumes (default: true)
--preserve-nodeports          Preserve NodePort values
--wait                        Wait for restore to complete
```

### Schedule Flags
```
--schedule                    Cron expression for schedule
--include-namespaces          Namespaces to backup
--exclude-namespaces          Namespaces to exclude
--ttl                         Backup retention time
--snapshot-volumes            Create volume snapshots
--default-volumes-to-fs-backup Use file-system backup
```

## Cron Schedule Examples

```
0 2 * * *       Daily at 2:00 AM
0 */6 * * *     Every 6 hours
0 0 * * 0       Weekly on Sunday at midnight
0 3 1 * *       Monthly on the 1st at 3:00 AM
*/30 * * * *    Every 30 minutes
0 0,12 * * *    Twice daily at midnight and noon
```

## Useful One-Liners

```bash
# Backup all namespaces except system ones
velero backup create all-apps \
  --include-namespaces '*' \
  --exclude-namespaces kube-system,kube-public,kube-node-lease,velero \
  --snapshot-volumes \
  --ttl 720h

# Backup critical apps with volumes
velero backup create critical \
  --include-namespaces homeassistant,vaultwarden,gitea \
  --default-volumes-to-fs-backup \
  --snapshot-volumes \
  --ttl 168h

# Disaster recovery backup
velero backup create dr-backup \
  --include-namespaces '*' \
  --include-cluster-resources=true \
  --snapshot-volumes \
  --default-volumes-to-fs-backup \
  --wait

# Restore only deployments and services
velero restore create --from-backup BACKUP_NAME \
  --include-resources deployments,services,configmaps \
  --exclude-resources secrets

# Clone namespace to new name
velero restore create clone-restore \
  --from-backup homeassistant-backup \
  --namespace-mappings homeassistant:homeassistant-clone
```

## Monitoring & Debugging

```bash
# Watch backup progress
watch velero backup get

# Get backup details with volumes
velero backup describe BACKUP_NAME --details

# Stream backup logs
velero backup logs BACKUP_NAME --follow

# Check Velero pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero

# Check backup storage location status
kubectl get backupstoragelocations -n velero

# Check volume snapshot class
kubectl get volumesnapshotclass

# View all Velero resources
kubectl get all -n velero
kubectl get backups -n velero
kubectl get restores -n velero
kubectl get schedules -n velero

# Debug backup failure
velero backup describe BACKUP_NAME --details
velero backup logs BACKUP_NAME | grep -i error
```

## Backup Strategies for This Homelab

```bash
# Daily application backups (30 days retention)
velero schedule create daily-apps \
  --schedule="0 2 * * *" \
  --include-namespaces '*' \
  --exclude-namespaces velero,kube-system,kube-public,kube-node-lease \
  --default-volumes-to-fs-backup \
  --ttl 720h

# Weekly full cluster backup (90 days retention)
velero schedule create weekly-full \
  --schedule="0 3 * * 0" \
  --include-namespaces '*' \
  --include-cluster-resources=true \
  --snapshot-volumes \
  --default-volumes-to-fs-backup \
  --ttl 2160h

# Frequent critical apps backup (7 days retention)
velero schedule create critical-apps \
  --schedule="0 */6 * * *" \
  --include-namespaces homeassistant,vaultwarden,gitea \
  --default-volumes-to-fs-backup \
  --snapshot-volumes \
  --ttl 168h
```

## Recovery Scenarios

### Restore entire cluster
```bash
# 1. Install Velero on new cluster
# 2. Configure same backup storage location
# 3. Restore
velero restore create cluster-restore --from-backup latest-full-backup
```

### Restore single application
```bash
velero restore create app-restore \
  --from-backup daily-backup-20250115 \
  --include-namespaces homeassistant
```

### Migrate to new cluster
```bash
# On source cluster: Create backup
velero backup create migration-backup --wait

# On destination cluster: Install Velero with same storage
# Then restore
velero restore create migration-restore --from-backup migration-backup
```

### Rollback after failed update
```bash
# 1. Delete broken deployment
kubectl delete namespace homeassistant

# 2. Restore from previous backup
velero restore create rollback --from-backup pre-update-backup \
  --include-namespaces homeassistant
```

## References

- Full README: [README.md](./README.md)
- Setup Guide: [SETUP.md](./SETUP.md)
- Velero Docs: https://velero.io/docs/

