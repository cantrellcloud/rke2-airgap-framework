
#!/usr/bin/env bash
# rke2-ubuntu-node-init.sh
# All-in-one: Ubuntu 24.04 prep + private registry + prewarm + RKE2 install + guards
set -euo pipefail

REGISTRY_ROOT="kuberegistry.dev.kube/rke2"
REG_USERNAME="admin"
REG_PASSWORD="ZAQwsx!@#123"
IMAGES_LIST=""
CA_SRC=""
ROLE="server"
RKE2_VERSION="v1.33.4+rke2r1"
INSTALL_URL="https://get.rke2.io"
OFFLINE_INSTALLER="false"
NO_REGISTRY_CHECK="false"
NO_PREWARM="false"
NO_RESTART="false"
NO_REBOOT="false"

while (( "$#" )); do
  case "$1" in
    --registry)    REGISTRY_ROOT="${2:?}"; shift 2 ;;
    --user)        REG_USERNAME="${2:?}"; shift 2 ;;
    --pass)        REG_PASSWORD="${2:?}"; shift 2 ;;
    --images)      IMAGES_LIST="${2:?}"; shift 2 ;;
    --ca)          CA_SRC="${2:?}"; shift 2 ;;
    --role)        ROLE="${2:?}"; shift 2 ;;
    --version)     RKE2_VERSION="${2:?}"; shift 2 ;;
    --install-url) INSTALL_URL="${2:?}"; shift 2 ;;
    --offline-installer) OFFLINE_INSTALLER="true"; shift ;;
    --no-registry-check) NO_REGISTRY_CHECK="true"; shift ;;
    --no-prewarm)  NO_PREWARM="true"; shift ;;
    --no-restart)  NO_RESTART="true"; shift ;;
    --no-reboot)   NO_REBOOT="true"; shift ;;
    -h|--help) sed -n '1,200p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo)."; exit 1; }
say(){ echo -e "\n== $* ==\n"; }
command -v curl >/dev/null || { apt-get update -y; apt-get install -y curl; }

say "Apt update & base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates gnupg lsb-release software-properties-common \
  iptables ipset ethtool conntrack socat ebtables nftables \
  nfs-common open-iscsi multipath-tools \
  chrony apparmor apparmor-utils auditd \
  jq unzip tar dnsutils

systemctl enable chrony >/dev/null 2>&1 || true
systemctl restart chrony || true
systemctl enable iscsid multipathd >/dev/null 2>&1 || true
systemctl restart iscsid multipathd || true

say "Kernel modules"
cat >/etc/modules-load.d/rke2.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true
modprobe nf_nat || true
modprobe xt_conntrack || true
modprobe ip_tables || true

say "Sysctl"
cat >/etc/sysctl.d/99-rke2.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_announce = 2
EOF
sysctl --system

say "Disable swap"
swapoff -a || true
cp /etc/fstab /etc/fstab.bak.$(date +%s) || true
sed -i.bak '/\sswap\s/s/^/#/g' /etc/fstab || true

say "Private registry config"
RKE2_DIR="/etc/rancher/rke2"
IMAGES_DIR="/var/lib/rancher/rke2/agent/images"
CA_DEST="${RKE2_DIR}/kuberegistry-ca.crt"
mkdir -p "$RKE2_DIR" "$IMAGES_DIR"

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

say "Pre-warm images"
if [[ "$NO_PREWARM" != "true" && -n "$IMAGES_LIST" ]]; then
  [[ -f "$IMAGES_LIST" ]] || { echo "Images list not found: $IMAGES_LIST"; exit 1; }
  install -m 0644 "$IMAGES_LIST" "${IMAGES_DIR}/01-images.txt"
  echo "Placed ${IMAGES_DIR}/01-images.txt  ($(wc -l < "$IMAGES_LIST") images)"
else
  echo "Skipping pre-warm (no list or --no-prewarm)"
fi

say "Registry reachability check"
if [[ "${NO_REGISTRY_CHECK:-false}" != "true" ]]; then
  if ! getent ahostsv4 "$REG_HOST" >/dev/null 2>&1 && ! getent ahosts "$REG_HOST" >/dev/null 2>&1; then
    echo "ERROR: DNS resolution failed for ${REG_HOST}"; exit 1
  fi
  if ! timeout 3 bash -c "</dev/tcp/${REG_HOST}/443" 2>/dev/null; then
    echo "ERROR: Cannot reach ${REG_HOST}:443"; exit 1
  fi
  CURL_CA=(); [[ -f "$CA_DEST" ]] && CURL_CA=(--cacert "$CA_DEST")
  if ! curl -u "${REG_USERNAME}:${REG_PASSWORD}" -fsSIL --max-time 6 --connect-timeout 3 \
        "${CURL_CA[@]}" "https://${REG_HOST}/v2/" >/dev/null; then
    echo "ERROR: Authenticated HTTPS probe to https://${REG_HOST}/v2/ failed"; exit 1
  fi
  echo "Registry OK"
else
  echo "Skipping registry check (--no-registry-check)"
fi

say "Installer reachability"
if [[ "${OFFLINE_INSTALLER}" != "true" ]]; then
  INSTALL_HOST="$(echo "$INSTALL_URL" | awk -F/ '{print $3}')"
  if ! getent ahostsv4 "$INSTALL_HOST" >/dev/null 2>&1 && ! getent ahosts "$INSTALL_HOST" >/dev/null 2>&1; then
    echo "ERROR: DNS failed for ${INSTALL_HOST}"; exit 1
  fi
  if ! curl -fsSIL --max-time 6 --connect-timeout 3 "$INSTALL_URL" >/dev/null; then
    echo "ERROR: Cannot reach ${INSTALL_URL}"; exit 1
  fi
  echo "Installer URL OK"
else
  echo "Offline installer mode; skipping installer URL check"
fi

say "Install RKE2 (${ROLE})"
if command -v rke2 >/dev/null || command -v rke2-server >/dev/null || command -v rke2-agent >/dev/null; then
  echo "RKE2 appears installed; skipping"
else
  if [[ "${OFFLINE_INSTALLER}" == "true" ]]; then
    echo "Offline mode but no local script specified. Place get.rke2.sh locally and run:"
    echo "  INSTALL_RKE2_VERSION='${RKE2_VERSION}' sh ./get.rke2.sh ${ROLE}"
    exit 1
  fi
  curl -sfL "${INSTALL_URL}" | INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -s - "${ROLE}"
fi

SERVICE="rke2-${ROLE}"
if [[ "${NO_RESTART}" != "true" ]]; then
  systemctl daemon-reload || true
  systemctl enable "${SERVICE}" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE}" || true
fi

echo "Chrony: $(systemctl is-active chrony || true)"
echo "iscsid: $(systemctl is-active iscsid || true)"
echo "multipathd: $(systemctl is-active multipathd || true)"
echo "br_netfilter: $(lsmod | grep -q br_netfilter && echo yes || echo no)"
echo "overlay: $(lsmod | grep -q overlay && echo yes || echo no)"
echo "ip_forward: $(sysctl -n net.ipv4.ip_forward)"
echo "swap devices: $(swapon --show | wc -l) (0 expected)"

apt-get autoremove -y || true
apt-get clean || true

if [[ "${NO_REBOOT}" == "true" ]]; then
  echo "Setup complete. Reboot recommended."
else
  read -rp "Reboot now? [y/N]: " REPLY
  [[ "${REPLY,,}" == "y" ]] && reboot || echo "Reboot when convenient."
fi
