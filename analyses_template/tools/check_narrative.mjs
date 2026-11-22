#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {resolveResult,resolveEvidence} from "./regression_layout.mjs";
import {checkReportReferences} from './report_references.mjs';
import {fitNarrativePolicy,checkFitNarrative} from './fit_narrative_policy.mjs';

const args = process.argv.slice(2);
const FIX = args.includes("--fix-evidence");
const REQUIRE_SECTIONS = args.includes("--require-discussion-conclusion");
const DIR = args.find((a) => !a.startsWith("-"));
if (!DIR) {
  console.error("usage: check_narrative.mjs <analysis-dir> [--fix-evidence]");
  process.exit(2);
}
const dir = path.resolve(DIR);
const md5 = (p) => crypto.createHash("md5").update(fs.readFileSync(p)).digest("hex");

const narrPath = path.join(dir, "report_narrative.json");
let fitPolicy;
try {
  const evidencePath=resolveEvidence(dir,'output/report_evidence.json');
  const family=fs.existsSync(evidencePath)?JSON.parse(fs.readFileSync(evidencePath,'utf8')).family:null;
  fitPolicy=['ppk','pkpd','tmdd'].includes(family)?fitNarrativePolicy(dir,family):null;
} catch(e) {console.log('NARRATIVE_CHECK_BAD reason=NARRATIVE_POLICY '+e.message);process.exit(2);}
if(fitPolicy?.required===false) {console.log('NARRATIVE_CHECK_OMITTED explicit user opt-out recorded');process.exit(0);}
if (!fs.existsSync(narrPath)) {
  if(fitPolicy?.required) {console.log('NARRATIVE_CHECK_BAD reason=NARRATIVE_REQUIRED missing report_narrative.json');process.exit(2);}
  console.log("NARRATIVE_CHECK_ABSENT no report_narrative.json at " + narrPath + " (optional; generated prose only)");
  process.exit(0);
}

let raw;
try {
  raw = fs.readFileSync(narrPath, "utf8");
} catch (e) {
  console.log("NARRATIVE_CHECK_BAD reason=NARRATIVE_UNREADABLE file=" + narrPath + " detail=" + e.message);
  process.exit(2);
}
let x;
try {
  x = JSON.parse(raw);
} catch (e) {
  console.log("NARRATIVE_CHECK_BAD reason=NARRATIVE_PARSE file=" + narrPath + " detail=" + e.message);
  process.exit(2);
}
if (!x || typeof x !== "object" || Array.isArray(x)) {
  console.log("NARRATIVE_CHECK_BAD reason=NARRATIVE_PARSE file=" + narrPath + " detail=not a JSON object");
  process.exit(2);
}

const rds = resolveResult(dir);
const rdsRel = path.relative(dir,rds);
let expectedRds = null;
if (fs.existsSync(rds)) expectedRds = md5(rds);

// Study-relative only: an absolute path or a ".." component makes the evidence unverifiable inside the
// job, which is the same rule pmx_narrative_gate() enforces.
const bad = (reason, file, extra = "") => {
  console.log("NARRATIVE_CHECK_BAD reason=" + reason + (file ? " file=" + file : "") + extra);
};

let changed = 0;
try {checkReportReferences(dir,x);} catch(e) {
  bad('NARRATIVE_REFERENCE_INVALID',narrPath,' '+e.message);process.exit(2);
}
const ev = x.evidence;
try {if(fitPolicy) checkFitNarrative(x,fitPolicy);} catch(e) {
  bad('NARRATIVE_REQUIRED',narrPath,' '+e.message);process.exit(2);
}
if (!Array.isArray(ev) || !ev.length) {
  bad("NARRATIVE_NO_EVIDENCE", "", " the prose needs at least one actual evidence file+hash");
  process.exit(2);
}
for (const e of ev) {
  if (!e || typeof e.file !== "string" || typeof e.md5 !== "string") {
    bad("NARRATIVE_BAD_EVIDENCE", JSON.stringify(e || null), " every entry needs file and md5");
    process.exit(2);
  }
  const norm = e.file.replace(/\\/g, "/");
  if (/^([/]|[A-Za-z]:)/.test(norm) || norm.split("/").includes("..")) {
    bad("NARRATIVE_BAD_EVIDENCE", e.file, " evidence paths must stay study-relative");
    process.exit(2);
  }
  const p = resolveEvidence(dir, norm);
  if (!fs.existsSync(p) || !fs.statSync(p).isFile()) {
    bad("NARRATIVE_MISSING_EVIDENCE", e.file, " the file does not exist under " + dir);
    process.exit(2);
  }
  const actual = md5(p);
  if (actual !== e.md5) {
    if (!FIX) {
      bad("NARRATIVE_CHANGED_EVIDENCE", e.file, " expected=" + e.md5 + " actual=" + actual);
      process.exit(2);
    }
    e.md5 = actual;
    changed++;
  }
}
if (x.section_results != null) {
  const details=x.section_results;
  if(typeof details!=='object' || Array.isArray(details)) {bad('NARRATIVE_BAD_SECTION_RESULTS','section_results');process.exit(2);}
  for(const [title,value] of Object.entries(details)) {
    const text=Array.isArray(value)?value:typeof value==='string'?[value]:[];
    if(!(/(?:^|[\\/])artifacts[\\/]s2[\\/]final[.]rds$/.test(rds)?/^[56](?:\.\d+)*\.? +[^\r\n]+$/:/^4(?:\.\d+)*\.? +[^\r\n]+$/).test(title) || !text.length ||
       text.some(p=>typeof p!=='string' || !p.trim() || /\[[^\]]+\]|not available|file not found|template slot|traceback|error:/i.test(p))) {
      bad('NARRATIVE_BAD_SECTION_RESULTS',title);process.exit(2);
    }
  }
}
if ((REQUIRE_SECTIONS || fitPolicy?.required) && fitPolicy?.required!==false) {
  for (const name of ['Discussion','Conclusion']) {
    const raw = x.sections?.[name];
    const text = Array.isArray(raw) ? raw : typeof raw === 'string' ? [raw] : [];
    if (!text.length || text.some(p => typeof p !== 'string' || !p.trim() || /\[[^\]]+\]|not available|file not found|template slot|traceback|error:/i.test(p))) {
      bad("NARRATIVE_INCOMPLETE", name, " both sections need supported paragraphs");
      process.exit(2);
    }
  }
}
// source_md5 is a scientific anchor, not a transcription: report, never rewrite.
if (expectedRds !== null && x.source_md5 !== expectedRds) {
  bad("NARRATIVE_STALE", rdsRel, " source_md5=" + x.source_md5 + " actual=" + expectedRds);
  console.log("NARRATIVE_CHECK_NEXT re-read the current result before setting source_md5 (this check never rewrites it)");
  process.exit(2);
}

if (changed) {
  fs.writeFileSync(narrPath, JSON.stringify(x, null, 2) + "\n");
  try {
    fs.chmodSync(narrPath, 0o644);
  } catch {}
  console.log("NARRATIVE_CHECK_FIXED repaired " + changed + " evidence hash(es) in " + narrPath);
}
console.log(
  "NARRATIVE_CHECK_OK source_md5=" + (x.source_md5 || "none") + " evidence=" + ev.length +
  (expectedRds === null ? " rds=absent" : "")
);
process.exit(0);
