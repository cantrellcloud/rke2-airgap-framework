#!/usr/bin/env bash
set -euo pipefail
DEST_DIR="${HOME}/.kube"
SRC="/etc/rancher/rke2/rke2.yaml"
[[ -f "$SRC" ]] || { echo "rke2 kubeconfig not found at $SRC"; exit 1; }
mkdir -p "$DEST_DIR"
install -m 0600 "$SRC" "$DEST_DIR/config"
chown "$(id -u):$(id -g)" "$DEST_DIR/config" || true
echo "Wrote $DEST_DIR/config"
