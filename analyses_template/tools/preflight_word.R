#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
dir  <- if (length(args)) args[[1]] else Sys.getenv("PMX_ANALYSIS_DIR", unset = getwd())
if (!dir.exists(dir)) { cat("WORD_PREFLIGHT_STOP usage: preflight_word.R <existing analysis-dir>\n"); quit(status = 2) }

# The one place that knows the fix for a named library. Keep it in sync with report_generator.R and
# analyses_template/tools/run_regression.sh, which emit the same WORD_ENV_BROKEN token to the same effect.
FIX <- c("libwebpmux.so.3"   = "apt-get install -y libwebpmux3",
         "libwebpdemux.so.2" = "apt-get install -y libwebpdemux2")
hint_for <- function(so) if (!is.na(so) && so %in% names(FIX)) unname(FIX[[so]]) else
  "rebuild the worker image with the missing system library (see analyses_template/tools/preflight_word.R header)"

# The load error names TWO libraries: the object R could not load (ragg.so) and the library that was
# actually absent (`.../ragg.so': libwebpmux.so.3: cannot open shared object file`). Only the second is
# actionable, and a naive "first .so in the message" match reports ragg.so - which reads like an R
# package problem and sends the reader after the wrong thing. Anchor on the linker's own wording.
missing_so <- function(msg) {
  so <- regmatches(msg, regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*: cannot open shared object file", msg))
  if (length(so)) return(sub(":.*$", "", so))
  so <- regmatches(msg, regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*", msg))
  if (length(so)) so else "unknown"
}

# 0. Shim: map a staged copy of a missing system library BEFORE anything loads ragg. Same contract as
#    word-report/preload_word_libs.R, kept inline because the preflight must also work in a study dir
#    where nothing of the toolkit was staged. The loader records the object under its SONAME, so
#    ragg.so's own request is satisfied from the already-mapped object and no filesystem search
#    happens; a broken image then costs queue time instead of the deliverable. LD_LIBRARY_PATH cannot
#    do this from R: glibc caches the search path at process start, so Sys.setenv() is ignored by dlopen.
shimmed <- character(0)
.pre_names <- c("libwebpmux.so.3", "libwebpdemux.so.2")
.pre_dirs <- c(Sys.getenv("PMX_WORD_LIB", ""),
               file.path(dir, ".pmx", "word-report", "lib"),
               file.path(dir, "word-report", "lib"),
               file.path(dir, ".pmx", "pmx_workspace", "word-report", "lib"))
.pre_dirs <- unique(.pre_dirs[nzchar(.pre_dirs) & dir.exists(.pre_dirs)])
.ld_dirs  <- c(strsplit(Sys.getenv("LD_LIBRARY_PATH", ""), ":")[[1]],
               "/lib", "/usr/lib", Sys.glob("/lib/*-linux-gnu"), Sys.glob("/usr/lib/*-linux-gnu"))
for (so in .pre_names) {
  if (any(file.exists(file.path(.ld_dirs[nzchar(.ld_dirs)], so)))) next
  for (d in .pre_dirs) {
    f <- file.path(d, so)
    if (file.exists(f) && !is.null(tryCatch({ dyn.load(f); 1 }, error = function(e) NULL))) {
      shimmed <- c(shimmed, so); break
    }
  }
}
if (length(shimmed)) cat("WORD_ENV_SHIM preloaded=", paste(shimmed, collapse = ","), "\n", sep = "")

# 1. Real load of the Word chain, exactly as report_generator.R does it.
pkgs <- c("jsonlite", "officer", "flextable")
pkg_status <- character(0)
for (p in pkgs) {
  msg <- tryCatch({ suppressPackageStartupMessages(library(p, character.only = TRUE)); NULL },
                  error = function(e) conditionMessage(e))
  pkg_status[p] <- if (is.null(msg)) "ok" else "fail"
  if (!is.null(msg)) {
    so <- missing_so(msg)
    cat("WORD_ENV_BROKEN pkg=", p, " missing=", so, ' fix="', hint_for(so), '"\n', sep = "")
    cat("WORD_ENV_BROKEN_MSG ", gsub("\\s+", " ", msg), "\n", sep = "")
    cat("WORD_PREFLIGHT_STOP a missing system library is permanent: fix the image, do not resubmit ",
        "analysis jobs (each attempt costs a serial queue slot and renders nothing)\n", sep = "")
    quit(status = 1)
  }
}

# 2. Ground truth from the dynamic linker, independent of R's error text. This is what named the
#    actual defect, and it catches a second missing library before it masks the first.
ragg_so <- tryCatch(file.path(find.package("ragg"), "libs", "ragg.so"), error = function(e) NA_character_)
ldd_missing <- character(0)
if (!is.na(ragg_so) && file.exists(ragg_so)) {
  ldd <- tryCatch(system2("ldd", ragg_so, stdout = TRUE, stderr = TRUE), error = function(e) character(0))
  ldd_missing <- sub("^[[:space:]]*([^[:space:]]+)[[:space:]]*=>.*not found.*$", "\\1",
                     grep("not found", ldd, value = TRUE))
  ldd_missing <- ldd_missing[nzchar(ldd_missing)]
}
# A library the step-0 shim already mapped is not missing for THIS process, so it must not be reported
# as broken. `ldd` runs as a NEW process, where the shim does not exist, so the SONAME still shows as
# `not found` there; subtract the shim set by hand instead of trusting ldd alone.
if (length(shimmed) > 0 && length(ldd_missing) > 0) {
  cat("WORD_ENV_SHIM_LDD image_missing=", paste(ldd_missing, collapse = " "),
      " mapped_by_shim=", paste(shimmed, collapse = " "),
      " (the image itself still lacks the package; install it for real with analyses_template/tools/word_image_fix.sh)\n",
      sep = "")
}
ldd_missing <- setdiff(ldd_missing, shimmed)
if (length(ldd_missing)) {
  so <- ldd_missing[1]
  cat("WORD_ENV_BROKEN pkg=ragg missing=", so, ' fix="', hint_for(so), '"\n', sep = "")
  cat("WORD_ENV_BROKEN_LDD ", paste(ldd_missing, collapse = " "), " (ldd ", ragg_so, ")\n", sep = "")
  cat("WORD_PREFLIGHT_STOP a missing system library is permanent: fix the image, do not resubmit ",
      "analysis jobs (each attempt costs a serial queue slot and renders nothing)\n", sep = "")
  quit(status = 1)
}

toolkit_dirs <- c(file.path(dir, ".pmx", "word-report"),
                  file.path(dir, "word-report"),
                  file.path(dir, ".pmx", "pmx_workspace", "word-report"),
                  Sys.glob(file.path(dir, ".pmx", "run_*", ".pmx", "word-report")))
has_generator <- file.exists(file.path(toolkit_dirs, "report_generator.R"))
has_style <- file.exists(file.path(toolkit_dirs, "reference.docx"))
complete_dirs <- toolkit_dirs[has_generator & has_style]
style_dirs <- toolkit_dirs[has_style]
if (length(complete_dirs)) {
  # Newest first: a study can have several finished mirrors and only the most recent one is the toolkit
  # its current artifacts were built with.
  style_dir <- complete_dirs[order(file.mtime(complete_dirs), decreasing = TRUE)][1]
  docx <- file.path(style_dir, "reference.docx")
  cat("WORD_STYLE_DIR ", docx, " (the directory report_generator.R runs from in that run)\n", sep = "")
} else {
  docx <- style_dirs
}
is_mirror <- file.exists(file.path(dir, ".pmx_staged")) || file.exists(file.path(dir, ".pmx_run_state"))
if (!length(docx)) {
  if (!is_mirror) {
    cat("WORD_STYLE_UNSTAGED reference.docx is not under ", dir, " -- expected: this is an analysis ",
        "directory, not a job mirror, and the wrapper stages word-report/ itself (with ",
        "report_narrative.json + report_metadata.dcf) into the job it submits. Do NOT mirror the toolkit ",
        "and do NOT submit a Word job by hand; run the study wrapper and read its STAGED / NEXT_STEP ",
        "line.\n", sep = "")
  } else {
    cat("WORD_STYLE_MISSING reference.docx not staged under ", dir,
        " (this is a job mirror, so word-report/ is incomplete: re-stage with analyses_template/tools/run_regression.sh, ",
        "not by hand)\n", sep = "")
    cat("WORD_PREFLIGHT_STOP no reference.docx: Word assembly has nothing to style from\n")
    quit(status = 1)
  }
}

completed <- c(Sys.glob(file.path(dir, ".pmx", "run_*", ".run_complete")),
               file.path(dir, ".run_complete"))
completed <- completed[file.exists(completed)]
if (length(completed)) {
  newest <- completed[order(file.mtime(completed), decreasing = TRUE)][1]
  cat("WORD_PREFLIGHT_REPEAT a run already completed without changing this environment (",
      newest, "): re-probing cannot change this result. To refresh only the .docx use the study ",
      "wrapper with --word-only (sh analyses_template/tools/run_er.sh <dir> --word-only); do not re-run the study ",
      "pipeline to answer a probe.\n", sep = "")
}

cat("WORD_ENV_OK r=", paste(R.version$major, R.version$minor, sep = "."),
    " jsonlite=", pkg_status[["jsonlite"]], " officer=", pkg_status[["officer"]],
    " flextable=", pkg_status[["flextable"]], " reference_docx=", docx[1],
    " shim=", if (length(shimmed)) paste(shimmed, collapse = ",") else "none", "\n", sep = "")
quit(status = 0)
