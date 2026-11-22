#!/usr/bin/env node
// Only explicit study settings are transported; credentials and other environment values are excluded.
// The budget knobs are in the list on purpose: the container-side guards (fit_need/budget_guard in
// run_pipeline.R, the stage timeout) must see the SAME numbers as the host-side queue_budget.sh, or
// the inner guard and the outer worker disagree about when to defer/stop. Overriding a budget is
// therefore a one-place change: export it before calling the tool, no code edit.
const allowed = ['SCM_CRITERION','SCM_P_FWD','SCM_P_BCK','PMX_EST','PMX_FIXED_APPROVED','PMX_ENDPOINT','PMX_DVID','PMX_RESID_INIT','PMX_CMT_OBS','PMX_STAGE_TIMEOUT','PMX_EXPOSURE_LABEL','PMX_SIM_CHECK_RTOL','PMX_SIM_CHECK_ATOL','PMX_SIM_CHECK_REASON','PMX_SIM_CHECK_APPROVED','PMX_PYTHON',
  'PMX_WORKER_TIMEOUT_S','PMX_HEADROOM_S','PMX_LADDER_RESERVE_S','PMX_MIN_FIT_S','PMX_FIT_S_EST','PMX_MIN_COV_FIT_S','PMX_COV_METHOD','PMX_COV_BASE','PMX_COV_FALLBACK_TRIES','PMX_COV_TRIES','PMX_COV_FALLBACK','PMX_COV_UNESTIMABLE_CONTINUE','PMX_SCM_BUDGET_S','PMX_HEARTBEAT_S','PMX_R_CORES','PMX_FIT_THREADS','PMX_MC_CORES','PMX_MAX_MODEL_WORKERS','PMX_MODEL_MEMORY_MB','PMX_MEMORY_RESERVE_MB'];
const values = Object.fromEntries(allowed.filter(k => process.env[k] !== undefined).map(k => [k,process.env[k]]));
const args = process.argv.slice(2);
if(args.length % 2) throw new Error('Expected setting/value pairs');
for(let i=0;i<args.length;i+=2) {
 if(!/^[A-Z][A-Z0-9_]*$/.test(args[i])) throw new Error('Invalid setting name');
 values[args[i]]=args[i+1];
}
if(Object.keys(values).length) process.stdout.write('Sys.setenv('+Object.entries(values).map(([k,v])=>k+'='+JSON.stringify(v)).join(',')+')\n');
