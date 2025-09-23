#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_SH="${SCRIPT_DIR}/rke2-ubuntu-node.sh"
[ -x "$NODE_SH" ] || { echo "Cannot find rke2-ubuntu-node.sh"; exit 1; }
# Role
if command -v fzf >/dev/null 2>&1; then
  ROLE=$(printf "server\nagent\n" | fzf --prompt="Role> " --height=10 --reverse) || exit 1
else
  read -rp "Role (server/agent): " ROLE
fi
[[ "$ROLE" == "server" || "$ROLE" == "agent" ]] || { echo "Invalid role"; exit 1; }
# Hostname
read -rp "Hostname: " HOSTNAME
[[ -n "$HOSTNAME" ]] || { echo "Hostname required"; exit 1; }
# Interface
if command -v fzf >/dev/null 2>&1; then
  IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | fzf --prompt="Interface> " --height=10 --reverse) || exit 1
else
  read -rp "Primary interface (e.g., eno1): " IFACE
fi
[[ -n "$IFACE" ]] || { echo "Interface required"; exit 1; }
# IP/GW/DNS
read -rp "IPv4/CIDR (e.g., 10.0.4.101/24): " IP_CIDR
read -rp "Gateway (e.g., 10.0.4.1): " GW
read -rp "DNS (comma-separated, e.g., 10.0.0.10,1.1.1.1): " DNS
sudo "$NODE_SH" --role "$ROLE" --hostname "$HOSTNAME" --iface "$IFACE" --ip-cidr "$IP_CIDR" --gw "$GW" --dns "$DNS"
