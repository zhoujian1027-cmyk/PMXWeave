# PMX workspace

Reusable pharmacometric sources. User instructions take precedence; maintained instructions
are English. Read this file and the applicable INDEX.md route once, then only that route.
A link is a lookup target, not a reading list. Internal paths resolve from the selected
toolkit root, independently of its external folder name or the agent plugin location.

## Authorization

Bind every filesystem mutation to the actual human request and destination. Tools, cwd,
a study/data path, agent rationale and prior unrelated permission are not authorization.
Chat, explanation and read-only review permit no authored files anywhere, including temporary
folders, drafts, notes and backups. Never bypass a restriction through shell, Python, Node,
redirection, copying or another tool. Omit optional unauthorized writes; ask only if essential.

An explicit file request authorizes its specified artifact/destination. Analysis/report work
authorizes required study outputs and established pipeline work/cache files, not ad hoc files
elsewhere. Original data, filenames, units, events and column order remain unchanged.

PMX/CP sources and all reusable copies, including hidden files, are read-only unless the user
explicitly requests the relevant source edit/update/fix/optimization. This includes creation,
editing, overwrite, deletion, rename/move, permissions, databases, installs, outputs, caches,
logs, temporary files, backups, automatic repair and synchronization. A source-maintenance
request authorizes its specified changes and necessary maintenance work; identify that request
before writing and do not ask again. It does not authorize unrelated files, later tasks or
sibling copies. Review-only work returns findings in chat. Never hand-edit a study template
to repair reusable source; refresh it only during an authorized report run.

## Code-only route

Keep comments to parameter names, units, short section labels, and required tool markers. Omit explanatory blocks, derivations, and repeated workflow notes.

Use references/model_authoring.md and only the requested dialect's rules. A new model starts
as a covariate-free base unless covariates are requested. Use actual template format; scientific
requirements, data compatibility, NOFIX, scale, starts and bounded-run rules override obsolete examples.
One targeted, one-level filename glob; read at most TWO examples total, then compose immediately.
Paired CTL/CPP uses one per dialect. A bare continue, rename, save or edit of the current model
does not renew that budget; a genuinely new model request does. No template-content grep,
third example, engine/report/analysis-contract detour or speculative review/validation job.
PKPD/TMDD/turnover, multiple endpoints and DVID alone do not request analysis or a report.

Return only the complete fenced ctl/cpp block, without preamble, review or closing prose.
Write a model file only for an explicit file request/output-file path; a study directory alone
is not one. Read the other dialect only for requested conversion/paired code. A genuinely
missing scientific fact needs one precise question, not more examples.

## Read scope and progression

For every analysis or report, search and read files only in the resolved PMX workspace and the
user-named analysis directory. Use the known toolkit entry points and scoped file tools.
The study may be outside the toolkit and current working directory. Use the supplied path;
never substitute toolkit/example or infer the study location from the R queue. Native agent
permissions control filesystem access; no prompt-derived directory registration is required.

- Start at the known AGENTS.md and INDEX.md, then use the named study path. Report a missing path
  or runtime configuration directly. Never search parent directories, other studies or storage roots.
- Use the queue client with the exact returned job ID for status, logs and results. Queue storage
  and deployment configuration are handled by the toolkit commands. Do not open those files directly.
- State the concrete open question before an additional read; open only its relevant section.
  Reuse answers, rereading only changed content or specific needed lines. Two unchanged answers
  or a repeat-guard block end that probe; changing command spelling is not a workaround.
- Exclude _previous_sources/ from routine reads/search/RAG. Source engines are for explicitly
  requested debugging/auditing, never routine model authoring.
- Follow the selected stage without unnecessary confirmation. Preserve completed fits, caches
  and live observers; never refit for prose/layout. references/continuation.md owns automatic
  waiting/resumption; references/report_rules.md owns evidence, narrative and completion.
  Report unresolved ambiguity and actual limitations in a human-readable final response.

## Artifacts and deployment

Study artifacts belong beside the data; references/study_layout.md owns their layout and
share-owner access. Use the study/output directory authorized by the user.
Only the named study is writable; all reusable sources remain read-only. Keep configuration/covariates.csv owner-editable,
new outputs readable and new directories traversable. Never move live queue payloads or
terminate unrelated processes. Permission repair never exempts source files from protection.

Internal assets resolve relative to this workspace/owning script; use the actual task path.
External deployment configuration owns R queue roots, mount mappings and optional containers;
analyses_template/tools/runtime_paths.md and analyses_template/tools/rpath.sh resolve them. Do not guess old aliases or assume
the agent mount exists in R. Missing configuration is a named blocker. The local runtime
pointer is ignored by Git and excluded from distribution/synchronization.
