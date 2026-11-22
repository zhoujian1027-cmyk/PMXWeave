#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {queueRoot,runtimeConfig,mapPath} from './runtime_paths.mjs';
try {
  const config=runtimeConfig(),queue=queueRoot();
  const health=JSON.parse(fs.readFileSync(path.join(queue,'scripts','r-run-state.json'),'utf8'));
  if(!health.container_running || Date.now()/1000-health.last_check_epoch>30)
    throw new Error('R worker is unavailable or its heartbeat is stale; start the configured worker');
  if(process.argv[2]) {
    const study=fs.realpathSync(process.argv[2]);
    if(!fs.statSync(study).isDirectory())throw new Error('study path is not a directory');
    console.log('PMX_STUDY client='+study+' worker='+mapPath('container',study));
  }
  console.log('PMX_RUNTIME_OK config='+config.file+' queue='+queue+' worker_cap_s='+health.worker_timeout_s);
} catch(error) {
  console.error(error.message+'\nSee analyses_template/tools/runtime_paths.md. Do not search other directories or edit study data to repair deployment.');
  process.exitCode=2;
}
