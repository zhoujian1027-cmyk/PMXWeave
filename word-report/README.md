# Word reports from current analysis results

The shared generator uses reference.docx for styles, headers and footers. Family files supply report identities and the original numbered section trees, without prewritten results. Tables/figures are placed by extraction manifests, so omitted endpoints cannot shift a positional table number into the wrong section. New SCM RDS names include family, model, search/covariance stage and candidate tag, followed by the full content hash; legacy hash-only caches remain readable. No fit is started during Word assembly. Fit families have separate S1 search and S1C covariance job windows. S1C reuses the matching fitted estimates, computes base and final uncertainty by default for PPK (final only for other families), and preserves completed search results on failure; `PMX_COV_BASE=true` requests base covariance. `run_analysis.sh --covariance-only` runs S1C without NCA, screening or SCM.

Screening retains all rounds and outcomes in `01_screen/ladder_table.csv`, with data/model
fingerprints and selection flags. PPK HTML retains screening history; Word omits that history,
EBE distribution/correlation, individual-fit and supplemental diagnostic panels. Word includes
observed versus PRED/IPRED and native CWRES versus TIME/PRED for every modeled endpoint;
Missing native CWRES in a frozen FitCore triggers one report-only native residual-table
evaluation on a private clone, preserving fitted parameters, omega, ETAs and objective.
The shared augmentation helper copies diagnostics by verified backend source-row numbers
(.rownum/nlmixrRowNums) onto original records, keeping numeric source CMT/DVID even when
native tables contain named/remapped compartments. ID/TIME verify row provenance; repeated
time/endpoint records stay distinct. Missing/conflicting maps stop, without guessed CMT.1
selection, model changes, estimation, covariance or generic residual substitutes.
PPK/PKPD/TMDD Word figure selection, native CWRES and covariate-impact placement follow
references/report_rules.md, PPK / PKPD / TMDD. BIC comparisons use one compatible round. S1 imports the verified selected screen fit rather
than optimizing the base again. Do not author a promoted M07 or overwrite the six-model
comparison. Cache/identity mismatches stop for review.

## Inputs

- Fit families: the current S2 final.rds, final_model.ctl, original data and the S3 manifests/assets.
- ER/c-QTc: output/report_results.rds from the Rmd plus extracted manifests/assets and original data.
- Fit-family display metadata comes from study-root data_spec.csv: variable,label,description,type,unit,code,value_label,status. Use repeated code rows and status=confirmed for categorical mappings. The dictionary overrides fallback pmx_config.R COV_LABEL/COV_UNIT/COV_LEVELS and COVARIATE_REVIEW units; never guess numeric sex/race labels. All covariate summaries, contrasts, plots and narrative use the same names without recoding model data. The dictionary is tracked in report evidence and S4/S5 inputs; metadata changes do not refit models.
- Optional report_metadata.dcf: Title, Project, Study, Drug, Indication and Prepared by. Missing identification fields are omitted, never fabricated. PredictionWindowHours optionally declares a positive model-prediction duration in hours for recorded-regimen covariate-impact plots; individual measurements at that time are not required.
- report_narrative.json: evidence-backed narrative, required by default for full reports and placed under the family's original headings; only explicit user opt-out makes required sections optional.
- If Word fails because officer/flextable cannot load a native dependency, run `sh analyses_template/tools/preflight_word.sh <analysis-dir>` once and inspect the named environment error. Install the required operating-system packages in the authorized worker image; resubmitting an unchanged job cannot repair it. This distribution does not include a copied `libwebpmux.so.3` binary. See `lib/README.md`.
- `preload_word_libs.R` retains support for explicitly supplied deployment fallback libraries. A clean installation must satisfy system dependencies itself. `analyses_template/tools/word_image_fix.sh` is an environment-maintenance helper requiring the actual deployment configuration; its binary-copy fallback is unavailable unless the deployment separately supplies that library.

The generator verifies the input-data fingerprint and, for fit families, artifacts/s2/final_fitted.ctl against the frozen final result (legacy fitted root controls remain readable). Root final_model.ctl retains updated base initials plus covariate starts; it is not substituted for fitted report/simulation quantities. Refresh older results that have no data fingerprint. Default prose states measured quantities, model formulas and retained covariates only. It never asserts model adequacy, clinical relevance, causality or a dosing decision from a p-value.

### Data sections for PPK, PK/PD and TMDD

The report shows the available study identifiers and analyzed cohort counts.
Use the following optional fields in `report_metadata.dcf` to report verified
study-specific details. Use the actual analysis record for every method claim.

