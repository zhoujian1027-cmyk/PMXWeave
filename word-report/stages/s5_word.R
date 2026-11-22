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
FAM <- "ppk"; NOFIG <- FALSE
if ("--family" %in% A) { i <- which(A == "--family"); FAM <- A[i + 1]; A <- A[-c(i, i + 1)] }
if ("--no-figures" %in% A) { NOFIG <- TRUE; A <- setdiff(A, "--no-figures") }
pmx_start(A[1], "s5")   # 03_word/ (or the flat folder when PMX_LAYOUT=flat)
FAM <- sub("_data\\.csv$", "", FAM)

WR <- normalizePath(file.path(.here, ".."))
stage_require("s5", "s3")
cat("=== S5 word:", FAM, "in", getwd(), "===\n")
stage_invalidate("s5")

out <- paste0(FAM, "_report.docx")

DIR  <- if (pmx_flat()) getwd() else pmx_root()
args <- c(shQuote(file.path(WR, "report_generator.R")), shQuote(DIR),
          "--family", FAM, "--out", paste0(FAM,"_report.tmp.docx"),
          "--ctl",shQuote(abs_root(gpath("html","artifacts","s2","final_fitted.ctl"))),
          "--data",shQuote(Sys.getenv("PMX_DATA",abs_root(paste0(FAM,"_data.csv")))))
if (!pmx_flat()) args <- c(args,
  "--fig-dir",   shQuote(abs_root(gpath("word", "figure"))),
  "--table-dir", shQuote(abs_root(gpath("word", "table"))),
  "--fit-log",   shQuote(abs_root(gpath("html", "_nlmixr2_output.txt"))))
if (NOFIG) args <- c(args, "--no-figures")
status <- system2("Rscript", args)
if (status != 0) stop("S5: report_generator.R exited ", status,
                      " - no docx written, gate NOT written", call. = FALSE)
tmp <- file.path(DIR,paste0(FAM,"_report.tmp.docx"))
if (!file.exists(tmp)) stop("S5: the generator exited 0 but wrote no docx", call. = FALSE)
if(!file.rename(tmp,abs_root(out))) stop("Cannot publish Word output")

evidence <- jsonlite::fromJSON(file.path(DIR,"output","report_evidence.json"),simplifyVector=FALSE)
if(isTRUE(evidence$narrative$required) && !identical(evidence$narrative$state,"accepted")) {
  cat("NARRATIVE_REQUIRED structured draft and evidence preserved; do not refit or resubmit unchanged stages.\n")
  cat("NARRATIVE_NEXT node analyses_template/tools/report_narrative.mjs ",shQuote(DIR),
      "; author current Results, Discussion and Conclusion; validate; resume --from=s5.\n",sep="")
  quit(status=4)
}

stage_close("s5", inputs = stage_inputs("s5", FAM), outputs = stage_outputs("s5", FAM),
            note = paste("no-figures:", NOFIG))
