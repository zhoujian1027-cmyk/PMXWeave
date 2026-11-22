#!/usr/bin/env Rscript
stage_dir_of_self <- function() {
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) {
    p <- sub("^--file=", "", a[1])
    if (file.exists(file.path(dirname(p), "stage_lib.R")))
      return(dirname(normalizePath(p, winslash = "/", mustWork = TRUE)))
  }
  for (cand in c(Sys.getenv("STAGES_DIR", ""),
                 getwd(), file.path(getwd(), "stages"))) {
    if (nzchar(cand) && file.exists(file.path(cand, "stage_lib.R")))
      return(normalizePath(cand, winslash = "/", mustWork = TRUE))
  }
  stop("cannot locate stage_lib.R - put stages/ in the working directory or set STAGES_DIR",
       call. = FALSE)
}
d <- stage_dir_of_self()
`%||%` <- function(a, b) if (is.null(a)) b else a
Sys.unsetenv("PMX_ROOT"); Sys.unsetenv("PMX_LAYOUT")
ok <- TRUE
say <- function(...) cat(..., "\n", sep = "")

say("--- parse ---")
for (f in unique(c(list.files(d, pattern = "\\.R$", full.names = TRUE),list.files(dirname(d),pattern="\\.R$",full.names=TRUE)))) {
  r <- tryCatch({ parse(f); "OK" }, error = function(e) paste("PARSE ERROR:", conditionMessage(e)))
  if (r != "OK") ok <- FALSE
  say(sprintf("%-14s %s", basename(f), r))
}

say("\n--- gates and manifests ---")
old <- getwd(); t <- tempfile("selftest"); dir.create(t); setwd(t)
source(file.path(d, "stage_lib.R"))
writeLines("a\nb\n", "in1.txt"); writeLines("x\n", "out1.txt")
m <- manifest_write("s1", "in1.txt", "out1.txt", note = "selftest")
stopifnot(file.exists(m))
say("manifest written, ", nrow(manifest_read("s1")), " rows")
stopifnot(!stage_done("s1"))
e <- tryCatch({ stage_close("s2", "in1.txt", c("out1.txt", "nope.txt")); "NO ERROR" },
              error = function(e) conditionMessage(e))
say("missing output  -> ", e); if (e == "NO ERROR") ok <- FALSE
file.create("empty.txt")
e <- tryCatch({ stage_close("s2", "in1.txt", "empty.txt"); "NO ERROR" },
              error = function(e) conditionMessage(e))
say("empty output    -> ", e); if (e == "NO ERROR") ok <- FALSE
stage_close("s1", "in1.txt", "out1.txt")
stopifnot(stage_done("s1"))
invisible(stage_close("s1", "in1.txt", "out1.txt"))
say("gate after close: ", stage_done("s1"))
e <- tryCatch({ stage_require("s3", "s2"); "NO ERROR" }, error = function(e) conditionMessage(e))
say("missing gate    -> ", e); if (e == "NO ERROR") ok <- FALSE
say("intact gate     -> ", tryCatch({ stage_require("s2", "s1"); "OK (hashes match)" },
                                     error = function(e) conditionMessage(e)))
writeLines("tampered\n", "out1.txt")
e <- tryCatch({ stage_require("s2", "s1"); "NO ERROR" }, error = function(e) conditionMessage(e))
say("tampered hash   -> ", e); if (e == "NO ERROR") ok <- FALSE
stage_invalidate(); say("invalidate      -> gate present: ", stage_done("s1"))

say("\n--- driver ---")
dd <- file.path(t, "fam"); dir.create(dd)
writeLines("ID\n1\n", file.path(dd, "ppk_data.csv")); writeLines("$PK\n", file.path(dd, "base_model.ctl"))
r <- system2("Rscript", c(file.path(d, "run_stages.R"), shQuote(dd), "--status"), stdout = TRUE, stderr = TRUE)
if (!any(grepl("next stage: s1", r))) { ok <- FALSE; say("FAIL: --status did not point at s1") }
r <- system2("Rscript", c(file.path(d, "run_stages.R"), shQuote(dd), "--only", "s2"), stdout = TRUE, stderr = TRUE)
if (!any(grepl("needs gate\\(s\\) s1", r))) { ok <- FALSE; say("FAIL: --only s2 did not block on the missing s1 gate") }
if (!identical(attr(r, "status"), 1L)) { ok <- FALSE; say("FAIL: blocked stage did not exit 1") }
say("driver blocks a stage without its upstream gate: OK")
r <- system2("Rscript", c(file.path(d, "run_stages.R"), shQuote(dd), "--only", "bogus"), stdout = TRUE, stderr = TRUE)
if (!any(grepl("unknown stage", r))) { ok <- FALSE; say("FAIL: unknown stage not rejected") }
say("unknown stage rejected: OK")

