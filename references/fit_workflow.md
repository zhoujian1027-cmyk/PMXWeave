# PPK / PKPD / TMDD workflow

Read by stage: study intake -> required model composition -> pipeline -> report rendering/prose.
Use only the selected family; model writing follows the shared authoring routine, not a second
report-specific design process. Read report Rmds/prose rules when their stage needs them.
Wrappers run on the configured Linux/shared R host; AGENTS.md controls source writes and reads.

## Start from the user's input

Use the actual data filename unchanged. Inspect schema, units, response scale, endpoints and
dose/event semantics once with `sh analyses_template/tools/data_peek.sh <study>/<data>.csv --covariates`; review covariate
scope per references/report_rules.md before submission. PEEK_STOP ends
routine discovery. Do not replace it with per-subject probes or infer absorption from dose CMTs.

If the user supplies a base or requests SCM, preserve starts and use
`sh analyses_template/tools/run_analysis.sh --follow-chain <study> --family=<family> --data=<file> --skip-nca` in background
without --screen/--models. Fit/reuse that base for the comparison; do not replace starts with
NCA unless requested. --run-nca opts into NCA; standalone NCA with an existing
base needs --allow-existing-base. These flags do not authorize changing supplied starts.

Only new models without supplied starts use NCA for rough PK initials, then author a complete
base or requested candidate set. Follow references/screening_rules.md for a screen.
After base selection: S1 SCM -> S1C covariance -> S2 freeze -> S4 HTML -> S3 extraction -> S5 Word.
Resume valid content-keyed gates, never rerun completed fits for report formatting.

## Model preparation: use the shared composition routine

Use references/model_authoring.md, Compose and deliver. Fit preparation reads Study input / Residual
endpoints in references/model_contract.md; simulator contracts wait until S2 needs them. Finish
only stage-required code before reading rendering/prose rules or implementation internals.

- Supplied base/direct SCM: read the actual base once. Keep its structure and initials; adapt
  only a named INPUT/data/endpoint incompatibility. No replacement base, NCA reinitialization,
  new screen or search for a better template. Reuse a compatible existing paired simulator.
- New requested model/screen: select the closest dialect skeleton, compose once and reuse it
  for the configured batch. Do not choose extra structures or variants merely for the report.
- SCM/covariance require CTL, not CPP. At S2, reuse compatible study simulators or try the
  translator against the frozen final CTL. Standard scalar A_0 initial conditions, deterministic
  inline observation guards and the existing parser's flat two-endpoint residual selectors
  are translated without redesigning the model. Structural branches/custom contracts still
  require authored CPP. CHAIN_SIMULATOR_REQUIRED is an authoring handoff within the report
  request, not a scientific failure or a reason to ask for another continue. For unsupported
  translation: translate its named files with the shared composition routine, preserving equations,
  retained covariates, parameters, ETA/EPS order and scale, then resume --from=s2. PKPD VPC uses
  final_model.cpp; EBE exposure uses 02_html/pkpd_ebe.cpp. Never refit to supply them.

Save the complete code directly in its established study location. The wrapper performs its
normal preflight once. Address a concrete returned error within existing repair limits, not a
speculative code-review/rewrite loop. A ready model hands off immediately to the next authorized
stage; it neither ends the report task nor authorizes a refit of completed work.

## NCA, only when applicable

`sh analyses_template/tools/nca_initials.sh <study>/<data>.csv` submits once. Author models while it runs,
then --collect <id> once and consume INITIALS/NCA_OK (the brief $THETA digest), not the
per-subject nca_initials.csv or a full transcript. NCA is initialization, not a report deliverable.
Use NCA_OK initials for eligible parameters in a new model. On NCA_SPARSE or NCA_FAIL,
continue with existing or template starts and state the reason once in the agent reply.
Use two_point only for exactly two terminal observations. Failed multi-point windows
may use the configured cohort fallback. KA follows the NONMEM initial rule.

