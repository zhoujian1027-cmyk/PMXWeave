# Model and report contract

## Study input

Use the actual data file unchanged, beside the study outputs in the user-authorized study directory. The fitting reader accepts headered CSV/tab/space/semicolon data. Existing fit-family HTML readers expect CSV; unsupported study formats require an explicitly selected study reader, never an unapproved data rewrite.

$INPUT is positional, including DROP/SKIP fields. Preflight checks canonical roles against the original header; changing DV from DV to LNDV requires an explicit DV=LNDV alias and a matching endpoint scale. It never silently changes the response column. Keep EVID/CMT/MDV/RATE/II/ADDL/SS/DVID and baseline records. One THETA parameter per line is required. Inline $THETA/$OMEGA/$SIGMA values are normalized in memory before covariate injection/export. OMEGA blocks use one lower-triangle row per line. Unsupported SIGMA covariance/FIX forms stop before fitting.

$DATA IGNORE/ACCEPT filters support column comparisons, logical operators and scalar constants; unsupported expressions or missing comparisons stop explicitly. Filters are applied in memory to the fit data. Reusable model templates do not carry old study exclusion conditions. Do not remove dose rows through IGNORE=(MDV.EQ.1).

## Workflow ownership

references/fit_workflow.md owns intake, supplied-base precedence, optional NCA, model preparation,
stage order and resumption. references/screening_rules.md owns an explicitly requested screen.
Read the input/endpoint/simulator sections here only as the current stage requires; they are
contracts to implement, not a request to inspect generators or redesign a supplied model.

## Residual endpoints

Residual functions and SD starts come from native ERROR/SIGMA records. Explicit flat CMT/DVID branches determine their observation mapping in code order. Unsupported or ambiguous contracts require study-run configuration, never extra CTL comments.

Residual initials are positive standard deviations, not variances. If no explicit residual initials are given, the SIGMA variances must map one-to-one to residual names in declaration order. DV scale and model prediction scale must agree.

## Covariates / configuration

SCM tests only the pairs declared in root covariates.csv, on CL and central volume only.
The agent prepares the default scope from actual study data per references/report_rules.md;
there is no blind engine grid or biological subset selection. Use actual THETA names from
$PK: TVCL and the model's central-volume symbol, including TVVC/TVV/TVV1 or oral ADVAN4
TVV2. Structural observation scaling resolves the role; a peripheral V2 is not a central alias.
Missing CSV/review blocks SCM preparation; reviewed empty scope is not evidence of no effect.
Each row defines effect/reference/exponent or a finite category contrast. test=no requires
user_instruction quoting an explicit human restriction. Existing base effects are prespecified;
constant/non-evaluable pairs are not nonsignificant. Unknown coding/missingness stops explicitly.
The coverage plan under 02_html/table/_scm_candidate_plan.csv distinguishes these outcomes.
Preserve approved fixed BW exponents and unbounded estimated starts unless domain/sign is
explicitly constrained. DOSE/ADY are administrative, not default covariates; unsupported
parameterizations require a compatible contract, not an improvised model change.

Custom candidates live in root covariates.csv; missing-covariate handling must be explicit. Default BIC supports fixed-power alternatives. Chi-square criteria use actual added coefficient counts and proper forward/backward signs; fixed-power alternatives require BIC or a prespecified base.

Queue entry points explicitly transport SCM_CRITERION, SCM_P_FWD, SCM_P_BCK, PMX_EST, PMX_CMT_OBS, PMX_STAGE_TIMEOUT and PMX_EXPOSURE_LABEL. Fit backend is FOCEI; other estimators require a compatible backend.

ER/c-QTc use a study pmx_config.R (or --config=...) to override their configuration chunk; --template=... can select a study Rmd. The standard wrapper also prefers a study's matching Rmd over the global default. Configuration never mutates the original data. Explicit continuous/categorical declarations control fitting; group codes are not guessed from the number of unique values. Candidate comparisons use the same observations. c-QTc final covariates combine retained effects with explicitly declared prespecified adjustments.

## Reports / simulators

Root base/final controls are estimation-start files: base uses the selected fit rounded to four significant digits; final retains those base starts and adds covariate starts. Full-precision final fitted controls are frozen under artifacts/s2/final_fitted.ctl and drive native result reporting/simulation. The automatic C++ translator supports plain-assignment ODE arithmetic, powers/comparisons and the original single-endpoint diagonal SIGMA/EPS/Y observation equation; it carries the fitted OMEGA and configured covariate references. Analytic ADVAN, branches, model-defined durations and explicit endpoint/scale metadata require an authored paired simulator. Unsupported contracts stop without refitting; update study simulators when changing the model.

