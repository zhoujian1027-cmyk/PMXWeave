// Read-only selection check; no R job or study files are created here.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';

export function ncaPreflight(text, args=[]) {
  const fail=s=>{throw new Error('NCA_ENDPOINT_REQUIRED: '+s);};
  text=text.replace(/^\uFEFF/,'');
  const header=text.split(/\r?\n/,1)[0];
  const sep=[',',';','\t'].sort((a,b)=>header.split(b).length-header.split(a).length)[0];
  let rows=[];
  if(!header.includes(sep)) rows=text.trim().split(/\r?\n/).map(s=>s.trim().split(/\s+/));
  else {
    let row=[],field='',quoted=false;
    for(let i=0;i<text.length;i++) {
      const c=text[i];
      if(c==='"') {
        if(quoted && text[i+1]==='"') {field+='"';i++;}
        else quoted=!quoted;
      } else if(!quoted && (c===sep || c==='\n')) {
        row.push(field.trim());field='';
        if(c==='\n') {if(row.some(Boolean)) rows.push(row);row=[];}
      } else field+=c;
    }
    if(quoted) fail('unclosed CSV quote');
    row.push(field.trim());if(row.some(Boolean)) rows.push(row);
  }
  if(rows.length<2) fail('no data observations');
  const names=rows.shift().map(s=>s.replace(/^[@#]/,'').toLowerCase());
  if(new Set(names).size!==names.length) fail('duplicate column names');
  const index=k=>names.indexOf(k), get=(row,k)=>row[index(k)];
  const number=x=>x==null || ['', '.', 'NA'].includes(x.trim()) ? NaN : Number(x);
  const columnArg=args.filter(a=>a.startsWith('--nca-dv-column=')).at(-1);
  const scaleArg=args.filter(a=>a.startsWith('--dv-scale=')).at(-1);
  const column=columnArg===undefined ? 'dv' : columnArg.slice('--nca-dv-column='.length).toLowerCase();
  const scale=scaleArg===undefined ? 'raw' : scaleArg.slice('--dv-scale='.length);
  if(!/^[a-z][a-z0-9_]*$/i.test(column)) fail('declare a nonempty --nca-dv-column=NAME');
  if(index(column)<0) fail('missing selected response column '+column);
  if(!['raw','log'].includes(scale)) fail('invalid selected response scale');
  const flags={};
  for(const a of args) {
    if(a==='--nca-dvid' || a==='--nca-cmt') fail('use --nca-dvid=N or --nca-cmt=N');
    const m=a.match(/^--nca-(dvid|cmt)=(.*)$/);if(m) flags[m[1]]=m[2];
  }
  for(const [k,v] of Object.entries(flags)) {
    if(index(k)<0 || !Number.isFinite(number(v))) fail('invalid PK --nca-'+k+' selection');
  }
  let obs=rows.filter(r=>{
    if(r.length!==names.length) fail('row width differs from header');
    if(index('evid')<0 && number(get(r,'amt'))>0) fail('dose records require EVID');
    return (index('evid')<0 || number(get(r,'evid'))===0) &&
      (index('mdv')<0 || number(get(r,'mdv'))===0) && Number.isFinite(number(get(r,column)));
  });
  for(const [k,v] of Object.entries(flags)) obs=obs.filter(r=>number(get(r,k))===number(v));
  if(!obs.length) fail('selected PK endpoint has no observations');
  const levels=k=>new Set(obs.map(r=>number(get(r,k))).filter(Number.isFinite));
  if(!Object.keys(flags).length && ['dvid','cmt'].some(k=>index(k)>=0 && levels(k).size>1))
    fail('multiple endpoints: select the known PK --nca-dvid=N or --nca-cmt=N');
  if(!('dvid' in flags) && index('dvid')>=0 && levels('dvid').size>1)
    fail('selected CMT contains multiple DVIDs; specify the PK --nca-dvid=N');
  const pair=obs.filter(r=>number(get(r,'dv'))>0 && Number.isFinite(number(get(r,'lndv'))));
  const rawAndLog=pair.length>0 && pair.length===obs.length && pair.every(r=>Math.abs(Math.log(number(get(r,'dv')))-number(get(r,'lndv')))<=1e-6*(1+Math.abs(number(get(r,'lndv')))));
  if(rawAndLog && ((column==='dv' && scale==='log') || (column==='lndv' && scale==='raw')))
    fail('NCA_SCALE_MISMATCH: DV is raw and LNDV=log(DV); use DV/raw or LNDV/log, independently of the fit response');
  if(['lndv','logdv','ln_dv','log_dv'].includes(column) && !args.some(a=>a.startsWith('--dv-scale=')))
    fail('declare --dv-scale=log for the selected transformed column');
  return 'NCA_PREFLIGHT_OK column='+column+' scale='+scale+' PK endpoint selection checked';
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  try {console.log(ncaPreflight(fs.readFileSync(process.argv[2],'utf8'),process.argv.slice(3)));}
  catch(e) {console.error(e.message);process.exitCode=2;}
}
