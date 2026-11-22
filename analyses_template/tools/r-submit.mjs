#!/usr/bin/env node
import fs from 'node:fs';
import {queueRoot} from './runtime_paths.mjs';
import {queueHandoff} from './queue_outcome.mjs';
import path from 'node:path';
import crypto from 'node:crypto';

const BASE = queueRoot({required: process.argv.length>2 && !process.argv.includes('--help')});
const REQ_DIR = path.join(BASE, 'requests');
const RES_DIR = path.join(BASE, 'results');
const LOG_DIR = path.join(BASE, 'logs');
const STATUS_DIR = path.join(BASE, 'status');
const TAIL_STATE = path.join(BASE, 'scripts', '.rsub-tail');

const WORKER_TIMEOUT_S = Number(process.env.PMX_WORKER_TIMEOUT_S || 900);
const POLL_DEFAULT_MS = (WORKER_TIMEOUT_S + 300) * 1000;
const pollMs = () => Number(process.env.POLL_MS || POLL_DEFAULT_MS);
const PROGRESS_MS = Number(process.env.RSUB_PROGRESS_MS || 10000);
// A finished result carries up to 200000 characters of stdout AND stderr (the worker's tail cap), i.e.
// ~50K tokens if printed whole. Only small payloads are printed verbatim; anything larger is digested.
const FULL_PRINT_MAX = Number(process.env.RSUB_FULL_PRINT_MAX || 12000);

const EXIT = { ok: 0, error: 1, usage: 2, resumable: 3, crashed: 4, poll: 5 };

const POLL_MIN_INTERVAL_S = Number(process.env.RSUB_POLL_MIN_INTERVAL_S || 45);
const POLL_MAX_STALLED = Number(process.env.RSUB_POLL_MAX_STALLED || 4);
const POLL_DIR = path.join(STATUS_DIR, '.poll');
const POLL_UNTHROTTLED = process.env.RSUB_POLL_UNTHROTTLED === '1';
// A wait defaults to a window SHORTER than the harness kill (~60 s), so it always returns output
// instead of being killed with nothing held by the caller.
const ATTACH_MAX_S = Number(process.env.RSUB_ATTACH_MAX_S || 45);
const AWAIT_MAX_S_DEFAULT = Number(process.env.RSUB_AWAIT_MAX_S || 300);

// --max-wait-s=N / --max-wait N, read straight from argv (the flag parser below keeps only names).
function numFlag(name, dflt) {
  let raw = null;
  const eq = process.argv.find((a) => a.startsWith(`--${name}=`));
  if (eq) raw = eq.slice(eq.indexOf('=') + 1);
  else if (process.argv.includes(`--${name}`)) raw = process.argv[process.argv.indexOf(`--${name}`) + 1];
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : dflt;
}

const sha16 = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 16);
const now = () => new Date().toISOString();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function readJson(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}
const checkpointOf = queueHandoff;
const readResult = (id) => readJson(path.join(RES_DIR, id + '.json'));
const readStatus = (id) => readJson(path.join(STATUS_DIR, id + '.json'));
const hasRequest = (id) => fs.existsSync(path.join(REQ_DIR, id + '.json'));

// One word for "where is this job right now". The status file is written by the worker; a request with
// no status file yet is simply queued (the worker is one instance driven by cron).
function stateOf(id) {
  const r = readResult(id);
  if (r) return { state: checkpointOf(r)?.state || r.status || 'ok', result: r, status: null, resultPath: path.join(RES_DIR, id + '.json'), log: null };
  const s = readStatus(id);
  if (s && s.state) return { state: s.state, result: null, status: s, resultPath: null, log: s };
  if (hasRequest(id)) return { state: 'queued', result: null, status: null, resultPath: null, log: null };
  return { state: 'none', result: null, status: null, resultPath: null, log: null };
}

// ---- the poll ledger -------------------------------------------------------------------------
const pollPath = (id) => path.join(POLL_DIR, id + '.json');
const readPoll = (id) => readJson(pollPath(id));
function writePoll(id, rec) {
  try {
    fs.mkdirSync(POLL_DIR, { recursive: true });
    fs.writeFileSync(pollPath(id), JSON.stringify(rec, null, 1));
    fs.chmodSync(pollPath(id), 0o666);
  } catch { /* a ledger we cannot write must never break a read */ }
}
const TERMINAL = ['ok', 'error', 'crashed', 'timeout', 'checkpoint', 'deferred'];

