#!/usr/bin/env Rscript
.cpu_script <- sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
.cpu_path <- file.path(if(!is.na(.cpu_script)) dirname(.cpu_script) else dirname(Sys.getenv("STAGES_DIR")),"cpu_budget.R")
if (!file.exists(.cpu_path)) stop("PMX_CPU_TOOLKIT_REQUIRED: complete word-report/cpu_budget.R required")
source(.cpu_path)
pmx_cpu_setup()
suppressPackageStartupMessages({
  library(nlmixr2); library(rxode2); library(dplyr)
})
pmx_cpu_setup(rx=TRUE)

`%||%` <- function(a, b) if (is.null(a)) b else a

script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) {
    d <- normalizePath(dirname(sub("^--file=", "", m[1])))
    if (dir.exists(file.path(d, "family"))) return(d)
  }
  for (d in c(getwd(), file.path(getwd(), "scripts"),
              file.path(getwd(), "..", "scripts"),
              file.path(getwd(), "word-report"),
              file.path(getwd(), "..", "word-report"))) {
    if (dir.exists(file.path(d, "family"))) return(normalizePath(d))
  }
  normalizePath(getwd())
}

ARGS_ <- commandArgs(trailingOnly = TRUE)
PHASE <- "search"
.pi <- which(ARGS_ == "--phase")
if(length(.pi)) { PHASE <- ARGS_[.pi[1]+1L]; ARGS_ <- ARGS_[-c(.pi[1],.pi[1]+1L)] }
if(!PHASE %in% c("search","covariance")) stop("--phase must be search or covariance")
FRESH <- "--fresh" %in% ARGS_
ARGS_ <- setdiff(ARGS_, "--fresh")
if(FRESH && PHASE=="covariance") stop("Covariance-only must preserve the search caches; --fresh is forbidden")
FAM_ARG <- NULL
fi <- which(ARGS_ == "--family")
if (length(fi)) { FAM_ARG <- ARGS_[fi[1] + 1]; ARGS_ <- ARGS_[-c(fi[1], fi[1] + 1)] }
SD     <- script_dir()
if (length(ARGS_)) setwd(ARGS_[1])
FAMDIR <- file.path(SD, "family")
source(file.path(SD,"scm_parallel.R"))
if (!dir.exists(FAMDIR)) stop("no family/ folder next to ", file.path(SD, "run_pipeline.R"))
families <- sub("_model\\.R$", "", basename(list.files(FAMDIR, pattern = "_model\\.R$")))
if (!length(families)) stop("no family/*_model.R found in ", FAMDIR)

if (is.null(FAM_ARG)) {
  hit <- character(0)
  for (f in families) {
    e <- new.env()
    ok <- tryCatch({ sys.source(file.path(FAMDIR, paste0(f, "_model.R")), envir = e); TRUE },
                   error = function(e) FALSE)
    if (ok && file.exists(e$MODEL$data_csv)) hit <- c(hit, f)
  }
  if (!length(hit))
    stop("cannot tell which family this directory holds (no <id>_data.csv for ",
         paste(families, collapse = "|"), "); pass --family")
  FAM_ARG <- hit[1]
  if (length(hit) > 1) cat("note: several families match this directory, using '",
                           FAM_ARG, "' (pass --family to choose)\n", sep = "")
}
if (!FAM_ARG %in% families)
  stop("unknown family '", FAM_ARG, "'; available: ", paste(families, collapse = ", "))
source(file.path(FAMDIR, paste0(FAM_ARG, "_model.R")))     # defines MODEL

pmx_resolve <- function(p) {
  p <- as.character(p)[1]
  if (is.na(p) || !nzchar(p) || file.exists(p)) return(p)
  root <- Sys.getenv("PMX_ROOT", "")
  if (!nzchar(root)) return(p)
  hit <- file.path(root, p)
  if (file.exists(hit)) hit else p
}
MODEL$data_csv <- pmx_resolve(Sys.getenv("PMX_DATA", MODEL$data_csv))
MODEL$model_ctl <- pmx_resolve(MODEL$model_ctl)

req <- c("id", "data_csv", "model_ctl", "read_data", "build", "fit", "candidates",
         "refs", "ref_units", "typical", "labels", "residual", "output")
miss <- req[!vapply(req, function(f) !is.null(MODEL[[f]]), logical(1))]
if (length(miss)) stop("family/", FAM_ARG, "_model.R does not define MODEL$",
                       paste(miss, collapse = ", "))

theta_block <- function(lines) {
  i <- grep("^\\s*\\$THETA", lines, ignore.case = TRUE)
  if (!length(i)) stop("the control stream has no $THETA block")
  after <- lines[(i[1] + 1L):length(lines)]
  stop_at <- which(grepl("^\\s*\\$", after))
  if (length(stop_at)) seq(i[1] + 1L, i[1] + stop_at[1] - 1L) else seq(i[1] + 1L, length(lines))
}
theta_count <- function(lines) sum(nzchar(trimws(sub(";.*$", "", lines[theta_block(lines)]))))
theta_append <- function(lines, extra) {
  if (!length(extra)) return(lines)
  blk <- theta_block(lines)
  c(lines[seq_len(max(blk))], extra, if(max(blk)<length(lines)) lines[seq.int(max(blk)+1L,length(lines))] else character(0))
}

# An appended effect starts at 0 unless the current model already carries a fitted value for
# the same effect name (warm start), so a step-2 candidate keeps the step-1 estimate.
cov_start <- function(type, nm = NULL) {
  if (!is.null(nm) && exists("START_EFFECTS", inherits = TRUE)) {
    starts <- get("START_EFFECTS", inherits = TRUE)
    key <- tolower(nm)   # fitted names are lower-cased; the appended THETA name keeps the model case
    if (is.numeric(starts) && length(starts) && key %in% names(starts) && is.finite(starts[[key]]))
      return(pmx_ctl_number(starts[[key]]))
  }
  switch(type,
    power  = "0",
    expo   = "0",
    linear = "0",
    cat    = "0",
    stop("unknown covariate effect type: ", type))
}

nonmem_add_cov <- function(lines, effects) {
  lines <- pmx_expand_records(lines)
  lines <- lines[seq_len(length(lines))]
  nxt <- theta_count(lines); extra <- character(0); nmv <- character(0)
  for (p in names(effects)) {
    terms <- character(0)
    for (e in effects[[p]]) {
      valid_number <- function(x) is.numeric(x) && length(x)==1L && is.finite(x)
      if(!e$type %in% c("power","expo","linear","cat")) stop("SCM_EFFECT_INVALID: unsupported effect type")
      if(e$type=="cat") {
        if(!valid_number(e$level)) stop("SCM_EFFECT_INVALID: category level must be finite for ",e$cov)
      } else {
        if(!valid_number(e$ref) || (e$type=="power" && e$ref<=0))
          stop("SCM_EFFECT_INVALID: finite reference required (positive for power): ",e$cov)
        if(!is.null(e$exp) && (!valid_number(e$exp) || e$type!="power"))
          stop("SCM_EFFECT_INVALID: fixed exponent must be a finite number for a power effect: ",e$cov)
      }
      nm <- sprintf("theta_%s_%s%s", sub("^TV", "", p), tolower(e$cov),
                    if (identical(e$type, "cat")) e$level else "")
      add_theta <- function() {
        nxt <<- nxt + 1L
        b <- cov_start(e$type, nm)
        extra <<- c(extra, sprintf("%s ; THETA(%d) %s",b,nxt,nm))
        nmv <<- c(nmv, nm); nxt
      }
      terms <- c(terms, switch(e$type,
        power = if (is.null(e$exp)) sprintf(" * (%s/%g)**THETA(%d)", e$cov, e$ref, add_theta())
                else sprintf(" * (%s/%g)**%g", e$cov, e$ref, e$exp),
        expo = sprintf(" * EXP(THETA(%d)*(%s - %g))", add_theta(), e$cov, e$ref),
        linear = sprintf(" * (1 + THETA(%d)*(%s - %g))", add_theta(), e$cov, e$ref),
        cat = sprintf(" * (1 + THETA(%d)*(%s.EQ.%g))", add_theta(), e$cov, e$level),
        stop("unknown covariate effect type: ", e$type)))
    }
    hit <- grep(sprintf("^\\s*%s\\s*=\\s*THETA\\([0-9]+\\)", p), lines, value = TRUE)
    if (!length(hit)) stop(sprintf(
      "the control stream has no '%s = THETA(k)' line in $PK, so no covariate effect can be tested on %s",
      p, p))
    matched <- regmatches(hit[1],regexec("^\\s*[A-Za-z0-9_]+\\s*=\\s*THETA\\(([0-9]+)\\)",hit[1]))[[1]]
    k <- as.integer(matched[2])
    i <- grep(sprintf("^\\s*%s\\s*=\\s*THETA\\(%d\\)", p, k), lines)[1]
    lines[i] <- sub(sprintf("THETA\\(%d\\)", k),
                    paste0("THETA(", k, ")", paste(terms, collapse = "")), lines[i])
  }
  list(lines = theta_append(lines, extra), extra = extra, names = nmv)
}

source(file.path(SD, "..", "analyses_template","tools", "model_contract.R"))
if(tolower(Sys.getenv("PMX_EST","focei"))!="focei") stop("FIT_ESTIMATION_METHOD_MISMATCH: screening/SCM require FOCEI throughout")
MODEL <- pmx_configure_model(MODEL, MODEL$model_ctl, MODEL$data_csv)
if (FRESH) unlink("_scm_sel_cache", recursive = TRUE)
dir.create("_scm_sel_cache", showWarnings = FALSE)
stopifnot(file.exists(MODEL$data_csv))
cat(sprintf("=== FAMILY: %s (%s) ===\n", MODEL$id, MODEL$data_csv))

D <- MODEL$read_data(MODEL$data_csv)

REF <- MODEL$refs

tagof <- function(lab, state = "") paste0("cand_", gsub("[^A-Za-z0-9]", "", lab),
                                          if (nzchar(state)) paste0("__", state) else "")

# Report edits retain search caches; covariance has its own post-fit contract.
FIT_CONTRACT_FILE <- file.path(SD, "fit_contract.md5")
FIT_CONTRACT <- local({
  live <- unname(tools::md5sum(c(file.path(SD, "run_pipeline.R"),
                                file.path(SD, "..", "analyses_template","tools", "model_contract.R"),
                                file.path(SD, "..", "analyses_template","tools", "data_filters.R"))))
  v <- if (file.exists(FIT_CONTRACT_FILE)) readLines(FIT_CONTRACT_FILE, warn = FALSE) else character(0)
  if (length(v) != length(live)) {
    cat("FIT_CONTRACT ", FIT_CONTRACT_FILE, " missing or malformed - writing the live one\n", sep = "")
    writeLines(live, FIT_CONTRACT_FILE); live
  } else v
})
COV_PRIMARY <- Sys.getenv("PMX_COV_METHOD", "s")
COV_METHOD <- COV_PRIMARY

