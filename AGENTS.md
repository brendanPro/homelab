# AGENTS.md

This document provides guidance for AI agents working with this Kubernetes homelab Infrastructure as Code (IaC) repository.

## Project Overview

This is a Kubernetes homelab infrastructure running on Raspberry Pi 5 cluster, managed using:
- **Kustomize** for application deployment
- **Rook-Ceph** for distributed storage
- **ArgoCD** for GitOps (infrastructure deployment)
- **Calico** for networking
- **Tailscale** for secure remote access

## Repository Structure

```
k8s/
├── homelab/                    # Main application definitions
│   ├── apps/                   # Application deployments
│   ├── config/                 # Cluster configuration
│   └── install.sh              # Cluster setup script
├── infra/                      # Infrastructure tooling
│   └── argoCD/                 # ArgoCD installation
└── README.md                   # Project documentation
```

## Architecture Patterns

### 1. Application Structure
Each application follows a consistent Kustomize-based structure:

```
app-name/
├── base/                       # Base manifests
│   ├── kustomization.yaml      # Kustomize config with namespace, labels
│   ├── ns.yaml                 # Namespace definition
│   ├── deploy.yaml             # Deployment/StatefulSet
│   ├── svc.yaml                # Service
│   ├── pvc.yaml                # PersistentVolumeClaim (if needed)
│   ├── storageclass.yaml       # StorageClass (if custom)
│   ├── ing.yaml                # Ingress (if exposed)
│   └── resources/              # Additional resources (RBAC, configs)
├── kustomization.yaml          # Root kustomize referencing base + overlays
├── blockpool.yaml              # Ceph block pool (for persistent storage)
└── assets/                     # Configuration files (mounted via ConfigMaps)
```

### 2. Storage Architecture
- **Rook-Ceph** provides distributed storage across the cluster
- Each app requiring persistent storage has:
  - A dedicated `blockpool.yaml` (Ceph RBD block pool)
  - A `storageclass.yaml` referencing the block pool
  - One or more `pvc.yaml` using the storage class
- Media apps use shared filesystem storage (`mediafs.yaml`, `downloadfs.yaml`)

### 3. Networking
- **Calico** CNI for pod networking
- **Tailscale** for secure remote access
- **Ingress** resources for HTTP/HTTPS access (likely using nginx-ingress or similar)

## Key Applications

### Infrastructure
- **storage/rook**: Rook-Ceph operator for distributed storage
- **storage/ceph**: Ceph cluster configuration
- **nginx-ts**: Nginx with Tailscale integration
- **homepage**: Kubernetes dashboard/homepage

### Home Automation
- **homeassistant**: Home automation platform
- **mosquitto**: MQTT broker
- **zigbee2mqtt**: Zigbee to MQTT bridge
- **adguard**: DNS ad-blocking (planned)

### Media Stack
- **jellyfin**: Media server
- **jellyseerr**: Request management for media
- **sonarr**: TV show management
- **radarr**: Movie management
- **prowlarr**: Indexer management
- **qbittorrent**: Torrent client

### Development & Security
- **gitea**: Self-hosted Git service (with PostgreSQL + Memcached)
- **vaultwarden**: Password manager (planned)

### Gaming
- **minecraft**: Minecraft server
- **factorio**: Factorio server (with blueprint storage)

### Monitoring
- **frigate**: NVR/security camera management

## Common Tasks for AI Agents

### Adding a New Application

1. **Create directory structure**:
   ```bash
   mkdir -p homelab/apps/<app-name>/base
   ```

2. **Create base manifests**:
   - `ns.yaml`: Namespace with labels
   - `deploy.yaml`: Deployment/StatefulSet
   - `svc.yaml`: Service definition
   - `kustomization.yaml`: List all resources, set namespace, add labels

3. **Add storage (if needed)**:
   - Create `blockpool.yaml` at app root
   - Create `storageclass.yaml` in base/
   - Create `pvc.yaml` in base/

4. **Create root kustomization**:
   ```yaml
   resources:
   - ./base
   - blockpool.yaml  # if storage needed
   ```

5. **Add ingress (if web-accessible)**:
   - Create `ing.yaml` in base/
   - Add to base/kustomization.yaml resources

### Modifying Existing Applications

1. **Always check the structure first**: Examine the app's kustomization.yaml files
2. **Understand the overlay pattern**: Root kustomization includes base + additional resources
3. **Check for assets**: Config files are often in `assets/` or `resources/` directories
4. **Review storage dependencies**: Look for blockpool, storageclass, and pvc definitions

### Working with Kustomize

**Base kustomization.yaml pattern**:
```yaml
namespace: <app-namespace>
commonLabels:
  app.kubernetes.io/name: <app-name>
commonAnnotations:
  app.kubernetes.io/name: <app-name>

resources:
- ./ns.yaml
- ./deploy.yaml
- ./svc.yaml
- ./pvc.yaml          # if needed
- ./storageclass.yaml # if needed
- ./ing.yaml          # if needed
```

