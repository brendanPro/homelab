# Runbook — Zigbee2MQTT phase 2 : migration namespace + alias legacy

> **⚠️ NE PAS `git push` sans avoir suivi cette procédure.**
> Un push déclenche ArgoCD qui tenterait de créer z2m dans `smart-home`
> **sans** rebind PVC → nouveau volume vide → **re-pairing de tous les devices Zigbee**.

## Objectif

- Zigbee2MQTT réel → namespace `smart-home`
- Données `/data` conservées (clé réseau, `devices.yaml`, `groups.yaml`)
- Pod sur **rpinode2** (dongle USB `z2m: usb`)
- Alias DNS optionnel → namespace `zigbee2mqtt` stub (`ExternalName`)
- MQTT inchangé : `mosquitto.mosquitto.svc.cluster.local` (alias mosquitto OK)

## Side effects (fenêtre ~5–10 min)

| Impact | Détail |
|--------|--------|
| Appareils Zigbee via HA | Entités `unavailable` |
| Automations HA (Zigbee) | Pause le temps du redémarrage |
| UI z2m | Ingress Tailscale indisponible |
| **Non impacté** | Mosquitto, portes garage, Frigate, HA core |

## Prérequis

- [ ] Phase 1 GitOps OK (`zigbee2mqtt` Application Synced)
- [ ] Fenêtre maintenance ~10 min
- [ ] Accès `kubectl` admin
- [ ] Pod z2m sur **rpinode2** : `kubectl get pod -n zigbee2mqtt -o wide`
- [ ] Manifests phase 2 préparés en local (voir § Git), **pas pushés**

## État cluster actuel

| Ressource | Valeur |
|-----------|--------|
| PVC | `zigbee2mqtt-data` |
| PV | `pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307` |
| Hostpath rpinode2 | `/var/openebs/local/pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307` |
| Reclaim policy PV | **`Delete`** ⚠️ (patch `Retain` obligatoire avant delete PVC) |
| nodeSelector | `z2m: usb` |

## État cible (Git — à préparer, pas pushé)

| Ressource | Namespace |
|-----------|-----------|
| Deployment, PVC, Service, Ingress, ConfigMap, StorageClass | `smart-home` |
| Namespace stub + Service ExternalName (optionnel) | `zigbee2mqtt` |

### Changements git à préparer

1. `apps/smart-home/zigbee2mqtt/base/kustomization.yaml` → `namespace: smart-home`
2. `apps/smart-home/zigbee2mqtt/base/resources/pvc.yaml` → ajouter :
   ```yaml
   volumeName: pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307
   ```
3. `apps/smart-home/zigbee2mqtt/kustomization.yaml` → ajouter `./legacy-alias/alias.yaml`
4. Créer `apps/smart-home/zigbee2mqtt/legacy-alias/alias.yaml` (ExternalName → `zigbee2mqtt.smart-home.svc.cluster.local`)
5. `argocd-apps/smart-home/zigbee2mqtt.yaml` → `destination.namespace: smart-home`

Valider :

```bash
kubectl kustomize apps/smart-home/zigbee2mqtt
```

## Procédure d'exécution

### 0. Suspendre ArgoCD (root + app)

> Le **root** app restaure le selfHeal de l'Application en quelques secondes si non suspendu.

```bash
kubectl patch application root -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

kubectl patch application zigbee2mqtt -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 1. Scale down z2m

```bash
kubectl scale deployment zigbee2mqtt -n zigbee2mqtt --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=zigbee2mqtt -n zigbee2mqtt --timeout=120s
```

### 2. Backup PVC (obligatoire)

```bash
./scripts/zigbee2mqtt-backup-pvc.sh
```

Archives sur **rpinode2** : `/var/backups/homelab/zigbee2mqtt-YYYY-MM-DD/`

| Fichier | Contenu |
|---------|---------|
| `zigbee2mqtt-data.tgz` | `configuration.yaml`, `devices.yaml`, clé réseau, state z2m |

Vérifier que l'archive contient `configuration.yaml` et `devices.yaml` (le script liste les 20 premiers fichiers).

**Plan B — restore** :

```bash
# Sur rpinode2, une fois le nouveau PV hostpath connu
sudo tar xzf /var/backups/homelab/zigbee2mqtt-YYYY-MM-DD/zigbee2mqtt-data.tgz \
  -C /var/openebs/local/pvc-<NOUVEAU-ID>/
