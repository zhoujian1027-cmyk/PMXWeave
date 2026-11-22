#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const metadata=new Set(['report_results.rds','report_context.json','labels.csv','endpoints.csv','safety_endpoints.csv']);
const analysisTable=name=>/^tbl_.*\.csv$/.test(name);
export function resolveSidecar(dir,name) {
  const current=path.join(dir,'output',name);
  return fs.existsSync(current) ? current : path.join(dir,name);
}
export function resolveResult(dir) {
  const current=path.join(dir,'output','report_results.rds');
  if(fs.existsSync(current)) return current;
  for(const rel of ['report_results.rds','02_html/artifacts/s2/final.rds','artifacts/s2/final.rds']) {
    const p=path.join(dir,rel);if(fs.existsSync(p)) return p;
  }
  return path.join(dir,'report_results.rds');
}
export function resolveEvidence(dir,rel) {
  const norm=rel.replaceAll('\\','/');
  const name=path.posix.basename(norm);
  if (!norm.includes('/') || /^output\/[^/]+$/.test(norm)) {
    const current=metadata.has(name) ? path.join(dir,'output',name) :
      analysisTable(name) ? path.join(dir,'table','analysis',name) : null;
    if(current && fs.existsSync(current)) return current;
  }
  const exact=path.join(dir,norm);
  if(fs.existsSync(exact)) return exact;
  if (/^(output|02_html)\/[^/]+$/.test(norm)) return path.join(dir,name);
  return exact;
}
function copySet(from,to,accept,dataName='') {
  if(!fs.existsSync(from)) return;
  for(const name of fs.readdirSync(from)) {
    if(!accept(name)) continue;
    const source=path.join(from,name);
    if(!fs.statSync(source).isFile()) continue;
    if(name===dataName) throw new Error('Generated output collides with original dataset: '+name);
    fs.mkdirSync(to,{recursive:true});
    const target=path.join(to,name);
    if(fs.existsSync(target) && fs.lstatSync(target).isSymbolicLink()) throw new Error('Refusing output symlink: '+target);
    fs.copyFileSync(source,target);
  }
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const [mode,first,second,rmd,dataName='']=process.argv.slice(2);
  if(mode==='select-template') {
    const current=path.join(first,rmd); let selected=second;
    if(fs.existsSync(current)) {
      try {
        const manifest=JSON.parse(fs.readFileSync(resolveSidecar(first,'run_manifest.json'),'utf8'));
        const {createHash}=await import('node:crypto');
        const hash=createHash('md5').update(fs.readFileSync(current)).digest('hex');
        if(manifest.template_origin==='study' || hash!==manifest.inputs?.template?.md5) selected=current;
      } catch { selected=current; }
    }
    console.log(selected); process.exit(0);
  }
  if(!['publish','stage'].includes(mode) || !first || !second) process.exit(2);
  if(mode==='publish') {
    const mirror=first,dir=second;
    // Newly published sidecars always live in output; old mirror layouts remain collectable.
    for(const from of [mirror,path.join(mirror,'output')])
      copySet(from,path.join(dir,'output'),name=>['report_evidence.json','report_context.json'].includes(name),dataName);
    const wordOnly=fs.existsSync(path.join(mirror,'.pmx_run_state')) && /^WORD_ONLY=1$/m.test(fs.readFileSync(path.join(mirror,'.pmx_run_state'),'utf8'));
    if(wordOnly) {
      // A prose refresh preserves the analysis source, frozen outputs and their layout.
      const ep=path.join(dir,'output','report_evidence.json');
      if(fs.existsSync(ep)) {
        const evidence=JSON.parse(fs.readFileSync(ep,'utf8'));
        const published=rel=>path.relative(dir,resolveEvidence(dir,rel)).replaceAll('\\','/');
        evidence.source_file=published(evidence.source_file);
        for(const entry of evidence.files || []) entry.file=published(entry.file);
        fs.writeFileSync(ep,JSON.stringify(evidence,null,2)+'\n');
        fs.chmodSync(ep,0o644);
      }
      process.exit(0);
    }
    fs.copyFileSync(path.join(mirror,rmd),path.join(dir,rmd));
    if(fs.existsSync(path.join(mirror,'pmx_config.R')))
      fs.copyFileSync(path.join(mirror,'pmx_config.R'),path.join(dir,'analysis_config.R'));
    for(const from of [mirror,path.join(mirror,'output')]) {
      copySet(from,path.join(dir,'output'),name=>metadata.has(name),dataName);
      copySet(from,path.join(dir,'table','analysis'),analysisTable,dataName);
    }
    const ep=path.join(dir,'output','report_evidence.json');
    if(fs.existsSync(ep)) {
      const evidence=JSON.parse(fs.readFileSync(ep,'utf8'));
      const canonical=rel=>{
        if(typeof rel!=='string' || rel===dataName) return rel;
        const norm=rel.replaceAll('\\','/'),name=path.posix.basename(norm);
        if(!norm.includes('/') || /^output\/[^/]+$/.test(norm)) {
          if(metadata.has(name)) return 'output/'+name;
          if(analysisTable(name)) return 'table/analysis/'+name;
        }
        return /^02_html\/[^/]+$/.test(norm) ? name : norm;
      };
      evidence.source_file=canonical(evidence.source_file);
      for(const entry of evidence.files || []) entry.file=canonical(entry.file);
      fs.writeFileSync(ep,JSON.stringify(evidence,null,2)+'\n');
      fs.chmodSync(ep,0o644);
    }
  } else {
    const dir=first,mirror=second;
    // Keep aliases inside hidden staging so existing flat studies need no migration.
    for(const from of [dir,path.join(dir,'output')])
      for(const target of [mirror,path.join(mirror,'output')])
        copySet(from,target,name=>metadata.has(name) || analysisTable(name));
  }
}