say("\n--- shared fit template ---")
FIT_KNOBS <- c("FIT_FAM", "FIT_SEC", "FIT_CTL", "FIT_THETA", "FIT_ETA",
               "FIT_REFIT", "FIT_ENDPOINT", "FIT_PREP")
SHARED_FIT <- c("fit_setup.Rmd", "fit_core.Rmd", "fit_tail.Rmd")
CORE_KNOBS <- c("FIT_CTL", "FIT_THETA", "FIT_ETA", "FIT_REFIT", "FIT_ENDPOINT", "FIT_PREP")
TAIL_KNOBS <- c("FIT_FAM", "FIT_SEC")
uses_knob <- function(lines, k)
  any(grepl(paste0("(^|[^A-Za-z0-9_.])", k, "([^A-Za-z0-9_.]|$)"), lines))
read_shared <- function(s) {
  f <- file.path(at, "_shared", s)
  if (file.exists(f)) readLines(f, warn = FALSE) else character(0)
}
find_analyses_template <- function() {
  for (p in c(Sys.getenv("PMX_ANALYSES_TEMPLATE", ""),
              file.path(d, "..", "..", "analyses_template"),
              file.path(getwd(), "analyses_template"),
              file.path(getwd(), "..", "analyses_template"))) {
    if (nzchar(p) && dir.exists(p) && dir.exists(file.path(p, "_shared")))
      return(normalizePath(p))
  }
  ""
}
at <- find_analyses_template()
if (!nzchar(at)) {
  say("SKIP analyses_template/_shared/ is not reachable from ", d)
} else {
  sec4 <- TRUE
  say("template root: ", at)
  for (s in SHARED_FIT) if (!length(read_shared(s))) {
    sec4 <- FALSE; say("FAIL missing shared chunk: _shared/", s)
  }
  if (!setequal(c(CORE_KNOBS, TAIL_KNOBS), FIT_KNOBS)) {
    sec4 <- FALSE
    say("FAIL the core/tail knob lists do not add up to the contract; unaccounted: ",
        paste(setdiff(FIT_KNOBS, c(CORE_KNOBS, TAIL_KNOBS)), collapse = " "))
  }
  for (s in c("fit_core.Rmd", "fit_tail.Rmd")) {
    l <- read_shared(s); if (!length(l)) next
    want <- if (s == "fit_core.Rmd") CORE_KNOBS else TAIL_KNOBS
    miss <- want[!vapply(want, function(k) uses_knob(l, k), logical(1))]
    if (length(miss)) {
      sec4 <- FALSE; say("FAIL _shared/", s, " never uses knob(s): ", paste(miss, collapse = " "))
    } else say("_shared/", s, " consumes ", paste(want, collapse = " "), ": OK")
  }
  fams <- c("ppk", "pkpd", "tmdd"); seen <- 0L
  for (fam in fams) {
    f <- file.path(at, fam, paste0(fam, "_fit.Rmd"))
    if (!file.exists(f)) { sec4 <- FALSE; say("FAIL missing family fit notebook: ", fam, "_fit.Rmd"); next }
    seen <- seen + 1L
    l <- readLines(f, warn = FALSE)
    assigned <- sub("^[[:space:]]*([A-Za-z0-9_.]+)[[:space:]]*<-.*$", "\\1", l)
    assigned <- assigned[grepl("^[A-Za-z0-9_.]+$", assigned)]
    miss <- setdiff(FIT_KNOBS, assigned)
    if (length(miss)) {
      sec4 <- FALSE; say("FAIL ", fam, "_fit.Rmd does not define: ", paste(miss, collapse = " "))
    }
    for (s in SHARED_FIT) {
      if (!any(grepl(paste0("pmx_shared(\"", s, "\")"), l, fixed = TRUE))) {
        sec4 <- FALSE; say("FAIL ", fam, "_fit.Rmd does not knit_child() ", s)
      }
    }
    if (any(grepl("```{r fit-model", trimws(l), fixed = TRUE))) {
      sec4 <- FALSE
      say("FAIL ", fam, "_fit.Rmd still carries its own fit-model chunk - the shared core owns it")
    }
  }
  if (!seen) { sec4 <- FALSE; say("FAIL no family fit notebook found under ", at) }
  else if (sec4) say(seen, " family fit notebooks share one core and declare the same ",
                     length(FIT_KNOBS), " knobs: OK")
  if (!sec4) ok <- FALSE
}

setwd(old); unlink(t, recursive = TRUE)
say("\n=== SELFTEST ", if (ok) "PASSED" else "FAILED", " ===")
quit(status = if (ok) 0 else 1)
