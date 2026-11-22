// Client-side screening identity. The R worker writes this record without Node.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const [mode,dirArg,dataArg,toolkitArg,modelsArg='',capArg='6',state]=process.argv.slice(2);
const hash=text=>crypto.createHash('md5').update(text).digest('hex');
const md5=p=>hash(fs.readFileSync(p));
const legacyLadder='3c44f2634b0ba684987b7671f8b84062';
const legacyContract='280629d25afb8ff784e60423971c9f24',legacyFilters='028e3301962ab390bcde7c99d493de73';
try {
  const dir=fs.realpathSync(dirArg);
  let toolkit=fs.realpathSync(toolkitArg);
  if(path.basename(toolkit)==='tools') toolkit=path.resolve(toolkit,'..','..');
  if(!fs.existsSync(path.join(toolkit,'INDEX.md')) || !fs.existsSync(path.join(toolkit,'word-report','stages','run_stages.R')))
    throw Error('LADDER_TOOLKIT_LAYOUT: pass the complete workspace root; do not assemble .toolkit copies');
  const screen=path.basename(dir)==='01_screen'?dir:fs.existsSync(path.join(dir,'01_screen'))?path.join(dir,'01_screen'):dir;
  const models=modelsArg.trim()?modelsArg.split(/[,\s]+/).filter(Boolean):fs.readdirSync(screen)
    .filter(n=>n.endsWith('.ctl')&&!/^(base_model|final_model|recommended_base|ppk_model|pkpd_model|tmdd_model)\.ctl$/.test(n)).sort().slice(0,Math.max(1,Number(capArg)||6));
  const ladder=fs.readFileSync(path.join(toolkit,'analyses_template','tools','fit_ladder.R'),'utf8').replace(/\r\n/g,'\n');
  const contract=fs.readFileSync(path.join(toolkit,'analyses_template','tools','model_contract.R'),'utf8').replace(/\r\n/g,'\n');
  const version=ladder.match(/^LADDER_VER\s*<-\s*([0-9]+)L?/m);
  if(!version) throw Error('missing fitting contract version');
  const exportStart=contract.indexOf('pmx_ctl_number <- function'),exportEnd=contract.indexOf('pmx_configure_model <- function');
  if(exportStart<0 || exportEnd<=exportStart) throw Error('cannot identify export-only source region');
  const controls=ladder.split('\n').filter(l=>/^\s*(CTL|RX)\s*<-/.test(l))
    .map(l=>l.replace(/,\s*cores\s*=\s*[0-9]+L?/g,'').trim());
  const inputs={data:md5(dataArg),configuration:{family:process.env.PMX_FAMILY||'ppk',cmt:process.env.PMX_CMT_OBS||'auto',endpoint:process.env.PMX_ENDPOINT||'',selector:process.env.PMX_DVID||'',residual:process.env.PMX_RESID_INIT||'',fixed:process.env.PMX_FIXED_APPROVED||''},
    models:models.map(m=>[path.basename(m),md5(path.isAbsolute(m)?m:path.join(screen,m))]).sort((a,b)=>a[0].localeCompare(b[0])),
    runtime:{version:Number(version[1]),controls,contract:hash(contract.slice(0,exportStart)+contract.slice(exportEnd)),filters:md5(path.join(toolkit,'analyses_template','tools','data_filters.R')),settings:md5(path.join(toolkit,'analyses_template','tools','screen_fit_identity.R'))}};
  const key=crypto.createHash('sha256').update(JSON.stringify(inputs)).digest('hex');
  const snapshot={schema:2,key,inputs,state:null,base_md5:null};
  const ledger=path.join(dir,'.pmx','ladder_round.json');
  if(mode==='--prepare') {
    if(process.env.PMX_LADDER_EXPORT_ONLY==='1' && fs.existsSync(ledger)) {
      const old=JSON.parse(fs.readFileSync(ledger));
      if(JSON.stringify([old.inputs?.data,old.inputs?.configuration,old.inputs?.models])!==
         JSON.stringify([inputs.data,inputs.configuration,inputs.models])) throw Error('export input identity changed; preserve completed fits');
      console.log(JSON.stringify(old)); // Retain the producing round ID and terminal history.
    } else console.log(JSON.stringify(snapshot));
  } else if(mode==='--finish') {
    if(!['complete','failed','export_required'].includes(state)) throw Error('invalid terminal state');
    fs.mkdirSync(path.dirname(ledger),{recursive:true});
    snapshot.state=state;snapshot.base_md5=state==='complete'?md5(path.join(dir,'base_model.ctl')):null;
    const tmp=ledger+'.'+process.pid+'.tmp';fs.writeFileSync(tmp,JSON.stringify(snapshot)+'\n',{mode:0o644});fs.renameSync(tmp,ledger);
    console.log('LADDER_RECORDED '+state);
  } else if(mode==='--check') {
    if(!fs.existsSync(ledger)) process.exit(10);
    const old=JSON.parse(fs.readFileSync(ledger));
    if(![1,2].includes(old.schema)) throw Error('invalid ledger; do not clear it to retry');
    let same=old.schema===2 && old.key===key;
    if(old.schema===1) {
      const previous=Object.fromEntries(old.inputs?.runtime||[]);
      same=previous['analyses_template/tools/fit_ladder.R']===legacyLadder && previous['analyses_template/tools/model_contract.R']===legacyContract && previous['analyses_template/tools/data_filters.R']===legacyFilters &&
        JSON.stringify([old.inputs.data,old.inputs.configuration,old.inputs.models])===JSON.stringify([inputs.data,inputs.configuration,inputs.models]);
    }
    const changedModels=JSON.stringify(old.inputs?.models)!==JSON.stringify(inputs.models);
    if(!same && ['complete','export_required'].includes(old.state) && old.inputs?.data===inputs.data && changedModels && process.env.PMX_LADDER_NEW_ROUND!=='1') {
      console.log('LADDER_STOP LADDER_SCREEN_SET_CHANGED previous screening ended; do not append a promoted/refitted candidate. Reuse its selected fit for SCM. --new-round is only for an explicit user-requested new screen.');process.exit(4);
    }
    // A runtime/source-only change cannot silently open another completed screening round.
    const studySame=JSON.stringify([old.inputs?.data,old.inputs?.configuration,old.inputs?.models])===
      JSON.stringify([inputs.data,inputs.configuration,inputs.models]);
    if(!same && studySame && ['complete','export_required'].includes(old.state)) {
      same=true;
      console.log('LADDER_RUNTIME_CHANGED completed round retained; SCM must verify the selected fit identity, never rescreen');
    }
    if(!same && studySame && old.state==='failed') {
      console.log('LADDER_STOP prior round failed; source/runtime changes do not authorize another screen. Explain the recorded blocker.');process.exit(4);
    }
    if(!same && ['complete','export_required'].includes(old.state) && old.inputs?.data===inputs.data &&
       process.env.PMX_LADDER_NEW_ROUND!=='1') {
      console.log('LADDER_STOP LADDER_CONFIGURATION_CHANGED completed screen cannot be repeated without an explicitly requested new round');process.exit(4);
    }
    if(!same) process.exit(10);
    if(old.state==='export_required') {
      console.log('LADDER_EXPORT_REQUIRED completed fits preserved; resume wrapper --export-only, never estimate again');process.exit(11);
    }
    if(old.state==='complete' && fs.existsSync(path.join(dir,'base_model.ctl')) && md5(path.join(dir,'base_model.ctl'))===old.base_md5) {
      console.log('LADDER_PARTIAL already selected base_model.ctl; continue SCM/report without refitting');
    } else {console.log('LADDER_STOP unchanged screening already ended; read 01_screen/ladder_table.csv; no queue job submitted');process.exit(4);}
  } else throw Error('unknown mode');
} catch(e) {console.error('LADDER_GUARD_ERROR '+e.message);process.exit(2);}
