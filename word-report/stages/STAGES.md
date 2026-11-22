# Fit-family stages

Execution order: S1 fit/SCM → S1C covariance → S2 freeze → S4 HTML → S3 manifest extraction → S5 Word. Gates check current inputs, outputs, source code and fitting settings.

S1 consumes actual data/base ctl, optional covariates.csv/base_selection.dcf; it preserves `<family>_scm_search_result.rds`, selection tables and final ctl without covariance. S1C reads that content-bound checkpoint and computes final covariance with setCov/addTable, never rerunning optimization or SCM. Base covariance is enabled by default for PPK; `PMX_COV_BASE=true` requests it for other families; if base equals final it is computed once. The queue wrapper ends the S1 and S1C job windows at their completed checkpoints. Resume the same wrapper for the next stage, or use `--covariance-only` for S1C alone. `_scm_covariance_state.dcf` distinguishes estimates complete from uncertainty pending/failed/complete/unestimable; failed uncertainty blocks freeze/report completion, while an explicit PMX_COV_UNESTIMABLE_CONTINUE=true records UNESTIMABLE (estimates preserved, SE/%RSE blank, disclosed) and lets S2-S5 proceed. S2 freezes the exact final fits/control stream and publishes archives/simulators. S4 runs the study Rmd with error=FALSE. S3 extracts current figures/tables and their manifests. S5 uses frozen results, manifests and optional evidence-backed study narrative; it never refits.

A narrative/metadata-only update invalidates S5, not the analysis. If the optional narrative names evidence files, their hashes also participate in the S5 gate. A study-local report_section_leads.R is an S5 input in the same way. Unsupported/stale narrative is omitted with a diagnostic, not printed into Word. The HTML report must obtain its Discussion/Conclusion from the same gate (pmx_narrative_sections), otherwise the two deliverables can disagree about the same frozen results. The source update was static only; no stages were executed or rendered.

S2 translates ordinary power/comparison covariate expressions to C++ while retaining estimated ALAG/F, fitted OMEGA, and the original single-endpoint SIGMA/EPS/Y model. Missing/unsupported simulator contracts stop as S2_MODEL_CONTRACT_UNSUPPORTED before archives are republished. Resume with run_analysis.sh --from=s2 only when S1/S1C gates are current; never redo their fits to fix an export. Root final_model.ctl contains estimation starts; final fitted controls live in artifacts/s2/final_fitted.ctl and are the report/simulator authority.

PPK Word includes the base/final parameter tables with supported 95% CI and %RSE, and
all SCM comparison outcomes (failed fits have no estimates). Base covariance is a bounded
S1C post-fit calculation, never a second base optimization. All fits use FOCEI with matching control options and ODE
tolerances; screening and SCM use native stats::BIC(fit), including its native parameter count.
The legacy manually computed screening BIC is not interchangeable with native likelihood BIC.
Word exposure figures are routed by caption into the matching 5.6.x subsection and extracted
from the current HTML. Appendix D.1 copies the published root final_model.ctl verbatim;
fitted parameter quantities still come from frozen S2 results for tables and simulations.

Completed covariance settings are inherited by run_analysis.sh from the verified S1C
manifest before queue submission (analyses_template/tools/covariance_handoff.mjs). Omitting a method on
report continuation must not reset successful r covariance to default s. Changed
explicit covariance policy on a full/report continuation stops before submission;
--covariance-only is for a deliberate replacement or incomplete uncertainty.
Preserve corrected-matrix/gradient warnings for scientific review: a completed
covariance gate does not by itself prove reliable confidence intervals or model adequacy.