**Root kustomization.yaml pattern**:
```yaml
resources:
- ./base
- blockpool.yaml      # Ceph storage
- <custom-resources>  # Additional overlays
```

### Storage Configuration

**Blockpool pattern** (app-level):
```yaml
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: <app>-blockpool
  namespace: rook-ceph
spec:
  replicated:
    size: 2  # or 3 for higher availability
```

**StorageClass pattern**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: <app>-rbd
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: <app>-blockpool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Retain
```

## Cluster Information

### Hardware
- **Platform**: Raspberry Pi 5 cluster
- **Master**: rpimaster (192.168.8.144)
- **Node 1**: rpinode1 (192.168.1.143)
- **Node 2**: rpinode2 (192.168.1.142)

### Kubernetes Version
- v1.30 (as per install.sh)

### Container Runtime
- containerd with systemd cgroup driver

### Storage
- Rook-Ceph distributed storage
- LVM2 for local storage management

## Development Workflow

1. **Make changes** to YAML manifests
2. **Validate** with kustomize:
   ```bash
   kubectl kustomize homelab/apps/<app-name>
   ```
3. **Apply** changes:
   ```bash
   kubectl apply -k homelab/apps/<app-name>
   ```
4. **Commit** to git (ArgoCD will sync automatically if configured)

## Best Practices for AI Agents

### Repository-Specific Practices

#### DO:
- ✅ Follow the established directory structure pattern
- ✅ Use Kustomize for all deployments
- ✅ Create dedicated namespaces for each application
- ✅ Use consistent labeling (app.kubernetes.io/name)
- ✅ Define storage requirements with blockpools and storageclasses
- ✅ Check existing similar apps for reference implementations
- ✅ Preserve YAML formatting and indentation
- ✅ Use Rook-Ceph for persistent storage needs
- ✅ Add ingress resources for web-accessible services

#### DON'T:
- ❌ Hardcode IP addresses (use service discovery)
- ❌ Mix different organizational patterns
- ❌ Skip namespace creation
- ❌ Ignore storage provisioning for stateful apps
- ❌ Create resources directly without Kustomize
- ❌ Modify the cluster installation scripts without understanding dependencies
- ❌ Use hostPath volumes (use Ceph PVCs instead)

### Kubernetes Best Practices

Based on official Kubernetes documentation and production best practices:

#### 1. Resource Management
- **Set Resource Limits and Requests**: Always define CPU and memory limits/requests for containers
  ```yaml
  resources:
    requests:
      memory: "64Mi"
      cpu: "250m"
    limits:
      memory: "128Mi"
      cpu: "500m"
  ```
- **Use ResourceQuotas**: Limit resource consumption per namespace to prevent resource exhaustion
- **Configure LimitRanges**: Set default limits for containers that don't specify them

#### 2. Pod Configuration
- **Use Liveness and Readiness Probes**: Ensure Kubernetes can detect and restart unhealthy containers
  ```yaml
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
  ```
- **Set Security Contexts**: Run containers with minimal privileges
  ```yaml
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
  ```
- **Use Init Containers**: For setup tasks that need to complete before main containers start

#### 3. Secrets and Configuration Management
- **Never Hardcode Secrets**: Use Kubernetes Secrets for sensitive data
- **Use ConfigMaps for Configuration**: Separate config from container images
- **Mount Secrets as Volumes**: Instead of environment variables when possible for better security
- **Implement Secret Encryption at Rest**: Enable encryption for etcd

#### 4. High Availability & Reliability
- **Set Pod Disruption Budgets (PDBs)**: Ensure minimum number of pods remain available during disruptions
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata:
    name: app-pdb
  spec:
    minAvailable: 1
    selector:
      matchLabels:
        app: myapp
  ```
- **Use Multiple Replicas**: For critical applications, run at least 2-3 replicas
- **Configure Anti-Affinity**: Spread pods across different nodes for resilience
  ```yaml
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: myapp
          topologyKey: kubernetes.io/hostname
  ```

#### 5. Networking
- **Use NetworkPolicies**: Control traffic flow between pods
- **Implement Ingress Controllers Properly**: Use TLS termination and proper routing
- **Use Services for Service Discovery**: Instead of pod IPs
- **Configure DNS Properly**: Ensure CoreDNS is properly scaled and configured

#### 6. Storage Best Practices
- **Use StorageClasses**: Define storage types for different workload needs
- **Set Appropriate Reclaim Policies**: Use `Retain` for important data, `Delete` for ephemeral
- **Plan for Volume Expansion**: Use `allowVolumeExpansion: true` in StorageClasses
- **Backup PVCs Regularly**: Implement backup strategy for persistent volumes

#### 7. Monitoring & Logging
- **Deploy Metrics Server**: For resource metrics and HPA (Horizontal Pod Autoscaler)
- **Implement Centralized Logging**: Aggregate logs from all containers
- **Set Up Alerting**: Monitor cluster health and application metrics
- **Use Proper Log Levels**: Configure appropriate verbosity for debugging vs production

