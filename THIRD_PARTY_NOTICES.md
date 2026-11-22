# Third party software and notices

The analysis workflows use separately installed software. Required R packages can be checked with analyses_template/tools/install_dependencies.R.

| Software | Use | Upstream |
|---|---|---|
| R and base/recommended packages | Statistical computation, graphics, parallel execution | [R](https://www.r-project.org/), [R licenses](https://www.r-project.org/Licenses/) |
| nlmixr2, nlmixr2est, nlmixr2extra, rxode2, lotri | Nonlinear mixed-effects fitting, ODEs, covariance, bootstrap support | [nlmixr2](https://github.com/nlmixr2/nlmixr2) |
| nonmem2rx | Supported NONMEM control-stream translation | [nonmem2rx](https://github.com/nlmixr2/nonmem2rx) |
| nlmixr2save | Portable fit export/import | [nlmixr2save](https://cran.r-project.org/package=nlmixr2save) |
| mrgsolve | Compiled model simulation and report simulator checks | [mrgsolve](https://mrgsolve.org/) |
| lme4, nlme | Mixed-effects models and fit accessors | [lme4](https://cran.r-project.org/package=lme4), [nlme](https://cran.r-project.org/package=nlme) |
| survival, survminer, cowplot | Time-to-event modeling and displays | [survival](https://cran.r-project.org/package=survival), [survminer](https://cran.r-project.org/package=survminer), [cowplot](https://cran.r-project.org/package=cowplot) |
| tidyverse, dplyr, tidyr, tibble, readr, stringr, ggplot2, scales | Data handling and graphics | [tidyverse](https://www.tidyverse.org/) |
| haven | Supported SAS-format input | [haven](https://cran.r-project.org/package=haven) |
| tidyvpc | Visual predictive check statistics/plots | [tidyvpc](https://cran.r-project.org/package=tidyvpc) |
| gridExtra, htmltools, jsonlite, rlang, xml2 | Layout and structured data/XML | [CRAN packages](https://cran.r-project.org/web/packages/available_packages_by_name.html) |
| knitr, rmarkdown, Pandoc | R Markdown execution and document conversion | [knitr](https://yihui.org/knitr/), [rmarkdown](https://rmarkdown.rstudio.com/), [Pandoc](https://pandoc.org/) |
| officer, flextable, ragg | Word documents, tables, graphics support | [officer](https://cran.r-project.org/package=officer), [flextable](https://cran.r-project.org/package=flextable), [ragg](https://cran.r-project.org/package=ragg) |
| RhpcBLASctl | Optional BLAS thread control | [RhpcBLASctl](https://cran.r-project.org/package=RhpcBLASctl) |
| Node.js | Queue clients and workflow orchestration | [Node.js](https://nodejs.org/) |
| Python | Word OOXML processing | [Python](https://www.python.org/) |
| POSIX/GNU utilities and rsync | Workflow shell operations and explicit synchronization | [GNU](https://www.gnu.org/software/), [rsync](https://rsync.samba.org/) |
| PsN | Optional control-stream preparation/external analysis integration | [PsN](https://uupharmacometrics.github.io/PsN/) |

R is distributed under GPL-2/GPL-3 terms, with file-level exceptions described upstream. PsN states GPL version 2 or later. Exact R package license strings vary; consult the recorded metadata and the upstream license files, including additional LICENSE files for MIT-licensed packages. Licenses of native/transitive dependencies and any redistributed runtime image require their own review.

NONMEM is a separate proprietary product, not an open-source dependency bundled by this project. The template format and conversion helpers do not include a NONMEM executable or grant a NONMEM license.

Software/project names and upstream organizations are retained for accurate attribution. No affiliation, sponsorship, or endorsement by those projects is claimed.
