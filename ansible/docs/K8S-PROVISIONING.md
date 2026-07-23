# Provisionnement Kubernetes — guide de migration Ansible

> Plan pour remplacer le bootstrap manuel par des playbooks idempotents.
> **Statut : non implémenté** — référence de travail pour la ROADMAP étape 6.

---

## Contexte

Le cluster homelab actuel (3× RPi 5, Ubuntu 24.04) a été provisionné à la main. Le script d’origine est archivé ici :

```
ansible/legacy/install-k8s-bootstrap.sh
```

Ce script **ne doit plus être exécuté** tel quel. Problèmes documentés :

| Élément script legacy | État prod actuel | Action Ansible |
|----------------------|------------------|----------------|
| Docker repo `amd64` | RPi = **arm64** | `arch: arm64` dans les dépôts |
| Kubernetes **v1.30** | Cluster **v1.33.3** | Variable `k8s_version: "1.33"` |
| IPs workers `192.168.1.x` | Internal-IP `192.168.8.143/142` | Inventory + `group_vars` — harmoniser avec la réalité réseau |
| Modules `rbd`, `ceph` | Ceph/Rook retirés | Supprimer ou rendre optionnel |
| Pas de kubeadm init/join | Cluster déjà formé | Playbooks séparés init / join |

---

## Cartographie legacy → rôles Ansible

### Phase 1 — Tous les nœuds (`role: common`)

Équivalent des lignes 3–35 de `install-k8s-bootstrap.sh` :

| Tâche | Détail |
|-------|--------|
| `/etc/hosts` + cloud-init template | Entrées rpimaster, rpinode1, rpinode2 |
| Modules kernel | `overlay`, `br_netfilter` (retirer rbd/ceph sauf besoin) |
| Sysctl | `bridge-nf-call-iptables`, `ip_forward` |
| Paquets base | `curl`, `ca-certificates`, `apt-transport-https`, `gnupg`, `lvm2` |

### Phase 2 — Runtime (`role: containerd`)

| Tâche | Détail |
|-------|--------|
| Dépôt containerd | Docker CE repo **arm64** ou package Ubuntu natif |
| Config | `SystemdCgroup = true` dans `config.toml` |
| Service | enable + restart containerd |

### Phase 3 — Kubernetes binaires (`role: kubernetes`)

| Tâche | Détail |
|-------|--------|
| Repo pkgs.k8s.io | Version pin (`v1.33`) |
| Packages | `kubelet`, `kubeadm`, `kubectl` |
| Hold | `apt-mark hold` pour éviter upgrades accidentelles |
| kubelet | config drop-in si besoin (cgroup driver systemd) |

### Phase 4 — Control plane (`playbook: k8s-init.yml`, hôte rpimaster)

Non présent dans le script legacy — à documenter depuis la procédure manuelle utilisée :

- `kubeadm init` (pod network CIDR Calico, etc.)
- Copie kubeconfig admin
- Installation CNI : `kubectl apply -k platform/calico`

### Phase 5 — Workers (`playbook: k8s-join.yml`)

- `kubeadm join` avec token (Ansible vault pour le join command ou `--discovery-token-unsafe-skip-ca-verification` en lab only)
- Vérification `kubectl get nodes`

### Phase 6 — Platform cluster-wide (`playbook: platform.yml`)

Apply manuel aujourd’hui — à automatiser ou laisser GitOps :

| Composant | Manifests | Notes |
|-----------|-----------|-------|
| OpenEBS | `platform/openebs/` | StorageClass avant apps avec PVC |
| metrics-server | `platform/metrics-server/` | `--kubelet-insecure-tls` conservé |
| logs | `platform/logs/` | logrotate + cronjob cleanup |
| Tailscale operator | `platform/tailscale/` | Secret OAuth via SOPS / vault Ansible |
| ArgoCD | `platform/argocd/` | Puis root app-of-apps |

Ordre recommandé : OpenEBS → metrics-server → logs → Calico (si pas en init) → Tailscale → ArgoCD.

### Phase 7 — GitOps

Une fois ArgoCD up :

```bash
kubectl apply -k argocd-apps/
```

Le reste (smart-home, infra) est géré par ArgoCD — **ne pas** dupliquer dans Ansible sauf bootstrap initial.

---

## Structure cible proposée

```
ansible/
├── inventory/
│   ├── homelab.yml          # rpimaster, rpinode1, rpinode2
│   └── rpiclaw.yml          # inventaire OpenClaw (existant)
├── group_vars/
│   ├── k8s_nodes.yml        # k8s_version, pod_cidr, etc.
│   └── rpiclaw.yml
├── host_vars/
├── roles/
│   ├── common/
│   ├── containerd/
│   └── kubernetes/
├── playbooks/
│   ├── site.yml             # orchestration complète
│   ├── k8s-init.yml
│   ├── k8s-join.yml
│   ├── platform.yml
│   └── setup-rpiclaw.yml    # existant
├── legacy/
│   └── install-k8s-bootstrap.sh
└── docs/
    └── K8S-PROVISIONING.md  # ce fichier
```

---

## Inventory homelab (esquisse)

```yaml
# inventory/homelab.yml
all:
  children:
    k8s_control_plane:
      hosts:
        rpimaster:
          ansible_host: 192.168.8.144
    k8s_workers:
      hosts:
        rpinode1:
          ansible_host: 192.168.8.143
        rpinode2:
          ansible_host: 192.168.8.142
    k8s_cluster:
      children:
        k8s_control_plane:
        k8s_workers:
```

> Vérifier les IPs réelles (`kubectl get nodes -o wide`) avant de figer l’inventory.

---

## Variables suggérées (`group_vars/k8s_nodes.yml`)

```yaml
k8s_version: "1.33"
k8s_patch_version: "1.33.3"   # optionnel, pin exact
containerd_version: "1.7.18"  # aligné prod
pod_network_cidr: "192.168.0.0/16"  # Calico — vérifier manifest platform/calico
architecture: arm64
```

---

## Critères de done

- [ ] Inventory homelab avec IPs validées
- [ ] Rôles `common`, `containerd`, `kubernetes` idempotents
- [ ] Playbook rebuild control-plane from scratch (lab/test)
- [ ] Playbook join worker
- [ ] Playbook platform (ou doc « apply -k » post-kubeadm)
- [ ] `legacy/install-k8s-bootstrap.sh` supprimé ou marqué clairement obsolète
- [ ] `AGENTS.md` + `ROADMAP.md` mis à jour
- [ ] Tests sur RPi spare ou VM arm64 avant prod

---

## Ordre de travail recommandé

1. **Inventory + group_vars** — sans toucher au cluster prod
2. **Rôle common** — test sur un nœud (sysctl, modules)
3. **Rôle containerd** — aligné arm64 + systemd cgroup
4. **Rôle kubernetes** — binaires v1.33 + hold
5. **kubeadm init/join** — runbook séparé, secrets dans Ansible Vault
6. **platform.yml** — wrapper autour des `kubectl apply -k platform/*`
7. Supprimer `legacy/` une fois les playbooks validés

---

## Références repo

| Ressource | Chemin |
|-----------|--------|
| CNI Calico | `platform/calico/` |
| Storage | `platform/openebs/` |
| Metrics | `platform/metrics-server/` |
| Logs | `platform/logs/` |
| Ingress | `platform/tailscale/` |
| GitOps | `platform/argocd/`, `argocd-apps/` |
| ROADMAP | `docs/ROADMAP.md` § étape 6 |
