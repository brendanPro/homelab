# Cleanup repo — migration `homelab/` → structure cible

> **Statut : quasi terminé** — dossier legacy `homelab/` supprimé (2026-07-23).

## Objectif

Une seule arborescence claire :

```
homelab/
├── ansible/
├── apps/
│   ├── smart-home/     ← apps domotique (GitOps ArgoCD)
│   └── infra/          ← vaultwarden (plus tard)
├── platform/
│   ├── argocd/
│   ├── tailscale/
│   ├── openebs/
│   └── calico/
├── argocd-apps/        ← Applications ArgoCD (app-of-apps)
├── docs/
├── scripts/
└── secrets/
```

Supprimer le dossier legacy `homelab/` — **fait** (2026-07-23). Bootstrap K8s archivé dans `ansible/legacy/`.

---

## Déjà migré ✅

| Ancien chemin | Nouveau chemin | Legacy supprimé |
|---------------|----------------|-----------------|
| `homelab/apps/homepage` | `apps/smart-home/homepage` | ✅ |
| `homelab/apps/frigate` | `apps/smart-home/frigate` | ✅ |
| `homelab/apps/mosquitto` | `apps/smart-home/mosquitto` | ✅ |
| `homelab/apps/zigbee2mqtt` | `apps/smart-home/zigbee2mqtt` | ✅ |
| `homelab/apps/homeassistant` | `apps/smart-home/homeassistant` | ✅ |
| `homelab/infra/argoCD` | `platform/argocd` | ✅ |

---

## Encore dans `homelab/` — à traiter

### Apps hors scope — supprimées ✅ (2026-07-22)

| Dossier | Action |
|---------|--------|
| `homelab/apps/media/` | ✅ supprimé |
| `homelab/apps/factorio/` | ✅ supprimé |
| `homelab/apps/minecraft/` | ✅ supprimé |
| `homelab/apps/adguard/` | ✅ supprimé |
| `homelab/apps/nginx-ts/` | ✅ supprimé |
| `homelab/apps/storage/` (Ceph/Rook/sbx) | ✅ supprimé |
| `homelab/apps/gitea/` (charts vendorisés, non trackés) | ✅ supprimé |

> Vérifier avant suppression qu'aucune Application ArgoCD ne pointe encore vers ces paths.

### Platform — à migrer (pas supprimer)

| Ancien | Cible | Notes |
|--------|-------|-------|
| `homelab/config/tailscale/` | `platform/tailscale/` | ✅ |
| `homelab/apps/openebs/` | `platform/openebs/` | ✅ |
| Calico | `platform/calico/` | ✅ |
| Metrics-server | `platform/metrics-server/` | ✅ |
| Logs (logrotate) | `platform/logs/` | ✅ |

### Infra — on hold

| Dossier | Action |
|---------|--------|
| `apps/infra/vaultwarden/` | ✅ phase 2 GitOps (`infra`) |

### Autres fichiers `homelab/` — migrés ✅

| Ancien | Nouveau | Notes |
|--------|---------|-------|
| `homelab/install.sh` | `ansible/legacy/install-k8s-bootstrap.sh` | Legacy — voir `ansible/docs/K8S-PROVISIONING.md` |

---

## Procédure recommandée

Exécuter **après** phase 2 namespaces smart-home (surtout homeassistant).

### 1. Inventaire

```bash
# Apps ArgoCD actives
kubectl get applications -n platform

# Références git restantes vers homelab/
rg 'homelab/apps' --glob '*.{yaml,md,json}'
```

### 2. Supprimer hors scope

```bash
git rm -r homelab/apps/media homelab/apps/factorio ...
```

### 3. Migrer platform

```bash
git mv homelab/config/tailscale platform/tailscale
git mv homelab/apps/openebs platform/openebs
# Mettre à jour les Applications ArgoCD platform
```

### 4. Activer infra dans app-of-apps

Quand vaultwarden sera prêt :

```yaml
# argocd-apps/kustomization.yaml
resources:
  - smart-home/
  - infra/    # décommenter
```

### 5. Supprimer `homelab/` vide

Quand plus aucune référence :

```bash
git rm -r homelab/
```

### 6. Mettre à jour docs

- `AGENTS.md` — structure finale
- `secrets/README.md` — chemins SOPS
- `renovate.json` — fileMatch vers `apps/` uniquement

---

## Risques

| Risque | Mitigation |
|--------|------------|
| Supprimer un manifest encore utilisé | `rg homelab/` avant chaque `git rm` |
| ArgoCD sync sur ancien path | Vérifier Applications Synced avant suppression |
| Secrets SOPS chemins obsolètes | Mettre à jour `secrets/README.md` en même commit |

---

## Critère de done

- [x] Apps hors scope supprimées (media, factorio, minecraft, adguard, nginx-ts, storage, gitea)
- [x] Platform manifests sous `platform/` (tailscale, openebs, calico, argocd, metrics-server, logs)
- [x] Dossier legacy `homelab/` supprimé — bootstrap dans `ansible/legacy/`
- [ ] `rg homelab/` ne retourne rien hors docs historiques / backups paths
- [x] ROADMAP étape 4 cochée
