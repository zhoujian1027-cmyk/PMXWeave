# Report rules

Read Shared and Covariate intake for every report, then only the requested family's section. Code-only tasks do not
read this file. Use the family-specific completion contract and existing frozen evidence.

## Shared

Use the human prompt and attachments, the resolved PMX toolkit and the named analysis directory.
Search and read files only in those two directories. Use the known AGENTS.md/INDEX.md and the
study path directly. If a required path is missing, report the exact path. Use the queue client
for the returned job ID; leave runtime configuration and queue files to the toolkit.

Report fit-frame extraction is shared code: call `pmx_est_aug(fit, CPP_SIM)` from
`analyses_template/_shared/report_aug.R`; never re-implement the block in a family template
or a study copy. It returns the observation frame with DV/PRED/IPRED (plus RES/IRES/CWRES/IWRES
when derivable) for any frozen fit, including an `nlmixr2FitCore` with no `$aug`.

Use reference.docx styles, headers/footers, current captions and original image proportions.
Across all Word reports, give different figures distinct descriptive captions. Images with
the same caption in the same subsection form one numbered figure with A/B/C panels; keep
each panel's asset reference bound to that figure. Distinguish endpoint and analysis type.
Word assembly does not refit. A file's existence, boilerplate or successful pipeline checks do
not establish model validity. Review evidence; never fabricate study identity, balance, findings
or clinical implications. Missing metadata may remain absent.

For every body section, including Synopsis/Executive Summary, Results, Discussion and Conclusion,
describe the supported finding/trend/contrast, uncertainty or limitation and cite its figure/table.
Mention every included figure/table at least once, using stable narrative-packet reference tokens
resolved separately to HTML/Word numbering. Do not transcribe sample counts, percentages,
estimates, CI/SE/RSE, p-values, BIC or axis values just because they are available.
A value belongs only when the sentence explains its magnitude, uncertainty, threshold or decision
relevance; "as shown" or a locator sentence is not justification. Avoid repeating numerical findings
between sections. Figure/table numbers, endpoint names such as Grade 3, units, model definitions
and configured Methods thresholds remain legitimate. Review sentences containing data values
before binding narrative; remove redundancy without altering meaning, never strip digits blindly.
Discussion explains findings; Conclusion states the supported takeaway and material limitations.

Patient characteristics stratify by available study identifiers before Total. Claim balance only
after reviewing actual distributions. Do not repeat the unadjusted-quartile/binomial-interval
boilerplate. Keep reusable reference Methods wording with actual configured scales.
Tables follow Normal typography: numeric/statistical cells centered; long Covariate/Variable/
Characteristic cells left-aligned with word-boundary wrapping; smaller type only for dense/
over-wide tables or an explicitly specified table style.

Run node analyses_template/tools/report_narrative.mjs <study> --brief once per result version. Read its report
context and the tables or figures needed for each claim directly in the study. Use the current
manifests for additional locators. Keep intermediate files in the study. Bind reviewed source_md5 and exact evidence; refresh prose when
results change. Unsupported interpretation remains empty with a disclosed limitation and
completion pending, not invented paragraphs or internal errors/instructions in the report.

## Covariate intake (every report family)

Before submitting a new PPK/PKPD/TMDD/ER/c-QTc analysis, inspect the actual named study data
and supplied dictionary/prompt once. Use sh analyses_template/tools/data_peek.sh <actual-data> --covariates for
one compact field profile (missingness, range/levels, within-subject changes, exact duplicates);
interpret its facts using study semantics, not a mechanical type guess.
A report request includes preparing its covariate scope;
absence of a configuration is not permission to skip screening. Existing explicit user scope,
effect definitions and approved constants take precedence. Do not change an active run or
refit completed results merely to apply this default. Code-only requests remain covariate-free
unless the user asks for covariates.

