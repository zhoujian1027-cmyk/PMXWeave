#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
WS=$(cd "$SELF/../.." && pwd)
. "$SELF/queue_budget.sh"

DIR=${1:-}
[ -n "$DIR" ] || { echo "MIRROR_FAIL usage: mirror_toolkit.sh <analysis-dir>"; exit 0; }
DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "MIRROR_FAIL no such directory $1"; exit 0; }
HDIR=$(sh "$SELF/rpath.sh" container "$DIR") || { echo "MIRROR_FAIL study path is outside configured R mounts" >&2; exit 2; }

MIRROR="$DIR/.pmx/pmx_workspace"
HMIRROR="$HDIR/.pmx/pmx_workspace"

# Stage the report runtime, not the model-authoring catalogs.
TREES="references word-report analyses_template"

# Invalidate the mirror when its selected sources change.
STAMP=$( {
  for t in $TREES; do [ -d "$WS/$t" ] && find "$WS/$t" -type f -not -path "*/_previous_sources/*"; done
} 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do cksum "$f" 2>/dev/null; done | cksum | tr -d ' ')
[ -n "$STAMP" ] || { echo "MIRROR_FAIL cannot stamp $WS"; exit 0; }

mkdir -p "$MIRROR" 2>/dev/null || { echo "MIRROR_FAIL cannot create $MIRROR"; exit 0; }
if [ -f "$MIRROR/.mirror_stamp" ] && [ "$(cat "$MIRROR/.mirror_stamp" 2>/dev/null)" = "$STAMP" ] \
   && [ -f "$MIRROR/analyses_template/tools/model_contract.R" ] && [ -d "$MIRROR/word-report/stages" ]; then
  echo "MIRROR_OK $HMIRROR"
  echo "MIRROR_TOOLKIT $HMIRROR"
  exit 0
fi

# Remove first, copy second, stamp third: a plain "cp -a" never removes a subtree deleted from the
# source and never replaces a mirror whose own path matched the source, so the container could keep
# running a stale - or partial - toolkit after the canonical one was fixed.
rm -rf "$MIRROR" 2>/dev/null
mkdir -p "$MIRROR" || { echo "MIRROR_FAIL cannot stage at $MIRROR"; exit 0; }
for t in $TREES; do
  [ -d "$WS/$t" ] || continue
  mkdir -p "$MIRROR/$t" || { echo "MIRROR_FAIL cannot stage $MIRROR/$t"; exit 0; }
  cp -a "$WS/$t/." "$MIRROR/$t/" || { echo "MIRROR_FAIL cannot copy $WS/$t"; exit 0; }
done
[ -f "$MIRROR/analyses_template/tools/model_contract.R" ] || { echo "MIRROR_FAIL staged mirror lacks analyses_template/tools/model_contract.R ($MIRROR)"; exit 0; }
[ -d "$MIRROR/word-report/stages" ] || { echo "MIRROR_FAIL staged mirror lacks word-report/stages ($MIRROR)"; exit 0; }
printf '%s\n' "$STAMP" > "$MIRROR/.mirror_stamp" 2>/dev/null
chmod -R a+rX "$MIRROR" 2>/dev/null || true
echo "MIRROR_SYNC $HMIRROR"
echo "MIRROR_TOOLKIT $HMIRROR"
exit 0