// Record one look at `id` and decide whether this look is allowed. Returns null to allow, or a
// verdict object describing the refusal. A change of state re-opens the window with a fresh budget:
// the refusal is about looking twice at the SAME fact, never about following a job.
function pollVerdict(id, kind) {
  const st = stateOf(id);
  const t = Date.now();
  let rec = readPoll(id);
  if (!rec || rec.state !== st.state) {
    rec = { id, state: st.state, looks: 0, refused: 0, stopped: false, first: t, updated: t, last: 0, lastKind: null };
  }
  const idleS = rec.last ? (t - rec.last) / 1000 : Infinity;
  const terminal = TERMINAL.includes(st.state);
  let why = null;
  if (!terminal && rec.stopped) why = 'stopped';
  else if (!terminal && idleS < POLL_MIN_INTERVAL_S) why = 'throttled';
  if (why) {
    rec.refused = (rec.refused || 0) + 1;
    rec.updated = t;
    rec.lastKind = kind;
    // Banging on a closed/throttled window is itself evidence of a spin: a run of refusals closes it.
    if (!terminal && rec.refused >= POLL_MAX_STALLED) rec.stopped = true;
    writePoll(id, rec);
    return { why, rec, state: st.state, nextS: why === 'stopped' ? null : Math.max(1, Math.ceil(POLL_MIN_INTERVAL_S - idleS)) };
  }
  rec.looks = (rec.looks || 0) + 1;
  rec.refused = 0;
  rec.last = t;
  rec.lastKind = kind;
  rec.updated = t;
  if (!terminal && rec.looks > POLL_MAX_STALLED) rec.stopped = true;
  writePoll(id, rec);
  return null;
}

function printPollRefusal(id, v) {
  const cp = path.basename(process.argv[1]);
  if (v.why === 'throttled') {
    console.error(`RSUB_POLL_THROTTLED id=${id} state=${v.state}; the last look was ` +
      `${v.rec.last ? Math.round((Date.now() - v.rec.last) / 1000) + 's' : 'n/a'} ago (kind=${v.rec.lastKind}).`);
    console.error(`  poll budget: ONE look per ${POLL_MIN_INTERVAL_S}s per id; ${v.rec.looks}/${POLL_MAX_STALLED} ` +
      `used in state=${v.state}, ${v.rec.refused} refused.`);
  } else {
    console.error(`RSUB_POLL_STOP id=${id} state=${v.state}: ${v.rec.looks} looks, still unchanged, ` +
      `${v.rec.refused} further look(s) refused. The window is CLOSED for this state.`);
  }
  console.error('  a repeated look cannot change the answer: the worker is SERIAL and the job is NOT lost.');
  console.error(`  wait properly:  node ${cp} --await ${id} --max-wait-s=40     (one foreground window only)`);
  console.error(`  or background:  node ${cp} --attach ${id} --follow --summary (single background observer; wakes on completion)`);
  console.error('  the window re-opens by itself on a state change; cached fits and the search state are on disk.');
}

// ---------------------------------------------------------------------------------------------
// Digest: a result is evidence, but 200 KB of mrgsolve compile noise is not. Keep the lines that
// carry a decision (gate table, fits, errors, the segfault banner) and drop the scroll.
const KEEP_RE = /^(CHAIN_|LADDER_|SCM_|S1_|S2_|S3_|S4_|S5_|STAGES_|KEY|PARSE|OFV|BIC|CONVERGE|MIRROR_|RSUB_|PROBE|CACHE|FIT_|NARRATIVE_|WORD_|NCA_|INIT_|INITIALS)/;
const HIT_RE = /\b(error|Error|ERROR|warning|Warning|caught segfault|Execution halted|not converged|NA\/NaN|killed|Timeout|timed out)\b/;
const HANDOFF_RE = /^(?:CHAIN_GATE\b|CHAIN_(?:DONE|COVARIANCE_DONE|CHECKPOINT|DEFER|NARRATIVE_REQUIRED)\b|STAGES_(?:CHECKPOINT|DEFER)\b|LADDER_(?:OK|PARTIAL|NEXT|STOP|BLOCKED|EXPORT_REQUIRED)\b|NARRATIVE_REQUIRED\b)/;