Identify available baseline demographics, disease characteristics and laboratory variables,
including suitable fields outside template examples. Test all eligible fields within the
family's target scope; do not choose a biological subset or retain variables based on an
anticipated result. Determine continuous/categorical roles and references from actual coding
and metadata, never the number of distinct values alone. Exclude identifiers, study/group
administration, dose/regimen, time/visit, event/filter flags, exposure, observed endpoints,
postbaseline values, constants and exact duplicate aliases. Prefer one documented alias of
identical BW/WTBL; correlated but different covariates are not duplicate columns.
Verify baseline consistency within subject. Do not silently take the first changing value,
impute/recode data, invent units/race labels or derive clinical cutoffs. Missingness or ambiguous
baseline/coding needs a supported declared policy or one precise question while independent
work continues; record unevaluated variables as such, never as no effect.

Save the reviewed scope in study-root pmx_config.R, preserving existing overrides:

```r
COVARIATE_REVIEW <- data.frame(
  variable = c("AGE", "ALB", "SEX", "ID", "TIME", "DV"),
  role = c("continuous", "continuous", "categorical", "excluded", "excluded", "excluded"),
  reason = c("Baseline age", "Baseline laboratory value", "Documented sex coding",
             "Subject identifier", "Observation time", "Observed response"))
```

Cover all inspected input fields and declared derived variables; use continuous, categorical,
prespecified (c-QTc base adjustments only) or excluded with a reason for every exclusion.
Use the actual family-adapter/CTL field names; record source aliases in the reasons without
changing original columns. Fit-family base effects keep their continuous/categorical roles;
the pair plan identifies them as prespecified. The example is a schema, not a
fixed variable list. Empty eligible scope is valid only after this review, or an explicit user
opt-out recorded in the reasons. The pipeline logs COVARIATE_INTAKE and exports
table/_covariate_scope.csv. PMX_COVARIATE_INTAKE_REQUIRED means finish this authorized
preparation, not ask permission to do routine intake or submit the same incomplete job again.

- PPK/PKPD/TMDD: write covariates.csv for every eligible variable on both CL and the actual
  central-volume THETA symbol. The `param` column must carry the literal `$PK` THETA names
  (`TVCL` and the central-volume symbol such as `TVVC`/`TVV`/`TVV1`), never a derived parameter
  name such as `CL` or `VC`; copy the schema from word-report/covariates_template.csv and
  replace its variables/references/levels with the study's reviewed ones. Use the SCM owner and
  functional-form rules; keep approved BW powers 0.75/1. All nonreference categorical contrasts
  belong to one candidate per variable/parameter. The coverage check rejects missing pairs; a
  wrong THETA spelling fails as SCM_PARAMETER_SCOPE before that coverage check. Header-only CSV
  is permitted only with a reviewed empty eligible scope; human pair exclusions retain
  test=no/user_instruction.
- ER: explicitly set CON_COV/CAT_COV to reviewed fields, including character() when none.
  If a derived variable is the sole representation tested, classify it by its modeled type and
  mark its raw source as excluded with the reason and derived field name.
  Configure actual COV_LABEL/COV_UNIT/COV_LEVELS/COV_REF and disable unsupported example
  COV_DERIVE cutoffs. Keep the exposure-only base, endpoint-specific logistic/Cox screening
  and same-record comparisons. Descriptive demographics use the same reviewed field roles.
- c-QTc: use drug for the default report identity and exposure label. ANALYTE_NAME selects
  the concentration analyte when PCTEST contains multiple measurements.
  Explicitly set cov_want/cov_categorical and actual cov_label/cov_levels/cov_ref.
  Baseline QTcF remains a prespecified base adjustment in mandatory_cov, recorded with role
  prespecified; it is not BIC-screened again. Optional variables use existing matched-record
  BIC comparisons. Demographic availability does not alone establish model evaluability.

These declarations select the search scope, not the retained model. After fitting, check the
coverage/outcomes once: failed, missing, prespecified and excluded are distinct from evaluated
but not retained. No candidate evaluated never supports "no significant covariate". Use current
BIC/p-value semantics and preserve family estimators, selection criteria and uncertainty.

## Observation scale (all families)

Resolve the fitted observation scale from the selected DV alias and the Y prediction's
assignment chain, not an unrelated LOG() or a column name alone. A literal DV can already be
log-transformed; it is then converted once like any log response. Mixed endpoint scales use
the explicit per-endpoint PKPD contract instead of one guessed global scale.

