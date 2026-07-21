# Runbook — Mosquitto phase 2 : migration namespace + alias legacy

> **⚠️ NE PAS `git push` sans avoir suivi cette procédure.**
> Les manifests phase 2 sont prêts dans le repo ; un push déclenche ArgoCD
> qui tenterait de créer le broker dans `smart-home` **sans** rebind PVC
> → nouveaux volumes vides + broker double.

## Objectif

- Broker réel → namespace `smart-home`
- NodePort **31883** inchangé (portes garage)
- Alias DNS → namespace `mosquitto` stub (`ExternalName`)
- frigate / zigbee2mqtt / homeassistant **sans changement de config**

## Prérequis

- [ ] Phase 1 GitOps OK (`mosquitto` Application Synced)
- [ ] Fenêtre maintenance ~10 min (MQTT down)
- [ ] Accès `kubectl` admin
- [ ] Pod Mosquitto sur **rpinode2** (vérifier : `kubectl get pod -n mosquitto -o wide`)

## État cible (Git — déjà préparé, pas pushé)

| Ressource | Namespace |
|-----------|-----------|
| Deployment, PVCs, Service NodePort, ConfigMap | `smart-home` |
| Namespace stub + Service ExternalName | `mosquitto` |

## Procédure d'exécution

### 0. Backup PVC (obligatoire)

Backup manuel sur **rpinode2** (hostpath OpenEBS) :

```bash
./scripts/mosquitto-backup-pvc.sh
```

Archives créées sur le nœud : `/var/backups/homelab/mosquitto-YYYY-MM-DD/`

| Fichier | Contenu |
|---------|---------|
| `mosquitto-data.tgz` | Persistence MQTT (retained messages, etc.) |
| `mosquitto-log.tgz` | Logs |

**Backup déjà fait le 2026-07-21** : `/var/backups/homelab/mosquitto-2026-07-21/` (~149 KiB data).

> Idéalement scale down Mosquitto avant backup pour cohérence :
> `kubectl scale deployment mosquitto -n mosquitto --replicas=0`

**Plan B si rebind échoue** — restaurer dans un nouveau hostpath :

```bash
# Sur rpinode2, une fois le nouveau PV créé (chemin affiché par kubectl get pv)
sudo tar xzf /var/backups/homelab/mosquitto-2026-07-21/mosquitto-data.tgz \
  -C /var/openebs/local/pvc-<NOUVEAU-ID>/
```

### 1. Suspendre ArgoCD (éviter selfHeal pendant ops manuelles)

```bash
kubectl patch application mosquitto -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 2. Scale down broker actuel

```bash
kubectl scale deployment mosquitto -n mosquitto --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=mosquitto -n mosquitto --timeout=120s
```

### 3. Rebind PVC `mosquitto-data`

```bash
# Noter le PV
kubectl get pvc mosquitto-data -n mosquitto -o jsonpath='{.spec.volumeName}{"\n"}'

PV_DATA=$(kubectl get pvc mosquitto-data -n mosquitto -o jsonpath='{.spec.volumeName}')

# Supprimer le PVC (Retain → PV conservé)
kubectl delete pvc mosquitto-data -n mosquitto --wait=true

# Libérer le PV
kubectl patch pv "$PV_DATA" -p '{"spec":{"claimRef": null}}'
```

### 4. Rebind PVC `mosquitto-log`

```bash
PV_LOG=$(kubectl get pvc mosquitto-log -n mosquitto -o jsonpath='{.spec.volumeName}')

kubectl delete pvc mosquitto-log -n mosquitto --wait=true
kubectl patch pv "$PV_LOG" -p '{"spec":{"claimRef": null}}'
```

### 5. Supprimer les ressources legacy (broker, pas le namespace)

```bash
kubectl delete deployment mosquitto -n mosquitto --ignore-not-found
kubectl delete service mosquitto -n mosquitto --ignore-not-found
# Ne PAS supprimer le namespace mosquitto
```

> Le NodePort 31883 est libéré quand le Service est supprimé.

### 6. Push Git + sync ArgoCD

```bash
# Sur ta machine de dev, après merge des changements phase 2 :
git push origin main
```

```bash
kubectl patch application root -n platform --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# Sync manuel recommandé (UI ou CLI)
argocd app sync mosquitto
```

ArgoCD crée :
- Broker dans `smart-home` (PVCs rebind sur les PV existants)
- Service NodePort `31883`
- Alias `ExternalName` dans `mosquitto`

### 7. Vérifications

```bash
# Broker up
kubectl get pods,svc,pvc -n smart-home -l app.kubernetes.io/name=mosquitto
kubectl get pods,svc -n mosquitto

# NodePort inchangé
kubectl get svc mosquitto -n smart-home -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'
# → 31883

# Test alias depuis un pod frigate
kubectl exec -n frigate deploy/frigate -- sh -c 'nc -zv mosquitto.mosquitto 1883'

# Test alias FQDN depuis zigbee2mqtt
kubectl exec -n zigbee2mqtt deploy/zigbee2mqtt -- sh -c 'nc -zv mosquitto.mosquitto.svc.cluster.local 1883'

# Home Assistant : UI → Intégrations → MQTT → connecté
# Portes garage : tester ouverture/fermeture
```

### 8. Réactiver selfHeal ArgoCD

```bash
kubectl patch application mosquitto -n platform --type merge -p '{
  "spec": {
    "syncPolicy": {
      "automated": { "selfHeal": true },
      "syncOptions": ["CreateNamespace=true"]
    }
  }
}'
```

## Rollback (si échec)

1. Suspendre sync ArgoCD
2. Scale down broker `smart-home`
3. Supprimer PVCs `smart-home` (si créés vides)
4. Rebind PVs vers namespace `mosquitto` (patch claimRef + recréer PVCs)
5. `git revert` push phase 2 + redeploy manuel ou sync phase 1
6. Vérifier portes garage + clients MQTT

## Quand supprimer l'alias legacy

Quand **toutes** les apps utilisent `mosquitto.smart-home.svc.cluster.local` :

1. Supprimer `legacy-alias/alias.yaml` du kustomization
2. Supprimer namespace stub `mosquitto`
3. Push git

## Endpoints de référence

| Client | Endpoint | Phase hybride |
|--------|----------|---------------|
| Portes garage | `<IP-nœud>:31883` | Inchangé |
| frigate | `mosquitto.mosquitto` | Alias → smart-home |
| zigbee2mqtt | `mosquitto.mosquitto.svc.cluster.local` | Alias → smart-home |
| homeassistant | (config PVC) | Alias si hostname = mosquitto.mosquitto |
| Cible finale | `mosquitto.smart-home.svc.cluster.local:1883` | Après cleanup alias |
