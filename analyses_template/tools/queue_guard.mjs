#!/usr/bin/env node

import fs from 'node:fs';
import {queueRoot} from './runtime_paths.mjs';
import path from 'node:path';
import {queueHandoff,handoffHasProgress,simulatorRepairReady} from './queue_outcome.mjs';

const BASE = queueRoot({required: process.argv.length>2 && !process.argv.includes('--help')});
const REQ_DIR = path.join(BASE, 'requests');
const RES_DIR = path.join(BASE, 'results');
const BACKOFF_S = Number(process.env.PMX_SUBMIT_BACKOFF_S ?? 180);
const INFLIGHT_TTL_S = Number(process.env.PMX_QUEUE_GUARD_INFLIGHT_TTL_S ?? 24 * 3600);

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--')));
const positional = argv.filter((a) => !a.startsWith('--'));
const dirArg = positional[0];

function usage(msg) {
  console.log(`QUEUE_GUARD_USAGE ${msg}`);
  console.error('usage: node queue_guard.mjs <analysis-dir> [--force] [--quiet]');
  process.exit(2);
}

if (!dirArg) usage('missing analysis directory');
let dir;
try { dir = fs.realpathSync(dirArg); } catch { usage(`no such directory ${dirArg}`); }

if (process.env.PMX_QUEUE_GUARD === 'off' || flags.has('--force')) {
  console.log(`QUEUE_GUARD_FORCED dir=${dir} (${flags.has('--force') ? '--force' : 'PMX_QUEUE_GUARD=off'})`);
  process.exit(0);
}

// A request belongs to this study when its job script lives under the analysis directory. The wrappers
// stage every job script as <dir>/.rsub_*.R and the escape hatch is <dir>/rq_*.R, so the prefix test is
// exact and does not need the queue to carry a "study" field.
function underDir(p) {
  if (typeof p !== 'string' || !p) return false;
  const r = path.resolve(p);
  return r === dir || r.startsWith(dir + path.sep);
}

function readRequest(id) {
  try { return JSON.parse(fs.readFileSync(path.join(REQ_DIR, id + '.json'), 'utf8')); } catch { return null; }
}
function readResult(id) {
  try { return JSON.parse(fs.readFileSync(path.join(RES_DIR, id + '.json'), 'utf8')); } catch { return null; }
}
function finishedAt(id) {
  try { return fs.statSync(path.join(RES_DIR, id + '.json')).mtimeMs; } catch { return null; }
}

function queueIds() {
  let names = [];
  try { names = fs.readdirSync(REQ_DIR); } catch { return []; }
  return names.filter((n) => n.endsWith('.json')).map((n) => n.slice(0, -5));
}

const now = Date.now();
let resumed = null;

// ---- 1. IN FLIGHT: a job for this study that has no result file yet -----------------------------
const inflight = [];
for (const id of queueIds()) {
  if (fs.existsSync(path.join(RES_DIR, id + '.json'))) continue;
  const r = readRequest(id);
  if (!r || !underDir(r.src)) continue;
  let age = null;
  try { age = (now - fs.statSync(path.join(REQ_DIR, id + '.json')).mtimeMs) / 1000; } catch { /* keep null */ }
  if (age !== null && age > INFLIGHT_TTL_S) continue; // a fossil request, not this submission
  inflight.push({ id, age });
}

