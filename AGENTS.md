# AGENTS.md

Guide pour les agents IA travaillant sur ce repo. Lire entièrement avant toute modification.

---

## ⚠️ RÈGLES CRITIQUES — LIRE EN PREMIER

**NE JAMAIS** supprimer, recréer, modifier ou migrer les PVCs suivants sans avoir un backup vérifié et fonctionnel au préalable :

| PVC | Namespace | Contenu |
|-----|-----------|---------|
| `vaultwarden-pvc` | `vaultwarden` | Tous les mots de passe — perte = catastrophe |
| `homeassistant-config` | `homeassistant` | Toute la configuration domotique (automations, devices, historique) |

En cas de doute sur une opération touchant ces volumes : **ne pas exécuter, demander confirmation.**

---

## Description du projet

Homelab Kubernetes tournant sur un cluster Raspberry Pi 5, géré en GitOps via ArgoCD. L'objectif est que tout changement d'infrastructure passe par un push git — aucun `kubectl apply` ou `kustomize apply` manuel en production.

### Hardware

| Nœud | Rôle | IP |
|------|------|----|
| `rpimaster` | control-plane | 192.168.8.144 |
| `rpinode1` | worker | 192.168.1.143 |
| `rpinode2` | worker | 192.168.1.142 |

### Stack technique

- **Kubernetes** v1.33
- **Container runtime** : containerd (systemd cgroup)
- **CNI** : Calico
- **Storage** : OpenEBS (local PV)
- **Réseau externe** : Tailscale (ingress via tailscale operator)
- **GitOps** : ArgoCD
- **Provisioning** : Ansible (en cours de mise en place, voir `ansible/`)

---

## Structure du repo

```
homelab/
├── ansible/                      ← provisioning des RPI depuis zéro
│   ├── inventory.yaml
│   ├── playbooks/
│   └── roles/
├── apps/
│   ├── smart-home/               ← homeassistant, mosquitto, zigbee2mqtt, frigate
│   └── infra/                    ← homepage, vaultwarden
├── platform/
│   ├── argocd/
│   ├── tailscale/
│   ├── openebs/
│   └── calico/
└── docs/
    └── ROADMAP.md
```

> Note : la migration vers cette structure est en cours. L'ancienne structure (`homelab/apps/`, `infra/argoCD/`) est encore présente pendant la transition. Voir `docs/ROADMAP.md`.

---

## Apps en production

### Namespace `smart-home`

| App | Image | PVC critique |
|-----|-------|-------------|
| homeassistant | `ghcr.io/home-assistant/home-assistant:latest` | `homeassistant-config` ⚠️ |
| mosquitto | `eclipse-mosquitto:latest` | `mosquitto-data`, `mosquitto-log` |
| zigbee2mqtt | `koenkk/zigbee2mqtt:2.8.0` | `zigbee2mqtt-data` |
| frigate | `ghcr.io/blakeblackshear/frigate:0.14.1` | `frigate-config`, `frigate-storage` |

### Namespace `infra`

| App | Image | PVC critique |
|-----|-------|-------------|
| vaultwarden | `docker.io/vaultwarden/server:latest` | `vaultwarden-pvc` ⚠️ |
| homepage | `ghcr.io/gethomepage/homepage:latest` | — |

### Namespace `platform`

| Composant | Rôle |
|-----------|------|
| ArgoCD | GitOps — sync git → cluster |
| Tailscale operator | Ingress sécurisé via réseau Tailscale |
| OpenEBS | Provisioning de volumes locaux |
| Calico | CNI (pod networking) |

---

## Workflow GitOps

```
1. Modifier les manifests YAML dans le repo
2. git push → ArgoCD détecte le changement
3. ArgoCD applique automatiquement sur le cluster
```

**Ne jamais appliquer manuellement** avec `kubectl apply -k` ou `kustomize apply` sur les apps gérées par ArgoCD — ArgoCD revertira le changement au prochain sync.

Pour forcer un sync immédiat : UI ArgoCD ou `argocd app sync <app-name>`.

