#!/usr/bin/env node
// One idle host controller advances verified fit-family windows, never failed fits.
import fs from 'node:fs';
import {queueRoot} from './runtime_paths.mjs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {queueHandoff,handoffHasProgress} from './queue_outcome.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
let child=null,interrupted=false;
function run(args) {
  return new Promise((resolve,reject)=>{
    child=spawn('sh',[path.join(here,'run_analysis.sh'),...args],{stdio:['ignore','pipe','pipe'],detached:process.platform!=='win32'});
    let text='';
    for(const stream of [child.stdout,child.stderr]) stream.on('data',chunk=>{
      text=(text+chunk.toString()).slice(-2000000);
    });
    child.once('error',reject);
    child.once('close',(code,signal)=>{
      child=null;
      // Queue logs retain full evidence; return only transitions and actionable errors to the model.
      const lines=text.split(/\r?\n/);
      const key=/^(?:CHAIN_(?:JOB |JOB_RUNNING|DONE|COVARIANCE_DONE|CHECKPOINT|DEFER|NARRATIVE_REQUIRED|SIMULATOR_REQUIRED|NEXT|NO_PROGRESS|FAIL|SUBMIT_FAIL|PROGRESS_ERROR|PARTIAL)|NCA_(?:OK|NOT_AVAILABLE)|RSUB_(?:JOB |RESULT_MISSING|NO_SUCH_JOB|WATCH_BLOCKED)|STAGES_(?:CHECKPOINT|DEFER)|NARRATIVE_REQUIRED|S2_(?:SIMULATOR_REQUIRED|TRANSLATION_REASON|MODEL_CONTRACT_UNSUPPORTED)|QUEUE_GUARD_(?:BUSY|BACKOFF))\b|^\s*\d+ lines,.*log /;
      const summary=lines.filter(line=>key.test(line)).slice(-18).join('\n');
      if(summary)console.log(summary);
      if(code!==0 && code!==3 && !/^NARRATIVE_REQUIRED/m.test(text))console.error(lines.slice(-20).join('\n').slice(-3000));
      resolve({code,signal,text});
    });
  });
}

// Exported driver allows isolated handoff tests without a queue or R installation.
export async function followChain(args,{execute=run,handoff,emit=console.log}={}) {
  const seen=new Set();let first=true;
  for(;;) {
    if(interrupted)return 130;
    const submitted=await execute(args);
    if(interrupted || submitted.signal)return 130;
    const receipt=submitted.text.match(/^CHAIN_JOB ([A-Za-z0-9_.~+-]+)\s*$/m);
    // A live id supplied by the wrapper is authoritative too; never increment job suffixes.
    const live=first && submitted.code===3 ? submitted.text.match(/^(?:CHAIN_JOB_RUNNING|QUEUE_GUARD_BUSY) id=([A-Za-z0-9_.~+-]+)\b/m):null;
    const id=receipt?.[1] || live?.[1];first=false;
    if(!id) {
      emit('CHAIN_FOLLOW_STOP no submitted/live queue receipt; preserve the wrapper verdict');
      return submitted.code || 2;
    }
    if(submitted.code!==0 && !live) {
      emit(`CHAIN_FOLLOW_STOP id=${id}; submission/ledger error, follow the named recovery instruction`);
      return submitted.code;
    }
    if(seen.has(id)) {emit(`CHAIN_FOLLOW_STOP repeated terminal id=${id}; no automatic replay`);return 4;}
    seen.add(id);emit(`CHAIN_FOLLOW_WAIT id=${id}; controller remains online; no model polling required`);
    const collected=await execute(['--attach',id]);
    if(interrupted || collected.signal)return 130;
    if(collected.code===0)return 0;
    if(/^CHAIN_SIMULATOR_REQUIRED /m.test(collected.text)) {
      emit(`CHAIN_FOLLOW_AUTHOR id=${id} next=s2; prepare only the named paired simulators from the frozen CTL now, then resume; no R retry or new user permission is needed within the authorized report task`);
      return 2;
    }
    // Exit 3 is never enough: require a published normal checkpoint/DEFER and new durable work.
    const next=collected.code===3 ? handoff(id):null;
    if(!next) {
      emit(`CHAIN_FOLLOW_STOP id=${id}; narrative/action required or real terminal failure; no resubmission`);
      return collected.code || 1;
    }
    emit(`CHAIN_FOLLOW_ADVANCE id=${id} next=${next.next} progress=verified; reuse completed stages and fits`);
    // The unchanged wrapper rechecks its progress/backoff guards before every new submission.
  }
}

async function main() {
  const args=process.argv.slice(2);
  if(!args[0] || args[0].startsWith('--') || args.slice(1).some(a=>a==='--sync' || a==='--screen' || a.startsWith('--models=') || a==='--follow-chain'))
    throw new Error('usage: run_analysis.sh --follow-chain <study> --family=ppk|pkpd|tmdd --data=<file>; supply/select the base first; do not combine --sync or --screen/--models');
  const dir=fs.realpathSync(args[0]);
  const onSignal=signal=>{
    interrupted=true;console.error(`CHAIN_FOLLOW_INTERRUPTED ${signal}; queued R work remains intact; resume the same controller command`);
    if(child)try{process.kill(process.platform==='win32'?child.pid:-child.pid,signal);}catch{}
  };
  process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
  try {
    const base=queueRoot();
    return await followChain(args,{handoff:id=>{
      let result;try{result=JSON.parse(fs.readFileSync(path.join(base,'results',id+'.json'),'utf8'));}catch{return null;}
      const next=queueHandoff(result);
      return next && handoffHasProgress(dir,id) ? next:null;
    }});
  } finally {process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);}
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{process.exitCode=await main();}catch(e){console.error(e.message);process.exitCode=2;}
}
