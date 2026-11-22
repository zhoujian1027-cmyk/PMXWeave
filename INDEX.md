# PMX routing index

Choose the requested deliverable. Read the listed sections once and only the selected family
or dialect. AGENTS.md controls read/write scope. A link is a lookup target, not a reading list. Resolve toolkit references from the toolkit root; use study paths supplied by the user.

Distribution examples use example/cqtc, example/er, example/ppk, example/pkpd and example/tmdd.
They may be moved outside the toolkit. Always use the user-named study path; never replace it
with toolkit/example or infer it from the queue location.
Read the family guide named in this index; do not assume each study contains a README.md.

## End-to-end entry points

Start with the named study. For ER/c-QTc run the family wrapper with --state first.
For a new analysis, read its dictionary and run data_peek.sh <data> --covariates once
before writing the study configuration. Apply Covariate intake in references/report_rules.md.
After publication use report_narrative.mjs <study> --brief for the current evidence paths.

| Request | Read | Action |
|---|---|---|
| NONMEM CTL only | references/model_authoring.md; references/nonmem_rules.md; 1-2 nonmem_template/*.ctl examples | Compose once; fenced CTL only. No files/shell/report route unless explicitly requested. |
| mrgsolve CPP only | references/model_authoring.md; references/mrgsolve_rules.md; 1-2 mrgsolve_template/*.cpp examples | Same composition/delivery; requested dialect only. |
| Explicit conversion or paired models | Shared authoring contract, requested dialect rules and actual source/destination templates | Preserve model, units, scale and mappings. |
| PPK / PKPD / TMDD analysis/report | references/fit_workflow.md first; needed input/endpoint/simulator sections of references/model_contract.md; shared model-authoring route only if code is needed; family Rmd/report rules at rendering, not before code | `sh analyses_template/tools/run_analysis.sh --follow-chain <study> --family=<family> --data=<actual file>` in background after base selection; supplied base/direct SCM uses `--skip-nca`, no screen. For a model-structure figure, also follow the Model diagram route below. |
| ER report | analyses_template/er/README.md (configuration); report_rules.md Covariate intake | `sh analyses_template/tools/run_er.sh <study> --state`; follow its single next action. |
| c-QTc report | analyses_template/cqtc/README.md (generic drug configuration); report_rules.md Covariate intake | `sh analyses_template/tools/run_cqtc.sh <study> --state`; follow its single next action. |
| ER HTML only | analyses_template/er/README.md (configuration) | Configure requested blocks; run_er.sh <study> --no-word --async. No Word/narrative requirement for HTML-only work. |
| Word layout/content change | word-report/README.md; word-report/family/<family>.R; shared + selected-family report rules | Refresh reports from existing evidence; no fit. |
| New-model candidate screen | references/screening_rules.md; selected model rules/template | One bounded ladder job; all configured slots, no first-success cancellation. |
| Queue waiting/continuation | references/continuation.md | One fit-chain controller through verified checkpoints; otherwise one observer per returned job id. |
| CPU allocation | references/cpu_budget.md | Auto budget: available physical cores minus two (minimum one); maximum six model workers, seven threads/fit; memory-aware. |
| Study folder layout | references/study_layout.md | Authorized outputs only; never move live payloads. |
| Model diagram (standalone or within a report) | [Diagram quick start](analyses_template/diagrams/README.md) and the actual CTL/CPP; [structure rules](references/rules_deliverables.md#structure-diagram-rules-svg) for mechanism/extension decisions | Single SVG: call analyses_template/tools/draw_model_structure.mjs once; no study mirror or analysis chain. The renderer consumes one matching SVG; do not grep SVG internals or author temporary drawing scripts. Reports reuse its PNG through HTML extraction. No diagram work for code-only requests. |
| PsN preparation | nonmem_template/psn/README.md; only requested nonmem_template/psn/templates assets/checklist | Conversion deliverables only; no fitting or PsN execution. |
| Named failure/warning or authorized source audit | references/troubleshooting.md, matching section | One cause-directed check; preserve state/caches. Source repair needs authorization. |

Local R setup and optional Docker deployment are documented in analyses_template/tools/runtime_paths.md. Use analyses_template/tools/runtime_check.mjs <study> for a connection check; internal references are toolkit-relative.
Queue commands run on the configured Linux/shared R host, not native Windows PowerShell.
Use analyses_template/tools/rpath.sh to translate known task paths when necessary. Do not inspect other trees
to discover an execution environment.

## Model templates

List filenames only in the requested dialect directory and read the closest complete template.
Route and structure follow the request/data, not a report-family default.

| Structure | NONMEM filename tokens | mrgsolve filename tokens |
|---|---|---|
| Linear PK | PK_*_1cpt/2cpt/3cpt_IV/PO_* | pk_1cmt_iv, pk_1cmt_po, pk_2cmt_po |
| Transit / parallel absorption | ADVAN5_* / ADVAN13_*parallel_abs* | pk_transit / pk_parallel |
| Nonlinear / time-varying clearance | ADVAN13_*mm* / PK_*TVCL* | pk_mm / pk_tvcl |
| Direct / effect compartment / turnover | DIRECT_* / EFFCMT_* / IRM_* | pd_direct / pd_effcmt / pd_irm |
| Parent-metabolite | PM_LINEAR_* / PM_EMAX_* | pm_emax |
| TMDD | TMDDFULL_* / TMDDQSS_* / TMDDQE_* / TMDDIRR_* | tmdd_full / tmdd_qss / tmdd_qe / tmdd_irr |
| TGI | TGIGOMP_* / TGISIM_* / TGICLARET_* | tgi_gompertz / tgi_simeoni / tgi_claret |
| Correlated IIV | *_BLK* | block_omega |

Tokens: add/prop/comb/logAdd = residual form; BW/SEX/AGE = covariates; BLK = correlated IIV;
TLAG = lag; F1IIV = fraction with logit-scale IIV; IOV = occasion variability.
SAEM/BAYES need a compatible NONMEM/PsN backend; the bundled nlmixr2 pipeline uses FOCEI.

## Reports

Fit-family HTML source is analyses_template/<family>/<family>_report.Rmd; for PKPD,
[pkpd_report.Rmd](analyses_template/pkpd/pkpd_report.Rmd). Use this actual path; do not construct
Rmd paths from a generator or contract name. word-report/ holds Word generators and simulator
contracts, not the family report Rmds. Read a contract only for the stage that needs it.
ER: analyses_template/er/er_analysis.Rmd; c-QTc: analyses_template/cqtc/cqtc_report.Rmd. Word: matching
word-report/family/<family>.R and reference.docx. Narrative skeletons in
word-report/report_template/ are reference assets; editing them alone does not change
generated Word text. Completion, narrative and resume rules belong to the routed contracts.

## Source organization and maintenance

AGENTS.md owns access scope, INDEX.md owns routing, and SYSTEM_PROMPT.md holds the agent instructions.
references/ holds the shared rules. Family usage guides live beside their analysis templates.
analyses_template/ holds analysis templates; analyses_template/tools/ holds workflow utilities.
nonmem_template/psn/ holds the PsN preparation templates and checklist.
word-report/ holds the Word generators and shared report assets.

Use task-sized rule modules, not one workspace-wide rulebook or one file per individual
rule. Model authoring, each dialect, fit workflow/input contract/screening, reporting,
CPU/continuation, study layout, diagrams and troubleshooting have distinct owners in
references/. Read only the routed owner and required shared sections for the current task.
references/study_layout.md owns output locations; references/model_authoring.md owns shared
model-code constraints; dialect files own their syntax; references/report_rules.md owns
report prose/completion. Family usage guides route to those owners instead of restating their rules.

Update a rule in its existing owner. Update references when moving that owner; do not retain
duplicate copies, compatibility-only documents or change-history notes. Merge sections that
are always consumed together; split only when independent tasks can avoid loading the result.
