// Shared interpretation of finished fit-family job windows. Never submit work here.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const digest=x=>crypto.createHash('sha256').update(x).digest('hex');
export function queueHandoff(j) {
  if(!j || Number(j.exit)!==3 || j.signal || !['error','checkpoint','deferred','resumable'].includes(j.state || j.status)) return null;
  const text=String(j.stdout || '');
  const checkpoint=text.match(/^STAGES_CHECKPOINT completed=(s1|s1c) next=(s1c|s2|s4|s3|s5);/m);
  if(checkpoint) return {state:'checkpoint',completed:checkpoint[1],next:checkpoint[2]};
  const deferred=text.match(/^STAGES_DEFER stage (s1|s1c) stopped on its job budget\./m);
  if(deferred && /^SCM_DEFER /m.test(text)) return {state:'deferred',next:deferred[1]};
  return null; // Exit 3 alone, a timeout, or arbitrary failure text is not a handoff.
}
// Same content-only fingerprint used by chain_progress.mjs; retain existing ledger compatibility.
export function completedFitProgress(dir,layout='convention') {
  const html=layout==='flat'?dir:path.join(dir,'02_html');
  const cache=path.join(html,'_scm_sel_cache'),artifacts=[];
  const add=p=>{if(fs.existsSync(p) && fs.statSync(p).isFile()) artifacts.push([path.relative(dir,p),digest(fs.readFileSync(p))]);};
  if(fs.existsSync(cache)) for(const name of fs.readdirSync(cache).sort()) {
    const match=name.match(/(?:^|__)([a-f0-9]+)\.rds$/);if(!match)continue;
    const key=match[1],keyFile=path.join(cache,name+'.key');
    if(fs.existsSync(keyFile) && fs.readFileSync(keyFile,'utf8').trim()===key && fs.statSync(path.join(cache,name)).size>0) add(path.join(cache,name));
  }
  for(const root of layout==='flat'?[dir]:[html,path.join(dir,'03_word')]) for(const name of ['s1','s1c','s2','s3','s4','s5']) {
    const p=path.join(root,'artifacts',name);
    if(fs.existsSync(path.join(p,name.toUpperCase()+'_DONE'))) add(path.join(p,'MANIFEST.tsv'));
  }
  return digest(JSON.stringify(artifacts.sort((a,b)=>a[0].localeCompare(b[0]))));
}
export function handoffHasProgress(dir,id) {
  try {
    const prior=JSON.parse(fs.readFileSync(path.join(dir,'.pmx','chain_progress.json'),'utf8'));
    if(prior.schema!==1 || prior.id!==id || typeof prior.progress!=='string')return false;
    const layout=prior.layout ?? (fs.existsSync(path.join(dir,'02_html'))?'convention':'flat');
    if(!['flat','convention'].includes(layout))return false;
    return completedFitProgress(dir,layout)!==prior.progress;
  } catch {return false;}
}

export function simulatorRepairReady(dir,result) {
  if(!result || Number(result.exit)!==1 || result.signal || (result.status||result.state)!=='error')return false;
  const rows=[...String(result.stdout||'').matchAll(/^S2_SIMULATOR_REQUIRED file=(\S+) prior_md5=(missing|[a-f0-9]{32}) source=(\S+) source_md5=([a-f0-9]{32})$/gm)];
  if(!rows.length)return false;
  const root=fs.realpathSync(dir)+path.sep;
  const md5=name=>{
    const file=path.join(dir,name);
    if(!fs.existsSync(file) || !fs.statSync(file).isFile() || !fs.statSync(file).size || !fs.realpathSync(file).startsWith(root))return null;
    return crypto.createHash('md5').update(fs.readFileSync(file)).digest('hex');
  };
  try {
    return rows.every(([,file,prior,source,frozen])=>
      /^(?:final_model\.cpp|(?:02_html\/)?(?:ppk|pkpd|tmdd)_ebe\.cpp)$/.test(file) &&
      /^(?:02_html\/)?artifacts\/s2\/final_fitted\.ctl$/.test(source) &&
      md5(source)===frozen && md5(file)!==null && md5(file)!==prior);
  } catch {return false;}
}