See word-report/README.md: result prose reads current structured output, tables/figures use manifests, and required-by-default narrative is tied to evidence hashes. No prewritten clinical conclusions or internal error messages belong in the Word body.

Study caches belong under study outputs, never in the reusable workspace. Preserve them for resumability; remove only when resumption is unnecessary.

## Endpoint and simulator contracts

EPS(2) alone is not a multiple endpoint marker: proportional-plus-additive error uses two EPS terms for one response. Branch-selected endpoints retain the native deterministic predictions and error scales; the fitting adapter reads their explicit selectors without requiring toolkit header annotations. Original DVID coding is retained in nmdvid for imported branch expressions, while dvid is mapped to the queue endpoint index. This is an explicit source contract, not runtime validation; adapt the template to study data, endpoint scale and backend before fitting. SAEM/BAYES remain NONMEM-backend examples.

General ADVAN observation defaults come from DEFOBSERVATION (DEFOBS), then CENTRAL, then the first MODEL compartment. Built-in defaults are ADVAN1/3/10/11=1 and ADVAN2/4/12=2. A missing general MODEL default is not guessed from an ERROR reference or the last compartment.

The mrgsolve library files are structural examples, not complete stochastic VPC models. Reports require explicit study SIGMA/EPS and the expected DV outputs for VPC; no generic noise is invented. EBE exposure uses the study's dose/interval/compartment/infusion, individual effects and frozen covariate formulas. Regular repeated regimens use 50 fixed conditioning intervals and the following interval for Cmax/Cavg/Ctrough; there is no steady-state/periodicity check or patient-specific fallback. All covariate-impact values are model predictions. Single-dose or irregular schedules use recorded dose events over a shared prediction window (PredictionWindowHours in report_metadata.dcf, otherwise the full study-level sampling-time range), with Cmax/Cavg/Clast and supported PD/target summaries. Individual observed measurements at prediction times are not required; no repeat interval or trough is invented. Unresolved event/covariate contracts are recorded as unavailable in table/_exposure_audit.csv. NCA --depots is printed as an explicit structure hint; only one-depot hints can receive the single-absorption KA approximation.

S2 records the final control stream and both simulator sources. HTML works on private simulator copies so updating fitted coefficients cannot mutate frozen gate artifacts. Editing an original simulator/ctl invalidates the downstream gates. Regression publishing replaces its generated artifact directories and makes worker files readable after creation.

Word uses the reference styling and the final apply_reference.py step to assemble Contents/List of Figures/List of Tables. PMX_PYTHON can specify the queue worker Python interpreter. These fields are marked for update in Word; source-only editing does not compute their pagination or verify final layout.

SCM treats LNDV/LOGDV/LN_DV/LOG_DV as response-derived fields, not default covariates.
CSV param must use the actual CL/central-volume THETA symbol from $PK (for example TVCL/TVV1),
and each cat row requires a finite numeric contrast level. CSV enumerates the requested pairs; omitted pairs are not tested. Failed preflight is not a fitting/convergence failure.

Multi-endpoint adapters, explicit PK NCA selection and supplied-base precedence follow
references/fit_workflow.md. Keep original selectors/data and valid fitted caches unchanged.

PKPD reporting uses pkpd_report_contract.R: PK_ENDPOINT/PD_ENDPOINT are model endpoint indices,
not original labels. PKPD_DV_SCALE declares raw/log; auto recognises explicit DV=LNDV aliases.
Plots use natural-scale DV/PRED/IPRED consistently; numerical model estimates remain frozen on
their fitted scale. PKPD_SIM_SCALE declares simulator output scale; population predictions must
agree with frozen fitted PRED. Do not mix endpoints or invent missing predictions. PK_UNIT and
DOSE_UNIT label the actual study units without conversion. PKPD_SIGMA_MAP names fitted SDs in EPS
order (two single-error endpoints default to endpoint order); complex residuals need an explicit map.
Simulator parameters and OMEGA/SIGMA are updated on parsed model objects with exact dimension checks,
never by editing numeric-looking comments. CPP is an S2/report dependency, not an SCM input.
Reuse or translate the frozen model first; unsupported export names the files to author, then
resume --from=s2 with valid S1/S1C. S3 extracts current HTML figures. Simulator repairs never
authorize refitting or reduced VPC counts.
