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
FAM <- "ppk"; NSIM <- ""
if ("--family" %in% A) { i <- which(A == "--family"); FAM <- A[i + 1]; A <- A[-c(i, i + 1)] }
if ("--nsim"   %in% A) { i <- which(A == "--nsim");   NSIM <- A[i + 1]; A <- A[-c(i, i + 1)] }
pmx_start(A[1], "s3")   # 03_word/ (or the flat folder when PMX_LAYOUT=flat)
FAM <- sub("_data\\.csv$", "", FAM)

WR <- normalizePath(file.path(.here, ".."))
stage_require("s3",c("s2","s4"))
cat("=== S3 figures:", FAM, "in", getwd(), "===\n")
stage_invalidate(c("s3","s5"))

FIGDIR <- gpath("word", "figure")
TBLDIR <- gpath("word", "table")
if (!dir.exists("figure")) dir.create("figure")
html     <- abs_root(paste0(FAM, "_report.html"))
fig_prog <- c("make_figures.R", file.path("scripts", "make_figures.R"))
fig_prog <- c(abs_root(fig_prog)[file.exists(abs_root(fig_prog))],
              fig_prog[file.exists(fig_prog)])

if(FAM %in% c("ppk","pkpd","tmdd")) fig_prog <- character() # Every Word figure must be extracted from the current HTML.
if (length(fig_prog)) {
  cat("route: family figure program (", fig_prog[1], ")\n", sep = "")
  if (nzchar(NSIM)) Sys.setenv(PPK_NSIM = NSIM)
  status <- system2("Rscript", shQuote(fig_prog[1]))
  if (status != 0) stop("S3: ", fig_prog[1], " exited ", status,
                        " - the gate is NOT written", call. = FALSE)
} else if (file.exists(html)) {
  cat("route: extract_figures.R on ", html, "\n", sep = "")
  status <- system2("Rscript", c(shQuote(file.path(WR, "extract_figures.R")),
                                 shQuote(html), "--out", shQuote(abs_root(FIGDIR))))
  if (status != 0) stop("S3: extract_figures.R exited ", status, call. = FALSE)
} else {
  stop("S3: no figure route - this directory has neither make_figures.R nor ",
       html, ". Add the figure program, or run S4 first and re-run S3.", call. = FALSE)
}

if (file.exists(html)) {
  if (!dir.exists("table")) dir.create("table")
  st <- system2("Rscript", c(shQuote(file.path(WR, "extract_tables.R")),
                             shQuote(html), "--out", shQuote(abs_root(TBLDIR))))
  if (st != 0) stop("S3: table extraction failed; stale tables must not enter Word")
}

if (!dir.exists("table")) dir.create("table")
for (f in c("_scm_summary.csv", "_scm_runrecord.csv")) {
  src <- abs_root(gpath("html", "table", f))
  if (file.exists(src)) file.copy(src, file.path("table", f), overwrite = TRUE)
  else { dst <- file.path("table",f); if(file.exists(dst)) unlink(dst); message("Optional SCM table omitted: ",f) }
}

outs <- stage_outputs("s3", FAM)
if(!file.exists(abs_root(gpath("word","figure","_html_figures.csv"))) ||
   !file.exists(abs_root(gpath("word","table","_html_tables.csv"))))
  stop("S3 requires current figure/table manifests from its extraction route")
cat("figures:", length(grep("\\.png$", outs, value = TRUE)), "\n")
stage_close("s3", inputs = stage_inputs("s3", FAM), outputs = outs,
            note = paste("route:", if (length(fig_prog)) basename(fig_prog[1]) else "extract_figures.R",
                         "| frozen input: artifacts/s2/final.rds"))
