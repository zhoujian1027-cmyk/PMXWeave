# Troubleshooting

Read only the section matching the actual token or requested maintenance task. Routine model
code/report generation uses INDEX.md. AGENTS.md governs read/write permission; a documented
repair command does not authorize source changes, package installation or external browsing.
Preserve study data, completed fits and guards. Never rerun an unchanged analysis to fix Word.

## Queue and progress

The queue processes one request at a time; candidates inside that request may run in parallel.
NCA/check_initials/fit_ladder/run_analysis are submit-only by default and return NCA_JOB,
INIT_JOB, LADDER_JOB or CHAIN_JOB with the id and next action. Use --collect for completed
initials/check results; internal --sync/PMX_SUBMIT_MODE=sync is not permission to block an agent
turn. Wrappers print the id before waiting and on TERM/INT so interrupted calls remain traceable.
Automatic continuation follows references/continuation.md: one active background observer.

| Token/state | Required action |
|---|---|
| QUEUE_GUARD_BUSY / RSUB_DUPLICATE | Follow the existing id; do not submit another copy. A finished but unpublished ER job is collected as ER_COLLECT_FINISHED without rendering again. |
| RUN_STATE FAILED (ER/c-QTc) | Run the printed `r-submit.mjs --result <id> --summary` command once to read the worker error. Repair the named study input and retry only after it changes. Use the queue client for any needed log tail. |
| QUEUE_GUARD_BACKOFF / CHAIN_NO_PROGRESS | Read the named error once; repair the authorized cause before a genuinely changed attempt. Never disable backoff or clear the ledger. |
| PMX_COVARIATE_INTAKE_REQUIRED / SCM_SCOPE_INCOMPLETE | Finish the actual-data review and study configuration per references/report_rules.md, Covariate intake. This is authorized report preparation; do not ask for routine permission, skip SCM or repeat the incomplete job. SCM_SCOPE_INCOMPLETE names the reviewed pairs absent from covariates.csv; fix the CSV, not the model. |
| SCM_PARAMETER_SCOPE | covariates.csv `param` is not a `$PK` THETA symbol. Rewrite those rows with the literal CL/central-volume THETA names (`TVCL`, `TVVC`/`TVV`/`TVV1`), using word-report/covariates_template.csv as the schema; `CL`/`VC` are derived names and are never valid there. This check runs before the coverage check, so a non-THETA target is never reported as a missing pair. |
| PD under-prediction / upward CWRES / non-zero mean ETA | Check the PD typical values and mean ETA. See references/fit_workflow.md, PD turnover starts and EBE shift. |
| SCM_NO_TESTABLE_PAIRS / SCM_COVERAGE candidates=0 | Consult the reviewed scope and pair plan once: explicit opt-out, no eligible variables or prespecified effects are distinct from evaluated but not retained. Missing configuration never establishes a no-effect result. |
| FIT_QUALITY_REVIEW_REQUIRED / SCM_WARM_START / SCM_FIT_INVALID / SCM_FIT_QUALITY / SCM_FIT_RECLASSIFIED | references/fit_workflow.md, SCM. A candidate that starts from the authored initials instead of the current fit is a cold refit: expect one candidate per job window and an unreliable dBIC. SCM_FIT_INVALID excludes genuinely invalid fits. A normal-exit objective-history warning and ETA resets/nudges alone are not failure. SCM_FIT_RECLASSIFIED reuses only the matching saved warning-only rejection, preserving its record without fitting. Check actual exit code/time before claiming a budget failure; do not propose MAXEVAL/SAEM/ETA removal as generic repairs. Failed assessment is not evidence of no effect. |
| CHAIN_STAGE_TIMEOUT / exit 124 | A fit was admitted with too little room and was terminated at the stage cap; the window and its learnable timing were lost. Check the admission margin and the SCM_DEFER lines; do not raise the budget, change the model, or clear caches. |
| CHAIN_ORPHAN_ACTIVE | Another owned process remains for this study. Inspect that owned task once; do not overlap fits or kill unrelated workers. The chain timeout uses TERM then KILL after 10 seconds on its process group. |
| S2_SIMULATOR_INVALID | Fault, actionable at S2: the paired simulator does not compile or does not capture the family contract. mrgsolve errors such as "'DVID' was not declared in this scope" mean the `$TABLE` reads a data item that is not declared (add `$INPUT DVID`); a missing capture means the report cannot find that endpoint observation. Fix the simulator, or delete it so stage 2 translates the control stream, then `resume --from=s2`. |
| S2_SIMULATOR_OK | Expected line: the translation compiled and carries the family captures from analyses_template/tools/simulator_contract.R. |
| REPORT_FIT_ROWS_AMBIGUOUS / named native CMT | Shared report augmentation must use verified native source-row provenance, not compartment labels or guessed suffixed columns. This can affect PPK/PKPD/TMDD. Preserve CTL/data/SCM/covariance; repair the shared helper and refresh from S4 during an authorized report run. Do not remove compartment names or repeat estimation. |
| PMX_SIMULATOR_PREDICTION_MISMATCH | Read table/_simulator_validation.json once. It reports coverage, endpoint/max differences and the one strict fixed-parameter native reference. A numerical-drift verdict requires independent agreement; small percentages or tighter CPP settings alone prove nothing. Preserve fitting/covariance, repair equations/events/scale or the named runtime issue; never edit a study Rmd to weaken the gate. |
| REPORT_FREEZE_REVIEW_REQUIRED | Simulator changes require S2 compile/freeze validation, not a new SCM. Matching completed S1/S1C allow report-only preparation; mismatched upstream source/settings stay preserved for review, never trigger automatic refitting. |
| PMX_REPORT_SHARED_MISSING | Fault: the report ran without analyses_template/_shared/report_aug.R (no complete toolkit, or the wrong working directory). Run from the study root with PMX_TOOLKIT set; never paste the extraction block back into the Rmd. |
| RSUB_POLL_THROTTLED / RSUB_POLL_STOP | Exit 5 is a probe limit, not job failure. Do not loop status/tail/job_output. A changed state reopens observation; use the existing background observer. |
| RSUB_CWD_UNRESOLVED / cannot change working directory | Read the two reported mount/path lines. The wrapper resolves/creates its study-side staging cwd and verifies data visibility. One retry is allowed for this mount-visibility failure; if repeated, report those lines and stop. |
| RSUB_STAGING_LOST | The submitted job cwd was removed. Identify that cause before another submission; do not delete live staging. |
| RSUB_RESULT_MISSING | Terminal status exists without a published result after the 30s publication allowance. End the observer; inspect queue publication. An old status file does not prove a current submission. |
| CHAIN_CONTROLLER_ACTIVE | The study already has a live controller lock; keep that controller, do not overlap observers. |
| RSUB_UNRUNNABLE_ID | Hidden/unsafe request id cannot run; new ids are sanitized. Repeated waiting cannot make the hidden request executable. |
| *_JOB_RUNNING / normal pending window | Still running, not a fit failure. Follow the existing id and collect once after completion. |
| STAGES_CHECKPOINT / CHAIN_CHECKPOINT / explicit normal-budget DEFER | Continue the named stage with valid gates/caches when verified completed work permits it; exit 3 alone is insufficient. |
| timeout / crash / error | Preserve completed work and identify the failed phase. Timeout rc=124 is distinct from R error and signal termination; rc>=128 reports signal=rc-128 (11 is SIGSEGV). Read the named log tail before changing model code. |

