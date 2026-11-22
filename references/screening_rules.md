# Candidate screening

Only for an authorized new-model screen. Supplied-base/direct-SCM work skips this route.
Code-only requests do not start NCA, screening or a report.

## Width, structure and starts

Author the requested candidate set once, normally six, never above the user's width or
--cand-max (PMX_CAND_MAX). Explicit --models lists and a larger cap do not override the requested width.
Number models in scientific priority order; excess filename-sorted entries may be excluded.
LADDER_WARN_LADDER_TOO_WIDE / LADDER_WARN_MODELS_OVER_CAP require correcting the authored
set before submission. Do not increase width to evade a budget.

Every candidate retains the requested structure. A simpler scientific reference is a separately
authorized, labelled check, not a replacement slot. Parallel absorption requires two depots,
an estimated fraction and estimated relative delay (TVALAG2=THETA(k), ALAG2=TVALAG2);
never silently remove TLAG or fix F1. Match every original INPUT column, including DROP.
Use the selected dialect template/rules, compatible ADVAN/MODEL width and initial-value rules.

## One bounded round

Submit one complete-toolkit fit_ladder.sh job. All configured slots run once with bounded
concurrency until all are terminal or the screening deadline expires. Do not cancel or withhold
remaining candidates on the first success, or hold the tail back by estimated duration.
Rank completed fits with the shared passed/warning/failed verdict in references/fit_workflow.md.
Normal-exit objective-history/ETA diagnostics are retained warnings, not automatic exclusions;
invalid quantities/status exclude new and cached fits. Never refit a rejected cache merely to
make it eligible. One eligible success is sufficient to continue, but neither
one success nor a completed screen proves adequacy or provides a multi-model comparison.
Record failed, timed-out, cancelled and unstarted slots without estimates; an unstarted/timeout
slot is not a statistical failure. Do not exceed the queue cap or reset a live screen.

A failed fit stays failed: record its reason, never change its structure/parameters and resubmit
to rescue a slot. The user-confirmed exception is one correction of a malformed control stream
rejected by validation/translation before reaching estimation: correct only that defect in place,
structure unchanged, and submit that slot once. If correction would change the model, record failure.
This exception is not permission to clear a guard, ledger or cache.
After a completed round, a new candidate set/--new-round requires an explicit user request.

Select from successful candidates using fit quality, uncertainty and scientific plausibility;
write Candidate and Reason in base_selection.dcf without asking again for routine selection.
Never promote failed/unstarted models or compare rewritten models as if they were originals.
Stop a failed base/final or unsupported contract at that stage; a successful screen cannot
override a later blocker.

## History, export and reuse

Keep cumulative 01_screen/ladder_table.csv with round/data/model fingerprints and every terminal
outcome; rank only the current round. Never replace history with the winner's row.
Publish base THETA/OMEGA/SIGMA initials at four significant digits, preserving bounds, structure,
INPUT and estimated lag/fraction. Keep original candidate controls/cache keys unchanged.
Do not create M07/base_promoted or refit the winner to update initials.

Use the terminal digest and exact LADDER_NEXT action; review selection once, then advance.
LADDER_STOP blocks unchanged replay; LADDER_PARTIAL returns the selected base.
LADDER_EXPORT_REQUIRED means fit_ladder.sh --export-only with verified caches, including
failed/unstarted history, never another estimation run. The R worker writes terminal JSON;
Node is client-side only. LADDER_TOOLKIT_LAYOUT requires the complete toolkit entry point.
Do not hand-build .toolkit trees, worker scripts or per-study line-ending-normalized copies;
shell entry points use LF. Stop if the proper toolkit remains unavailable.

SCM reuses the verified selected screen fit. FIT3 identity compares named FOCEI/ODE settings,
exact package versions, model/data/endpoint/helper contract, fixed approvals and selected RDS
hashes; threads, serialization attributes, generated job text and export/layout code do not
invalidate fits. Estimator/data/model changes still do. A mismatch names its field and stops.
LEGACY_SETTINGS_UNVERIFIABLE means preserve old FIT2 results and report the compatibility
blocker: never guess versions/cores, edit keys or loop diagnostic/refit jobs. Runtime/source-only
changes do not reopen a completed screen. Export-only preserves its producing round.

## Scheduling

Follow references/cpu_budget.md and references/continuation.md: the host physical-core-minus-two
budget, at most six memory-aware PSOCK workers and seven threads/fit.
These allocations limit logical threads. Parent-only durable cache/checkpoint
commits; collect completed receipts before more work. Worker loss is a blocker, not permission
for a serial refit. Existing timeout, DEFER, stage and no-progress guards remain in force.
