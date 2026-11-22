#!/bin/sh
set -u
SELF=$(cd "$(dirname "$0")" && pwd)
WSF=${PMX_WS:-$(node "$SELF/runtime_paths.mjs" value workspace_root)}
[ -n "$WSF" ] || exit 2
mkdir -p "$WSF/.pmx_nca_selftest" 2>/dev/null || { echo "SELFTEST_FAIL cannot create the selftest root $WSF/.pmx_nca_selftest" >&2; exit 1; }
chmod 755 "$WSF/.pmx_nca_selftest" 2>/dev/null || true
TMP=$(mktemp -d "$WSF/.pmx_nca_selftest/run_XXXXXX") || { echo "SELFTEST_FAIL cannot create fixture dir" >&2; exit 1; }
chmod 755 "$TMP"   # the queue worker runs in the container as another user and must traverse it
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
FAIL=""

cat > "$TMP/fixA.csv" <<'CSV'
ID,TIME,DV,AMT,EVID,CMT,DOSE
101,0,.,100,1,1,100 mg
101,0,.,100,1,2,100 mg
101,0.5,2.2,0,0,3,.
101,1,2.5,0,0,3,.
101,2,2.1,0,0,3,.
101,4,1.8,0,0,3,.
101,6,2.6,0,0,3,.
101,8,1.6,0,0,3,.
101,12,3.5,0,0,3,.
101,24,0.0062,0,0,3,.
101,48,1e-6,0,0,3,.
CSV

cat > "$TMP/fixB.csv" <<'CSV'
ID,TIME,DV,AMT,EVID,CMT,DOSE
201,0,.,100,1,1,100 mg
201,0,.,100,1,2,100 mg
201,0.5,4.0,0,0,3,.
201,1,5.0,0,0,3,.
201,2,4.5242,0,0,3,.
201,4,3.7041,0,0,3,.
201,6,3.0327,0,0,3,.
201,8,2.4826,0,0,3,.
201,12,1.6642,0,0,3,.
201,24,0.5011,0,0,3,.
201,48,0.0455,0,0,3,.
202,0,.,100,1,1,100 mg
202,0,.,100,1,2,100 mg
202,0.5,4.0,0,0,3,.
202,1,5.0,0,0,3,.
202,2,4.5242,0,0,3,.
202,4,3.7041,0,0,3,.
202,6,3.0327,0,0,3,.
202,8,2.4826,0,0,3,.
202,12,1.6642,0,0,3,.
202,20,0.7483,0,0,3,.
202,23,0.5538,0,0,3,.
202,24,.,100,1,1,100 mg
202,24,.,100,1,2,100 mg
202,24.5,4.0,0,0,3,.
202,25,5.0,0,0,3,.
202,26,4.5242,0,0,3,.
202,28,3.7041,0,0,3,.
202,30,3.0327,0,0,3,.
202,32,2.4826,0,0,3,.
202,36,1.6642,0,0,3,.
202,48,0.5011,0,0,3,.
203,0,.,100,1,1,100 mg
203,0,.,100,1,2,100 mg
203,0.5,4.0,0,0,3,.
203,1,5.0,0,0,3,.
203,2,4.5242,0,0,3,.
203,12,1.6642,0,0,3,.
CSV

