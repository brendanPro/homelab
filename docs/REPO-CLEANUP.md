# Cleanup repo — migration `homelab/` → structure cible

> **Statut : en cours** — phase 1 (suppression apps hors scope) exécutée 2026-07-22.

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

Supprimer le dossier legacy `homelab/` (sauf ce qui n'a pas encore été migré).

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
| `homelab/config/tailscale/` | `platform/tailscale/` | Operator Helm via kustomize |
| `homelab/apps/openebs/` | `platform/openebs/` | Storage cluster-wide |
| Calico | `platform/calico/` | Manifests ou doc Ansible-only |

### Infra — on hold

| Dossier | Action |
|---------|--------|
| `homelab/apps/vaultwarden/` | **Ne pas toucher** — migration GitOps + namespace reportée |

### Autres fichiers `homelab/`

| Fichier | Action |
|---------|--------|
| `homelab/install.sh` | Remplacer par Ansible (on hold) — supprimer quand playbooks prêts |
| `homelab/config/logs/` | Évaluer : migrer vers `platform/` ou supprimer si obsolète |

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
- [ ] Plus aucun fichier sous `homelab/apps/` (reste : **vaultwarden**, **openebs**)
- [ ] Platform entièrement sous `platform/`
- [ ] `rg homelab/apps` ne retourne rien (hors historique git)
- [ ] ROADMAP étape 4 cochée
