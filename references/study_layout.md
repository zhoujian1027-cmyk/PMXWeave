# Study output layout

This is the single location contract for study artifacts. Reusable PMX/CP source trees remain
read-only unless the user requests a source change. Original data keep their names/content;
do not select a dataset merely because it is the largest file.

Use the study/output directory authorized by the user, wherever it is located.
Keep outputs there and leave reusable sources read-only unless their modification was requested.

## Study root

Keep original data, base_model.ctl, final_model.ctl, final_model.cpp, final HTML/Word and
study configuration at root: data_spec.csv, covariates.csv, base_selection.dcf, pmx_config.R,
report_metadata.dcf and report_narrative.json when applicable. covariates.csv remains editable
by the study/share owner; do not move it into 01_screen/.
output/report_evidence.json binds narrative to source/assets; output/run_manifest.json records
completion and artifact hashes. Make generated files readable and directories traversable
for the share user.

## Fit families: PPK / PKPD / TMDD

| Directory | Contents |
|---|---|
| 01_screen/ | NCA status/initials CSV and visible/hidden initials text, settings keys/logs, candidate CTL/fits, recommendation, cumulative ladder_table.csv. |
| 02_html/ | Study Rmd, SCM/fitted caches, frozen archives and artifacts/s1,s2,s4. |
| 03_word/ | Extracted manifests/assets and artifacts/s3,s5. |

_scm_sel_cache contains study results and is never distributed with the toolkit. Preserve it
for resumption; remove after final delivery only when resumption is unnecessary and cleanup
is authorized. A supported flat layout may put stage/NCA/screen outputs at the study root;
read it without refitting merely to relocate artifacts.

## ER / c-QTc

Keep the used Rmd and study configuration (including analysis_config.R when applicable),
narrative and final reports at root.

| Directory | Contents |
|---|---|
| output/ | report_results.rds, report_context.json, evidence/completion JSON, labels and endpoint indexes. |
| table/ | HTML-extracted Word tables/manifests. Optional named analysis CSVs use table/analysis/ (ER SAVE_OUTPUTS=TRUE). |
| figure/ | Report images. |

Do not generate RUN_REGRESSION.flag. Existing flat-file studies remain readable without
refitting or moving results solely to match this layout.

## Queue sidecars

.pmx/ is queue transport, not the final deliverable directory. New agent-authored rq_*.R
queue/continuation scripts belong in .pmx/jobs/, not root or 01_screen/. Never move/delete a
queued or running payload, and never hand-submit a replacement chain to tidy files.
Verify published shared artifacts; queue stdout and toolkit build copies are transport only.

.pmx/run_<family>_XXXXXX/ is a job cwd/staging mirror. Its .pmx_run_state records
STAGE=staging|staged|hold|duplicate|queued|published and ID. ID=PENDING or no marker means no
job was queued; those mirrors cannot show worker progress and are wrapper-swept after
60 minutes. Use run_er.sh/run_cqtc.sh --state rather than directory listings. Preserve mirrors
while their real job may run; normal removal is more than 60 minutes after .run_complete,
with the wrapper's 24-hour last-resort rule. Do not manually clear staging to force retries.
