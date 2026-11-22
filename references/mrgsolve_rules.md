# mrgsolve rules

Use references/model_authoring.md and one matching mrgsolve_template/*.cpp.
For CPP-only work, use the shared Compose and deliver behavior;
NONMEM syntax and report engines are not required reads.
Preserve the selected PARAM/CMT/OMEGA/MAIN/ODE/TABLE/CAPTURE layout.
A requested residual-error simulator must include matching SIGMA/EPS and captured IPRED/DV;
a structural-only skeleton is not a completed residual simulator.

## mrgsolve verified rules
1. IIV from $OMEGA via `ETA(i)`; RUV via `EPS(i)` (never `SIGMA(i)`).
2. ODEs: `dxdt_CMT = expr;`.
3. $PARAM names are read-only: derive with new doubles, e.g. `double CL = TVCL * exp(ETA(1));`.
4. Dose flags are bare assignments in $MAIN: `F_DEPOT = ...;` / `ALAG_DEPOT = ...;` (no `double`).
5. Set CMT_0 in $MAIN to match the data and the paired CTL.
   For steady-state turnover, use KIN = R0 * KOUT and RESPONSE_0 = R0.
   pk_parallel.cpp expects the full dose in each depot and splits it with F_DEPOT1/F_DEPOT2.
   Avoid steady-state simulation with explicitly time-varying clearance.
6. $CAPTURE: derived doubles from $TABLE (and compartments where needed).
7. Math functions lowercase: `exp log sqrt pow fabs fmax`; literals in plain decimal or `e` form (`0.0001`), **never** a FORTRAN `D`-exponent (`1D-10`).
8. Time-varying: NONMEM `TIME` → mrgsolve `SOLVERTIME` in $ODE.
9. TMDD units: ligand = MASS (`A(n)` / `CENTRAL/VC`), receptor & complex = CONCENTRATION.
10. Correlated IIV uses `$OMEGA @block`, lower-triangle rows with zeros outside the block;
    never a flat list or @cor. Use mrgsolve_template/block_omega.cpp. Preserve covariance,
    ETA order and dimensions from the CTL, not correlations or sign-constrained off-diagonals.
    Reports update parsed model matrices through the shared report helper; token counts or
    numeric-looking comments never determine fitted OMEGA/SIGMA.

11. Bioavailability fraction carrying an ETA: keep the `$PARAM` on the 0-1 scale and build
    the logit in `$MAIN` (`double LGTF1_TV = log(TVF1 / (1.0 - TVF1));`). A fraction without an ETA
    needs no logit (references/model_authoring.md, Shared pharmacology and response scale).

12. Use short // comments. Keep C++ statement terminators.

13. If a `$SET` block is requested, place each named setting on its own line (for example,
    `atol = 1e-10` then `rtol = 1e-8`). Check the loaded settings rather than assuming a
    space-separated list was applied in runtime/report work; code-only tasks run no checks.
    Reports configure loaded solver objects; no CPP edit
    or header rewrite is needed merely to change numerical evaluation controls.

## Fraction example

Keep TVF1=0.5 in PARAM. In MAIN, derive
`double LGTF1_TV = log(TVF1 / (1.0 - TVF1));`,
`double LGTF1 = LGTF1_TV + ETA(5);` and
`double FRAC1 = exp(LGTF1) / (1.0 + exp(LGTF1));`.
Use the selected model's actual parameter/ETA names and mapping.
For a fraction without IIV, use the fraction directly.