- Assemble natural-scale fitted DV/PRED/IPRED once with pmx_fit_natural() (PPK/TMDD) or
  pmx_pkpd_aug() (PKPD). Residuals remain on their fitted scale and are never exponentiated.
- pmx_observed_dv() retains a dataset's natural DV unchanged when the fit aliases a different
  response column (e.g. DV=LNDV). Otherwise it reads/converts the actual selected model response
  once, including a log value stored under literal DV. Never apply another downstream transform.
- Convert simulator captures/population predictions and EBE exposure profiles once before
  natural-scale VPC comparisons or Cmax/Cavg/Ctrough calculation. Preserve declared simulator scales.
- REPORT_DV_SCALE and REPORT_OBSERVED_DV identify the choices; repair a mixed-scale comparison
  in shared code, never by rewriting the original study data.

Native fitted predictions/residuals take precedence. The shared fallback uses the paired model
with frozen parameters, zero ETAs for PRED and explicitly mapped frozen EBEs for IPRED. It
preserves record/endpoint identity, never random draws or ID/time-only deduplication. Weighted
residuals without a backend calculation stay unavailable rather than receiving an invented SD.

## PPK / PKPD / TMDD

Results interpretation, Discussion and Conclusion are required by default, not optional follow-up.
Use frozen S2 results/current assets and exact required_result_targets/section_results keys
(5.x; TMDD also 6.1). The first structured draft is evidence for authoring; NARRATIVE_REQUIRED
leaves S5 incomplete. Write the reviewed source-bound draft, bind via report_narrative.mjs
--write <draft>, then validate check_narrative.mjs --require-discussion-conclusion.
Only an explicit user opt-out permits report_metadata.dcf Narrative: omit with NarrativeReason.
Missing evidence is never an agent-approved opt-out.
Refresh through --from=s5 for Word or --from=s4 for HTML/assets/Word, not screening/SCM/covariance.

