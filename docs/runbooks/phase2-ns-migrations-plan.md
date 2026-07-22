# Plan — Phase 2 : migrations namespace `smart-home`

> Modèle de référence : [`mosquitto-phase2-ns-migration.md`](mosquitto-phase2-ns-migration.md) (exécuté 2026-07-21 ✅)

## Objectif final

Toutes les apps domotique tournent dans le namespace `smart-home`, avec des alias DNS legacy si nécessaire pour éviter de reconfigurer les clients.

```
smart-home/          ← workloads réels
├── homepage
├── mosquitto        ✅
├── zigbee2mqtt      ✅
├── frigate          ✅
└── homeassistant    ⏳ (dernier)
```

---

## Ordre d'exécution

| # | App | Risque | Downtime | Backup PVC | Particularité |
|---|-----|--------|----------|------------|---------------|
| ✅ | mosquitto | Moyen | ~10 min MQTT | Oui | NodePort 31883, alias legacy |
| ✅ | zigbee2mqtt | Moyen | ~5 min Zigbee | Oui | `nodeSelector: z2m: usb` sur rpinode2 |
| ✅ | frigate | Moyen | ~5 min caméras | Config oui | PVC 700 Go rebind Retain, alias homepage |
| 1 | **homeassistant** | **Critique** | ~10 min domotique | **Obligatoire** | Toute la config + automations |

---

## Pattern commun (chaque app)

### Préparation (git, sans push)

1. Changer `namespace:` → `smart-home` dans `base/kustomization.yaml`
2. Mettre à jour `argocd-apps/smart-home/<app>.yaml` → `destination.namespace: smart-home`
3. Si clients référencent `<app>.<old-ns>` : ajouter `legacy-alias/` (ExternalName)
4. Ajouter `volumeName` explicite dans `pvc.yaml` (OpenEBS local, évite provisioning vide)
5. Écrire runbook + script backup (`scripts/<app>-backup-pvc.sh`)
6. Valider : `kubectl kustomize` + `kubectl diff`

### Exécution (cluster, fenêtre maintenance)

1. Suspendre ArgoCD **root** + app (`selfHeal` restaure sinon)
2. Scale down app
3. Backup PVC (`./scripts/<app>-backup-pvc.sh`)
4. Rebind PVC(s) : delete PVC → patch PV `claimRef: null`
5. Supprimer deployment/service legacy (libère ressources)
6. **Push git** → sync ArgoCD manuel + prune
7. Vérifications fonctionnelles
8. Réactiver selfHeal root + app

> ⚠️ **Ne pas push avant rebind PV** — sinon ArgoCD crée des PVC vides.

---

## zigbee2mqtt — exécuté 2026-07-22 ✅

Runbook : [`zigbee2mqtt-phase2-ns-migration.md`](zigbee2mqtt-phase2-ns-migration.md)

| Ressource | Valeur |
|-----------|--------|
| Namespace runtime | `smart-home` |
| Alias legacy | `zigbee2mqtt.zigbee2mqtt` → ExternalName |
| Backup | `/var/backups/homelab/zigbee2mqtt-2026-07-22/` |
| PV (Retain) | `pvc-38726ebb-20e4-4041-9bc3-8d3f2be1a307` |

### Vérifications post-migration

- [x] UI `zigbee2mqtt.wombat-wahoo.ts.net`
- [x] Logs z2m : publish MQTT OK
- [x] Pod schedulé sur rpinode2
- [ ] Devices Zigbee visibles dans HA (validation manuelle)

---

## frigate — détails

### État actuel

| Ressource | Valeur |
|-----------|--------|
| Namespace | `frigate` |
| PVCs | `frigate-config` (1 Gi), `frigate-storage` (700 Gi) |
| Secrets | KSOPS (`secret.sops.yaml`) |
| Ingress | `frigate.wombat-wahoo.ts.net` |

### Particularités

- Deux PVCs à rebind (config + enregistrements)
- Secrets SOPS : vérifier que ArgoCD KSOPS plugin fonctionne post-migration
- Caméras RTSP : pas de changement réseau attendu

### Alias legacy proposé

Namespace stub `frigate` si des clients hardcodent `frigate.frigate`.

---

## homeassistant — détails (EN DERNIER)

### État actuel

| Ressource | Valeur |
|-----------|--------|
| Namespace | `homeassistant` |
| PVC | `homeassistant-config` (5 Gi) — **⚠️ CRITIQUE** |
| PV | `pvc-6fa70131-cce6-4de6-bf0a-00ba4eff1bc3` |
| Image | `latest` (pin reporté volontairement) |
| Ingress | `homeassistant.wombat-wahoo.ts.net` (funnel activé) |

### Prérequis stricts

- [ ] Backup PVC vérifié et testé (restore dry-run)
- [ ] Export snapshot HA (optionnel, double sécurité)
- [ ] Fenêtre maintenance annoncée (domotique down)
- [ ] Toutes les autres apps smart-home déjà migrées

### Alias legacy proposé

Namespace stub `homeassistant` — integrations MQTT/Frigate/z2m utilisent déjà service discovery ou FQDN.

---

## Scripts backup à créer

| App | Script | Chemin backup nœud |
|-----|--------|-------------------|
| mosquitto | `scripts/mosquitto-backup-pvc.sh` | ✅ `/var/backups/homelab/mosquitto-YYYY-MM-DD/` |
| zigbee2mqtt | `scripts/zigbee2mqtt-backup-pvc.sh` | ✅ voir runbook phase 2 |
| frigate | `scripts/frigate-backup-pvc.sh` | ✅ config — `/var/backups/homelab/frigate-YYYY-MM-DD/` |
| homeassistant | `scripts/homeassistant-backup-pvc.sh` | À créer |

Modèle : Job Kubernetes `hostPath` sur le nœud OpenEBS local (comme mosquitto).

---

## Rollback général

1. Suspendre sync ArgoCD
2. Scale down app `smart-home`
3. Supprimer PVCs `smart-home` si vides
4. Rebind PVs vers ancien namespace
5. `git revert` + redeploy
6. Vérifier fonctionnel

---

## Prochaine action

**Home Assistant** — runbook à créer : `docs/runbooks/homeassistant-phase2-ns-migration.md` (**backup PVC obligatoire**).
