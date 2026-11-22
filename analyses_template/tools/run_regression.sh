#!/bin/sh
set -u
FAM=${1:-}; shift
case "$FAM" in er) RMD=er_analysis.Rmd; HTML=er_analysis.html; LABEL=ER;; cqtc) RMD=cqtc_report.Rmd; HTML=cqtc_report.html; LABEL=CQTC;; *) exit 2;; esac
HERE=$(cd "$(dirname "$0")" && pwd); WS=$(cd "$HERE/../.." && pwd); NODE=${NODE:-node}
. "$HERE/queue_budget.sh" 2>/dev/null || true
DIR=""; DATA=""; WORD=1; WORD_ONLY=0; RERUN=0; TEMPLATE=""; CONFIG=""; COLLECT=""; WANT_COLLECT=0; STATE=0; ASYNC=0
for a in "$@"; do
  if [ "$WANT_COLLECT" = 1 ]; then COLLECT=$a; WANT_COLLECT=0; continue; fi
  case "$a" in
  --template=*) TEMPLATE=${a#--template=};; --config=*) CONFIG=${a#--config=};;
  --collect=*) COLLECT=${a#--collect=};;
  --collect) WANT_COLLECT=1;;
  --state) STATE=1;;
  --async) ASYNC=1;;
  --data=*) DATA=${a#--data=};; --no-word) WORD=0;;
  --word-only) WORD_ONLY=1;;
  # The deliberate override for the "already complete" stop (below): a plain rerun is a decision, never
  # a reflex. Without it, "the .docx is stale" leads back into a full render every time.
  --rerun) RERUN=1;;
  # The staging mirror now OUTLIVES this wrapper by design, so there is nothing left to keep: the flag
  # is accepted (and ignored) so older callers do not break.
  --keep-mirror) ;;
  -*) echo "Unknown option $a" >&2; exit 2;; *) [ -z "$DIR" ] || { echo "One analysis directory required" >&2; exit 2; }; DIR=$a;;
esac; done
[ "$WANT_COLLECT" = 0 ] || { echo "usage: run_$FAM.sh <analysis-dir> --collect=<job-id>" >&2; exit 2; }
[ -n "$DIR" ] || { echo "usage: run_$FAM.sh <analysis-dir> [--data=<file>] [--word-only] [--rerun] [--no-word] [--collect=<job-id>] [--state] [--async]" >&2; exit 2; }
if [ "$WORD_ONLY" = 1 ]; then
  [ "$WORD" = 1 ] || { echo "--word-only and --no-word contradict each other: a word-only refresh needs Word" >&2; exit 2; }
  WORD=1
fi
DIR=$(cd "$DIR" && pwd) || exit 2
SMB_UID=${PMX_SMB_UID:-$(stat -c %u "$DIR")}
SMB_GRP=${PMX_SMB_GRP:-$(stat -c %g "$DIR")}
BASE=$("$NODE" "$HERE/runtime_paths.mjs" queue) || exit 2; RES_DIR="$BASE/results"; LOG_DIR="$BASE/logs"

mirror_for_id() {
  for m in "$DIR"/.pmx/run_${FAM}_*/; do
    [ -d "$m" ] || continue
    [ -f "${m}.pmx_run_state" ] || continue
    grep -qx "ID=$1" "${m}.pmx_run_state" 2>/dev/null || continue
    printf '%s\n' "${m%/}"
    return 0
  done
  return 1
}

newest_complete_mirror() {
  # The most recent staging mirror whose job actually finished (.run_complete is written by the job as
  # its last act, so its presence means "this run produced its artifacts").
  newest=""
  for m in "$DIR"/.pmx/run_${FAM}_*/; do
    [ -f "${m}.run_complete" ] || continue
    if [ -z "$newest" ] || [ "$m" -nt "$newest" ]; then newest=$m; fi
  done
  [ -n "$newest" ] || return 1
  printf '%s\n' "${newest%/}"
}

result_status() {
  # "" (no result file yet) | ok | error | crashed | timeout
  [ -f "$1" ] || { printf '\n'; return 0; }
  tr -d '\n' < "$1" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([a-zA-Z]*\)".*/\1/p' | head -1
}

mirror_stage() {
  # $1 = STAGE, $2 = mirror, $3 = job id ("" -> PENDING). Rewrites .pmx_run_state; WORD/WORD_ONLY are
  # re-emitted so the --collect path keeps reading the mode of the submission that filled this mirror.
  # Called at EVERY stage transition, starting at mktemp time, so that a directory under
  # .pmx/run_<FAM>_* is never anonymous: "was a job ever queued for this?" has an answer on disk.
  { printf 'ID=%s\n' "${3:-PENDING}"
    printf 'STAGE=%s\n' "$1"
    printf 'MIRROR=%s\nDIR=%s\nPID=%s\nTIME=%s\n' "$2" "$DIR" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    [ "$WORD" = 1 ] || printf 'WORD=0\n'
    [ "$WORD_ONLY" = 0 ] || printf 'WORD_ONLY=1\n'; } > "$2/.pmx_run_state" 2>/dev/null || true
}

share_owner() {
  # $1 = a directory tree under .pmx. Hand it to the share user (see SMB_UID/SMB_GRP at the top) so the
  # owner of the share can read, write AND DELETE it: root-owned directories are what made `rm -rf
  # <study>/.pmx` fail for the SMB user. chown is root-only; a non-root caller just gets the chmod, so
  # this is safe to call from anywhere. Never fatal: a permission fix must not fail a run.
  [ -n "${1:-}" ] || return 0
  [ -e "$1" ] || return 0
  if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
    chown -R "$SMB_UID:$SMB_GRP" "$1" 2>/dev/null || true
  fi
  chmod -R g+rwX "$1" 2>/dev/null || true
  return 0
}