PPK, PKPD and TMDD Word include observed versus PRED/IPRED (linear and supported log views)
and native CWRES versus TIME/PRED, separately for each modeled endpoint, in Model evaluation.
Never exclude a required diagnostic merely because its HTML section is named Goodness-of-Fit.
Covariate correlation, EBE distribution/correlation, individual fits and supplemental weighted-
residual/QQ/fitted-time-profile panels remain HTML-only evidence. All use
word-report/ppk_report_support.R for diagnostic plotting, figure selection and covariate layout.
Frozen FitCore objects without residual tables require one native addTable(cwres=TRUE,
npde=FALSE) evaluation on nlmixrClone(fit), with the stored censoring method and original
row mapping. This is report-only work: no optimizer, covariance, EBE updating or fitting.
Verify theta/omega/ETAs/objective remain unchanged. Use the backend source-row map
(`nlmixrRowNums` / fit environment `.rownum`), checked against original ID/TIME, to copy
only diagnostic columns onto original records. Preserve original CMT/DVID and their native
NMCMT/NMDVID companions; backend compartment names/endpoint indices are not join keys.
Reject missing, conflicting or duplicate row provenance; never infer it from CMT.1, sorted
labels, endpoint order or repeated ID/TIME occurrences. Do not substitute IWRES or simulated
residuals for CWRES. A presentation mismatch never authorizes renaming compartments or refitting.
Dedicated CWRES use finite native backend values,
separately by observation endpoint, without fabricated residuals or empty zero-line plots;
unavailable diagnostics are disclosed. Every Word image is verified against the current HTML.
Remove the Dose level covariate-impact subsection and its figures; renumber the remaining
default subsections consecutively. Keep actual dose/regimen inputs in the simulations.
Use descriptive endpoint/analysis captions, including VPC versus pcVPC. Put covariate figures under matching
5.6.x subsections (PPK/PKPD) or 5.7.x (TMDD), using supported PK/drug exposure and PD/target
predictions. Reuse the complete frozen paired simulator when a legacy EBE simulator exposes
only drug. All impact figures display model-predicted profiles/summaries from frozen individual
estimates; recorded dosing is a simulation input, never a claim that plotted values are observations.
Captions start Model-predicted. Regular repeated regimens use the existing fixed 50 conditioning
intervals and summarize the next interval as Cmax/Cavg/Ctrough. Do not test adjacent cycles,
exclude patients for periodicity, or switch those patients to Clast/follow-up plots. Numerical
failure remains unavailable rather than receiving fabricated values. Single-dose/irregular
recorded regimens use Cmax/Cavg/Clast; Clast is not Ctrough. Continuous and categorical plots
share predictions, metric definitions/order and regimen handling; only grouping differs.
Use two-column metric panels with additional rows and matching figure heights; switch to one
column for crowded labels. Keep x-axis labels on one line; do not insert range/word breaks, dodge labels,
or drop groups. Give crowded labels a full-width metric panel.
Fit-family summaries, parameters, plots and narrative use study-root data_spec.csv names,
units and confirmed category labels (variable,label,description,type,unit,code,value_label,status).
Repeated categorical rows document each code; status=confirmed permits the mapping. The
study dictionary takes precedence; pmx_config.R COV_LABEL/COV_UNIT/COV_LEVELS and
COVARIATE_REVIEW units are fallback metadata. Numeric sex/race codes have no universal
meaning: ask once for missing labels, never invent a mapping or silently print the code.
Presentation decoding never changes raw data, model equations, contrasts or references.
Dictionary edits refresh HTML/Word evidence only; never restart SCM for display changes. Legacy reviewed range/unit notation is accepted literally; never
infer units from magnitudes or hardcode g/L. Omit undeclared units; never rescale data for labels.
An observation at the requested prediction time is not required for each patient. Use the study's
PredictionWindowHours in report_metadata.dcf when supplied; otherwise use the full study-level
sampling-time range, not the shortest individual follow-up. Mark prediction duration/provenance
and discuss extrapolation when appropriate; never invent repeat dosing for a single-dose study.
Fit-family descriptive impact plots use integer display cutoffs for BW/WTBL, BMI and age.
With declared matching units, defaults are BW/WTBL (kg): 60/80, BMI (kg/m2): 25/30,
age (years): 65, and CRCL (mL/min): 30/60/90. Show exact interval labels such as <60,
60–<80 and ≥80; assign patients using unrounded values, with the cutoff in the upper group.
These are descriptive bins, not clinical classifications or changes to SCM effects.
An optional data_spec.csv group_cutpoints column (e.g. BW: 60;80, age: 65) overrides
defaults without rounding. Keep display overrides out of SCM configuration; dictionary
changes invalidate report stages only.
For BW/BMI/age in other or undeclared units, choose rounded subject-level quantile cutpoints
on an integer grid (BW: 10, BMI/age: 5), without converting units or reusing kg/year cutoffs.
Other continuous variables retain finite observed-range labels and unit-appropriate precision
(e.g. albumin in g/dL); never print Inf or round the underlying measurements.
Screen/SCM/S1C/S2 use the estimator-specific verdict in references/fit_workflow.md. Normal-exit
objective-history warnings remain disclosed, not relabelled as failed convergence; true invalid
fits remain blocked. Covariance completion establishes neither convergence nor predictive adequacy.
VPC uses all frozen model data parameters (including supplied base covariates), actual events,
endpoint-specific response scales and the original simulation count/seed. Compare deterministic
zero-ETA/zero-EPS predictions record by record, not stochastic medians; nonlinear IIV can shift
those medians. Run the deterministic check before stochastic replicates. On a mismatch,
make at most one strict native solve at the same frozen parameters/zero ETAs/EPS; this is
not optimization or covariance. Continue only if that independent native reference agrees
with the simulator at the unchanged comparison tolerance, recording numerical drift and
using one validated population reference for observed/simulated pcVPC correction. Frozen
GOF predictions, fitted estimates and uncertainty stay unchanged. Both solvers are numerical;
a small percentage alone never proves a translation is correct or an error irreducible.
Write table/_simulator_validation.json with input coverage, failure counts, maximum absolute/
relative discrepancies, endpoint summaries, worst records and strict-reference settings.
Read that named artifact once on failure; never inject diagnostics into a study Rmd.
PMX_SIM_CHECK_RTOL/ATOL default to 1e-3/1e-8. Looser values require explicit human approval,
PMX_SIM_CHECK_APPROVED=true and PMX_SIM_CHECK_REASON; transport/hash them as report policy,
not estimator settings. No automatic tolerance escalation or check opt-out.
Every replicate retains the observation-record multiset; missing/non-finite
simulations are errors, not dropped rows. A poor VPC with consistent simulation is model evidence,
not permission to retune the model, axes, residuals or sample count. Read table/_exposure_audit.csv once when figures
are unavailable, then repair the named template cause without repeating unchanged Word renders.
New exposure figures require report-only S4 -> S3 -> S5 with --from=s4 --refresh-templates;
Word-only/S5 cannot add figures absent from the published HTML. Preserve scientific study
settings during the template refresh and reuse S1/S1C/S2; never restart parameter estimation.
Missing evaluable predictions/groups require a limitation, never an empty impact
chapter or a claim of no effect. Preserve simulator scales, actual EBEs, estimators, VPC count
and seed; these report changes never authorize fitting. ER/c-QTc retain their own applicable
figure/model rules rather than inheriting fit-family omissions.

