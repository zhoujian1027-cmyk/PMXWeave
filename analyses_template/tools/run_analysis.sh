#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
WS=$(cd "$SELF/../.." && pwd)
NODE=${NODE:-node}
# A controller holds only an idle host process, not an extra R worker.
if [ "${1:-}" = --follow-chain ]; then
  shift
  FOLLOW_DIR=${1:-}
  [ -n "$FOLLOW_DIR" ] || { echo "CHAIN_FOLLOW_USAGE supply the study directory" >&2; exit 2; }
  FOLLOW_DIR=$(cd "$FOLLOW_DIR" && pwd) || exit 2
  command -v flock >/dev/null 2>&1 || { echo "CHAIN_CONTROLLER_CAPABILITY flock is required; no job submitted" >&2; exit 2; }
  mkdir -p "$FOLLOW_DIR/.pmx" || exit 2
  # Kernel lock releases on exit/service interruption; the empty file is not a progress ledger.
  LOCK="$FOLLOW_DIR/.pmx/chain_controller.lock"
  (umask 002; : >> "$LOCK") || exit 2
  chmod g+rw "$LOCK" 2>/dev/null || true
  FOLLOW_RC=0
  flock -n -E 75 "$LOCK" "$NODE" "$SELF/chain_follow.mjs" "$@" || FOLLOW_RC=$?
  [ "$FOLLOW_RC" != 75 ] || echo "CHAIN_CONTROLLER_ACTIVE study=$FOLLOW_DIR; keep the existing controller, do not start another" >&2
  exit "$FOLLOW_RC"
fi
. "$SELF/queue_budget.sh"   # one budget for the whole queue; see the header there

ACTUAL=""; LADID=""
trap 'echo "CHAIN_INTERRUPTED signal=$1 - the job KEEPS RUNNING on the worker; nothing is lost." >&2;
  [ -n "${LADID:-}" ] && echo "CHAIN_LADDER_JOB $LADID" >&2;
  [ -n "${ACTUAL:-}" ] && echo "CHAIN_JOB $ACTUAL" >&2;
  echo "CHAIN_RESUME node $SELF/r-submit.mjs --await ${ACTUAL:-${LADID:-<id>}} --max-wait-s=40  (one fallback only; prefer the single BACKGROUND --attach waiter)" >&2;
  echo "CHAIN_RESUME keep one BACKGROUND observer for the live id; a verified checkpoint/DEFER completion automatically advances the wrapper. Never resubmit live R work or loop --status." >&2;
  exit 3' TERM INT

# A missing paired simulator is model-authoring work, not another R retry.
simulator_handoff() {
  printf '%s\n' "$OUT" | grep -q '^S2_SIMULATOR_REQUIRED file=' || return 1
  printf '%s\n' "$OUT" | grep -q 'S2_MODEL_CONTRACT_UNSUPPORTED' || return 1
  if printf '%s\n' "$OUT" | grep -q 'S2_SIMULATOR_INVALID'; then return 1; fi
  echo "CHAIN_SIMULATOR_REQUIRED prepare the named files from the frozen CTL; report scope authorizes this study artifact work"
  echo "CHAIN_NEXT author the pair now, preserving equations/endpoints/ETA/EPS/scale; then resume --from=s2; do not refit or ask for another continue"
  return 0
}

case "${1:-}" in
  --attach|--watch) MODE=--attach; MODE_ID=${2:-};;
  --status)         MODE=--status; MODE_ID=${2:-};;
  *)                MODE=""; MODE_ID="";;
