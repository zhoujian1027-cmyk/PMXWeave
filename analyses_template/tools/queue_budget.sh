#!/bin/sh

PMX_WORKER_TIMEOUT_S=${PMX_WORKER_TIMEOUT_S:-900}
PMX_HEADROOM_S=${PMX_HEADROOM_S:-120}
case "$PMX_WORKER_TIMEOUT_S:$PMX_HEADROOM_S" in *[!0-9:]*|:*) echo "QUEUE_BUDGET_INVALID integer worker/headroom required" >&2; exit 2;; esac
[ "$PMX_WORKER_TIMEOUT_S" -gt 60 ] || { echo "QUEUE_BUDGET_INVALID worker cap must exceed 60s" >&2; exit 2; }
if [ "$PMX_WORKER_TIMEOUT_S" -gt 900 ]; then
  echo "QUEUE_BUDGET_CLAMP worker=$PMX_WORKER_TIMEOUT_S installed_cap=900" >&2
  PMX_WORKER_TIMEOUT_S=900
fi
[ "$PMX_HEADROOM_S" -ge 20 ] || PMX_HEADROOM_S=20
PMX_LADDER_RESERVE_S=${PMX_LADDER_RESERVE_S:-60}
export PMX_WORKER_TIMEOUT_S PMX_HEADROOM_S PMX_LADDER_RESERVE_S

PMX_COLLECT_MAX_S=${PMX_COLLECT_MAX_S:-40}
PMX_ATTACH_MAX_S=${PMX_ATTACH_MAX_S:-$PMX_WORKER_TIMEOUT_S}
export PMX_COLLECT_MAX_S PMX_ATTACH_MAX_S
export RSUB_ATTACH_MAX_S=${RSUB_ATTACH_MAX_S:-$PMX_COLLECT_MAX_S}

qb_collect_wait() { printf "%s\n" "$PMX_COLLECT_MAX_S"; }   # foreground: under the harness kill
qb_attach_wait()  { printf "%s\n" "$PMX_ATTACH_MAX_S"; }    # background: the worker cap is fine

qb_worker_timeout() { printf '%s\n' "$PMX_WORKER_TIMEOUT_S"; }

# Hard ceiling for any single submitted job: always strictly below the worker cap.
qb_job_budget() {
  B=$(( PMX_WORKER_TIMEOUT_S - PMX_HEADROOM_S ))
  [ "$B" -ge 60 ] || B=60
  printf '%s\n' "$B"
}

# A ladder round must finish, rank and promote inside one job, so it gets the reserve too.
qb_budget_ladder() {
  B=$(( $(qb_job_budget) - PMX_LADDER_RESERVE_S ))
  [ "$B" -ge 60 ] || B=60
  if [ "${PMX_LIMIT_S:-0}" -gt 0 ] 2>/dev/null && [ "$PMX_LIMIT_S" -lt "$B" ]; then B=$PMX_LIMIT_S; fi
  printf '%s\n' "$B"
}

# A report stage runs inside one job as well.
qb_budget_stage() {
  B=$(qb_job_budget)
  if [ -n "${PMX_STAGE_TIMEOUT:-}" ]; then
    case "$PMX_STAGE_TIMEOUT" in *[!0-9]*|0) echo "QUEUE_BUDGET_INVALID stage timeout must be a positive integer" >&2; return 2;; esac
    [ "$PMX_STAGE_TIMEOUT" -ge "$B" ] || B=$PMX_STAGE_TIMEOUT
  fi
  printf '%s\n' "$B"
}

qb_poll_ms() {
  if [ "${POLL_MS:-0}" -gt 0 ] 2>/dev/null; then printf '%s\n' "$POLL_MS"; return 0; fi
  printf '%s\n' "$(( (PMX_WORKER_TIMEOUT_S + 300) * 1000 ))"
}
