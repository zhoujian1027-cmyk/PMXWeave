# Model-structure diagrams: direct entry

For an authorized single SVG, read the actual CTL/CPP and call the existing portable entry once:

```sh
node <toolkit>/analyses_template/tools/draw_model_structure.mjs <actual.ctl-or.cpp> <ppk|pkpd|tmdd|tgi> <requested-output.svg>
```

It uses local R when available; otherwise it submits a compact job to the configured R queue.
No R-host discovery, full toolkit mirror, study .pmx directory, fit, data CSV or temporary drawing
script is needed. The worker stages only the selected SVG and renderer in its temporary directory,
then removes those temporary files. Only the requested SVG is written in the target directory.
For DIAGRAM_PENDING, follow the exact DIAGRAM_FOLLOW command once in background. Do not launch
the analysis/report chain. Queue audit files remain in the runtime queue, outside the study.
Existing study .pmx directories may contain fit caches: do not remove them for a figure request.

After a successful standalone render, deliver the requested figure/path and stop. Do not reopen,
preview, inspect, revise or redraw unless the user explicitly requests review or changes. Keep
the renderer's built-in validation. A report reuses the generated figure and continues its
remaining authorized stages; do not add a separate figure-review pass.

The renderer consumes one of ppk.svg, pkpd.svg, tmdd.svg or tgi.svg and selects its hidden variants.
Do not read/grep the raw SVG groups or helper source for routine drawing, unhide every group,
move nodes or redraw the template. references/rules_deliverables.md owns the scientific rules.
Use an extra implementation read only for a named incompatibility. Unchanged lookup results
are reused. A new actual human request to save/export a figure updates an earlier chat-only scope automatically;
no global write-permission change is needed. For a code block not saved as CTL/CPP, pass those exact
source lines to pmx_model_diagram(ctl=<lines>, ...) through the configured R execution route. Do not
invent a saved model path or create a temporary drawing script. After a real PMX_CHAT_ONLY rejection,
report the exact mismatch once; do not retry alternate tools or read nonexistent temporary SVGs.

PPK/PKPD/TMDD reports place structure-fig first in Results / Base Model, before parameter tables,
using base_model.ctl. Word places the same extracted PNG in 5.2 Base model. RUN_STRUCTURE_FIG
defaults to TRUE; preserve study configuration and resume at S4 for an authorized diagram refresh.

The R API is pmx_model_diagram(ctl, family, template_dir, out_dir, options=list(), render_png=TRUE).
STRUCTURE_CONFIG normally remains list(). A source-reviewed ambiguous turnover mechanism may use
list(turnover="inhibit_kout"); labels may shorten titles. Conflicting topology stops with
MODEL_DIAGRAM_SPEC_REQUIRED: repair only the named coverage/configuration issue, never the fit.
Only xml2 and standard R graphics are required; no DiagrammeR/browser/rsvg dependency.