Status limits: RSUB_POLL_MIN_INTERVAL_S defaults to 45 seconds; repeated same-state looks exit
5; RSUB_POLL_MAX_STALLED defaults to four unchanged looks. The probe ledger is
managed by the queue client. `--status <id>` reports state, elapsed_s, out_bytes, err_bytes
and last_line. `--tail <id>` returns newly written log bytes;
it is diagnostic, not a polling workaround. No foreground fallback exceeds 40 seconds.
Low-level collect/attach limits use PMX_COLLECT_MAX_S/RSUB_ATTACH_MAX_S; deliberate background
attach uses PMX_ATTACH_MAX_S. Worker bounds come from analyses_template/tools/queue_budget.sh, environment
PMX_WORKER_TIMEOUT_S/PMX_STAGE_TIMEOUT/PMX_HEADROOM_S/PMX_HEARTBEAT_S or the configured
worker file. A larger budget is never an automatic retry authorization.

## Screening, endpoints and covariance

| Token/question | Current contract |
|---|---|
| INIT_BAD codes=NOFIX / Unapproved fixed parameter(s) | Exact human-approved name=value only; references/model_authoring.md, Fixed parameters. PMX_FIXED is disclosure. |
| NCA_SPARSE / NCA_FAIL / no initials | references/fit_workflow.md, NCA. Continue with existing or template starts and note the outcome once in chat. |
| LADDER_CANDIDATE_CAP / LADDER_BUDGET_STOP | references/screening_rules.md. Keep requested width/structure, run configured slots through terminal/deadline and report unstarted slots accurately. |
| LADDER_EXPORT_REQUIRED / LADDER_TOOLKIT_LAYOUT | Use the complete toolkit entry point; export-only reuses verified fits. Never construct .toolkit variants or replay estimation. |
| SCM_SCREEN_BASE_MISMATCH / LEGACY_SETTINGS_UNVERIFIABLE | Preserve selected fits; read the named mismatch once. Do not guess package versions/threads or edit keys. |
| endpoint mapping error / cmt_obs ambiguity | references/model_contract.md, Residual endpoints. Use the native model selector or study-run configuration and explicit PK selection; never guess CMT=DVID or change data. |
| CHAIN_SIMULATOR_REQUIRED / S2_MODEL_CONTRACT_UNSUPPORTED | Missing paired simulators after a conservative translation refusal are an authoring handoff, not failed SCM/covariance. Standard A_0/observation guards/flat endpoint selectors are translated automatically; unsupported constructs name the exact files and frozen CTL. In an authorized report task, author those files now and resume --from=s2 with valid gates, without another permission or unchanged job. |
| COV_ATTEMPT_BUDGET_EXHAUSTED / COV_ATTEMPT_SKIP / completed r covariance reset to s | references/fit_workflow.md, Covariance. Starts are counted per fit key/method (PMX_COV_TRIES, PMX_COV_FALLBACK_TRIES); a spent budget means read the log and repair, not that covariance became estimable. Inherit verified S1C policy; --covariance-only deliberately resumes/replaces uncertainty without SCM. |
| Covariance not estimable / COV_DEGENERATE_AT_BOUND | references/fit_workflow.md, Covariance. Boundary proximity or a near-zero diagonal variance may contribute, but do not establish the cause. Read COV_DIAGNOSIS and actual derivative/curvature warnings before any scientific model change. Only PMX_COV_UNESTIMABLE_CONTINUE=true continues with blank SE/%RSE and a disclosure; never clear attempts or cache a covariance-free fit as completed uncertainty. |
| CPU allocation / long fit | references/cpu_budget.md. CPU_PLAN is an allocation, not utilization; preserve VPC settings and completed caches. |