function digest(text, { head = 6, tail = 24, maxHits = 25 } = {}) {
  if (!text) return '';
  const lines = text.split('\n').filter(line=>!/^\s*\[[=| -]+\]\s*[0-9: ]*\s*$/.test(line));
  if (lines.length <= head + tail + 4) return lines.join('\n');
  const picked = new Set();
  const box = (i) => { if (i >= 0 && i < lines.length) picked.add(i); };
  for (let i = 0; i < head; i++) box(i);
  for (let i = Math.max(0, lines.length - tail); i < lines.length; i++) box(i);
  for (let i = 0; i < lines.length; i++) if (HANDOFF_RE.test(lines[i])) box(i);
  let kept = 0;
  for (let i = 0; i < lines.length && kept < maxHits; i++) {
    if (KEEP_RE.test(lines[i]) || HIT_RE.test(lines[i])) { if (!picked.has(i)) { picked.add(i); kept++; } }
  }
  const idx = [...picked].sort((a, b) => a - b);
  const out = [];
  let prev = -2;
  for (const i of idx) {
    if (i !== prev + 1) out.push(`        ... (lines ${prev + 2}-${i} omitted) ...`);
    out.push(lines[i]);
    prev = i;
  }
  if (prev < lines.length - 1) out.push(`        ... (lines ${prev + 2}-${lines.length} omitted) ...`);
  return out.join('\n');
}

function describeLines(text, n) {
  if (!text) return '0 lines';
  const c = text.split('\n').length;
  return `${c} lines, ${Buffer.byteLength(text, 'utf8')} B`;
}

const bytesOf = (p) => { try { return fs.statSync(p).size; } catch { return 0; } };
const mtimeOf = (p) => { try { return fs.statSync(p).mtimeMs; } catch { return 0; } };

// The most recent line of either stream - the cheapest honest answer to "is it still working?".
function lastBit(id) {
  for (const ext of ['out', 'err']) {
    const p = path.join(LOG_DIR, id + '.' + ext);
    if (!fs.existsSync(p)) continue;
    try {
      const fd = fs.openSync(p, 'r');
      const size = fs.fstatSync(fd).size;
      const n = Math.min(size, 400);
      const buf = Buffer.alloc(n);
      fs.readSync(fd, buf, 0, n, size - n);
      fs.closeSync(fd);
      const ls = buf.toString('utf8').split('\n').filter((s) => s.trim());
      if (ls.length) return ls[ls.length - 1].trim().slice(0, 110);
    } catch { /* unreadable -> no hint */ }
  }
  return '';
}

function progressLine(id, t0) {
  const st = stateOf(id);
  const el = Math.round((Date.now() - t0) / 1000);
  if (st.result) return null;
  const outB = bytesOf(path.join(LOG_DIR, id + '.out'));
  const errB = bytesOf(path.join(LOG_DIR, id + '.err'));
  const newest = Math.max(mtimeOf(path.join(LOG_DIR, id + '.out')), mtimeOf(path.join(LOG_DIR, id + '.err')));
  const ageS = newest ? Math.round((Date.now() - newest) / 1000) : -1;
  const last = lastBit(id);
  return `[${String(el).padStart(4)}s] ${st.state.padEnd(7)} id=${id}` +
    ` out=${(outB / 1024).toFixed(1)}KB err=${(errB / 1024).toFixed(1)}KB` +
    (ageS >= 0 ? ` last_write=${ageS}s ago` : ' no_log_yet') +
    (last ? ` :: ${last}` : '');
}

