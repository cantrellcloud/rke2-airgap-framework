#!/usr/bin/env bash
set -euo pipefail

# ======= Inputs (edit as needed) =======
DEST_REG="${DEST_REG:-kuberegistry.dev.kube/rke2}"
WORKDIR="${WORKDIR:-$PWD/rke2-mirror}"
CACHE_DIR="$WORKDIR/cache"
LIST_DIR="$WORKDIR/lists"
ALL_LIST="${ALL_LIST:-$LIST_DIR/images.all.txt}"

need() { command -v "$1" >/dev/null || { echo "ERROR: missing $1"; exit 1; }; }
need skopeo

[ -d "$CACHE_DIR" ] || { echo "ERROR: no cache dir: $CACHE_DIR"; exit 1; }
[ -f "$ALL_LIST" ]  || { echo "ERROR: image list not found: $ALL_LIST"; exit 1; }

sanitize() {
  local ref="$1"
  ref="${ref//\//_}"
  ref="${ref//:/__}"
  echo "${ref}.oci.tar.gz"
}

# Rewrite "docker.io/library/busybox:1.36" -> "kuberegistry.dev.kube/rke2/docker.io/library/busybox:1.36"
rewrite_dest() {
  local src="$1"
  echo "${DEST_REG}/${src}"
}

while read -r IMG; do
  [ -z "$IMG" ] && continue
  ARCHIVE="$CACHE_DIR/$(sanitize "$IMG")"
  [ -f "$ARCHIVE" ] || { echo "WARN: archive missing for $IMG, skipping"; continue; }

  DEST_REF="$(rewrite_dest "$IMG")"
  echo "[PUSH] $IMG  ->  $DEST_REF"

  # Tell skopeo which tag to use when reading from the OCI archive
  TAG="${IMG##*:}"

  skopeo copy --all --retry-times 3 \
    "oci-archive:${ARCHIVE}:${TAG}" "docker://${DEST_REF}"
done < "$ALL_LIST"

echo "Done. Everything should now be in: ${DEST_REG}/…"
