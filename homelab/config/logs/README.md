# Kubernetes Log Management Policy

This directory contains comprehensive log management and rotation policies for the Raspberry Pi Kubernetes cluster.

## Overview

The log management system consists of several components:

1. **LogRotate DaemonSet** - Runs on every node to rotate logs
2. **Log Cleanup CronJob** - Daily cleanup of old logs and artifacts
3. **Container Log Policy** - Configuration templates for applications
4. **Resource Quotas** - Limits for log management components
5. **Monitoring Rules** - Alerts for log-related issues

## Components

### 1. LogRotate DaemonSet (`logrotate-daemonset.yaml`)
- Runs on all nodes (including master)
- Rotates logs every hour
- Handles container logs, kubelet logs, audit logs
- Compresses old logs automatically
- Cleans systemd journal logs

### 2. Log Cleanup CronJob (`log-cleanup-cronjob.yaml`)
- Runs daily at 2 AM
- Removes logs older than retention periods
- Cleans temporary files and core dumps
- Reports disk usage after cleanup
- Identifies large files that need attention

### 3. Container Log Policy (`container-log-policy.yaml`)
- Kubelet configuration for container log limits
- Containerd log driver settings
- Application logging best practices
- Monitoring and alerting rules

## Log Retention Policies

| Log Type | Retention Period | Max Size | Compression |
|----------|------------------|----------|-------------|
| Container Logs | 3 days | 100MB per file | Yes |
| Kubelet Logs | 7 days | 50MB per file | Yes |
| Audit Logs | 14 days | 100MB per file | Yes |
| System Journal | 7 days | 500MB total | Built-in |
| Application Logs | 7 days | 25MB per file | Yes |

## Deployment

### Apply the log management policy:
```bash
kubectl apply -k homelab/config/logs/
```

### Verify deployment:
```bash
# Check DaemonSet
kubectl get ds -n kube-system logrotate

# Check CronJob
kubectl get cronjob -n kube-system log-cleanup

# Check recent log cleanup jobs
kubectl get jobs -n kube-system | grep log-cleanup
```

### Monitor log rotation:
```bash
# Check logrotate logs
kubectl logs -n kube-system -l app=logrotate

# Check cleanup job logs
kubectl logs -n kube-system job/log-cleanup-<timestamp>
```

## Configuration

### Customize Log Rotation
Edit `logrotate-configmap.yaml` to modify:
- Rotation frequency (daily, weekly, monthly)
- Retention periods (rotate count)
- File size limits (maxsize)
- Compression settings

### Adjust Cleanup Schedule
Modify the CronJob schedule in `log-cleanup-cronjob.yaml`:
```yaml
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
```

### Application Integration
For your applications, follow the template in `container-log-policy.yaml`:
1. Log to stdout/stderr (not files)
2. Use structured logging (JSON format)
3. Set appropriate log levels
4. Configure resource limits

## Monitoring

The system includes Prometheus rules for monitoring:
- High log volume alerts
- Disk space warnings
- Log rotation failure alerts

### Manual Monitoring Commands
```bash
# Check disk usage on nodes
kubectl exec -n kube-system ds/logrotate -- df -h /host/var/log

# Check large log files
kubectl exec -n kube-system ds/logrotate -- find /host/var/log -size +100M -ls

# Manual log cleanup
kubectl create job --from=cronjob/log-cleanup manual-cleanup -n kube-system
```

## Troubleshooting

### LogRotate Issues
```bash
# Check logrotate status
kubectl exec -n kube-system ds/logrotate -- logrotate -d /etc/logrotate.conf

# Force rotation
kubectl exec -n kube-system ds/logrotate -- logrotate -f /etc/logrotate.conf
```

### Disk Space Issues
```bash
# Emergency cleanup
kubectl exec -n kube-system ds/logrotate -- find /host/var/log -name "*.log" -mtime +1 -delete

# Check journal usage
kubectl exec -n kube-system ds/logrotate -- chroot /host journalctl --disk-usage
```

### Performance Impact
The log management system is designed to be lightweight:
- LogRotate: 50m CPU, 64Mi RAM per node
- Cleanup Job: 25m CPU, 32Mi RAM (runs briefly)
- Total cluster overhead: ~150m CPU, ~200Mi RAM

## Best Practices

1. **Application Logging**:
   - Always log to stdout/stderr
   - Use structured logging (JSON)
   - Include correlation IDs
   - Set appropriate log levels

2. **Resource Management**:
   - Set container resource limits
   - Monitor log volume growth
   - Use log sampling for high-traffic apps

3. **Security**:
   - Don't log sensitive information
   - Rotate logs regularly
   - Secure log access with RBAC

4. **Performance**:
   - Avoid excessive logging in hot paths
   - Use async logging where possible
   - Monitor log processing impact

## Emergency Procedures

### Disk Full Emergency
```bash
# Immediate cleanup (run on affected node)
sudo journalctl --vacuum-time=1d
sudo find /var/log -name "*.log" -mtime +0 -delete
sudo find /var/log -name "*.gz" -delete

# Then restart log management
kubectl rollout restart ds/logrotate -n kube-system
```

### Log Rotation Stuck
```bash
# Kill stuck logrotate processes
kubectl exec -n kube-system ds/logrotate -- pkill -f logrotate

# Restart the DaemonSet
kubectl rollout restart ds/logrotate -n kube-system
```

This log management system will prevent the disk pressure issues you experienced and ensure your cluster maintains healthy log levels automatically.
