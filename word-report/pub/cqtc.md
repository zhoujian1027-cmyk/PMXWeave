# CQTC report entry

Use INDEX.md to select the analysis wrapper. Fit families follow NCA → authored candidates → agent-recorded base selection → SCM → freeze → HTML → extraction → Word. ER/c-QTc use their direct regression wrapper.

Study covariate configuration belongs in pmx_config.R (regression) or covariates.csv (SCM), not in a global template. Word uses current structured results and manifests. See ../README.md for optional evidence-backed prose; a prose-only edit requires Word assembly only.

## c-QTc presentation and reusable methods

Word 4.2 is ordered as 4.2.1 Data Exploration, 4.2.2 Base Model, 4.2.3 Full Model (including the covariate screen), 4.2.4 Diagnostics, and 4.2.5 Simulations. Manifest headings route included displays to these subsections; calculation order in the Rmd is preserved. The tumour-type visit plot, all hysteresis plots and the concentration-QTcF relationship/goodness-of-fit statistics table remain in HTML only. Word filtering uses their captions/sections, not fixed figure/table numbers. These assets remain source-bound evidence for narrative review.

Base/full parameter estimates combine fixed effects, random-effect SDs/correlations, and residual SD in one table per model. BIC appears once per parameter table. Demographics and screening use ER typography: continuous variables first, categorical variable names bold with blank coefficient cells, indented category/comparison rows, left-aligned labels and centred statistics. Demographic median [min, max] and n (%) definitions appear once in a footnote; N_total is inline with the categorical variable name. Screening uses Covariate, Estimate, 95% CI, BIC, Delta BIC and Retained, without comparison counts or row names; variable-level BIC/retention appears on the categorical parent row, and its type is one point below Normal. An identical full/final fit does not generate another final-estimates table.

The base model includes concentration plus baseline QTcF when supplied and estimable. Baseline QTcF is prespecified, not BIC-selected, and is excluded from optional screening. Full models add only optional BIC-retained covariates. Every candidate/base comparison uses matching complete cases and actual random-effects structures, including a bounded comparator refit if fallback changed the structure. With no retained optional covariates, reuse the base comparison fit. This default follows the pre-specified modeling approach in [Garnett et al.](https://doi.org/10.1007/s10928-017-9558-5); it is a modeling recommendation, not a blanket regulatory requirement. Study configuration can override mandatory_cov explicitly.

Outlier prose is generated from unique threshold-flagged records and participants. Category counts can overlap; flags alone do not remove records in this template. Missing absolute QTcF means its threshold counts are not assessed, rather than zero.

Reusable prose covers the analysis objective, supplied paired records, units without conversion, the Fridericia/Delta-QTcF definitions, actual missing-data handling, maximum-likelihood fitting, matched-sample covariate comparisons, diagnostic purpose and prediction-interval interpretation. Counts, model structure, available data and software versions come from the current results/configuration. CONC_UNIT accepts the study's concentration unit. PAIRING_METHOD and BASELINE_DEFINITION accept the source matching and baseline rules; empty settings do not invent a protocol-specific baseline or pairing algorithm.

Do not prefill drug mechanisms, assay/ECG schedules, data reanalysis history, a Cycle-1-Day-1 baseline rule, absence of hysteresis, model adequacy or a QT threshold conclusion. The reference photographs illustrate layout, not reusable study findings. Slope/mean-response intervals and individual prediction intervals are distinct; the main prediction plot retains its current 95% mean-response band, while binned/slope summaries identify 90% intervals. Study narrative can override the method sections through the existing evidence gate.

Use drug for the report identity and drug concentration for the exposure label.