state_report() {
  D=$1
  DETAILS=""
  state_detail() { DETAILS="$DETAILS$(printf "$@")
"; }
  STATE_MAN="$D/output/run_manifest.json"
  [ -f "$STATE_MAN" ] || STATE_MAN="$D/run_manifest.json"
  N_MIR=0; N_DEBRIS=0; N_QUEUED=0
  BEST=NOT_RUN; RANK=1; BEST_ID=""; BEST_DIR=""
  MIRRORS=$(ls -1dt "$D"/.pmx/run_${FAM}_* 2>/dev/null)
  while IFS= read -r m; do
    [ -d "$m" ] || continue
    N_MIR=$((N_MIR+1))
    mid=$(sed -n 's/^ID=//p' "$m/.pmx_run_state" 2>/dev/null | head -1)
    stg=$(sed -n 's/^STAGE=//p' "$m/.pmx_run_state" 2>/dev/null | head -1)
    [ -n "$stg" ] || stg=nostate
    if [ ! -f "$m/.pmx_run_state" ]; then
      N_DEBRIS=$((N_DEBRIS+1))
      state_detail 'RUN_MIRROR_ORPHAN %s has no .pmx_run_state: it was created by a hand-built job or by a wrapper that died before staging. Nothing will ever be written into it (collect/await cannot address it) and it is swept automatically = IGNORE IT.\n' "$m"
      [ "$RANK" -lt 2 ] && { RANK=2; BEST=DEBRIS; BEST_DIR=$m; }
      continue
    fi
    case "$mid" in
      ""|PENDING)
        N_DEBRIS=$((N_DEBRIS+1))
        state_detail 'RUN_MIRROR_NEVER_QUEUED %s stage=%s no job id was ever assigned, so no worker will ever write here (= IGNORE IT; swept by age).\n' "$m" "$stg"
        [ "$RANK" -lt 3 ] && { RANK=3; BEST=NEVER_QUEUED; BEST_DIR=$m; }
        ;;
      *)
        N_QUEUED=$((N_QUEUED+1))
        st=$(result_status "$RES_DIR/$mid.json")
        # "Already published from this mirror" == the published HTML is not older than the mirror's.
        # Without this test a collected run would read as UNPUBLISHED for the rest of the day and send
        # the caller back to --collect for a report that is already in the analysis directory.
        if [ -f "$m/$HTML" ] && [ -f "$D/${LABEL}_report.html" ] && [ ! "$m/$HTML" -nt "$D/${LABEL}_report.html" ]; then
          state_detail 'RUN_MIRROR_COLLECTED %s id=%s status=%s and already published into %s (= IGNORE IT; swept by age).\n' "$m" "$mid" "$st" "$D"
          continue
        fi
        if [ -z "$st" ] && [ -f "$m/.run_complete" ]; then
          state_detail 'RUN_MIRROR_FINISHED %s id=%s wrote .run_complete but the result file %s/%s.json is absent: staging is intact, publish it directly: sh %s/run_%s.sh %s --collect=%s\n' "$m" "$mid" "$RES_DIR" "$mid" "$HERE" "$FAM" "$D" "$mid"
          [ "$RANK" -lt 5 ] && { RANK=5; BEST=UNPUBLISHED; BEST_ID=$mid; BEST_DIR=$m; }
        elif [ -z "$st" ]; then
          state_detail 'RUN_MIRROR_RUNNING %s id=%s queued or running: DO NOT resubmit.\n  progress: node %s/r-submit.mjs --tail %s\n  collect:  sh %s/run_%s.sh %s --collect=%s\n' "$m" "$mid" "$HERE" "$mid" "$HERE" "$FAM" "$D" "$mid"
          [ "$RANK" -lt 6 ] && { RANK=6; BEST=RUNNING; BEST_ID=$mid; BEST_DIR=$m; }
        elif [ "$st" = ok ]; then
          state_detail 'RUN_MIRROR_UNPUBLISHED %s id=%s status=ok but its artifacts are not published: publish them with NO worker time: sh %s/run_%s.sh %s --collect=%s\n' "$m" "$mid" "$HERE" "$FAM" "$D" "$mid"
          [ "$RANK" -lt 5 ] && { RANK=5; BEST=UNPUBLISHED; BEST_ID=$mid; BEST_DIR=$m; }
        else
          if [ -f "$STATE_MAN" ] && [ "$STATE_MAN" -nt "$m/.pmx_run_state" ]; then
            state_detail 'RUN_MIRROR_SUPERSEDED %s id=%s status=%s\n' "$m" "$mid" "$st"
            continue
          fi
          state_detail 'RUN_MIRROR_FAILED %s id=%s status=%s\n' "$m" "$mid" "$st"
          [ "$RANK" -lt 5 ] && { RANK=5; BEST=FAILED; BEST_ID=$mid; BEST_DIR=$m; }
        fi
        ;;
    esac
  done <<EOF
$MIRRORS
EOF
  REPORT_STATE=$(sed -n 's/.*"report_state": *"\([^"]*\)".*/\1/p' "$STATE_MAN" 2>/dev/null | head -1)
  if [ -z "$REPORT_STATE" ]; then
    LEGACY_PROSE=$(sed -n 's/.*"prose": *{"state": *"\([^"]*\)".*/\1/p' "$STATE_MAN" 2>/dev/null | head -1)
    case "$LEGACY_PROSE" in absent) REPORT_STATE=needs_narrative;; stale|dropped) REPORT_STATE=review_required;; esac
  fi
  case "$BEST" in
    RUNNING)      printf 'RUN_STATE RUNNING id=%s mirror=%s\n' "$BEST_ID" "$BEST_DIR";;
    FAILED)       printf 'RUN_STATE FAILED id=%s mirror=%s\n' "$BEST_ID" "$BEST_DIR";;
    UNPUBLISHED)  printf 'RUN_STATE UNPUBLISHED id=%s mirror=%s\n' "$BEST_ID" "$BEST_DIR";;
    NEVER_QUEUED) printf 'RUN_STATE NEVER_QUEUED mirror=%s\n' "$BEST_DIR";;
    DEBRIS)       printf 'RUN_STATE DEBRIS mirror=%s\n' "$BEST_DIR";;
    *)
      if [ -f "$STATE_MAN" ]; then
        case "$REPORT_STATE" in
          needs_narrative) printf 'RUN_STATE NARRATIVE_REQUIRED dir=%s analysis=complete\n' "$D";;
          review_required) printf 'RUN_STATE NARRATIVE_REVIEW_REQUIRED dir=%s analysis=complete\n' "$D";;
          needs_word_runtime) printf 'RUN_STATE WORD_RUNTIME_REQUIRED dir=%s analysis=complete\n' "$D";;
          *) printf 'RUN_STATE COMPLETE dir=%s\n' "$D";;
        esac
      else printf 'RUN_STATE NOT_RUN dir=%s\n' "$D"; fi;;
  esac
  printf '%s' "$DETAILS"
  printf 'RUN_STATE_COUNTS mirrors=%s queued=%s debris=%s\n' "$N_MIR" "$N_QUEUED" "$N_DEBRIS"
  case "$BEST" in
    RUNNING)     printf 'RUN_STATE_NEXT BACKGROUND node "%s/r-submit.mjs" --attach "%s" --follow --summary; collect the returned job after completion.\n' "$HERE" "$BEST_ID";;
    FAILED)      printf 'RUN_STATE_NEXT node "%s/r-submit.mjs" --result "%s" --summary\n' "$HERE" "$BEST_ID";;
    UNPUBLISHED) printf 'RUN_STATE_NEXT sh "%s/run_%s.sh" "%s" --collect=%s\n' "$HERE" "$FAM" "$D" "$BEST_ID";;
    NEVER_QUEUED|DEBRIS)
                 printf 'RUN_STATE_NEXT prepare missing study configuration once, then submit: sh "%s/run_%s.sh" "%s" --async\n' "$HERE" "$FAM" "$D";;
    *)
      if [ -f "$STATE_MAN" ]; then
        case "$REPORT_STATE" in
          needs_narrative) printf 'RUN_STATE_NEXT node "%s/report_narrative.mjs" "%s" --brief; author both sections, validate, then --word-only --async once.\n' "$HERE" "$D";;
          review_required) printf 'RUN_STATE_NEXT read %s and review current prose/evidence; do not repeat an unchanged job.\n' "$STATE_MAN";;
          needs_word_runtime) printf 'RUN_STATE_NEXT read %s; repair the Word runtime, preserve completed analysis.\n' "$STATE_MAN";;
          *) printf 'RUN_STATE_NEXT STOP: the requested report is complete. Reply with deliverables and recorded warnings, then end this turn. No further file probes or submissions. Explicit user-requested document review is a separate goal.\n';;
        esac
      else printf 'RUN_STATE_NEXT prepare missing study configuration once, then submit: sh "%s/run_%s.sh" "%s" --async\n' "$HERE" "$FAM" "$D"; fi;;
  esac
  return 0
}

