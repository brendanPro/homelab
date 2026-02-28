# Homelab GitOps Roadmap

## Vue d'ensemble

L'objectif est de passer d'un cluster géré manuellement (`kustomize apply`) à un workflow GitOps complet où un push git déclenche automatiquement le déploiement via ArgoCD. En parallèle, remplacer le script `install.sh` par des playbooks Ansible pour pouvoir reconstruire le cluster depuis zéro en une commande.

```
git push → ArgoCD sync → déploiement automatique sur le cluster
ansible-playbook → provisioning RPI depuis zéro
```

---

## Architecture cible des namespaces

Regroupement fonctionnel (au lieu d'un namespace par service) :

| Namespace    | Services                                          |
|--------------|---------------------------------------------------|
| `smart-home` | homeassistant, mosquitto, zigbee2mqtt, frigate    |
| `infra`      | homepage, vaultwarden                             |
| `platform`   | argocd, tailscale, openebs, calico (inchangé)     |

Apps supprimées du repo (hors scope) : `gitea`, `n8n`, `adguard`, `media`, `factorio`, `minecraft`, `nginx-ts`, `storage` (Ceph/Rook)

---

## Structure cible du repo

```
homelab/
├── ansible/
│   ├── inventory.yaml
│   ├── playbooks/
│   │   ├── setup-all.yaml        ← point d'entrée unique
│   │   ├── init-master.yaml      ← kubeadm init + calico + argocd
│   │   └── join-workers.yaml     ← kubeadm join automatique
│   └── roles/
│       ├── common/               ← hosts, kernel modules, sysctl, containerd
│       └── kubernetes/           ← kubelet, kubeadm, kubectl v1.33
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

---

## TODO

### Étape 0 — Docs et AGENTS.md

- [x] Créer `docs/ROADMAP.md` (ce fichier)
- [ ] Réécrire `AGENTS.md` avec l'architecture actuelle, les règles IaC homelab et les avertissements critiques sur les volumes

### Étape 1 — Ansible : provisioning des RPI

Remplacer `homelab/install.sh` (non idempotent, manuel nœud par nœud) par des playbooks Ansible.

Commande unique pour reconstruire le cluster depuis zéro :
```bash
ansible-playbook -i ansible/inventory.yaml ansible/playbooks/setup-all.yaml
```

- [ ] Créer `ansible/inventory.yaml` avec rpimaster, rpinode1, rpinode2
- [ ] Créer le rôle `common` (hosts, kernel modules, sysctl, containerd)
- [ ] Créer le rôle `kubernetes` (kubelet, kubeadm, kubectl v1.33)
- [ ] Créer `playbooks/setup-all.yaml`
- [ ] Créer `playbooks/init-master.yaml` (kubeadm init + Calico)
- [ ] Créer `playbooks/join-workers.yaml` (kubeadm join automatique)

### Étape 2 — Déployer ArgoCD

- [ ] Créer namespace `argocd`
- [ ] Appliquer `platform/argocd/install.yaml` (déplacer depuis `infra/argoCD/`)
- [ ] Créer l'ingress Tailscale pour l'UI ArgoCD
- [ ] Connecter ArgoCD au repo `git@github.com:brendanPro/homelab.git`

### Étape 3 — Restructurer le repo

- [ ] Créer la nouvelle arborescence `apps/` et `platform/`
- [ ] Supprimer les dossiers hors scope (`gitea`, `n8n`, `adguard`, `media`, `factorio`, `minecraft`, `nginx-ts`, `storage`)
- [ ] Déplacer `infra/argoCD/` → `platform/argocd/`
- [ ] Déplacer configs tailscale/openebs/calico → `platform/`

### Étape 4 — Pattern ArgoCD App-of-Apps

Créer une `Application` ArgoCD par namespace fonctionnel. Exemple :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: smart-home
  namespace: argocd
spec:
  source:
    repoURL: git@github.com:brendanPro/homelab.git
    path: apps/smart-home
  destination:
    namespace: smart-home
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

- [ ] Créer `apps/smart-home/application.yaml`
- [ ] Créer `apps/infra/application.yaml`
- [ ] Créer l'Application racine (app-of-apps)

### Étape 5 — Migration des namespaces

> **CRITIQUE — BACKUP OBLIGATOIRE avant toute migration de vaultwarden et homeassistant.**
> Ces deux PVCs ne doivent JAMAIS être supprimés sans backup vérifié :
> - `vaultwarden/vaultwarden-pvc` — tous les mots de passe
> - `homeassistant/homeassistant-config` — toute la configuration domotique

Ordre de migration (du moins au plus critique) :

- [ ] `homepage` → namespace `infra` (stateless, zéro downtime)
- [ ] `vaultwarden` → namespace `infra` (**backup PVC avant**)
- [ ] `mosquitto` → namespace `smart-home`
- [ ] `zigbee2mqtt` → namespace `smart-home`
- [ ] `frigate` → namespace `smart-home`
- [ ] `homeassistant` → namespace `smart-home` (**backup PVC avant**, en dernier)

Pour chaque migration :
1. Mettre à jour `namespace:` dans les YAML de l'app
2. Push git → ArgoCD déploie dans le nouveau namespace
3. Vérifier que tout fonctionne
4. Supprimer l'ancien namespace

### Étape 6 — Mise à jour des versions

- [ ] `zigbee2mqtt` : `2.0.0` → `2.8.0`
