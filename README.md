# Homelab

Infrastructure as Code pour mon homelab Kubernetes sur cluster Raspberry Pi 5, géré en GitOps via ArgoCD.

## Stack

| Composant | Rôle |
|-----------|------|
| Kubernetes v1.33 | Orchestration |
| ArgoCD | GitOps — push git = déploiement automatique |
| Tailscale | Accès distant sécurisé |
| OpenEBS | Stockage persistant (local PV) |
| Calico | Réseau (CNI) |
| Ansible | Provisioning des nœuds depuis zéro |

## Cluster

3 nœuds Raspberry Pi 5 :
- `rpimaster` — control-plane
- `rpinode1` — worker
- `rpinode2` — worker

## Apps en production

**`smart-home`** — homeassistant, mosquitto, zigbee2mqtt, frigate

**`infra`** — homepage, vaultwarden

## Structure du repo

```
homelab/
├── ansible/        ← provisioning des RPI
├── apps/           ← applications (smart-home, infra)
├── platform/       ← argocd, tailscale, openebs, calico
└── docs/
    └── ROADMAP.md  ← plan de migration en cours
```

## Documentation

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — roadmap et todos
- [`AGENTS.md`](AGENTS.md) — guide pour les agents IA
