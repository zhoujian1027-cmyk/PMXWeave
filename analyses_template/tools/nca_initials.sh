#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
MODE=${PMX_SUBMIT_MODE:-submit}
FULL=0
JID=""; DATA=""; NCA_FLAGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sync)      MODE=sync ;;
    --async)     MODE=submit ;;
    --full)      FULL=1 ;;
    --collect)   MODE=collect; JID="${2:-}"; [ -z "$JID" ] || shift ;;
    --collect=*) MODE=collect; JID="${1#--collect=}" ;;
    *) if [ -z "$DATA" ]; then DATA="$1"; else NCA_FLAGS="$NCA_FLAGS $1"; fi ;;
  esac
  shift
done

if [ "$MODE" = collect ]; then
  [ -n "$JID" ] || { echo "NCA_FAIL usage: nca_initials.sh --collect <job-id>" >&2; exit 2; }
  # A COLLECT wait is bounded (40 s, under the harness kill) so it always returns an answer: either
  # the digest, or "not ready" plus the id and the way to wait. --status is never polled here.
  RC=0; OUT=$(node "$SELF/r-submit.mjs" --attach "$JID" --max-wait-s="${PMX_COLLECT_MAX_S:-40}" 2>&1) || RC=$?
  if [ "$FULL" = 1 ]; then
    printf '%s\n' "$OUT"
  else
    # Brief: the numbers needed to write the $THETA block, nothing else (NCA is screening only).
    printf '%s\n' "$OUT" | grep -E 'INITIALS|^NCA_|^\$THETA|^ *\(' || true
  fi
  if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qE '^NCA_(OK|SPARSE)'; then
    echo "NCA_COLLECTED $JID - brief digest above; nca_initials.txt/csv sit beside the table= path"
    [ "$FULL" = 1 ] || echo "NCA_FULL_ONLY_IF_NEEDED add --full to reprint the whole block (rarely useful; never read nca_initials.csv for initials)"
  elif [ "$RC" = 3 ] && printf '%s\n' "$OUT" | grep -q '^RSUB_PENDING '; then
    echo "NCA_NOT_READY $JID - retain/create one BACKGROUND node $SELF/r-submit.mjs --attach $JID --follow --summary; yield WAITING and continue automatically on completion; never resubmit"
  else
    printf '%s\n' "$OUT" | tail -12 >&2
    echo "NCA_FAIL $JID - terminal failure or observer error; no new waiter or unchanged resubmission" >&2
    [ "$RC" = 0 ] && RC=1
    exit "$RC"
  fi
  exit 0
fi

[ -n "$DATA" ] || { echo "usage: nca_initials.sh <data.csv> [nca flags] [--sync|--async] | --collect <job-id>" >&2; exit 2; }
[ -f "$DATA" ] || { echo "NCA_FAIL missing input" >&2; exit 2; }
DIR=$(cd "$(dirname "$DATA")" && pwd); DATA="$DIR/$(basename "$DATA")"
case " $NCA_FLAGS " in *" --allow-existing-base "*) ;; *)
  [ ! -f "$DIR/base_model.ctl" ] || { echo "NCA_BASE_PROTECTED existing base; skip NCA and preserve starts. --allow-existing-base is only for user-requested NCA, never permission to overwrite starts." >&2; exit 2; };;
esac
node "$SELF/nca_preflight.mjs" "$DATA" $NCA_FLAGS || exit 2
HDIR=$(sh "$SELF/rpath.sh" container "$DIR") || exit 2
MIRROR="$DIR/.pmx/pmx_workspace"; mkdir -p "$MIRROR/analyses_template/tools"
if [ "$SELF" != "$MIRROR/analyses_template/tools" ]; then cp -a "$SELF/." "$MIRROR/analyses_template/tools/" || exit 1; fi
chmod -R a+rX "$MIRROR"
JOB="$DIR/.rsub_nca_$$.R"; trap 'rm -f "$JOB"' EXIT HUP INT TERM
NCA_OUT=${PMX_NCA_OUT:-"$DIR/01_screen"}
HOUT=$(sh "$SELF/rpath.sh" container "$NCA_OUT") || exit 2
node -e 'const q=JSON.stringify;console.log("Sys.setenv(PMX_DATA="+q(process.argv[1])+",PMX_ARGS="+q(process.argv.slice(4).join(" "))+",PMX_NCA_OUT="+q(process.argv[2])+",PMX_TOOLKIT="+q(process.argv[3])+")")' "$HDIR/$(basename "$DATA")" "$HOUT" "$HDIR/.pmx/pmx_workspace" $NCA_FLAGS > "$JOB"
cat "$SELF/nca_initials.R" >> "$JOB"; chmod a+r "$JOB"

if [ "$MODE" != sync ]; then
  RC=0; OUT=$(node "$SELF/r-submit.mjs" "$JOB" "nca_$(printf '%s' "$(basename "$DIR")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')" 2>&1) || RC=$?
  rm -f "$JOB"
  printf '%s\n' "$OUT"
  ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
  [ -n "$ACTUAL" ] || ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
  echo "NCA_JOB ${ACTUAL:-unknown}"
  echo "NCA_ATTACH node $SELF/r-submit.mjs --attach ${ACTUAL:-unknown} --follow --summary   (BACKGROUND; completion automatically continues initials/model authoring)"
  echo "NCA_STATUS node $SELF/r-submit.mjs --status ${ACTUAL:-unknown}   (--tail for incremental output)"
  echo "NCA_ASYNC_READY nothing here is waiting on R. Prepare candidate models while NCA runs. Use a successful digest for eligible starts. If NCA fails or is sparse, continue with template starts and note the outcome in chat."
  exit "$RC"
fi

RC=0; OUT=$(node "$SELF/r-submit.mjs" --wait "$JOB" "nca_$$" 2>&1) || RC=$?
printf '%s\n' "$OUT"
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -qE '^NCA_(OK|SPARSE)' || { echo "NCA_FAIL queue or calculation failed" >&2; exit 1; }
[ -s "$NCA_OUT/nca_initials.csv" ] && [ -s "$NCA_OUT/nca_initials.txt" ] || exit 1
