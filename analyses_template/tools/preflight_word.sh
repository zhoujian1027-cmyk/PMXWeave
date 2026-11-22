#!/bin/sh

SELF=$(cd "$(dirname "$0")" && pwd)
MODE=${PMX_SUBMIT_MODE:-submit}
JID=""; DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sync)      MODE=sync ;;
    --async)     MODE=submit ;;
    --collect)   MODE=collect; JID="${2:-}"; [ -z "$JID" ] || shift ;;
    --collect=*) MODE=collect; JID="${1#--collect=}" ;;
    -*)          echo "WORD_PREFLIGHT_STOP unknown option $1" >&2; exit 2 ;;
    *)           DIR="$1" ;;
  esac
  shift
done

if [ "$MODE" = collect ]; then
  [ -n "$JID" ] || { echo "WORD_PREFLIGHT_STOP usage: preflight_word.sh --collect <job-id>"; exit 2; }
  # A COLLECT wait is bounded (40 s, under the harness kill) so it always returns an answer: either
  # the digest, or "not ready" plus the id and the way to wait. --status is never polled here.
  RC=0; OUT=$(node "$SELF/r-submit.mjs" --attach "$JID" --max-wait-s="${PMX_COLLECT_MAX_S:-40}" 2>&1) || RC=$?
  printf '%s\n' "$OUT" | grep -E '^(WORD_ENV_OK|WORD_ENV_BROKEN|WORD_ENV_BROKEN_MSG|WORD_ENV_BROKEN_LDD|WORD_STYLE_DIR|WORD_STYLE_MISSING|WORD_STYLE_UNSTAGED|WORD_PREFLIGHT_REPEAT|WORD_SCRIPT_COPY|WORD_PREFLIGHT_STOP)' || true
  printf '%s\n' "$OUT" | grep -qE '^(WORD_ENV_OK)' && exit 0
  printf '%s\n' "$OUT" | tail -12
  exit 1
fi

[ -n "$DIR" ] || { echo "WORD_PREFLIGHT_STOP usage: preflight_word.sh <analysis-dir>" >&2; exit 2; }
DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "WORD_PREFLIGHT_STOP no such directory $1" >&2; exit 2; }
HDIR=$(sh "$SELF/rpath.sh" container "$DIR") || { echo "WORD_PREFLIGHT_STOP study path is outside configured R mounts" >&2; exit 2; }

# The probe R file is built inside the workspace root so the container can read it; it is staged into
# the analysis dir's .pmx/ sidecar so nothing of the user's directory layout is disturbed.
W="$DIR/.pmx/preflight_word_$$.R"
mkdir -p "$DIR/.pmx" 2>/dev/null || true
{ node "$SELF/queue_env.mjs" PMX_ANALYSIS_DIR "$HDIR"
  cat "$SELF/preflight_word.R"; } > "$W" || { echo "WORD_PREFLIGHT_STOP cannot stage $W" >&2; exit 2; }
chmod a+rx "$DIR/.pmx" 2>/dev/null || true
chmod a+r "$W" 2>/dev/null || true

RC=0
if [ "$MODE" = sync ]; then
  OUT=$(node "$SELF/r-submit.mjs" --wait "$W" "wf_"$$ 2>&1) || RC=$?
else
  OUT=$(node "$SELF/r-submit.mjs" "$W" "wf_$(printf '%s' "$(basename "$DIR")" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')" 2>&1) || RC=$?
fi
rm -f "$W"

if [ "$MODE" = sync ]; then
  printf '%s\n' "$OUT" | grep -E '^(WORD_ENV_OK|WORD_ENV_BROKEN|WORD_ENV_BROKEN_MSG|WORD_ENV_BROKEN_LDD|WORD_STYLE_DIR|WORD_STYLE_MISSING|WORD_STYLE_UNSTAGED|WORD_PREFLIGHT_REPEAT|WORD_SCRIPT_COPY|WORD_PREFLIGHT_STOP)' || printf '%s\n' "$OUT" | tail -12
  [ "$RC" = 0 ] && exit 0
  exit 1
fi

printf '%s\n' "$OUT"
ID=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
[ -n "$ID" ] || ID=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
[ -n "$ID" ] || exit 1
echo "WORD_PREFLIGHT_JOB $ID dir=$DIR"
echo "WORD_PREFLIGHT_COLLECT sh $SELF/preflight_word.sh --collect <job-id>"
exit 0