// Mirrors left by run_regression.sh/run_analysis.sh name their job id; they catch a job whose request
// file was already consumed by the worker (mid-run: request present, result absent, no request match).
const mirrorIds = [];
try {
  for (const m of fs.readdirSync(path.join(dir, '.pmx'))) {
    if (!/^run_[a-z0-9]+_/.test(m)) continue;
    const st = path.join(dir, '.pmx', m, '.pmx_run_state');
    let txt;
    try { txt = fs.readFileSync(st, 'utf8'); } catch { continue; }
    const id = (txt.match(/^ID=(.+)$/m) || [])[1];
    if (!id) continue;
    if (/^PENDING$/i.test(id.trim())) continue;
    // Likewise, a mirror that never advanced past staging (hold, duplicate, submit-failed,
    // word-only-no-html) is debris, not a job: only a state the wrapper reaches AFTER a successful
    // submit can stand for something in the queue. A real, id-bearing mirror is kept, so a job whose
    // request file the worker already consumed is still caught.
    const stage = (txt.match(/^STAGE=(.+)$/m) || [])[1];
    if (stage && !/^(staged|queued|running)$/.test(stage.trim())) continue;
    // ...and a fossil in either case: mirrors are swept by age in the wrapper, but the guard must not
    // resurrect one that outlived the sweep (same TTL as the request-side inflight filter).
    let age = null;
    try { age = (Date.now() - fs.statSync(st).mtimeMs) / 1000; } catch {}
    if (age !== null && age > INFLIGHT_TTL_S) continue;
    if (fs.existsSync(path.join(RES_DIR, id + '.json'))) continue;
    if (!inflight.some((x) => x.id === id)) mirrorIds.push(id);
  }
} catch { /* no .pmx yet: nothing staged */ }

const busyIds = [...new Set([...inflight.map((x) => x.id), ...mirrorIds])];
if (busyIds.length) {
  const id = busyIds[0];
  const age = (inflight.find((x) => x.id === id) || {}).age;
  console.log(`QUEUE_GUARD_BUSY id=${id} dir=${dir}${age != null ? ` age_s=${Math.round(age)}` : ''}` +
    `${busyIds.length > 1 ? ` others=${busyIds.slice(1).join(',')}` : ''}`);
  console.error(`  a job for THIS study is already in the SERIAL queue; a second submission does not`);
  console.error(`  run sooner, it only delays this study and every other request behind it.`);
  console.error(`  follow it:  node r-submit.mjs --await ${id} --max-wait-s=40   (or --attach, backgrounded)`);
  console.error(`  progress:   node r-submit.mjs --tail ${id}   (--status is poll-budgeted: one look per 45 s)`);
  console.error(`  do not bypass this hold or create another waiter; report the pending id.`);
  process.exit(3);
}

// ---- 2. RECENT FAILURE: the last job for this study died seconds ago -----------------------------
// A failure that is environmental or deterministic reproduces exactly; the fix is to read the log.
// Only a NON-ok status within the backoff window holds off a resubmission, so a legitimate refit after
// a completed run is never blocked.
if (BACKOFF_S > 0) {
  let last = null;
  for (const id of queueIds()) {
    const req = readRequest(id);
    if (!req || !underDir(req.src)) continue;
    const fin = finishedAt(id);
    if (fin === null) continue; // still in flight: handled above
    if (!last || fin > last.fin) last = { id, fin };
  }
  if (last) {
    const res = readResult(last.id) || {};
    const status = res.status || res.state || 'unknown';
    const ageS = Math.round((now - last.fin) / 1000);
    const handoff=queueHandoff(res);
    if(handoff && handoffHasProgress(dir,last.id)) resumed={id:last.id,...handoff};
    if(!resumed && simulatorRepairReady(dir,res)) resumed={id:last.id,state:"simulator-repair",next:"s2"};
    if (status !== 'ok' && !resumed && ageS <= BACKOFF_S) {
      console.log(`QUEUE_GUARD_BACKOFF id=${last.id} status=${status} finished_s_ago=${ageS} dir=${dir}`);
      console.error(`  the last job for THIS study ended status=${status} ${ageS}s ago (took_s=${res.took_s ?? '?'}).`);
      console.error(`  a job that fails immediately fails again for the same reason: READ THE LOG.`);
      console.error(`  log:   ${res.log || path.join(BASE, 'logs', last.id + '.out')}`);
      console.error(`  tail:  node r-submit.mjs --tail ${last.id}`);
      console.error(`  stop and repair the named cause; do not sleep through backoff or bypass the guard.`);
      process.exit(3);
    }
  }
}

console.log(`QUEUE_GUARD_OK dir=${dir}${resumed?` resume=${resumed.state} next=${resumed.next} id=${resumed.id} ${resumed.state==="simulator-repair"?"inputs=changed":"progress=verified"}`:""}`);
process.exit(0);