// ---------------------------------------------------------------------------------------------
function printPayload(j, id, { summary = false } = {}) {
  const total = (j.stdout || '').length + (j.stderr || '').length;
  const useDigest = summary || total > FULL_PRINT_MAX;
  const logP = path.join(LOG_DIR, id + '.out');
  console.log(`=== STATUS ${checkpointOf(j)?.state || j.status}${j.state && j.state !== j.status ? ' state=' + j.state : ''} exit ${j.exit}` +
    (j.signal ? ' signal=' + j.signal : '') + ` took_s ${j.took_s} ===`);
  console.log(`    ${describeLines(j.stdout || '', 0)} stdout | ${describeLines(j.stderr || '', 0)} stderr` +
    (fs.existsSync(logP) ? ` | log ${LOG_DIR}/${id}.out` : ''));
  if (useDigest) {
    console.log(`--- stdout (digest; full log in ${LOG_DIR}/${id}.out, ${bytesOf(path.join(LOG_DIR, id + '.out'))} B) ---`);
    console.log(digest(j.stdout || ''));
    if (j.stderr) {
      console.log(`--- stderr (digest; full log in ${LOG_DIR}/${id + ''}.err, ${bytesOf(path.join(LOG_DIR, id + '.err'))} B) ---`);
      console.log(digest(j.stderr, { head: 3, tail: 12, maxHits: 20 }));
    }
  } else {
    if (j.stdout) console.log(j.stdout);
    if (j.stderr) { console.log('--- stderr ---'); console.log(j.stderr); }
  }
}

function exitForResult(j, { quiet = false } = {}) {
  const state = j.state || j.status;
  const checkpoint = checkpointOf(j);
  if(checkpoint) {
    if(!quiet) console.error(`RSUB_${checkpoint.state.toUpperCase()} completed=${checkpoint.completed ?? "none"} next=${checkpoint.next}; this job is finished. Continue the wrapper once in a fresh job using valid gates/caches; do not attach to the completed id or replay finished fits.`);
    process.exit(EXIT.resumable);
  }
  if (j.status === 'timeout'  || state === 'timeout') {
    if (!quiet) {
      console.error('RSUB_WORKER_TIMEOUT the worker ended this job at its cap (rc=' + j.exit + '); this id is finished.');
      console.error('Cached fits/search state survive. Exit 3 alone is not a resumable checkpoint.');
      console.error('BLOCKED: review the timeout once; do not reattach to this finished id, split/replay screening or resubmit unchanged work.');
    }
    process.exit(EXIT.resumable);
  }
  if (state === 'crashed' || (j.signal && j.signal !== 0)) {
    if (!quiet) {
      console.error('RSUB_CRASHED the R process died on signal ' + (j.signal || (j.exit - 128)) +
        ' (' + signalName(j.signal || (j.exit - 128)) + '); this is NOT an R error.');
      console.error('Log: ' + path.join(LOG_DIR, (j.id || '') + '.err') + '  Result: ' + path.join(RES_DIR, (j.id || '') + '.json'));
    }
    process.exit(EXIT.crashed);
  }
  process.exit(j.status === 'ok' ? EXIT.ok : EXIT.error);
}

const SIGNALS = { 2: 'SIGINT', 6: 'SIGABRT', 9: 'SIGKILL', 11: 'SIGSEGV', 15: 'SIGTERM' };
const signalName = (n) => SIGNALS[n] || ('signal ' + n);

// ---------------------------------------------------------------------------------------------
const argv = process.argv.slice(2);
const flags = new Set();
const positional = [];
let fromArg = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--from') { fromArg = Number(argv[++i]); continue; }
  if (a.startsWith('--')) { flags.add(a); continue; }
  positional.push(a);
}

const USAGE = `usage:
  r-submit.mjs <script.R> [id]              submit, print RSUB_JOB <id>, return at once
  r-submit.mjs --wait <script.R> [id]       submit, then wait for the result
  r-submit.mjs --attach <id> --follow --summary  background observer across queue/execution until result
  r-submit.mjs --await <id> [--max-wait-s=N] sleep, look once per budget tick, give the turn back
  r-submit.mjs --status <id> [--json]       one-shot state; POLL-BUDGETED, exit ${EXIT.poll} when too soon
  r-submit.mjs --tail <id> [--from N]       incremental log read
  r-submit.mjs --result <id> [--summary]    print a finished result
flags: --max-wait-s=N    bounded window for --attach/--await (attach default ${ATTACH_MAX_S}s, under the
                         harness kill so a wait always returns output); --force-resubmit

POLL RULE: one look per id per ${POLL_MIN_INTERVAL_S}s. A second look in the same state exits ${EXIT.poll} with
RSUB_POLL_THROTTLED; after ${POLL_MAX_STALLED} looks with no state change the window closes (RSUB_POLL_STOP) until
the job moves. Do NOT loop --status: wait with --await/--attach.`;

