# Renovate — mises à jour des images et charts

[Renovate](https://docs.renovatebot.com/) ouvre des **PR automatiques** quand une nouvelle version d’image Docker ou de chart Helm est disponible.

Les tags sont **épinglés dans les `kustomization.yaml`** (`images:` / `helmCharts.version`). Renovate met à jour ces fichiers — pas de `latest` dans le repo.

---

## Activation (une fois)

1. Installer l’app GitHub **[Mend Renovate](https://github.com/apps/renovate)** sur le repo `brendanPro/homelab`
2. Au premier scan, Renovate ouvre une PR **« Configure Renovate »** — la merger (ou configurer via `renovate.json` déjà présent à la racine)
3. Les PR suivantes arrivent le **lundi avant 9h** (cf. `schedule` dans `renovate.json`)

Sans l’app GitHub installée, `renovate.json` seul ne fait rien.

---

## Versions épinglées (apps GitOps)

| App | Image | Tag | Fichier |
|-----|-------|-----|---------|
| homeassistant | `ghcr.io/home-assistant/home-assistant` | `2026.7.3` | `apps/smart-home/homeassistant/base/kustomization.yaml` |
| vaultwarden | `docker.io/vaultwarden/server` | `1.36.0` | `apps/infra/vaultwarden/base/kustomization.yaml` |
| mosquitto | `eclipse-mosquitto` | `2.1.2-alpine` | `apps/smart-home/mosquitto/base/kustomization.yaml` |
| frigate | `ghcr.io/blakeblackshear/frigate` | `0.14.1` | `apps/smart-home/frigate/base/kustomization.yaml` |
| zigbee2mqtt | `koenkk/zigbee2mqtt` | `2.8.0` | `apps/smart-home/zigbee2mqtt/base/kustomization.yaml` |
| homepage | `ghcr.io/gethomepage/homepage` | `v1.13.2` | `apps/smart-home/homepage/kustomization.yaml` |

### Platform (apply manuel)

| Composant | Tag | Fichier |
|-----------|-----|---------|
| metrics-server | `v0.7.1` | `platform/metrics-server/base/kustomization.yaml` |
| logs (alpine) | `3.18` | `platform/logs/base/kustomization.yaml` |
| tailscale operator | `1.96.5` | `platform/tailscale/base/kustomization.yaml` |
| calico | `v3.26.0` | `platform/calico/calico.yaml` — **ignoré par Renovate** |

---

## Politique de merge

| Label PR | Comportement |
|----------|--------------|
| `renovate` + `critical` | HA, vaultwarden, frigate, zigbee2mqtt, mosquitto — **review + test obligatoires** |
| `renovate` + `infra` | metrics-server, alpine, tailscale — review manuelle |
| `renovate` | homepage — review recommandée |

**Aucun automerge** — tu merges quand tu veux, ArgoCD sync ensuite.

---

## Workflow recommandé

1. Renovate ouvre une PR (ex. `Update ghcr.io/home-assistant/home-assistant to 2026.8.0`)
2. Lire le changelog upstream
3. Pour apps **critical** : tester en local ou accepter le risque + backup PVC si besoin
4. Merger → ArgoCD sync (apps GitOps)
5. Vérifier pods : `kubectl get pods -n smart-home` / `-n infra`

---

## Fichiers surveillés

- `renovate.json` — règles globales
- Managers **kustomize** (`images:`, `helmCharts.version`)
- Manager **kubernetes** (`image:` dans les deploy/statefulset)

Calico et Ceph restent exclus (`enabled: false`).

---

## Mettre à jour manuellement (sans attendre Renovate)

Éditer le `newTag` dans le `kustomization.yaml` concerné, puis :

```bash
kubectl kustomize apps/smart-home/homeassistant --enable-alpha-plugins  # si KSOPS
git commit && git push
```

ArgoCD appliquera au prochain sync.