# The ONE value a study's prose must carry. word-report/result_narrative.R accepts report_narrative.json
# only when its source_md5 equals md5(output/report_results.rds); on any mismatch it drops the prose
# SILENTLY (the sections just come out generated). Print the command, not a hash, when there is no md5sum.
rds_md5() {
  if command -v md5sum >/dev/null 2>&1 && [ -f "$1" ]; then md5sum "$1" | cut -d' ' -f1
  else printf '<run: md5sum %s>' "$1"; fi
}

# Minimal JSON string escaping for run_manifest.json (below): a path or a warning sample can contain a
# quote or a newline, and the manifest is meant to be parsed, not skimmed.
jesc() {
  printf '%s' "$1" | tr -d '\r' | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# One artifact entry for the manifest: {"path":…,"bytes":N,"md5":"…"}, or null when absent.
artifact_field() { # $1 = json key, $2 = path
  if [ -f "$2" ]; then
    printf '"%s": {"path": "%s", "bytes": %s, "md5": "%s"}' "$1" "$(jesc "$2")" "$(wc -c < "$2" | tr -d ' ')" "$(rds_md5 "$2")"
  else
    printf '"%s": null' "$1"
  fi
}

publish() {
  # $1 = mirror, $2 = job id (informational)
  MIR=$1
  WORD_ENV_BROKEN=0
  if [ -s "$MIR/.word_env_broken" ]; then
    WORD_ENV_BROKEN=1
    cat "$MIR/.word_env_broken" >&2
    echo "${LABEL}_WORD_SKIPPED Word was not built: the worker image cannot load officer/ragg (line above). The HTML was rendered and IS being published. This is an image/system-library defect -- fix the image (see analyses_template/tools/preflight_word.sh), do NOT resubmit the analysis job; a resubmission changes nothing." >&2
  fi
  cp "$MIR/$HTML" "$DIR/${LABEL}_report.html" || exit 1
  if [ "$WORD" = 1 ] && [ "$WORD_ENV_BROKEN" = 0 ] && [ -f "$MIR/${LABEL}_report.docx" ]; then
    cp "$MIR/${LABEL}_report.docx" "$DIR/${LABEL}_report.docx" || exit 1
  fi
  for d in figure table; do
    [ -d "$MIR/$d" ] || continue
    # Replace only these generated artifact directories; do not merge old run assets.
    [ ! -L "$DIR/$d" ] || { echo "Refusing generated-output symlink $DIR/$d" >&2; exit 1; }
    new="$DIR/.pmx_publish_${d}_$$"; previous="$DIR/.pmx_previous_${d}_$$"
    [ ! -e "$new" ] && [ ! -e "$previous" ] || exit 1
    cp -a "$MIR/$d" "$new" || exit 1
    if [ -e "$DIR/$d" ]; then mv "$DIR/$d" "$previous" || exit 1; fi
    if ! mv "$new" "$DIR/$d"; then [ ! -e "$previous" ] || mv "$previous" "$DIR/$d"; exit 1; fi
    case "$previous" in "$DIR"/.pmx_previous_*) rm -rf -- "$previous";; *) exit 1;; esac
  done
  # An absent or STALE narrative is silent in the generator (it gates on source_md5 and simply omits the
  # prose), so "edit the file, re-render, still no prose, no reason anywhere" is a loop the log never
  # breaks. Name it here, with the one value that has to match.
  "$NODE" "$HERE/regression_layout.mjs" publish "$MIR" "$DIR" "$RMD" "$(sed -n 's/^data=//p' "$MIR/.pmx_staged" | head -1)" || exit 1
  PUBLISHED_RDS="$DIR/output/report_results.rds"
  [ -f "$PUBLISHED_RDS" ] || PUBLISHED_RDS="$DIR/report_results.rds"
  NARR_STATE=none; NARR_REASON=""; NARR_FILE=""
  if [ "$WORD" = 1 ]; then
    RDS="$DIR/output/report_results.rds"
    [ -f "$RDS" ] || RDS="$DIR/report_results.rds"
    NARR_STATE=ok
    [ -f "$MIR/report_narrative.json" ] || NARR_STATE=absent
    NARR_TOK=$(grep -ho 'NARRATIVE_\(STALE\|ABSENT\|INCOMPLETE\|BAD_SECTION_RESULTS\|NO_EVIDENCE\|BAD_EVIDENCE\|CHANGED_EVIDENCE\|MISSING_EVIDENCE\|PARSE\|UNREADABLE\|NO_RESULT\|NO_RDS\)[^ ]*' \
                 "$LOG_DIR/$2.out" "$LOG_DIR/$2.err" 2>/dev/null | head -1)
    NARR_FILE=$(grep -ho 'NARRATIVE_\(CHANGED_EVIDENCE\|MISSING_EVIDENCE\|BAD_EVIDENCE\)[[:space:]][^[:space:]]*' \
                 "$LOG_DIR/$2.out" "$LOG_DIR/$2.err" 2>/dev/null | head -1 | awk '{print $2}')
    if [ -n "$NARR_TOK" ] && [ "$NARR_TOK" != "NARRATIVE_OK" ]; then
      NARR_REASON=${NARR_TOK#NARRATIVE_}
      NARR_STATE=dropped
      echo "${LABEL}_NARRATIVE_DROPPED ${LABEL}_report.docx was published WITHOUT the study prose: $NARR_TOK${NARR_FILE:+ $NARR_FILE}" >&2
      [ "$NARR_REASON" = STALE ] && echo "${LABEL}_NARRATIVE_STALE (kept for callers that grep the older token) report_narrative.json source_md5 != md5($RDS)" >&2
      case "$NARR_REASON" in
        STALE)
          echo "  the staged report_narrative.json source_md5 does not match the current $RDS" >&2
          echo "  next: re-read current evidence with node $HERE/report_narrative.mjs $DIR --brief and rewrite both sections; never update source_md5 alone, then:" >&2
          echo "  sh $HERE/run_$FAM.sh $DIR --word-only" >&2;;
        CHANGED_EVIDENCE|MISSING_EVIDENCE|BAD_EVIDENCE)
          echo "  an evidence entry in report_narrative.json does not match the file on disk (they are transcriptions of the published files, so they can be rebuilt exactly)." >&2
          echo "  next: node $HERE/check_narrative.mjs $DIR --fix-evidence" >&2
          echo "  then: sh $HERE/run_$FAM.sh $DIR --word-only" >&2;;
        *)
          echo "  next: fix report_narrative.json and re-check it BEFORE spending a queue slot:" >&2
          echo "  node $HERE/check_narrative.mjs $DIR" >&2;;
      esac
    elif [ ! -f "$MIR/report_narrative.json" ] && [ -f "$RDS" ]; then
      echo "${LABEL}_NARRATIVE_ABSENT ${LABEL}_report.docx published without a staged report_narrative.json: it carries generated prose only" >&2
      echo "  next: write $DIR/report_narrative.json with \"source_md5\":\"$(rds_md5 "$RDS")\" ($RDS), then:" >&2
      echo "  sh $HERE/run_$FAM.sh $DIR --word-only" >&2
    fi
  fi
  WARN_N=0; WARN_CLASS=none; WARN_SAMPLE=""
  if [ -f "$LOG_DIR/$2.err" ]; then
    WARN_N=$(grep -ci 'warning' "$LOG_DIR/$2.err" 2>/dev/null) || WARN_N=0
    WARN_SAMPLE=$(grep -i -m1 -A1 'warning' "$LOG_DIR/$2.err" 2>/dev/null | tr '\n' ' ')
    if grep -q 'relationship file contains invalid id' "$LOG_DIR/$2.err" 2>/dev/null; then WARN_CLASS=template_layout; fi
  fi
  if [ "$WARN_CLASS" = template_layout ]; then
    echo "${LABEL}_TEMPLATE_WARNING the report was generated, but the reference.docx carries invalid relationship id(s) (e.g. footer1.xml): a LAYOUT defect of the template, not a generation failure. Re-rendering WILL NOT clear it -- check the template's document structure (unzip the .docx, compare footer/header rels) instead of running the pipeline again." >&2
  fi
  # ------------------------------------------------- structured completion record ----------------
  # Five sessions answered "is another run still needed?" by reading logs. The answer is a file:
  # status, artifacts, inputs, warnings and the ONE conclusion, written when the run is accepted.
  # `conclusion` is the line a model can read instead of re-deriving the state from five artifacts.
  STAGED_DATA=$(sed -n 's/^data=//p' "$MIR/.pmx_staged" 2>/dev/null | head -1)
  [ -n "$STAGED_DATA" ] || STAGED_DATA=$(basename "$DATA" 2>/dev/null || printf '')
  CONC="run ok; ${LABEL}_report.html published"
  if [ "$WORD_ENV_BROKEN" = 1 ]; then CONC="$CONC; Word NOT built (worker image cannot load officer/ragg)"
  elif [ "$WORD_ONLY" = 1 ]; then CONC="$CONC; ${LABEL}_report.docx refreshed from the published HTML (no render, no refit)"
  elif [ "$WORD" = 1 ] && [ -f "$DIR/${LABEL}_report.docx" ]; then CONC="$CONC; ${LABEL}_report.docx published"
  fi
  case "$NARR_STATE" in
    stale)  CONC="$CONC WITHOUT the study prose (report_narrative.json source_md5 is stale)";;
    absent) CONC="$CONC without a staged report_narrative.json (generated prose only)";;
    dropped) CONC="$CONC WITHOUT the study prose (narrative gate: $NARR_REASON${NARR_FILE:+ on $NARR_FILE})";;
  esac
  [ "$WARN_CLASS" = none ] || CONC="$CONC; open template-layout warning (re-rendering will not clear it)"
  mkdir -p "$DIR/output" || exit 1
  MAN="$DIR/output/run_manifest.json"
  TMPMAN="$DIR/output/.pmx_manifest_$$"
  {
    printf '{\n'
    printf '  "schema": 1,\n'
    printf '  "status": "ok",\n'
    printf '  "family": "%s",\n' "$FAM"
    printf '  "analysis_state": "complete",\n'
    printf '  "report_state": "%s",\n' "$(
      if [ "$WORD" = 0 ]; then printf html_only
      elif [ "$WORD_ENV_BROKEN" = 1 ]; then printf needs_word_runtime
      elif [ "$NARR_STATE" = absent ] || [ "$NARR_STATE" = none ]; then printf needs_narrative
      elif [ "$NARR_STATE" = dropped ] || [ "$NARR_STATE" = stale ]; then printf review_required
      else printf complete; fi)"
    printf '  "template_origin": "%s",\n' "$(cat "$MIR/.pmx_template_origin" 2>/dev/null || printf toolkit)"
    printf '  "mode": "%s",\n' "$( [ "$WORD_ONLY" = 1 ] && printf 'word-only' || printf 'render' )"
    printf '  "job": "%s",\n' "$2"
    printf '  "dir": "%s",\n' "$(jesc "$DIR")"
    printf '  "mirror": "%s",\n' "$(jesc "$MIR")"
    printf '  "completed_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf unknown)"
    printf '  "conclusion": "%s",\n' "$(jesc "$CONC")"
    printf '  "artifacts": {\n    '
    artifact_field report_html "$DIR/${LABEL}_report.html"; printf ',\n    '
    artifact_field report_docx "$DIR/${LABEL}_report.docx"; printf ',\n    '
    artifact_field evidence "$DIR/output/report_evidence.json"; printf ',\n    '
    artifact_field context "$DIR/output/report_context.json"; printf ',\n    '
    artifact_field results_rds "$PUBLISHED_RDS"; printf '\n  },\n'
    printf '  "inputs": {\n    '
    artifact_field data "$MIR/$STAGED_DATA"; printf ',\n    '
    artifact_field template "$MIR/$RMD"; printf ',\n    '
    artifact_field narrative "$DIR/report_narrative.json"; printf ',\n    '
    artifact_field metadata "$DIR/report_metadata.dcf"; printf ',\n    '
    artifact_field config "$MIR/pmx_config.R"; printf '\n  },\n'
    if [ "$NARR_STATE" = dropped ]; then
      printf '  "prose": {"state": "%s", "reason": "%s", "file": "%s", "source_md5_expected": "%s", "fix": "%s"},\n' \
        "$NARR_STATE" "$NARR_REASON" "$(jesc "$NARR_FILE")" "$(rds_md5 "$PUBLISHED_RDS")" \
        "$(jesc "$( [ "$NARR_REASON" = STALE ] && printf 're-read current evidence and rewrite both sections before --word-only; never update source_md5 alone' || printf "node analyses_template/tools/check_narrative.mjs <dir> --fix-evidence, then --word-only" )")"
    else
      printf '  "prose": {"state": "%s", "source_md5_expected": "%s"},\n' "$NARR_STATE" "$(rds_md5 "$PUBLISHED_RDS")"
    fi
    printf '  "counts": {"tables": %s, "figures": %s},\n' \
      "$(find "$DIR/table" -type f 2>/dev/null | wc -l | tr -d ' ')" \
      "$(find "$DIR/figure" -type f 2>/dev/null | wc -l | tr -d ' ')"
    printf '  "warnings": {"count": %s, "class": "%s", "sample": "%s", "regeneration_helps": %s},\n' \
      "$WARN_N" "$WARN_CLASS" "$(jesc "$WARN_SAMPLE")" \
      "$( [ "$WARN_CLASS" = none ] && printf true || printf false )"
    printf '  "toolkit": {"path": "%s", "wrapper_cksum": "%s"},\n' "$(jesc "$WS")" "$(cksum "$HERE/run_regression.sh" 2>/dev/null | tr -s ' ' | tr ' ' ':' | sed 's/:$//')"
    printf '  "next_step": "%s"\n' "$( case "$NARR_STATE" in
      dropped) printf 'prose was dropped (%s%s): fix report_narrative.json, then --word-only' "$NARR_REASON" "${NARR_FILE:+ on $NARR_FILE}";;
      absent) printf 'node analyses_template/tools/report_narrative.mjs <dir> --brief; author both sections, validate, then --word-only';;
      stale) printf 're-read current evidence and rewrite the interpretation before --word-only; never update source_md5 alone';;
      *) printf 'none: the published artifacts are current';; esac )"
    printf '}\n'
  } > "$TMPMAN" 2>/dev/null && mv "$TMPMAN" "$MAN" 2>/dev/null && chmod a+r "$MAN" 2>/dev/null || rm -f "$TMPMAN" 2>/dev/null
  echo "${LABEL}_MANIFEST $MAN (status=ok conclusion=\"$CONC\")"
  if [ "$WORD" = 1 ] && [ "$NARR_STATE" = absent ]; then
    echo "${LABEL}_NARRATIVE_REQUIRED analysis is complete; author Discussion and Conclusion before final delivery. Do not rerun the analysis or queue an R job to read its results."
    echo "  node $HERE/report_narrative.mjs $DIR --brief"
  fi
  # The job's own directories (output/ table/ figure/ and anything the Word step created) come back owned
  # by the WORKER, which chmods them 0755 (see the Sys.chmod block in the job script). Left that way, the
  # SMB user can read them but not delete the mirror. Hand the finished tree to the share user NOW, while
  # this process is still root -- this is the "SMB access to .pmx" fix, on the success path.
  share_owner "$MIR"
  echo "PMX_SHARE $MIR staging retained"
  mirror_stage published "$MIR" "$2"
  echo "MIRROR_KEPT $MIR (staged for job $2; swept by age once finished)"
  if [ "${WORD_ENV_BROKEN:-0}" = 1 ]; then
    echo "${LABEL}_HTML_OK_WORD_SKIPPED $DIR (image cannot load officer/ragg: ${LABEL}_report.html published, ${LABEL}_report.docx not built)"
  elif [ "$WORD_ONLY" = 1 ]; then
    echo "${LABEL}_RUN_OK $DIR (word-only refresh: published HTML reused, no render, no refit)"
  else
    echo "${LABEL}_RUN_OK $DIR"
  fi
}

