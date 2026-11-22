#!/bin/sh
SELF=$(cd "$(dirname "$0")" && pwd)
if [ "$(basename "$SELF")" != tools ] || [ ! -f "$SELF/../../INDEX.md" ] || [ ! -d "$SELF/../../word-report/stages" ]; then
  CANON_ROOT=${PMX_WS:-${PMX_TOOLKIT:-}}
  CANON="${CANON_ROOT:+$CANON_ROOT/analyses_template/tools/fit_ladder.sh}"
  if [ -f "$CANON" ] && [ "$CANON" != "$SELF/$(basename "$0")" ]; then
    echo "LADDER_TOOLKIT_REDIRECT incomplete/flat copy; using $CANON"
    exec sh "$CANON" "$@"
  fi
  echo "LADDER_TOOLKIT_LAYOUT use the complete workspace analyses_template/tools/fit_ladder.sh; do not build .toolkit copies or submit R scripts by hand" >&2
  exit 2
fi
. "$SELF/queue_budget.sh"   # one budget for the whole queue; see the header there
case "$SELF" in
  */.pmx/*)
    CANON_ROOT=${PMX_WS:-${PMX_TOOLKIT:-}}
    CANON="${CANON_ROOT:+$CANON_ROOT/analyses_template/tools}"
    if [ "${PMX_ALLOW_MIRROR:-0}" != "1" ] && [ -f "$CANON/$(basename "$0")" ]; then
      echo "LADDER_WARN invoked the MIRROR toolkit ($SELF) - re-execing the workspace copy"
      echo "LADDER_WARN (the mirror is a build artifact; set PMX_ALLOW_MIRROR=1 to run it deliberately)"
      exec sh "$CANON/$(basename "$0")" "$@"
    fi
    echo "LADDER_WARN running the MIRROR toolkit ($SELF): its analyses_template/tools/ may be older than $CANON"
    ;;
esac
ACTUAL=""
trap 'echo "LADDER_INTERRUPTED signal=$1 - the round KEEPS RUNNING on the worker; nothing is lost." >&2;
  [ -n "${ACTUAL:-}" ] && echo "LADDER_JOB $ACTUAL" >&2;
  echo "LADDER_RESUME node $SELF/r-submit.mjs --await ${ACTUAL:-<id>} --max-wait-s=40" >&2;
  echo "LADDER_RESUME (or --attach ${ACTUAL:-<id>} --follow --summary as a BACKGROUND job; do NOT loop --status - it is poll-budgeted, exit 5)" >&2;
  exit 0' TERM INT

WSROOT=$(cd "$SELF/../.." && pwd)
DIR="$1"; shift 2>/dev/null
[ -n "$DIR" ] || { echo "usage: fit_ladder.sh <analysis-dir> [--family=..] [--data=..] [--models=..] [--maxfit=9999] [--cores=14] [--export-only] [--new-round] [--limit=0] [--cmt-obs=auto] [--endpoint=\"..\"] [--sync|--async]"; exit 2; }
DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "LADDER_FAIL no such directory"; exit 0; }
HDIR=$(sh "$SELF/rpath.sh" container "$DIR") || { echo "LADDER_FAIL study path is outside configured R mounts" >&2; exit 2; }

# --- toolkit staging ---------------------------------------------------------
# Resolve source relative to this script. If it is outside configured R mounts,
# mirror_toolkit.sh stages the complete toolkit with one content stamp; no partial copies.
if HTOOLKIT=$(sh "$SELF/rpath.sh" container "$WSROOT" 2>/dev/null); then :
else
MIR=$(sh "$SELF/mirror_toolkit.sh" "$DIR")
     printf '%s\n' "$MIR" | grep '^MIRROR_SYNC' | sed 's/^MIRROR_SYNC /LADDER_MIRROR_SYNC /'
     HTOOLKIT=$(printf '%s\n' "$MIR" | sed -n 's/^MIRROR_TOOLKIT //p' | head -1)
     case "$MIR" in
       *MIRROR_FAIL*) printf '%s\n' "$MIR"; echo "LADDER_FAIL toolkit staging failed"; exit 0;;
     esac
     [ -n "$HTOOLKIT" ] || { echo "LADDER_FAIL toolkit mirror not reported"; exit 0; }
fi

FAMILY=ppk; DATA=""; MODELS=""; MAXFIT="${PMX_MAXFIT:-9999}"; MC_CORES="${PMX_MC_CORES:-6}"; CAND_MAX="${PMX_CAND_MAX:-6}"; MANUAL="${PMX_MANUAL_SELECT:-0}"
EXPORT_ONLY=0; NEW_ROUND=0
ASYNC=1; [ "${PMX_SUBMIT_MODE:-submit}" = sync ] && ASYNC=0
CMT_OBS="${PMX_CMT_OBS:-auto}"; ENDPOINT="${PMX_ENDPOINT:-}"; LIMIT_S="${PMX_LIMIT_S:-0}"
[ "$LIMIT_S" -gt 0 ] 2>/dev/null || LIMIT_S=$(qb_budget_ladder)
for a in "$@"; do case "$a" in
  --family=*)   FAMILY="${a#--family=}";;
  --data=*)     DATA="${a#--data=}";;
  --models=*)   MODELS="${a#--models=}";;
  --maxfit=*)   MAXFIT="${a#--maxfit=}";;
  --cores=*)    MC_CORES="${a#--cores=}";;
  --cmt-obs=*)  CMT_OBS="${a#--cmt-obs=}";;
  --endpoint=*) ENDPOINT="${a#--endpoint=}";;
  --layout=flat) PMX_LAYOUT=flat;;
  --layout=convention) PMX_LAYOUT=convention;;
  --limit=*)    LIMIT_S="${a#--limit=}";;
  --cand-max=*) CAND_MAX="${a#--cand-max=}";;
  --manual-select) MANUAL=1;;
  --export-only) EXPORT_ONLY=1;;
  --new-round) NEW_ROUND=1;;
  --sync)  ASYNC=0;;
  --async) ASYNC=1;;
  *) echo "LADDER_FAIL unknown option $a"; exit 0;;
esac; done
CEILING=$(qb_budget_ladder)
if [ "$LIMIT_S" -gt "$CEILING" ] 2>/dev/null; then
  echo "LADDER_LIMIT_CLAMP requested=$LIMIT_S ceiling=$CEILING"
  LIMIT_S=$CEILING
fi
case "$CMT_OBS" in auto|AUTO|keep|KEEP) ;; [0-9]*) ;; *) echo "LADDER_FAIL --cmt-obs must be auto, an integer, or keep"; exit 0;; esac
echo "LADDER_BUDGET limit_s=$LIMIT_S worker_timeout_s=$(qb_worker_timeout) headroom_s=$PMX_HEADROOM_S ladder_reserve_s=$PMX_LADDER_RESERVE_S cand_max=$CAND_MAX models_explicit=$([ -n "$MODELS" ] && echo 1 || echo 0)"
SCREEN="$DIR/01_screen"
[ "${PMX_LAYOUT:-convention}" != flat ] || SCREEN="$DIR"
mkdir -p "$SCREEN" 2>/dev/null
HSCREEN="$HDIR/01_screen"
[ "$SCREEN" != "$DIR" ] || HSCREEN="$HDIR"

if [ -n "$MODELS" ]; then
  NM=$(printf '%s\n' "$MODELS" | tr ',' '\n' | grep -c . 2>/dev/null)
  if [ "${NM:-0}" -gt "${CAND_MAX:-6}" ] 2>/dev/null; then
    echo "LADDER_WARN_MODELS_OVER_CAP models=$NM cand_max=$CAND_MAX"
    echo "LADDER_WARN an explicit --models list bypasses --cand-max, so every listed model is attempted"
    echo "LADDER_WARN (the round's time budget still applies: over-wide rounds get their tail held back)"
  fi
elif [ -d "$SCREEN" ]; then
  SET=""
  for f in "$SCREEN"/*.ctl; do [ -e "$f" ] || continue; SET="$SET $(basename "$f")"; done
  NCAND=0; for n in $SET; do NCAND=$((NCAND + 1)); done
  if [ "$NCAND" -gt "${CAND_MAX:-6}" ] 2>/dev/null; then
    DROP=""; KEEPN=0; KEEP=""
    for n in $(printf '%s\n' $SET | sort); do
      if [ "$KEEPN" -lt "$CAND_MAX" ]; then KEEPN=$((KEEPN + 1)); KEEP="$KEEP $n"
      else DROP="$DROP $n"; fi
    done
    echo "LADDER_WARN_LADDER_TOO_WIDE candidates=$NCAND cand_max=$CAND_MAX will_not_fit=$DROP"
    echo "LADDER_WARN fits=${KEEP# } not_attempted=${DROP# }"
    echo "LADDER_WARN authoring width = fit width: delete or rename the candidates you do not want, or"
    echo "LADDER_WARN lower/raise --cand-max deliberately - a wide screen loses the END of the ladder"
  fi
fi

CHMOD_N=0
for f in "$SCREEN"/*.ctl; do
  [ -e "$f" ] || continue
  M=$(ls -ld "$f" 2>/dev/null); M=${M%% *}
  case "$M" in
    ???????r*) ;;
    *) chmod a+r "$f" 2>/dev/null && CHMOD_N=$((CHMOD_N + 1));;
  esac
done
[ "$CHMOD_N" -gt 0 ] && echo "LADDER_CHMOD_READABLE granted_world_read=$CHMOD_N dir=$SCREEN (SKILL.md SMB readability rule was not applied to these .ctl)"

if [ -z "$DATA" ]; then
  for f in "$DIR/${FAMILY}_data.csv" "$DIR/ppk_data.csv" "$DIR/data.csv" \
           "$DIR/${FAMILY}_data.txt" "$DIR/data.txt" "$DIR/${FAMILY}_data.dat" "$DIR/data.dat"; do
    [ -f "$f" ] && { DATA="$f"; break; }
  done
  if [ -z "$DATA" ]; then
    DATA=$(ls -S "$DIR"/*.csv "$DIR"/*.txt "$DIR"/*.dat 2>/dev/null | grep -v -e '/ladder_table\.' -e '/covariates' -e '/nca_initials\.' -e '/\.nca_initials\.' | head -1)
  fi
fi
[ -n "$DATA" ] || { echo "LADDER_FAIL no data file in $DIR"; exit 0; }
case "$DATA" in
  /*) ;;
  *)  DATA="$DIR/$DATA";;
esac
HDATA=$(sh "$SELF/rpath.sh" container "$DATA") || { echo "LADDER_FAIL data path is outside configured R mounts" >&2; exit 2; }
GUARD_RC=0
GUARD=$(PMX_LADDER_NEW_ROUND="$NEW_ROUND" PMX_FAMILY="$FAMILY" PMX_CMT_OBS="$CMT_OBS" PMX_ENDPOINT="$ENDPOINT" node "$SELF/ladder_guard.mjs" --check "$DIR" "$DATA" "$WSROOT" "$MODELS" "$CAND_MAX" 2>&1) || GUARD_RC=$?
case "$GUARD_RC" in
  0|4) printf '%s\n' "$GUARD"; exit "$GUARD_RC";;
  10) ;;  # new content; one bounded screening round is allowed
  11) printf '%s\n' "$GUARD"; EXPORT_ONLY=1;;  # completed fits need export, never estimation
  *) printf '%s\n' "$GUARD"; echo "LADDER_STOP cannot verify screening ledger"; exit 2;;
esac
ROUND_RECORD=$(PMX_LADDER_EXPORT_ONLY="$EXPORT_ONLY" PMX_FAMILY="$FAMILY" PMX_CMT_OBS="$CMT_OBS" PMX_ENDPOINT="$ENDPOINT" node "$SELF/ladder_guard.mjs" --prepare "$DIR" "$DATA" "$WSROOT" "$MODELS" "$CAND_MAX") || {
  echo "LADDER_STOP cannot prepare content-bound round record" >&2; exit 2;
}
W="$DIR/.rsub_ladder.R"
echo "LADDER_TOOLKIT $HTOOLKIT"
{ node "$SELF/queue_env.mjs" PMX_DIR "$HSCREEN" PMX_ROOT "$HDIR" PMX_DATA "$HDATA" PMX_MODELS "$MODELS" PMX_FAMILY "$FAMILY" PMX_MAXFIT "$MAXFIT" PMX_MC_CORES "$MC_CORES" PMX_CMT_OBS "$CMT_OBS" PMX_ENDPOINT "$ENDPOINT" PMX_LIMIT_S "$LIMIT_S" PMX_CAND_MAX "$CAND_MAX" PMX_MANUAL_SELECT "$MANUAL" PMX_LADDER_RECORD "$ROUND_RECORD" PMX_LADDER_AGENT_DIR "$DIR" PMX_LADDER_AGENT_TOOLKIT "$WSROOT" PMX_LADDER_EXPORT_ONLY "$EXPORT_ONLY" PMX_TOOLKIT "$HTOOLKIT" PMX_WORKER_TIMEOUT_S "$(qb_worker_timeout)" PMX_HEADROOM_S "$PMX_HEADROOM_S" PMX_LADDER_RESERVE_S "$PMX_LADDER_RESERVE_S"
  cat "$SELF/fit_ladder.R"; } > "$W"
chmod a+r "$W" 2>/dev/null
POLL_MS=$(qb_poll_ms); export POLL_MS
LID="ladder_$(printf '%s' "$(basename "$DIR")" | tr -c 'A-Za-z0-9._-' '_')"
if [ "$ASYNC" = 1 ]; then
  RC=0; OUT=$(node "$SELF/r-submit.mjs" "$W" "$LID" 2>&1) || RC=$?
  rm -f "$W"
  printf '%s\n' "$OUT" | sh "$SELF/rpath.sh" text
  ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
  [ -n "$ACTUAL" ] || ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
  if [ -z "$ACTUAL" ]; then
    echo "LADDER_SUBMIT_FAIL no queue id was returned; no observer can be promised. Preserve the screen and review the submission error." >&2
    [ "$RC" != 0 ] || RC=2
    exit "$RC"
  fi
  echo "LADDER_JOB $ACTUAL"
  echo "LADDER_ATTACH node $SELF/r-submit.mjs --attach ${ACTUAL:-unknown} --follow --summary   (BACKGROUND; one active observer)"
  echo "LADDER_WAIT node $SELF/r-submit.mjs --await ${ACTUAL:-unknown} --max-wait-s=40   (one foreground fallback only)"
  echo "LADDER_STATUS node $SELF/r-submit.mjs --status ${ACTUAL:-unknown}   (POLL-BUDGETED: one look per 45s; repeated looks exit 5)   |  --tail for incremental output"
  echo "LADDER_SELECT On completion review the selection once and follow LADDER_NEXT. Cached fits and the terminal ledger are preserved; a worker timeout is a blocker, not permission to replay screening."
  echo "LADDER_ASYNC_READY nothing here is waiting on R: this ONE job fits all candidates in $SCREEN. Prepare downstream configuration while it runs; never rewrite or delete active candidates."
  echo "LADDER_WAIT_FALLBACK if run_in_background is refused (no background job controller in this client), do NOT retry and do NOT sit in a blocking wait."
  echo "LADDER_WAIT_FALLBACK take ONE bounded foreground window per queue id: node $SELF/r-submit.mjs --await ${ACTUAL:-unknown} --max-wait-s=40  (it sleeps between looks and returns RSUB_PENDING + the id)."
  echo "LADDER_WAIT_FALLBACK NEVER loop LADDER_STATUS/--status: it is poll-budgeted (one look per 45s per id; repeated looks exit 5; 4 unchanged looks CLOSE the window). Use --tail for progress. Configure background jobs and completion notifications in the agent client."
  exit 0
fi
# SUBMIT, PRINT THE ID, THEN WAIT ONE BOUNDED WINDOW. The id is the contract with the caller: it is
# printed before anything can block, so a killed turn still knows what to follow and never needs to
# loop --status. The window is short (qb_collect_wait) so this call ALWAYS returns output.
RCS=0; OUTS=$(node "$SELF/r-submit.mjs" "$W" "$LID" 2>&1) || RCS=$?
printf '%s\n' "$OUTS" | sh "$SELF/rpath.sh" text
ACTUAL=$(printf '%s\n' "$OUTS" | sed -n 's/^RSUB_JOB //p' | head -1)
[ -n "$ACTUAL" ] || ACTUAL=$(printf '%s\n' "$OUTS" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
if [ -z "$ACTUAL" ]; then
  rm -f "$W"
  echo "LADDER_SUBMIT_FAIL no queue id was returned; preserve the screen and review the submission error." >&2
  [ "$RCS" != 0 ] || RCS=2
  exit "$RCS"
fi
echo "LADDER_JOB $ACTUAL"
echo "LADDER_ATTACH node $SELF/r-submit.mjs --attach ${ACTUAL:-unknown} --follow --summary   (run it as a BACKGROUND job)"
echo "LADDER_AWAIT node $SELF/r-submit.mjs --await ${ACTUAL:-unknown} --max-wait-s=40"
echo "LADDER_SELECT On completion review the selection once and follow LADDER_NEXT. Cached fits and the terminal ledger are preserved; a worker timeout is a blocker, not permission to replay screening."
OUT=""
if [ -n "$ACTUAL" ]; then
  RCS=0; OUT=$(node "$SELF/r-submit.mjs" --await "$ACTUAL" --max-wait-s="$(qb_collect_wait)" 2>&1) || RCS=$?
fi
rm -f "$W"
printf '%s\n' "$OUT" | sh "$SELF/rpath.sh" text
# Only an explicit pending result means this R job is still live. A finished worker timeout
# preserves the screen ledger/caches but does not authorize another estimation round.
case "$OUT" in
  *"RSUB_PENDING id="*)
    echo "LADDER_DEFER id=${ACTUAL:-unknown} the round is STILL RUNNING (this window was $(qb_collect_wait)s; a ladder may use $(qb_budget_ladder)s).";
    echo "LADDER_DEFER nothing is lost and nothing is refitted: ladder_table.csv and <model>.fit.rds persist.";
    echo "LADDER_DEFER wait:      node $SELF/r-submit.mjs --attach ${ACTUAL:-unknown} --follow --summary   (as a BACKGROUND job)";
    echo "LADDER_DEFER do not resubmit while running; collect once. A completed round advances with any usable fit or stops with recorded failures.";
    exit 3;;
esac
if [ "$RCS" != 0 ]; then
  echo "LADDER_BLOCKED id=${ACTUAL:-unknown} result_exit=$RCS; this wait ended without an explicit pending handoff. Preserve completed fits and review the recorded terminal reason; do not replay screening." >&2
  exit "$RCS"
fi
exit 0
