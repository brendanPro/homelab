# Runbook — Home Assistant phase 2 : migration namespace + alias legacy

> **⚠️ CRITIQUE — NE PAS `git push` sans runbook complet.**
> PVC `homeassistant-config` = toute la domotique (automations, devices, historique).
> Un push prématuré sans rebind PV → volume vide → **catastrophe**.

## Objectif

- Home Assistant réel → namespace `smart-home`
- PVC `homeassistant-config` conservé (rebind PV)
- Pod sur **rpinode2**
- Alias legacy `homeassistant.homeassistant` (optionnel)
- Homepage widget : `namespace: smart-home` dans `services.yaml`

## Side effects (fenêtre ~10–15 min)

| Impact | Détail |
|--------|--------|
| **Toute la domotique** | Down — lumières, automations, MQTT triggers HA |
| Zigbee/Frigate via HA | Entités indisponibles côté HA |
| **Non impacté** | Mosquitto broker, portes garage (MQTT direct), z2m/frigate pods |

> Les devices Zigbee continuent via z2m/MQTT ; seul le **cerveau** HA est down.

## Prérequis

- [ ] Phase 1 GitOps OK (`homeassistant` Application Synced)
- [ ] Fenêtre maintenance ~15 min annoncée
- [ ] Accès `kubectl` admin
- [ ] Pod HA sur **rpinode2**
- [ ] Manifests phase 2 préparés, **pas pushés**

## État cluster actuel

| Ressource | Valeur |
|-----------|--------|
| PVC | `homeassistant-config` (5 Gi) |
| PV | `pvc-6fa70131-cce6-4de6-bf0a-00ba4eff1bc3` |
| Hostpath | `/var/openebs/local/pvc-6fa70131-cce6-4de6-bf0a-00ba4eff1bc3` |
| Reclaim policy | **Retain** |
| Image cluster | `latest` + `Always` |

## Procédure d'exécution

### 0. Suspendre ArgoCD (root + app)

```bash
kubectl patch application root -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

kubectl patch application homeassistant -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 1. Scale down HA

```bash
kubectl scale deployment homeassistant -n homeassistant --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=homeassistant -n homeassistant --timeout=180s
```

### 2. Backup PVC (obligatoire)

```bash
./scripts/homeassistant-backup-pvc.sh
```

Archive : `/var/backups/homelab/homeassistant-YYYY-MM-DD/homeassistant-config.tgz`

Vérifier présence de `configuration.yaml`, `.storage/`, `automations.yaml` (ou équivalent).

**Plan B — restore** :

```bash
sudo tar xzf /var/backups/homelab/homeassistant-YYYY-MM-DD/homeassistant-config.tgz \
  -C /var/openebs/local/pvc-<NOUVEAU-ID>/
```

### 3. Rebind PVC `homeassistant-config`

```bash
PV=$(kubectl get pvc homeassistant-config -n homeassistant -o jsonpath='{.spec.volumeName}')
echo "PV=$PV"

kubectl delete pvc homeassistant-config -n homeassistant --wait=true
kubectl patch pv "$PV" -p '{"spec":{"claimRef": null}}'
kubectl get pv "$PV" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase
```

### 4. Supprimer ressources legacy

```bash
kubectl delete deployment homeassistant -n homeassistant --ignore-not-found
kubectl delete service homeassistant -n homeassistant --ignore-not-found
kubectl delete ingress homeassistant -n homeassistant --ignore-not-found
```

### 5. Push Git + sync ArgoCD

```bash
git push origin main
```

```bash
kubectl patch application homeassistant -n platform --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main","prune":true}}}'
```

### 6. Vérifications

```bash
kubectl get pods,svc,pvc -n smart-home -l app.kubernetes.io/name=homeassistant -o wide
kubectl get pvc homeassistant-config -n smart-home -o jsonpath='{.spec.volumeName}{"\n"}'
# → pvc-6fa70131-cce6-4de6-bf0a-00ba4eff1bc3
```

**Manuel :**
- [ ] UI `https://homeassistant.wombat-wahoo.ts.net`
- [ ] Automations actives
- [ ] Intégrations MQTT, Frigate, Zigbee OK
- [ ] Homepage stats HA (`namespace: smart-home`)
- [ ] Portes garage (via MQTT/HA)

### 7. Réactiver selfHeal

```bash
kubectl patch application homeassistant -n platform --type merge -p '{
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

### 8. Nettoyage

```bash
kubectl delete job homeassistant-pvc-backup-YYYY-MM-DD -n homeassistant --ignore-not-found
```

Conserver l'archive sur rpinode2 au moins 1–2 semaines.

## Rollback

1. Suspendre sync ArgoCD
2. Scale down HA `smart-home`
3. Supprimer PVC `smart-home` si vide
4. Rebind PV → namespace `homeassistant`
5. Restore tar si nécessaire
6. `git revert` + sync

## Références

- Plan : [`phase2-ns-migrations-plan.md`](phase2-ns-migrations-plan.md)
- Script : [`../../scripts/homeassistant-backup-pvc.sh`](../../scripts/homeassistant-backup-pvc.sh)
