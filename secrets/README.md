# Secrets SOPS — Homelab

Les secrets applicatifs sont chiffrés avec [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) et versionnés dans Git sous le suffixe `*.sops.yaml`.

## Prérequis

```bash
brew install sops age
```

## Clé age

Ce repo utilise la clé age standard SOPS déjà présente sur ce poste :

| Élément | Emplacement |
|---------|-------------|
| Clé privée | `~/.config/sops/age/keys.txt` |
| Clé publique | `.sops.yaml` → `age19cgxjr3phxdw5g8fg49weueyx2dvhn54qlkjesnhkr562axu6y5srah56v` |

SOPS la trouve automatiquement — pas besoin de `SOPS_AGE_KEY_FILE` si ce fichier existe.

Sur une **nouvelle machine**, copier `keys.txt` depuis ton backup sécurisé vers `~/.config/sops/age/keys.txt`.

## Setup cluster (ArgoCD)

Déployer la même clé privée sur le repo-server ArgoCD :

```bash
kubectl create secret generic argocd-age-key \
  -n platform \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

ArgoCD ne déchiffre **pas** SOPS nativement. Le repo-server est patché avec **KSOPS** (`platform/argocd/base/repo-server-ksops-patch.yaml`) et monte `argocd-age-key`. Chaque app Kustomize utilise un générateur `kind: ksops` pointant vers le fichier `*.sops.yaml`.

```bash
kubectl create secret generic argocd-age-key \
  -n platform \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -k platform/argocd
```

### Secrets bootstrap (hors Git)

Ces secrets restent créés manuellement (chicken-and-egg ArgoCD) :

```bash
# Accès repo GitHub (deploy key read-only)
kubectl create secret generic homelab-repo \
  -n platform \
  --from-literal=type=git \
  --from-literal=url=git@github.com:brendanPro/homelab.git \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd_deploy_key \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret homelab-repo -n platform \
  argocd.argoproj.io/secret-type=repository --overwrite
```

## Workflow quotidien

### Éditer un secret

```bash
sops homelab/apps/frigate/base/secret.sops.yaml
# Sauvegarde automatique + rechiffrement
```

Ou via le helper :

```bash
./scripts/sops-edit.sh homelab/apps/frigate/base/secret.sops.yaml
```

### Vérifier le contenu déchiffré

```bash
sops -d homelab/config/tailscale/oauth.sops.yaml
```

### Valider un overlay Kustomize

```bash
kubectl kustomize homelab/apps/frigate --enable-helm
```

> `kubectl kustomize` affiche les valeurs chiffrées sans KSOPS local — normal. ArgoCD déchiffre via KSOPS au sync.

## Inventaire des secrets SOPS

| Fichier | Secret K8s | Namespace | Clés |
|---------|-----------|-----------|------|
| `homelab/config/tailscale/oauth.sops.yaml` | `operator-oauth` | tailscale | `client_id`, `client_secret` |
| `homelab/apps/frigate/base/secret.sops.yaml` | `creds` | frigate | `FRIGATE_RTSP_USER`, `FRIGATE_RTSP_PASSWORD` |
| `homelab/apps/vaultwarden/base/secret.sops.yaml` | `vaultwarden-secret` | vaultwarden | `ADMIN_TOKEN` |
| `homelab/apps/factorio/base/secret.sops.yaml` | `factorio-secret` | factorio | variables `.env` Factorio |
| `homelab/apps/homepage/resources/secret.sops.yaml` | `homepage` | smart-home | token SA |
| `homelab/apps/media/base/qbittorrent/config.sops.yaml` | `qbittorrent-config` | qbittorrent | config WebUI |

## Rotation de clé age

```bash
# Générer une nouvelle paire
age-keygen -o ~/.config/sops/age/keys.txt.new

# Mettre à jour .sops.yaml avec la nouvelle clé publique
# Re-chiffrer tous les fichiers
find homelab -name '*.sops.yaml' -print0 | xargs -0 sops updatekeys -y

# Redéployer argocd-age-key sur le cluster
kubectl create secret generic argocd-age-key \
  -n platform \
  --from-file=keys.txt=$HOME/.config/sops/age/keys.txt.new \
  --dry-run=client -o yaml | kubectl apply -f -
```
