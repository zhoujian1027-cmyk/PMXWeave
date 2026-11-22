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
FRESH <- "--fresh" %in% A
A <- setdiff(A, "--fresh")
FAM <- "ppk"
if ("--family" %in% A) { i <- which(A == "--family"); FAM <- A[i + 1]; A <- A[-c(i, i + 1)] }
pmx_start(A[1], "s1")   # 02_html/ (or the flat folder when PMX_LAYOUT=flat)
FAM <- sub("_data\\.csv$", "", FAM)

WR <- normalizePath(file.path(.here, ".."))   # the word-report folder
if (!file.exists(file.path(WR, "run_pipeline.R")))
  stop("cannot find run_pipeline.R next to stages/ (looked in ", WR, ")", call. = FALSE)

need <- stage_inputs("s1", FAM)
miss <- need[!file.exists(abs_root(need))]
if (length(miss)) stop("stage s1 needs ",
  paste(miss, collapse = ", "), " in ", if (nzchar(pmx_root())) pmx_root() else getwd(), call. = FALSE)

stage_invalidate("s1")
if (FRESH && dir.exists("_scm_sel_cache")) {
  cat("--fresh: clearing _scm_sel_cache/ (every candidate is refitted)\n")
  unlink("_scm_sel_cache", recursive = TRUE)
}

cat("=== S1 fit:", FAM, "in", getwd(), "===\n")
status <- system2("Rscript", c(shQuote(file.path(WR, "run_pipeline.R")), ".",
                               "--family", FAM, "--phase", "search", if (FRESH) "--fresh"))
if (status == 3) {
  cat("S1_DEFER run_pipeline.R used its whole job budget before the fits were complete;",
      "\n  state: _scm_sel_cache/scm_state.rds, cached fits are reused.",
      "\n  The s1 gate is NOT written. Re-run the same command to resume.\n", sep = "")
  quit(save = "no", status = 3)
}
if (status != 0) stop("S1: run_pipeline.R exited ", status,
                      " - the gate is NOT written; fix the fit, do not retry.", call. = FALSE)

# The fit is now final, so the frozen downstream artifacts are stale: clear s2..s5 BEFORE writing the
# new s1 gate. This used to happen on entry, which meant every s1 attempt - including one that stopped on
# its job budget and produced nothing new - threw away the downstream gates of a finished report.
stage_invalidate(c("s1c", "s2", "s3", "s4", "s5"))
pmx_covariance_state("PENDING","SCM selection and parameter estimates complete; final uncertainty pending")
stage_close("s1", inputs = need, outputs = stage_outputs("s1", FAM),
            note = paste("family", FAM, "| estimates complete; uncertainty pending; search checkpoint preserved"))
