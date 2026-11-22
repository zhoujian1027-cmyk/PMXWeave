#!/usr/bin/env node
// A standalone diagram is not an analysis chain: no study mirror, fits or CSV input.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {toolkitRoot,mapPath,queueRoot} from './runtime_paths.mjs';

const args=process.argv.slice(2);
if(args.length!==3 || !['ppk','pkpd','tmdd','tgi'].includes(args[1])) {
  console.error('usage: node analyses_template/tools/draw_model_structure.mjs <actual.ctl-or.cpp> <ppk|pkpd|tmdd|tgi> <requested.svg>');
  process.exit(2);
}
const [input,family,destination]=args,model=path.resolve(input),output=path.resolve(destination);
if(!/\.(?:ctl|cpp)$/i.test(model) || !/\.svg$/i.test(output))throw new Error('DIAGRAM_INPUT: use a native CTL/CPP and an SVG output filename');
const helper=fs.readFileSync(path.join(toolkitRoot,'word-report','model_diagram.R'));
const native=fs.readFileSync(model);
const templates=Object.fromEntries(['ppk','pkpd','tmdd','tgi'].map(f=>[f,fs.readFileSync(path.join(toolkitRoot,'analyses_template','diagrams',f+'.svg')).toString('base64')]));
const rscript=process.env.RSCRIPT || 'Rscript';
const local=spawnSync(rscript,['--version'],{encoding:'utf8'});
const workerOutput=local.status===0?output:mapPath('container',output);
const quoted=JSON.stringify;
const assets='c('+Object.entries(templates).map(([k,v])=>k+'='+quoted(v)).join(',')+')';
const code=[
  'if(!requireNamespace("jsonlite",quietly=TRUE))stop("DIAGRAM_RUNTIME: jsonlite is required")',
  'source(textConnection(rawToChar(jsonlite::base64_dec('+quoted(helper.toString('base64'))+'))),local=TRUE)',
  'native <- strsplit(rawToChar(jsonlite::base64_dec('+quoted(native.toString('base64'))+')),"\n",fixed=TRUE)[[1]]',
  'family <- '+quoted(family),
  'spec <- pmx_diagram_spec(native,family)',
  'assets <- '+assets,
  'scratch <- tempfile("pmx_diagram_");dir.create(scratch)',
  'tryCatch({',
  'writeBin(jsonlite::base64_dec(assets[[spec$family]]),file.path(scratch,paste0(spec$family,".svg")))',
  'result <- pmx_model_diagram(native,family,scratch,dirname('+quoted(workerOutput)+'),render_png=FALSE,svg_name=basename('+quoted(workerOutput)+'))',
  'cat("DIAGRAM_COMPLETE ",result$svg,"\n",sep="")',
  '},finally=unlink(scratch,recursive=TRUE))'
].join('\n');
if(local.status===0) {
  const run=spawnSync(rscript,['--vanilla','-'],{input:code,encoding:'utf8',maxBuffer:2*1024*1024});
  if(run.stdout)process.stdout.write(run.stdout);
  if(run.stderr)process.stderr.write(run.stderr);
  process.exit(run.status??1);
}
const base=queueRoot(),reqDir=path.join(base,'requests'),resDir=path.join(base,'results');
if(!fs.existsSync(reqDir))throw new Error('DIAGRAM_RUNTIME: the configured R queue is unavailable; do not search other roots');
const sha=crypto.createHash('sha256').update(code).digest('hex'),id='diagram_'+family+'_'+sha.slice(0,16);
const request=path.join(reqDir,id+'.json'),result=path.join(resDir,id+'.json');
if(fs.existsSync(result)) {
  const prior=JSON.parse(fs.readFileSync(result,'utf8'));
  if(prior.status==='ok' && fs.existsSync(output)){console.log('DIAGRAM_ALREADY_COMPLETE '+output);process.exit(0);}
  throw new Error('DIAGRAM_PREVIOUS_RESULT: '+id+'; inspect its named result once, do not resubmit unchanged');
}
if(!fs.existsSync(request) && !fs.existsSync(path.join(base,'status',id+'.json'))) {
  const temporary=path.join(reqDir,'.'+id+'.'+process.pid+'.tmp');
  try {
    fs.writeFileSync(temporary,JSON.stringify({id,sha:sha.slice(0,16),created:new Date().toISOString(),src:model,cwd:path.dirname(output),code,purpose:'standalone_model_structure'},null,2),{flag:'wx',mode:0o666});
    fs.chmodSync(temporary,0o666);
    try{fs.linkSync(temporary,request);}catch(e){if(e.code!=='EEXIST')throw e;}
  } finally {if(fs.existsSync(temporary))fs.unlinkSync(temporary);}
}
console.log('RSUB_JOB '+id);
console.log('DIAGRAM_PENDING output='+output);
console.log('DIAGRAM_FOLLOW node '+JSON.stringify(path.join(toolkitRoot,'analyses_template','tools','r-submit.mjs'))+' --attach '+id+' --follow --summary');
