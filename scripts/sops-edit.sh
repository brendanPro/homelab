#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_KEY="$HOME/.config/sops/age/keys.txt"
LOCAL_KEY="$ROOT/secrets/age.key"

if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
  KEY_FILE="$SOPS_AGE_KEY_FILE"
elif [[ -f "$DEFAULT_KEY" ]]; then
  KEY_FILE="$DEFAULT_KEY"
elif [[ -f "$LOCAL_KEY" ]]; then
  KEY_FILE="$LOCAL_KEY"
else
  echo "Clé age introuvable." >&2
  echo "Attendu : $DEFAULT_KEY (ou secrets/age.key)" >&2
  echo "Voir secrets/README.md pour le setup." >&2
  exit 1
fi

export SOPS_AGE_KEY_FILE="$KEY_FILE"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <fichier.sops.yaml> [fichier2 ...]" >&2
  echo "Clé utilisée : $KEY_FILE" >&2
  exit 1
fi

cd "$ROOT"
for file in "$@"; do
  sops "$file"
done