run() {   # run <fixture> <outdir> <logfile> <extra flags...>
  fixt=$1; out=$2; log=$3; shift 3
  mkdir -p "$out"
  PMX_NCA_OUT="$out" sh "$SELF/nca_initials.sh" "$fixt" --sync "$@" > "$log" 2>&1
}
ann()  { # column <name> [subject]: R's write.csv QUOTES the header and character cells, so strip '"'
         # before matching - without this every ann() lookup returns nothing and the test goes red
         # for reasons that have nothing to do with the NCA policy it pins.
         awk -F, -v want="$2" -v sid="${3:-*}" '
           NR==1{for(i=1;i<=NF;i++){h=$i; gsub(/"/,"",h); if(h==want) c=i} next}
           c && (sid=="*" || $1==sid){v=$c; gsub(/"/,"",v); print v}' "$1"; }
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAIL="$FAIL $1"; }

# --- fixture A: late Tmax, one terminal point, assay-floor 48 h sample -------------------------
run "$TMP/fixA.csv" "$TMP/out_a" "$TMP/a.log" --route=oral --depots=2
printf 'fixture A (Tmax 12 h, 48 h below Cmax/1e4, one terminal point):\n'
grep -qE '^NCA_SPARSE' "$TMP/a.log" && ok "NCA_SPARSE reported" || bad "expected NCA_SPARSE"
if grep -q 'INCOMPLETE_TERMINAL_OR_EARLY_SAMPLES' "$TMP/out_a/nca_initials.csv" "$TMP/out_a/nca_initials.txt" 2>/dev/null
then bad "old uninformative status still emitted"; else ok "old status gone"; fi
grep -q 'LAMBDAZ_LT3_TERMINAL_POINTS' "$TMP/out_a/nca_initials.csv" && ok "cause named (LAMBDAZ_LT3_TERMINAL_POINTS)" || bad "cause not named"
grep -q 'BLQ_EXCLUDED_FROM_LAMBDAZ' "$TMP/out_a/nca_initials.csv" && ok "assay-floor point excluded and counted" || bad "BLQ point not excluded"
grep -q 'PARALLEL_DEPOT_DOSE_NOT_SUMMED' "$TMP/out_a/nca_initials.csv" && ok "dual-depot split dose flagged" || bad "dual-depot split dose not flagged"
[ "$(ann "$TMP/out_a/nca_initials.csv" n_term)" = "1" ] && ok "n_term published (1)" || bad "n_term not published as 1"
awk -F, -v want="auc_ll" 'NR==1{for(i=1;i<=NF;i++){h=$i; gsub(/"/,"",h); if(h==want) c=i} next} c+0>0 {found=1; exit} END{exit !found}' "$TMP/out_a/nca_initials.csv" \
  && ok "descriptive auc_ll still published" || bad "descriptive values missing"
grep -q '^\$THETA' "$TMP/out_a/nca_initials.txt" && bad "emitted \$THETA without a terminal rate" || ok "no \$THETA block"
grep -q 'no profile produced CL/V' "$TMP/out_a/nca_initials.txt" && ok "text states why there is no CL/V" || bad "no explanation for the empty screen"
grep -q 'INITIALS' "$TMP/out_a/nca_initials.txt" && bad "empty screen still printed an INITIALS digest" || ok "no INITIALS digest without CL/V"

# --- fixture B: early Tmax, clean tail, full grid + 2 occasions + 2-point profile ---------------
run "$TMP/fixB.csv" "$TMP/out_b" "$TMP/b.log" --route=oral --depots=2
printf 'fixture B (Tmax 1 h, monoexponential tail, 201 full grid / 202 two occasions / 203 2-point):\n'
grep -qE '^NCA_OK' "$TMP/b.log" && ok "NCA_OK reported" || bad "expected NCA_OK"
grep -q 'REGIMEN_REQUIRES_STUDY_NCA' "$TMP/out_b/nca_initials.csv" && bad "multi-occasion subject flagged ambiguous again" || ok "multi-occasion subject evaluated, not vetoed"
[ "$(ann "$TMP/out_b/nca_initials.csv" dose_amt | sort -u | tr -d '\n')" = "100" ] && ok "nominal dose taken once (100)" || bad "dose_amt not 100 (200 = double count)"
N=$(ann "$TMP/out_b/nca_initials.csv" cl_f | grep -c '[0-9]')
[ "$N" = "3" ] && ok "CL/V published for all 3 profiles" || bad "CL/V finite for $N rows, expected 3"
# one row per subject, taken on the first dose occasion (202's second occasion is not a profile)
[ "$(ann "$TMP/out_b/nca_initials.csv" occ_end 202)" = "24" ] && ok "profile is the first occasion (202 occ_end=24)" || bad "occasion semantics drifted"
for sid in 201 202; do
  for v in $(ann "$TMP/out_b/nca_initials.csv" cl_f "$sid"); do
    awk -v v="$v" -v s="$sid" 'BEGIN{if(v+0>1.5 && v+0<2.5) printf "  ok   subject %s cl_f=%s within 1.5-2.5\n",s,v; else {printf "  FAIL subject %s cl_f=%s outside 1.5-2.5 (double-count gives ~4)\n",s,v; exit 1}}' || FAIL="$FAIL cl_f-range-$sid"
  done
done
Q=$(ann "$TMP/out_b/nca_initials.csv" quality 203)
[ "$Q" = "approx" ] && ok "2-point profile labelled quality=approx" || bad "203 quality=$Q, expected approx"
grep -q 'EXTRAPOLATION_GT_30_PERCENT' "$TMP/out_b/nca_initials.csv" && ok ">30% extrapolation labelled, not vetoed" || bad "extrapolation not labelled"
grep -q 'EXTRAPOLATION_GT_60_PERCENT' "$TMP/out_b/nca_initials.csv" && bad "203 frac_extrap is ~0.32, GT_60 must not fire" || ok "no spurious GT_60 label"
[ "$(ann "$TMP/out_b/nca_initials.csv" quality | grep -c '^good$')" != "0" ] && ok "good tier present" || bad "no profile reached the good tier"
grep -q 'CL/F \[min - max\]' "$TMP/out_b/nca_initials.txt" && ok "header publishes the CL/F range" || bad "no CL/F range published"
CL=$(grep -E '^ *\(0, .*; TVCL' "$TMP/out_b/nca_initials.txt" | head -1 | sed 's/.*(0, *\([0-9.eE+-]*\)).*/\1/')
awk -v v="$CL" 'BEGIN{if(v+0>1.5 && v+0<2.5) printf "  ok   \$THETA TVCL/F=%s within 1.5-2.5\n",v; else {printf "  FAIL \$THETA TVCL/F=%s outside 1.5-2.5\n",v; exit 1}}' || FAIL="$FAIL theta-cl"
grep -qE '^; INITIALS TVCL/F=[0-9]' "$TMP/out_b/nca_initials.txt" && ok "one-line INITIALS digest published first" || bad "no INITIALS digest line"
grep -qE 'INITIALS TVCL/F=[0-9]' "$TMP/b.log" && ok "NCA_OK digest line carries the initials" || bad "NCA_OK line lacks INITIALS"

printf '\n'
if [ -n "$FAIL" ]; then echo "SELFTEST_FAIL$FAIL"; exit 1; fi
echo "SELFTEST_OK 2 fixtures: A=sparse-with-named-cause B=all-profiles-published"
