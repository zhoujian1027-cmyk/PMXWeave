# PPK covariate-model rules — functional forms

**Read this before adding any covariate to a PPK model, or before running or
reporting a covariate search.** It is the single source of truth for which
function a covariate enters with.

Precedence: **this file > `report_template/PopPK.md` > `nonmem_template/*.ctl`**.
Current explicit user instructions and references/fit_workflow.md govern scope and approved fixed values.

## The rules

| Covariate type | Form | Exponent |
|---|---|---|
| Continuous (age, creatinine clearance, albumin, BMI, …) | `P = TVP * (COV/REF)**theta` | **estimated** |
| **Body weight** | `CL = TVCL * (BW/70)**0.75` and `Vc = TVVC * (BW/70)**1` | **standard allometric power** — 0.75 on clearance, 1 on volume: a structural constant with no `$THETA` entry, never written as `FIX` in a `.ctl` |
| Categorical (sex, race, baseline disease class, …) | `P = TVP * (1 + theta_j * X_j)` | n/a; `theta_j` is a relative change; the parameter ratio is `1 + theta_j` |

Conventions that come with these forms:

- **Categorical reference category = the most frequent category.** `X_j` is 0 for it,
  so `TVP` is the typical value for that category and every `theta_j` reads as a
  fold-change relative to it. For a two-level covariate code the indicator as
  `(COV == non_reference_level)`.
- **Reference values (REF)** of the power model: **body weight 70 kg**,
  **age 40 years**, **creatinine clearance 90 mL/min**. The 70 kg value is the
  conventional standard and is used throughout the analysis templates.
- **Never use `P = TVP * EXP(theta * COV)` on a centred covariate.** It is only the
  different functional form from the power model. Do not substitute it silently; an explicit
  configured effect retains its declared form.
- **Multiplicative parameterisation, never additive.** the power model keeps the parameter positive for positive covariate/reference values.
  For categorical shift models, 1 + theta_j must remain positive; an invalid fitted
  parameter is a fit failure, not a reason to clip a coefficient silently.
- **Body weight is the one covariate with a fixed exponent.** Do not estimate 0.75
  or 1 unless you are explicitly testing whether the fixed allometric value is
  adequate; fit both in that case and report both.

Estimated covariate coefficients are emitted as scalar initials (0) without default
lower/upper bounds. Direction constraints require an explicit scientific specification in
the study control stream; do not infer them from a covariate name or from observed data.
Body-weight exponents 0.75 on CL and 1 on V remain fixed as explicitly retained by the user.
FOCEI may move an exact zero initial to 0.001. SCM_INIT_SCALE_WARNING identifies a coefficient
that remains at that value with a small recorded scale; it requires scientific review and
does not prove a true near-zero effect or statistical significance.

## Reference implementation

`word-report/run_pipeline.R` implements exactly these forms. The builder takes a
per-parameter list of effects:

```r
pw  <- function(cov, ref, exp = NULL) list(type = "power", cov = cov, ref = ref, exp = exp)
ctg <- function(cov, level)          list(type = "cat",   cov = cov, level = level)

BWCL_HOUSE <- pw("bw", 70, 0.75)        # fixed allometric, on CL
BWV_HOUSE  <- pw("bw", 70, 1)           # fixed allometric, on Vc
pw("age", 40)                           # power, exponent estimated
pw("crcl", 90)                          # power, exponent estimated
ctg("sex", 2)                           # shift, reference = non-2
```

- `exp = NULL` → the exponent is estimated (`theta <- 0`).
- `exp = <number>` → emitted as `fix(<number>)`, i.e. a fixed allometric exponent.
- `type = "cat"` emits `(1 + theta * (cov == level))`, so the reference is every
  other level.
- Candidate scope: every data-reviewed eligible baseline covariate on both CL and central VC,
  per references/report_rules.md and references/fit_workflow.md. The agent declares all pairs;
  a coverage check rejects omissions. test=no requires the explicit human restriction.
  Do not infer race labels or preselect a biological subset.
- In covariates.csv the `param` column uses the model's literal `$PK` THETA symbols, i.e.
  `TVCL` and the central-volume symbol (`TVVC`/`TVV`/`TVV1`), not the derived `CL`/`Vc` names;
  the schema example is word-report/covariates_template.csv.

