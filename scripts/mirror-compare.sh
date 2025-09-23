#!/usr/bin/env bash
set -euo pipefail
LIST="${1:-}"
DEST_ROOT="${DEST_ROOT:-kuberegistry.dev.kube/rke2}"
REG_USER="${REG_USER:-admin}"
REG_PASS="${REG_PASS:-ZAQwsx!@#123}"
CA_BUNDLE="${CA_BUNDLE:-}"
if [[ -z "$LIST" ]]; then echo "Usage: $0 /path/to/images.all.txt"; exit 2; fi
[[ -f "$LIST" ]] || { echo "Image list not found: $LIST"; exit 1; }
need(){ command -v "$1" >/dev/null || { echo "ERROR: missing $1"; exit 1; }; } ; need skopeo
missing=()
while IFS= read -r IMG; do
  [[ -z "$IMG" ]] && continue
  DEST_REF="${DEST_ROOT}/${IMG}"
  if [[ -n "$CA_BUNDLE" && -f "$CA_BUNDLE" ]]; then
    skopeo inspect --tls-verify=true --cert-dir "$(dirname "$CA_BUNDLE")" --creds "${REG_USER}:${REG_PASS}" "docker://${DEST_REF}" >/dev/null 2>&1 || missing+=("$DEST_REF")
  else
    skopeo inspect --tls-verify=false --creds "${REG_USER}:${REG_PASS}" "docker://${DEST_REF}" >/dev/null 2>&1 || missing+=("$DEST_REF")
  fi
done < "$LIST"
if (( ${#missing[@]} )); then
  echo "Missing images (${#missing[@]}):"; printf '%s\n' "${missing[@]}"; exit 1
else
  echo "All images present."
fi
