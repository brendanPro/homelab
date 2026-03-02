# OpenClaw — Documentation opérationnelle

OpenClaw est un agent AI déployé sur le cluster via l'opérateur Kubernetes `openclaw-rocks/k8s-operator`.
Il est accessible à l'adresse : **https://openclaw.wombat-wahoo.ts.net**

---

## Architecture de déploiement

```
argocd-apps/ai/
├── openclaw-crds.yaml      ← sync-wave: -1 — CRDs installées en premier
├── openclaw-operator.yaml  ← sync-wave: 0  — opérateur (namespace openclaw-operator-system)
└── openclaw.yaml           ← instance OpenClaw (namespace ai)

apps/ai/openclaw/
└── base/
    ├── kustomization.yaml
    ├── openclawinstance.yaml  ← config principale (modèles, réseau, stockage)
    ├── storageclass.yaml      ← StorageClass OpenEBS dédiée
    ├── networkpolicy.yaml     ← allow Tailscale ingress + Ollama egress
    └── ingress.yaml           ← Tailscale ingress vers port 18789
```

**Important** : l'opérateur gère lui-même les ressources Kubernetes (Deployment, Service, etc.) à partir de la CR `OpenClawInstance`. Ne jamais appliquer manuellement.

---

## Provider LLM : Google Gemini (free tier)

OpenClaw utilise Google Gemini via l'API Generative Language.

### Modèles configurés

| Modèle | Context | Max tokens | Free tier |
|--------|---------|------------|-----------|
| `gemini-2.0-flash` | 1M tokens | 8192 | ✅ |
| `gemini-1.5-flash` | 1M tokens | 8192 | ✅ |

### Obtenir une clé API

1. Aller sur [aistudio.google.com](https://aistudio.google.com)
2. "Get API key" → "Create API key"
3. Copier la clé (`AIza...`)

---

## Setup initial (à faire une seule fois après installation)

### 1. Créer le secret Kubernetes

La clé API ne doit jamais être dans git. Elle est stockée dans un secret Kubernetes :

```bash
# Mettre la clé dans .env (déjà dans .gitignore)
echo "GEMINI_API_KEY=AIzaXXXXX" > .env

# Créer le secret sur le cluster
source .env && kubectl create secret generic openclaw-llm-keys \
  --namespace ai \
  --from-literal=GEMINI_API_KEY="${GEMINI_API_KEY}"
```

Si le secret existe déjà (mise à jour de clé) :

```bash
source .env && kubectl create secret generic openclaw-llm-keys \
  --namespace ai \
  --from-literal=GEMINI_API_KEY="${GEMINI_API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 2. La clé est injectée automatiquement via le spec

Dans `openclawinstance.yaml`, l'env var `GEMINI_API_KEY` est montée depuis le secret :

```yaml
env:
  - name: GEMINI_API_KEY
    valueFrom:
      secretKeyRef:
        name: openclaw-llm-keys
        key: GEMINI_API_KEY
```

OpenClaw lit **`GEMINI_API_KEY`** automatiquement pour le provider `google` (provider built-in).
**Aucune config `models.providers.google` n'est nécessaire** — ne pas l'ajouter, ça casse tout.

> ⚠️ Ne pas utiliser `GOOGLE_GENERATIVE_AI_API_KEY` — OpenClaw utilise `GEMINI_API_KEY`.

### 3. Récupérer le token de connexion

```bash
kubectl get secret -n ai openclaw-gateway-token -o jsonpath='{.data.token}' | base64 -d
```

Coller ce token dans l'UI → champ "Connect".

### 4. Approuver le device pairing

La première connexion depuis un nouveau navigateur nécessite une approbation :

```bash
# Lister les devices en attente
kubectl exec -n ai openclaw-0 -- node /app/openclaw.mjs devices list

# Approuver
kubectl exec -n ai openclaw-0 -- node /app/openclaw.mjs devices approve <requestId>
```

---

## Troubleshooting

### "No API key found for provider 'google'"

La clé n'est pas dans la config OpenClaw sur le PVC. Refaire l'étape 2 du setup initial.

### "Model context window too small"

Le `contextWindow` déclaré dans `openclawinstance.yaml` est inférieur au minimum de 16000 tokens requis par OpenClaw.

### "model requires more system memory"

Les nodes ont 8GB RAM. Si Ollama est utilisé à la place de Gemini, les modèles nécessitent du swap ou un modèle plus quantizé. Raison pour laquelle on utilise Gemini (API cloud, pas de contrainte RAM).

### Pod en CrashLoopBackOff — "Unrecognized key"

Config invalide dans `openclawinstance.yaml`. Vérifier les logs :

```bash
kubectl logs -n ai openclaw-0
```

### CORS error dans l'UI

Vérifier que `gateway.controlUi.allowedOrigins` dans `openclawinstance.yaml` contient bien `https://openclaw.wombat-wahoo.ts.net`.

---

## Mise à jour de la version de l'opérateur

La version est fixée dans deux fichiers ArgoCD :

```bash
# Fichiers à mettre à jour
argocd-apps/ai/openclaw-crds.yaml      # targetRevision: vX.Y.Z
argocd-apps/ai/openclaw-operator.yaml  # targetRevision: vX.Y.Z
```

Vérifier les releases : https://github.com/openclaw-rocks/k8s-operator/releases
