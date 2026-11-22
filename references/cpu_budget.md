# Shared CPU budget

Applies to PPK, PKPD, TMDD, ER and c-QTc. Compute the total parallel budget on the
execution host as max(1, available physical cores - 2); never assume a CPU model, 32 logical
CPUs or a fixed 14/24-thread default. Linux counts physical-core groups within the current
process CPU affinity; Windows/macOS use physical-core detection. Unknown topology falls
back to one thread. Applicable cgroup CPU quotas can further reduce the result.

PMX_R_CORES is an optional lower cap; leave it unset for automatic allocation on another
computer. The result is a shared thread budget, not CPU affinity/pinning or an exclusive
reservation of physical cores. Single fits use at most seven threads; PMX_FIT_THREADS can
lower that limit. PMX_MC_CORES/screen --cores and PMX_MAX_MODEL_WORKERS cap concurrent model
workers at six, also bounded by pending tasks, the computed budget and available memory.
Workers divide the budget; never give each worker the full allowance. BLAS/MKL/BLIS remain
single-threaded. Do not fill unused threads with unrequested fits or overlap study jobs.

PSOCK pools respect pending tasks and available/cgroup memory. The default allowance is
2048 MiB per worker plus two data copies, with 4096 MiB left outside that allowance for
the parent R process and host services. These are conservative planning estimates, not measured peaks;
large models may need a larger allowance or fewer workers. Insufficient memory blocks
dispatch. Six processes avoid the memory/compilation pressure of 12-24 R processes.

Independent SCM additions/removals run in parallel within each round; dependent rounds
and winner selection retain their original order, criterion, effects and initial values.
Workers use isolated model-build directories and atomic content-keyed receipts. Only the
parent commits caches and checkpoints. Recover completed receipts first. Worker loss or
missing dependencies are toolchain blockers, never an automatic serial refit or a finding
that covariates have no effect. Failed statistical candidates retain their failure records.

The per-fit cap/concurrency policy does not promise a fixed end-to-end speedup.
Complete SCM, covariance, concurrent contention and different families may scale differently.

SCM stores maximum completed wall time by assigned thread count for the same fit identity.
Exact-thread observations take precedence; otherwise use the conservative maximum of
observed times rescaled by the capped benchmark curve. Legacy timing lacks a reliable
thread label and is conservatively treated as a seven-thread observation. Unknown work
keeps the existing 240-second cold start. Retain 25% headroom, the learned 60-second floor,
and any explicit PMX_MIN_FIT_S. Do not predict inverse-linear speed from assigned
core-seconds; old core_seconds remain readable telemetry only. The planner reduces workers
when the predicted fit cannot finish in the remaining window. Queue cleanup is reserved once
outside the stage cap; children share its deadline. An estimate larger than a fresh window
returns SCM_BUDGET_INFEASIBLE before dispatch; only otherwise feasible work permits DEFER.
Timing is not fit progress.

Hard queue/stage/worker/covariance caps and unchanged-failure protections remain in force. Completed
model caches remain authoritative; resource changes never authorize refitting. A single
base/final fit or post-fit covariance may use up to seven threads where supported.
Estimator, ODE tolerances, starts, selection criteria and covariance methods stay unchanged.

HTML/graphics/table extraction/Word and lightweight preparation use one numerical thread.
ER/c-QTc cheap regressions stay in their existing process. VPC counts, seed, simulator and
interval definitions are unchanged. Narrative and normal completion gates still apply.
Only refresh reports for prose/formatting; never replay fits for CPU settings. Follow
references/continuation.md for the single background observer and automatic continuation.
PMX_CPU_PLAN logs allocation, not measured CPU utilization or a speedup guarantee.

Timing checkpoints carry a host CPU signature. After a hardware change, discard only timing estimates; preserve scientific fit caches. VPC remains 500 replicates with its existing seed; serial rendering is not a deadlock.
