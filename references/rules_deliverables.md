# Deliverable-specific rules — read ONLY when the deliverable is that thing

Read only the section for the requested deliverable. Model code uses the dialect route in
INDEX.md; the rules router is not a requirement to load every reference.

## Structure diagram rules (SVG)

Use these rules only for a requested diagram or a report-required structure figure; a code-only
request does not authorize diagram files. Read the actual CTL/CPP and the diagram README once;
call the existing renderer, which selects ONE matching SVG skeleton. Do not inspect helper source,
grep raw SVG groups, rewrite nodes or create a temporary drawing script for a supported model.
Read one relevant implementation section only for a named renderer incompatibility.
The skeleton layout and the scientific rules below remain mandatory.

After PMX_CHAT_ONLY, explain the named scope mismatch; do not retry shell/write, switch tools,
read nonexistent temporary files or search SVG internals to work around it. A loaded old guard
requires a newly loaded PMX preset/session, not global write access or changed directory rights.
Once a lookup answers its question, reuse it; a truncated SVG search is not a reason for another
regex sweep. For an unsupported mechanism, report its exact missing mapping instead.

1. **Select before drawing.** Use `word-report/model_diagram.R` to select the source-matched
   route, distribution compartments and mechanism. For reports, the shared structure-fig chunk
   does this automatically. `STRUCTURE_CONFIG` in that Rmd can resolve an ambiguous turnover
   mechanism or shorten labels; it cannot contradict detected topology. Unsupported structures
   require a source-matched extension, never a plausible-looking default. No fitting is needed.
2. **Preserve meaning.** Clearance removes drug from the system, never Central -> free Drug.
   Free drug is a species in the central system, not another PK compartment reached by CL.
   Only show absorption, distribution, elimination and effects supported by the actual code.
   No THETA/ETA numbers, covariates or ODE syntax. Use native parameter labels, not fitted values.
3. **Keep the skeleton.** White full-canvas background; dark labels/lines on light rounded
   boxes, one PK accent and one response accent, thin arrows, sans-serif text and one title.
   No shadows, gradients or animation. Labels stay clear of shafts, arrowheads and box edges.
   Do not add observation symbols unless the actual endpoint is identified and connected.
   Label each bidirectional distribution pair with Q once, retaining both arrows.
4. **Separate information from material flow.** Binding and PK transfers use solid arrows.
   Drug effects use dashed links: turnover effects end on the affected rate shaft, not its
   box or empty space. Inhibition uses a T-bar perpendicular to the RATE shaft; stimulation
   uses an arrowhead. Direct PD relationships are information links, not mass transfers.
5. **Render once, then deliver.** Keep the renderer's built-in node/edge, clearance,
   reaction-stoichiometry and rate-attachment validation. After a successful standalone render,
   deliver the requested figure/path and stop. Do not reopen, preview, visually inspect, revise
   or redraw it unless the user explicitly requests review or changes. These built-in checks
   do not establish that a chosen pharmacological interpretation matches an arbitrary model.
6. **Use the same figure in reports.** HTML embeds the generated PNG with a Model structure
   caption; Word extracts that exact image from HTML. Never redraw it independently for Word.
   Refresh current study Rmds from the family template, preserve study configuration, and resume
   at S4 for an authorized diagram update. Do not rerun NCA, screening, SCM or covariance.

### TMDD binding mechanism

Use tmdd.svg: **free Drug + free Target <-> Complex**, with one shared reversible reaction
for the PAIR of reactants. Dissociation releases BOTH drug and target. An irreversible model
has only the forward reaction. Full TMDD labels association KON and dissociation KOFF separately; QSS/QE shows only its
binding constant KSS or KD without inventing separately estimated kinetic rates or an extra ODE state.
Kint leaves Complex; Kin/Ksyn enters free Target; Kout/Kdeg leaves free Target, as in code.
Never replace binding with Drug -> Target or a generic inhibits-Kout turnover diagram.
Display Drug, Target and Complex without free/total qualifiers. Preserve species distinctions
in the source interpretation and semantic checks, not the visible labels. Omit the explanatory
QSS/complex footer; retain the binding-relation parameter label when applicable.

### PPK, PKPD and TGI skeletons

- ppk.svg: IV or one/two oral depots, one to three distribution compartments and a clearance
  sink. Preserve actual fraction/lag and nonlinear-elimination labels; add no PD pathway.
- pkpd.svg: direct response, effect-site response, or turnover. For turnover, select exactly
  the affected Kin/Kout rate and inhibit/stimulate direction from code. No universal PD default.
- tgi.svg: a growing tumor with drug-related loss, or the supported four-state Simeoni damage
  chain. Growth applies to the proliferating state; the total includes all modeled tumor states.
  Do not collapse a damage-transit model into an immediate-response box or invent drug PK.

## Covariate functions (nlmixr2 covariate search / PopPK reports)

The `.ctl` templates carry covariate examples as `$THETA`/`$PK` syntax only. The *functional form*
each covariate must take — continuous vs categorical, reference values, and the body-weight
allometric exception with its exponent fixed — is defined once in
`../word-report/ppk_covariate_model_rules.md`. Read it before adding a covariate to an nlmixr2
model or describing one in a report; do not invent a form here.