Set --dv-scale=raw|log for --nca-dv-column (DV by default), independently of CTL aliases.
DV/raw and LNDV/log are valid different inputs; DV=LNDV in a fit never makes raw DV logarithmic.
Specify known PK --nca-dvid or --nca-cmt for multiple endpoints; shared CMT across DVIDs
requires --nca-dvid. Never assume endpoint 1 is PK. Exclude PD observations only in memory,
retaining original data and all dose/event records. Selection is checked before submission.
Use --route=unknown|iv|oral|sc, --tau=H and --depots=N only as supported study hints; raw is
the default DV scale. Complex/unknown regimens return descriptive/unestimable results rather
than invented starts. CL/V need an isolated profile, terminal information and limited
extrapolation. OMEGA/SIGMA, extra absorption and PD/TMDD starts need model-specific justification.
NCA publishes the initials table and visible/hidden digest even for small studies; consume only
the digest. Cache keys include settings/sources; a queue failure is never a successful cache.
Each subject contributes one first-dose-occasion profile, bounded by occ_start/occ_end;
n_tot counts subjects, not dose occasions. Do not rerun to increase that count.

## Model and endpoint contract

The backend imports native CTL records; never substitute a hardcoded R model or insert toolkit header annotations.
Preserve scale/error models and exact fixed approvals. Derive observation order from explicit model
selectors, or use the study-run configuration when the native contract is ambiguous.
Original selectors remain nmcmt/nmdvid; dose/event CMT is never remapped. The same adapter
applies to screen, serial SCM and PSOCK workers. Unknown/ambiguous observations stop with
endpoint mapping error; do not equate CMT/DVID, disable combine.dvid or edit data to suppress it.
Adapter identity affects multi-endpoint caches, not valid single-endpoint keys. Preserve old
incompatible fits for explicit review, not an automatic new screen.
Dynamic ETA indices such as ETA(4+OCC) are unsupported and fail preflight once.

## SCM

Prepare the data-driven scope before submission using references/report_rules.md,
Covariate intake (every report family). Report requests include this intake by default;
model-code-only requests do not. The agent writes reviewed pairs to root covariates.csv,
including every eligible baseline covariate on both CL and central volume. Each row's `param`
column must be the literal `$PK` THETA symbol — `TVCL` and the central-volume symbol
(`TVVC`/`TVV`/`TVV1`), never the derived `CL`/`VC` names; the schema example is
word-report/covariates_template.csv. The engine executes those declarations; it does not guess
clinical meaning from arbitrary column names, and a non-THETA target fails as
SCM_PARAMETER_SCOPE before the reviewed-scope coverage check.
Missing configuration stops for preparation instead of finalizing an untested base model.
Header-only CSV requires a reviewed empty scope or explicit user opt-out.

Declared pairs are limited to CL and central volume VC (including TVV/TVV1 and structurally verified TVV2 aliases), not
KA/Q/VP/lag. `covariates.csv` defines every effect (type, reference, exponent, category level);
an exclusion needs `test=no` plus `user_instruction` quoting a human restriction. Review
02_html/table/_scm_candidate_plan.csv once and distinguish prespecified, constant and
not-evaluated pairs from nonsignificant results. Never restart an active study to apply a new
default.

Blank/missing exponent is NULL (estimated power), never fixed NA. Explicit references,
exponents and category levels must be finite; power values/references positive. Preserve
approved fixed allometry and unbounded estimated starts unless a sign/domain is constrained.
SCM_ASSESSMENT_PARTIAL is incomplete assessment, not evidence of no effect. Keep raw errors,
calls and stacks in failure caches. Covariate functions remain defined in
word-report/ppk_covariate_model_rules.md; do not invent substitutes.