if(flags.has('--follow') && !flags.has('--attach')) {
  console.error('RSUB_FOLLOW_USAGE --follow requires --attach <id> in background mode; it never submits work');
  process.exit(EXIT.usage);
}
// ---- read-only modes -------------------------------------------------------------------------
if (flags.has('--status')) {
  const id = positional[0];
  if (!id) { console.error(USAGE); process.exit(EXIT.usage); }
  refuseHiddenPending(id);
  const st = stateOf(id);
  // The poll budget is checked BEFORE the answer is printed, so a repeated look costs one line, not
  // another read of the same fact. Result states are always served (they carry the payload).
  const verdict = POLL_UNTHROTTLED ? null : pollVerdict(id, 'status');
  if (verdict) { printPollRefusal(id, verdict); process.exit(EXIT.poll); }
  const out = {
    id, state: st.state,
    result: st.resultPath, log_out: path.join(LOG_DIR, id + '.out'), log_err: path.join(LOG_DIR, id + '.err'),
    out_bytes: bytesOf(path.join(LOG_DIR, id + '.out')), err_bytes: bytesOf(path.join(LOG_DIR, id + '.err')),
    status: st.status, poll: readPoll(id),
  };
  if (st.result) { out.exit = st.result.exit; out.signal = st.result.signal; out.took_s = st.result.took_s; out.finished = st.result.finished; }
  if (flags.has('--json')) console.log(JSON.stringify(out, null, 1));
  else console.log(`${st.state} id=${id}` + (out.took_s !== undefined ? ` took_s=${out.took_s}` : '') +
    (out.finished ? ` finished=${out.finished}` : '') + ` out=${(out.out_bytes / 1024).toFixed(1)}KB err=${(out.err_bytes / 1024).toFixed(1)}KB` +
    (lastBit(id) ? ` :: ${lastBit(id)}` : ''));
  if (st.state === 'checkpoint' || st.state === 'deferred') {
    const c=checkpointOf(st.result);
    console.error(`RSUB_${c.state.toUpperCase()} completed=${c.completed ?? "none"} next=${c.next}; use the wrapper to continue from the next stage, preserving completed fits`);
    process.exit(EXIT.resumable);
  }
  if (st.state === 'ok') process.exit(0);
  if (st.state === 'error') process.exit(1);
  if (st.state === 'crashed') process.exit(4);
  if (st.state === 'timeout') process.exit(3);
  if (!POLL_UNTHROTTLED && (st.state === 'queued' || st.state === 'running')) {
    const rec = readPoll(id);
    if (rec) console.error(`  poll budget: ${rec.looks}/${POLL_MAX_STALLED} looks used in state=${st.state}` +
      (rec.stopped ? ' - window CLOSED (RSUB_POLL_STOP); re-opens on a state change' :
        `; next look allowed in ${Math.max(0, Math.ceil(POLL_MIN_INTERVAL_S - (Date.now() - rec.last) / 1000))}s`) +
      `. Keep/create one background --attach ${id} --follow --summary observer; no repeated status calls`);
  }
  process.exit(0); // queued / running / none are not failures of a status query
}

if (flags.has('--tail')) {
  const id = positional[0];
  if (!id) { console.error(USAGE); process.exit(EXIT.usage); }
  refuseHiddenPending(id);
  const fromFlag = fromArg;
  let state = {};
  try { state = JSON.parse(fs.readFileSync(TAIL_STATE, 'utf8')) || {}; } catch { /* first read */ }
  fs.mkdirSync(path.dirname(TAIL_STATE), { recursive: true });
  const CAP = 8000;
  const chunks = [];
  let nextKind = 'out';
  for (const ext of ['out', 'err']) {
    const p = path.join(LOG_DIR, id + '.' + ext);
    const size = bytesOf(p);
    const off = fromFlag !== null ? fromFlag : (state[id + '.' + ext] || 0);
    if (size <= off) { state[id + '.' + ext] = size; continue; }
    const n = Math.min(size - off, CAP);
    const fd = fs.openSync(p, 'r');
    const buf = Buffer.alloc(n);
    fs.readSync(fd, buf, 0, n, off);
    fs.closeSync(fd);
    state[id + '.' + ext] = off + n;
    chunks.push(`--- ${ext} bytes ${off}..${off + n} of ${size} ---\n` + buf.toString('utf8'));
    nextKind = ext;
  }
  fs.writeFileSync(TAIL_STATE, JSON.stringify(state));
  if (!chunks.length) {
    const st = stateOf(id);
    if (st.result) { console.log(`RSUB_TAIL_END ${id} (no new log bytes; job ${st.state})`); process.exit(0); }
    console.log(`RSUB_TAIL_IDLE ${id} state=${st.state} ${lastBit(id)}`);
    process.exit(EXIT.resumable);
  }
  process.stdout.write(chunks.join('\n'));
  void nextKind;
  process.exit(0);
}

