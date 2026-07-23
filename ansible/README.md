# Ansible — homelab

Deux périmètres distincts dans ce dossier :

| Périmètre | Statut | Fichiers |
|-----------|--------|----------|
| **Cluster K8s** (rpimaster, rpinode1, rpinode2) | 📋 À ansibleiser | `legacy/install-k8s-bootstrap.sh`, [`docs/K8S-PROVISIONING.md`](docs/K8S-PROVISIONING.md) |
| **RPi OpenClaw** (`rpiclaw.local`) | ✅ Playbook utilisable | `playbooks/setup-rpiclaw.yml` |

---

## OpenClaw (rpiclaw)

Machine séparée du cluster homelab — Node.js, Chromium, gcloud.

```bash
cp ansible/host_vars/rpiclaw.local.yml.example ansible/host_vars/rpiclaw.local.yml
# éditer ansible_user et la clé SSH

ansible-playbook -i ansible/inventory.yml ansible/playbooks/setup-rpiclaw.yml
```

Variables : `ansible/group_vars/rpiclaw.yml`

---

## Cluster Kubernetes (futur)

Le bootstrap manuel d’origine est archivé dans :

```
ansible/legacy/install-k8s-bootstrap.sh
```

**Ne pas l’exécuter** — script obsolète (amd64, K8s v1.30). Il sert de checklist pour écrire les rôles Ansible.

Guide complet pour « ansibleiser » le cluster : **[`docs/K8S-PROVISIONING.md`](docs/K8S-PROVISIONING.md)**

Contenu cible une fois migré :

1. Prérequis nœuds (hosts, sysctl, modules kernel)
2. containerd (arm64, systemd cgroup)
3. kubelet / kubeadm / kubectl (version alignée sur `platform/`)
4. Post-install cluster (`platform/calico`, `openebs`, `metrics-server`, `logs`, etc.)
5. Bootstrap ArgoCD → GitOps (`platform/argocd`, `argocd-apps/`)

---

## Structure actuelle

```
ansible/
├── README.md
├── docs/
│   └── K8S-PROVISIONING.md
├── legacy/
│   └── install-k8s-bootstrap.sh
├── inventory.yml              # rpiclaw uniquement pour l’instant
├── group_vars/
├── host_vars/
└── playbooks/
    └── setup-rpiclaw.yml
```

Structure cible (cluster) : décrite dans `docs/K8S-PROVISIONING.md`.
