# HTML analysis templates

Read only the requested family. INDEX.md routes the full task; do not read all notebooks.

- PPK/PKPD/TMDD: analyses_template/tools/run_analysis.sh imports the actual CTL, searches covariates, computes
  required covariance and freezes results before <family>_report.Rmd reads them.
  Follow references/fit_workflow.md and references/model_contract.md.
  Older *_fit.Rmd notebooks are optional requested manual examples, not the default chain.
- ER: er/er_analysis.Rmd expects subject-level exposure and endpoint/censoring columns;
  use analyses_template/tools/run_er.sh.
- c-QTc: cqtc/cqtc_report.Rmd accepts repeated concentration/QTc records; use analyses_template/tools/run_cqtc.sh.
  Both wrappers honor the actual --data file and assemble Word from successful HTML/assets;
  follow references/report_rules.md.

Adapt model-specific chunks only in the authorized study copy, for actual units/regimen/model.
Reusable sources contain no study caches and require explicit source-edit authorization.

## Bounded screening and required parallel lag

The single screening contract is references/screening_rules.md. Run all configured slots
until terminal/deadline, not just the first success. One eligible completed fit permits
continuation; retain failed/timed-out/unstarted outcomes and required estimated lag/fraction.
Supplied-base/direct-SCM tasks skip screening.