if (flags.has('--result')) {
  const id = positional[0];
  if (!id) { console.error(USAGE); process.exit(EXIT.usage); }
  refuseHiddenPending(id);
  const j = readResult(id);
  if (!j) { console.error(`RSUB_NO_RESULT ${id} is not finished (state=${stateOf(id).state})`); process.exit(EXIT.resumable); }
  printPayload(j, id, { summary: flags.has('--summary') });
  exitForResult(j);
}

// A terminal status without its published result is not a live job. Allow only the
// worker's short status-to-result publication gap; old status fossils cannot authorize a wait.
function requireObservable(id) {
  const st=stateOf(id);
  if(st.result)return;
  if(st.state==='none') {
    console.error(`RSUB_NO_SUCH_JOB id=${id}; use the exact wrapper receipt, never predict/increment ids`);
    process.exit(EXIT.usage);
  }
  if(TERMINAL.includes(st.state) || ['completed','failed','killed'].includes(st.state)) {
    const statusFile=path.join(STATUS_DIR,id+'.json');
    let changed=0;try{changed=fs.statSync(statusFile).mtimeMs;}catch{}
    const ended=Number(st.status?.updated_epoch)*1000 || Date.parse(st.status?.updated || '') || changed;
    if(!ended || Date.now()-ended>30000) {
      console.error(`RSUB_RESULT_MISSING id=${id} terminal_status=${st.state}; no published result. Stop this observer and review queue publication; do not resubmit or invent a new id`);
      process.exit(EXIT.error);
    }
  }
}
async function awaitBounded(id, maxS) {
  requireObservable(id);
  const t0 = Date.now();
  if(maxS>40) console.error('RSUB_WAIT_CAPPED foreground --await is capped at 40s; use one background --attach waiter for longer work');
  maxS=Math.min(maxS,40);
  const deadline = t0 + maxS * 1000;
  const cp = path.basename(process.argv[1]);
  const tickMs = Math.max(2, POLL_MIN_INTERVAL_S) * 1000;
  let looks = 0;
  for (;;) {
    const j = readResult(id);
    if (j) { printPayload(j, id, { summary: flags.has('--summary') }); exitForResult(j); }
    requireObservable(id);
    if (Date.now() >= deadline) break;
    // A wait is the sanctioned act: it is never refused for looking too often. A refused ledger
    // entry only means the wait sleeps the rest of the tick and re-checks the RESULT file.
    const v = pollVerdict(id, 'await');
    if (v) {
      const waitS = v.why === 'stopped' ? POLL_MIN_INTERVAL_S : (v.nextS || POLL_MIN_INTERVAL_S);
      await sleep(Math.min(waitS * 1000, Math.max(500, deadline - Date.now())));
      continue;
    }
    looks++;
    const st = stateOf(id);
    console.error(`RSUB_AWAIT id=${id} state=${st.state} look=${looks} waited=${Math.round((Date.now() - t0) / 1000)}s/${maxS}s` +
      (lastBit(id) ? ` :: ${lastBit(id)}` : ''));
    await sleep(Math.min(tickMs, Math.max(500, deadline - Date.now())));
  }
  const late = readResult(id);
  if (late) { printPayload(late, id, { summary: flags.has('--summary') }); exitForResult(late); }
  const st = stateOf(id);
  console.error(`RSUB_PENDING id=${id} state=${st.state} (await window ${maxS}s elapsed after ${looks} look(s)) - the job is NOT lost.`);
  console.error('  Foreground window closed: keep/create the single background --attach --follow --summary observer, then yield WAITING for automatic completion. Missing background support is a capability blocker, not an automatic-resume promise.');
  console.error('  do NOT loop --status: repeated looks in an unchanged state are refused (RSUB_POLL_STOP).');
  process.exit(EXIT.resumable);
}

