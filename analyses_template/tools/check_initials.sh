#!/bin/sh

SELF=$(cd "$(dirname "$0")" && pwd)
MODE=${PMX_SUBMIT_MODE:-submit}
JID=""; DATA=""; WANT_ID=0
for arg do
  shift
  if [ "$WANT_ID" = 1 ]; then JID=$arg; WANT_ID=0; continue; fi
  case "$arg" in
    --sync)      MODE=sync ;;
    --async)     MODE=submit ;;
    --collect)   MODE=collect; WANT_ID=1 ;;
    --collect=*) MODE=collect; JID="${arg#--collect=}" ;;
    --force-resubmit) EXTRA=--force-resubmit ;;
    *.csv|*.CSV) DATA="$arg" ;;
    *) set -- "$@" "$arg" ;;
  esac
done
EXTRA=${EXTRA:-}

if [ "$MODE" = collect ]; then
  [ -n "$JID" ] || { echo "INIT_BAD n=1 codes=NO_JOB_ID usage=check_initials.sh --collect <job-id>"; exit 2; }
  # A COLLECT wait is bounded (40 s, under the harness kill) so it always returns an answer: either
  # the digest, or "not ready" plus the id and the way to wait. --status is never polled here.
  RC=0; OUT=$(node "$SELF/r-submit.mjs" --attach "$JID" --max-wait-s="${PMX_COLLECT_MAX_S:-40}" 2>&1) || RC=$?
  printf '%s\n' "$OUT" | grep -E '^(BOUNDS|NOFIX|FLIPFLOP|F1_RANGE|TLAG|SCALE|OMEGA|SIGMA|DATA|INIT_OK|INIT_BAD)' || true
  printf '%s\n' "$OUT" | grep -qE '^(INIT_OK|INIT_BAD)' || printf '%s\n' "$OUT" | tail -12
  exit 0
fi

if [ -z "${1:-}" ]; then echo "INIT_BAD n=1 codes=NO_ARG"; exit 0; fi
CTL="$1"
if [ ! -f "$CTL" ]; then echo "INIT_BAD n=1 codes=NO_CTL path=$CTL"; exit 0; fi
D=$(dirname "$CTL")
if [ -z "$DATA" ]; then
  for f in "$D"/*.csv; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in covariates.csv|nca_initials.csv|tbl_*.csv|html_tbl_*.csv|ladder_table.csv) continue;; esac
    [ -z "$DATA" ] || { echo "INIT_BAD n=1 codes=AMBIGUOUS_DATA pass_explicit_data"; exit 2; }
    DATA=$f
  done
fi

[ -n "$DATA" ] && [ -f "$DATA" ] || { echo "INIT_BAD n=1 codes=NO_DATA"; exit 2; }

hmap() { sh "$SELF/rpath.sh" container "$1"; }
HDATA=$(hmap "$DATA") || { echo "INIT_BAD n=1 codes=NOT_SHARED_DATA path=$DATA"; exit 2; }


JIDS=""; N=0
for CTL do
  N=$((N + 1))
  HCTL=$(hmap "$CTL") || { echo "INIT_BAD n=1 codes=NOT_SHARED path=$CTL"; continue; }
  W="$(dirname "$CTL")/.rsub_ci_$$_$N.R"
  { node "$SELF/queue_env.mjs" PMX_CTL "$HCTL" PMX_DATA "$HDATA"
    cat "$SELF/data_filters.R" "$SELF/check_initials.R"; } > "$W"
  RC=0
  if [ "$MODE" = sync ]; then
    OUT=$(node "$SELF/r-submit.mjs" --wait $EXTRA "$W" "ci_$$_$N" 2>&1) || RC=$?
  else
    OUT=$(node "$SELF/r-submit.mjs" $EXTRA "$W" "ci_$$_$N" 2>&1) || RC=$?
  fi
  rm -f "$W"
  OUT=$(printf '%s\n' "$OUT" | sh "$SELF/rpath.sh" text)
  if [ "$MODE" = sync ]; then
    printf '%s\n' "$OUT" | grep -E '^(BOUNDS|NOFIX|FLIPFLOP|F1_RANGE|TLAG|SCALE|OMEGA|SIGMA|DATA|INIT_OK|INIT_BAD)' || true
    if ! printf '%s\n' "$OUT" | grep -qE '^(INIT_OK|INIT_BAD)'; then
      printf '%s\n' "$OUT" | tail -12
      echo "INIT_BAD n=1 codes=QUEUE_FAIL file=$CTL"
    fi
  else
    printf '%s\n' "$OUT"
    ID=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
    [ -n "$ID" ] || ID=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
    echo "INIT_JOB ${ID:-unknown} file=$CTL"
    JIDS="$JIDS ${ID:-unknown}"
  fi
done

if [ "$MODE" = sync ]; then exit 0; fi
echo "INIT_QUEUED n=$N jobs=$JIDS"
echo "INIT_ATTACH node $SELF/r-submit.mjs --attach <job-id> --follow --summary   (BACKGROUND; verdicts also land in <model>.initials.txt)"
echo "INIT_STATUS node $SELF/r-submit.mjs --status <job-id>   (--tail for incremental output)"
echo "INIT_ASYNC_READY nothing here is waiting on R: every candidate is queued in one call. Submit the ladder while these run."
exit 0
