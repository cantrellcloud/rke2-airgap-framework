
#!/usr/bin/env bash
set -euo pipefail

# Inputs
RKE2_VERSION="${RKE2_VERSION:-v1.33.4+rke2r1}"
ARCH="linux-amd64"
WORKDIR="${WORKDIR:-$PWD/../rke2-mirror}"
CACHE_DIR="$WORKDIR/cache"
LIST_DIR="$WORKDIR/lists"

mkdir -p "$CACHE_DIR" "$LIST_DIR"
cd "$(dirname "$0")"

need(){ command -v "$1" >/dev/null || { echo "ERROR: missing $1"; exit 1; }; }
need curl; need skopeo

RKE2_SAFE="${RKE2_VERSION//+/%2B}"
RKE2_LIST="$LIST_DIR/rke2-images.$ARCH.txt"
curl -fsSLo "$RKE2_LIST" \
  "https://github.com/rancher/rke2/releases/download/${RKE2_SAFE}/rke2-images.${ARCH}.txt"

EXTRAS_LIST="$LIST_DIR/extras-images.txt"
cat > "$EXTRAS_LIST" <<'EOF'
quay.io/metallb/controller:v0.15.2
quay.io/metallb/speaker:v0.15.2
ghcr.io/projectcontour/contour:v1.33.0
docker.io/envoyproxy/envoy:v1.34.1
EOF

ALL_LIST="$LIST_DIR/images.all.txt"
awk 'NF' "$RKE2_LIST" "$EXTRAS_LIST" | sort -u > "$ALL_LIST"
echo "Image count: $(wc -l < "$ALL_LIST")"

sanitize(){ local r="$1"; r="${r//\//_}"; r="${r//:/__}"; echo "${r}.oci.tar.gz"; }

while read -r IMG; do
  [ -z "$IMG" ] && continue
  OUT="$CACHE_DIR/$(sanitize "$IMG")"
  if [ -f "$OUT" ]; then echo "[SKIP] cached: $IMG"; continue; fi
  echo "[PULL] $IMG"
  skopeo copy --all --retry-times 3 \
    "docker://${IMG}" "oci-archive:${OUT}:${IMG##*:}"
done < "$ALL_LIST"

echo "Done. Lists in $LIST_DIR ; archives in $CACHE_DIR"
