#!/usr/bin/env Rscript
.this <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.here <- if (!is.na(.this) && .this != "-" &&
             file.exists(file.path(dirname(.this), "stage_lib.R"))) dirname(.this) else {
  cand <- c(Sys.getenv("STAGES_DIR", ""), getwd(), file.path(getwd(), "stages"))
  cand <- cand[nzchar(cand)]
  hit  <- cand[file.exists(file.path(cand, "stage_lib.R"))]
  if (!length(hit)) stop("cannot locate stages/stage_lib.R - set STAGES_DIR", call. = FALSE)
  hit[1]
}
.here <- normalizePath(.here, winslash = "/", mustWork = TRUE)
source(file.path(.here, "stage_lib.R"))

A <- commandArgs(trailingOnly = TRUE)
FAM <- "ppk"
if ("--family" %in% A) { i <- which(A == "--family"); FAM <- A[i + 1]; A <- A[-c(i, i + 1)] }
pmx_start(A[1], "s4")   # 02_html/ (or the flat folder when PMX_LAYOUT=flat)
FAM <- sub("_data\\.csv$", "", FAM)

stage_require("s4", "s2")
cat("=== S4 html:", FAM, "in", getwd(), "===\n")
stage_invalidate(c("s4","s3","s5"))

rmd <- paste0(FAM, "_report.Rmd")
if (!file.exists(rmd)) stop("S4: ", rmd, " is not in ", getwd(),
  " - copy the family template from analyses_template/<fam>/ first", call. = FALSE)

out <- paste0(FAM, "_report.html")
if (file.exists(abs_root(out))) unlink(abs_root(out))   # a stale HTML must never satisfy the gate
figdir <- abs_root(gpath("html", "_knit_figures"))
if (!dir.exists(figdir)) dir.create(figdir, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(PMX_RMD = normalizePath(rmd), PMX_HTML_OUT = abs_root(out))
expr <- sprintf(paste0("knitr::opts_chunk$set(fig.path=%s); ",
                       "rmarkdown::render(Sys.getenv('PMX_RMD'), output_file=Sys.getenv('PMX_HTML_OUT')%s)"),
                shQuote(paste0(figdir, "/")),
                if (pmx_flat()) "" else ", knit_root_dir=Sys.getenv('PMX_ROOT')")
status <- system2("Rscript", c("-e", shQuote(expr)))
if (status != 0) stop("S4: knitting ", rmd, " exited ", status, call. = FALSE)
source(file.path(dirname(.here), "html_references.R"))
pmx_html_references(abs_root(out))

stage_close("s4", inputs = stage_inputs("s4", FAM), outputs = stage_outputs("s4", FAM),
            note = "self-contained HTML; re-run S3 to (re)extract figure/ and table/ from it")
