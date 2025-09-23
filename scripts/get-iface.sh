export IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')" ; [ -z "$IFACE" ] && export IFACE="$(ip -o -6 route show to default 2>/dev/null | awk '{print $5; exit}')"