Fit-family parameter tables use separate Fixed Effects, Covariate Effects,
Interindividual Variability and Residual Variability blocks. IIV rows show variance (%CV),
variance-scale RSE (%) and shrinkage; %CV is defined only for log-normal effects. Corr rows
show omega_ij/sqrt(omega_ii*omega_jj), never untransformed covariance labelled correlation.
Residual rows are Proportional term or Additive term with declared observation units/log
scale where known. Preserve supported 95% CI and native uncertainty; never borrow structural
SE/RSE for IIV or covariance RSE for correlation. Group headings are bold and merged;
section-specific column headings distinguish %CV from 95% confidence limits.

PPK Word contains base/final parameters with supported 95% CI/%RSE and all SCM comparison
outcomes; failed fits carry no estimates. Covariance policy is in references/fit_workflow.md.
Route exposure figures into their matching 5.6.x subsections by caption, using current HTML.
Appendix D.1 reproduces root final_model.ctl records while omitting toolkit-only header comments; fitted table/simulation quantities come
from frozen S2, not from replacing the printed control stream's starts. D.2 embeds the native
printed summary of the frozen final fit as preformatted text, including estimation messages
and warnings; this technical appendix may reproduce parameter tables. It does not run or
queue another fit and is not a complete iteration-by-iteration NONMEM listing.

## ER / c-QTc

ER logistic/Cox fits must have finite estimable coefficients/covariance without convergence or
separation warnings. c-QTc comparisons/final slopes use clean fits from the existing disclosed
random-effects ladder, keeping matched records/structures. Failed covariates leave assessment
partial, never a no-effect claim; unavailable logistic curves retain the observed summaries.

Use the corresponding run_er.sh/run_cqtc.sh wrapper and the completion rules below.
No NONMEM ladder or fit-family SCM route. Identify real input/coding and use --state once;
RUN_STATE and output/run_manifest.json are authoritative, not staging timestamps.
NOT_RUN/NEVER_QUEUED/DEBRIS: follow the named submission action. RUNNING: observe the existing id.
UNPUBLISHED: collect once. FAILED: read the named error once and stop unchanged deterministic
retries. Empty/orphan mirrors cannot acquire job progress; do not loop directory listings.

Full reports require Discussion/Conclusion unless the user requests analysis/HTML only.
After initial publication, run report_narrative.mjs <dir> --brief and review the listed
study context, safety results and relevant figures. An empty safety-table list is an answered lookup: use listed figures/current
structured results once or disclose insufficient evidence, never repeatedly read the manifest.
Write .pmx/narrative_sections.json with reviewed source_md5; --write <draft> binds evidence;
validate --require-discussion-conclusion, then wrapper --word-only --async once.
NARRATIVE_REQUIRED is authoring; NARRATIVE_REVIEW_REQUIRED repairs rejected prose/evidence;
WORD_REFRESH_REQUIRED is Word only; WORD_RUNTIME_REQUIRED is a runtime blocker.
Do not hand-submit Word jobs or rerun analysis to clear template warnings.