esac
if [ -n "${MODE:-}" ]; then
  [ -n "$MODE_ID" ] || { echo "usage: run_analysis.sh $1 <id>" >&2; exit 2; }
  # --attach is the BACKGROUND waiter, so it may hold for the worker cap; a foreground kill still
  # prints its banner and its id through the trap above. --status is deliberately never looped here.
  if [ "$MODE" = --attach ]; then
    RC=0; OUT=$("$NODE" "$SELF/r-submit.mjs" "$MODE" "$MODE_ID" --follow --summary 2>&1) || RC=$?
  else
    RC=0; OUT=$("$NODE" "$SELF/r-submit.mjs" "$MODE" "$MODE_ID" 2>&1) || RC=$?
  fi
  printf '%s\n' "$OUT"
  [ "$MODE" = --status ] && exit "$RC"
  if simulator_handoff; then exit 2; fi
  GATES=$(printf '%s\n' "$OUT" | grep '^CHAIN_GATE' | tr -d '\r')
  COUNT=$(printf '%s\n' "$GATES" | grep -c ' DONE$')
  if printf '%s\n' "$OUT" | grep -q '^NARRATIVE_REQUIRED'; then
    echo "CHAIN_NARRATIVE_REQUIRED structured report preserved; author Results/Discussion/Conclusion using node $SELF/report_narrative.mjs <study> --brief, validate, then resume --from=s5 (or --from=s4 for HTML); do not rerun fits"
    exit 4
  fi
  if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^CHAIN_COVARIANCE_DONE'; then echo "CHAIN_COVARIANCE_DONE $MODE_ID"; exit 0; fi
  if printf '%s\n' "$OUT" | grep -q '^STAGES_CHECKPOINT'; then echo "CHAIN_CHECKPOINT $MODE_ID - continue the next stage in a fresh job; do not repeat completed work"; exit 3; fi
  if printf '%s\n' "$OUT" | grep -q '^STAGES_DEFER stage '; then echo "CHAIN_DEFER $MODE_ID finished its window; continue the wrapper once with valid caches; do not reattach to this completed id"; exit 3; fi
  if [ "$RC" = 0 ] && [ "$COUNT" = 6 ]; then echo "CHAIN_DONE $MODE_ID"; exit 0; fi
  case "$RC" in
    3) echo "CHAIN_PENDING_OR_STOPPED $MODE_ID: use the recorded result state. Follow a live id once; a completed non-handoff exit requires repair, never repeated attachment or blind resubmission." >&2; exit 3;;
    4) echo "CHAIN_CRASHED $MODE_ID R died from a SIGNAL (see the log paths printed above). The worker timeout can also cause a signal exit: read the failed phase once; do not change the model or raise the budget blindly." >&2; exit 4;;
    *) echo "CHAIN_PARTIAL $MODE_ID finished with $COUNT/6 gates DONE" >&2; exit 1;;
  esac
fi
DIR=${1:-}; [ -n "$DIR" ] || { echo "usage: run_analysis.sh <analysis-dir> --family=ppk|pkpd|tmdd --data=<file> [--screen --models=a.ctl,b.ctl] [--depots=N] [--tau=H] [--route=iv|oral|sc] [--blq=exclude|keep] [--blq-factor=F] [--dose-split=auto|single|total] [--impute-lambda-z=cohort|off] [--cand-max=6] [--manual-select] [--skip-nca|--run-nca] [--nca-dv-column=DV --dv-scale=raw] [--covariance-only|--from=s2|--from=s4|--from=s5] [--sync]" >&2
  echo "       run_analysis.sh --attach <id> | --watch <id> | --status <id>   (wait for / inspect an already submitted chain job; --async is the default)" >&2; exit 2; }
shift
DIR=$(cd "$DIR" && pwd) || exit 2
FAMILY=ppk; CHAIN_ONLY=""; CHAIN_FROM=""; DATA=""; MODELS=""; JOBS=3; MAXFIT=9999; DO_SCREEN=0; SKIP_NCA=0; RUN_NCA=0; LAYOUT=convention; REFRESH=0; NCA_FLAGS=""; CAND_MAX=6; MANUAL_SELECT=0; ASYNC=1
for a in "$@"; do case "$a" in
  --family=*) FAMILY=${a#--family=};;
  --data=*) DATA=${a#--data=};;
  --models=*) MODELS=${a#--models=}; DO_SCREEN=1;;
  --screen) DO_SCREEN=1;;
  --skip-nca) SKIP_NCA=1;;
  --run-nca) RUN_NCA=1;;
  --covariance-only) CHAIN_ONLY=s1c;;
  --from=s2|--from=s4|--from=s5) CHAIN_FROM=${a#*=};;
  --skip-ladder) DO_SCREEN=0;;
  --jobs=*) JOBS=${a#--jobs=};;
  --maxfit=*) MAXFIT=${a#--maxfit=};;
  --layout=flat) LAYOUT=flat;;
  --refresh-templates) REFRESH=1;;
  --depots=*|--dv-scale=*|--route=*|--nca-dvid=*|--nca-cmt=*|--nca-dv-column=*|--blq=*|--blq-factor=*|--dose-split=*|--impute-lambda-z=*) NCA_FLAGS="$NCA_FLAGS $a";;
  --require-nca) RUN_NCA=1;;
  --cand-max=*) CAND_MAX="${a#--cand-max=}";;
  --manual-select) MANUAL_SELECT=1;;
  --async) ASYNC=1;;
  --sync)  ASYNC=0;;
  --tau=*)    NCA_FLAGS="$NCA_FLAGS --tau=${a#--tau=}";;
  *) echo "CHAIN_FAIL unknown option: $a" >&2; exit 2;;