# Start real work only when the remaining job budget can hold it.
T0 <- Sys.time()
elapsed <- function() as.numeric(difftime(Sys.time(), T0, units = "secs"))
JOB_BUDGET <- local({
  stage <- suppressWarnings(as.numeric(Sys.getenv("PMX_STAGE_TIMEOUT","780")))
  worker <- suppressWarnings(as.numeric(Sys.getenv("PMX_WORKER_TIMEOUT_S","900")))
  headroom <- suppressWarnings(as.numeric(Sys.getenv("PMX_HEADROOM_S","120")))
  requested <- suppressWarnings(as.numeric(Sys.getenv("PMX_SCM_BUDGET_S",as.character(stage))))
  deadline <- Sys.getenv("PMX_STAGE_DEADLINE","")
  remaining <- if(nzchar(deadline)) suppressWarnings(as.numeric(deadline))-as.numeric(Sys.time()) else Inf
  safe <- pmx_scm_window(stage,worker,headroom,requested,remaining)
  cat(sprintf("SCM_BUDGET window=%.0fs stage=%.0fs worker=%.0fs cleanup=%.0fs (reserved once)\n",safe,stage,worker,headroom))
  safe
})
MIN_FIT_EXPLICIT <- nzchar(Sys.getenv("PMX_MIN_FIT_S", ""))
MIN_FIT_S <- suppressWarnings(as.numeric(Sys.getenv("PMX_MIN_FIT_S", "240")))
if(!is.finite(MIN_FIT_S) || MIN_FIT_S<=0) stop("SCM_BUDGET_INVALID: PMX_MIN_FIT_S must be positive")
MIN_COV_FIT_S <- suppressWarnings(as.numeric(Sys.getenv("PMX_MIN_COV_FIT_S", "0.9")))
# Learn the search-fit cost from completed work.
OBS_FIT_S <- suppressWarnings(as.numeric(Sys.getenv("PMX_FIT_S_EST", "0")))
if (!is.finite(OBS_FIT_S) || OBS_FIT_S < 0) OBS_FIT_S <- 0
# Unknown work keeps the conservative cold start. Learned cost gets 25% headroom;
# an explicit user floor is always honored. The worker/stage ceilings stay unchanged.
fit_need <- function(threads=pmx_fit_threads()) {
  key <- as.character(threads)
  cost <- if(key %in% names(OBS_FIT_TIMES)) OBS_FIT_TIMES[[key]] else if(length(OBS_FIT_TIMES))
    max(OBS_FIT_TIMES*pmx_fit_speed(as.numeric(names(OBS_FIT_TIMES)))/pmx_fit_speed(threads)) else
    OBS_FIT_S*pmx_fit_speed(pmx_fit_threads())/pmx_fit_speed(threads)
  if(cost>0) max(if(MIN_FIT_EXPLICIT) MIN_FIT_S else 60,1.25*cost) else MIN_FIT_S
}
OBS_FIT_WORK <- 0 # Legacy telemetry only; core-seconds no longer predict linear scaling.
OBS_FIT_TIMES <- numeric(0)
FIT_TIMING_KEY <- NULL
.st <- NULL
STATE_FILE <- file.path("_scm_sel_cache", "scm_state.rds")
st_chosen <- character(0); st_added <- list(); st_phase <- "search"; n_new_fits <- 0L
# Search replay reuses content-keyed fits; this record identifies the remaining phase.
if (file.exists(STATE_FILE)) {
  .st <- tryCatch(readRDS(STATE_FILE), error = function(e) NULL)
  if (is.list(.st))
    cat(sprintf("SCM_STATE_RESUME phase=%s chosen=%s written=%s\n", .st$phase %||% "?",
                if (length(.st$chosen)) paste(.st$chosen, collapse = "; ") else "none",
                format(.st$time %||% NA)))
}
defer <- function(what) {
  dir.create("_scm_sel_cache", showWarnings = FALSE)
  pmx_scm_save_state(list(phase = what, chosen = st_chosen, added = st_added, new_fits = n_new_fits,
               budget = JOB_BUDGET, elapsed = elapsed(), time = Sys.time(),
               fit_timing=list(key=FIT_TIMING_KEY,host=pmx_cpu_timing_host(),seconds=OBS_FIT_S,core_seconds=OBS_FIT_WORK,thread_seconds=OBS_FIT_TIMES)), STATE_FILE)
  cat(sprintf(paste0("\nSCM_DEFER %s: %.0fs of the %.0fs job budget used, %d fit(s) cached this job.",
                     "\n  state saved to %s; the chain resume is a plain re-run of the same command",
                     " - every finished fit is reused, no work is repeated.\n"),
              what, elapsed(), JOB_BUDGET, n_new_fits, STATE_FILE))
  quit(save = "no", status = 3)
}
budget_guard <- function(tag, cov) {
  need <- if(isTRUE(cov)) MIN_COV_FIT_S*JOB_BUDGET else fit_need()
  pmx_scm_admit(need,JOB_BUDGET-elapsed(),JOB_BUDGET,defer,tag)
}

# Preserve valid cov=FALSE search keys across this covariance-only interface repair.
# Covariance keys retain the new body, so old mislabeled covariance caches are not reused.
search_fit_body <- function(x) {
  if(is.symbol(x) && identical(as.character(x),"cov_method")) return("s")
  if(is.call(x)) return(as.call(lapply(as.list(x),search_fit_body)))
  x
}
fit_key <- function(effects, cov) {
  x <- list(contract=if(isTRUE(cov)) 3L else 2L, data=unname(tools::md5sum(MODEL$data_csv)),
    ctl=unname(tools::md5sum(MODEL$model_ctl)), effects=effects,
    cov=if (isTRUE(cov)) COV_METHOD else FALSE,          # FALSE keeps every search fit's key as it was
    model=paste(deparse(if(isTRUE(cov)) body(MODEL$fit) else search_fit_body(body(MODEL$fit))),collapse="\n"),
    start=if(length(effects)) START_MODE else "authored",
    code=FIT_CONTRACT,
    settings=Sys.getenv(c("PMX_EST","PMX_ENDPOINT","PMX_DVID","PMX_RESID_INIT","PMX_CMT_OBS")),endpoint=pmx_endpoint(MODEL$model_ctl),refs=REF,
    runtime=vapply(c("nlmixr2","rxode2","nonmem2rx",if(isTRUE(cov)) "nlmixr2est"),function(p) as.character(packageVersion(p)),""))
  if (length(effects)) x$base_fit <- FIT_BASE_ID
  policy <- pmx_endpoint_policy(MODEL$model_ctl)
  if(!is.null(policy)) x$endpoint_policy <- policy
  rlang::hash(x)
}
cache_file <- function(key,tag="fit",cov=FALSE,failure=FALSE) {
  suffix <- if(failure) ".failure.rds" else ".rds"
  legacy <- file.path("_scm_sel_cache",paste0(key,suffix))
  if(file.exists(legacy)) return(legacy)
  named <- list.files("_scm_sel_cache",full.names=TRUE)
  named <- named[endsWith(basename(named),paste0("__",key,suffix))]
  if(length(named)) return(sort(named)[1])
  label <- paste(FAM_ARG,sub("\\.ctl$","",basename(MODEL$model_ctl)),
                 if(cov) paste0("cov_",COV_METHOD) else "scm",tag,sep="_")
  label <- substr(gsub("[^A-Za-z0-9_-]+","_",label),1,100)
  file.path("_scm_sel_cache",paste0(label,"__",key,suffix))
}
fit_cached <- function(key) {
  cache <- cache_file(key); keyfile <- paste0(cache, ".key")
  file.exists(cache) && file.exists(keyfile) && identical(readLines(keyfile, warn = FALSE), key)
}
fit_failures <- list()
# Per-tag record of an estimates-only covariance continuation. Declared with the other run
# state because fitm() is first called by the search phase, before the covariance helpers below.
COV_UNESTIMABLE <- list()
# Warm start for every post-base fit. Cold refits from the authored .ctl initials cost a whole
# job window each and land in different local optima, which makes a likelihood comparison
# between the current model and a candidate meaningless (and the search never finishes).
START_MODE <- "warm_v1"
START_CTL <- NULL
# Fitted identity of the accepted base fit. Candidate fits are only comparable to the base they
# were warm-started from, so it enters their cache key (a repaired/re-centred base invalidates
# stale candidate fits instead of comparing old objectives against a new base).
FIT_BASE_ID <- NULL
START_EFFECTS <- numeric(0)
# Per-fit optimizer warnings, captured so a fit that stopped before a minimum is visible in the
# log line for that fit instead of appearing only in the trailing "Warning messages:" block.
FIT_WARNINGS <- list()
warm_from <- function(fit, tag) {
  # written in the run directory next to _scm_sel_cache/, never into the toolkit tree
  START_CTL <<- pmx_warm_ctl(MODEL$model_ctl, fit, dir = getwd())
  fe <- fixef(fit)
  nmv <- tolower(sub("^t[.]", "", names(fe)))
  START_EFFECTS <<- stats::setNames(as.numeric(fe), nmv)[grepl("^theta_", nmv)]
  cat(sprintf("SCM_WARM_START from=%s thetas=%d effects=%d ctl=%s\n", tag, length(fe),
              length(START_EFFECTS), basename(START_CTL)))
  invisible(START_CTL)
}
# A FOCEI solution can stop in a shallow optimum where a multiplicative typical value stays at
# its authored initial estimate while the corresponding EBEs absorb the difference (mean ETA
# materially non-zero). Population predictions are then biased - for a PD/turnover endpoint this
# shows up as systematic PD under-prediction and upward-shifted CWRES - even though the optimizer
# reports a normal exit. Re-centre those typical values by exp(mean ETA), refit once from that
# start and keep the better objective. Disable with PMX_PLATEAU_RECENTRE=false.
PLATEAU_RECENTRE <- !grepl("^(false|0|no|off)$", tolower(Sys.getenv("PMX_PLATEAU_RECENTRE", "true")))
PLATEAU_ETA_MEAN <- suppressWarnings(as.numeric(Sys.getenv("PMX_PLATEAU_ETA_MEAN", "0.25")))
if (!is.finite(PLATEAU_ETA_MEAN)) PLATEAU_ETA_MEAN <- 0.25

