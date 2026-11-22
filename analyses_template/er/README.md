# Exposure-response configuration

Check state once with analyses_template/tools/run_er.sh <study> --state. For a new run, read the study
dictionary and run analyses_template/tools/data_peek.sh <data> --covariates once. Write pmx_config.R
from that evidence and submit analyses_template/tools/run_er.sh <study> --data=<file> --async. Follow
the returned job ID. Use this configuration guide for routine reports.

Run analyses_template/tools/run_er.sh <study> --data=actual.csv. The input stays unchanged. Use study pmx_config.R or --config=path to override the configuration blocks; use --template=path for a study Rmd. A matching study er_analysis.Rmd is preferred automatically. To refresh ONLY the .docx after a prose-only edit (`report_narrative.json` / `report_metadata.dcf`), run `analyses_template/tools/run_er.sh <study> --word-only --async`: it reuses the published HTML, renders no Rmd and refits nothing, and stages those optional inputs itself. Never hand-build a Word job.

Before submission, follow references/report_rules.md, Covariate intake (every report family).
Inspect actual study fields and record COVARIATE_REVIEW in pmx_config.R; explicitly set
CON_COV/CAT_COV from that review. For a raw field used solely to derive a modeled covariate,
record the raw field as excluded and give the derived field the role used in the model.
Configuration: CON_COV/CAT_COV declare types; COV_LABEL/COV_UNIT/COV_LEVELS define displays; COV_REF is modal or a named per-variable reference vector; COV_DERIVE defines study-appropriate derived variables; DOSE_VAR/REG_LABEL define descriptive grouping. Check endpoint event/censor codes and exposure scale before fitting. Explicit study units/cutoffs take precedence over examples. Declare the albumin unit in COV_UNIT. Baseline albumin is summarized below 35 g/L (3.5 g/dL) when the declared unit is supported. Set ALBUMIN_LLN in the declared units to use the study limit. Continuous albumin remains continuous if selected for modeling.

Declared but unavailable covariates are recorded as unevaluated, never a no-effect finding. Fits use complete cases for their actual variables, with the categorical reference selected on the fitted sample. Efficacy candidates are compared with exposure-only models on matching rows. SAE uses forward addition and backward elimination by BIC, with exposure retained throughout. Each nested comparison uses matching rows and records the sample size. N labels use the fitted sample; final models carry unique retained covariates. Failed/unestimable endpoint fits are recorded in diagnostics.

Dose grouping is descriptive by default. A separate dose term is a study design/modeling choice; concentration does not mathematically guarantee collinearity with dose. Revise the analysis plan explicitly if a dose term is scientifically justified.

The Rmd publishes output/report_results.rds for Word. HTML demographics and Word table captions originate from the current configuration/results. Word prose never precommits to an exposure direction or dosing decision. A full report requires agent-authored Discussion and Conclusion after the first analysis pass: read `node analyses_template/tools/report_narrative.mjs <study> --brief` locally, write both sections from current evidence, validate, then refresh Word once. See word-report/README.md; do not queue a result-reading job or refit for prose.

ER/c-QTc output layout: used Rmd/configuration and final reports stay in root. Structured results and endpoint/label indexes go in output/. Named analysis CSVs are optional (ER SAVE_OUTPUTS=TRUE) and go in table/analysis/. Word assets stay in table/ and figure/. Readers accept legacy flat paths; do not rerun a study just to relocate files.

ER presentation: full-model tables replace redundant generated final-model estimate tables in Word. TTE median summaries combine median and 95% confidence limits in one column (NR = median not reached; NE = confidence limit not estimable). Endpoint univariable tables omit OR/HR columns and use the report font family at one point below Normal. Base/full coefficient tables omit Effect (95% CI); effect ratios remain in forest plots and the current result context.


## ER methods, result sections and shared Word typography

The base model remains exposure only. The full-model covariate list is data-selected, never a prespecified base-model list, and is no longer printed as an endpoint formula under Methods. The photographed logistic/Cox method paragraphs, formulas and definitions are retained with a generic exposure symbol; the condition of fitting only after a positive graphical association is omitted because this template does not implement it. Covariate-analysis and software prose follow the photographed wording, without fixed table numbers, R version, drug, dose or trial-cohort text.

