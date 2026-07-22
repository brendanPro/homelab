# Runbook — Frigate phase 2 : migration namespace + alias legacy

> **⚠️ NE PAS `git push` sans avoir suivi cette procédure.**
> Un push déclenche ArgoCD qui tenterait de créer Frigate dans `smart-home`
> **sans** rebind PVC → nouveaux volumes vides → **perte config + enregistrements**.

## Objectif

- Frigate réel → namespace `smart-home`
- PVCs `frigate-config` + `frigate-storage` conservés (rebind PV)
- Pod sur **rpinode2**
- Alias DNS → namespace `frigate` stub (`ExternalName`) pour homepage widget `frigate.frigate:5000`
- MQTT / caméras RTSP inchangés (config sur PVC)

## Side effects (fenêtre ~5–10 min)

| Impact | Détail |
|--------|--------|
| Caméras / NVR | Pas de détection, pas d'enregistrement |
| Homepage widget Frigate | Indisponible brièvement |
| HA intégration Frigate | Entités caméra `unavailable` |
| **Non impacté** | Mosquitto, Zigbee, portes garage |

## Prérequis

- [ ] Phase 1 GitOps OK (`frigate` Application Synced)
- [ ] Fenêtre maintenance ~10 min
- [ ] Accès `kubectl` admin
- [ ] Pod Frigate sur **rpinode2** : `kubectl get pod -n frigate -o wide`
- [ ] Manifests phase 2 préparés en local (voir § Git), **pas pushés**

## État cluster actuel

| Ressource | PVC | PV | Reclaim | Nœud |
|-----------|-----|-----|---------|------|
| Config | `frigate-config` | `pvc-46a92f8d-414e-4b27-b9fd-5c27e63676cf` | Retain | rpinode2 |
| Storage | `frigate-storage` | `pvc-aeee2766-b65f-4b28-8f38-67d76356b696` | Retain | rpinode2 |

Hostpaths rpinode2 :
- `/var/openebs/local/pvc-46a92f8d-414e-4b27-b9fd-5c27e63676cf`
- `/var/openebs/local/pvc-aeee2766-b65f-4b28-8f38-67d76356b696`

## État cible (Git — à préparer, pas pushé)

| Ressource | Namespace |
|-----------|-----------|
| Deployment, PVCs, Service, Ingress, ConfigMap, StorageClass, Secret | `smart-home` |
| Namespace stub + Service ExternalName | `frigate` |

### Changements git

1. `apps/smart-home/frigate/base/kustomization.yaml` → `namespace: smart-home`, retirer `ns.yaml`
2. `apps/smart-home/frigate/base/pvc.yaml` → `volumeName` explicite sur les 2 PVCs
3. `apps/smart-home/frigate/kustomization.yaml` → `./legacy-alias/alias.yaml`
4. `legacy-alias/alias.yaml` → ExternalName `frigate.smart-home.svc.cluster.local`
5. `argocd-apps/smart-home/frigate.yaml` → `destination.namespace: smart-home`

## Procédure d'exécution

### 0. Suspendre ArgoCD (root + app)

```bash
kubectl patch application root -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

kubectl patch application frigate -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 1. Scale down Frigate

```bash
kubectl scale deployment frigate -n frigate --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=frigate -n frigate --timeout=180s
```

### 2. Backup PVC config (obligatoire)

```bash
./scripts/frigate-backup-pvc.sh
```

Archives : `/var/backups/homelab/frigate-YYYY-MM-DD/frigate-config.tgz`

> Storage 700Gi : PV **Retain** + rebind = données conservées sans tar.
> Backup storage optionnel (très long) : `BACKUP_STORAGE=1 ./scripts/frigate-backup-pvc.sh`

**Plan B — restore config** :

```bash
sudo tar xzf /var/backups/homelab/frigate-YYYY-MM-DD/frigate-config.tgz \
  -C /var/openebs/local/pvc-<NOUVEAU-ID>/
```

### 3. Rebind PVC `frigate-config`

```bash
PV_CONFIG=$(kubectl get pvc frigate-config -n frigate -o jsonpath='{.spec.volumeName}')
echo "PV_CONFIG=$PV_CONFIG"

kubectl delete pvc frigate-config -n frigate --wait=true
kubectl patch pv "$PV_CONFIG" -p '{"spec":{"claimRef": null}}'
kubectl get pv "$PV_CONFIG" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
```

### 4. Rebind PVC `frigate-storage`

```bash
PV_STORAGE=$(kubectl get pvc frigate-storage -n frigate -o jsonpath='{.spec.volumeName}')
echo "PV_STORAGE=$PV_STORAGE"

kubectl delete pvc frigate-storage -n frigate --wait=true
kubectl patch pv "$PV_STORAGE" -p '{"spec":{"claimRef": null}}'
kubectl get pv "$PV_STORAGE" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
```

### 5. Supprimer ressources legacy

```bash
kubectl delete deployment frigate -n frigate --ignore-not-found
kubectl delete service frigate -n frigate --ignore-not-found
kubectl delete ingress frigate -n frigate --ignore-not-found
```

### 6. Push Git + sync ArgoCD

```bash
git push origin main
```

```bash
kubectl patch application root -n platform --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

kubectl patch application frigate -n platform --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

kubectl patch application frigate -n platform --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main","prune":true}}}'
```

### 7. Vérifications

```bash
kubectl get pods,svc,pvc -n smart-home -l app.kubernetes.io/name=frigate -o wide

kubectl get pvc frigate-config frigate-storage -n smart-home \
  -o custom-columns=NAME:.metadata.name,PV:.spec.volumeName,STATUS:.status.phase

kubectl get svc -n frigate

kubectl logs -n smart-home deploy/frigate --tail=30
```

**Manuel :**
- [ ] UI `https://frigate.wombat-wahoo.ts.net`
- [ ] Caméras détectées, live view OK
- [ ] Homepage widget Frigate (`frigate.frigate:5000`)
- [ ] Enregistrements / snapshots accessibles

### 8. Réactiver selfHeal

```bash
kubectl patch application frigate -n platform --type merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": { "selfHeal": true },
      "syncOptions": ["CreateNamespace=true"]
    }
  }
}'

kubectl patch application root -n platform --type merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": { "prune": true, "selfHeal": true }
    }
  }
}'
```

### 9. Nettoyage

```bash
kubectl delete job frigate-pvc-backup-YYYY-MM-DD -n frigate --ignore-not-found
```

## Rollback

1. Suspendre sync ArgoCD
2. Scale down Frigate `smart-home`
3. Supprimer PVCs `smart-home` si vides
4. Rebind PVs vers namespace `frigate`
5. Restore tar config si nécessaire
6. `git revert` + sync

## Références

- Plan : [`phase2-ns-migrations-plan.md`](phase2-ns-migrations-plan.md)
- Script : [`../../scripts/frigate-backup-pvc.sh`](../../scripts/frigate-backup-pvc.sh)
