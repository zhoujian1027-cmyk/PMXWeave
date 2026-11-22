import fs from 'node:fs';
import path from 'node:path';
import {resolveSidecar} from './regression_layout.mjs';
export function fitNarrativePolicy(dir,family) {
  const isFit=['ppk','pkpd','tmdd'].includes(family);
  const fields={};let key='';
  const file=path.join(dir,'report_metadata.dcf');
  if(isFit && fs.existsSync(file)) for(const line of fs.readFileSync(file,'utf8').split(/\r?\n/)) {
    const m=line.match(/^([^\s:]+):\s*(.*)$/);
    if(m){key=m[1];fields[key]=m[2];}
    else if(/^\s+\S/.test(line) && key) fields[key]+=' '+line.trim();
    else if(!line.trim()) key='';
  }
  const mode=(fields.Narrative??'required').trim().toLowerCase(),reason=(fields.NarrativeReason??'').trim();
  if(!['required','omit'].includes(mode)) throw new Error('Narrative must be required or omit');
  if(mode==='omit' && !reason) throw new Error('Narrative omission requires the explicit user request in NarrativeReason');
  let targets=[];
  if(isFit) {
    const e=resolveSidecar(dir,'report_evidence.json');
    const evidence=fs.existsSync(e)?JSON.parse(fs.readFileSync(e,'utf8')):{};
    targets=evidence.narrative?.required_result_targets??[
      '5.1 Data','5.2 Base model','5.3 Covariate selection','5.4 Final model','5.5 Model evaluation'];
  }
  return {required:mode!=='omit',reason,required_result_targets:targets};
}
export function checkFitNarrative(draft,policy) {
  if(!policy.required) return;
  for(const section of ['Discussion','Conclusion']) {
    const value=draft.sections?.[section];
    if(!(typeof value==='string'?value.trim():Array.isArray(value) && value.length))
      throw new Error('NARRATIVE_REQUIRED: missing '+section);
  }
  const missing=policy.required_result_targets.filter(t=>!Object.hasOwn(draft.section_results??{},t));
  if(missing.length) throw new Error('NARRATIVE_REQUIRED_RESULTS: '+missing.join('; '));
}