| Field | Suggested wording to adapt |
|---|---|
| `StudiesIncluded` | Data from studies [IDs] were included. These studies enrolled [populations] and evaluated [routes and dose regimens]. |
| `AnalysisDataset` | The analysis included [N] participants and [n] usable observations. Report PK and PD or target counts separately when applicable. |
| `BioanalyticalMethods` | [Analyte or endpoint] was measured by [assay] in [matrix]. The lower limit of quantification (LLOQ) was [value and unit] for [study or assay]. |
| `DataAssembly` | Observations were linked to [recorded or nominal] dosing and sampling times. [Describe verified units, endpoint coding and response transformations.] |
| `BLQHandling` | [n/N (%)] observations were below the LLOQ. [Describe the implemented handling, such as exclusion from estimation or left censoring.] Report the rationale and any sensitivity comparison that was run. |
| `DataErrors` | Records with [documented issue] were [corrected or excluded] after [review]. State the counts and reasons. |
| `OutlierHandling` | Potential outliers were flagged using [prespecified criterion, for example absolute CWRES greater than 5] and reviewed against the source records. State how many were flagged, retained or excluded, with reasons and any sensitivity analysis that was run. |
| `BaselineResponse` | For PK/PD, describe observed baseline collection or the fitted initial condition, according to the actual model and data. |
| `MissingCovariates` | Report the extent of missingness in the evaluated covariates and the implemented handling for each. |

