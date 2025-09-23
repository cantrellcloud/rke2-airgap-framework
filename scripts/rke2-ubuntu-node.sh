#!/usr/bin/env bash
# rke2-ubuntu-node.sh
set -Eeuo pipefail
set -o pipefail 2>/dev/null || true

LOG_FILE="${LOG_FILE:-/var/log/rke2-ubuntu-node.log}"
mkdir -p /var/log; touch "$LOG_FILE"
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S] "), $0; fflush() }' | tee -a "$LOG_FILE") 2>&1
trap 'rc=$?; echo "[TRAP] Exit code=$rc at line $LINENO"; exit $rc' EXIT

say(){ echo -e "\n== $* ==\n"; }

# Defaults
ALLOW_LEAF_CA="${ALLOW_LEAF_CA:-false}"
CA_SRC="${CA_SRC:-}"
DNS_CSV="${DNS_CSV:-}"
GATEWAY="${GATEWAY:-}"
HOSTNAME="${HOSTNAME:-}"
IFACE="${IFACE:-}"
IMAGES_LIST="${IMAGES_LIST:-}"
INSTALL_CACHE="/opt/rke2/get.rke2.sh"
INSTALL_URL="${INSTALL_URL:-https://get.rke2.io}"
IPV4_CIDR="${IPV4_CIDR:-}"
REG_PASSWORD="${REG_PASSWORD:-ZAQwsx!@#123}"
REGISTRY_ROOT="${REGISTRY_ROOT:-kuberegistry.dev.kube/rke2}"
REG_USERNAME="${REG_USERNAME:-admin}"
RKE2_VERSION="${RKE2_VERSION:-v1.33.4+rke2r1}"
ROLE="${ROLE:-}"
SERVER_URL="${SERVER_URL:-}"
TOKEN="${TOKEN:-}"
TOKEN_FILE="${TOKEN_FILE:-}"
SKIP_VERIFY="${SKIP_VERIFY:-false}"
TEMPLATE="${TEMPLATE:-false}"

OFFLINE_STAGE1_MARKER="/var/local/rke2_offline_stage1_done"
OFFLINE_STAGE2_MARKER="/var/local/rke2_offline_stage2_done"

# Args (alphabetical)
while (( "$#" )); do
  case "$1" in
    --allow-leaf-ca) ALLOW_LEAF_CA="true"; shift ;;
    --ca)            CA_SRC="${2:?}"; shift 2 ;;
    --dns)           DNS_CSV="${2:?}"; shift 2 ;;
    --gw)            GATEWAY="${2:?}"; shift 2 ;;
    --hostname)      HOSTNAME="${2:?}"; shift 2 ;;
    --iface)         IFACE="${2:?}"; shift 2 ;;
    --images)        IMAGES_LIST="${2:?}"; shift 2 ;;
    --install-url)   INSTALL_URL="${2:?}"; shift 2 ;;
    --ip-cidr)       IPV4_CIDR="${2:?}"; shift 2 ;;
    --pass)          REG_PASSWORD="${2:?}"; shift 2 ;;
    --registry)      REGISTRY_ROOT="${2:?}"; shift 2 ;;
    --role)          ROLE="${2:?}"; shift 2 ;;
    --server-url)    SERVER_URL="${2:?}"; shift 2 ;;
    --skip-verify)   SKIP_VERIFY="true"; shift ;;
    --template)      TEMPLATE="true"; shift ;;
    --token)         TOKEN="${2:?}"; shift 2 ;;
    --token-file)    TOKEN_FILE="${2:?}"; shift 2 ;;
    --user)          REG_USERNAME="${2:?}"; shift 2 ;;
    --version)       RKE2_VERSION="${2:?}"; shift 2 ;;
    -h|--help) sed -n '1,240p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Please run as root (sudo)."; exit 1; }
echo "SCRIPT: $0"; echo "ARGS: $*"; echo "DATE: $(date -Is)"; echo "KERNEL: $(uname -r)"

need_pkg(){ dpkg -s "$1" >/dev/null 2>&1 || apt-get install -y --no-install-recommends "$1"; }

