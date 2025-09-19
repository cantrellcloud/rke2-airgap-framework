#!/usr/bin/env bash
set -euo pipefail

# ======= Inputs (edit as needed) =======
RKE2_VERSION="${RKE2_VERSION:-v1.33.4+rke2r1}"
ARCH="linux-amd64"            # you asked for amd64 only
WORKDIR="${WORKDIR:-$PWD/rke2-mirror}"
CACHE_DIR="$WORKDIR/cache"    # where OCI archives are stored
LIST_DIR="$WORKDIR/lists"

mkdir -p "$CACHE_DIR" "$LIST_DIR"
cd "$WORKDIR"

# ======= Tools sanity =======
need() { command -v "$1" >/dev/null || { echo "ERROR: missing $1"; exit 1; }; }
need curl
need skopeo

# ======= Get official RKE2 image list for this version/arch =======
RKE2_SAFE="${RKE2_VERSION//+/%2B}"  # URL-escape '+'
RKE2_LIST="$LIST_DIR/rke2-images.$ARCH.txt"
curl -fsSLo "$RKE2_LIST" \
  "https://github.com/rancher/rke2/releases/download/${RKE2_SAFE}/rke2-images.${ARCH}.txt"

# ======= Add MetalLB + Contour pins =======
EXTRAS_LIST="$LIST_DIR/extras-images.txt"
cat > "$EXTRAS_LIST" <<'EOF'
quay.io/metallb/controller:v0.15.2
quay.io/metallb/speaker:v0.15.2
ghcr.io/projectcontour/contour:v1.33.0
docker.io/envoyproxy/envoy:v1.34.1
EOF

# ======= Merge & de-dup =======
ALL_LIST="$LIST_DIR/images.all.txt"
awk 'NF' "$RKE2_LIST" "$EXTRAS_LIST" | sort -u > "$ALL_LIST"
echo "Image count: $(wc -l < "$ALL_LIST")"
echo "Lists under: $LIST_DIR"
echo "Cache under: $CACHE_DIR"

# ======= Helper: sanitize an image ref into a filename =======
#  e.g. "docker.io/library/busybox:1.36" -> "docker.io_library_busybox__1.36.oci.tar.gz"
sanitize() {
  local ref="$1"
  ref="${ref//\//_}"      # slashes -> _
  ref="${ref//:/__}"      # colon before tag -> __
  echo "${ref}.oci.tar.gz"
}

# ======= Pull each image to a local OCI archive (compressed) =======
# We use per-image OCI archives so they’re easy to copy/scan.
while read -r IMG; do
  [ -z "$IMG" ] && continue
  OUT="$CACHE_DIR/$(sanitize "$IMG")"
  if [ -f "$OUT" ]; then
    echo "[SKIP] already cached: $IMG"
    continue
  fi
  echo "[PULL] $IMG"
  # copy all platforms embedded in the manifest (even if we’ll run amd64),
  # keeps the archive usable elsewhere too.
  skopeo copy --all --retry-times 3 \
    "docker://${IMG}" "oci-archive:${OUT}:${IMG##*:}"
done < "$ALL_LIST"

echo "Done. Archives in: $CACHE_DIR"
echo "Keep BOTH $ALL_LIST and $CACHE_DIR for the push step."

