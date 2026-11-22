#!/bin/sh

set -u
SELF=$(cd "$(dirname "$0")" && pwd)
CONTAINER=${PMX_CONTAINER:-$(node "$SELF/runtime_paths.mjs" value r_container)}
[ -n "$CONTAINER" ] || exit 2
BASE=$(node "$SELF/runtime_paths.mjs" queue) || exit 2
discover_init() {
  # Explicit roots win. Otherwise read the actual bind mount before known aliases.
  for d in "${PMX_HOST_R_ROOT:-}" "${RSUB_BASE:-}"; do
    [ -n "$d" ] && [ -f "$d/scripts/cont-init-install-pkgs.sh" ] && { echo "$d/scripts/cont-init-install-pkgs.sh"; return; }
  done
  f=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/cont-init.d/99-install-r-packages"}}{{.Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null) || f=""
  [ -n "$f" ] && [ -f "$f" ] && { echo "$f"; return; }
  return 1
}
INIT=$(discover_init)
INIT=${INIT:-$BASE/scripts/cont-init-install-pkgs.sh}
PKGS="libwebpmux3 libwebpdemux2"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

probe() {
  # The load error names the ABSENT library as `<something>.so.*: cannot open shared object file`.
  # Only that wording is actionable; a package that is merely missing from the library has a different text.
  docker exec "$CONTAINER" Rscript --vanilla -e \
    'm <- tryCatch({suppressPackageStartupMessages(library(ragg)); "OK"}, error=function(e) conditionMessage(e)); cat("RAGG_PROBE ", m, "\n", sep="")' 2>&1
}

# Distinguish "no docker CLI here" from "the container is down". The first case used to print the
# second's message ("container ... is not running"), which sent the reader to restart a container that
# was running fine -- this script only works from a shell that can talk to the docker daemon.
command -v docker >/dev/null 2>&1 || {
  echo "WORD_IMAGE_NEEDS_DOCKER docker CLI not on PATH in this shell; run this script on the Docker host (it is a host-side fix, not a job)"
  echo "WORD_IMAGE_NOTE install the required libraries in the worker image or provide the deployment fallback libraries explicitly"
  exit 3; }
docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q '^true$' || {
  echo "WORD_IMAGE_FAIL container $CONTAINER is not running (start it, then re-run)"; exit 1; }

OUT=$(probe)
case "$OUT" in
  *"RAGG_PROBE OK"*)
    # Already usable. Still make sure the init list cannot re-break it later.
    if [ "$CHECK" = 1 ]; then echo "WORD_IMAGE_OK $CONTAINER (ragg loads; run without --check to verify the cont-init list)"; exit 0; fi
    ;;
  *) : ;;
esac

if [ "$CHECK" = 1 ]; then
  echo "WORD_IMAGE_FIXED NEEDED: ragg does not load in $CONTAINER"
  printf '%s\n' "$OUT" | tail -3
  echo "  fix: sh $SELF/word_image_fix.sh"
  exit 1
fi

# --- 1. durable fix: the image's own self-heal list must carry the packages ----------------------
if [ -f "$INIT" ]; then
  echo "WORD_IMAGE_INIT found=$INIT"
  if grep -q 'libwebpmux3' "$INIT"; then
    echo "WORD_IMAGE_INIT already lists $PKGS"
  else
    cp -p "$INIT" "$INIT.orig_$(date -u +%Y%m%d%H%M%S)" 2>/dev/null || true
    # Insert into the SYSPKGS="..." assignment, not a new line: the loop reads that one variable.
    if grep -q '^SYSPKGS=' "$INIT"; then
      sed -i "s/^SYSPKGS=\"\(.*\)\"/SYSPKGS=\"\1 $PKGS\"/" "$INIT" \
        && echo "WORD_IMAGE_INIT added '$PKGS' to SYSPKGS in $INIT"
    else
      echo "WORD_IMAGE_INIT WARNING: no SYSPKGS= line in $INIT; add '$PKGS' by hand"
    fi
  fi
else
  echo "WORD_IMAGE_INIT WARNING: cont-init script not found; the durable (cont-init) fix was skipped"
  echo "WORD_IMAGE_INIT TRIED \$PMX_HOST_R_ROOT \$RSUB_BASE + actual container bind mount"
  printf '%s\n' "WORD_IMAGE_INIT HINT read the real host path off the container's mount source:" \
    "  docker inspect -f '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{\"\\n\"}}{{end}}' $CONTAINER | grep cont-init"
  echo "WORD_IMAGE_INIT HINT then re-run with PMX_HOST_R_ROOT=<dir holding scripts/> sh $SELF/word_image_fix.sh"
fi

# --- 2. install into the running container -------------------------------------------------------
if docker exec "$CONTAINER" sh -c "dpkg -s libwebpmux3 >/dev/null 2>&1"; then
  echo "WORD_IMAGE_PKG libwebpmux3 already installed in the running container"
else
  echo "WORD_IMAGE_INSTALL apt-get install -y --no-install-recommends $PKGS"
  docker exec "$CONTAINER" sh -c \
    "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y --no-install-recommends $PKGS" 2>&1 | tail -5
fi

# Optional host-supplied fallback library
LIB_SRC="$SELF/../../word-report/lib/libwebpmux.so.3"
MULTIARCH=$(docker exec "$CONTAINER" dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null) || MULTIARCH=""
LIB_DEST=${PMX_CONTAINER_LIB_DIR:-${MULTIARCH:+/usr/lib/$MULTIARCH}}
if [ -f "$LIB_SRC" ] && [ -n "$LIB_DEST" ]; then
  if docker exec "$CONTAINER" test -e "$LIB_DEST/libwebpmux.so.3" 2>/dev/null; then
    echo "WORD_IMAGE_LIB libwebpmux.so.3 already resolvable in $CONTAINER"
  elif docker cp "$LIB_SRC" "$CONTAINER:$LIB_DEST/libwebpmux.so.3" 2>&1 | tail -2 &&
       docker exec "$CONTAINER" sh -c 'chmod 644 "$1" && ldconfig' sh "$LIB_DEST/libwebpmux.so.3" 2>&1 | tail -2; then
    echo "WORD_IMAGE_LIB staged $LIB_SRC into $CONTAINER (offline fix from word-report/lib)"
  else
    echo "WORD_IMAGE_LIB WARNING: could not copy $LIB_SRC into $CONTAINER; the apt fix above must carry it"
  fi
else
  echo "WORD_IMAGE_LIB WARNING: $LIB_SRC or the container library directory is unavailable; use the worker image dependency setup"
fi

OUT=$(probe)
case "$OUT" in
  *"RAGG_PROBE OK"*)
    echo "WORD_IMAGE_FIXED $CONTAINER can load ragg (and therefore officer/flextable); Word jobs will build"
    echo "WORD_IMAGE_CHECK re-verify with: sh $SELF/preflight_word.sh --sync <analysis-dir>"
    exit 0;;
  *)
    printf '%s\n' "$OUT" | tail -5
    echo "WORD_IMAGE_FAIL ragg still does not load; the container may need root or the R library itself rebuilt"
    exit 1;;
esac