Every fit after the base starts at the current model's fitted estimates, printed as
SCM_WARM_START from=<model> thetas= effects= ctl=_scm_warm.ctl. The authored .ctl still owns
records, bounds and the endpoint; only the initial estimates are replaced, and an appended
effect starts at its fitted value when the current model already carries that effect. A cold
refit from the .ctl initials both spends a whole bounded job window per candidate (~600 s for a
moderate POPPK/PD model, i.e. one candidate per job) and lands in a different local optimum, so
the BIC difference would then describe the optimizer's starting point rather than the covariate.
Warm starts change no reported estimate and no criterion: fitted values remain the only result.
Use one estimator-specific verdict in screen, serial/parallel SCM, cache reuse, S1C and S2:
passed, warning or failed. A normal native optimizer exit with finite fitted coefficients,
objective, random-effect covariance and native BIC can proceed with warnings retained.
nlmixr2's "last objective function was not at minimum" compares the order of objective-history
entries; alone it is not a failed convergence code. ETA resets/nudges alone are not failure.
SCM_FIT_QUALITY and assessment$optimization retain the actual status/message/warnings for
interpretation; warn about fragile selection/uncertainty without claiming a demonstrated minimum.
Nonzero/non-finite optimizer codes, explicit failed-convergence/limit errors or invalid fitted
quantities remain failures. FIT_QUALITY_REVIEW_REQUIRED names those blockers. Covariance
completion is neither a convergence repair nor evidence of predictive adequacy.
A matching saved failure labelled exactly "Optimizer minimum not demonstrated" can be
reclassified only when its saved native fit passes the current checks with a verified normal
exit and that history warning. SCM_FIT_RECLASSIFIED reuses those estimates without a fit,
retains the original failure record and changes no cache identity, data, model or controls.
Other failures stay failed; never clear ledgers, retune starts/bounds, switch estimators, remove
random effects or increase budgets automatically. A native CTL MAXEVAL suggestion is not a
repair of this FOCEI backend; use the actual runtime status before naming a time/iteration limit.

Stage 2 also validates each paired simulator before it freezes the result: `mrgsolve::mread`
must compile it and its `$CAPTURE` line must carry the family contract from
`analyses_template/tools/simulator_contract.R` (`pkpd`: IPRED IPRED2 DV_PK DV_PD; `ppk`: IPRED DV; `tmdd`:
IPRED IPRED2 DV_L DV_R; the `*_ebe.cpp` exposure simulator needs IPRED only). `S2_SIMULATOR_OK` means
both checks passed; `S2_SIMULATOR_INVALID` names the failing file, the reason and the C++
error, and stops the stage. A translation that exists is not a translation that works.

## PD turnover starts and EBE shift

Set R0 or E0 from the observed baseline response and KOUT from the recovery rate.
Check mean ETA and population prediction bias when typical values stay near their starts.

The base fit tries one re-centred fit when a multiplicative parameter has |mean ETA|
above PMX_PLATEAU_ETA_MEAN (default 0.25). It keeps the fit if OBJF improves by more
than 0.5. Candidate fits use the accepted base objective. Set
PMX_PLATEAU_RECENTRE=false to disable the retry.

## Covariance and frozen results

All fits use matching FOCEI controls/ODE tolerances through pmx_focei_control() in
screen_fit_identity.R: pass rxControl inside foceiControl, not as an ignored outer nlmixr2
argument. Verify the saved effective control. A corrected recipe keeps old caches distinct;
never relabel their precision or automatically refit them. Fixed-parameter strict report
validation may diagnose legacy numerical drift without replacing those estimates.
Screen and SCM use native stats::BIC(fit)
and its native parameter count; legacy manually computed screening BIC is not comparable.
S1 checkpoints before S1C. S1C uses setCov/addTable on matching completed estimates
(nlmixr2est >=7.1.0), without fresh optimization. PPK defaults to base and final uncertainty;
PKPD/TMDD use final unless PMX_COV_BASE=true. Pending/failed uncertainty preserves estimates
and blocks report completion; --covariance-only resumes uncertainty.

Read valid covariance caches before budget checks. Deferral is not a failed covariance attempt.
Compare COV_FIT_START requested with COV_FIT_RESULT actual, not a printed option or mirror edit.
Each S1C invocation tries an available primary method once, then the fallback (PMX_COV_FALLBACK,
default r). Across deliberate invocations, PMX_COV_TRIES (default 2) and
PMX_COV_FALLBACK_TRIES (default 1) cap cumulative starts per fit key/method; a method whose
start budget is already used is skipped with COV_ATTEMPT_SKIP instead of being retried. If every
start is spent and no method installs a matrix, the default stays strict: the stage fails, the
estimates and the search checkpoint are preserved, and COV_DIAGNOSIS/COV_DEGENERATE_AT_BOUND
name the estimates sitting on a bound (boundary proximity is a diagnostic observation, not proof of zero derivatives or singular information).
Only explicit human approval to report without uncertainty permits setting
PMX_COV_UNESTIMABLE_CONTINUE=true; never waive this gate yourself. S1C then
records Covariance_state UNESTIMABLE with Report_state READY_TO_FREEZE, keeps the estimates,
writes covariance$state="unestimable" plus its disclosure into the frozen result, and S2-S5 run
with blank SE/%RSE/CI and a mandatory methods disclosure. That state is never presented as
estimated uncertainty, never cached under a covariance key, and covariance_handoff.mjs reports
COV_HANDOFF_UNESTIMABLE rather than reusing it as completed uncertainty.
COV_ATTEMPT_BUDGET_EXHAUSTED reports that every method's start budget was already spent, so
nothing new was tried; clearing attempts to repeat an unchanged job is still forbidden. Unsupported runtime/invalid covariance stops the stage.
run_analysis.sh inherits verified S1C settings through covariance_handoff.mjs; an omitted
option must not reset successful r to s. A changed explicit policy stops a full/report
continuation; deliberate replacement uses --covariance-only. Preserve gradient/corrected-matrix
warnings: completion does not establish trustworthy intervals or adequacy.