Base/full coefficient tables omit Effect (95% CI); ratios and uncertainty remain available in the result context and covariate-effect forest plots. Median time and its 95% limits share one column: Median <endpoint> (months, 95% CI), value median (lower–upper), preserving NR/NE. Forest labels and percentiles use the fitted complete-case sample. Exposure-only/all-continuous Cox models produce forests without requiring a categorical label column; raw-exposure mappings are supported too. Only fitted terms are used for forest contrasts; plots are printed explicitly. Non-estimable plots are described without internal errors, with the cause recorded in structured output.

Shared Word tables use the reference Normal font family/size (currently Times New Roman, 11 pt), centre headers and content, and reduce size only for dense tables. Density means at least eight columns, six columns with very long cells, or more than 35 rows with at least five columns. ER univariable screening defaults to one point below Normal; other tables retain these density rules. Reference headings, captions, headers/footers and figure proportions are retained.

ER graphical/regression Results use explicit bracketed interpretation placeholders until reviewed. The agent writes exposure-response trends, uncertainty and supported regression/covariate effects in section_results, using exact report_narrative.mjs er_interpretation_targets and paragraph arrays. Describe actual factor contrasts and directions; distinguish BIC retention from statistical significance. Do not replace interpretation with methods or figure-navigation boilerplate. Unsupported or inaccessible evidence leaves the placeholder visible and is reported to the user, without another analysis job. The --write mode binds them to current evidence, and Word-only refresh places them under those same headings. Unsupported population comparisons, flat-response conclusions and clinical/dose claims are never prefilled from the reference photographs. Hash/shape checks do not establish scientific correctness. Methods overrides remain available through sections.Methods and sections.CovariateAnalysis.

ER display refinement: omit Report control; abbreviations are an unnumbered front-matter table
on their own page. Synopsis and Introduction each start on a new page. Disposition is left-aligned.
Baseline N_total stays inline with its variable name. Screening groups each variable once, bolds
its name, leaves categorical heading coefficient fields blank, indents comparison rows one character,
retains every coefficient/comparison row, omits comparison counts, and uses magnitude-based
precision (up to two decimals, two significant digits below one, scientific notation below 0.0001). Group-level BIC/selection
appears once on the categorical variable heading (or the continuous variable row), not repeated on category rows. Display transformed exposure terms as Log(actual exposure column), never infer
transformation from the first letter alone. Median tables use the full text width, with a wider
median/CI column. No routine SE/RSE explanatory paragraph follows the coefficient tables.

Graphical analyses contains descriptive bar/KM plots. A binary endpoint's logistic fitted graph
belongs immediately after its base estimates, followed by screening and non-duplicate full estimates and a
Covariate effect plot of <endpoint> <regression> full model. When full and base have identical formulas, fitted rows and estimates with no retained covariates, omit the repeated full table and state at the model-section opening that no covariates met the configured selection criteria. Absent evaluable screening is described separately. The exposure-effect forest is retained. Response-rate/logistic/KM captions describe the endpoint and exposure; figures have explicit captions separate from numbered headings;
extraction keeps these captions and optional cell bold-prefix metadata in existing manifests.
Word retains legacy-manifest fallback. Captions contain Table/Figure numbering, not subsection
numbers.

ER safety Results are interpretation targets too. The frozen safety evidence contains endpoint-specific
exposure-group rates, denominators and exact binomial 95% intervals from the same evaluable records as
the bar plots. The agent reviews these and the logistic curves/bands, then replaces each bracketed
placeholder through section_results. Describe increasing, approximately flat, decreasing, nonmonotonic
or unclear patterns; lack of significance or broad intervals is not evidence of flatness. Discussion
synthesizes the named endpoint patterns and relevant uncertainty, instead of repeating counts or only
stating that the plotted curves were unadjusted. The SAE logistic regression section reports the exposure-only
base estimates, stepwise selection record, distinct final-model estimates, and an odds-ratio forest
plot when estimable. Interpret formal models in their corresponding regression sections. Set
SAFETY_MODEL_ENDPOINTS in pmx_config.R to choose the prespecified safety endpoints for formal modeling.
To use a different endpoint catalogue, set SAFETY_DEF to a list of entries with var (the binary
endpoint column), lab (its display label), and optional time (the event-time column).
Safety logistic captions omit "Exploratory" and include the existing dose-exposure panel when dose is
available. Original-data records with unavailable/invalid endpoint or plotted exposure are excluded
from the plot-specific summaries, with the count recorded. Legacy evidence remains usable for visual
interpretation; Word-only cannot add a new panel to an old extracted figure.
