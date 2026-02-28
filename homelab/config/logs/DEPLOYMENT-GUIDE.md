# Log Management Deployment Guide

## Quick Start

### 1. Deploy the Log Management System
```bash
# Navigate to the logs directory
cd homelab/config/logs/

# Deploy using the automated script
./deploy.sh

# OR deploy manually with kubectl
kubectl apply -k .
```

### 2. Verify Deployment
```bash
# Check DaemonSet status
kubectl get ds logrotate -n kube-system

# Check CronJob
kubectl get cronjob log-cleanup -n kube-system

# View logs
kubectl logs -n kube-system -l app=logrotate
```

### 3. Monitor System
```bash
# Check disk usage
kubectl exec -n kube-system ds/logrotate -- df -h /host/var/log

# Manual cleanup if needed
kubectl create job --from=cronjob/log-cleanup manual-cleanup -n kube-system
```

## What This System Does

### 🔄 **Automatic Log Rotation**
- **Frequency**: Every hour
- **Container Logs**: 3 days retention, 100MB max size
- **System Logs**: 7 days retention, 50MB max size
- **Compression**: Automatic for rotated logs

### 🧹 **Daily Cleanup**
- **Schedule**: 2 AM daily
- **Removes**: Logs older than retention periods
- **Cleans**: Temporary files, core dumps, old journals
- **Reports**: Disk usage and large files

### 📊 **Monitoring & Alerts**
- **Disk Usage**: Alerts when >85% full
- **Log Volume**: Monitors write rates
- **Job Status**: Tracks cleanup success/failure

### 🛡️ **Resource Protection**
- **CPU Limits**: 100m per container
- **Memory Limits**: 128Mi per container
- **Tolerations**: Runs even during node pressure

## Configuration Files

| File | Purpose |
|------|---------|
| `kustomization.yaml` | Main deployment configuration |
| `logrotate-daemonset.yaml` | Runs logrotate on every node |
| `log-cleanup-cronjob.yaml` | Daily cleanup automation |
| `logrotate-configmap.yaml` | Log rotation policies |
| `container-log-policy.yaml` | Application logging guidelines |
| `resource-quotas.yaml` | Resource limits and quotas |
| `monitoring-dashboard.yaml` | Grafana dashboard config |

## Customization

### Change Rotation Frequency
Edit `logrotate-configmap.yaml`:
```yaml
# Change from 'daily' to 'weekly' or 'monthly'
daily -> weekly
```

### Adjust Retention Periods
```yaml
# Keep logs for 14 days instead of 7
rotate 7 -> rotate 14
```

### Modify Cleanup Schedule
Edit `log-cleanup-cronjob.yaml`:
```yaml
# Run twice daily at 2 AM and 2 PM
schedule: "0 2,14 * * *"
```

### Add Application-Specific Rules
Add to `logrotate-configmap.yaml`:
```yaml
/var/log/myapp/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 myapp myapp
    maxsize 10M
}
```

## Troubleshooting

### LogRotate Not Working
```bash
# Check pod status
kubectl get pods -n kube-system -l app=logrotate

# Check logs for errors
kubectl logs -n kube-system -l app=logrotate

# Test configuration
kubectl exec -n kube-system ds/logrotate -- logrotate -d /etc/logrotate.conf
```

### Cleanup Job Failing
```bash
# Check recent job logs
kubectl logs -n kube-system job/$(kubectl get jobs -n kube-system | grep log-cleanup | tail -1 | awk '{print $1}')

# Run manual cleanup
kubectl create job --from=cronjob/log-cleanup debug-cleanup -n kube-system
```

### High Disk Usage
```bash
# Emergency cleanup
kubectl exec -n kube-system ds/logrotate -- find /host/var/log -name "*.log" -mtime +1 -delete

# Check large files
kubectl exec -n kube-system ds/logrotate -- find /host/var/log -size +100M -ls
```

## Performance Impact

The log management system is designed to be lightweight:

| Component | CPU | Memory | Frequency |
|-----------|-----|--------|-----------|
| LogRotate DaemonSet | 50m | 64Mi | Continuous |
| Cleanup CronJob | 25m | 32Mi | Daily (brief) |
| **Total per Node** | **75m** | **96Mi** | **Mixed** |

## Security Considerations

- **Privileged Access**: Required for host filesystem access
- **RBAC**: Uses system service accounts
- **Log Isolation**: Maintains proper file permissions
- **No Sensitive Data**: Doesn't read log contents, only manages files

This system will prevent the disk pressure issues you experienced and maintain healthy log levels automatically across your entire Raspberry Pi cluster!
