// Source-bound narrative reference validation; no R job or document render.
import fs from 'node:fs';
import {resolveSidecar} from './regression_layout.mjs';
const normalize=s=>String(s).replace(/\s+/g,' ').trim();
export function checkReportReferences(dir,draft) {
  const file=resolveSidecar(dir,'report_evidence.json');
  const entries=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')).references??[]:[];
  const aliases=new Map();
  for(const r of entries) for(const key of [r.file,r.caption?.replace(/^(Table|Figure)\s+\d+[.:]?\s*/, '')].filter(Boolean)) {
    const alias=r.kind+':'+normalize(key),target=r.kind+' '+r.number;
    if(aliases.has(alias) && aliases.get(alias)!==target) aliases.set(alias,null);
    else if(!aliases.has(alias)) aliases.set(alias,target);
  }
  const prose=[...Object.values(draft.sections??{}),...Object.values(draft.section_results??{})].flat();
  for(const p of prose) if(typeof p==='string') {
    if(p.includes('These are unadjusted quartile summaries with exact binomial intervals.'))
      throw new Error('NARRATIVE_REVIEW_REQUIRED: remove the redundant quartile-interval sentence');
    for(const m of p.matchAll(/\{\{(figure|table):([^{}]+)\}\}/g))
      if(!aliases.get(m[1]+':'+normalize(m[2])))
        throw new Error('NARRATIVE_REFERENCE_INVALID: '+m[0]+'; choose an unambiguous Word-included reference from the current packet');
  }
}