Published base_model.ctl contains fitted starts at four significant digits. final_model.ctl
retains those base starts and adds only covariate starts, without agent fine-tuning.
Before either final stream is printed, a `$INPUT` field whose data column is not numeric is
published as `NAME=DROP`: a text column cannot be an estimated data item, and NONMEM would
otherwise reject the control stream. The rewrite is positional, keeps the field count, never
touches an item that already carries `=...`, is idempotent, and prints
`CTL_INPUT_DROP ctl=… data=… columns=NAME=DROP`.
Full-precision final estimates stay in native frozen results and artifacts/s2/final_fitted.ctl
for simulations/tables. S2_MODEL_CONTRACT_UNSUPPORTED needs an authorized export repair or
paired simulator, then --from=s2 with valid upstream gates, not fitting again.
Generated CPP declares new DES intermediates once. S2 records File/Origin/MD5/SourceMD5 in
artifacts/s2/simulators.dcf: unchanged generated files may regenerate; edited generated and
existing files are preserved with their actual origin, then recompiled and prediction-checked.
A first-line phrase never grants authorship or preservation. Legacy files without provenance
stay classified as existing; provenance is not proof of scientific equivalence. Never disguise a generated header as user-authored.
Apply report solver controls to the loaded simulator, without changing CPP for numerical tuning.
A changed CPP properly invalidates S2; report resumes can prepend lightweight S2 validation
when matching S1/S1C gates remain valid, never launch estimation. A source/settings mismatch
needs review of the preserved fit, not an automatic restart.

## Budget, waiting and checkpoints

references/cpu_budget.md owns allocation, memory and timing admission; references/continuation.md
owns the single background controller/observer, exact returned ids, verified handoffs and stopping.
Use one background --follow-chain controller after base selection. It advances valid checkpoints
with caches and stops for narrative or a real blocker; do not add observers for its owned jobs.

Only new completed fits/stages are progress. Timing, logs, attempts and mirror stamps are not.
SCM_BUDGET_INFEASIBLE means the estimate exceeds a fresh bounded window, not a deferral.
Admission also requires the estimate plus a safety margin (min 60 s, otherwise at least 20 s or
5% of the window) to fit in what remains: a fit admitted with no slack is killed at the stage cap
and loses its entire window, which is what the recorded CHAIN_STAGE_TIMEOUT / exit 124 was.
DEFER/exit 3 needs its explicit normal-budget marker and verified durable progress before another
submission. Never clear counters/backoff, change mirrors, guess ids or replay completed work.
CHAIN_ORPHAN_ACTIVE blocks a new fit while owned children remain; timeout terminates the owned
process group. Never kill unrelated workers. Keep simulation counts, RNG, estimators, ODE settings
and covariance methods unchanged. CPU or report changes do not authorize refitting.

A live candidate fit is not a deadlock. Retain the automatic wake source; no polling/sleep loop.
Missing background support is a capability blocker. ACP degeneration is a transport/model-handoff
blocker, not permission to refit or reset guards. Existing tasks retain their preset; source updates
do not authorize service restarts or temperature changes.

## Study files

Follow references/study_layout.md for root configuration, family outputs, caches, queue
payloads and share permissions. It is the single owner of study artifact locations.