if (flags.has('--await')) {
  const id = positional[0];
  if (!id) { console.error(USAGE); process.exit(EXIT.usage); }
  refuseHiddenPending(id);
  if (stateOf(id).state === 'none') {
    console.error(`RSUB_NO_SUCH_JOB id=${id} (no request, no status, no result)`);
    process.exit(EXIT.usage);
  }
  await awaitBounded(id, numFlag('max-wait-s', numFlag('max-wait', AWAIT_MAX_S_DEFAULT)));
}

// ---- waiting ---------------------------------------------------------------------------------
function refuseHiddenPending(id) {
  if(id?.startsWith('.') && !readResult(id)) {
    console.error(`RSUB_UNRUNNABLE_ID ${id}: the worker ignores hidden request files. Stop waiting; repair the submission id. Do not resubmit analyses to read existing results.`);
    process.exit(EXIT.usage);
  }
}
async function attach(id, t0 = Date.now()) {
  refuseHiddenPending(id);
  requireObservable(id);
  const rp = path.join(RES_DIR, id + '.json');
  // Bounded by default (ATTACH_MAX_S, under the ~60 s harness kill) so a foreground wait ALWAYS
  // returns output - the caller can never be left with an un-followable, id-less job.
  // PMX background observation explicitly passes --follow; bounded collection remains supported.
  const follow=flags.has('--follow');
  const capS = follow ? 86400 : Math.min(numFlag('max-wait-s', numFlag('max-wait', ATTACH_MAX_S)), Math.round(pollMs() / 1000));
  if(follow) console.error(`RSUB_FOLLOW id=${id} observing only; completion wakes the owning agent; no R job submitted`);
  const deadline = Date.now() + capS * 1000;
  let nextProgress = Date.now();
  for (;;) {
    const j = readResult(id);
    if (j) { printPayload(j, id, {summary:follow || flags.has('--summary')}); exitForResult(j); }
    requireObservable(id);
    if (Date.now() >= deadline) break;
    if (!follow && !flags.has('--summary') && Date.now() >= nextProgress) {
      nextProgress = Date.now() + PROGRESS_MS;
      const line = progressLine(id, t0);
      if (line) console.error(line);
    }
    await sleep(1500);
  }
  const late = readResult(id);
  if (late) { printPayload(late, id, {summary:follow || flags.has('--summary')}); exitForResult(late); }
  const st = stateOf(id);
  if(follow) {
    console.error(`RSUB_WATCH_BLOCKED id=${id} state=${st.state}; no result after 24h. Preserve work and review worker/observer infrastructure; do not resubmit or create another watcher.`);
    process.exit(EXIT.error);
  }
  console.error(`RSUB_PENDING id=${id} state=${st.state} (waited ${capS}s) - the job is NOT lost.`);
  console.error(`  observer: node ${path.basename(process.argv[1])} --attach ${id} --follow --summary (background; at most one ACTIVE observer)`);
  console.error(`  fallback:   node ${path.basename(process.argv[1])} --await ${id} --max-wait-s=40 (one foreground window only)`);
  console.error(`  progress:   node ${path.basename(process.argv[1])} --tail ${id}   (--status is POLL-BUDGETED: one look per ${POLL_MIN_INTERVAL_S}s)`);
  console.error('  Do NOT resubmit the same model: the worker is SERIAL and an identical in-flight job is');
  console.error('  refused as RSUB_DUPLICATE anyway; cached fits and the search state are on disk.');
  process.exit(EXIT.resumable);
}

if (flags.has('--attach')) {
  const id = positional[0];
  if (!id) { console.error(USAGE); process.exit(EXIT.usage); }
  refuseHiddenPending(id);
  if (!fs.existsSync(path.join(RES_DIR, id + '.json')) && !hasRequest(id) && !readStatus(id)) {
    console.error(`RSUB_NO_SUCH_JOB id=${id} (no request, no status, no result)`);
    process.exit(EXIT.usage);
  }
  await attach(id);
}

// ---- submit ----------------------------------------------------------------------------------
const wantWait = flags.has('--wait');
const src = positional[0];
const explicitId = positional[1] || null;
if (!src) { console.error(USAGE); process.exit(EXIT.usage); }
if (!fs.existsSync(src)) { console.error('no such file:', src); process.exit(EXIT.usage); }
const abs = path.resolve(src);