A large residual is a review flag. Record a source-supported reason for any
exclusion and, when warranted, evaluate its influence with a sensitivity fit.
Select BLQ handling for the assay, data and analysis objective. Report
likelihood-based censoring only when the fitting backend actually used it.
See the [FDA population PK guidance](https://www.fda.gov/media/128793/download)
and the [evaluation of likelihood-based BLQ methods](https://pubmed.ncbi.nlm.nih.gov/18686017/).


## Agent workflow for study prose

1. Collect/publish the analysis and initial Word once. A full ER/c-QTc report also requires agent-authored Discussion and Conclusion; `analysis_state=complete` with `report_state=needs_narrative` is an intermediate result, not final delivery. An explicit HTML/analysis-only request does not require these sections.
2. Run `node analyses_template/tools/report_narrative.mjs <dir> --brief` once. It verifies evidence hashes and names the study files that contain the estimates, uncertainty, factor coding, tables and figures. It submits nothing. Never queue an R script to print the result RDS; Legacy reports without the JSON snapshot use the current tables and must disclose unavailable metadata rather than infer comparison coding.
3. Read the relevant diagnostic figures and author two concise, supported sections in `<dir>/.pmx/narrative_sections.json`: `source_md5` from the review packet, plus `sections.Discussion` and `sections.Conclusion` arrays. Discuss direction, uncertainty, retained/prespecified covariates, population and limitations. c-QTc threshold claims need predicted change and its interval at the relevant exposure; ER safety curves are exploratory unless an adjusted model was actually fitted. No causal or dosing claim follows from a p-value alone.
4. Run `node analyses_template/tools/report_narrative.mjs <dir> --write <draft.json>` to create `report_narrative.json` with exact current evidence hashes. It does not author prose or re-anchor a stale draft. Check with `node analyses_template/tools/check_narrative.mjs <dir> --require-discussion-conclusion`; invalid or incomplete prose stops before submission. Changed results require fresh interpretation, never replacing source_md5 alone.
5. Refresh Word once using `sh analyses_template/tools/run_er.sh <dir> --word-only` or `run_cqtc.sh`. No Rmd render or refit. Confirm `report_state=complete` and accepted prose; ALREADY_COMPLETE stops further work. If interpretation cannot be justified, report the specific limitation to the user and stop; never fill report headings with workflow warnings or invented conclusions.

Example shape (replace all example values with current evidence; do not deliver this example as prose):

```json
{
  "source_md5": "current-result-file-md5",
  "evidence": [{"file": "output/report_results.rds", "md5": "current-result-file-md5"}],
  "sections": {"Discussion": ["Study-specific interpretation supported by the current results."], "Conclusion": ["A conclusion limited to the supported findings."]}
}
```

An absent, malformed or stale narrative is omitted with a console diagnostic and leaves required report completion pending. It is not printed into Word. Source hashes prevent accidental reuse; they do not automatically prove the scientific interpretation. The agent must read the evidence and update its prose.

## Section lead-in sentences

Each section may open with one qualitative sentence that states the reading of its own figure(s) and table(s), so a reader who stops at a section still knows what it shows. The engine default is word-report/section_leads.R; a study replaces or extends it by placing report_section_leads.R beside its data, and that file may call section_lead_default() to keep the generic behaviour.

Contract: `section_lead(fam, section, dir, result)` returns character(0) or one sentence, receiving the section heading exactly as written in family/<fam>.R and the frozen result contract. Two rules are enforced by the generator, not by the author: a sentence containing any digit is dropped, and a section with no sentence stays a bare heading. The digit rule is what keeps a lead-in from restating a value that is tabulated in the same section - duplicating a number is how two parts of one report start to disagree. The engine default derives direction from the frozen estimate and its standard error and says nothing about magnitude, adequacy, causality or clinical relevance. An unreadable or erroring module prints a SECTION_LEAD diagnostic and leaves the report as it is.

## One narrative gate for both deliverables

The Word report and the HTML report must accept or reject report_narrative.json identically, otherwise the same frozen results can be presented as two different Discussions. Both now use pmx_narrative_gate() in result_narrative.R: source_md5 must equal the current output/report_results.rds hash, every evidence entry must exist with its recorded hash, and evidence paths must stay study-relative.

A study Rmd (or script) obtains the already-validated sections with one call, and falls back to its own result-backed prose when it returns NULL:

```r
source(file.path(Sys.getenv("PMX_WORD_REPORT"),"result_narrative.R"))  # or the word-report directory
narr <- pmx_narrative_sections(".", "er", DATA_FILE)
if (!is.null(narr$Discussion)) for (p in narr$Discussion) cat(p, "\n\n")
```

A report that writes its own discussion text inline, without going through the gate, will not be updated by a prose-only edit and will not agree with the Word deliverable; that is a defect in the report source, not in the narrative.

## Assembly — through the study wrapper, never from a copy

```sh
sh analyses_template/tools/run_er.sh <study-dir> --word-only      # or: sh analyses_template/tools/run_cqtc.sh <study-dir> --word-only
```

`--word-only` stages the published HTML, `output/`, `table/`, `figure/`, `report_narrative.json`, `report_metadata.dcf` and `word-report/` into the job, re-renders the .docx, renders no Rmd and refits nothing. It is the only supported prose refresh.

The generator is invoked **in place, from the toolkit directory the wrapper stages** (`.pmx/word-report/report_generator.R`). It refuses to run from a copy: a hand-built job — a scratch script with `commandArgs <- function(...) c(...)` appended — evaluates that override *after* the argument parsing has already run, so it dies with `Specify a supported --family`, and the copy carries neither `family/` nor `result_narrative.R` anyway. That shape now fails immediately with `WORD_SCRIPT_COPY` instead of after a queue wait.

A direct `Rscript .../report_generator.R <dir> --family er --data <dir>/actual.csv` still works **only when run from a complete toolkit directory** (one holding both `report_generator.R` and `reference.docx`); it is a debugging entry point, not a delivery path, because it stages no optional input. Fit-family S5 supplies the grouped table/figure directories automatically. Direct calls may specify --table-dir, --fig-dir, --ctl and --out. --no-figures omits figures without inserting missing-figure warnings.

Word tables repeat their header and avoid splitting individual rows; image aspect ratios come from the extraction manifest. Source inspection alone does not verify page appearance.

Field assembly: the generator calls apply_reference.py on its temporary DOCX before publishing. PMX_PYTHON may select the queue-worker interpreter. Contents, figure and table lists are updateable Word fields; pagination requires rendering or Word field updates. Captions accept either `Table 1.` or `Table 1:`. If field assembly fails, the previous deliverable is preserved and the error stays in the console.

## c-QTc Discussion and Conclusion

A full c-QTc report uses the same agent-authored report_narrative.json as ER, with separate Discussion and Conclusion headings in Word. Read current estimates, uncertainty and diagnostics before writing either section; changed results require reinterpreting the evidence, not updating hashes alone. Use analyses_template/tools/run_cqtc.sh <dir> --word-only for a Word refresh. The c-QTc HTML template reads the same validated sections during a full render; Word-only refresh does not change HTML. Empty or rejected narrative leaves the headings without unsupported findings. HTML narrative must pass the same evidence gate; do not claim that a Word-only update changed either HTML report.

ER/c-QTc output layout: used Rmd/configuration and final reports stay in root. Structured results, report_context.json, completion/evidence JSON and endpoint/label indexes go in output/. Named analysis CSVs are optional (ER SAVE_OUTPUTS=TRUE) and go in table/analysis/. Word assets stay in table/ and figure/. Readers accept legacy flat paths; do not rerun a study just to relocate files.

Narrative review is semantic as well as content-keyed: use the fitted categorical contrasts and their actual derived-variable definitions; distinguish log-coefficient RSE from effect-ratio uncertainty; distinguish fitted exploratory safety curves from formal multivariable models. A nonmonotonic sequence of quartile medians alone does not show a direction opposite to a hazard-ratio estimate. File/hash checks do not validate these interpretations.

ER narrative sections may also supply Introduction, Objectives, ExposureMeasures, DataAssembly, DataHandling, Methods, CovariateAnalysis, Software and References through the same evidence gate. New ER result bundles carry default methods text, actual model factor references, raw coefficients and derivation definitions. Leave unsupported references absent; Word omits an empty References section. Full-model Word tables use frozen raw estimates, so Word-only refresh can repair rounded coefficients without refitting. Review actual fitted N separately from population N.

## c-QTc presentation and reusable methods

Word 4.2 follows Data Exploration, Base Model, Full Model (including the covariate screen), Diagnostics and Simulations. The tumour-type visit plot, hysteresis figures and concentration-QTcF relationship/goodness-of-fit statistics table stay in HTML only, with their evidence retained for review. See pub/cqtc.md for the current display and routing contract.

The c-QTc base model includes concentration and prespecified baseline QTcF when available and estimable. Optional covariates are screened against that adjusted base with matched records and actual random-effects structures. Baseline QTcF is not BIC-selected. Demographic and screening tables follow ER layout, including continuous-before-categorical ordering, bold parent labels, indented categories, compact confidence limits and categorical-parent BIC/retention. Base/full parameter tables combine fixed and random estimates, with BIC once; identical full/final fits do not produce another final table.

Outlier prose is generated from unique threshold-flagged records and participants. Category counts can overlap; flags alone do not remove records in this template. Missing absolute QTcF means its threshold counts are not assessed, rather than zero.

Reusable prose covers the analysis objective, supplied paired records, units without conversion, the Fridericia/Delta-QTcF definitions, actual missing-data handling, maximum-likelihood fitting, matched-sample covariate comparisons, diagnostic purpose and prediction-interval interpretation. Counts, model structure, available data and software versions come from the current results/configuration. CONC_UNIT accepts the study's concentration unit. PAIRING_METHOD and BASELINE_DEFINITION accept the source matching and baseline rules; empty settings do not invent a protocol-specific baseline or pairing algorithm.

Do not prefill drug mechanisms, assay/ECG schedules, data reanalysis history, a Cycle-1-Day-1 baseline rule, absence of hysteresis, model adequacy or a QT threshold conclusion. The reference photographs illustrate layout, not reusable study findings. Slope/mean-response intervals and individual prediction intervals are distinct; the main prediction plot retains its current 95% mean-response band, while binned/slope summaries identify 90% intervals. Study narrative can override the method sections through the existing evidence gate.

## ER methods, result sections and shared Word typography

The base model remains exposure only. The full-model covariate list is data-selected, never a prespecified base-model list, and is no longer printed as an endpoint formula under Methods. The photographed logistic/Cox method paragraphs, formulas and definitions are retained with a generic exposure symbol; the condition of fitting only after a positive graphical association is omitted because this template does not implement it. Covariate-analysis and software prose follow the photographed wording, without fixed table numbers, R version, drug, dose or trial-cohort text.

Base/full coefficient tables omit Effect (95% CI); ratios and uncertainty remain available in the result context and covariate-effect forest plots. Median time and its 95% limits share one column: Median <endpoint> (months, 95% CI), value median (lower–upper), preserving NR/NE. Forest labels and percentiles use the fitted complete-case sample. Exposure-only/all-continuous Cox models produce forests without requiring a categorical label column; raw-exposure mappings are supported too. Only fitted terms are used for forest contrasts; plots are printed explicitly. Non-estimable plots are described without internal errors, with the cause recorded in structured output.

Shared Word tables use the reference Normal font family/size (currently Times New Roman, 11 pt), centre numeric/statistical content, left-align Covariate/Variables/Characteristic columns, and reduce size only for dense or otherwise over-wide tables. Density means at least eight columns, six columns with very long cells, or more than 35 rows with at least five columns. ER univariable screening defaults to one point below Normal; other tables retain these density rules. Reference headings, captions, headers/footers and figure proportions are retained.

ER graphical/regression Results use explicit bracketed interpretation placeholders until reviewed. The agent writes exposure-response trends, uncertainty and supported regression/covariate effects in section_results, using exact report_narrative.mjs er_interpretation_targets and paragraph arrays. Describe actual factor contrasts and directions; distinguish BIC retention from statistical significance. Do not replace interpretation with methods or figure-navigation boilerplate. Unsupported or inaccessible evidence leaves the placeholder visible and is reported to the user, without another analysis job. The --write mode binds them to current evidence, and Word-only refresh places them under those same headings. Unsupported population comparisons, flat-response conclusions and clinical/dose claims are never prefilled from the reference photographs. Hash/shape checks do not establish scientific correctness. Methods overrides remain available through sections.Methods and sections.CovariateAnalysis.

ER/c-QTc terminal stop: read references/report_rules.md. RUN_STATE COMPLETE or *_ALREADY_COMPLETE ends the requested report-generation task: give the report paths and recorded limitations, then end the turn. Do not follow it with repeated DOCX/text/hash/mtime probes or compression/status calls. Repeated checks are identified by question and artifact version, not by command spelling; changing quotes or search terms does not reopen an answered check. A repeat-guard warning/block stops that repeated probe; keep live work WAITING with its observer, and resume only on verified new completion or human input. Never bypass the guard. Explicit user-requested content/visual review is a separate goal: review each unchanged relevant artifact once and recheck only a concrete changed artifact. Always give a human-readable final result or blocker. ER/c-QTc keep their wrapper routing. Follow references/continuation.md for automatic continuation.

## Long table labels and ER equation layout

Covariate, Variables and Characteristic columns are left-aligned in Word. Long labels wrap at
spaces with separate lines for group counts and summary descriptors. Columns reserve space
for whole header words and give descriptive labels additional width; headings wrap at word
boundaries, rather than shrinking all columns proportionally to a long label. Statistical
values stay centred. Reference Normal typography remains the default; only dense/over-wide
tables use smaller type, except ER screening defaults to Normal minus one point. HTML baseline and screening tables have the same label alignment.

ER section 3.5 keeps the original methods wording. Logistic/Cox equations are bold and centred;
parameter definitions have a 0.25-inch left indent in Word and a corresponding indent in HTML.
Only presentation is changed, with no refitting or reinterpretation of results.

For ER and c-QTc Discussion/Conclusion, explain findings rather than restating Results.
Do not repeat sample counts, coefficients, SEs, CIs, p-values, BICs or other table numbers by
default, or repeat a numeric summary between the two sections. Include a specific value only
when explaining its magnitude, uncertainty, threshold meaning or another substantive point;
keep only the values needed for that explanation. Conclusions should state the supported
takeaway and material limitations. Do not mechanically strip necessary numbers or alter them.

CQTC quality: reference footer ids are numeric and assembly resolves them against destination
relationships. Summary/Synopsis/Executive Summary starts on a new Word page. Table body padding
is 2 pt vertically and 4 pt horizontally; headers retain 3 pt. Parameter labels are left-aligned.
CQTC model-summary displays omit both R2 columns, including legacy extracted tables on Word-only
refresh. Concentration units are explicit metadata; absent units are marked unspecified, with
no guessed conversion. Hysteresis defaults to patient panels with time arrows (max 12 per figure),
with an optional overview. Plot availability is distinct from scientific review.

Current lme4 tables contain random SD/correlation estimates, but no directly supplied SE/CI for
those estimates. The uncertainty cells show — (not computed); no profile/bootstrap fitting is
added to HTML/Word assembly. Reliable variance-component CI estimation would be a separately
requested analysis step, never a formatting retry.

ER display refinement: omit Report control; abbreviations are an unnumbered front-matter table
on their own page. Synopsis and Introduction each start on a new page. Disposition is left-aligned.
Baseline N_total stays inline with its variable name. Screening groups each variable once, bolds
its name, leaves categorical heading statistics blank, indents comparison rows one character,
retains every coefficient/comparison row, omits comparison counts, and uses magnitude-based
precision (up to two decimals, two significant digits below one, scientific notation below 0.0001). Group-level BIC/selection
appears once on the first comparison row, never the categorical heading. Display transformed exposure terms as Log(actual exposure column), never infer
transformation from the first letter alone. Median tables use the full text width, with a wider
median/CI column. No routine SE/RSE explanatory paragraph follows the coefficient tables.

Graphical analyses contains descriptive bar/KM plots. A binary endpoint's logistic fitted graph
belongs immediately after its base estimates, followed by screening and non-duplicate full estimates and a
Covariate effect plot of <endpoint> <regression> full model. When full and base have identical formulas, fitted rows and estimates with no retained covariates, omit the repeated full table and state at the model-section opening that no covariates met the configured selection criteria. Absent evaluable screening is described separately. The exposure-effect forest is retained. Response-rate/logistic/KM captions describe the endpoint and exposure; figures have explicit captions separate from numbered headings;
extraction keeps these captions and optional cell bold-prefix metadata in existing manifests.
Word retains legacy-manifest fallback. Captions contain Table/Figure numbering, not subsection
numbers. No statistical fitting, variable coding or model-selection rule changes.


PPK/PKPD/TMDD report prose is required by default and source-bound: `analyses_template/tools/report_narrative.mjs <dir> --brief` reads
frozen S2 evidence and exposes exact current section_targets. Author supported section_results
 and sections.Discussion/sections.Conclusion; exclude unsupported claims and numeric inventories. Use --write,
then check_narrative.mjs --require-discussion-conclusion. Refresh only Word with
run_analysis.sh <dir> --family=<family> --data=<original.csv> --from=s5; --from=s4 refreshes
HTML/extracted assets/Word from frozen inputs, without screening/SCM/covariance. Never
re-anchor old prose automatically. PPK/PKPD/TMDD base/final parameter tables share the five-column
format; unavailable uncertainty stays blank. Parenthesized bounds are 95% confidence intervals,
identified in the column heading and footnote. ETA labels come from the fitted control stream.
Parameter blocks follow the reference layout: Fixed Effects/Covariate Effects retain
estimates and supported 95% CI; Interindividual Variability shows variance (%CV), RSE (%)
and shrinkage. CV is 100*sqrt(exp(variance)-1) only for log-normal effects; other variances
have no CV. RSE belongs to the variance, never the attached structural coefficient.
Corr rows are normalized omega correlations, with unavailable correlation uncertainty blank.
Residual Variability uses Proportional term/Additive term, with declared units or log scale
where supported. The proportional term remains a relative SD (0.1 = 10%); its confidence
limits stay on that scale. Bold merged block headings and local column headings distinguish
CV parentheses from 95% confidence intervals; the footnote explains both. The reference's
example unit is not a default unit for another dataset.
When S1C reports covariance state unestimable (only with the explicit PMX_COV_UNESTIMABLE_CONTINUE=true
opt-in), the parameter tables keep the point estimates with blank SE/%RSE/CI and the Word Methods carry a
mandatory disclosure sentence; that run is never presented as having estimated uncertainty.

PPK Word includes the base/final parameter tables with supported 95% CI and %RSE, and
all SCM comparison outcomes (failed fits have no estimates). Base covariance is a bounded
S1C post-fit calculation, never a second base optimization. All fits use FOCEI with matching control options and ODE
tolerances; screening and SCM use native stats::BIC(fit), including its native parameter count.
The legacy manually computed screening BIC is not interchangeable with native likelihood BIC.
Word impact sections omit Dose level and its figures; subsequent baseline-covariate
subsections are renumbered consecutively in the outline, captions and narrative targets.
Word exposure figures are routed by caption into the matching 5.6.x subsection and extracted
from the current HTML. Appendix D.1 reproduces the published root final_model.ctl records without toolkit-only header comments;
fitted parameter quantities still come from frozen S2 results for tables and simulations.
D.2 includes the native print(frozen final fit) summary in preformatted text: method,
objective/likelihood criteria, parameter uncertainty, correlations and available backend
messages/warnings. It is captured inside Word assembly, without a new queue job or fitting.
This is a final-fit summary, not an invented NONMEM .lst or a full optimizer iteration log.

Completed covariance settings are inherited by run_analysis.sh from the verified S1C
manifest before queue submission (analyses_template/tools/covariance_handoff.mjs). Omitting a method on
report continuation must not reset successful r covariance to default s. Changed
explicit covariance policy on a full/report continuation stops before submission;
--covariance-only is for a deliberate replacement or incomplete uncertainty.
Preserve corrected-matrix/gradient warnings for scientific review: a completed
covariance gate does not by itself prove reliable confidence intervals or model adequacy.

Screen completion: consume the terminal digest and exact LADDER_NEXT command, review
selection once, then submit the chain. Do not reread completed job output or dump the
same control stream repeatedly. A background job is not a reason for rapid job_output
polls. ACP degeneration is a model/transport stop, not a reason to refit or clear guards;
preserve the selected fit and report the handoff blocker. Dynamic ETA indices such as
ETA(4+OCC) are unsupported by the current nonmem2rx backend and fail preflight once.
ER Parameter estimates use Parameter (not Term), with the same cov_lab/comparison
label rules as univariable screening: bold variable header, blank statistical cells,
indented category contrasts without N counts. Actual fitted references govern direction.

PPK Word places the complete SCM run record in Appendix C. Its display omits failure-reason
text and uses Decision fail for failed fits; detailed reasons remain in frozen audit records.
Shared patient-characteristic tables follow ER layout: wide left-aligned variable labels,
bold parent rows, indented category levels and a single median/range versus n (%) footnote.
Measure labels and values, use the available page width, and let Word wrap naturally rather
than inserting character-count line breaks. Covariate correlation figures stay HTML-only.
Covariate-impact metric panels use two columns and additional rows, with matching image
height and single-line x-axis labels; use a full-width panel for crowded labels, preserving every group.
Impact-group cutoffs come from the shared report helper. Matching declared units use
BW/WTBL 60/80 kg, BMI 25/30 kg/m2, age 65 years and CRCL 30/60/90 mL/min. Integer
threshold labels describe actual bin membership; raw values are never rounded for assignment.
An optional data_spec.csv group_cutpoints cell (e.g. 60;80 for BW) takes precedence
without invalidating fit stages. Other/undeclared
units use rounded integer quantile cutpoints for BW/BMI/age, not an assumed unit conversion.
Other labs retain meaningful decimal precision. These display bins do not change SCM or fits.
Dataset sex percentages use one record per subject and explicit source-data sex codes.
Log VPC limits are automatic unless VPC_LOG_YMIN is set; ribbon portions below the positive
display limit are clipped only for rendering and labeled on the plot. Simulations and the
linear panel stay unchanged. Native nlmixr2 %RSE is already a percentage; do not multiply or
divide it by 100 again. Missing IIV uncertainty stays blank, without borrowing structural SEs.

All report families: body prose describes supported findings/trends, not numeric inventories from
figures/tables. Repeat a value only to explain its magnitude, uncertainty, threshold or another
substantive point. End finding sentences with the relevant figure/table reference and mention
every included figure/table at least once. Use report_narrative.mjs reference tokens (for example
{{figure:html_fig_01.png}}); final Word numbering is resolved after asset filtering. Do not cite
HTML-only figures as numbered Word figures. Patient characteristics are stratified by available
study identifiers, followed by Total; claim balance across studies only with supporting distributions.
Do not include "These are unadjusted quartile summaries with exact binomial intervals."
ER Univariable covariate screening is displayed by increasing Delta BIC, with missing values last.
Each categorical parent and its indented levels move together; formatting follows the moved rows.
Patient-characteristic summaries retain continuous-before-categorical ordering. Sorting is a display
change only and does not alter covariate retention, fitted models or parameter estimates.
Word body references (Table/Figure plus final number), including resolved narrative tokens and
automatic locator text, are internal hyperlinks to the corresponding caption bookmark. The shared
assembler preserves surrounding/run typography, handles references split across text runs, and
leaves captions, table cells, existing hyperlinks and Word fields unchanged. Targets use the actual
Word-included assets; no external relationship or HTML figure number is used for navigation.

PPK/PKPD/TMDD narrative is required by default: current Results interpretation, Discussion and
Conclusion, with meaningful findings/limitations and figure/table references. Core result sections
and subsections with included assets are listed in narrative_policy.required_result_targets.
First-pass structured Word/context/evidence are review artifacts. NARRATIVE_REQUIRED means S5 is not
complete; author prose locally, validate check_narrative.mjs --require-discussion-conclusion and resume
--from=s5 (Word) or --from=s4 (HTML/assets/Word), preserving all fitted/covariance caches. No repeat fit.
Only when the user explicitly declines narrative, record in the study's report_metadata.dcf:
Narrative: omit
NarrativeReason: <the user's actual request to omit it>
The agent must not create this opt-out on its own, including when evidence is insufficient. Report
unsupported interpretation as a limitation and keep completion pending; do not invent findings.

S2 declares new scalar DES intermediates in the generated ODE once, leaves existing variables as
assignments and never declares dxdt_* derivative macros. This applies to final_model.cpp and the EBE
simulator. Generated files retain their generated header; agents must not mark generated files as
user-authored merely to bypass regeneration. An actual user-authorized paired simulator remains supported.

All report families (PPK, PKPD, TMDD, ER and c-QTc), every body section including
Synopsis/Executive Summary, Results, Discussion and Conclusion: describe the supported finding,
trend, contrast, uncertainty or limitation, then cite its figure/table. Do not transcribe counts,
percentages, estimates, CI/SE/RSE, p-values, BIC or axis values merely because they are available.
Keep a data value only when that sentence explains its magnitude, uncertainty, threshold or
decision relevance; a locator sentence or "as shown" does not justify repeating it. Do not
repeat the same numerical finding across sections. Figure/Table reference numbers, endpoint
names (e.g. Grade 3), model definitions, units and configured Methods thresholds remain valid.
Before binding narrative, review every sentence containing a data value against this rule;
remove redundant values without changing the scientific meaning. No automatic digit stripping.

Fit-family final parameter tables reconcile the complete frozen fixef inventory with parFixedDf
and retained SCM effects. Covariate coefficients are shown under Covariate Effects, with their
target parameter, actual contrast/form and supported CI/%RSE. A retained fixed exponent is
disclosed as not estimated with blank uncertainty. Never substitute control-stream initials.
Word regenerates parameter-table contents from the frozen fit even when extracted HTML tables
already exist; the same helper supplies HTML on its next report-only render. Missing retained
coefficients stop reporting with REPORT_COVARIATE_ESTIMATE_MISSING, without replaying fits.

SCM CSV parsing: blank/missing exponent means NULL (estimate the power coefficient), never a fixed
NA exponent. Explicit references/exponents/category levels must be finite; power covariates and
references must be positive. Preserve approved fixed allometry and unbounded estimated starts.
SCM_ASSESSMENT_PARTIAL means some candidates were not evaluated; never describe those as
nonsignificant. Raw errors/calls/stacks remain in failure caches. STAGES_CHECKPOINT/CHAIN_CHECKPOINT
is a completed job handing off to the named next stage, not a fit failure: continue the wrapper once
with valid gates/caches; never attach to the finished id, reset caches or replay completed fits.

DEFER handoff: exit 3 is resumable only with the explicit normal-budget marker, never by exit code
alone. The client and queue guard share queue_outcome.mjs; failure backoff is waived only when the
matching chain ledger proves a new completed fit/stage. Real errors/timeouts and unchanged work
retain their guards. Keep one active background --attach --follow --summary observer per queue id. No shell sleep or blocking
job_output; one <=40s foreground fallback is diagnostic only. See references/continuation.md.
SCM fit scheduling keeps the 240s cold-start allowance when no same-key timing is known, then
uses the observed maximum fit cost with 25% margin and a 60s minimum. Explicit PMX_MIN_FIT_S
still supplies the floor. Persisted timing is bound to data/model/estimation identity; it is not
fit progress, does not authorize retries and never raises the worker/stage cap. Background chain
collection uses --summary; raw logs retain full output. Repeated DEFER windows with new completed
fits are active SCM, not a hung agent. Coefficients near zeroTheta need numerical/scientific review,
not automatic claims of no covariate effect or changed initials/bounds.
Foreground expiry closes that window only: keep/create the single observer, yield WAITING and
automatically continue on completion. Missing background capability is a named blocker. Existing tasks keep their preset;
switching a started task is not supported. No temperature change or service restart is implied.

## Engine maintenance

The shared engine is report_generator.R; family/<family>.R defines identity, section tree
and asset selection. Fit families additionally use family/<family>_model.R/run_pipeline.R;
ER/c-QTc use extracted HTML/regression results and have no NONMEM Appendix D/fit-family SCM.
Use explicit --family/--data when ambiguous; never fabricate data or source arbitrary family
scripts. Family detection excludes _dummy_gen names and requires a top-level FAMILY assignment.
Use exact list indexing ([[ ]]) for block/cover fields to avoid R partial matching. Labels
come from output/labels.csv; cover_dataset_fn receives the resolved data filename. Do not
hardcode unknown filenames/identity. A new family copies the closest spec and extends the
engine dictionary with param_labels where needed; it does not copy the engine.

The engine places assets; it never regenerates figures. extract_figures.R is the single
figure path; extract_tables.R requires actual HTML table/thead/th markup, not images or
script-built page content. Use manifest captions/filenames and final automatic numbering,
not positional table assumptions or fixed narrative-slot numbers. Repeat asset references
become pointers, not duplicate objects. Captions are bold above assets with keepNext;
footnotes go below. Follow current family page-break and parameter-table specifications.
Strip t. from imported parameter symbols for dictionary lookup and TV for displayed symbols.
Keep reference.docx and apply_reference.py for A4/styles/headers/footers and updateable contents/
figure/table fields. XML work stays in Python with assertions; ZIP packaging preserves _rels.
Never hand-edit fitted estimates/uncertainty to improve appearance, print internal errors,
add agency branding/source annotations or include individual-patient exposure listings.
Keep study outputs and caches in the user-authorized study directory. Author prose from current
evidence; render before claiming final visual quality. Runtime-fault handling is documented
in references/troubleshooting.md.

Model structure figures use the shared SVG skeletons and word-report/model_diagram.R;
see references/rules_deliverables.md, Structure diagram rules. HTML embeds the resulting
PNG; Word extracts that same image. Preserve study configuration when refreshing the
family Rmd and resume at S4 for diagram changes; do not refit or change VPC simulations.

## Deterministic simulator validation

PPK/PKPD/TMDD validate before the unchanged VPC simulation count/seed. The shared helper
performs one strict fixed-parameter native reference only if stored predictions disagree;
references/report_rules.md owns the verdict, audited overrides and numerical-drift disclosure.
Read table/_simulator_validation.json for an actionable failure, not a full render/temporary
Rmd diagnostic loop. Report solver settings update the loaded model, not CPP or fitted controls.
S2 simulator provenance/refresh policy is in references/fit_workflow.md. Header wording is not
an ownership flag. covariates.csv uses resolved CL/central-volume THETA symbols (e.g. TVCL/TVVC);
continuous references must be reviewed in the study's units, not guessed from MODEL$refs defaults.
