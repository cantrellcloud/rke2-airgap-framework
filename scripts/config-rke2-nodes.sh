
#!/usr/bin/env bash
# config-rke2-nodes.sh
set -euo pipefail

REGISTRY_ROOT="kuberegistry.dev.kube/rke2"
REG_USERNAME="${REG_USERNAME:-admin}"
REG_PASSWORD="${REG_PASSWORD:-ZAQwsx!@#123}"
IMAGES_LIST="./lists/images.all.txt"
CA_SRC=""
ROLE="auto"
NO_RESTART="false"

while (( "$#" )); do
  case "$1" in
    -r|--registry-root) REGISTRY_ROOT="${2:?}"; shift 2 ;;
    -l|--images-list)   IMAGES_LIST="${2:?}"; shift 2 ;;
    -c|--ca)            CA_SRC="${2:?}"; shift 2 ;;
    --user)             REG_USERNAME="${2:?}"; shift 2 ;;
    --pass)             REG_PASSWORD="${2:?}"; shift 2 ;;
    --role)             ROLE="${2:?}"; shift 2 ;;
    --no-restart)       NO_RESTART="true"; shift ;;
    -h|--help) sed -n '1,200p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo)."; exit 1; }

RKE2_DIR="/etc/rancher/rke2"
IMAGES_DIR="/var/lib/rancher/rke2/agent/images"
CA_DEST="${RKE2_DIR}/kuberegistry-ca.crt"
mkdir -p "$RKE2_DIR" "$IMAGES_DIR"

[[ -f "$IMAGES_LIST" ]] || { echo "Images list not found: $IMAGES_LIST"; exit 1; }
REG_HOST="$(echo "$REGISTRY_ROOT" | cut -d/ -f1)"

if [[ -n "$CA_SRC" ]]; then
  install -m 0644 "$CA_SRC" "$CA_DEST"
  command -v update-ca-certificates >/dev/null && update-ca-certificates || true
  command -v update-ca-trust >/dev/null && update-ca-trust extract || true
fi

cat > "${RKE2_DIR}/registries.yaml" <<EOF
mirrors:
  "docker.io":
    endpoints: ["https://${REGISTRY_ROOT}/docker.io"]
  "registry.k8s.io":
    endpoints: ["https://${REGISTRY_ROOT}/registry.k8s.io"]
  "quay.io":
    endpoints: ["https://${REGISTRY_ROOT}/quay.io"]
  "ghcr.io":
    endpoints: ["https://${REGISTRY_ROOT}/ghcr.io"]
  "rancher":
    endpoints: ["https://${REGISTRY_ROOT}/rancher"]
  "rancher.io":
    endpoints: ["https://${REGISTRY_ROOT}/rancher.io"]
configs:
  "${REG_HOST}":
    auth:
      username: "${REG_USERNAME}"
      password: "${REG_PASSWORD}"
    tls:
      $( [[ -f "$CA_DEST" ]] && echo "ca_file: ${CA_DEST}" || echo "# ca_file: ${CA_DEST}" )
EOF

cat > "${RKE2_DIR}/config.yaml" <<EOF
system-default-registry: "${REGISTRY_ROOT}"
EOF

install -m 0644 "$IMAGES_LIST" "${IMAGES_DIR}/01-images.txt"

detect_role() {
  case "$ROLE" in
    server|agent) echo "$ROLE"; return ;;
  esac
  if systemctl list-unit-files | grep -q '^rke2-server\.service'; then
    echo "server"
  elif systemctl list-unit-files | grep -q '^rke2-agent\.service'; then
    echo "agent"
  else
    echo "server"
  fi
}
ROLE_RESOLVED="$(detect_role)"
SERVICE="rke2-${ROLE_RESOLVED}"

if [[ "$NO_RESTART" != "true" ]]; then
  systemctl daemon-reload || true
  systemctl enable "${SERVICE}" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE}" || true
fi

echo "Configured ${SERVICE}. Images list installed."
