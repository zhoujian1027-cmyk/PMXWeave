#!/usr/bin/env node
// Deployment paths belong to external runtime configuration, never reusable sources.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const toolkitRoot=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..','..');
const fail=(message,code='PMX_RUNTIME_REQUIRED')=>{throw new Error(code+': '+message);};
const readJson=file=>{try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch(e){fail('cannot read '+file+': '+e.message);}};
const absolute=(value,base)=>path.resolve(base,value);
export function runtimeConfig(required=true) {
  let file=process.env.PMX_RUNTIME_CONFIG;
  if(!file) {
    const pointer=path.join(toolkitRoot,'.pmx-runtime.local.json');
    if(fs.existsSync(pointer)) {
      const value=readJson(pointer).runtime_config;
      if(typeof value!=='string' || !value.trim())fail('local deployment pointer needs runtime_config');
      file=absolute(value,path.dirname(pointer));
    }
  }
  if(!file) {
    if(required)fail('set PMX_RUNTIME_CONFIG or a workspace-local deployment pointer; see analyses_template/tools/runtime_paths.md. Do not search storage trees.');
    return null;
  }
  file=path.resolve(file);
  const config=readJson(file);
  if(!config || Array.isArray(config) || typeof config!=='object')fail('runtime configuration must be an object');
  return {...config,file,base:path.dirname(file)};
}
export function queueRoot({required=true}={}) {
  if(process.env.RSUB_BASE?.trim())return path.resolve(process.env.RSUB_BASE);
  const config=runtimeConfig(false);
  if(config?.queue_root)return absolute(config.queue_root,config.base);
  if(required)fail('R queue_root is not configured; set RSUB_BASE or PMX_RUNTIME_CONFIG. No machine-specific default is used.');
  return '';
}
const beneath=(input,prefix)=>input===prefix || input.startsWith(prefix+path.sep);
function mappings(config) {
  const items=config.path_mappings ?? [];
  if(!Array.isArray(items))fail('path_mappings must be an array');
  return items.map(item=>{
    if(typeof item.client!=='string' || typeof item.worker!=='string')fail('each path mapping needs client and worker strings');
    return {client:absolute(item.client,config.base),worker:absolute(item.worker,config.base)};
  });
}
export function mapPath(mode,input) {
  if(!input)fail('a task path is required','RPATH_USAGE');
  const config=runtimeConfig();
  const value=path.resolve(input);
  const items=mappings(config);
  if(config.execution==='local' && !items.length)return value;
  const from=mode==='container'?'client':'worker',to=mode==='container'?'worker':'client';
  const match=items.filter(item=>beneath(value,item[from])).sort((a,b)=>b[from].length-a[from].length)[0];
  if(!match)fail('task path is outside the configured '+from+' mounts: '+value,'RPATH_OFF_MOUNT');
  return match[to]+value.slice(match[from].length);
}
export function translateText(input) {
  const config=runtimeConfig();
  return mappings(config).sort((a,b)=>b.worker.length-a.worker.length).reduce((text,item)=>text.split(item.worker).join(item.client),input);
}
function main(args) {
  const [mode,input]=args;
  if(mode==='queue'){console.log(queueRoot());return;}
  if(mode==='config'){console.log(runtimeConfig().file);return;}
  if(mode==='value') {
    const config=runtimeConfig(),value=config[input];
    if(typeof value!=='string' || !value.trim())fail('runtime setting '+input+' is not configured');
    console.log(input.endsWith('_root')?absolute(value,config.base):value);return;
  }
  if(mode==='text'){process.stdout.write(translateText(fs.readFileSync(0,'utf8')));return;}
  if(mode==='container' || mode==='host'){console.log(mapPath(mode,input));return;}
  if(mode==='check') {
    mapPath('container',input);
    if(!fs.existsSync(input) || !fs.statSync(input).isDirectory())fail('task directory does not exist: '+input,'RPATH_MISSING');
    console.log('RPATH_OK');return;
  }
  fail('rpath.sh container|host|check <path>; queue|config|value <key>|text','RPATH_USAGE');
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{main(process.argv.slice(2));}catch(e){console.error(e.message);process.exitCode=2;}
}