const code = fs.readFileSync(src, 'utf8');
const sha = sha16(code);

function inFlightDuplicate() {
  const cutoff = Date.now() - 24 * 3600 * 1000;
  let names = [];
  try { names = fs.readdirSync(REQ_DIR); } catch { return []; }
  const hits = [];
  for (const n of names) {
    if (!n.endsWith('.json')) continue;
    const id = n.slice(0, -5);
    if (fs.existsSync(path.join(RES_DIR, id + '.json'))) continue; // finished: a refit is legitimate
    let raw;
    try {
      const p = path.join(REQ_DIR, n);
      if (fs.statSync(p).mtimeMs < cutoff) continue;
      raw = fs.readFileSync(p, 'utf8');
    } catch { continue; }
    let r; try { r = JSON.parse(raw); } catch { continue; }
    const s = r.sha || (typeof r.code === 'string' ? sha16(r.code) : null);
    if (s === sha) hits.push(id);
  }
  return hits;
}

let id = explicitId || path.basename(src).replace(/\.[^.]+$/, '');
if (id.startsWith('--')) id = path.basename(src).replace(/\.[^.]+$/, '');
const originalId = id;
id = id.replace(/^\.+/, '');
if (!/^[A-Za-z0-9_][A-Za-z0-9_.~-]*$/.test(id)) {
  console.error('RSUB_INVALID_ID use a non-hidden job id containing letters, digits, underscores, dots, hyphens or tildes');
  process.exit(EXIT.usage);
}
if(id !== originalId) console.error(`RSUB_ID_NORMALIZED ${originalId} -> ${id}: hidden request files are not executable`);

const dups = flags.has('--force-resubmit') ? [] : inFlightDuplicate();
if (dups.length) {
  console.log(`RSUB_DUPLICATE id=${dups[0]} identical script already in flight (sha=${sha}); not submitting.`);
  console.log(`  same text as ${abs}`);
  console.error(`  RSUB_DUPLICATE refusing to queue a second copy of the same model: the worker is`);
  console.error(`  SERIAL, so a duplicate does not run sooner, it only delays every other request.`);
  const cp = path.basename(process.argv[1]);
  console.error(`  wait:      node ${cp} --await ${dups[0]} --max-wait-s=40   (one foreground fallback only)`);
  console.error(`  or attach: node ${cp} --attach ${dups[0]} --follow --summary  (one BACKGROUND observer)`);
  console.error(`  override:  --force-resubmit`);
  if (wantWait) await attach(dups[0]);
  process.exit(EXIT.ok);
}

// Never overwrite a finished result: take the first free `<id>~N` instead (agent.md forbids silent
// deletion, and the old client deleted results/<id>.json before every submit).
const idTaken=id=>[RES_DIR,REQ_DIR,STATUS_DIR].some(dir=>fs.existsSync(path.join(dir,id+'.json')));
let finalId = id;
if (idTaken(finalId)) {
  let n = 2;
  while (idTaken(`${id}~${n}`)) {
    if (++n > 99) { console.error(`RSUB_ID_TAKEN ${id}: too many suffixes; pass a new id`); process.exit(EXIT.usage); }
  }
  finalId = `${id}~${n}`;
  console.error(`r-submit: id "${id}" is taken; submitting as "${finalId}" (the previous result is preserved).`);
}

const reqPath = path.join(REQ_DIR, finalId + '.json');
const temporary = path.join(REQ_DIR, '.' + crypto.randomUUID() + '.tmp');
try {
  fs.writeFileSync(temporary, JSON.stringify({ id: finalId, sha, created: now(), src: abs, code }, null, 2),
    { flag: 'wx', mode: 0o666 });
  fs.chmodSync(temporary, 0o666);
  fs.linkSync(temporary, reqPath);
} catch (error) {
  console.error('RSUB_SUBMIT_FAILED: ' + error.message);
  process.exitCode = EXIT.error;
} finally {
  if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
}
if (process.exitCode) process.exit(process.exitCode);
// The id is the contract with the caller: one machine-readable line, printed before anything can wait.
console.log(`RSUB_JOB ${finalId}`);
console.error(`submitted ${reqPath} ${fs.statSync(reqPath).size} B`);

if (wantWait) await attach(finalId);
process.exit(EXIT.ok);