prep_base(){
  say "Apt update & base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  for p in ca-certificates curl gnupg lsb-release software-properties-common iptables ipset ethtool conntrack socat ebtables nftables nfs-common open-iscsi multipath-tools chrony apparmor apparmor-utils auditd jq unzip tar dnsutils; do need_pkg "$p"; done
  systemctl enable chrony >/dev/null 2>&1 || true; systemctl restart chrony || true
  systemctl enable iscsid multipathd >/dev/null 2>&1 || true; systemctl restart iscsid multipathd || true

  say "Kernel modules"
  cat >/etc/modules-load.d/rke2.conf <<'EOF'
overlay
br_netfilter
EOF
  modprobe overlay || true; modprobe br_netfilter || true; modprobe nf_nat || true; modprobe xt_conntrack || true; modprobe ip_tables || true

  say "Sysctl"
  cat >/etc/sysctl.d/99-rke2.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
  sysctl --system

  say "Disable swap"
  swapoff -a || true
  sed -i.bak '/\sswap\s/s/^/#/g' /etc/fstab || true
}

detect_iface(){
  for dev in /sys/class/net/*; do
    n="$(basename "$dev")"; [[ "$n" == "lo" ]] && continue
    [[ -f "$dev/carrier" && "$(cat "$dev/carrier")" == "1" ]] && { echo "$n"; return; }
  done
  ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1
}

write_netplan(){
  local iface="$1" ip_cidr="$2" gw="$3" dns_csv="$4"
  say "Writing netplan for ${iface}"
  cat >/etc/netplan/01-rke2-static.yaml <<EOF
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses: [${ip_cidr}]
      routes:
        - to: 0.0.0.0/0
          via: ${gw}
      nameservers:
        addresses: [${dns_csv}]
EOF
  netplan generate && netplan apply
}

install_rke2_offline(){
  local role="$1"
  say "Installing RKE2 (${role}) via cached installer"
  [[ -x "$INSTALL_CACHE" ]] || { echo "Cached installer not found: $INSTALL_CACHE"; exit 1; }
  INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh "$INSTALL_CACHE" "${role}"
}

verify_node(){
  echo "== VERIFY =="
  local REG_HOST; REG_HOST="$(echo "$REGISTRY_ROOT" | cut -d/ -f1)"
  local CA_DEST="/etc/rancher/rke2/kuberegistry-ca.crt"; local CA_ARG=""
  [[ -f "$CA_DEST" ]] && CA_ARG="--cacert $CA_DEST"
  curl -u "${REG_USERNAME}:${REG_PASSWORD}" -fsSIL --max-time 6 --connect-timeout 3 $CA_ARG "https://${REG_HOST}/v2/" >/dev/null \
    && echo "✔ Registry /v2/ reachable with auth" || { echo "✖ Registry /v2/ probe failed"; return 1; }
  lsmod | grep -q br_netfilter && echo "✔ br_netfilter loaded" || { echo "✖ br_netfilter not loaded"; return 1; }
  lsmod | grep -q overlay && echo "✔ overlay loaded" || { echo "✖ overlay not loaded"; return 1; }
  [[ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" = "1" ]] && echo "✔ net.ipv4.ip_forward=1" || { echo "✖ ip_forward not 1"; return 1; }
  [[ "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 0)" = "1" ]] && echo "✔ bridge-nf-call-iptables=1" || { echo "✖ bridge-nf-call-iptables not 1"; return 1; }
  [[ "$(swapon --show | wc -l)" = "0" ]] && echo "✔ swap disabled" || { echo "✖ swap devices active"; return 1; }
  systemctl is-active --quiet rke2-server && echo "✔ rke2-server active" || true
  systemctl is-active --quiet rke2-agent  && echo "✔ rke2-agent  active" || true
  echo "== VERIFY COMPLETE =="
}

# TEMPLATE mode (online)
if [[ "$TEMPLATE" == "true" ]]; then
  say "Template mode"
  hostnamectl set-hostname rke2image
  prep_base
  mkdir -p /opt/rke2
  curl -fsSLo "$INSTALL_CACHE" "$INSTALL_URL"
  chmod +x "$INSTALL_CACHE"
  echo "Template ready."
  exit 0
fi

# OFFLINE Stage 1
if [[ ! -f "$OFFLINE_STAGE1_MARKER" ]]; then
  say "Offline Stage 1"
  [[ -n "$ROLE" ]] || read -rp "Role (server/agent): " ROLE
  [[ "$ROLE" == "server" || "$ROLE" == "agent" ]] || { echo "Invalid role"; exit 1; }
  [[ -n "$HOSTNAME" ]] || read -rp "Hostname: " HOSTNAME
  hostnamectl set-hostname "$HOSTNAME"
  [[ -n "$IFACE" ]] || IFACE="$(detect_iface)"
  [[ -n "$IPV4_CIDR" ]] || read -rp "IPv4/CIDR: " IPV4_CIDR
  [[ -n "$GATEWAY"   ]] || read -rp "Gateway: " GATEWAY
  [[ -n "$DNS_CSV"   ]] || read -rp "DNS (comma-separated): " DNS_CSV
  write_netplan "$IFACE" "$IPV4_CIDR" "$GATEWAY" "$DNS_CSV"
  prep_base
  mkdir -p /var/local; echo "$ROLE" > "$OFFLINE_STAGE1_MARKER"
  echo "Rebooting..."
  reboot; exit 0
fi

# OFFLINE Stage 2
if [[ ! -f "$OFFLINE_STAGE2_MARKER" ]]; then
  say "Offline Stage 2"
  ROLE="$(cat "$OFFLINE_STAGE1_MARKER")"
  RKE2_DIR="/etc/rancher/rke2"; IMAGES_DIR="/var/lib/rancher/rke2/agent/images"; CA_DEST="${RKE2_DIR}/kuberegistry-ca.crt"
  mkdir -p "$RKE2_DIR" "$IMAGES_DIR"
  # CA bundle
  if [[ -n "$CA_SRC" ]]; then
    [[ -f "$CA_SRC" ]] || { echo "CA file not found: $CA_SRC"; exit 1; }
    if [[ "$ALLOW_LEAF_CA" != "true" ]]; then
      if ! openssl x509 -in "$CA_SRC" -noout -text 2>/dev/null | grep -q "CA:TRUE"; then
        echo "ERROR: --ca must contain a CA certificate (CA:TRUE). Use --allow-leaf-ca to bypass."; exit 1
      fi
    fi
    install -m 0644 "$CA_SRC" "$CA_DEST"
    update-ca-certificates || true
  fi
  # registries.yaml
  REG_HOST="$(echo "$REGISTRY_ROOT" | cut -d/ -f1)"
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
  # config.yaml (+join info)
  cat > "${RKE2_DIR}/config.yaml" <<EOF
system-default-registry: "${REGISTRY_ROOT}"
EOF
  if [[ "$ROLE" == "agent" ]]; then
    [[ -n "$SERVER_URL" ]] || { echo "--server-url required for agent"; exit 1; }
    [[ -n "$TOKEN" || -n "$TOKEN_FILE" ]] || { echo "--token or --token-file required for agent"; exit 1; }
    if [[ -z "$TOKEN" && -n "$TOKEN_FILE" ]]; then TOKEN="$(sed -n '1p' "$TOKEN_FILE" | tr -d '\n\r')"; fi
    {
      echo "server: \"${SERVER_URL}\""
      echo "token: \"${TOKEN}\""
    } >> "${RKE2_DIR}/config.yaml"
  else
    if [[ -n "$TOKEN" || -n "$TOKEN_FILE" ]]; then
      if [[ -z "$TOKEN" && -n "$TOKEN_FILE" ]]; then TOKEN="$(sed -n '1p' "$TOKEN_FILE" | tr -d '\n\r')"; fi
      echo "token: \"${TOKEN}\"" >> "${RKE2_DIR}/config.yaml"
    fi
  fi
  # pre-warm list
  if [[ -n "$IMAGES_LIST" ]]; then
    [[ -f "$IMAGES_LIST" ]] || { echo "Images list not found: $IMAGES_LIST"; exit 1; }
    install -m 0644 "$IMAGES_LIST" "${IMAGES_DIR}/01-images.txt"
  fi
  # probe registry
  CURL_CA=(); [[ -f "$CA_DEST" ]] && CURL_CA=(--cacert "$CA_DEST")
  curl -u "${REG_USERNAME}:${REG_PASSWORD}" -fsSIL --max-time 6 --connect-timeout 3 "${CURL_CA[@]}" "https://${REG_HOST}/v2/" >/dev/null || { echo "Registry probe failed"; exit 1; }
  # install RKE2
  install_rke2_offline "$ROLE"
  systemctl daemon-reload || true
  systemctl enable "rke2-${ROLE}" >/dev/null 2>&1 || true
  systemctl restart "rke2-${ROLE}" || true
  [[ "$SKIP_VERIFY" == "true" ]] || verify_node
  touch "$OFFLINE_STAGE2_MARKER"
  say "Stage 2 complete."
  exit 0
fi

say "Nothing to do (both stages complete)."
