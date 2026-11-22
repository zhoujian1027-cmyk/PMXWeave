#!/usr/bin/env node
// Read-only completion check: no submission, hash repair, or mtime-based success.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {resolveResult,resolveEvidence,resolveSidecar} from './regression_layout.mjs';
const [dirArg, family, dataArg, templateArg, configArg = '', word = '1'] = process.argv.slice(2);
if (!dirArg || !['er', 'cqtc'].includes(family) || !dataArg || !templateArg) process.exit(2);
const dir = path.resolve(dirArg);
const hash = p => crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex');
const same = (entry, p) => !!entry?.md5 && fs.existsSync(p) && hash(p) === entry.md5;
const optionalSame = (entry, p) => fs.existsSync(p) ? same(entry, p) : entry == null;
const finish = (code, state, reason) => { console.log(`REPORT_${state} ${reason}`); process.exit(code); };
try {
  const m = JSON.parse(fs.readFileSync(resolveSidecar(dir, 'run_manifest.json'), 'utf8'));
  if (m.status !== 'ok' || m.family !== family) finish(2, 'STALE', 'no matching successful manifest');
  if (!same(m.inputs?.data, dataArg) || !same(m.inputs?.template, templateArg))
    finish(2, 'STALE', 'data or analysis template changed');
  if (!optionalSame(m.inputs?.config, configArg || path.join(dir, 'pmx_config.R')))
    finish(2, 'STALE', 'configuration changed or was not recorded');
  const label = family.toUpperCase();
  for (const [key, rel] of [['report_html', `${label}_report.html`], ['results_rds', path.relative(dir,resolveResult(dir))]])
    if (!same(m.artifacts?.[key], path.join(dir, rel))) finish(2, 'STALE', `${rel} missing or changed`);
  if (word === '0') finish(0, 'COMPLETE', 'HTML and frozen results match; no submission needed');
  if (!optionalSame(m.inputs?.narrative, path.join(dir, 'report_narrative.json')) ||
      !optionalSame(m.inputs?.metadata, path.join(dir, 'report_metadata.dcf')))
    finish(3, 'WORD_REFRESH', 'prose or metadata changed; use --word-only, not a full render');
  if (!same(m.artifacts?.report_docx, path.join(dir, `${label}_report.docx`)) ||
      !same(m.artifacts?.evidence, resolveSidecar(dir, 'report_evidence.json')))
    finish(3, 'WORD_REFRESH', 'Word or evidence missing or changed; use --word-only');
  const evidence = JSON.parse(fs.readFileSync(resolveSidecar(dir, 'report_evidence.json'), 'utf8'));
  for (const entry of evidence.files || []) {
    const rel = entry.file?.replaceAll('\\', '/');
    if (!rel || path.isAbsolute(rel) || /^[A-Za-z]:/.test(rel) || rel.split('/').includes('..') || !same(entry, resolveEvidence(dir, rel)))
      finish(3, 'WORD_REFRESH', 'report evidence changed; review it before refreshing Word');
  }
  if (['dropped', 'stale'].includes(m.prose?.state))
    finish(4, 'REVIEW', 'unchanged rejected narrative; review prose.reason/file, do not repeat the job');
  if (m.prose?.state !== 'ok' || !fs.existsSync(path.join(dir, 'report_narrative.json')))
    finish(5, 'NARRATIVE_REQUIRED', 'analysis and report files are ready; run node analyses_template/tools/report_narrative.mjs <study> --brief, author both sections, then refresh Word once');
  const narrative = JSON.parse(fs.readFileSync(path.join(dir, 'report_narrative.json'), 'utf8'));
  for (const name of ['Discussion', 'Conclusion']) {
    const raw = narrative.sections?.[name];
    const text = Array.isArray(raw) ? raw : typeof raw === 'string' ? [raw] : [];
    if (!text.length || text.some(p => typeof p !== 'string' || !p.trim() || /\[[^\]]+\]|not available|file not found|template slot|traceback|error:/i.test(p)))
      finish(5, 'NARRATIVE_REQUIRED', 'both Discussion and Conclusion need supported paragraphs; do not repeat the analysis');
  }
  finish(0, 'COMPLETE', 'artifacts, inputs and both narrative sections match; no submission needed');
} catch (e) { finish(2, 'STALE', `completion could not be verified: ${e.message}`); }
