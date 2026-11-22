#!/usr/bin/env node
// Chain retries compare completed artifacts, never log growth or attempt counters.
import fs from 'node:fs';
import {queueRoot} from './runtime_paths.mjs';
import path from 'node:path';
import crypto from 'node:crypto';
import {completedFitProgress} from './queue_outcome.mjs';
const [mode, dirArg, toolkitArg, dataArg, family = 'ppk', layout = 'convention', chainOnly = '', chainFrom = ''] = process.argv.slice(2);
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const readJson = p => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };
function fileHash(p) { return fs.existsSync(p) && fs.statSync(p).isFile() ? digest(fs.readFileSync(p)) : null; }
try {
  if (!dirArg || !['check', 'record'].includes(mode)) throw new Error('usage: chain_progress.mjs check <dir> <toolkit> <data> <family> <layout> | record <dir> <job-id>');
  const dir = fs.realpathSync(dirArg), stateFile = path.join(dir, '.pmx', 'chain_progress.json');
  if (mode === 'record') {
    const id = toolkitArg;
    if (!/^[A-Za-z0-9_.~+-]+$/.test(id || '')) throw new Error('invalid job id');
    const snapshot = JSON.parse(fs.readFileSync(0, 'utf8'));
    if (snapshot.schema !== 1 || typeof snapshot.inputs !== 'string' || typeof snapshot.progress !== 'string') throw new Error('invalid progress snapshot');
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    const temp = stateFile + '.' + process.pid + '.tmp';
    fs.writeFileSync(temp, JSON.stringify({ ...snapshot, id }) + '\n', { mode: 0o644 });
    fs.renameSync(temp, stateFile);
  } else {
    if (!toolkitArg || !dataArg || !['ppk', 'pkpd', 'tmdd'].includes(family)) throw new Error('missing chain inputs');
    const toolkit = fs.realpathSync(toolkitArg), htmlDir = layout === 'flat' ? dir : path.join(dir, '02_html');
    const cache = path.join(htmlDir, '_scm_sel_cache');
    const settings = Object.fromEntries(['PMX_EST', 'PMX_FIXED_APPROVED', 'PMX_ENDPOINT','PMX_DVID','PMX_RESID_INIT', 'PMX_CMT_OBS', 'SCM_CRITERION', 'SCM_P_FWD', 'SCM_P_BCK', 'PMX_COV_METHOD', 'PMX_COV_BASE', 'PMX_COV_FALLBACK', 'PMX_COV_TRIES', 'PMX_COV_FALLBACK_TRIES', 'PMX_STAGE_TIMEOUT', 'PMX_SCM_BUDGET_S', 'PMX_HEADROOM_S', 'PMX_MIN_FIT_S', 'PMX_FIT_S_EST', 'PMX_MIN_COV_FIT_S'].map(k => [k, process.env[k] || '']));
    const tries = Math.max(1, Number(process.env.PMX_COV_TRIES) || 2);
    // Only crossing the configured-method limit opens a fallback window; counters are not progress.
    settings.covarianceFallbackKeys = fs.existsSync(cache) ? fs.readdirSync(cache).sort().filter(n =>
      /^[a-f0-9]+\.cov_attempts$/.test(n) && Number(fs.readFileSync(path.join(cache,n),'utf8').trim()) >= tries) : [];
    const sourceFiles = ['word-report/cpu_budget.R', ...(family==='pkpd'?['word-report/pkpd_report_contract.R']:[]), 'analyses_template/tools/queue_outcome.mjs', 'word-report/run_pipeline.R', 'word-report/scm_parallel.R', `word-report/family/${family}_model.R`, 'analyses_template/tools/model_contract.R', 'analyses_template/tools/screen_fit_identity.R', 'analyses_template/tools/simulator_contract.R', 'analyses_template/tools/data_filters.R', 'analyses_template/tools/covariate_intake.R', 'word-report/stages/stage_lib.R', 'word-report/stages/run_stages.R', 'word-report/stages/s1_fit.R', 'word-report/stages/s1c_covariance.R', 'word-report/stages/s2_freeze.R', 'word-report/stages/s4_html.R', 'word-report/stages/s5_word.R'];
    settings.simulatorValidation = Object.fromEntries(["PMX_SIM_CHECK_RTOL", "PMX_SIM_CHECK_ATOL", "PMX_SIM_CHECK_REASON", "PMX_SIM_CHECK_APPROVED"].map(k=>[k,process.env[k]||'']));
    const reportInputs = ['s4','s5'].includes(chainFrom) || chainOnly==='s5' ?
      ['report_narrative.json','report_metadata.dcf'].map(n=>[n,fileHash(path.join(dir,n))]) : [];
    const inputs = [family, layout, chainOnly, chainFrom, settings, [dataArg, fileHash(dataArg)], ...['base_model.ctl', 'base_selection.dcf', 'pmx_config.R', 'covariates.csv', 'data_spec.csv'].map(n => [n, fileHash(path.join(dir, n))]), ...reportInputs, ...['final_model.cpp',path.relative(dir,path.join(htmlDir,family+'_ebe.cpp'))].map(n=>[n,fileHash(path.join(dir,n))]), ...sourceFiles.map(n => [n, fileHash(path.join(toolkit, n))])];
    const snapshot = { schema: 1, layout, inputs: digest(JSON.stringify(inputs)), progress: completedFitProgress(dir,layout) };
    const previous = readJson(stateFile);
    if (fs.existsSync(stateFile) && previous?.schema !== 1) throw new Error('invalid progress ledger; inspect it instead of resetting it');
    if (previous?.schema === 1) {
      const resultPath = path.join(queueRoot(), 'results', previous.id + '.json');
      if (!fs.existsSync(resultPath)) {
        console.error(`CHAIN_JOB_RUNNING id=${previous.id}; source/settings changes do not permit rewriting its live mirror`);
        process.exit(3);
      }
    }
    if (previous?.schema === 1 && previous.inputs === snapshot.inputs) {
      const base = queueRoot();
      const result = readJson(path.join(base, 'results', previous.id + '.json'));
      if (!result) { console.error(`CHAIN_JOB_RUNNING id=${previous.id}; follow this job, do not submit another`); process.exit(3); }
      const status = result.status || result.state;
      if (status !== 'ok' && previous.progress === snapshot.progress) {
        console.error(`CHAIN_NO_PROGRESS id=${previous.id} status=${status}; no completed fit or stage was added`);
        console.error('Stop and repair the named failure in the source toolkit; do not edit the mirror, clear counters, or repeat the unchanged chain.');
        process.exit(4);
      }
    }
    process.stdout.write(JSON.stringify(snapshot));
  }
} catch (e) { console.error('CHAIN_PROGRESS_ERROR ' + e.message); process.exit(2); }
