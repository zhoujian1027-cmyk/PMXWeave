# NONMEM rules

Use one matching nonmem_template/*.ctl and the sections relevant to the requested
structure/estimator; do not follow explanatory source
links or load mrgsolve/report/queue internals for a CTL-only request.

Use references/model_authoring.md for composition, authorization, the two-example cap,
NOFIX and delivery. Read it once before examples; there is no later review/validation pass.

## NONMEM house style

Record order: $PROBLEM -> $INPUT -> $DATA -> $SUBROUTINES -> [$MODEL] -> $PK -> [$DES] ->
$ERROR -> $THETA -> $OMEGA -> $SIGMA -> [$PRIOR] -> $ESTIMATION -> [$ESTIMATION] ->
$COVARIANCE -> $TABLE. Keep template banners, indentation, names and parameter mappings.

- DATA uses the actual filename/path; INPUT matches its original column order exactly,
  including DROP/SKIP. ID TIME DV AMT EVID CMT DVID MDV ADDL II RATE STUDYID is only a
  suggested layout for newly supplied data, never permission to reorder an existing file.
- Before LOG(), guard a nonpositive argument with IF (X.LE.0) X = 0.0001.
- Multi-line IF...THEN requires ENDIF; single-line IF remains single-line.
  Use dotted comparisons (.EQ., .LE., etc.) and ** for powers.
- Set A_0(n) baselines in PK using MODEL compartment indices.
  For steady-state turnover, estimate R0 and KOUT, set KIN = R0 * KOUT and A_0(n) = R0.
  Match the paired simulator and use the study initial state for non-steady-state data.
- TMDD log endpoints use separate CMT blocks with F.GT.0 on both branches.
  Initialize IPRED = LOG(0.0001) and Y = IPRED. Log LFREE or RTOT only when positive.
  Use KSS for QSS and KD for QE.
- When using native F for concentration observations, set the actual observation scale
  S<n>=central volume (e.g. oral ADVAN4 S2=V2); F defaults to amount when S is omitted.
  General DES may instead define IPRED=A(n)/V explicitly. Keep response-state scales separate.
- Preserve banners: Typical values; Covariate effects when applicable; Individual parameters
  (or PK parameters / PD parameters); MU references only for SAEM.

### Guard and constant literals — plain decimal, never a FORTRAN `D`-exponent

Use decimal notation in CTL source: 0.0001, not 1D-4. The D notation denotes a FORTRAN
double-precision exponent, but is excluded by this toolkit's translation contract.
Write every new literal in decimal from the outset, including copied values and bounds.
The usual log floor is 0.0001; a genuinely required smaller floor is 0.0000000001 rather
than 1D-10. E notation may be legal in C++ but values transferred into CTL use decimals.
Correct a defective reusable template at source when authorized; do not add a per-request
post-generation scan or rewrite cycle. This is a numeric-format rule, not an extra job.

### DV scale — log-additive error needs a log DV (a DATA change, not an $ERROR tweak)

A model that measures two or more DVs (two or more observation endpoints, e.g. PK plus a PD
response) is authored with a log-transformed DV by default; use the natural scale only when
the user asks for it. Match the simulator scale to the selected DV column.
Y=LOG(IPRED)+EPS(k) requires the actual selected DV column to be log-transformed. This
applies to logAdd/logPD and the PKPD/TMDD/TGI/metabolite/turnover examples; it must not be
paired with raw DV. Raw DV uses the supported proportional-error endpoint unless another
compatible form is requested. Never silently change response scale to match a template.

Only when the user requests a derived log dataset:
1. Write that derived file first, preserving column order and replacing DV with LN(DV).
   Retain the linear value in an additional explicitly named column if both scales are needed.
   Use a distinct study-directory filename such as pk_data_log.csv, or the explicitly requested
   drop-in filename; never overwrite original input on the agent's initiative.
2. Point DATA at that file and INPUT at its actual columns.
3. Do not change ERROR alone. Nonpositive/missing DV cannot be logged; retain the supported
   proportional form and disclose that fallback rather than inventing transformed data.

The R endpoint, nonmem2rx import and paired simulation error must use the same DV scale:
raw concentration with prop(sdRes), or the matching log-DV additive endpoint.

### THETA starting values — `(lower, init)`, NOT `(lower, upper)`

Use one parameter per line. The second number in (lower, initial) or (lower, initial, upper)
is the start. Defaults: TVCL (0,5), TVV/TVVC (0,50), TVKA (0,1), TVLAG (0,1), TVMTT (0,10),
TVR0 (0,10), TVKOUT (0,0.1), TVIMAX (0,1), TVEC50 (0,100), TVGAMMA (0.01,1,10),
TVKON (0,0.05), TVKOFF (0,0.5), TVKDEG (0,0.5), TVRSS (0,5), TVKINT (0,0.5), TVKSS (0,5),
TVW0 (0,0.2), TVKG (0,0.01), TVKD (0,1), TVBASE (0,8). Supplied/verified fitted starts prevail. Set turnover starts from the observed baseline response and recovery rate.

Bounds encode real constraints: lower 0 for nonnegative rates/volumes; 0-1 fractions use
(0,0.5,1); PsN logit parameters use +/-20. Add an upper bound only for a justified domain/
design limit, such as an ALAG restriction supported by sampling design. Do not invent round
upper bounds: (0,7.169), not (0,7.169,50). In particular, a lag upper bound of 1 must not
silently exclude a later observed peak. Two-value entries have an infinite upper bound.
Covariate starts are unbounded unless their sign/domain is explicitly constrained.

### Absorption rate constant — TVKA starts at the template value `1`, never the NCA Bateman estimate

For a fresh model, use (0,1) for TVKA/TVKA1/TVKA2 and other absorption-rate parameters,
regardless of lag/depot count. Exclude KA from NCA-derived initialization: its single-depot
Bateman approximation can seed a slow flip-flop region and fail to separate parallel depots.
Printed Bateman KA is informational only. Preserve supplied or already fitted starts; on
a genuinely fresh structure start at 1, never re-seed a completed fit from NCA.

### Fixed parameters

Use the shared NOFIX contract in references/model_authoring.md. Estimate parameters unless
the human approved the exact name/value; copied template constants are not approval.

### Bioavailability F1 with IIV — keep the THETA on the 0-1 fraction scale

With an ETA on a fraction, keep TVF1 readable on 0-1, initial/bounds (0,0.5,1), and construct
the logit in PK:

    TVF1 = THETA(6)
    LGTF1_TV = LOG(TVF1/(1.0-TVF1))
    LGTF1 = LGTF1_TV + ETA(5)
    F1 = EXP(LGTF1)/(1.0+EXP(LGTF1))
    F2 = 1 - F1

Use actual template indices. A logit initial such as 0.8472978604 or bounds (-3,0,3) must
not be presented as a fraction. Convert an old logit L to p=EXP(L)/(1+EXP(L)), retain 0-1
THETA bounds and add the typical-logit expression. Logit 0 corresponds to fraction 0.5.
For SAEM, MU_5=LOG(TVF1/(1.0-TVF1)), then LGTF1=MU_5+ETA(5); never MU_5=TVF1.
Every other MU reference is LOG(TVx). PsN uses the same TVBIO/TVPHI/PHI/BIO mapping.
A fraction without IIV is simply F1=TVF1 with (0,0.5,1); do not add a logit.

### Estimation blocks

- FOCEI default: plain TV=THETA assignments; no MU referencing. Use
  $ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT and
  $COVARIANCE UNCONDITIONAL PRINT=E.
- SAEM: MU_1=LOG(TVCL), CL=EXP(MU_1+ETA(1)), etc. Use
  $ESTIMATION METHOD=SAEM INTERACTION NBURN=2000 NITER=1000, then
  $ESTIMATION METHOD=IMP EONLY=1 ISAMPLE=1000 NITER=5; comment out COVARIANCE.
- BAYES: justified $PRIOR NWPRI, $THETAP means and $THETAPV covariance (OMEGA priors
  when needed), followed by $ESTIMATION METHOD=BAYES INTERACTION FILE=bayes_output.
  N(mean,variance) is not NONMEM prior-record syntax.

### Solved-system ADVAN ↔ compartment count

Match the solved ADVAN to route/compartment count before drafting; a mismatch is not a
style variation. Oral absorption adds a depot, so 1/2/3-cmt PO has 2/3/4 states.

| ADVAN | System | Compartments |
|---|---|---|
| 1 | 1-cmt IV | CENTRAL |
| 2 TRANS2 | 1-cmt PO | DEPOT, CENTRAL |
| 3 | 2-cmt IV | CENTRAL, PERIPH |
| 4 TRANS4 | 2-cmt PO | DEPOT, CENTRAL, PERIPH |
| 10 | 1-cmt IV Michaelis-Menten | CENTRAL |
| 11 | 3-cmt IV | CENTRAL, PERIPH1, PERIPH2 |
| 12 TRANS4 | 3-cmt PO | DEPOT, CENTRAL, PERIPH1, PERIPH2 |

Default observed central CMT: ADVAN1/3/10/11=1; ADVAN2/4/12=2. Do not use ADVAN11 for
a depot/central-only model. General ADVAN5/6/7/8/9/13 derives state count from MODEL;
preserve the actual template's linear-system/DES representation. Parallel absorption uses
ADVAN13 TOL=9 with explicit depots and requested distribution states.

## Structure selection

Nonlinear TMDD/PKPD/TGI/Emax-metabolite uses ADVAN13/DES. ADVAN5 covers supported linear
transit/first-order formation, not nonlinear formation or a two-compartment metabolite shortcut.
Solved (matrix-exponential) control streams translate to rxode2 `matExp()` systems, which
reject `_` and `.` in compartment names: use rx-safe `$MODEL` names such as
`DEPOT`/`PARENT`/`PERIPH`/`METAB`, not `PARENT_CENTRAL`. A name with an underscore fails the
translation with "compartments in matrix exponential models cannot contain '_' or '.' unless
they start with 'rx'" even though the NONMEM text itself is legal.
The latter needs its own central/peripheral states and transfers. Combined PKPD-turnover/
parent-metabolite systems share one ADVAN13 DES, with distinct PK and PD state roles.
Default OMEGA variance starts are 0.2 and diagonal unless requested otherwise. Preserve
shared amount/time flux, receptor concentration, fraction, baseline and response-scale laws.
Only an explicitly requested fitting/analysis workflow reads the Residual endpoints section
of references/model_contract.md. A request for multi-endpoint CTL code alone never enables that
route: preserve native CMT/DVID selectors and requested DV/error scale using these authoring rules.