esac; done
[ "$RUN_NCA:$SKIP_NCA" != 1:1 ] || { echo "CHAIN_FAIL --run-nca conflicts with --skip-nca" >&2; exit 2; }
if [ -f "$DIR/base_model.ctl" ] && [ "$RUN_NCA" = 0 ]; then
  SKIP_NCA=1
  echo "NCA_SKIPPED_EXISTING_BASE preserve user starts; proceed to base-fit comparison/SCM using valid caches"
fi
[ "$RUN_NCA" = 0 ] || NCA_FLAGS="$NCA_FLAGS --allow-existing-base"
[ "$CHAIN_ONLY" != s1c ] || { SKIP_NCA=1; DO_SCREEN=0; }
[ -z "$CHAIN_FROM" ] || { SKIP_NCA=1; DO_SCREEN=0; }
[ -z "$CHAIN_FROM" ] || [ -z "$CHAIN_ONLY" ] || { echo "CHAIN_FAIL choose --from=s2/s4/s5 or --covariance-only" >&2; exit 2; }
case "$FAMILY" in ppk|pkpd|tmdd) ;; *) echo "Use run_er.sh or run_cqtc.sh for regression families" >&2; exit 2;; esac
case "$JOBS:$MAXFIT" in *[!0-9:]*|0:*|*:0) echo "jobs and maxfit must be positive integers" >&2; exit 2;; esac
if [ -z "$DATA" ]; then
  set -- "$DIR"/*.csv "$DIR"/*.dat "$DIR"/*.txt "$DIR"/*.tab
  for f in "$@"; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in covariates.csv|ladder_table.csv|nca_initials.*|.nca_initials.*) continue;; esac
    [ -z "$DATA" ] || { echo "CHAIN_FAIL several data files; pass --data" >&2; exit 2; }
    DATA=$f
  done
fi
case "$DATA" in /*) ;; *) DATA="$DIR/$DATA";; esac
[ -f "$DATA" ] || { echo "CHAIN_FAIL missing data: $DATA" >&2; exit 2; }
DATA=$(cd "$(dirname "$DATA")" && pwd)/$(basename "$DATA")
[ "$(dirname "$DATA")" = "$DIR" ] || { echo "Use the directory containing the data as analysis-dir" >&2; exit 2; }
sh "$SELF/rpath.sh" check "$DIR" >/dev/null 2>&1 || { echo "CHAIN_FAIL analysis directory is not visible on the R shared mount" >&2; exit 2; }
HDIR=$(sh "$SELF/rpath.sh" container "$DIR")
HDATA="$HDIR/$(basename "$DATA")"
if [ "$LAYOUT" = flat ]; then SCREEN="$DIR"; HTMLD="$DIR"; WORDD="$DIR"; else SCREEN="$DIR/01_screen"; HTMLD="$DIR/02_html"; WORDD="$DIR/03_word"; fi
# Restore a verified completed covariance policy before progress checks/job environment capture.
# An omitted PMX_COV_METHOD must never replace successful r covariance with default s.
COV_HANDOFF_RC=0
COV_HANDOFF=$("$NODE" "$SELF/covariance_handoff.mjs" "$DIR" "$DATA" "$FAMILY" "$LAYOUT" "$CHAIN_ONLY" 2>&1) || COV_HANDOFF_RC=$?
[ "$COV_HANDOFF_RC" = 0 ] || { printf '%s\n' "$COV_HANDOFF"; exit "$COV_HANDOFF_RC"; }
for COV_KEY in PMX_COV_METHOD PMX_COV_FALLBACK PMX_COV_BASE; do
  COV_LINE=$(printf '%s\n' "$COV_HANDOFF" | sed -n "s/^COV_HANDOFF_SETTING $COV_KEY=//p")
  if printf '%s\n' "$COV_HANDOFF" | grep -q "^COV_HANDOFF_SETTING $COV_KEY="; then
    if [ -n "$COV_LINE" ]; then export "$COV_KEY=$COV_LINE"; else unset "$COV_KEY"; fi
  fi
done
printf '%s\n' "$COV_HANDOFF" | sed '/^COV_HANDOFF_SETTING /d;/^$/d'
# Capture BEFORE submission: a fresh valid cache or completed stage permits resumption.
# Counter/log growth and mirror edits alone do not permit another failed chain.
PROGRESS_RC=0
CHAIN_SNAPSHOT=$("$NODE" "$SELF/chain_progress.mjs" check "$DIR" "$WS" "$DATA" "$FAMILY" "$LAYOUT" "$CHAIN_ONLY" "$CHAIN_FROM") || PROGRESS_RC=$?
[ "$PROGRESS_RC" = 0 ] || exit "$PROGRESS_RC"
mkdir -p "$SCREEN" "$HTMLD" "$WORDD"
DATA_KEY=$( { cksum "$DATA" "$SELF/nca_initials.R" "$SELF/nca_initials.sh" "$SELF/nca_input.R" "$SELF/nca_preflight.mjs"; printf '%s\n' "$NCA_FLAGS"; } | cksum)
if [ "$SKIP_NCA" = 0 ] && { [ ! -s "$SCREEN/nca_initials.csv" ] || [ ! -s "$SCREEN/nca_initials.txt" ] || [ ! -f "$SCREEN/.nca_initials.key" ] || [ "$(cat "$SCREEN/.nca_initials.key")" != "$DATA_KEY" ]; }; then
  if PMX_NCA_OUT="$SCREEN" sh "$SELF/nca_initials.sh" "$DATA" $NCA_FLAGS --sync > "$SCREEN/.nca_initials.log" 2>&1; then
    printf '%s\n' "$DATA_KEY" > "$SCREEN/.nca_initials.key"
    chmod a+r "$SCREEN/.nca_initials.key" 2>/dev/null
    if grep -q '^NCA_OK ' "$SCREEN/.nca_initials.log"; then
      grep '^NCA_OK ' "$SCREEN/.nca_initials.log" | tail -1
    else
      echo "NCA_NOT_AVAILABLE No usable NCA initials. Continue with existing or template starts."
    fi
  else
    RC=$?
    echo "NCA_NOT_AVAILABLE NCA exited $RC. Continue with existing or template starts. See $SCREEN/.nca_initials.log."
  fi
elif [ "$SKIP_NCA" = 0 ]; then
  if grep -q '^; INITIALS ' "$SCREEN/nca_initials.txt"; then
    printf 'NCA_OK %s\n' "$(sed -n '1s/^; //p' "$SCREEN/nca_initials.txt")"
  else
    echo "NCA_NOT_AVAILABLE No usable NCA initials. Continue with existing or template starts."
  fi
fi
if [ "$DO_SCREEN" = 1 ]; then
  if [ "$SCREEN" != "$DIR" ]; then
    for c in "$DIR"/*.ctl "$DIR"/*.ctl.orig "$DIR"/*.initials.txt "$DIR"/*.R "$DIR"/*.rds; do
      [ -f "$c" ] || continue
      b=$(basename "$c")
      case "$b" in base_model.ctl|final_model.ctl|*_model.ctl|*_model.R) continue;; esac
      if [ ! -f "$SCREEN/$b" ]; then
        mv -f "$c" "$SCREEN/$b"; echo "CHAIN_MOVED $b -> $SCREEN/"
      elif cmp -s "$c" "$SCREEN/$b"; then
        rm -f "$c"; echo "CHAIN_DEDUPED $b (identical copy already in $SCREEN)"
      else
        case "$b" in *.ctl) t="$SCREEN/${b%.ctl}.fromroot.ctl";; *) t="$SCREEN/$b.fromroot";; esac
        mv -f "$c" "$t"; echo "CHAIN_MOVED $b -> $t (differs from the copy already in $SCREEN)"
      fi
    done
  fi
  i=1; LAD=""
  echo "CHAIN_BUDGET ladder_limit_s=$(qb_budget_ladder) stage_limit_s=$(qb_budget_stage) worker_timeout_s=$(qb_worker_timeout)"
  while [ "$i" -le "$JOBS" ]; do
    LAD=$(sh "$SELF/fit_ladder.sh" "$DIR" --family="$FAMILY" --data="$DATA" --models="$MODELS" --maxfit="$MAXFIT" --cores="${PMX_MC_CORES:-6}" --cand-max="$CAND_MAX" $([ "$MANUAL_SELECT" = 1 ] && echo --manual-select) --layout="$LAYOUT" --sync)
    printf '%s\n' "$LAD"
    case "$LAD" in
      *LADDER_OK*|*LADDER_PARTIAL*) break;;
      # Explicit pending evidence means follow the same live job. A finished timeout is not
      # a pending handoff and cannot authorize another screen or another foreground window.
      *LADDER_DEFER*|*RSUB_PENDING\ id=*)
        # A deferral is NOT a retry signal: the round is still running as its OWN job, so re-waiting
        # in this shell only burns the harness kill budget and ends in a SIGTERM with no output. Hand
        # the id back and stop: one command, resumable, cached.
        LADID=$(printf '%s\n' "$LAD" | sed -n 's/^LADDER_JOB //p' | head -1)
        echo "CHAIN_LADDER_JOB ${LADID:-unknown}"
        echo "CHAIN_LADDER_RUNNING the ladder round is STILL RUNNING as its own job; nothing was refitted and nothing is lost."
        echo "CHAIN_ATTACH node $SELF/r-submit.mjs --attach ${LADID:-<id>} --follow --summary"
        echo "CHAIN_RESUME start one BACKGROUND observer. On completion review selection once and follow LADDER_NEXT; never replay screening."
        echo "CHAIN_RESUME never loop --status: one look per 45s per id, then exit 5. Use --await/--attach."
        exit 3;;
      *LADDER_BLOCKED*|*RSUB_WORKER_TIMEOUT*) echo "CHAIN_BLOCKED screening job finished without an eligible completion handoff; preserve fits and review the terminal reason once" >&2; exit 1;;
      *LADDER_SCREEN_SET_CHANGED*) echo "CHAIN_STOP previous screening is complete; continue with its selected base without --screen. Do not append a promoted/refitted candidate." >&2; exit 4;;
      *LADDER_STOP*) echo "CHAIN_STOP screening ended without an eligible model; review ladder_table.csv, do not resubmit unchanged candidates"; exit 1;;
      *LADDER_NEEDS_SELECTION*) echo "CHAIN_NEEDS_SELECTION agent must record Candidate and scientific Reason in base_selection.dcf"; exit 2;;
      *) echo "CHAIN_FAIL screening produced no usable model" >&2; exit 1;;
    esac
  done
  case "$LAD" in *LADDER_OK*|*LADDER_PARTIAL*) ;; *) echo "CHAIN_PARTIAL screening unfinished" >&2; exit 1;; esac
fi
[ -f "$DIR/base_model.ctl" ] || { echo "CHAIN_NEEDS_MODELS author base_model.ctl or candidates using the available NCA digest or template starts, then resume"; exit 2; }
MIRROR="$DIR/.pmx/pmx_workspace"
# The container cannot see $WS, so the toolkit and the report stages are mirrored into the analysis
# dir. Staging is owned by analyses_template/tools/mirror_toolkit.sh - this script and fit_ladder.sh used to stage the
# SAME path from two different sources (analyses_template/tools/ + word-report/ here, analyses_template/tools/ only there), so each call
# wiped the other's subtree and a job needing $PMX_TOOLKIT/references/... saw nothing. One routine,
# one content stamp over the whole tree, complete or absent.
MIR=$(sh "$SELF/mirror_toolkit.sh" "$DIR")
case "$MIR" in
  *MIRROR_FAIL*) printf '%s\n' "$MIR"; echo "CHAIN_FAIL cannot stage the toolkit mirror" >&2; exit 1;;
esac
printf '%s\n' "$MIR" | grep '^MIRROR_SYNC'
HTOOLKIT_CONTAINER=$(printf '%s\n' "$MIR" | sed -n 's/^MIRROR_TOOLKIT //p' | head -1)
TEMPLATE="$WS/analyses_template/$FAMILY/${FAMILY}_report.Rmd"
[ -f "$TEMPLATE" ] || { echo "CHAIN_FAIL missing report template" >&2; exit 1; }
if [ ! -f "$HTMLD/${FAMILY}_report.Rmd" ] || [ "$REFRESH" = 1 ]; then cp "$TEMPLATE" "$HTMLD/"; fi
HSTAGES="$HDIR/.pmx/pmx_workspace/word-report/stages"
# A report stage runs inside ONE queue job, so its own guard must sit below the worker cap: the old
# 840 s default left nothing for the container and the result write, which is how a stage can be
# killed at the cap and read back as an empty render.
STAGE_TIMEOUT_S=$(qb_budget_stage) || exit 2
JOB="$DIR/.rsub_chain_$$.R"
trap 'rm -f "$JOB"' EXIT HUP INT TERM
{
  "$NODE" "$SELF/queue_env.mjs" PMX_STAGE_TIMEOUT "$STAGE_TIMEOUT_S" PMX_CHAIN_ONLY "$CHAIN_ONLY" PMX_CHAIN_FROM "$CHAIN_FROM"
  "$NODE" -e 'const q=JSON.stringify; console.log("Sys.setenv(PMX_ROOT="+q(process.argv[1])+",PMX_DATA="+q(process.argv[2])+",PMX_LAYOUT="+q(process.argv[3])+",STAGES_DIR="+q(process.argv[4])+")")' "$HDIR" "$HDATA" "$LAYOUT" "$HSTAGES"
  cat <<'R'
.pmx_wd <- Sys.getenv("PMX_ROOT")
for (.pmx_i in 1:20) {
  if (dir.exists(.pmx_wd)) break
  dir.create(.pmx_wd, recursive=TRUE, showWarnings=FALSE)
  Sys.sleep(0.5)
}
if (!dir.exists(.pmx_wd)) {
  cat("RSUB_CWD_UNRESOLVED ", .pmx_wd, "\n", sep="")
  quit(status=1)
}
setwd(.pmx_wd)
R
  printf 'FAM <- "%s"\n' "$FAMILY"
  cat <<'R'
source(file.path(Sys.getenv("STAGES_DIR"),"stage_lib.R"))
.here <- Sys.getenv("STAGES_DIR")
# Refuse overlapping/orphan fits from this study; never kill another job here.
.other <- suppressWarnings(as.integer(system2("pgrep",c("-x","R"),stdout=TRUE)))
.other <- .other[is.finite(.other) & .other != Sys.getpid()]
.busy <- .other[vapply(.other,function(p) system2("grep",
  c("-z","-F","-x","-q",shQuote(paste0("PMX_ROOT=",Sys.getenv("PMX_ROOT"))),
    shQuote(paste0("/proc/",p,"/environ"))),stdout=FALSE,stderr=FALSE)==0L,TRUE)]
if(length(.busy)) stop("CHAIN_ORPHAN_ACTIVE study=",Sys.getenv("PMX_ROOT")," pid=",paste(.busy,collapse=","),
  "; inspect and stop the owned old task; do not submit another fit")
.timeout <- Sys.which("timeout")
.cap <- suppressWarnings(as.numeric(Sys.getenv("PMX_STAGE_TIMEOUT","780")))
if(!nzchar(.timeout) || !is.finite(.cap) || .cap<=0) stop("CHAIN_TIMEOUT_UNAVAILABLE; no unbounded stage allowed")
# GNU timeout signals the complete owned process group, including nested Rscript children.
.only <- Sys.getenv("PMX_CHAIN_ONLY","")
.from <- Sys.getenv("PMX_CHAIN_FROM","")
Sys.setenv(PMX_STAGE_DEADLINE=as.character(as.numeric(Sys.time())+.cap))
st <- system2(.timeout,c("--signal=TERM","--kill-after=10s",paste0(.cap,"s"),"Rscript",
  shQuote(file.path(Sys.getenv("STAGES_DIR"),"run_stages.R")),shQuote(getwd()),"--family",FAM,
  "--job-window",if(nzchar(.only)) c("--only",.only),if(nzchar(.from)) c("--from",.from)))
if(st %in% c(124L,137L)) {
  cat("CHAIN_STAGE_TIMEOUT children terminated; retain caches and inspect the failed phase\n")
  if(stage_current("s1",FAM) && !stage_current("s1c",FAM))
    pmx_covariance_state("TIMED_OUT","Search estimates complete; covariance job timed out; no report completion")
}
if(st==0L && .only=="s1c") cat("CHAIN_COVARIANCE_DONE final uncertainty complete; full report may still be pending\n")
for(s in c("s1","s1c","s2","s4","s3","s5")) cat("CHAIN_GATE",s,if(stage_current(s,FAM)) "DONE" else "PENDING","\n")
quit(status=st)
R
} > "$JOB"
chmod a+r "$JOB"
chmod -R a+rX "$DIR/.pmx"
for generated in "$SCREEN" "$HTMLD" "$WORDD"; do
  [ "$generated" = "$DIR" ] || chmod -R a+rX "$generated"
done
SMB_UID=$(stat -c %u "$DIR")
SMB_GRP=$(stat -c %g "$DIR")
share_owner() {
  [ -n "${1:-}" ] || return 0
  [ -e "$1" ] || return 0
  if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
    chown -R "${PMX_SMB_UID:-$SMB_UID}:${PMX_SMB_GRP:-$SMB_GRP}" "$1" 2>/dev/null || true
  fi
  chmod -R g+rwX "$1" 2>/dev/null || true
}
share_owner "$DIR/.pmx"
for generated in "$SCREEN" "$HTMLD" "$WORDD"; do
  [ "$generated" = "$DIR" ] || share_owner "$generated"
done
# Editable configuration can be root:root 0600 after an atomic agent write.
# Repair only named configuration files, never original data or symlink targets.
for CONFIG in covariates.csv base_selection.dcf pmx_config.R report_metadata.dcf report_narrative.json; do
  [ -L "$DIR/$CONFIG" ] || share_owner "$DIR/$CONFIG"
done

if [ "$ASYNC" = 1 ]; then
  JID="chain_$(printf '%s' "$(basename "$DIR")" | tr -c 'A-Za-z0-9._-' '_')_$FAMILY"
  G=0
  "$NODE" "$SELF/queue_guard.mjs" "$DIR" || G=$?
  if [ "$G" = 3 ]; then
    echo "CHAIN_JOB_HOLD $JID dir=$DIR (queue_guard: no new job was queued -- see QUEUE_GUARD_BUSY/BACKOFF above)"
    exit 3
  fi
  [ "$G" = 0 ] || { echo "CHAIN_GUARD_ERROR exit=$G; no job submitted" >&2; exit "$G"; }
  RC=0; OUT=$("$NODE" "$SELF/r-submit.mjs" "$JOB" "$JID" 2>&1) || RC=$?
  printf '%s\n' "$OUT"
  ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
  [ -n "$ACTUAL" ] || ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
  if [ -z "$ACTUAL" ]; then
    echo "CHAIN_SUBMIT_FAIL no job id returned; no progress ledger was changed" >&2
    [ "$RC" != 0 ] || RC=2
    exit "$RC"
  fi
  printf '%s' "$CHAIN_SNAPSHOT" | "$NODE" "$SELF/chain_progress.mjs" record "$DIR" "$ACTUAL" || {
    echo "CHAIN_PROGRESS_ERROR job=$ACTUAL was submitted; follow this id, do not resubmit" >&2; exit 2;
  }
  echo "CHAIN_JOB $ACTUAL"
  echo "CHAIN_ATTACH $SELF/run_analysis.sh --attach $ACTUAL"
  echo "CHAIN_WAIT $SELF/r-submit.mjs --await $ACTUAL --max-wait-s=40   (one foreground fallback only; otherwise use CHAIN_ATTACH in background)"
  echo "CHAIN_STATUS $SELF/r-submit.mjs --status $ACTUAL   (POLL-BUDGETED: one look per 45s, repeated looks exit 5)   |  --tail $ACTUAL for incremental output"
  echo "CHAIN_ASYNC_READY start the single CHAIN_ATTACH background observer, record its id, then yield WAITING; completion must automatically continue this authorized workflow."
  echo "CHAIN_WAIT_FALLBACK if run_in_background is refused (no background job controller in this client), do NOT retry and do NOT sit in a blocking wait: take ONE bounded foreground window per queue id (node $SELF/r-submit.mjs --await $ACTUAL --max-wait-s=40)."
  echo "CHAIN_WAIT_FALLBACK NEVER loop CHAIN_STATUS/--status: it is poll-budgeted (one look per 45s per id; repeated looks exit 5; 4 unchanged looks CLOSE the window). Use --tail for progress. Configure background jobs and completion notifications in the agent client."
  exit "$RC"
fi
i=1; BEFORE_COUNT=0
while [ "$i" -le "$JOBS" ]; do
  if [ "$i" -gt 1 ]; then
    PROGRESS_RC=0
    CHAIN_SNAPSHOT=$("$NODE" "$SELF/chain_progress.mjs" check "$DIR" "$WS" "$DATA" "$FAMILY" "$LAYOUT" "$CHAIN_ONLY" "$CHAIN_FROM") || PROGRESS_RC=$?
    [ "$PROGRESS_RC" = 0 ] || exit "$PROGRESS_RC"
  fi
  RC=0; OUT=$("$NODE" "$SELF/r-submit.mjs" "$JOB" "chain_$$_$i" 2>&1) || RC=$?
  printf '%s\n' "$OUT"
  ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_JOB //p' | head -1)
  [ -n "$ACTUAL" ] || ACTUAL=$(printf '%s\n' "$OUT" | sed -n 's/^RSUB_DUPLICATE id=\([^ ]*\).*/\1/p' | head -1)
  if [ -n "$ACTUAL" ]; then
    printf '%s' "$CHAIN_SNAPSHOT" | "$NODE" "$SELF/chain_progress.mjs" record "$DIR" "$ACTUAL" || exit 2
    echo "CHAIN_JOB_RUNNING $ACTUAL; attach this id before any new submission" >&2
    # Written by the worker as it goes: keep the tree the share user's to delete while the chain runs.
    share_owner "$DIR/.pmx"
    exit 3
  fi
  if simulator_handoff; then exit 2; fi
  GATES=$(printf '%s\n' "$OUT" | grep '^CHAIN_GATE' | tr -d '\r')
  COUNT=$(printf '%s\n' "$GATES" | grep -c ' DONE$')
  if printf '%s\n' "$OUT" | grep -q '^NARRATIVE_REQUIRED'; then
    echo "CHAIN_NARRATIVE_REQUIRED structured report preserved; author Results/Discussion/Conclusion using node $SELF/report_narrative.mjs <study> --brief, validate, then resume --from=s5 (or --from=s4 for HTML); do not rerun fits"
    exit 4
  fi
  if [ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q '^CHAIN_COVARIANCE_DONE'; then echo "CHAIN_COVARIANCE_DONE $MODE_ID"; exit 0; fi
  if printf '%s\n' "$OUT" | grep -q '^STAGES_CHECKPOINT'; then echo "CHAIN_CHECKPOINT $MODE_ID - continue the next stage in a fresh job; do not repeat completed work"; exit 3; fi
  if printf '%s\n' "$OUT" | grep -q '^STAGES_DEFER stage '; then echo "CHAIN_DEFER $MODE_ID finished its window; continue the wrapper once with valid caches; do not reattach to this completed id"; exit 3; fi
  if [ "$RC" = 0 ] && [ "$COUNT" = 6 ]; then echo "CHAIN_DONE $DIR/${FAMILY}_report.html $DIR/${FAMILY}_report.docx"; share_owner "$DIR/.pmx"; exit 0; fi
  if printf '%s\n' "$OUT" | grep -q '^STAGES_CHECKPOINT'; then
    echo "CHAIN_CHECKPOINT next stage needs a fresh job; completed stages are preserved"; exit 3
  fi
  case "$RC" in 1|2|4|5) break;; esac
  # An explicit deferral is only a possible resume; the next iteration checks artifacts.
  # A worker timeout alone never counts as progress.
  PROGRESS=0
  printf '%s\n' "$OUT" | grep -q 'S1_DEFER\|SCM_DEFER\|STAGES_DEFER' && PROGRESS=1
  if [ "$PROGRESS" = 1 ] || [ "$COUNT" -gt "$BEFORE_COUNT" ]; then
    echo "CHAIN_RESUME saved artifacts will be checked before another submission" >&2
    BEFORE_COUNT="$COUNT"; i=$((i+1)); continue
  fi
  break
done
echo "CHAIN_PARTIAL no further verified progress; cached fits are preserved. Review the failed stage before another submission." >&2
exit 1