## Word runtime and styles

officer/flextable import ragg; a missing libwebpmux.so.3 is an environment failure, not a
model failure. Run analyses_template/tools/preflight_word.sh <study> once (submit-only, --collect reprints its
verdict), rather than rerendering the analysis. The wrapper also probes in a child R process
before the HTML render; the generator emits WORD_ENV_BROKEN and .word_env_broken on failure.

| Verdict | Meaning/action |
|---|---|
| WORD_ENV_OK | Worker dependencies load. |
| WORD_ENV_SHIM / WORD_ENV_SHIM_LDD | Staged fallback is loaded; preserve it and disclose the runtime warning. |
| WORD_ENV_BROKEN pkg=... missing=... | Worker and fallback cannot satisfy the dependency. Repair the explicitly authorized environment; unchanged resubmission cannot help. |
| WORD_STYLE_DIR | Resolved toolkit style path. |
| WORD_STYLE_UNSTAGED | Normal in a bare study directory; the wrapper stages styles. |
| WORD_STYLE_MISSING | Style missing inside a staged job; fix staging/source. |
| WORD_PREFLIGHT_REPEAT | The same completed environment check is already answered. |
| WORD_SCRIPT_COPY | Generator was copied away from family/ or result_narrative.R. Use the wrapper and complete toolkit. |
| *_HTML_OK_WORD_SKIPPED | Preserve published HTML and repair the Word-runtime blocker; no analysis rerun. |
| footer1.xml invalid relationship id | Template layout defect; fix the authorized reference.docx source. Rerendering cannot remove an unchanged defect. |
| CTL_INPUT_DROP | Expected line, not a fault: that `$INPUT` field's data column is not numeric, so the published final stream carries `NAME=DROP`. Keep the column in the data file; change the model only if it references that item. |

Keep preload_word_libs.R and apply_reference.py in staged toolkits. This distribution does
not ship native fallback binaries; install the worker image's required system libraries
instead. An explicitly supplied deployment fallback can be preloaded under its SONAME in
the same R process before ragg loads; changing LD_LIBRARY_PATH inside R is insufficient.
For an authorized runtime investigation, use ldd on the actual failing .so.
analyses_template/tools/word_image_fix.sh can install libwebpmux3/libwebpdemux2 in the configured image; its
binary-copy fallback requires a separately supplied deployment library. A one-off install
alone does not persist across rebuilds.

## Narrative and completion

Use references/report_rules.md. NARRATIVE_REQUIRED is authoring, NARRATIVE_REVIEW_REQUIRED is
prose/evidence repair, WORD_REFRESH_REQUIRED is Word only and WORD_RUNTIME_REQUIRED is a runtime
blocker. Refresh ER/c-QTc using wrapper --word-only; never hand-submit a copied generator.
The wrapper stages report_narrative.json/metadata/styles and reports ER_STAGED and ER_NEXT_STEP.
NARRATIVE_ABSENT/STALE/CHANGED_EVIDENCE and *_NARRATIVE_DROPPED identify the exact issue.
check_narrative.mjs --fix-evidence rebuilds evidence hashes from the files; it never rewrites
source_md5 to launder interpretation against different results. An empty safety-table list
is answered: review listed figures/structured evidence, not repeated manifests.

output/run_manifest.json records status, analysis/report states, input/artifact hashes,
prose.state/reason/file/fix and classified warnings; its conclusion summarizes the outcome.
*_ALREADY_COMPLETE stops report generation. --rerun/--force is an explicit rebuild choice,
not a warning-removal method; queue-guard overrides do not bypass artifact completion checks.
RUN_STATE comes from wrapper --state, never staging timestamps. ID=PENDING/no marker means
no queued job, not an active worker. Orphan/never-queued mirrors are wrapper-managed; do not
probe or remove live directories to force progress.

## Study permissions

For explicitly requested study-permission repair, analyses_template/tools/pmx_share.sh <study> --check reports
ownership of generated files. Apply repair only to the authorized .pmx directory.
Wrappers use the study directory owner and group unless PMX_SMB_UID and PMX_SMB_GRP
are configured. Keep the study and R worker writable by the intended accounts.
