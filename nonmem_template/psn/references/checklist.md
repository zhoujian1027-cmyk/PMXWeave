# Conversion checklist — `.ctl` → scm / bootstrap ready

Apply **A**, then **S** (if scm in scope), then **B** (if bootstrap in scope).
Every rule is either *edit the control stream* (E), *emit in the .scm file* (C), or
*flag to the user, cannot be fixed in the .ctl* (F).

## A — both tools

| # | Rule |
|---|---|
| A1 | E — Remove `PRINT=` / `PRINT=N` from `$ESTIMATION` (output size only; no behaviour change). |
| A2 | E — Keep every estimate, bound, method, compartment and line of PK/PD code identical. This is a packaging conversion, not a re-specification. |
| A3 | F — `$DATA` must resolve from the PsN run directory; data-file headers are ignored, column names come from `$INPUT`. |
| A4 | F — Do not add `$MSFI` without `$THETA`/`$OMEGA`/`$SIGMA` records; tools read the control stream copy in the `.lst` to see which parameters are estimated. |

## S — scm (covariate screening)

| # | Rule |
|---|---|
| S1 | E — Every tested parameter needs a `TVpar` intermediate **in `$PK`/`$PRED`**: `TVCL = THETA(1)` then `CL = TVCL*EXP(ETA(1))`. Rewrite `CL = THETA(1)*EXP(ETA(1))`; update all uses. `TVpar` in `$ERROR` does not work, and scm stops if `TVpar` is absent. |
| S2 | E — The input model must be **clean**: no covariate relation pre-coded. Move existing effects out of `$PK` (restore `TVpar`-only form) and declare them in `[included_relations]` instead. Leaving them in place conflicts with scm's own add/remove. |
| S3 | E — Each tested covariate must be an `$INPUT` column. If a covariate is used anywhere in PK/PRED code or in `IGNORE/ACCEPT`, add it to `do_not_drop=` or candidate models drop the column. |
| S4 | F — Missing covariates must be a **numeric** token in the data (`.` becomes 0 once NONMEM reads it) and the same value goes on the command line as `-missing_data_token=`. Rewriting the data file is the user's job. |
| S5 | E — With `$PRIOR NWPRI`, priors must live in prior-specific records (`$THETAP` …). Priors stored as the **trailing** `$THETA`s break: scm appends its new THETAs at the end. |
| S6 | E — Rename columns/parameters so that (a) no covariate name is the prefix of another (`AP` + `APGR` breaks, `APX` + `APGR` is fine), (b) `PARAM`+`COVariate` concatenation never contains the string `PAR` (`SLP`+`ARM` → corrupted code). Update `$INPUT`, `$DATA`, code, and the config lists together. |
| S7 | E — Only for `linearize=1`: the ETA on a tested parameter must be unique to it, and the IIV must be in a recognized form (`TVPAR*EXP(ETA)`, `EXP(MU_i+ETA)`, `TVPAR+TVPAR*ETA`, `TVPAR*(1+ETA)`, `TVPAR+ETA`). `PAR=TVPAR+ETA` is additive unless the parameter is listed in `logit=`. Also: input model must not use `METHOD=ZERO`. |
| S8 | E — Logit parameter, full pattern (needed if the user wants a bounded fraction tested): `TVBIO=THETA(1)` / `TVPHI=LOG(TVBIO/(1-TVBIO))` / `PHI=TVPHI+ETA(1)` / `BIO=EXP(PHI)/(1+EXP(PHI))`; then test **PHI** and list it in `logit=`. On a logit parameter the function is added to TV and equals 0 (not 1) at THETA=0; linear/hockey-stick get bounds ±20; power and exponential are inappropriate there. |
| S9 | E — If the model defines constants that must precede scm-generated code, or the covariate code must start at a specific line, add the exact line `;;;SCM-ANCHOR` (no spaces, uppercase, own line) after them. |
| S10 | C — Classify covariates: continuous vs categorical → `continuous_covariates=` / `categorical_covariates=` (comma lists, `$INPUT` names) and the matching `[valid_states]` line. Built-in states: 1 none, 2 linear, 3 hockey-stick, 4 exponential, 5 power. Defaults tried: continuous 1,2,3 / categorical 1,2. |
| S11 | C — `[test_relations]` lists the parameters (implicitly) and which covariates attach to each; keep it consistent with S1/S6. |
| S12 | C — `[included_relations]` uses `PARAM=COV-STATE[,COV-STATE]` (e.g. `CL=WGT-2,AGE-3`). Required if `search_direction=backward`. |
| S13 | C — `[valid_states]` is **global**, so a state you list must exist for every pair that can reach it: use custom states only with `*` wildcard definitions in `[code]`, or narrow `[test_relations]`. |
| S14 | C — `[code]` (header once; never redefine state 1): LHS `PARAM:COV-STATE`, `*` wildcards allowed → use `PAR`/`COV` inside. RHS is free NONMEM; substitute `median`/`mean`/`maximum`/`minimum` (exact lowercase) and renumber THETAs from 1 per parameterization. Multi-line: `\` on every line but the last. Missing-data handling is **not** automatic here. Shortcut reuse: `*:WGT-4=power` (`none linear hockey-stick exponential power`). |
| S15 | C — `[inits]`/`[lower_bounds]`/`[upper_bounds]`: one value per THETA (continuous state 2 = 1, state 3 = 2, states 4/5 = 1; categorical state 2 = one per non-reference category). Default bounds keep a multiplicative function positive — override for parameters allowed negative (`CL:*-2=-200`) and for logits (±20). |
| S16 | C — `gof=ofv` only with `[ofv_forward]`/`[ofv_backward]` covering **every** dof the relations can add: linear/exponential/power = 1, hockey-stick = 2, categorical = categories − 1. p=0.05: 3.84 5.99 7.81 9.49 11.07 12.59 14.07 15.51 16.92 18.31 · p=0.01: 6.63 9.21 11.34 13.28 15.09 16.81 18.48 20.09 21.67 23.21. |
| S17 | F — Never add `-foce` or `-second_order` (documented as not working). |

## B — bootstrap (resampling)

| # | Rule |
|---|---|
| B1 | F — Individuals are **renumbered** by PsN: remove `ACCEPT/IGNORE` statements that use `ID`, and any abbreviated code that depends on ID values (first-occurrence tests, `ID.EQ.n`, cross-individual logic). Filtering must move into the data file. `-allow_ignore_id` exists but is not recommended — flag it, do not rely on it. |
| B2 | F — `IGNORE/ACCEPT` on *other* columns stay in the control stream and are applied **after** resampling, so a replicate can be smaller than `sample_size`. Flag it; if the intent is to shrink the analysis set, pre-filter the dataset instead. |
| B3 | C — If the user must stratify (rich vs sparse, study pools), the stratification column must be in `$INPUT` (add it) and constant within each individual, else the run aborts. Emit `-stratify_on=col` and, for exact per-stratum counts, `-sample_size="1001=>12,1002=>24"`. |
| B4 | E — `$COVARIANCE` and `$TABLE` are stripped from every replicate unless `-keep_covariance` / `-keep_tables` are given, so leaving them in the base model costs nothing for the replicates; delete `$COV` in the delivered file only when the user wants the base run cheaper too. |
| B5 | F — Initial estimates come from the **final** estimates of the base model unless `-no-update_inits`; if the base `.lst` is absent the base model is run first, which also changes the RNG state — same seed ≠ same datasets. Tell the user to keep the base `.lst` next to the model and set `-seed=`. |
| B6 | C — Size to the stated purpose: ~200 samples for standard errors, ~2000 for percentile CIs (percentile CIs also need ≥19/39/199 successful samples for 5–95 / 2.5–97.5 / 0.5–99.5%). |

For optional epsilon=0 with error=add/prop/propadd, the manual requires a THETA-based W
(and WA/WP for combined error). This parameterization needs a unit residual SIGMA to avoid
duplicate residual scales; apply a fixed unit only with explicit user approval under NOFIX.
Otherwise preserve the estimated SIGMA and exact EPS linearization/full-fitting route.
Never set residual SIGMA to zero; that removes residual variability entirely.
