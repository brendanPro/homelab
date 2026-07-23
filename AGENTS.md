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
- **Provisioning** : Ansible — cluster K8s à ansibleiser ([`ansible/docs/K8S-PROVISIONING.md`](ansible/docs/K8S-PROVISIONING.md)) ; playbook OpenClaw opérationnel

> ⚠️ **Outillage** : Ce repo utilise **kustomize uniquement** pour la gestion des manifests.
> Ne jamais installer ni utiliser `helm` directement. Les `helmCharts` dans les `kustomization.yaml`
> sont rendus via `kubectl kustomize --enable-helm` (kustomize gère helm en interne).
> Ne pas suggérer `helm install`, `helm upgrade` ou `brew install helm`.

---

## Structure du repo

```
homelab/
├── ansible/                      ← provisioning (voir ansible/README.md)
│   ├── docs/K8S-PROVISIONING.md  ← plan migration cluster K8s
│   ├── legacy/install-k8s-bootstrap.sh
│   ├── inventory.yml
│   └── playbooks/
├── apps/
│   ├── smart-home/               ← homepage, homeassistant, mosquitto, zigbee2mqtt, frigate
│   └── infra/                    ← vaultwarden
├── platform/
│   ├── argocd/
│   ├── tailscale/
│   ├── openebs/
│   ├── calico/
│   ├── metrics-server/
│   └── logs/
└── docs/
    └── ROADMAP.md
```

> Note : la migration vers cette structure est en cours. Voir `docs/ROADMAP.md`.

---

## Apps en production

### Namespace `smart-home`

| App | Image | PVC critique |
|-----|-------|-------------|
| homeassistant | `ghcr.io/home-assistant/home-assistant:2026.7.3` | `homeassistant-config` ⚠️ |
| mosquitto | `eclipse-mosquitto:2.1.2-alpine` | `mosquitto-data`, `mosquitto-log` |
| zigbee2mqtt | `koenkk/zigbee2mqtt:2.8.0` | `zigbee2mqtt-data` |
| frigate | `ghcr.io/blakeblackshear/frigate:0.14.1` | `frigate-config`, `frigate-storage` |
| homepage | `ghcr.io/gethomepage/homepage:v1.13.2` | — |

### Namespace `infra`

| App | Image | PVC critique |
|-----|-------|-------------|
| vaultwarden | `docker.io/vaultwarden/server:1.36.0` | `vaultwarden-pvc` ⚠️ |

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

App-of-apps : `platform/argocd/root-app.yaml` → `argocd-apps/` → une Application par app.

Première app migrée : **homepage** (`argocd-apps/smart-home/homepage.yaml`). **Frigate** et **mosquitto** phase 1 GitOps : même pattern, namespace runtime conservé (`frigate`, `mosquitto`). Mosquitto phase 2 (NS `smart-home` + alias legacy) : manifests préparés, runbook `docs/runbooks/mosquitto-phase2-ns-migration.md` — **exécution manuelle PV rebind avant push**.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homepage
  namespace: platform
spec:
  project: default
  source:
    repoURL: git@github.com:brendanPro/homelab.git
    targetRevision: main
    path: apps/smart-home/homepage
  destination:
    server: https://kubernetes.default.svc
    namespace: smart-home
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Bootstrap ArgoCD (une fois) :

```bash
# 1. Repo GitHub (deploy key read-only)
kubectl create secret generic homelab-repo -n platform ...

# 2. Clé SOPS montée sur le repo-server (KSOPS)
kubectl create secret generic argocd-age-key -n platform \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt

# 3. Déployer ArgoCD (inclut KSOPS + --enable-alpha-plugins) + root app-of-apps
kubectl apply -k platform/argocd

# 4. git push → ArgoCD sync homepage automatiquement
```

---

## Règles IaC — Homelab

Ces règles tiennent compte des contraintes d'une infra maison sur RPI :

### À faire

- `reclaimPolicy: Retain` sur **tous** les PVCs — ne jamais utiliser `Delete`
- Versionner les images applicatives via `images:` dans les `kustomization.yaml` — pas de `latest`
- Mises à jour : [Renovate](docs/RENOVATE.md) (PR hebdomadaires, merge manuel)
- Stocker les configs applicatives dans des ConfigMaps (dossier `assets/`)
- Référencer les secrets via `secretKeyRef` — jamais de valeur en dur dans les YAML commités
- Chiffrer les secrets avec **SOPS + age** (`*.sops.yaml`) — voir `secrets/README.md`

### À ne pas faire

- Ne pas mettre de secrets en clair dans les YAML (mots de passe, tokens, clés)
- Ne pas hardcoder les IPs dans les services (utiliser la découverte de service Kubernetes)
- Ne pas utiliser `hostPath` pour le stockage persistant
- Ne pas modifier les PVCs critiques (vaultwarden, homeassistant) sans backup
- Ne pas appliquer manuellement sur les namespaces gérés par ArgoCD
- Ne pas utiliser `latest` pour les images applicatives (impact données ou comportement)

### Resource limits

Sur RPI, les ressources sont limitées. Les `requests` et `limits` CPU/mémoire ne sont **pas obligatoires** mais recommandées pour les apps gourmandes (frigate). Prioriser la stabilité sur la granularité.

---

## Secrets et variables d'environnement

Les secrets applicatifs sont gérés avec **SOPS + age** et versionnés chiffrés (`*.sops.yaml`).

| Élément | Emplacement |
|---------|-------------|
| Clé publique age | `.sops.yaml` (commité) |
| Clé privée age | `~/.config/sops/age/keys.txt` (standard SOPS, gitignored) |
| Workflow complet | `secrets/README.md` |

### Setup rapide

```bash
# Éditer un secret (SOPS trouve la clé dans ~/.config/sops/age/keys.txt)
sops apps/smart-home/frigate/base/secret.sops.yaml

# Déployer la clé sur ArgoCD (une fois)
kubectl create secret generic argocd-age-key \
  -n platform \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

ArgoCD déchiffre les `*.sops.yaml` via le plugin **KSOPS** (repo-server patché dans `platform/argocd/base/repo-server-ksops-patch.yaml`) si `argocd-age-key` est présent. Les apps Kustomize référencent les secrets via un générateur `kind: ksops` (voir `apps/smart-home/homepage/resources/secret-generator.yaml`).

### Secrets bootstrap (hors Git — chicken-and-egg ArgoCD)

La clé deploy `~/.ssh/argocd_deploy_key` doit être ajoutée dans GitHub → Settings → Deploy keys (read-only).

```bash
kubectl create secret generic homelab-repo \
  -n platform \
  --from-literal=type=git \
  --from-literal=url=git@github.com:brendanPro/homelab.git \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd_deploy_key \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret homelab-repo -n platform argocd.argoproj.io/secret-type=repository
```

Voir le template : `platform/argocd/base/repo-secret.yaml.example`

### Secrets SOPS par app

| App | Fichier |
|-----|---------|
| tailscale | `platform/tailscale/oauth.sops.yaml` |
| frigate | `apps/smart-home/frigate/base/secret.sops.yaml` |
| vaultwarden | `apps/infra/vaultwarden/base/secret.sops.yaml` |
| homepage | `apps/smart-home/homepage/resources/secret.sops.yaml` |

Les variables sensibles Frigate dans `assets/config.yaml` utilisent `{FRIGATE_RTSP_USER}` / `{FRIGATE_RTSP_PASSWORD}` — injectées via le secret `creds`.

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