# --------------------------------------------------- state (read-only; answers, does not submit) ----
if [ "$STATE" = 1 ]; then
  state_report "$DIR"
  exit 0
fi

# ------------------------------------------------------------------ collect an in-flight job ----
if [ -n "$COLLECT" ]; then
  MIRROR=$(mirror_for_id "$COLLECT") || {
    echo "${LABEL}_COLLECT_UNKNOWN no staging mirror for job $COLLECT under $DIR/.pmx (it may have been swept by age, or the job belongs to another study dir)" >&2
    # "UNKNOWN" used to be the last word, which is how a session ends up `ls`-ing .pmx/run_* forever:
    # the id is unknown, but the STATE of the study is not. Answer it, and say what the leftovers are.
    state_report "$DIR" >&2
    exit 1; }
  ID=$COLLECT
  if [ -f "$MIRROR/.pmx_run_state" ]; then
    grep -q '^WORD=0' "$MIRROR/.pmx_run_state" && WORD=0
    grep -q '^WORD_ONLY=1' "$MIRROR/.pmx_run_state" && WORD_ONLY=1
  fi
else
  if [ -z "$DATA" ]; then
    for f in "$DIR"/*.csv; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in covariates.csv|data_spec.csv|nca_initials.csv|tbl_*.csv|html_tbl_*.csv|ladder_table.csv|labels.csv|endpoints.csv|safety_endpoints.csv) continue;; esac
      [ -z "$DATA" ] || { echo "Several CSV files; pass --data" >&2; exit 2; }
      DATA=$f
    done
  fi
  case "$DATA" in /*) ;; *) DATA="$DIR/$DATA";; esac
  [ -f "$DATA" ] || { echo "Missing data file $DATA" >&2; exit 2; }
  DATA_NAME=$(basename "$DATA")
  # Resolve identical input paths for the content guard and staging.
  if [ -z "$TEMPLATE" ]; then
    TEMPLATE=$("$NODE" "$HERE/regression_layout.mjs" select-template "$DIR" "$WS/analyses_template/$FAM/$RMD" "$RMD") || exit 1
  fi
  if [ "$WORD_ONLY" = 1 ] && [ -f "$DIR/$RMD" ]; then TEMPLATE="$DIR/$RMD"; fi
  case "$TEMPLATE" in /*) ;; *) TEMPLATE="$DIR/$TEMPLATE";; esac
  TEMPLATE_ORIGIN=study
  [ "$TEMPLATE" != "$WS/analyses_template/$FAM/$RMD" ] || TEMPLATE_ORIGIN=toolkit
  if [ -z "$CONFIG" ] && [ -f "$DIR/pmx_config.R" ]; then CONFIG="$DIR/pmx_config.R"; fi
  if [ -n "$CONFIG" ]; then case "$CONFIG" in /*) ;; *) CONFIG="$DIR/$CONFIG";; esac; fi
  if [ "$RERUN" = 0 ]; then
    COMPLETE_RC=0
    COMPLETE_OUT=$("$NODE" "$HERE/check_report_complete.mjs" "$DIR" "$FAM" "$DATA" "$TEMPLATE" "$CONFIG" "$WORD" 2>&1) || COMPLETE_RC=$?
    case "$COMPLETE_RC" in
      0) echo "${LABEL}_ALREADY_COMPLETE $COMPLETE_OUT"
         echo "${LABEL}_NEXT_STEP none: read $DIR/output/run_manifest.json; review template warnings separately."
         exit 0;;
      3) if [ "$WORD_ONLY" = 0 ]; then
           echo "${LABEL}_WORD_REFRESH_REQUIRED $COMPLETE_OUT" >&2
           echo "  sh $HERE/run_$FAM.sh $DIR --word-only" >&2
           exit 2
         fi;;
      4) echo "${LABEL}_NARRATIVE_REVIEW_REQUIRED $COMPLETE_OUT" >&2; exit 2;;
      5) echo "${LABEL}_NARRATIVE_REQUIRED $COMPLETE_OUT"
         echo "  node $HERE/report_narrative.mjs $DIR --brief"
         echo "  Author both sections; validate and use --word-only once. No analysis submission is needed."
         exit 0;;
    esac
  fi
  if [ "$WORD_ONLY" = 0 ] && [ "$RERUN" = 0 ]; then
    PUB_HTML="$DIR/${LABEL}_report.html"
    DONE_MIR=$(newest_complete_mirror) || DONE_MIR=""
    MIR_INPUTS_OK=1
    if [ -n "$DONE_MIR" ]; then
      cmp -s "$DATA" "$DONE_MIR/$DATA_NAME" || MIR_INPUTS_OK=0
      cmp -s "$TEMPLATE" "$DONE_MIR/$RMD" || MIR_INPUTS_OK=0
      for opt in report_narrative.json report_metadata.dcf pmx_config.R; do
        CURRENT="$DIR/$opt"
        [ "$opt" != pmx_config.R ] || [ -z "$CONFIG" ] || CURRENT="$CONFIG"
        if [ -f "$CURRENT" ] || [ -f "$DONE_MIR/$opt" ]; then
          cmp -s "$CURRENT" "$DONE_MIR/$opt" || MIR_INPUTS_OK=0
        fi
      done
    fi
    if [ -n "$DONE_MIR" ] && [ "$MIR_INPUTS_OK" = 1 ]; then
      MIR_HTML="$DONE_MIR/$HTML"
      if [ -f "$MIR_HTML" ] && { [ ! -f "$PUB_HTML" ] || [ "$MIR_HTML" -nt "$PUB_HTML" ]; }; then
        MID=$(sed -n 's/^ID=//p' "$DONE_MIR/.pmx_run_state" 2>/dev/null | head -1)
        if [ -n "$MID" ] && [ "$(result_status "$RES_DIR/$MID.json")" = ok ]; then
          echo "${LABEL}_COLLECT_FINISHED the finished run $MID in $DONE_MIR produced a $HTML that is not published yet; publishing it instead of rendering again (no worker time is used)" >&2
          MIRROR="$DONE_MIR"; ID="$MID"
          grep -q '^WORD=0' "$DONE_MIR/.pmx_run_state" && WORD=0
          grep -q '^WORD_ONLY=1' "$DONE_MIR/.pmx_run_state" && WORD_ONLY=1
          publish "$MIRROR" "$ID"
          exit 0
        fi
      fi
    fi
  fi
  mkdir -p "$DIR/.pmx" 2>/dev/null || true
  chmod a+rx "$DIR/.pmx" 2>/dev/null || true
  # Sweep only finished or idle mirrors belonging to this study.
  find "$DIR/.pmx" -maxdepth 1 -type d -name "run_${FAM}_*" -mmin +60 \
       -exec sh -c 'test -f "$1/.run_complete"' _ {} \; -exec rm -rf {} + 2>/dev/null || true
  find "$DIR/.pmx" -maxdepth 1 -type d -name "run_${FAM}_*" -mmin +60 -exec sh -c '
    for d in "$@"; do
      [ -f "$d/.run_complete" ] && continue
      if [ ! -f "$d/.pmx_run_state" ]; then rm -rf "$d"; continue; fi
      id=$(sed -n "s/^ID=//p" "$d/.pmx_run_state" 2>/dev/null | head -1)
      case "$id" in ""|PENDING) rm -rf "$d";; esac
    done' _ {} + 2>/dev/null || true
  find "$DIR/.pmx" -maxdepth 1 -type d -name "run_${FAM}_*" -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
  G=0
  "$NODE" "$HERE/queue_guard.mjs" "$DIR" || G=$?
  if [ "$G" = 3 ]; then
    # The hold printed the id to follow / the log to read. Nothing has been staged or submitted at this
    # point, so there is no mirror to mark and no request to clean up. Exit 3 is the "still running,
    # nothing lost" state the caller already understands, so a gate hold is never read as a failed run.
    echo "${LABEL}_JOB_RUNNING (queue_guard hold; no new job was queued and no staging directory was created -- see QUEUE_GUARD_BUSY/BACKOFF above)" >&2
    exit 3
  fi
  NARRV=0
  NARR_OUT=$( { "$NODE" "$HERE/check_narrative.mjs" "$DIR" --fix-evidence --require-discussion-conclusion 2>&1; } ) || NARRV=$?
  printf '%s\n' "$NARR_OUT"
  case "$NARR_OUT" in *NARRATIVE_CHECK_FIXED*)
    echo "${LABEL}_NARRATIVE_REPAIRED an evidence hash in $DIR/report_narrative.json did not match its file; the hash was rebuilt from the file on disk and the repaired file is what this job stages. source_md5 was not touched." >&2;;
  esac
  if [ "$NARRV" != 0 ]; then
    echo "${LABEL}_NARRATIVE_REJECTED report_narrative.json failed validation; repair it before spending a queue slot" >&2
    echo "  node $HERE/check_narrative.mjs $DIR --require-discussion-conclusion" >&2
    exit 2
  fi
  MIRROR=$(mktemp -d "$DIR/.pmx/run_${FAM}_XXXXXX") || exit 1
  # NAME THE MIRROR AT CREATION, not after the submit succeeds. From here on every directory under
  # .pmx/run_<FAM>_* carries ID=/STAGE= and is therefore classifiable by state_report()/--collect and
  # removable by the sweep above. Before this, the first thing the toolkit wrote into a new mirror was
  # the *job id* -- so everything between mktemp and submit was anonymous, and an interrupted wrapper
  # left a directory that no code path could classify.
  mirror_stage staging "$MIRROR" ""
  # Own it from the FIRST second: if this wrapper is killed while the job is still queued, what is left
  # behind must still be the share user's to delete.
  share_owner "$MIRROR"
  JOB="$DIR/.rsub_${FAM}_$$.R"
  # The trap must NEVER touch $MIRROR: this wrapper can be killed (harness deadline) while its job is
  # still queued, and the job needs its working directory when it finally starts.
  cleanup() { rm -f "$JOB"; }
  trap cleanup EXIT HUP INT TERM
  CONT_DIR=$(sh "$HERE/rpath.sh" container "$MIRROR") || exit 1
  cp "$DATA" "$MIRROR/$DATA_NAME" || exit 1
  if [ -z "$TEMPLATE" ]; then
    TEMPLATE=$("$NODE" "$HERE/regression_layout.mjs" select-template "$DIR" "$WS/analyses_template/$FAM/$RMD" "$RMD") || exit 1
  fi
  case "$TEMPLATE" in /*) ;; *) TEMPLATE="$DIR/$TEMPLATE";; esac
  cp "$TEMPLATE" "$MIRROR/$RMD" || exit 1
  if [ -z "$CONFIG" ] && [ -f "$DIR/pmx_config.R" ]; then CONFIG="$DIR/pmx_config.R"; fi
  if [ -n "$CONFIG" ]; then
    case "$CONFIG" in /*) ;; *) CONFIG="$DIR/$CONFIG";; esac
    cp "$CONFIG" "$MIRROR/pmx_config.R" || exit 1
  fi
  for name in report_metadata.dcf report_narrative.json; do
    [ -f "$DIR/$name" ] || continue
    # The user reads these over SMB/WebDAV as another uid, and so does the container's R user: a 0600
    # file (the write tool's default for a NEW file) is invisible to both, which is how a session ends
    # up re-authoring a file that already existed. Fix the source, then stage it.
    if [ -n "$(find "$DIR/$name" -maxdepth 0 ! -perm -o=r 2>/dev/null)" ]; then
      chmod a+r "$DIR/$name" 2>/dev/null && echo "${LABEL}_PERM_FIXED $DIR/$name was not world-readable; chmod a+r applied" >&2
    fi
    cp "$DIR/$name" "$MIRROR/$name" || exit 1
  done
  mkdir -p "$MIRROR/.pmx/word-report"
  cp -a "$WS/word-report/." "$MIRROR/.pmx/word-report/" || exit 1
  mkdir -p "$MIRROR/.pmx/analyses_template/tools"
  cp "$WS/analyses_template/tools/covariate_intake.R" "$MIRROR/.pmx/analyses_template/tools/" || exit 1
  if [ "$WORD_ONLY" = 1 ]; then
    # REUSE, do not recompute: the HTML already published in the analysis dir and the result/table/figure
    # set it was built from. report_generator.R reads output/report_results.rds; extract_*.R read the
    # HTML. Nothing here re-renders or refits. The PUBLISHED html is ${LABEL}_report.html (that is the
    # name publish() gives it); inside the job it keeps the study's own name, which is what RMD/report use.
    PUB_HTML="$DIR/${LABEL}_report.html"
    [ -f "$PUB_HTML" ] || PUB_HTML="$DIR/$HTML"
    [ -f "$PUB_HTML" ] || { echo "${LABEL}_WORD_ONLY_NO_HTML neither $DIR/${LABEL}_report.html nor $DIR/$HTML exists yet: --word-only refreshes an existing report, so run the full wrapper once first" >&2; mirror_stage word-only-no-html "$MIRROR" ""; exit 2; }
    cp "$PUB_HTML" "$MIRROR/$HTML" || exit 1
    for d in table figure; do
      [ -d "$DIR/$d" ] || continue
      cp -a "$DIR/$d" "$MIRROR/$d" || exit 1
    done
  fi
  if [ "$WORD_ONLY" = 1 ]; then
    "$NODE" "$HERE/regression_layout.mjs" stage "$DIR" "$MIRROR" || exit 1
  fi
  NAR=no; [ -f "$MIRROR/report_narrative.json" ] && NAR=yes
  MET=no; [ -f "$MIRROR/report_metadata.dcf" ] && MET=yes
  echo "${LABEL}_STAGED data=$DATA_NAME narrative=$NAR metadata=$MET word-report=yes word=$WORD mode=$( [ "$WORD_ONLY" = 1 ] && printf 'word-only' || printf 'render' )"
  if [ "$WORD_ONLY" = 0 ] && [ "$NAR" = no ]; then
    RDS="$DIR/output/report_results.rds"
    [ -f "$RDS" ] || RDS="$DIR/report_results.rds"
    echo "${LABEL}_NEXT_STEP no report_narrative.json was staged: pass 1 renders generated prose only."
    if [ -f "$RDS" ]; then
      echo "  source_md5=$(rds_md5 "$RDS")   (md5sum $RDS; a wrong value makes the generator DROP the prose silently)"
      echo "  write $DIR/report_narrative.json with that source_md5, then refresh ONLY the .docx:"
      echo "  sh $HERE/run_$FAM.sh $DIR --word-only      (stages it for you; no refit, no hand-built job)"
    else
      echo "  no $RDS yet: pass 1 must run once before prose can be authored (source_md5 comes from that file)."
    fi
  fi
  # The staging marker is the job's proof that THIS wrapper finished filling this directory. It is
  # written last, next to the data, so "no marker" can only mean "the staging was lost or this is not
  # the directory the wrapper wrote".
  printf '%s\n' "$TEMPLATE_ORIGIN" > "$MIRROR/.pmx_template_origin" || exit 1
  { printf 'data=%s\n' "$DATA_NAME"; cksum "$MIRROR/$DATA_NAME"; printf 'staged=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"; } > "$MIRROR/.pmx_staged" || exit 1
  mirror_stage staged "$MIRROR" ""
  {
    "$NODE" "$HERE/queue_env.mjs" PMX_CONFIG "$( [ -z "$CONFIG" ] || printf '%s' "$CONT_DIR/pmx_config.R" )" PMX_WORD_ONLY "$WORD_ONLY" PMX_OUTPUT_DIR "output" PMX_RUN_DIR "$CONT_DIR" PMX_DATA "$DATA_NAME"
    # The job setwd()s into the staging mirror, which the wrapper created minutes earlier and never
    # deletes. It must NOT create that directory itself: re-creating a deleted path produces an EMPTY
    # directory whose NAME resolves, which is how a deleted staging dir used to be misreported as a
    # mount/snapshot mismatch. Wait briefly for a dentry cache that has not caught up, then assert the
    # marker and the data. Both failures name themselves as RSUB_STAGING_LOST.
    cat <<'R'
.pmx_wd <- Sys.getenv("PMX_RUN_DIR")
.data_name <- Sys.getenv("PMX_DATA")
for (.pmx_i in 1:10) {
  if (dir.exists(.pmx_wd)) break
  Sys.sleep(0.5)
}
if (!dir.exists(.pmx_wd)) {
  cat("RSUB_STAGING_LOST ", .pmx_wd, " is GONE: the wrapper's staging directory was deleted (or swept) before this job started\n", sep="")
  quit(status=1)
}
setwd(.pmx_wd)
source(file.path(".pmx","word-report","cpu_budget.R"))
pmx_cpu_setup(threads=1L)
if (!file.exists(".pmx_staged") || !file.exists(.data_name)) {
  cat("RSUB_STAGING_LOST ", .pmx_wd, " exists but holds no staged input (", .data_name, " / .pmx_staged): ",
      "the directory is empty, i.e. it was deleted and re-created, or the worker sees a different export\n", sep="")
  quit(status=1)
}
R
    printf 'FAM <- "%s"; RMD <- "%s"; HTML <- "%s"; WORD <- %s\n' "$FAM" "$RMD" "$HTML" "$WORD"
    cat <<'R'
if(WORD==1) {
  pf <- tempfile(fileext=".R")
  writeLines(c(
    '.so <- c("libwebpmux.so.3","libwebpdemux.so.2")',
    '.d  <- c(file.path(getwd(),".pmx","word-report","lib"),',
    '         file.path(getwd(),".pmx","pmx_workspace","word-report","lib"))',
    '.ld <- strsplit(Sys.getenv("LD_LIBRARY_PATH",""),":")[[1]]',
    'for (s in .so) {',
    '  if (any(file.exists(file.path(c(.ld,"/lib","/usr/lib",Sys.glob("/lib/*-linux-gnu"),Sys.glob("/usr/lib/*-linux-gnu")),s)))) next',
    '  for (d in .d) { f <- file.path(d,s)',
    '    if (file.exists(f) && !is.null(tryCatch({dyn.load(f); 1}, error=function(e) NULL))) {',
    '      cat("PREFLIGHT_SHIM",s,"\\n"); break } }',
    '}',
    'for (p in c("officer","flextable")) {',
    '  m <- tryCatch({suppressPackageStartupMessages(library(p,character.only=TRUE)); NULL},',
    '                error=function(e) conditionMessage(e))',
    '  if (!is.null(m)) {',
    '    cat("PREFLIGHT_FAIL pkg=", p, " msg=", gsub("\\n", " ", m), "\\n", sep="")',
    '    quit(status=1)',
    '  }',
    '}',
    'cat("PREFLIGHT_OK\\n")'
  ), pf)
  out <- suppressWarnings(system2("Rscript", pf, stdout=TRUE, stderr=TRUE))
  unlink(pf)
  # Fail closed only on a NAMED missing library. A probe that could not complete on its own (no
  # Rscript, an unexpected error) must never block an otherwise valid run: that would turn a guard
  # into a new way to lose the HTML deliverable.
  if (!any(grepl("PREFLIGHT_OK", out)) &&
      any(grepl("cannot open shared object|no package called", out))) {
    msg <- paste(out, collapse=" ")
    # The load error names both the object R could not load (ragg.so) and the absent library
    # (`.../ragg.so': libwebpmux.so.3: cannot open shared object file`). Only the second is
    # actionable: anchor on the linker's wording first, and fall back to any .so.
    so  <- regmatches(msg, regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*: cannot open shared object file", msg))
    if (length(so)) so <- sub(":.*$", "", so)
    if (!length(so)) so <- regmatches(msg, regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*", msg))
    if (!length(so)) so <- "unknown"
    pk  <- regmatches(msg, regexpr("pkg=[^ ]+", msg))
    pk  <- if (length(pk)) sub("^pkg=", "", pk) else "officer"
    hint <- switch(so,
      "libwebpmux.so.3"   = "apt-get install -y libwebpmux3",
      "libwebpdemux.so.2" = "apt-get install -y libwebpdemux2",
      "rebuild the worker image with the missing system library")
    line <- paste0("WORD_ENV_BROKEN pkg=", pk, " missing=", so, ' fix="', hint, '"')
    writeLines(line, ".word_env_broken")
    cat(line, " -- skipping Word, rendering HTML\n", sep="")
    WORD <- 0
  } else if (!any(grepl("PREFLIGHT_OK", out))) {
    cat("WORD_PREFLIGHT_SKIPPED environment probe did not complete; continuing to render\n")
  }
}
if (identical(Sys.getenv("PMX_WORD_ONLY"), "1")) {
  # Prose-only refresh: the wrapper staged the published HTML plus output/table/figure, so there is
  # nothing to render and nothing to refit. Say so in the job log, because "no render" is otherwise
  # indistinguishable from a render that produced nothing.
  if (!file.exists(HTML) || file.size(HTML) == 0)
    stop("--word-only: the published HTML was not staged into the job (the wrapper copies it from the analysis dir)")
  cat("WORD_ONLY reusing ", HTML, " as rendered (no Rmd render, no refit)\n", sep = "")
} else {
  rmarkdown::render(RMD,quiet=TRUE)
  source(file.path(".pmx","word-report","html_references.R"))
  pmx_html_references(HTML)
}
run <- function(script,args) {
  status <- system2("Rscript",c(shQuote(file.path(".pmx","word-report",script)),args))
  if(status!=0) stop(script," failed with exit ",status)
}
if(WORD==1) {
  run("extract_figures.R",shQuote(HTML))
  run("extract_tables.R",shQuote(HTML))
  run("report_generator.R",c("--family",FAM,"--data",shQuote(Sys.getenv("PMX_DATA"))))
  if(!file.exists(paste0(toupper(FAM),"_report.docx"))) stop("Missing Word output")
}
if(!any(file.exists(c("report_results.rds",file.path("output","report_results.rds"))))) stop("Study Rmd must publish report_results.rds; update the study template using the result contract")
if(!file.exists(HTML) || file.size(HTML)==0) stop("Missing HTML output")
# Shared queue outputs must be readable regardless of the worker's umask.
published <- list.files(".",recursive=TRUE,all.files=TRUE,full.names=TRUE,no..=TRUE)
published_dirs <- dir.exists(published)
Sys.chmod(published[!published_dirs],mode="0644",use_umask=FALSE)
Sys.chmod(published[published_dirs],mode="0755",use_umask=FALSE)
writeLines("complete",".run_complete")
Sys.chmod(".run_complete","0644",use_umask=FALSE)
R
  } > "$JOB"
  chmod -R a+rX "$MIRROR"; chmod a+r "$JOB"
fi

# ---------------------------------------------------------------------- wait for a real state ----
# SUBMIT and WAIT are separate acts. `--wait` folds them together and its window (45 s) is far shorter
# than this job's queue wait, which is what made a healthy job look failed. Submit first, learn the id,
# persist it, and then wait in bounded windows.
if [ -z "$COLLECT" ]; then
  SUB=$( { "$NODE" "$HERE/r-submit.mjs" "$JOB" "${FAM}_$$" 2>&1; } ) || { printf '%s\n' "$SUB"; echo "${LABEL}_SUBMIT_FAIL" >&2; exit 1; }
  printf '%s\n' "$SUB"
  ID=$(printf '%s\n' "$SUB" | sed -n 's/^RSUB_JOB //p' | head -1)
  case "$SUB" in *RSUB_DUPLICATE*)
    ID=$(printf '%s\n' "$SUB" | tr ' ' '\n' | sed -n 's/^id=//p' | head -1)
    # An identical script (same sha) is already in flight in ITS OWN mirror; this fresh mirror will
    # never be written by anybody. Point at the live job instead of reporting a failure of this one.
    mirror_stage duplicate "$MIRROR" ""
    echo "${LABEL}_JOB_RUNNING $ID (RSUB_DUPLICATE: an identical job is already in flight; this submission was NOT queued and its mirror $MIRROR holds nothing)" >&2
    echo "  observer:  node $HERE/r-submit.mjs --attach $ID --follow --summary (BACKGROUND; automatically collect/publish on completion)" >&2
    exit 3;;
  esac
  [ -n "$ID" ] || { echo "${LABEL}_SUBMIT_FAIL could not read the job id from r-submit output" >&2; mirror_stage submit-failed "$MIRROR" ""; exit 1; }
  mirror_stage queued "$MIRROR" "$ID"
  echo "${LABEL}_JOB $ID mirror=$MIRROR"
  if [ "$ASYNC" = 1 ]; then
    printf 'RUN_STATE_NEXT BACKGROUND node "%s/r-submit.mjs" --attach "%s" --follow --summary; after completion: sh "%s/run_%s.sh" "%s" --collect=%s\n' "$HERE" "$ID" "$HERE" "$FAM" "$DIR" "$ID"
    exit 3
  fi
fi

WINDOW=$(qb_collect_wait 2>/dev/null || printf '40')
ST=$(result_status "$RES_DIR/$ID.json")
RC=0
if [ -z "$ST" ]; then
  "$NODE" "$HERE/r-submit.mjs" --await "$ID" --max-wait-s="$WINDOW" >/dev/null 2>&1 || RC=$?
  ST=$(result_status "$RES_DIR/$ID.json")
fi
if [ -z "$ST" ]; then
  # NOT FINISHED is not FAILED. Keep every byte of staging and hand the caller the one command that
  # resumes: re-running the plain command would only submit a duplicate of the same script.
  echo "${LABEL}_JOB_RUNNING $ID state=$( [ "$RC" = 3 ] && printf 'queued-or-running' || printf 'unfinished' ) - the job is NOT lost and nothing was deleted." >&2
  echo "  collect:   sh $HERE/run_$FAM.sh $DIR --collect=$ID" >&2
  echo "  or wait:   node $HERE/r-submit.mjs --attach $ID --follow --summary   (start it as a BACKGROUND job)" >&2
  echo "  progress:  node $HERE/r-submit.mjs --tail $ID   (--status is POLL-BUDGETED: one look per 45 s)" >&2
  echo "  Do NOT resubmit: the wrapper is SERIAL and the staged mirror $MIRROR is waiting for this job." >&2
  # The worker may already have written into the mirror (or will, before the collect). Anything it owns is
  # the share user's to delete only after a chown, so grant it here as well -- this path returns while the
  # job is still running, which is exactly when the user goes looking inside .pmx.
  share_owner "$MIRROR"
  exit 3
fi
if [ "$ST" != ok ]; then
  echo "${LABEL}_RUN_FAIL job $ID ended with status=$ST; the mirror $MIRROR was kept for inspection" >&2
  printf 'RUN_STATE_NEXT node "%s/r-submit.mjs" --result "%s" --summary\n' "$HERE" "$ID" >&2
  # A FAILED job must not leave the share user a tree they cannot delete either: inspection is exactly
  # when they will try. Grant it before handing control back.
  share_owner "$MIRROR"
  echo "PMX_SHARE $MIRROR staging retained" >&2
  exit 1
fi
[ -s "$MIRROR/.run_complete" ] || { echo "${LABEL}_RUN_FAIL job $ID reported ok but wrote no .run_complete in $MIRROR; nothing was published over the previous deliverables" >&2; share_owner "$MIRROR"; exit 1; }
publish "$MIRROR" "$ID"