# theta name <-> eta index from the authored $PK, for multiplicative IIV (P = TVP * EXP(ETA(n))).
plateau_theta_eta <- function(ctl) {
  pk <- ctl_body(ctl, "PK"); if (!length(pk)) return(NULL)
  rows <- list()
  for (l in pk) {
    m <- regmatches(l, regexec("^[[:space:]]*[A-Za-z][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(TV[A-Za-z0-9_]*)[[:space:]]*[*][[:space:]]*EXP[(][[:space:]]*ETA[(][[:space:]]*([0-9]+)[[:space:]]*[)][[:space:]]*[)]", l, ignore.case = TRUE))[[1]]
    if (length(m) == 3L) rows[[length(rows) + 1L]] <- data.frame(theta = m[2], eta = as.integer(m[3]),
      stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(NULL)
  rows <- unique(do.call(rbind, rows)); rows[order(rows$eta), , drop = FALSE]
}

pmx_plateau_fit <- function(fit, tag, data) {
  none <- list(fit = fit, refit = FALSE)
  if (!PLATEAU_RECENTRE || is.null(fit) || !inherits(fit, "nlmixr2FitCore")) return(none)
  if (is.null(fit$eta) || !length(fit$eta)) return(none)
  eta_cols <- grep("^eta[0-9]+$", names(fit$eta), value = TRUE)
  if (!length(eta_cols)) return(none)
  mu <- vapply(fit$eta[eta_cols], mean, numeric(1), na.rm = TRUE)
  if (!any(abs(mu) > PLATEAU_ETA_MEAN)) return(none)
  pairs <- tryCatch(plateau_theta_eta(MODEL$model_ctl), error = function(e) NULL)
  if (is.null(pairs) || !nrow(pairs)) return(none)
  fe <- fixef(fit); upd <- list(); shifted <- character(0)
  for (i in seq_len(nrow(pairs))) {
    n <- pairs$eta[i]
    if (n > length(mu) || !is.finite(mu[n]) || abs(mu[n]) <= PLATEAU_ETA_MEAN) next
    want <- c(paste0("t.", pairs$theta[i]), paste0("theta_", pairs$theta[i]), pairs$theta[i])
    nm <- want[want %in% names(fe)]
    if (!length(nm)) nm <- grep(paste0("^(t[.]|theta_)?", pairs$theta[i], "$"), names(fe), value = TRUE, ignore.case = TRUE)
    if (!length(nm)) next
    upd[[paste0("t.", pairs$theta[i])]] <- fe[[nm[1]]] * exp(mu[n])
    shifted <- c(shifted, sprintf("%s=%.4f (mean eta %+.3f)", pairs$theta[i], upd[[length(upd)]], mu[n]))
  }
  if (!length(upd)) return(none)
  cat("FIT_PLATEAU_RECENTRE ", tag, ": population typical values stuck while EBEs absorb the offset (",
      paste(shifted, collapse = ", "), "); refitting once from re-centred starts\n", sep = "")
  ui2 <- tryCatch(do.call(nlmixr2est::ini, c(list(fit$ui), upd)), error = function(e) NULL)
  if (is.null(ui2)) { cat("FIT_PLATEAU_SKIP ", tag, ": cannot re-centre the translated model\n", sep = ""); return(none) }
  got <- tryCatch({
    warn <- character(0)
    r <- withCallingHandlers(MODEL$fit(ui2, pmx_endpoint_data(ui2, data), cov = FALSE),
      warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") })
    list(fit = r, warnings = warn)
  }, error = function(e) list(fit = NULL, error = conditionMessage(e)))
  if (is.null(got$fit) || !is.finite(got$fit$objf)) {
    cat("FIT_PLATEAU_SKIP ", tag, ": re-centred refit failed (", got$error, "); keeping the original fit\n", sep = "")
    return(none)
  }
  if (!(got$fit$objf < fit$objf - 0.5)) {
    cat(sprintf("FIT_PLATEAU_REJECTED %s: re-centred refit OBJF %.6f did not improve on %.6f; keeping the original fit\n",
                tag, got$fit$objf, fit$objf))
    return(none)
  }
  cat(sprintf("FIT_PLATEAU_KEPT %s: OBJF %.6f -> %.6f with re-centred starts\n", tag, fit$objf, got$fit$objf))
  attr(got$fit, "pmx_fit_warnings") <- got$warnings
  list(fit = got$fit, refit = TRUE)
}

brief_fit_failure <- function(message) {
  if (grepl("converg", message, ignore.case = TRUE)) return("Model did not converge")
  if (grepl("non.?finite|nan|infinite", message, ignore.case = TRUE)) return("Non-finite estimates")
  if (grepl("singular|hessian|covariance", message, ignore.case = TRUE)) return("Covariance not estimable")
  if (grepl("timeout|timed out|time limit", message, ignore.case = TRUE)) return("Fit timed out")
  "Model fitting failed"
}
screen_base_fit <- function() {
  root <- Sys.getenv("PMX_ROOT",dirname(normalizePath(MODEL$model_ctl)))
  if(!nzchar(root)) root <- dirname(normalizePath(MODEL$model_ctl))
  ledger <- file.path(root,".pmx","ladder_round.json")
  if(!file.exists(ledger)) return(NULL) # An independently authored base is fitted once.
  round <- jsonlite::fromJSON(ledger,simplifyVector=FALSE)
  reject <- function(reason) stop("SCM_SCREEN_BASE_MISMATCH: ",reason,"; preserve screen fits, do not create a promoted candidate or refit automatically")
  if(!identical(round$state,"complete")) reject("screening/export is not complete")
  if(!identical(round$inputs$data,unname(tools::md5sum(MODEL$data_csv))) ||
     !identical(round$base_md5,unname(tools::md5sum(MODEL$model_ctl))) ||
     !identical(round$inputs$configuration$family,FAM_ARG)) reject("data, family or published base changed")
  cmt <- Sys.getenv("PMX_CMT_OBS","auto");if(!nzchar(cmt)) cmt <- "auto"
  if(!identical(round$inputs$configuration$cmt,cmt)) reject("observation-compartment configuration differs")
  choice <- read.dcf(file.path(root,"base_selection.dcf"))
  candidate <- basename(choice[1,"Candidate"])
  pairs <- Filter(function(p) identical(p[[1]],candidate),round$inputs$models)
  if(length(pairs)!=1L) reject("selected candidate is not in the completed round")
  dirs <- c(file.path(root,"01_screen"),root)
  ctl <- file.path(dirs,candidate);ctl <- ctl[file.exists(ctl)][1]
  fitfile <- sub(".ctl$",".fit.rds",ctl);keyfile <- sub(".rds$",".key",fitfile)
  if(is.na(ctl) || !file.exists(fitfile) || !file.exists(keyfile) ||
     !identical(pairs[[1]][[2]],unname(tools::md5sum(ctl)))) reject("candidate or fitted cache missing/changed")
  key <- readLines(keyfile,n=1L,warn=FALSE)
  parts <- if(length(key)==1L) strsplit(key,"|",fixed=TRUE)[[1]] else character()
  if(length(parts)!=10L || !parts[1] %in% c("FIT2","FIT3")) reject("cache key schema unsupported")
  ep <- pmx_endpoint(ctl)
  expected <- c(pairs[[1]][[2]],paste0(round$inputs$data,":",file.size(MODEL$data_csv)),
    as.character(rlang::hash(paste(ep$lines,collapse="|"))))
  if(!identical(parts[2:4],expected)) reject("candidate/data/endpoint fingerprint differs")
  if(parts[7]!=cmt) reject("cached observation-compartment setting differs")
  if(parts[8]!=pmx_screen_contract(ctl)) reject("scientific data/model/endpoint helper contract differs")
  if(!identical(round$inputs$configuration$fixed,Sys.getenv("PMX_FIXED_APPROVED","")))
    reject("explicit fixed-parameter approval differs")
  if(!identical(round$inputs$configuration$endpoint,Sys.getenv("PMX_ENDPOINT","")))
    reject("endpoint override differs")
  meta <- round$selected
  if(is.null(meta) || !identical(meta$candidate,candidate) || !identical(meta$fit_key,key) ||
     !identical(meta$fit_md5,unname(tools::md5sum(fitfile)))) reject("selected-fit fingerprint missing/changed")
  controls <- pmx_screen_controls()
  settings <- pmx_screen_settings(controls$CTL,controls$RX)
  if(parts[1]=="FIT3") {
    if(parts[5]!="1" || parts[10]!=pmx_screen_recipe) reject("scientific fitting recipe differs")
    stored <- readLines(keyfile,n=2L,warn=FALSE)
    if(length(stored)!=2L || is.null(meta$settings)) reject("named estimator settings missing")
    recorded <- jsonlite::fromJSON(stored[2],simplifyVector=FALSE)
    if(!identical(pmx_screen_digest(recorded),parts[9]) ||
       !identical(pmx_screen_digest(meta$settings),parts[9])) reject("named settings fingerprint changed")
    difference <- pmx_screen_difference(recorded,settings)
    if(nzchar(difference)) reject(paste("estimator setting differs:",difference))
  } else {
    # The version belongs to the fit producer, not today's ladder script.
    if(parts[5]!=as.character(round$inputs$runtime$version)) reject("legacy producer version differs from ledger")
    rx <- controls$RX;rx[intersect(names(rx),"cores")] <- NULL
    raw_control <- as.character(rlang::hash(list(CTL=controls$CTL,RX=rx,packages=vapply(
      c("nlmixr2","nlmixr2est","rxode2","nonmem2rx"),function(p) as.character(packageVersion(p)),""))))
    if(parts[9]!=raw_control) reject(paste0("LEGACY_SETTINGS_UNVERIFIABLE: old cache has only an opaque hash (recorded=",
      parts[9],", current=",raw_control,"); no named settings to verify. Stop; do not guess core counts/package versions or submit diagnostic/refit jobs"))
  }
  f <- readRDS(fitfile)
  if(!is.finite(f$objf) || any(!is.finite(fixef(f))) ||
     (is.numeric(f$convergence) && any(!is.finite(f$convergence) | f$convergence!=0))) reject("selected fit is not eligible")
  pmx_screen_bic(f)
  cat("SCM_BASE_SCREEN_REUSED ",candidate,"; no parameter re-estimation\n",sep="")
  f
}

fitm <- function(effects, tag, cov = FALSE) {
  if(is.null(FIT_TIMING_KEY)) {
    FIT_TIMING_KEY <<- fit_key(list(),FALSE)
    timing <- if(is.list(.st)) .st$fit_timing else NULL
    if(is.list(timing) && identical(timing$key,FIT_TIMING_KEY) &&
       identical(timing$host,pmx_cpu_timing_host()) &&
       is.numeric(timing$seconds) && length(timing$seconds)==1L &&
       is.finite(timing$seconds) && timing$seconds>0) {
      OBS_FIT_S <<- max(OBS_FIT_S,timing$seconds)
      core_seconds <- timing$core_seconds
      OBS_FIT_WORK <<- if(is.numeric(core_seconds) && length(core_seconds)==1L &&
        is.finite(core_seconds) && core_seconds>0) core_seconds else OBS_FIT_S*pmx_cpu_budget()
      by_thread <- timing$thread_seconds
      keys <- suppressWarnings(as.numeric(names(by_thread)))
      if(is.numeric(by_thread) && length(by_thread) && length(keys)==length(by_thread) &&
         !anyDuplicated(names(by_thread)) && all(is.finite(keys) & keys>=1 & keys<=32 & keys==floor(keys)) &&
         all(is.finite(by_thread) & by_thread>0)) OBS_FIT_TIMES <<- by_thread
      cat(sprintf("SCM_TIMING_REUSED observed_max=%.0fs reserve=%.0fs; same fitted-work identity\n",OBS_FIT_S,fit_need()))
    }
  }
  if(isTRUE(cov)) COV_METHOD <<- COV_PRIMARY
  key <- fit_key(effects, cov)
  # Starts are counted per fit key/method inside cov_ladder(), which may try the
  # primary method up to PMX_COV_TRIES times and then the fallback method, instead
  # of stopping the stage after a single post-fit attempt.
  cache <- cache_file(key,tag,cov)
  keyfile <- paste0(cache,".key")
  fit_failures[[tag]] <<- NULL
  # Estimates-only continuation is tracked per tag so no fit object is mutated.
  COV_UNESTIMABLE[[tag]] <<- NULL
  if (fit_cached(key)) {
    cached <- readRDS(cache)
    pmx_require_fit_quality(cached,paste("cached",tag))
    if(!isTRUE(cov) && identical(tag,"base")) {
      FIT_BASE_ID <<- sprintf("%.6f", cached$objf)
      repaired <- pmx_plateau_fit(cached, tag, D)
      if (isTRUE(repaired$refit)) { cached <- repaired$fit; n_new_fits <<- n_new_fits + 1L
        saveRDS(cached,cache); writeLines(key,keyfile) }
    }
    return(cached)
  }
  if(!isTRUE(cov) && !length(effects)) {
    screened <- screen_base_fit()
    if(!is.null(screened)) {saveRDS(screened,cache);writeLines(key,keyfile);return(screened)}
  }
  failure_file <- cache_file(key,tag,cov,failure=TRUE)
  if(!isTRUE(cov)) {
    recovered <- pmx_scm_recover_fit(failure_file,key)
    if(!is.null(recovered)) {
      saveRDS(recovered,cache);writeLines(key,keyfile)
      cat("SCM_FIT_RECLASSIFIED ",tag,": normal optimizer exit with objective-history warning; native estimates reused, failure record retained; no refit\n",sep="")
      return(recovered)
    }
  }
  pending <- if(!isTRUE(cov)) pmx_scm_pending(key) else NULL
  receipt <- if(!is.null(pending) && file.exists(pending)) readRDS(pending) else NULL
  if(!is.null(receipt) && (!is.list(receipt) || !identical(receipt$schema,1L) ||
     !identical(receipt$key,key) || !is.numeric(receipt$elapsed) || length(receipt$elapsed)!=1L ||
     !is.finite(receipt$elapsed) || receipt$elapsed<0)) stop("SCM_PARALLEL_RECEIPT_INVALID: ",tag)
  fail <- function(reason, diagnostic=NULL, estimate=NULL) {
    fit_failures[[tag]] <<- reason
    if (!isTRUE(cov)) saveRDS(list(key = key, reason = reason, diagnostic = diagnostic, estimate = estimate), failure_file)
    if(!is.null(pending) && file.exists(pending)) unlink(pending)
    cat("FIT_FAILED ", tag, ": ", reason, "\n", sep = "")
    NULL
  }
  if (!isTRUE(cov) && pmx_scm_failure_cached(failure_file)) {
    previous <- readRDS(failure_file)
    if (!identical(previous$key, key) || !is.character(previous$reason) || length(previous$reason) != 1L)
      stop("Invalid failed-fit record: ", failure_file)
    fit_failures[[tag]] <<- previous$reason
    cat("FIT_FAILED_CACHED ", tag, ": ", previous$reason, "\n", sep = "")
    return(NULL)
  }
  if(is.null(receipt)) budget_guard(tag, cov)
  t0 <- Sys.time()
  diagnostic <- NULL
  f <- if(!is.null(receipt)) {diagnostic <- receipt$diagnostic; FIT_WARNINGS[[tag]] <<- receipt$warnings; receipt$fit} else tryCatch(withCallingHandlers({
    if(isTRUE(cov)) {
      search_key <- fit_key(effects,FALSE)
      if(!fit_cached(search_key)) stop("Covariance requires the matching completed search fit")
      if(packageVersion("nlmixr2est") < "7.1.0") stop("Post-fit covariance requires nlmixr2est >= 7.1.0; do not refit as a fallback")
      f0 <- readRDS(cache_file(search_key))
      fitted_coef <- fixef(f0); fitted_objf <- f0$objf; fitted_bic <- pmx_screen_bic(f0)
      cat("COV_REUSE ",tag," source=",basename(cache_file(search_key)),"\n",sep="")
      ladder <- cov_ladder(f0,effects,tag)
      if(!is.null(ladder$diagnostics)) cov_diagnostic_lines(tag,ladder$diagnostics)
      if(is.null(ladder$fit)) {
        if(!COV_UNESTIMABLE_CONTINUE)
          stop(if(!length(ladder$attempted)) "COV_ATTEMPT_BUDGET_EXHAUSTED" else "Requested covariance not estimable",
            cov_ladder_summary(ladder),
            "; the ladder ",paste(cov_methods(),collapse="/"),
            " is exhausted for this fit. Preserve the search checkpoint and repair the gradient/bound cause, ",
            "or opt in to estimates-only continuation with PMX_COV_UNESTIMABLE_CONTINUE=true")
        f <- nlmixr2est::addTable(f0)
        COV_UNESTIMABLE[[tag]] <<- list(
          reason="post-fit FOCEI covariance is not estimable at the completed estimates",
          methods=cov_methods(), attempted=ladder$attempted, notes=ladder$diagnostics,
          disclosure=cov_unestimable_disclosure(tag,ladder$diagnostics))
        cat("COV_UNESTIMABLE ",tag,": no method installed a covariance; fitted estimates are preserved and reported uncertainty stays blank\n",sep="")
        f
      } else {
        COV_METHOD <<- ladder$method
        key <- ladder$key
        cache <- cache_file(key,tag,TRUE)
        keyfile <- paste0(cache,".key")
        f <- ladder$fit
        if(!isTRUE(all.equal(fixef(f),fitted_coef,tolerance=1e-8)) ||
           !isTRUE(all.equal(f$objf,fitted_objf,tolerance=1e-8)) ||
           !isTRUE(all.equal(pmx_screen_bic(f),fitted_bic,tolerance=1e-8))) stop("Post-fit step changed fitted estimates or objective")
        f
      }
    } else {
      ui <- MODEL$build(effects, START_CTL)
      FIT_WARNINGS[[tag]] <<- character(0)
      withCallingHandlers(
        MODEL$fit(ui,pmx_endpoint_data(ui,D),cov=FALSE),
        warning=function(w) {
          FIT_WARNINGS[[tag]] <<- c(FIT_WARNINGS[[tag]], conditionMessage(w))
          invokeRestart("muffleWarning")
        })
    }
  },error=function(e) {
    diagnostic <<- list(message=conditionMessage(e),
      call=paste(deparse(conditionCall(e)),collapse=" "),
      stack=vapply(tail(sys.calls(),12L),function(x) paste(deparse(x),collapse=" "),""))
  }),error=function(e) e)
  el <- if(!is.null(receipt)) round(receipt$elapsed,1) else round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  if (inherits(f, "error")) {
    cat(sprintf("  %-26s FAILED (%.0fs): %s\n", tag, el, conditionMessage(f)))
    if(!is.null(diagnostic) && nzchar(diagnostic$call)) cat("FIT_ERROR_CALL ",tag,": ",diagnostic$call,"\n",sep="")
    return(fail(brief_fit_failure(conditionMessage(f)),diagnostic))
  }
  if(isTRUE(cov) && is.null(COV_UNESTIMABLE[[tag]])) cat("COV_FIT_RESULT ",tag," requested=",COV_METHOD,
    " actual=",paste(as.character(unlist(f$covMethod)),collapse=","),"\n",sep="")
  quality <- pmx_fit_quality(f,FIT_WARNINGS[[tag]])
  attr(f,"pmx_fit_warnings") <- quality$warnings
  if(length(quality$warnings)) cat("SCM_FIT_QUALITY ",tag,": ",paste(quality$warnings,collapse=" | "),"\n",sep="")
  if(!quality$ok) {
    cat("SCM_FIT_INVALID ",tag,": excluded from likelihood comparisons\n",sep="")
    return(fail("Optimizer or fitted estimates invalid",list(message=paste(quality$problems,collapse=" | ")),f))
  }
  if (!is.finite(f$objf) || any(!is.finite(fixef(f)))) return(fail("Non-finite estimates",estimate=f))
  th <- grep("^theta_", names(fixef(f)), value = TRUE)
  cat(sprintf("  %-26s OFV=%-15s BIC=%-15s %s (%.0fs)\n", tag,
      format(f$objf, digits = 9), format(pmx_screen_bic(f), digits = 9),
      paste(sprintf("%s=%.4f", th, fixef(f)[th]), collapse = " "), el))
  if(!isTRUE(cov) && length(th)) {
    starts <- tryCatch(as.data.frame(f$scaleInfo),error=function(e) NULL)
    if(!is.null(starts) && all(c("est","scaleC") %in% names(starts))) {
      positions <- match(th,names(fixef(f)))
      positions <- positions[!is.na(positions) & positions<=nrow(starts)]
      if(length(positions) && any(abs(starts$est[positions]-.001)<1e-10 & abs(starts$scaleC[positions])<.01,na.rm=TRUE))
        cat("SCM_INIT_SCALE_WARNING: covariate remains at the zero-start adjustment with a small scale; review optimization and uncertainty before interpreting effects. BIC retention is not significance.\n")
    }
  }
  if(!is.null(COV_UNESTIMABLE[[tag]])) {
    # Estimates-only continuation: never cache the covariance-free fit under a
    # covariance key, otherwise a later run would treat it as completed uncertainty.
    cat("COV_ESTIMATES_ONLY ",tag,": not cached under a covariance key; no new fit counted\n",sep="")
    return(f)
  }
  n_new_fits <<- n_new_fits + 1L
  if (!isTRUE(cov)) {
    if(el>OBS_FIT_S) OBS_FIT_S <<- el
    used_threads <- if(!is.null(receipt) && is.numeric(receipt$threads) &&
      length(receipt$threads)==1L && is.finite(receipt$threads) && receipt$threads>=1L)
      receipt$threads else pmx_fit_threads()
    thread_key <- as.character(used_threads)
    OBS_FIT_TIMES[thread_key] <<- max(c(OBS_FIT_TIMES[thread_key],el),na.rm=TRUE)
    OBS_FIT_WORK <<- max(OBS_FIT_WORK,el*used_threads)
  }
  if (!isTRUE(cov) && identical(tag, "base")) {
    repaired <- pmx_plateau_fit(f, tag, D)
    if (isTRUE(repaired$refit)) { f <- repaired$fit; n_new_fits <<- n_new_fits + 1L }
    FIT_BASE_ID <<- sprintf("%.6f", f$objf)
  }
  saveRDS(f, cache); writeLines(key,keyfile)
  if(!is.null(pending) && file.exists(pending)) unlink(pending)
  pmx_scm_save_state(list(phase = st_phase, chosen = st_chosen, added = st_added, new_fits = n_new_fits,
               elapsed = elapsed(), time = Sys.time(),
               fit_timing=list(key=FIT_TIMING_KEY,host=pmx_cpu_timing_host(),seconds=OBS_FIT_S,core_seconds=OBS_FIT_WORK,thread_seconds=OBS_FIT_TIMES)), STATE_FILE)
  f
}


scm_add <- function(current,effects) {
  for(p in names(effects)) current[[p]] <- c(current[[p]],effects[[p]])
  current
}
scm_remove <- function(current,effects) {
  for(p in names(effects)) {
    keep <- current[[p]]
    for(e in effects[[p]]) keep <- keep[!vapply(keep,function(k)
      identical(k$cov,e$cov) && identical(k$type,e$type) && identical(k$level,e$level),logical(1))]
    if(length(keep)) current[[p]] <- keep else current[[p]] <- NULL
  }
  current
}
scm_prefetch <- function(tasks) {
  if(!length(tasks)) return(invisible(NULL))
  tasks <- lapply(tasks,function(task) {
    task$key <- fit_key(task$effects,FALSE);task$pending <- pmx_scm_pending(task$key);task
  })
  tasks <- tasks[!duplicated(vapply(tasks,function(task)task$key,""))]
  context <- list(model=MODEL,data=D,dir=getwd(),start_ctl=START_CTL,
                  start_effects=START_EFFECTS,
                  contract=normalizePath(file.path(SD,"..","analyses_template","tools","model_contract.R")))
  pmx_scm_prefetch(tasks,context,fit_commit=function(effects,tag)fitm(effects,tag),
    cached=function(task) fit_cached(task$key) || pmx_scm_failure_cached(cache_file(task$key,task$tag,FALSE,failure=TRUE)),
    need=fit_need,left=function()JOB_BUDGET-elapsed(),defer_work=defer,
    scaled_need=fit_need,window=JOB_BUDGET)
}

pw  <- function(cov, ref, exp = NULL) list(type = "power", cov = cov, ref = ref, exp = exp)
ctg <- function(cov, level) list(type = "cat", cov = cov, level = level)
CAND <- list()  # Build the complete grid after reading explicit effect definitions/exclusions.
stopifnot(is.list(CAND))

.short_lab <- function(x) {
  map <- vapply(CAND, function(cd) cd$sl %||% cd$lab, character(1))
  names(map) <- vapply(CAND, function(cd) cd$lab, character(1))
  out <- unname(map[x])
  out[is.na(out)] <- x[is.na(out)]        # CSV-supplied labels are used as they are
  as.character(out)
}

read_candidates <- function(path = "covariates.csv", ref = REF) {
  path <- pmx_resolve(path)          # a user's covariates.csv sits at the ROOT
  if (!file.exists(path)) return(NULL)
  d <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  need <- c("label", "param", "covariate", "effect")
  if (!all(need %in% names(d))) stop(path, " needs the columns: ", paste(need, collapse = ", "))
  excluded <- NULL
  if ("test" %in% names(d)) {
    omit <- !is.na(d$test) & tolower(trimws(d$test)) %in% c("no","false","0")
    if(any(omit)) {
      if(!"user_instruction" %in% names(d) || any(is.na(d$user_instruction[omit]) | !nzchar(trimws(d$user_instruction[omit]))))
        stop("SCM_SCOPE_APPROVAL_REQUIRED: test=no requires the exact explicit user instruction in user_instruction; agent rationale is not approval")
      excluded <- d[omit,c("param","covariate","user_instruction"),drop=FALSE]
    }
    d <- d[!omit,,drop=FALSE]
  }
  supplied <- function(x) length(x)==1L && !is.na(x) && nzchar(trimws(as.character(x)))
  num <- function(x,field) {
    value <- suppressWarnings(as.numeric(x))
    if(length(value)!=1L || !is.finite(value)) stop("SCM_COVARIATE_CONFIG_INVALID: ",field," must be a finite number in ",path)
    value
  }
  out <- lapply(split(d, d$label), function(g) {
    eff <- list()
    for (i in seq_len(nrow(g))) {
      r <- g[i, ]
      r$covariate <- tolower(trimws(r$covariate))
      r$effect <- tolower(trimws(r$effect))
      if(!r$effect %in% c("power","expo","linear","cat")) stop("SCM_COVARIATE_CONFIG_INVALID: unknown effect for ",g$label[1])
      if(!r$covariate %in% names(D)) stop("Covariate missing from data: ",r$covariate)
      if(anyNA(D[[r$covariate]])) stop("SCM requires a declared missing-covariate policy for ",r$covariate)
      if (r$effect == "cat") {
        lst <- ctg(r$covariate, num(r$level,paste("numeric category contrast level for",r$covariate,"on",r$param)))
      } else {
        rv <- if ("reference" %in% names(g) && supplied(r$reference))
          num(r$reference,"reference") else if(r$covariate %in% names(ref)) ref[[r$covariate]] else
            median(suppressWarnings(as.numeric(as.character(D[[r$covariate]]))))
        if (is.null(rv)) stop("no reference value for ",r$covariate," in ",path," (add a reference column)")
        rv <- num(rv,"reference")
        x <- suppressWarnings(as.numeric(as.character(D[[r$covariate]])))
        if(any(!is.finite(x)) || (r$effect=="power" && (rv<=0 || any(x<=0))))
          stop("SCM_COVARIATE_CONFIG_INVALID: finite data/reference required (positive for power): ",r$covariate)
        ex <- if ("exponent" %in% names(g) && supplied(r$exponent)) num(r$exponent,"exponent") else NULL
        if(!is.null(ex) && r$effect!="power") stop("SCM_COVARIATE_CONFIG_INVALID: exponent applies only to power effects")
        lst <- pw(r$covariate, rv, ex)
        lst$type <- r$effect
      }
      eff[[r$param]] <- c(eff[[r$param]], list(lst))
    }
    list(lab = g$label[1], eff = eff)
  })
  names(out) <- NULL
  attr(out,"excluded") <- excluded
  cat("candidate list read from ", path, ": ", length(out), " candidates
", sep = "")
  out
}
source(file.path(SD,"..","analyses_template","tools","covariate_intake.R"))
.covariate_review <- if(PHASE=="search")
  pmx_covariate_intake(pmx_resolve("pmx_config.R"),FAM_ARG) else NULL
if(PHASE=="search" && !file.exists(pmx_resolve("covariates.csv")))
  stop("PMX_COVARIATE_INTAKE_REQUIRED: write reviewed pairs to root covariates.csv before SCM; use a header-only CSV only after documenting no eligible covariates or an explicit user opt-out")
.cand_from_file <- read_candidates()
if(!is.null(.covariate_review)) attr(.cand_from_file,"review") <- .covariate_review
CAND <- MODEL$candidates(REF,.cand_from_file)
if (!length(CAND))
  cat("SCM_NO_TESTABLE_PAIRS: consult table/_covariate_scope.csv and _scm_candidate_plan.csv; no tested effect is not evidence of no effect\n")

CRIT <- Sys.getenv("SCM_CRITERION", "bic")
P_FWD <- as.numeric(Sys.getenv("SCM_P_FWD", "0.05"))
P_BCK <- as.numeric(Sys.getenv("SCM_P_BCK", "0.01"))
if (!CRIT %in% c("bic", "chisq")) stop("SCM_CRITERION must be 'bic' or 'chisq'")
if(any(!is.finite(c(P_FWD,P_BCK))) || any(c(P_FWD,P_BCK)<=0 | c(P_FWD,P_BCK)>=1)) stop("SCM p thresholds must be between 0 and 1")
df_of <- function(eff) sum(vapply(unlist(eff,recursive=FALSE),function(e) as.integer(is.null(e$exp)),0L))
if(CRIT=="chisq" && any(vapply(CAND,function(cd) any(vapply(unlist(cd$eff,recursive=FALSE),function(e) !is.null(e$exp),TRUE)),TRUE))) stop("Fixed-power alternatives require BIC or a prespecified base model, not a nested chi-square test")
score <- function(f, cur, df, alpha, backward=FALSE) {
  if (CRIT == "bic") pmx_screen_bic(f) - pmx_screen_bic(cur)
  else f$objf - cur$objf + (if(backward) -qchisq(1-alpha,df) else qchisq(1-alpha,df))     # < 0 -> passes the test
}
cat(sprintf("=== CRITERION: %s%s ===\n", CRIT,
            if (CRIT == "chisq") sprintf(" (forward p < %g, backward p < %g)", P_FWD, P_BCK) else ""))

SEARCH_RESULT <- paste0(FAM_ARG,"_scm_search_result.rds")
SEARCH_SIGNATURE <- rlang::hash(list(base=fit_key(list(),FALSE),candidates=CAND,
  criterion=c(CRIT,P_FWD,P_BCK),covariates=if(file.exists(pmx_resolve("covariates.csv"))) unname(tools::md5sum(pmx_resolve("covariates.csv"))) else NULL))
if(PHASE=="covariance" && !file.exists(SEARCH_RESULT)) stop("SCM_SEARCH_REQUIRED; complete s1 before covariance")
if(PHASE=="search") {
cat("=== BASE ===\n"); base <- fitm(list(), "base")
if (is.null(base)) stop("the base model could not be fitted - see the FAILED line above")
cat("base OFV", format(base$objf, digits = 10), " BIC", format(pmx_screen_bic(base), digits = 10), "\n\n")
if (length(CAND)) cat("=== FORWARD: every remaining candidate is added to the CURRENT model ===\n")
added <- list(); chosen <- character(0); step_of <- list()
log_rows <- list()     # every fit the search makes, for the run record
log_fit <- function(st, lab, f, decision, eff = NULL, reason = "") {
  log_rows[[length(log_rows) + 1]] <<-
    list(st = st, lab = lab, f = f, decision = if (is.null(f)) "failed" else decision,
         eff = eff, reason = reason)
}
while (length(CAND)) {   # no candidates means the base model is final; nothing to search
  st <- length(chosen) + 1                     # forward step number
  stag <- paste0("st", st)                     # cache state of the current model
  cur <- if (length(chosen)) fitm(added, paste0("cur_", stag)) else base
  best_sc <- 0; best_eff <- NULL; best_lab <- NA   # < 0 means "improves on the current model"
  cat(sprintf("--- forward step %d (current model: %s) ---\n", st,
              if (length(chosen)) paste(chosen, collapse = "; ") else "base"))
  warm_from(cur, paste0("cur_", stag))
  scm_prefetch(lapply(Filter(function(cd)!cd$lab %in% chosen,CAND),function(cd)
    list(effects=scm_add(added,cd$eff),tag=tagof(cd$lab,stag))))
  for (cd in CAND) {
    if (cd$lab %in% chosen) next
    cand <- scm_add(added,cd$eff)
    fit_tag <- tagof(cd$lab, stag)
    f <- fitm(cand, fit_tag)
    log_fit(st, cd$lab, f, "candidate", cd$eff,
            if (is.null(f)) fit_failures[[fit_tag]] else "")
    if (is.null(f)) next
    sc <- score(f, cur, df_of(cd$eff), P_FWD)
    cat(sprintf("    %-46s dBIC = %+.2f (dOFV %+.2f, cutoff %+.2f, df %d)%s\n", cd$lab,
                pmx_screen_bic(f) - pmx_screen_bic(cur), f$objf - cur$objf,
                if (CRIT == "chisq") -qchisq(1 - P_FWD, df_of(cd$eff)) else 0,
                df_of(cd$eff), if (sc < 0) "  <- passes" else ""))
    if (sc < best_sc) { best_sc <- sc; best_eff <- cd$eff; best_lab <- cd$lab }
  }
  if (is.null(best_eff)) {
    cat(sprintf("forward step %d: no candidate passes the %s test - stop\n\n", st, CRIT))
    break
  }
  for (p in names(best_eff)) added[[p]] <- c(added[[p]], best_eff[[p]])
  chosen <- c(chosen, best_lab)
  step_of[[best_lab]] <- st
  st_chosen <- chosen; st_added <- added; st_phase <- paste0("forward_", st)
  for (k in seq_along(log_rows))
    if (identical(log_rows[[k]]$lab, best_lab) && identical(log_rows[[k]]$st, st))
      log_rows[[k]]$decision <- "kept"
  cat(sprintf("forward step %d: KEEP %s\n\n", st, best_lab))
}

if (length(chosen)) {
  cat("=== BACKWARD ===\n")
  repeat {
    cur <- fitm(added, paste0("bcur", length(chosen)))   # current (post-forward) model
    worst <- NULL; worst_sc <- 0; worst_lab <- NA   # removal must WORSEN nothing
    warm_from(cur, paste0("bcur", length(chosen)))
    scm_prefetch(lapply(Filter(function(cd)cd$lab %in% chosen,CAND),function(cd)
      list(effects=scm_remove(added,cd$eff),
           tag=paste0("drop_",gsub("[^A-Za-z0-9]","",cd$lab),"__b",length(chosen)))))
    for (cd in CAND) {
      if (!(cd$lab %in% chosen)) next
      red <- scm_remove(added,cd$eff)
      fit_tag <- paste0("drop_", gsub("[^A-Za-z0-9]", "", cd$lab), "__b", length(chosen))
      f <- fitm(red, fit_tag)
      log_fit("backward", paste0("remove ", cd$lab), f, "candidate",
              reason = if (is.null(f)) fit_failures[[fit_tag]] else "")
      if (is.null(f)) next
      sc <- score(f, cur, df_of(cd$eff), P_BCK,backward=TRUE)
      cat(sprintf("    remove %-44s dBIC = %+.2f (dOFV %+.2f, df %d)%s\n", cd$lab,
                  pmx_screen_bic(f) - pmx_screen_bic(cur), f$objf - cur$objf, df_of(cd$eff),
                  if (sc < 0) "  <- removal passes" else ""))
      if (sc < worst_sc) { worst_sc <- sc; worst <- red; worst_lab <- cd$lab }
    }
    if (is.null(worst)) { cat(sprintf("backward: no removal passes the %s test - stop\n\n", CRIT)); break }
    added <- worst; chosen <- setdiff(chosen, worst_lab)
    st_chosen <- chosen; st_added <- added; st_phase <- paste0("backward_", length(chosen))
    cat(sprintf("backward: DROP %s\n\n", worst_lab))
  }
}

# The search is over: record that, so a resumed job knows the remaining work is the cov fits only.
st_phase <- "search_done"
pmx_scm_save_state(list(phase = st_phase, chosen = st_chosen, added = st_added, new_fits = n_new_fits,
             budget = JOB_BUDGET, elapsed = elapsed(), time = Sys.time(),
               fit_timing=list(key=FIT_TIMING_KEY,host=pmx_cpu_timing_host(),seconds=OBS_FIT_S,core_seconds=OBS_FIT_WORK,thread_seconds=OBS_FIT_TIMES)), STATE_FILE)
cat(sprintf("SCM_SEARCH_DONE chosen=%s fits_this_job=%d elapsed=%.0fs budget=%.0fs\n",
            if (length(chosen)) paste(chosen, collapse = "; ") else "none", n_new_fits,
            elapsed(), JOB_BUDGET))

final <- if(length(chosen)) fitm(added,paste0("selected__",length(chosen))) else base
if(is.null(final)) stop("Selected model has no completed search fit")
cat("=== FINAL MODEL ===\n")
failed_candidates <- unique(vapply(Filter(function(x) is.null(x$f),log_rows),function(x) x$lab,""))
assessment <- list(state=if(length(failed_candidates)) "partial" else "complete",
  failed_candidates=failed_candidates,
  optimization=list(base=pmx_fit_quality(base),final=pmx_fit_quality(final),
    candidates=setNames(lapply(log_rows,function(r) if(is.null(r$f)) list(state="failed",reason=r$reason) else pmx_fit_quality(r$f)),
      vapply(log_rows,function(r) paste(r$st,r$lab,sep=":"),""))))
cat("retained:", if (length(chosen)) paste(chosen, collapse = "; ") else "none", "\n")
if(length(failed_candidates)) cat("SCM_ASSESSMENT_PARTIAL failed_candidates=",length(failed_candidates),
  "; not retained is not evidence against covariates that could not be evaluated\n",sep="")
cat("OFV", format(final$objf, digits = 10), " BIC", format(pmx_screen_bic(final), digits = 10), "\n")

ofv0 <- base$objf; bic0 <- pmx_screen_bic(base)
row <- function(tag, label, f, decision, eff = NULL, reason = "") {
  if (is.null(f)) return(data.frame(
    Step = tag, Model = label, OFV = NA_real_, `dOFV vs base` = NA_real_,
    BIC = NA_real_, `dBIC vs base` = NA_real_, Estimate = "", Decision = "Fit failed",
    `Failure reason` = if (is.null(reason) || !nzchar(reason)) "Model fitting failed" else reason,
    check.names = FALSE, stringsAsFactors = FALSE))
  th <- grep("^theta_", names(fixef(f)), value = TRUE)
  est <- if (length(th)) paste(sprintf("%s=%.4f", th, fixef(f)[th]), collapse = "; ") else {
    fx <- if (length(eff)) unlist(lapply(names(eff), function(p) vapply(eff[[p]], function(e)
      if (!is.null(e$exp)) sprintf("%s=%g (fixed)", e$cov, e$exp) else NA_character_,
      character(1)))) else character(0)
    fx <- fx[!is.na(fx)]
    if (length(fx)) paste(fx, collapse = "; ") else "-"
  }
  data.frame(Step = tag, Model = label, OFV = round(f$objf, 2),
             `dOFV vs base` = round(f$objf - ofv0, 2), BIC = round(pmx_screen_bic(f), 2),
             `dBIC vs base` = round(pmx_screen_bic(f) - bic0, 2), Estimate = est,
             Decision = decision, `Failure reason` = "", check.names = FALSE, stringsAsFactors = FALSE)
}
rows <- list(row("0", "base model (no covariate)", base, "reference"))
for (r in log_rows) {
  dec <- if (identical(r$decision, "kept")) paste0("kept at step ", r$st) else "not retained"
  rows[[length(rows) + 1]] <- row(as.character(r$st), .short_lab(r$lab), r$f, dec,
                                  eff = r$eff, reason = r$reason)
}
rows[[length(rows) + 1]] <- row("final",
  paste0("final model", if (length(chosen))
         paste0(": ", paste(.short_lab(chosen), collapse = " + ")) else ""),
  final, "final model")
rec <- do.call(rbind, rows); rownames(rec) <- NULL
rec <- rec[, c("Step", "Model", "BIC", "Estimate", "Decision", "Failure reason")]
dir.create("table", showWarnings = FALSE)
write.csv(rec, file.path("table", "_scm_runrecord.csv"), row.names = FALSE, na = "")
kept_bic <- function(l) {
  k <- Filter(function(r) identical(r$lab, l) && identical(r$decision, "kept"), log_rows)
  if (length(k)) round(pmx_screen_bic(k[[1]]$f), 2) else NA_real_
}
short <- data.frame(
  Step = c("0", as.character(seq_along(chosen)), "final"),
  Model = c("base model (no covariate)", .short_lab(chosen),
            paste0("final model: base",
                   if (length(chosen)) paste0(" + ", paste(.short_lab(chosen), collapse = " + ")) else "")),
  BIC = c(round(pmx_screen_bic(base), 2), vapply(chosen, kept_bic, 0), round(pmx_screen_bic(final), 2)),
  Decision = c("reference", rep("retained", length(chosen)), "final model"),
  check.names = FALSE, stringsAsFactors = FALSE)
write.csv(short, file.path("table", "_scm_summary.csv"), row.names = FALSE)
ctl_final <- MODEL$ctl_out(final, chosen, REF, added=added)
ctl_initial <- pmx_clean_ctl(nonmem_add_cov(pmx_expand_records(readLines(MODEL$model_ctl,warn=FALSE)),added)$lines)
# A non-numeric data column cannot be an estimated field: publish it as NAME=DROP.
ctl_initial <- pmx_input_drop_ctl(ctl_initial, MODEL$data_csv, "final_model.ctl", data_ctl = MODEL$model_ctl)
ctl_final <- pmx_input_drop_ctl(ctl_final, MODEL$data_csv, "final_fitted.ctl", data_ctl = MODEL$model_ctl)
root <- Sys.getenv("PMX_ROOT", "")
writeLines(ctl_initial,file.path(if(nzchar(root)) root else ".","final_model.ctl"))
saveRDS(list(signature=SEARCH_SIGNATURE,base_key=fit_key(list(),FALSE),
             final_key=fit_key(added,FALSE),chosen=chosen,added=added,rec=rec,assessment=assessment,ctl=ctl_final,initial_ctl=ctl_initial),SEARCH_RESULT)
cat("SCM_ESTIMATES_COMPLETE uncertainty=PENDING checkpoint=",SEARCH_RESULT,
    "\nSCM_NEXT_STAGE s1c covariance; do not rerun the search\n",sep="")
quit(save="no",status=0)
}
selection <- readRDS(SEARCH_RESULT)
if(!identical(selection$signature,SEARCH_SIGNATURE)) stop("SCM_SEARCH_STALE; covariance must use a current search checkpoint")
chosen <- selection$chosen; added <- selection$added; rec <- selection$rec; ctl_final <- selection$ctl
ctl_initial <- selection$initial_ctl %||% selection$ctl
# Keep a resumed stage on the same published streams: a checkpoint written before the
# =DROP rule (or by an older toolkit) is normalised here, and final_model.ctl follows it.
ctl_initial <- pmx_input_drop_ctl(ctl_initial, MODEL$data_csv, "final_model.ctl", data_ctl = MODEL$model_ctl)
ctl_final <- pmx_input_drop_ctl(ctl_final, MODEL$data_csv, "final_fitted.ctl", data_ctl = MODEL$model_ctl)
ctl_root <- Sys.getenv("PMX_ROOT", "")
ctl_path <- file.path(if(nzchar(ctl_root)) ctl_root else ".", "final_model.ctl")
if(!file.exists(ctl_path) || !identical(readLines(ctl_path,warn=FALSE),ctl_initial)) writeLines(ctl_initial,ctl_path)
# Covariance phase skips the search block (line 772) so fitm() is never called for the base,
# leaving FIT_BASE_ID at its initial NULL. Restore it from the cached base fit exactly as
# fitm() does at line 493 so fit_key(added,FALSE) reproduces the search-time hash.
if(PHASE == "covariance") FIT_BASE_ID <<- sprintf("%.6f", readRDS(cache_file(selection$base_key))$objf)
if(!identical(selection$base_key,fit_key(list(),FALSE)) || !identical(selection$final_key,fit_key(added,FALSE)) ||
   !fit_cached(selection$base_key) || !fit_cached(selection$final_key)) stop("SCM_SEARCH_CACHE_MISSING_OR_STALE; no covariance refit fallback")
base <- readRDS(cache_file(selection$base_key)); final <- readRDS(cache_file(selection$final_key))
pmx_require_fit_quality(base,"base before covariance")
pmx_require_fit_quality(final,"final before covariance")
st_chosen <- chosen; st_added <- added; st_phase <- "covariance"
cat("SCM_SEARCH_REUSED checkpoint=",SEARCH_RESULT,"; no search fits submitted\n",sep="")
# Covariance uses the completed fit, with starts bounded per model/key/method.
COV_TRIES <- suppressWarnings(as.integer(Sys.getenv("PMX_COV_TRIES","2")))
if(is.na(COV_TRIES) || COV_TRIES<1L) COV_TRIES <- 2L
COV_FALLBACK_TRIES <- suppressWarnings(as.integer(Sys.getenv("PMX_COV_FALLBACK_TRIES","1")))
if(is.na(COV_FALLBACK_TRIES) || COV_FALLBACK_TRIES<1L) COV_FALLBACK_TRIES <- 1L
COV_FALLBACK <- Sys.getenv("PMX_COV_FALLBACK","r")
if(!all(c(COV_PRIMARY,COV_FALLBACK) %in% c("s","r","r,s"))) stop("Unsupported covariance method")
cov_starts <- function(key) {
  p <- file.path("_scm_sel_cache",paste0(key,".cov_attempts"))
  n <- suppressWarnings(as.integer(if(file.exists(p)) readLines(p,warn=FALSE)[1] else 0L))
  if(is.na(n) || n<0L) stop("COV_ATTEMPTS_INVALID ",p,"; inspect, do not reset")
  n
}
# --- Post-fit covariance: method ladder, degeneracy diagnosis, explicit opt-out ---
# Starts are cumulative per fit key/method. Each invocation tries a method once;
# repeated identical numerical failures are not extra work within the same window.
COV_UNESTIMABLE_CONTINUE <- tolower(trimws(Sys.getenv("PMX_COV_UNESTIMABLE_CONTINUE",""))) %in%
  c("true","1","yes","on")
cov_methods <- function() unique(c(COV_PRIMARY,COV_FALLBACK))
cov_method_limit <- function(method) {
  if(!identical(COV_PRIMARY,COV_FALLBACK) && identical(method,COV_FALLBACK)) COV_FALLBACK_TRIES else COV_TRIES
}
cov_actual_method <- function(x) {
  x <- trimws(as.character(unlist(x)))
  x <- trimws(sub("\\(full\\)\\s*$","",x))       # nlmixr2 7.1.0 labels, e.g. "r,s (full)"
  paste(x[nzchar(x)],collapse=",")
}
cov_estimable <- function(f,method) {
  if(is.null(f) || inherits(f,"error")) return(FALSE)
  if(!identical(cov_actual_method(f$covMethod),method)) return(FALSE)
  if(!is.matrix(f$cov) || !nrow(f$cov) || any(!is.finite(f$cov)) || !isSymmetric(f$cov)) return(FALSE)
  !inherits(try(chol(f$cov),silent=TRUE),"try-error")
}
cov_param_frame <- function(f) {
  d <- tryCatch(as.data.frame(f$iniDf),error=function(e) NULL)
  if(!is.data.frame(d)) d <- tryCatch(as.data.frame(f$env$iniDf0),error=function(e) NULL)
  if(!is.data.frame(d) || !all(c("name","est","lower","upper") %in% names(d))) return(NULL)
  d
}
# Boundary proximity and diagonal variance size are observations, not a causal diagnosis.
# Neither proves a zero derivative, singular information or a need to fix/drop a parameter.
cov_diagnostics <- function(f,notes=character()) {
  d <- cov_param_frame(f); at <- character(0); small <- character(0)
  if(!is.null(d)) for(i in seq_len(nrow(d))) {
    est <- d$est[i]; if(!is.finite(est)) next
    lo <- d$lower[i]; up <- d$upper[i]; tol <- 1e-6*max(1,abs(est))
    if(is.finite(up) && abs(est-up)<=tol)
      at <- c(at,sprintf("%s=%s is at its upper bound %s",d$name[i],format(est,digits=8),format(up,digits=8)))
    else if(is.finite(lo) && abs(est-lo)<=tol)
      at <- c(at,sprintf("%s=%s is at its lower bound %s",d$name[i],format(est,digits=8),format(lo,digits=8)))
    diagonal <- all(c("neta1","neta2") %in% names(d)) &&
      is.finite(d$neta1[i]) && is.finite(d$neta2[i]) && d$neta1[i]>0 && d$neta1[i]==d$neta2[i]
    if(diagonal && est>=0 && est<=1e-6)
      small <- c(small,sprintf("%s diagonal variance %s is near zero",d$name[i],format(est,digits=6)))
  }
  clean <- unique(trimws(notes)); clean <- clean[nzchar(clean)]
  list(at_bound=at,near_zero_variance=small,notes=utils::head(clean,12L))
}
cov_diagnostic_lines <- function(tag,diag) {
  for(x in diag$at_bound) cat(sprintf("COV_DEGENERATE_AT_BOUND %s: %s\n",tag,x))
  for(x in diag$near_zero_variance) cat(sprintf("COV_DEGENERATE_VARIANCE %s: %s\n",tag,x))
  for(x in diag$notes) cat(sprintf("COV_RUNTIME_NOTE %s: %s\n",tag,x))
  if(length(diag$at_bound)) cat(sprintf(paste0("COV_DIAGNOSIS %s: %d estimate(s) sit on an estimation bound. ",
    "Boundary proximity may affect uncertainty but does not prove a zero gradient or singular information. ",
    "Review actual derivatives, curvature and runtime diagnostics before changing the model; do not clear ",
    "attempt counters to repeat the unchanged job.\n"),tag,length(diag$at_bound)))
  invisible(NULL)
}
cov_ladder <- function(f0,effects,tag) {
  attempted <- character(0); exhausted <- character(0); last <- NULL; notes <- character(0)
  for(m in cov_methods()) {
    COV_METHOD <<- m
    key_m <- fit_key(effects,TRUE)
    if(fit_cached(key_m)) {
      cached <- readRDS(cache_file(key_m,tag,TRUE))
      if(cov_estimable(cached,m)) {
        cat("COV_FIT_CACHED ",tag," method=",m,"\n",sep="")
        return(list(fit=cached,method=m,key=key_m,attempted=attempted,diagnostics=NULL))
      }
    }
    started <- cov_starts(key_m); limit <- cov_method_limit(m)
    if(started >= limit) {
      exhausted <- c(exhausted,sprintf("%s %d/%d",m,started,limit))
      cat(sprintf("COV_ATTEMPT_SKIP %s method=%s starts=%d/%d; start budget already used\n",tag,m,started,limit))
      next
    }
    writeLines(as.character(started+1L),file.path("_scm_sel_cache",paste0(key_m,".cov_attempts")))
    attempted <- c(attempted,m)
    cat(sprintf("COV_FIT_START %s requested=%s attempt=%d/%d mode=postfit\n",tag,m,started+1L,limit))
    f <- tryCatch(withCallingHandlers(nlmixr2est::setCov(f0,m),
      warning=function(w) notes <<- c(notes,conditionMessage(w)),
      # Progress chatter from the model rebuild is not a covariance note; keep only
      # messages that describe the covariance/gradient state.
      message=function(x) {
        msg <- conditionMessage(x)
        if(grepl("covariance|covMethod|gradient|non-positive|not estimable",msg,ignore.case=TRUE))
          notes <<- c(notes,msg)
        else invokeRestart("muffleMessage")
      }),
      error=function(e) e)
    if(inherits(f,"error")) {
      cat(sprintf("COV_FIT_ERROR %s method=%s: %s\n",tag,m,conditionMessage(f)))
      notes <- c(notes,conditionMessage(f))
      next
    }
    last <- f
    cat(sprintf("COV_FIT_RESULT %s requested=%s actual=%s cov=%s\n",tag,m,
      cov_actual_method(f$covMethod),if(cov_estimable(f,m)) "estimable" else "not_estimable"))
    if(cov_estimable(f,m))
      return(list(fit=f,method=m,key=key_m,attempted=attempted,diagnostics=NULL))
  }
  list(fit=NULL,method=NULL,key=NULL,attempted=attempted,exhausted=exhausted,
    diagnostics=cov_diagnostics(if(is.null(last)) f0 else last,notes))
}
cov_ladder_summary <- function(ladder) {
  attempts <- if(length(ladder$attempted)) paste(ladder$attempted,collapse=",") else "none"
  used <- if(length(ladder$exhausted)) paste(ladder$exhausted,collapse="; ") else "none"
  paste0(" (attempted this run: ",attempts,"; start budget already used: ",used,")")
}
# Reported verbatim in the frozen result and the report when uncertainty is absent.
cov_unestimable_disclosure <- function(tag,diag) {
  cause <- if(!is.null(diag) && length(diag$at_bound))
    paste0("Parameters resting on an estimation bound: ",paste(diag$at_bound,collapse="; "),
      ". Boundary proximity may contribute to uncertainty problems; the cause has not been established. ") else ""
  label <- if(grepl("^final",tag)) "the final model" else if(identical(tag,"base")) "the base model" else tag
  paste0("Model parameter uncertainty could not be estimated for ",label,
    " at the completed estimates. ",cause,
    "Standard errors, relative standard errors and confidence intervals are therefore not available ",
    "and are left blank. Point estimates, the objective function and the model fit are unaffected, but the ",
    "precision of the estimates cannot be quantified from this run.")
}
cat("=== POST-FIT COVARIANCE ===\n")
final <- if (length(chosen)) {
  f <- fitm(added, paste0("final__", length(chosen)), cov = TRUE)
  if (is.null(f)) stop("Final covariance failed; retain completed search fits; no frozen report fit")
  f
} else base
if(!length(chosen)) final <- fitm(list(),"final_base",cov=TRUE)
if(is.null(final)) stop("Final covariance failed; retain the search checkpoint; no frozen report fit")
final_tag <- if(length(chosen)) paste0("final__",length(chosen)) else "final_base"
cov_notes <- COV_UNESTIMABLE[[final_tag]]
cov_state <- if(!is.null(cov_notes)) "unestimable" else "complete"
cov_label <- function(f,tag) {
  if(!is.null(COV_UNESTIMABLE[[tag]])) "unestimable" else as.character(f$covMethod)
}
base_setting <- tolower(Sys.getenv("PMX_COV_BASE",if(FAM_ARG=="ppk") "true" else "false"))
if(!base_setting %in% c("false","0","no","true","1","yes")) stop("PMX_COV_BASE must be true or false")
base_requested <- base_setting %in% c("true","1","yes")
if(!length(chosen)) {
  base <- final
} else if(base_requested) {
  base <- fitm(list(),"base",cov=TRUE)
  if(is.null(base)) stop("Requested base covariance failed; retain the search checkpoint")
  if(!is.null(COV_UNESTIMABLE[["base"]])) {
    cov_state <- "unestimable"
    if(is.null(cov_notes)) cov_notes <- COV_UNESTIMABLE[["base"]]
  }
} else {
  base <- nlmixr2est::addTable(base)
}
cat("COV_OK final=",cov_label(final,final_tag)," base=",
    if(!length(chosen)) "same_as_final" else if(base_requested) cov_label(base,"base") else "not_requested",
    "\n",sep="")
if(identical(cov_state,"complete")) {
  saveRDS(final,file.path("_scm_sel_cache","final_cov.rds"))
} else {
  cat("COV_ESTIMATES_ONLY final: uncertainty state UNESTIMABLE; no covariance cache written\n")
}
covariance_entry <- list(state=cov_state,
  final_method=if(identical(cov_state,"complete")) as.character(final$covMethod) else "none",
  base_method=if(!length(chosen)) "same_as_final" else if(base_requested) cov_label(base,"base") else "not_requested")
if(!identical(cov_state,"complete")) covariance_entry <- c(covariance_entry,list(
  disclosure=cov_notes$disclosure,diagnostics=cov_notes$notes,
  attempts=cov_notes$attempted,methods=cov_notes$methods,
  opt_in="PMX_COV_UNESTIMABLE_CONTINUE"))
saveRDS(list(selection=if(file.exists(pmx_resolve("base_selection.dcf"))) as.list(read.dcf(pmx_resolve("base_selection.dcf"))[1,]) else NULL,data_md5=unname(tools::md5sum(MODEL$data_csv)), n_subjects=length(unique(D$id)), n_observations=sum(D$evid==0 & !is.na(D$dv)), criterion=CRIT,p_forward=P_FWD,p_backward=P_BCK,ctl=ctl_final, initial_ctl=ctl_initial, added = added, base = base, final = final, rec = rec, chosen = chosen,
             refs = structure(as.numeric(REF), names = toupper(names(REF))),
             assessment=selection$assessment,
             covariance=covariance_entry),
        "_scm_final_result.rds")

fmt <- function(x, d = 3) ifelse(is.na(x), "n/a", formatC(x, format = "f", digits = d))

pf <- as.data.frame(final$parFixedDf)
pf$Parameter <- rownames(pf)
cn  <- names(pf)
col <- function(nm) if (nm %in% cn) pf[[nm]] else rep(NA_real_, nrow(pf))
est_v <- col("Estimate"); rse_v <- col("%RSE"); shr_v <- col("Shrink(SD)%")
bsv_v <- { v <- rep(NA_real_, nrow(pf))
  for (nm in c("BSV(CV% or SD)", "BSV(CV%)")) if (nm %in% cn) { v <- pf[[nm]]; break }
  v }
fe <- fixef(final)
has_cov <- length(fixef(final)) && !all(is.na(rse_v))

pick <- function(nm, v) { i <- match(nm, pf$Parameter); if (is.na(i)) NA_real_ else as.numeric(v[i]) }
pf_name <- function(nm) c(nm, paste0(MODEL$fe_prefix %||% "", nm))
theta_of <- function(nm) {
  for (k in pf_name(nm)) {
    if (k %in% names(fe)) return(as.numeric(fe[[k]]))
    v <- pick(k, est_v); if (!is.na(v)) return(v)
  }
  NA_real_
}
rse_of <- function(nm) { for (k in pf_name(nm)) { v <- pick(k, rse_v); if (!is.na(v)) return(v) }; NA_real_ }

LAB <- MODEL$labels

rw <- function(p, d, e, r) data.frame(Parameter = p, Description = d, Estimate = e,
                                      `RSE (%)` = r, check.names = FALSE, stringsAsFactors = FALSE)
sec <- function(x) rw(x, "", "", "")

tv   <- MODEL$typical
tvs  <- tv[!is.na(vapply(tv, theta_of, numeric(1)))]
covp <- grep("^theta_", names(fe), value = TRUE)
rows_fix <- lapply(c(tvs, covp), function(nm)
  rw(nm, if (nm %in% names(LAB)) LAB[[nm]] else nm, fmt(theta_of(nm), 4), fmt(rse_of(nm), 1)))

iiv <- pf[grepl("^ETA_|^eta", pf$Parameter), , drop = FALSE]
rows_iiv <- if (nrow(iiv)) lapply(seq_len(nrow(iiv)), function(i)
  rw(gsub("^ETA_", "", iiv$Parameter[i]), "Inter-individual variability (CV%)",
     fmt(as.numeric(bsv_v[match(iiv$Parameter[i], pf$Parameter)]), 1), "")) else list()

res_rows <- names(MODEL$residual)[names(MODEL$residual) %in% pf$Parameter]
rows_res <- lapply(res_rows, function(nm) {
  e <- theta_of(nm)
  cv <- e
  rw(nm, MODEL$residual[[nm]], fmt(cv, 1), fmt(rse_of(nm), 1))
})

rows_shr <- if (nrow(iiv) && any(!is.na(shr_v))) lapply(seq_len(nrow(iiv)), function(i)
  rw(gsub("^ETA_", "", iiv$Parameter[i]), "Shrinkage of the individual estimates (%)",
     fmt(as.numeric(shr_v[match(iiv$Parameter[i], pf$Parameter)]), 1), "")) else list()

out <- rbind(
  sec("Fixed Effects"),
  do.call(rbind, rows_fix),
  if (length(rows_iiv)) rbind(sec("Inter-Individual Variability (%CV)"), do.call(rbind, rows_iiv)),
  if (length(rows_res)) rbind(sec("Residual Error"), do.call(rbind, rows_res)),
  if (length(rows_shr)) rbind(sec("Shrinkage (%)"), do.call(rbind, rows_shr)))
write.csv(out, file.path("table", "tbl_10.csv"), row.names = FALSE)
cat("tbl_10.csv written; covariance available:", has_cov, "\n")
print(out)

lst_text <- function(final, chosen, refs, title, notes = NULL) {
  ref_line <- paste(sprintf("%s %g %s", toupper(names(refs)), as.numeric(refs),
                            MODEL$ref_units[names(refs)]), collapse = ", ")
  c("", title,
    paste0("Date: ", format(Sys.time(), "%Y-%m-%d %H:%M")), "",
    "--- Header ---",
    paste0("Estimation method : ", paste(unlist(final$est), collapse = ", ")),
    paste0("Objective function: ", format(final$objf, digits = 10)),
    paste0("AIC               : ", format(AIC(final), digits = 10)),
    paste0("BIC               : ", format(pmx_screen_bic(final), digits = 10)),
    paste0("Log-likelihood    : ", format(as.numeric(logLik(final)), digits = 10)),
    paste0("Optimiser message : ", if (length(final$message)) as.character(final$message)[1] else "-"),
    paste0("Covariance        : ", paste(as.character(unlist(final$covMethod)), collapse = ",")),
    if (length(notes)) c("", "--- Model ---", paste0("  ", notes)),
    "", "--- Covariate functions in the final model ---",
    if (length(chosen)) paste0("  ", chosen) else "  none",
    paste0("  reference values: ", ref_line),
    "", "--- Run info / warnings ---",
    as.character(if (length(final$runInfo))
      paste0("  - ", gsub("[\r\n]+", " ", as.character(final$runInfo)))
    else "  none"),
    "", "--- Parameter estimates ---", capture.output(print(final)))
}
writeLines(MODEL$output(final, chosen, REF), "_nlmixr2_output.txt")

cat("FINAL_INITIALS base initials retained; new covariates use template starts; fitted values preserved in the result bundle\n")

cat("\nwritten: table/_scm_runrecord.csv, table/_scm_summary.csv, table/tbl_10.csv,",
    "_nlmixr2_output.txt, _scm_final_result.rds\n\n=== RUN RECORD ===\n")
print(rec)
