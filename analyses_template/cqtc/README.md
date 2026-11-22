# Concentration-QTc analysis

Use the study's time-matched concentration/QTc table and study pmx_config.R.
Read references/report_rules.md for covariate intake, report interpretation and
completion; shared Word presentation is documented in word-report/README.md.

## Run

Read the study data dictionary and profile the actual data once before configuring
a new analysis. The input file and its numeric units remain unchanged.

```sh
sh <toolkit>/analyses_template/tools/run_cqtc.sh <study> --state
sh <toolkit>/analyses_template/tools/data_peek.sh <study>/<data>.csv --covariates
sh <toolkit>/analyses_template/tools/run_cqtc.sh <study> --data=<data>.csv --async
```

The wrapper stages the analysis and Word assets, submits the R job and returns
the exact job ID and next action. Follow references/continuation.md. Use --data
when several CSV files are present. Study overrides use pmx_config.R or --config;
an explicitly supplied study Rmd uses --template.

## Input

One row represents a time-matched concentration/QTc observation.

| Fields | Purpose |
|---|---|
| USUBJID, SUBJID or ID | Subject identifier |
| PKCONC | Concentration |
| ATPT | Nominal time point |
| QTCFAG and BQTCF, or CFBQTCF | Paired QTcF/baseline values, or supplied change |
| PCTEST or ANALYTE | Analyte selection when several analytes are present |
| ATPTN, AVISIT, ADY, TRTA | Time ordering, cycle and dose-group displays |
| QTCFAG or QTCF, CFBHR, PKBLQ, TSFD | Absolute QTcF, heart-rate, BLQ and hysteresis sections |
| Eligible baseline covariates | Prespecified adjustments and reviewed screening candidates |

Missing optional fields omit the corresponding section and are logged.
CQTC_SCHEMA_NO_CORE identifies missing core fields; CQTC_SCHEMA_MULTI requires
selection of the actual data file.

## Study settings

- Record COVARIATE_REVIEW and configure cov_want/cov_categorical from the actual
  eligible baseline fields, labels, reference levels and category coding.
- BQTCF is a prespecified base-model adjustment when available and estimable.
  Optional covariates are screened using matched-record BIC comparisons.
- QT_CHANGE_SOURCE can be "derived" or "supplied". By default, usable paired
  QTCFAG/BQTCF values supply the change; supplied CFBQTCF is the fallback.
- ANALYTE_NAME selects the measured analyte when needed. Default wording is drug.
- CONC_UNIT must describe the actual PKCONC unit; the default is unspecified.
  CONC_LAB changes only the label. No automatic unit conversion is performed.
- ATPTN determines time-point order when supplied; ATPT_ORDER configures an
  unusual nominal ordering.

## Analysis and reports

The base uses concentration and the available baseline QTcF adjustment, with a
random slope, random intercept or fixed-effects structure selected from the data
and reused across comparisons. The final model adds retained optional covariates.
Reports include population summaries, exploratory figures, parameter estimates,
covariate screening, diagnostics and concentration-response predictions.

CQTC_report.html and CQTC_report.docx are published in the study root. Structured
results and evidence are under output/; figures and tables use figure/ and table/.
Follow references/study_layout.md for the complete study layout.

For a full report, use the current evidence to author Discussion and Conclusion
under references/report_rules.md. Refresh Word from existing results with
analyses_template/tools/run_cqtc.sh <study> --word-only --async. This does not
refresh HTML. A completed report requires no resubmission.
