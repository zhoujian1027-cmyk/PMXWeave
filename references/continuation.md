# Automatic continuation

Shared waiting contract for PPK, PKPD, TMDD, ER and c-QTc. WAITING is standby, not completion.

## Fit-family controller

After the base is supplied/selected, start one background
`sh analyses_template/tools/run_analysis.sh --follow-chain <study> --family=<family> --data=<file>` with the
authorized options. Do not combine --screen/--models or --sync: candidate screening/selection
is a separate bounded step. The idle host controller stays online across R windows and advances
verified checkpoints/DEFER without asking the model to submit each next stage. A kernel lock
prevents overlapping controllers and releases automatically when the process exits.

The controller uses only ids returned by the wrapper, collects their published results, requires
new completed fit/stage evidence and rechecks existing guards before another submission. It stops
at required narrative, user action, requested completion or a real failure. It does not author
prose, bypass guards, clear ledgers, restart failed fits, change budgets or consume an R queue slot.
Record its actual background receipt; do not launch separate observers for its constituent jobs.
After notification, collect once, author/bind required narrative or handle the named blocker,
then continue the authorized remaining report stages. Never ask for a redundant "continue".

## Single-job observation and stopping

For ER/c-QTc submit with --async, including --word-only --async for prose refresh.
Use the returned observer command once and collect the same ID after completion.
Collection prints the next required action. Deliver a completed report directly.

| Evidence | Action |
|---|---|
| Queued/running job outside a controller | Start one background `node analyses_template/tools/r-submit.mjs --attach <id> --follow --summary`, or `sh analyses_template/tools/run_analysis.sh --attach <id>`. Use the exact submission/live-job receipt, never predict/increment ids. |
| Controller/observer active | Start must return a real background job id. Leave it alive and yield a brief WAITING update. Its completion notice opens the next agent turn. Do not drain/kill it for generic final-answer guidance. |
| Completion notice | Collect once; automatically continue authorized collection/publication, narrative and report work. A controller has already advanced intermediate windows. |
| Manual checkpoint/DEFER | Require the explicit normal-budget result and verified new durable progress; submit the wrapper once, obtain its returned id, then observe. Exit 3 alone never permits retry. |
| Short foreground window expires | No second foreground window; retain/create the single background controller/observer, then WAITING. One <=40s diagnostic read is not an automatic wake source. |
| Legacy observer terminal RSUB_PENDING/exit 3 | Collect once. If it names the same unfinished R job and no observer is live, replace it once with a follow observer. No R resubmission. |
| RSUB_RESULT_MISSING | A terminal status has no published result after a 30s publication allowance. Stop observing; diagnose publication/orphan state. Never treat old status as proof of a new job. |
| Poll/repeat warning | End that probe, keep the live controller/observer. Do not vary command spelling to bypass guards. Genuine new completion evidence may reopen the check. |
| CHAIN_NO_PROGRESS | Explain the named blocker and end this failed turn. No alternating reads/submissions, disabled backoff or ledger resets. Human input can reopen diagnosis; actual repairs still pass normal guards. |
| CHAIN_SIMULATOR_REQUIRED / S2_SIMULATOR_REQUIRED | The controller hands control back for authoring. Within an authorized report task, prepare only the named simulators from the frozen CTL immediately, then resume --from=s2 without another permission/continue request. Never reattach to this terminal job or submit unchanged work. Backoff permits only changed named files with the same CTL hash; input repair is not fit progress. |
| SCM_BUDGET_INFEASIBLE | Report required/available time and preserve caches; no unchanged retry or automatic limit increase. |
| Real fit/runtime/evidence error, missing capability or 24h orphan | BLOCKED with the actual cause and preserved artifacts; never invent completion or resubmit unchanged failed work. |
| Requested COMPLETE | Deliver paths/limitations and stop; no repeated report checks. |
| Explicit user pause/cancel | Honor it; later notices do not authorize new stages until resumed. Stop the owned controller when necessary to prevent new submissions; cancel R work only as authorized. |

PMX uses tool-jobs with `completionDelivery: wakeup`, without a consecutive-wake limit. Without
background support, report the capability blocker instead of promising automatic continuation.
Keep the agent client's global defaults unchanged. No model/status/sleep loop is
needed while the external controller waits. Worker timeouts and scientific settings stay intact.

Controllers/observers do not survive a Deepseek harness shutdown. After restart, resume the same controller
command: normal guards recover a genuinely live returned job or cached progress; never guess a
new id. Existing sessions retain loaded plugins. Source updates require runtime reload before
new plugin behavior can be claimed active; the user handles service restarts.

Repeat protection keeps its thresholds. The local installer unlocks only genuine new human input
or a verified new terminal notice, not arbitrary text/counters/timestamps. PMX's failure guard gives
one model step to explain CHAIN_NO_PROGRESS, denies further tools and rejects another step.