#### 8. Updates & Rollouts
- **Use Rolling Updates**: Default deployment strategy for zero-downtime updates
  ```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  ```
- **Test in Staging First**: Validate changes before production deployment
- **Use Version Tags**: Never use `latest` tag for production images
- **Implement Rollback Plans**: Know how to quickly revert problematic changes

#### 9. Security Hardening
- **Enable RBAC**: Use Role-Based Access Control for authorization
- **Use ServiceAccounts**: Assign specific ServiceAccounts to pods instead of default
- **Scan Images for Vulnerabilities**: Regularly check container images for CVEs
- **Implement Pod Security Standards**: Use Pod Security Admission to enforce security policies
- **Limit Cluster Access**: Use network policies and firewall rules

#### 10. Performance Optimization
- **Use HPA (Horizontal Pod Autoscaler)**: Auto-scale based on metrics
  ```yaml
  apiVersion: autoscaling/v2
  kind: HorizontalPodAutoscaler
  metadata:
    name: app-hpa
  spec:
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: app
    minReplicas: 2
    maxReplicas: 10
    metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  ```
- **Configure Resource Quotas per Namespace**: Prevent resource hogging
- **Use Local Storage When Possible**: For better I/O performance on temporary data
- **Optimize Image Sizes**: Use minimal base images (alpine, distroless)

#### 11. Labels and Annotations
- **Use Recommended Labels**: Follow Kubernetes label conventions
  ```yaml
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: myapp-prod
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: myapp-system
    app.kubernetes.io/managed-by: kustomize
  ```
- **Add Meaningful Annotations**: Document ownership, change reasons, etc.

#### 12. Declarative Configuration
- **Use Declarative YAML**: Prefer `kubectl apply` over imperative commands
- **Version Control Everything**: Keep all manifests in Git
- **Use GitOps**: Leverage ArgoCD for automated deployments from Git
- **Validate Manifests**: Use `kubectl diff` or `kubectl apply --dry-run=client` before applying

#### 13. Cluster Administration
- **Regular Updates**: Keep Kubernetes and components up to date
- **Monitor Cluster Resources**: Track node capacity and usage
- **Implement Backup Strategy**: Regular etcd backups and disaster recovery plans
- **Document Everything**: Maintain runbooks and operational procedures

#### 14. Development Workflow
- **Use Namespaces for Isolation**: Separate dev, staging, production
- **Implement CI/CD**: Automate testing and deployment
- **Use Helm or Kustomize**: For templating and overlay management
- **Test Locally**: Use minikube or kind for local development

## Troubleshooting Guide

### Storage Issues
- Check Rook-Ceph operator: `kubectl -n rook-ceph get pods`
- Verify blockpool exists: `kubectl -n rook-ceph get cephblockpool`
- Check PVC status: `kubectl get pvc -n <namespace>`

### Network Issues
- Verify Calico pods: `kubectl -n kube-system get pods | grep calico`
- Check service endpoints: `kubectl get endpoints -n <namespace>`
- Verify ingress: `kubectl get ingress -n <namespace>`

### Application Issues
- Check pod logs: `kubectl logs -n <namespace> <pod-name>`
- Describe pod: `kubectl describe pod -n <namespace> <pod-name>`
- Review events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`

## Special Considerations

### Helm-based Apps
Some apps (gitea, adguard) use Helm charts:
- Charts are stored in `charts/` directory
- Output manifests in `output.yaml`
- Still managed via Kustomize at the root level

### Config-heavy Apps
Apps with extensive configuration (frigate, homepage, factorio blueprints):
- Configs stored in `assets/` directory
- Mounted via ConfigMaps or Secrets
- Check the deployment for volumeMounts to understand config structure

### StatefulSet vs Deployment
- **StatefulSets**: gitea, databases (stable network identity, persistent storage)
- **Deployments**: Most other apps (stateless or with separate storage)

## GitOps with ArgoCD

- ArgoCD is installed in the `infra/argoCD/` directory
- Applications are likely configured as ArgoCD Applications
- Changes to git trigger automatic syncs
- Manual sync: Check ArgoCD UI or use ArgoCD CLI

## Quick Reference: File Locations

| Component | Location |
|-----------|----------|
| App definitions | `homelab/apps/<app-name>/` |
| Base manifests | `homelab/apps/<app-name>/base/` |
| Storage configs | `homelab/apps/storage/` |
| Network configs | `homelab/config/calico/`, `homelab/config/tailscale/` |
| Cluster setup | `homelab/install.sh` |
| ArgoCD | `infra/argoCD/` |
| App configs | `homelab/apps/<app-name>/assets/` or `base/assets/` |

---

**Last Updated**: 2025-10-15
**Kubernetes Version**: v1.30
**Platform**: Raspberry Pi 5 Cluster

