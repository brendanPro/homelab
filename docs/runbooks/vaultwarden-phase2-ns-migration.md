# Runbook — Vaultwarden phase 2 : migration namespace `infra`

> **⚠️ CRITIQUE — NE PAS `git push` sans runbook complet.**
> PVC `vaultwarden-pvc` = **tous les mots de passe**.
> Un push prématuré sans rebind PV → volume vide → **catastrophe**.

## Objectif

- Vaultwarden réel → namespace `infra`
- PVC `vaultwarden-pvc` conservé (rebind PV)
- Pod sur **rpinode2**
- Homepage widget : `namespace: infra` dans `services.yaml`

## Side effects (~5–10 min)

| Impact | Détail |
|--------|--------|
| **Coffre mots de passe** | Down — apps/clients Bitwarden indisponibles |
| **Non impacté** | smart-home, MQTT, domotique |

## Prérequis

- [ ] Phase 1 GitOps OK (`vaultwarden` Application Synced)
- [ ] Fenêtre maintenance ~10 min
- [ ] Manifests phase 2 préparés, **pas pushés** avant rebind

## État cluster (référence)

| Ressource | Valeur |
|-----------|--------|
| PVC | `vaultwarden-pvc` (5 Gi) |
| PV | `pvc-fc24a55b-5a3b-410e-a4b8-f5be7222f862` |
| Hostpath | `/var/openebs/local/pvc-fc24a55b-5a3b-410e-a4b8-f5be7222f862` |
| Nœud | rpinode2 |
| Reclaim policy | **Retain** |

## Procédure

### 0. Suspendre ArgoCD (root + vaultwarden)

```bash
kubectl patch application root -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'

kubectl patch application vaultwarden -n platform --type json \
  -p='[{"op": "remove", "path": "/spec/syncPolicy/automated"}]'
```

### 1. Scale down

```bash
kubectl scale deployment vaultwarden -n vaultwarden --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=vaultwarden -n vaultwarden --timeout=180s
```

### 2. Backup PVC (obligatoire)

```bash
./scripts/vaultwarden-backup-pvc.sh
```

Archive : `/var/backups/homelab/vaultwarden-YYYY-MM-DD/vaultwarden-data.tgz`

### 3. Rebind PV

```bash
kubectl delete pvc vaultwarden-pvc -n vaultwarden
kubectl patch pv pvc-fc24a55b-5a3b-410e-a4b8-f5be7222f862 \
  -p '{"spec":{"claimRef":null}}' --type merge
```

### 4. Supprimer legacy namespace `vaultwarden`

```bash
kubectl delete deployment,service,ingress vaultwarden -n vaultwarden --ignore-not-found
kubectl delete job -n vaultwarden -l job-name --ignore-not-found
kubectl delete secret vaultwarden-secret -n vaultwarden --ignore-not-found
```

### 5. Commit + push + sync ArgoCD

Puis :

```bash
kubectl patch application vaultwarden -n platform --type merge \
  -p '{"operation":{"sync":{"revision":"main","prune":true}}}'
```

### 6. Vérifications

```bash
kubectl get pods,pvc -n infra -l app.kubernetes.io/name=vaultwarden
curl -sS -o /dev/null -w '%{http_code}\n' https://newvaultwarden.wombat-wahoo.ts.net/alive
```

Login Bitwarden + sync client.

### 7. Réactiver selfHeal

```bash
kubectl patch application vaultwarden -n platform --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
kubectl patch application root -n platform --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### 8. Nettoyage

```bash
kubectl delete job vaultwarden-pvc-backup-YYYY-MM-DD -n vaultwarden --ignore-not-found
kubectl delete namespace vaultwarden --ignore-not-found
```

Conserver l'archive backup 1–2 semaines sur rpinode2.
