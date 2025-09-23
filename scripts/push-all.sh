#!/usr/bin/env bash
set -euo pipefail
DEST_ROOT="${DEST_ROOT:-kuberegistry.dev.kube/rke2}"
WORKDIR="${WORKDIR:-$PWD/../rke2-mirror}"
CACHE_DIR="$WORKDIR/cache"; LIST_DIR="$WORKDIR/lists"
ALL_LIST="${ALL_LIST:-$LIST_DIR/images.all.txt}"
need(){ command -v "$1" >/dev/null || { echo "ERROR: missing $1"; exit 1; }; }
need skopeo
[ -d "$CACHE_DIR" ] || { echo "ERROR: no cache dir: $CACHE_DIR"; exit 1; }
[ -f "$ALL_LIST" ]  || { echo "ERROR: image list not found: $ALL_LIST"; exit 1; }
sanitize(){ local r="$1"; r="${r//\//_}"; r="${r//:/__}"; echo "${r}.oci.tar.gz"; }
rewrite_dest(){ echo "${DEST_ROOT}/$1"; }
while read -r IMG; do
  [ -z "$IMG" ] && continue
  ARCHIVE="$CACHE_DIR/$(sanitize "$IMG")"
  [ -f "$ARCHIVE" ] || { echo "WARN: missing archive for $IMG"; continue; }
  DEST_REF="$(rewrite_dest "$IMG")"
  TAG="${IMG##*:}"
  echo "[PUSH] $IMG -> $DEST_REF"
  skopeo copy --all --retry-times 3 "oci-archive:${ARCHIVE}:${TAG}" "docker://${DEST_REF}"
done < "$ALL_LIST"
echo "Done. Pushed under: ${DEST_ROOT}/…"
