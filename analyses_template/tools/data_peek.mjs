// data_peek.mjs - ONE-SHOT structural probe of a PK/PPK dataset (see data_peek.sh header).
// Prints a fixed, compact report (~40 lines). It exists so that the schema/units/dose-event/
// endpoint check rules require is ONE tool call, not a dozen ad-hoc awk probes.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";

const f = process.argv[2];
if (!f) { console.error("PEEK_FAIL usage: data_peek.mjs <data.csv>"); process.exit(2); }

let txt;
try { txt = readFileSync(f, "utf8"); }
catch (e) { console.error("PEEK_FAIL cannot read " + f + ": " + e.message); process.exit(2); }
txt = txt.replace(/^\uFEFF/, "");

const sep = (() => {
  const head = txt.slice(0, txt.indexOf("\n") < 0 ? txt.length : txt.indexOf("\n"));
  const cand = [",", ";", "\t", "|"];
  let best = ",", n = -1;
  for (const c of cand) { const k = head.split(c).length; if (k > n) { n = k; best = c; } }
  return best;
})();

function split(line) {
  const out = []; let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) { if (ch === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += ch; }
    else if (ch === '"') q = true;
    else if (ch === sep) { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out.map(s => s.trim());
}

const rawLines = txt.split(/\r?\n/).filter(l => l.trim() !== "");
if (rawLines.length < 2) { console.error("PEEK_FAIL no data rows"); process.exit(2); }
const header = split(rawLines[0]);
const hmap = {};
header.forEach((h, i) => hmap[h.toUpperCase()] = i);
const rows = rawLines.slice(1).map(split).filter(r => r.length > 1);

const pick = (...names) => {
  const hit = names.map(n => n.toUpperCase()).find(n => n in hmap);
  return hit === undefined ? undefined : hmap[hit];
};
const ci = {
  id: pick("ID", "USUBJID", "SUBJID", "SUBJECT", "NMID"),
  time: pick("TIME", "TAD", "TAFD"),
  dv: pick("DV", "CONC", "Y", "CP"),
  amt: pick("AMT", "DOSE"),
  evid: pick("EVID", "EVIDENCE"),
  cmt: pick("CMT", "CMTID"),
  mdv: pick("MDV"),
  addl: pick("ADDL"),
  ii: pick("II", "TAU"),
  rate: pick("RATE"),
  occ: pick("OCC", "OCCASION", "CYCLE", "VISIT"),
};
const val = (r, k) => (k != null && k !== undefined && ci[k] != null && r[ci[k]] !== undefined) ? r[ci[k]] : "";
const nm = (k) => (ci[k] === undefined ? "-" : (k === "occ" ? "-" : `${header[ci[k]]}`));
const missing = value => /^(?:|\.|NA|N\/A|NULL)$/i.test(value);
const num = (r, k) => {
  const value = val(r, k);
  return !missing(value) && Number.isFinite(Number(value)) ? Number(value) : null;
};
const range = values => values.reduce(([lo,hi],v) => [Math.min(lo,v),Math.max(hi,v)],[Infinity,-Infinity]).join("..");
const uniqCount = (arr) => { const m = new Map(); for (const x of arr) m.set(x, (m.get(x) || 0) + 1); return m; };
const fmtMap = (m, cap = 12) => {
  const e = [...m.entries()].sort((a, b) => b[1] - a[1]);
  const shown = e.slice(0, cap).map(([k, v]) => `${k}:${v}`);
  return shown.join(" ") + (e.length > cap ? ` (+${e.length - cap} more)` : "");
};

console.log(`PEEK file=${f}`);
console.log(`PEEK rows=${rows.length} columns=${header.length} sep=${sep === "\t" ? "TAB" : sep}`);
console.log(`PEEK columns=${header.join(",")}`);
console.log(`PEEK id=${nm("id")} time=${nm("time")} dv=${nm("dv")} amt=${nm("amt")} evid=${nm("evid")} cmt=${nm("cmt")} mdv=${nm("mdv")} addl=${nm("addl")} ii=${nm("ii")} rate=${nm("rate")} occ=${nm("occ")}`);

const ids = rows.map(r => val(r, "id"));
const idm = uniqCount(ids);
console.log(`PEEK ids=${idm.size}`);

const hasEvid = ci.evid !== undefined;
const inferEvents = !hasEvid && ci.time !== undefined && ci.dv !== undefined && ci.amt !== undefined;
const dosed = rows.filter(r => hasEvid ? num(r, "evid") === 1 : inferEvents && num(r, "amt") > 0);
const obs = rows.filter(r => hasEvid ? num(r, "evid") === 0 : inferEvents && !(num(r, "amt") > 0) && num(r, "dv") !== null);
if (hasEvid) console.log(`PEEK evid_counts=${fmtMap(uniqCount(rows.map(r => val(r, "evid"))))}`);
if (hasEvid || inferEvents) console.log(`PEEK dose_rows=${dosed.length} obs_rows=${obs.length}${inferEvents ? " (inferred from AMT/DV)" : ""}`);
else console.log("PEEK event rows: not applicable without an event column or a time/response/dose layout");
if (dosed.length) {
  const doseCmt = uniqCount(dosed.map(r => val(r, "cmt")));
  const amtVals = [...new Set(dosed.map(r => val(r, "amt")))].filter(Boolean);
  const iiVals = [...new Set(dosed.map(r => val(r, "ii")))].filter(v => v !== "" && v !== ".");
  const addlVals = [...new Set(dosed.map(r => val(r, "addl")))].filter(v => v !== "" && v !== ".");
  const rateVals = [...new Set(dosed.map(r => val(r, "rate")))].filter(v => v !== "" && v !== ".");
  console.log(`PEEK dose_cmt=${fmtMap(doseCmt)} amt=${amtVals.slice(0, 8).join("|")}${amtVals.length > 8 ? "|..." : ""} n_amt=${amtVals.length}`);
  console.log(`PEEK dose_ii=${iiVals.slice(0, 8).join("|") || "-"} addl=${addlVals.slice(0, 8).join("|") || "-"} rate=${rateVals.slice(0, 8).join("|") || "-"}`);
  // parallel depot: several dose records at the SAME (id,time) into DIFFERENT cmt with IDENTICAL amt
  const byKey = new Map();
  for (const r of dosed) {
    const k = val(r, "id") + "@" + val(r, "time");
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(r);
  }
  let par = 0, tot = 0;
  for (const g of byKey.values()) {
    tot++;
    const cmts = new Set(g.map(r => val(r, "cmt")));
    const amts = new Set(g.map(r => val(r, "amt")));
    if (g.length > 1 && cmts.size > 1 && amts.size === 1) par++;
  }
  if (tot) console.log(`PEEK parallel_depot_same_amt=${par}/${tot} dose instants${par ? "  (dose is SPLIT across depots - sum of records would double it)" : ""}`);
}
if (obs.length) {
  const cmtO = uniqCount(obs.map(r => val(r, "cmt")));
  const dv = obs.map(r => num(r, "dv")).filter(v => v !== null);
  const tt = rows.map(r => num(r, "time")).filter(v => v !== null);
  console.log(`PEEK obs_cmt=${fmtMap(cmtO)}`);
  console.log(`PEEK time_range=${tt.length ? range(tt) : "NA"}  dv_range=${dv.length ? range(dv) : "NA"}  dv_nonfinite_or_missing=${obs.length - dv.length}`);
  const occVals = [...new Set(rows.map(r => val(r, "occ")).filter(v => v !== "" && v !== "."))];
  if (occVals.length) console.log(`PEEK occasions=${occVals.slice(0, 8).join("|")}${occVals.length > 8 ? "|..." : ""}`);
}

const perId = new Map();
for (const r of obs) {
  const k = val(r, "id");
  perId.set(k, (perId.get(k) || 0) + 1);
}
const doseIds = new Set(dosed.map(r => val(r, "id")));
const obsIds = new Set(obs.map(r => val(r, "id")));
const gaps = [...obsIds].filter(x => !doseIds.has(x));
const counts = [...perId.values()].sort((a, b) => a - b);
const ev = [...perId.values()].filter(n => n >= 2).length;
if (hasEvid || inferEvents) console.log(`PEEK ids_with_dose=${doseIds.size} ids_with_obs=${obsIds.size} ids_with_obs_but_no_dose=${gaps.length}${gaps.length ? " (" + gaps.slice(0, 6).join(",") + ")" : ""}`);
if (counts.length) {
  const med = counts[Math.floor(counts.length / 2)];
  console.log(`PEEK obs_per_id min=${counts[0]} median=${med} max=${counts[counts.length - 1]} ids_ge2_obs=${ev}/${obsIds.size}`);
}

// Optional factual profile for agent intake; numeric cardinality never assigns a clinical role.
if (process.argv.includes("--covariates")) {
  const fingerprints = new Map();
  for (let j = 0; j < header.length; j++) {
    const values = rows.map(r => r[j] ?? "");
    const present = values.filter(v => !/^(?:|\.|NA|N\/A|NULL)$/i.test(v));
    const unique = [...new Set(present)];
    const numbers = present.map(Number).filter(Number.isFinite);
    const bySubject = new Map();
    if (ci.id !== undefined) for (let i = 0; i < rows.length; i++) {
      if (/^(?:|\.|NA|N\/A|NULL)$/i.test(values[i])) continue;
      const id = rows[i][ci.id];
      if (!id) continue;
      if (!bySubject.has(id)) bySubject.set(id, new Set());
      bySubject.get(id).add(values[i]);
    }
    const changing = [...bySubject.values()].filter(v => v.size > 1).length;
    const digest = createHash("sha256").update(JSON.stringify(values)).digest("hex");
    const duplicate = fingerprints.get(digest);
    if (!duplicate) fingerprints.set(digest, header[j]);
    const range = numbers.length ? numbers.reduce(([lo,hi],v) => [Math.min(lo,v),Math.max(hi,v)],[Infinity,-Infinity]).join("..") : "NA";
    console.log(`PEEK_COV field=${JSON.stringify(header[j])} missing=${values.length-present.length} unique=${unique.length} numeric=${numbers.length}/${present.length} range=${range} changing_subjects=${ci.id===undefined ? "unknown" : changing} exact_duplicate_of=${duplicate ? JSON.stringify(duplicate) : "-"}${unique.length<=8 ? " levels="+JSON.stringify(unique) : ""}`);
  }
}

// one complete subject, so the dose/observation record layout is visible once
const sample = ids[0];
const srows = rows.filter(r => val(r, "id") === sample);
console.log(`PEEK sample_id=${sample} records=${srows.length} (full record layout):`);
for (const r of srows.slice(0, 14)) console.log(`PEEK   ${r.join(sep === "\t" ? " " : sep)}`);
if (srows.length > 14) console.log(`PEEK   ... +${srows.length - 14} more rows for id ${sample}`);

console.log("PEEK_STOP structural/data profile complete; interpret units/baseline/coding from supplied metadata. Reuse this profile, not subject-by-subject probes. Follow the requested report stage; a supplied base/direct SCM skips NCA. No covariate role is inferred by this probe.");
