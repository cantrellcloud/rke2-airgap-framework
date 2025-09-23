#!/usr/bin/env bash
set -euo pipefail
NAME="rke2-airgap-framework"; VERSION="${1:-1.0.0}"; ARCH="${2:-all}"
WORKDIR="$(mktemp -d)"; trap 'rm -rf "$WORKDIR"' EXIT
ROOT="$WORKDIR/${NAME}_${VERSION}_${ARCH}"
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/rke2-airgap" "$ROOT/etc/bash_completion.d" "$ROOT/usr/local/bin"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: ${NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: bash
Maintainer: rke2-airgap
Description: RKE2 air-gap framework scripts and docs
EOF
cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ -f /opt/rke2-airgap/completion/rke2-ubuntu-node.sh ]; then
  install -m 0644 /opt/rke2-airgap/completion/rke2-ubuntu-node.sh /etc/bash_completion.d/rke2-ubuntu-node.sh || true
fi
exit 0
EOF
chmod 0755 "$ROOT/DEBIAN/postinst"
cp -a . "$ROOT/opt/rke2-airgap"
ln -s /opt/rke2-airgap/scripts/rke2-ubuntu-node.sh "$ROOT/usr/local/bin/rke2-ubuntu-node" || true
ln -s /opt/rke2-airgap/scripts/stage1-tui.sh       "$ROOT/usr/local/bin/rke2-stage1-tui" || true
ln -s /opt/rke2-airgap/scripts/pull-all.sh         "$ROOT/usr/local/bin/rke2-mirror-pull" || true
ln -s /opt/rke2-airgap/scripts/push-all.sh         "$ROOT/usr/local/bin/rke2-mirror-push" || true
dpkg-deb --build "$ROOT"
mv "$ROOT.deb" "./${NAME}_${VERSION}_${ARCH}.deb"
echo "Created ./${NAME}_${VERSION}_${ARCH}.deb"