---

## Patterns de code

### Structure d'une app Kustomize

```
app-name/
├── kustomization.yaml            ← racine, référence ./base
└── base/
    ├── kustomization.yaml        ← namespace, labels, liste des resources
    ├── ns.yaml
    ├── deploy.yaml
    ├── svc.yaml
    ├── pvc.yaml                  ← si stockage nécessaire
    ├── ing.yaml                  ← si exposé via Tailscale
    └── assets/                   ← ConfigMaps (configs applicatives)
```

### Pattern kustomization.yaml de base

```yaml
namespace: <namespace>
commonLabels:
  app.kubernetes.io/name: <app>

resources:
- ./ns.yaml
- ./deploy.yaml
- ./svc.yaml
- ./pvc.yaml       # si nécessaire
- ./ing.yaml       # si nécessaire
```

### Pattern ingress Tailscale

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>
  namespace: <namespace>
spec:
  ingressClassName: tailscale
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <app>
            port:
              number: <port>
  tls:
  - hosts:
    - <app>
```

### Pattern Application ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <namespace>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:brendanPro/homelab.git
    targetRevision: main
    path: apps/<namespace>
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

---

## Règles IaC — Homelab

Ces règles tiennent compte des contraintes d'une infra maison sur RPI :

### À faire

- `reclaimPolicy: Retain` sur **tous** les PVCs — ne jamais utiliser `Delete`
- Versionner les images applicatives (pas de `latest` pour les apps critiques comme frigate ou zigbee2mqtt)
- Stocker les configs applicatives dans des ConfigMaps (dossier `assets/`)
- Référencer les secrets via `secretKeyRef` — jamais de valeur en dur dans les YAML commités
- Ajouter `admin-secret.yaml` au `.gitignore` pour les secrets locaux

### À ne pas faire

- Ne pas mettre de secrets en clair dans les YAML (mots de passe, tokens, clés)
- Ne pas hardcoder les IPs dans les services (utiliser la découverte de service Kubernetes)
- Ne pas utiliser `hostPath` pour le stockage persistant
- Ne pas modifier les PVCs critiques (vaultwarden, homeassistant) sans backup
- Ne pas appliquer manuellement sur les namespaces gérés par ArgoCD
- Ne pas utiliser `latest` pour les images dont la version a un impact sur les données (zigbee2mqtt, frigate)

### Resource limits

Sur RPI, les ressources sont limitées. Les `requests` et `limits` CPU/mémoire ne sont **pas obligatoires** mais recommandées pour les apps gourmandes (frigate). Prioriser la stabilité sur la granularité.

---

## Secrets et variables d'environnement

Les secrets ne sont jamais commités. Ils sont créés manuellement sur le cluster :

```bash
# Exemple : secret admin Gitea
kubectl create secret generic gitea-admin-secret \
  --namespace gitea \
  --from-literal=password='ton-mot-de-passe'
```

Les fichiers `*.env` et `admin-secret.yaml` sont dans le `.gitignore`.

Les variables sensibles référencées dans les déploiements :
- `gitea/staefulset.yaml` → `GITEA_ADMIN_PASSWORD` via `secretKeyRef: gitea-admin-secret`
- `frigate/config.yaml` → `{FRIGATE_RTSP_USER}` et `{FRIGATE_RTSP_PASSWORD}` via variables d'env

---

## Troubleshooting rapide

```bash
# État général
kubectl get pods -A

# Logs d'une app
kubectl logs -n <namespace> deployment/<app>

# Events d'un namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# État des PVCs
kubectl get pvc -A

# Forcer un sync ArgoCD
argocd app sync <app-name>

# Vérifier un manifest avant apply
kubectl diff -k apps/<namespace>/<app>
```

---

## Références

- `docs/ROADMAP.md` — plan de migration en cours
- Cluster : `https://192.168.8.144:6443`
- ArgoCD UI : `https://argocd.wombat-wahoo.ts.net` (une fois déployé)
