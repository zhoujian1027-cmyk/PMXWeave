# Convert a `.ctl` into scm / bootstrap ready files

Output = **files and a command line**, never advice about running or reading a PsN run.
`<psn>` = the `nonmem_template/psn/` folder under the workspace root. Read at most one file:
`<psn>/references/checklist.md`. Templates: `<psn>/templates/`.

## Workflow

1. Read the user-supplied control stream. Treat the reusable nonmem_template/psn/ assets as read-only.
   Return the complete converted `.ctl`, `.scm` and commands in one response; save files
   only to a user-designated study/output directory. Never default to the template directory.
2. Run the conversion rules in `<psn>/references/checklist.md` over it, in order:
   **A** (always) → **S** (scm) → **B** (bootstrap). Report each change; report each failed
   precondition as a blocking fix request rather than working around it.
3. Emit, in fenced blocks with the target filename as the first line:
   - `model_psn.ctl` — the converted control stream, complete.
   - `<model>.scm` — from `nonmem_template/psn/templates/scm_config.scm` if scm is in scope.
   - the command line — from `nonmem_template/psn/templates/psn_commands.sh` (one line per tool).

## Hard rules

1. **Never invent** options, defaults, section names, or relation states. The checklist and
   templates list everything; anything beyond them is outside these preparation templates (verify in
   the matching [official PsN manual](https://uupharmacometrics.github.io/PsN/docs.html); cite its version and source if consulted).
2. **The conversion must not change model behaviour** unless the rule says so. Keep
   `$THETA`/`$OMEGA`/`$SIGMA` values, estimation method, and all PK/PD code intact; rename
   only what the `TVpar` rule requires and update every use.
3. **scm input must be the clean base model**: no covariate relation pre-coded, every tested
   parameter as `TVpar` in `$PK`/`$PRED`. Covariates to be tested appear in `$INPUT` only.
4. **scm config syntax**: no leading `-`, all option lines above the first `[section]`,
   flags as `name=1`, `;` comments on their own line (never at end of line), no `seed` /
   `missing_data_token` in the file — those go on the command line.
5. **Preparation does not execute PsN or NONMEM.** Do not claim a fit was run, validated or converged from the generated files alone.