```

### 3. Patch PV → Retain (CRITIQUE)

Le PV actuel a `persistentVolumeReclaimPolicy: Delete`. Sans ce patch, supprimer le PVC **efface les données**.

```bash
PV=$(kubectl get pvc zigbee2mqtt-data -n zigbee2mqtt -o jsonpath='{.spec.volumeName}')
echo "PV=$PV"

kubectl patch pv "$PV" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl get pv "$PV" -o jsonpath='reclaimPolicy={.spec.persistentVolumeReclaimPolicy}{"\n"}'
# → reclaimPolicy=Retain
```

### 4. Rebind PVC `zigbee2mqtt-data`

```bash
kubectl delete pvc zigbee2mqtt-data -n zigbee2mqtt --wait=true
kubectl patch pv "$PV" -p '{"spec":{"claimRef": null}}'
kubectl get pv "$PV" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef
# → STATUS Available
```

### 5. Supprimer les ressources legacy (pas le namespace)

```bash
kubectl delete deployment zigbee2mqtt -n zigbee2mqtt --ignore-not-found
kubectl delete service zigbee2mqtt -n zigbee2mqtt --ignore-not-found
# Garder Ingress si alias stub non encore déployé — ou supprimer et laisser ArgoCD recréer dans smart-home
kubectl delete ingress zigbee2mqtt -n zigbee2mqtt --ignore-not-found
```

### 6. Push Git + sync ArgoCD

```bash
git push origin main
```

```bash
kubectl patch application root -n platform --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

kubectl patch application zigbee2mqtt -n platform --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Sync manuel avec prune (UI ArgoCD ou patch operation)
kubectl patch application zigbee2mqtt -n platform --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main","prune":true}}}'
```

ArgoCD crée :
- z2m dans `smart-home` (PVC rebind sur PV existant)
- Ingress Tailscale `zigbee2mqtt.wombat-wahoo.ts.net`
- Alias `ExternalName` dans `zigbee2mqtt` (si manifests legacy-alias inclus)

### 7. Vérifications

```bash
# Pod sur rpinode2, Running
kubectl get pods,svc,pvc -n smart-home -l app.kubernetes.io/name=zigbee2mqtt -o wide

# PVC bound sur le bon PV
kubectl get pvc zigbee2mqtt-data -n smart-home -o jsonpath='{.spec.volumeName}{"\n"}'
# → pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307

# Logs : connexion MQTT OK
kubectl logs -n smart-home deploy/zigbee2mqtt --tail=30 | grep -iE 'mqtt|started|error'

# MQTT publish (depuis un pod test)
kubectl run mqtt-check --rm -i --restart=Never --image=busybox:1.36 -- \
  sh -c 'nc -zv mosquitto.mosquitto.svc.cluster.local 1883'
```

**Manuel :**
- [ ] UI `https://zigbee2mqtt.wombat-wahoo.ts.net` — frontend OK
- [ ] Home Assistant — entités Zigbee repassent `available`
- [ ] Tester une prise/lumière Zigbee
- [ ] Vérifier qu'aucun device ne demande re-pairing

### 8. Réactiver selfHeal ArgoCD

```bash
kubectl patch application zigbee2mqtt -n platform --type merge -p '{
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

### 9. Nettoyage (optionnel)

Supprimer le job backup une fois la migration validée :

```bash
kubectl delete job -n zigbee2mqtt -l job-name=zigbee2mqtt-pvc-backup-$(date +%F) 2>/dev/null || \
kubectl delete job zigbee2mqtt-pvc-backup-YYYY-MM-DD -n zigbee2mqtt --ignore-not-found
```

## Rollback (si échec)

1. Suspendre sync ArgoCD (root + zigbee2mqtt)
2. Scale down z2m `smart-home`
3. Supprimer PVC `smart-home/zigbee2mqtt-data` (si créé vide)
4. Rebind PV vers namespace `zigbee2mqtt` (patch claimRef + recréer PVC)
5. Restore tar si données perdues (Plan B §2)
6. `git revert` push phase 2 + sync
7. Vérifier devices Zigbee dans HA

## Quand supprimer l'alias legacy

Quand plus aucun client n'utilise `zigbee2mqtt.zigbee2mqtt` :

1. Supprimer `legacy-alias/alias.yaml` du kustomization
2. Supprimer namespace stub `zigbee2mqtt`
3. Push git

## Références

- Plan global : [`phase2-ns-migrations-plan.md`](phase2-ns-migrations-plan.md)
- Modèle : [`mosquitto-phase2-ns-migration.md`](mosquitto-phase2-ns-migration.md)
- Script backup : [`../../scripts/zigbee2mqtt-backup-pvc.sh`](../../scripts/zigbee2mqtt-backup-pvc.sh)