For ER result subsections, use optional section_results with exact current section_targets and
supported paragraph arrays. Interpret exposure-response trends/uncertainty and statistically
supported covariate contrasts/directions; BIC retention is not statistical significance.
If plots cannot be reviewed or evidence is insufficient, retain the explicit bracketed
placeholder and disclose the limitation, without resubmitting analysis or copying another
study's cohort counts, drug findings or flat/comparable-relationship claims.
Parameter tables use Parameter, not Term, and screening cov_lab/comparison labels:
bold variable header with blank statistical cells, indented category contrasts without N counts;
actual fitted reference levels govern direction.

Follow references/study_layout.md for ER/c-QTc outputs and readable flat-file compatibility.
Do not duplicate the location contract in a report-specific rule file.

COMPLETE or *_ALREADY_COMPLETE ends report generation: give paths and recorded warnings/
limitations, then end the turn. Do not follow with repeated DOCX/hash/time/prose/status probes.
Scientific/content/visual review is a separate explicitly requested goal: inspect unchanged
relevant artifacts once and recheck only a concrete changed artifact.
Repeated probes stop by question and artifact version, not command spelling; an active
observer/verified new completion still permits automatic continuation.


Use one active background observer and the current continuation
contract. Missing background capability is a blocker; keep no-output/status probes bounded.
After publication, --state supplies the final decision. COMPLETE means pipeline checks passed,
not scientific validation. Final replies include deliverable paths and recorded warnings.
Only changed evidence/artifacts or a new user question reopens an answered check; command
spelling changes do not. Give phase-transition/progress updates and a human-readable result.

For ER safety sections, interpret increasing, approximately flat, decreasing, nonmonotonic
or unclear patterns from current rates/intervals and logistic plots. Nonsignificance does
not establish flatness. Group supported patterns by named endpoint in Discussion and explain
uncertainty; missing adjustment limits the claim, not the ability to describe observed trends.
Keep unsupported safety placeholders and disclose limitations; never refit just to fill prose.
Captions navigate evidence and are not interpreted results. Reference tokens such as
{{figure:html_fig_01.png}} resolve after output filtering; do not cite HTML-only assets as
numbered Word figures.

## ER HTML only

Use analyses_template/er/er_analysis.Rmd, configure only the requested efficacy/safety and
logistic/KM/Cox blocks in the study configuration, then run_er.sh <study> --no-word. There
is no separate root er_analysis.Rmd. HTML-only work does not require Word or agent narrative.
Keep actual input/reference levels, matched-sample BIC comparisons, effect uncertainty and
configured forest plots; never replace them with a different legacy template.

PPK/PKPD/TMDD reports include one model structure figure at the start of Results / Base Model,
before parameter tables. Render base_model.ctl through the shared SVG skeletons and
word-report/model_diagram.R (references/rules_deliverables.md, Structure diagram rules).
HTML embeds the PNG; Word extracts the same image into 5.2 Base model, never Methods.
Missing structure assets require an S4/S3 report-only refresh, not silent omission or refitting.
Preserve study configuration and VPC simulations when refreshing the family Rmd.

## One home for shared logic

Toolkit behaviour is implemented once and called everywhere else. Shared report/analysis
helpers live in `analyses_template/_shared/` (report chunks) or `word-report/**` (pipeline
code); family templates and a study's copied template only *call* them.

- If a fix would need the same change in two family templates, or in a study's copy of a
  template, the defect is in the shared source: repair it there, not in the copies. Never
  hand-edit a study copy of a template; refresh it (`--refresh-templates`).
- Do not copy a template into a study directory as part of a fix. `02_html/<family>_report.Rmd`
  is produced by `analyses_template/tools/run_analysis.sh <dir> --refresh-templates`, at run time, and only when
  a run is authorized; a template repair alone leaves every study file untouched.
- Never fork an existing helper into a second file or a second family. All families call the same implementation and artifact contract.
- Never paper over a failure with a silent `tryCatch`, an empty result or a retry that hides
  it. Detect the fault at the earliest stage that can name it, and let it fail there with the
  real message (an uncompilable paired simulator must stop S2 with the C++ error, not crash
  the S4 knit).
- One artifact, one contract: names a report consumes (e.g. the simulator `$CAPTURE` set) are
  declared once in toolkit source, not restated per family.

