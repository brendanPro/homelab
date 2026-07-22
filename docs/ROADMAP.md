# Homelab GitOps Roadmap

> Dernière mise à jour : 2026-07-22

## Vue d'ensemble

Passer d'un cluster géré manuellement (`kustomize apply`) à un workflow GitOps complet : **push git → ArgoCD sync → déploiement automatique**.

```
git push → ArgoCD sync → cluster
```

En parallèle (plus tard) : Ansible pour reprovisionner les RPI depuis zéro.

---

## État actuel du cluster

### Smart-home — GitOps phase 1 ✅

Toutes les apps smart-home sont gérées par ArgoCD (`argocd-apps/smart-home/`).

| App | Manifests | Namespace runtime | Phase 2 namespace |
|-----|-----------|-------------------|-------------------|
| homepage | `apps/smart-home/homepage` | `smart-home` | N/A (déjà cible) |
| mosquitto | `apps/smart-home/mosquitto` | `smart-home` | ✅ fait (+ alias legacy) |
| frigate | `apps/smart-home/frigate` | `smart-home` | ✅ fait (+ alias legacy) |
| zigbee2mqtt | `apps/smart-home/zigbee2mqtt` | `smart-home` | ✅ fait (+ alias legacy) |
| homeassistant | `apps/smart-home/homeassistant` | `homeassistant` | ⏳ à faire (en dernier) |

### Infra — en attente

| App | Statut |
|-----|--------|
| vaultwarden | Legacy `homelab/apps/vaultwarden` — **ne pas toucher pour le moment** |

### Platform

| Composant | Manifests | GitOps |
|-----------|-----------|--------|
| ArgoCD | `platform/argocd/` | ✅ root app-of-apps |
| Tailscale operator | `homelab/config/tailscale/` | ❌ à migrer |
| OpenEBS | `homelab/apps/openebs/` | ❌ à migrer |
| Calico | (install manuel / ansible) | ❌ à documenter |

---

## Architecture cible des namespaces

| Namespace | Services |
|-----------|----------|
| `smart-home` | homepage, mosquitto, zigbee2mqtt, frigate, homeassistant |
| `infra` | vaultwarden |
| `platform` | argocd, tailscale, openebs |

---

## Priorités — ordre de travail

### 🔜 Prochaine session : phase 2 namespaces

Plan détaillé : [`docs/runbooks/phase2-ns-migrations-plan.md`](runbooks/phase2-ns-migrations-plan.md)

Ordre restant :

1. **homeassistant** → `smart-home` (**backup PVC obligatoire**, en dernier)

Modèle : runbook mosquitto (`docs/runbooks/mosquitto-phase2-ns-migration.md`).

### 📋 Backlog documenté

| Sujet | Doc | Statut |
|-------|-----|--------|
| Cleanup repo legacy | [`docs/REPO-CLEANUP.md`](REPO-CLEANUP.md) | À planifier |
| Pin images (HA, vaultwarden) | ci-dessous § versions | En attente volontaire |
| Renovate Bot | ci-dessous § versions | **On hold** |
| Ansible provisioning | ci-dessous § Ansible | **On hold** |
| Vaultwarden GitOps | — | **On hold** |

---

## TODO détaillé

### Étape 0 — Docs

- [x] Créer `docs/ROADMAP.md`
- [x] Runbook mosquitto phase 2
- [x] Runbook zigbee2mqtt phase 2
- [x] Plan phase 2 namespaces smart-home
- [x] Doc cleanup repo (`docs/REPO-CLEANUP.md`)
- [ ] Réécrire `AGENTS.md` (architecture actuelle)

### Étape 1 — ArgoCD

- [x] `platform/argocd/` + root app-of-apps
- [x] Repo connecté (`homelab-repo` secret)
- [ ] Ingress Tailscale UI ArgoCD (vérifier si déjà OK en prod)

### Étape 2 — GitOps smart-home (phase 1)

- [x] homepage
- [x] frigate
- [x] mosquitto
- [x] zigbee2mqtt
- [x] homeassistant

### Étape 3 — GitOps smart-home (phase 2 — migration namespace)

- [x] mosquitto → `smart-home` + alias legacy `mosquitto.mosquitto`
- [x] zigbee2mqtt → `smart-home` + alias legacy `zigbee2mqtt.zigbee2mqtt`
- [x] frigate → `smart-home` + alias legacy `frigate.frigate`
- [ ] homeassistant → `smart-home` (**backup PVC avant**)

> **CRITIQUE** — backup obligatoire avant migration PVC :
> - `homeassistant/homeassistant-config` — toute la config domotique
> - `vaultwarden/vaultwarden-pvc` — tous les mots de passe (hors scope actuel)

### Étape 4 — Restructurer le repo

Voir [`docs/REPO-CLEANUP.md`](REPO-CLEANUP.md).

- [x] Arborescence `apps/smart-home/` opérationnelle
- [x] `platform/argocd/`
- [x] Supprimer `n8n`, `velero`
- [ ] Supprimer `homelab/apps/` legacy (media, factorio, adguard, storage, etc.)
- [ ] Migrer tailscale / openebs → `platform/`
- [ ] Activer `argocd-apps/infra/` (vaultwarden — quand décidé)

### Étape 5 — Versions d'images **(on hold)**

| Catégorie | Apps | Stratégie |
|-----------|------|-----------|
| Données critiques | vaultwarden, homeassistant | Tag précis, PR manuelle |
| Apps avec état | zigbee2mqtt, frigate, mosquitto | Tag précis |
| Stateless | homepage | `latest` OK |

- [ ] Pin `homeassistant` (volontairement reporté)
- [ ] Pin `vaultwarden`
- [ ] Renovate Bot sur GitHub

### Étape 6 — Ansible **(on hold)**

- [ ] Inventory + rôles + playbooks (reconstruction cluster from scratch)

---

## Historique

- [x] `zigbee2mqtt` image : `2.0.0` → `2.8.0`
- [x] Mosquitto phase 2 exécutée 2026-07-21
- [x] Zigbee2MQTT phase 2 exécutée 2026-07-22
- [x] Frigate phase 2 exécutée 2026-07-22
- [x] Phase 1 GitOps complète smart-home 2026-07-21
