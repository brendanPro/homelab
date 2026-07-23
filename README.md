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
| Ansible | Provisioning — cluster K8s (à venir), OpenClaw (playbook prêt) |

## Cluster

3 nœuds Raspberry Pi 5 :
- `rpimaster` — control-plane
- `rpinode1` — worker
- `rpinode2` — worker

## Apps en production

**`smart-home`** — homeassistant, mosquitto, zigbee2mqtt, frigate, homepage

**`infra`** — vaultwarden

## Structure du repo

```
homelab/
├── ansible/        ← provisioning (legacy bootstrap + guide K8S-PROVISIONING.md)
├── apps/           ← applications (smart-home, infra)
├── platform/       ← argocd, tailscale, openebs, calico
└── docs/
    └── ROADMAP.md  ← plan de migration en cours
```

## Documentation

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — roadmap et todos
- [`AGENTS.md`](AGENTS.md) — guide pour les agents IA
- [`ansible/README.md`](ansible/README.md) — Ansible (OpenClaw + plan cluster K8s)
- [`docs/RENOVATE.md`](docs/RENOVATE.md) — versions épinglées et Renovate
