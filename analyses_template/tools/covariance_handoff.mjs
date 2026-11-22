#!/usr/bin/env node
// Read-only completed covariance handoff: restore recorded settings before queue submission.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const [dirArg,dataArg,family='ppk',layout='convention',only='']=process.argv.slice(2);
const md5=p=>crypto.createHash('md5').update(fs.readFileSync(p)).digest('hex');
const keys=['PMX_COV_METHOD','PMX_COV_FALLBACK','PMX_COV_BASE'];
const validators=[/^(s|r|r,s)?$/,/^(s|r|r,s)?$/,/^(true|false|0|1|yes|no)?$/i];
const readManifest=p=>{
  const text=fs.readFileSync(p,'utf8');
  const lines=text.split(/\r?\n/);
  const rows=lines.filter(l=>/^(in|out)\t/.test(l)).map(l=>{
    const [kind,file,hash]=l.split('\t');return {kind,file,hash};});
  return {rows,contracts:lines.filter(l=>l.startsWith('# contract\t')).map(l=>l.slice(11))};
};
try {
  if(!dirArg || !dataArg || !['ppk','pkpd','tmdd'].includes(family)) throw Error('invalid handoff arguments');
  const dir=fs.realpathSync(dirArg),html=layout==='flat'?dir:path.join(dir,'02_html');
  const s1=path.join(html,'artifacts','s1'),s1c=path.join(html,'artifacts','s1c');
  if(!fs.existsSync(path.join(s1c,'S1C_DONE'))) process.exit(0);
  const manifest=readManifest(path.join(s1c,'MANIFEST.tsv'));
  const search=readManifest(path.join(s1,'MANIFEST.tsv'));
  const dataRows=search.rows.filter(r=>r.kind==='in' && path.basename(r.file)===path.basename(dataArg));
  if(dataRows.length!==1 || dataRows[0].hash!==md5(dataArg)) {
    console.log('COV_HANDOFF_NOT_REUSED data fingerprint changed');process.exit(0);
  }
  // Validate every producing input/output, including frozen search, source, fit and state.
  if(!manifest.rows.length || !manifest.rows.some(r=>r.kind==='out' && r.file.endsWith('_scm_final_result.rds')))
    throw Error('completed covariance manifest has no frozen result');
  for(const row of manifest.rows) {
    const p=path.resolve(dir,row.file),relative=path.relative(dir,p);
    if(relative.startsWith('..'+path.sep) || path.isAbsolute(relative) ||
       !fs.existsSync(p) || md5(p)!==row.hash) {
      console.log('COV_HANDOFF_NOT_REUSED changed input/output: '+row.file);process.exit(0);
    }
  }
  const state=fs.readFileSync(path.join(html,'_scm_covariance_state.dcf'),'utf8');
  const completed=/^Covariance_state:\s*COMPLETE\s*$/m.test(state);
  // UNESTIMABLE is an explicit, disclosed completion without uncertainty: the gate is
  // genuine, but its result must never be reported as estimated standard errors.
  const unestimable=/^Covariance_state:\s*UNESTIMABLE\s*$/m.test(state);
  if(!completed && !unestimable) throw Error('completed gate disagrees with covariance state');
  if(manifest.contracts.length!==1) throw Error('ambiguous covariance settings receipt');
  const fields=manifest.contracts[0].split('|');
  // The producer appends the three covariance settings to the stage contract; earlier
  // stage_lib revisions recorded them after eight base fields, the current one after ten
  // (PMX_EXPOSURE_LABEL/SCM_P_BCK were added). Both layouts end with the covariance trio,
  // so read it from the tail instead of pinning a field count that drifts with the contract.
  if(fields.length<11) throw Error('unsupported settings receipt; preserve completed covariance');
  const values=fields.slice(-3);
  values.forEach((v,i)=>{if(!validators[i].test(v)) throw Error('invalid recorded '+keys[i]);});
  const defaults=['s','r',family==='ppk'?'true':'false'];
  const semantic=(v,i)=>i===2 ? (['true','1','yes'].includes((v||defaults[i]).toLowerCase())?'true':'false') : (v||defaults[i]);
  const explicitChanges=keys.filter((k,i)=>process.env[k]!==undefined &&
    semantic(process.env[k],i)!==semantic(values[i],i));
  if(explicitChanges.length && only!=='s1c') {
    console.error('COV_HANDOFF_CHANGE_STOP completed covariance settings changed: '+explicitChanges.join(',')+
      '; report continuation preserves the completed method. Use --covariance-only only for a deliberate uncertainty replacement.');
    process.exit(4);
  }
  keys.forEach((k,i)=>{
    if(process.env[k]!==undefined) {
      if(!validators[i].test(process.env[k])) throw Error('invalid '+k);
      // Keep the original spelling in the stage contract for equivalent explicit settings.
      if(!explicitChanges.length) console.log('COV_HANDOFF_SETTING '+k+'='+values[i]);
    } else console.log('COV_HANDOFF_SETTING '+k+'='+values[i]);
  });
  console.log(explicitChanges.length?'COV_HANDOFF_REPLACEMENT covariance-only requested':
    unestimable?'COV_HANDOFF_UNESTIMABLE verified recorded settings; uncertainty was not estimable and stays blank in the report':
    'COV_HANDOFF_REUSED verified completed settings; continue downstream without covariance re-estimation');
} catch(e) {console.error('COV_HANDOFF_ERROR '+e.message);process.exit(2);}
