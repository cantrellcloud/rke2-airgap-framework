#!/usr/bin/env bash
set -euo pipefail
export IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')
echo "The network interface is: ${IFACE}"
echo
