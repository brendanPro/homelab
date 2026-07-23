# Logs — rotation et cleanup automatique

Composants cluster dans `kube-system` (apply manuel, hors ArgoCD).

| Ressource | Rôle |
|-----------|------|
| DaemonSet `logrotate` | logrotate horaire + vacuum journal (7j / 500M) sur chaque nœud |
| CronJob `log-cleanup` | cleanup quotidien 2h — vieux logs pods/containers, `.gz`, core dumps |
| ConfigMap `logrotate-config` | politiques de rotation (`/var/log/pods`, kubelet, containers, etc.) |

## Déployer / mettre à jour

```bash
kubectl apply -k platform/logs
kubectl rollout status daemonset/logrotate -n kube-system
```

## Vérifier

```bash
kubectl get ds logrotate -n kube-system
kubectl logs -n kube-system -l app=logrotate --tail=20
kubectl get cronjob log-cleanup -n kube-system
```

## Ajuster la rétention

Éditer `base/logrotate-configmap.yaml` (rotate, maxsize, chemins) puis `kubectl apply -k platform/logs`.

## Notes

- Accès host via `hostPath` + `privileged` — requis pour rotation sur les nœuds RPI.
- L’ancien namespace `log-management`, quotas, dashboard Grafana et ConfigMap `container-log-policy` (doc kubelet/containerd non branchée) ont été retirés du repo.

### Cleanup cluster (legacy)

Si une ancienne apply a créé des quotas dans `kube-system` :

```bash
kubectl delete resourcequota log-management-quota -n kube-system --ignore-not-found
kubectl delete pdb log-management-pdb -n kube-system --ignore-not-found
kubectl delete limitrange log-management-limits -n kube-system --ignore-not-found
kubectl delete configmap container-log-policy -n kube-system --ignore-not-found
kubectl rollout restart daemonset/logrotate -n kube-system
```
