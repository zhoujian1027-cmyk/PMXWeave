#!/usr/bin/env Rscript
LADDER_VER <- 7L   # Operational revision; scientific identity uses pmx_screen_recipe/settings.
.cpu_path <- file.path(Sys.getenv("PMX_TOOLKIT"),"word-report","cpu_budget.R")
if(!file.exists(.cpu_path)) stop("PMX_CPU_TOOLKIT_REQUIRED: invoke the complete workspace wrapper")
source(.cpu_path)
CFG_DATA   <- Sys.getenv("PMX_DATA", "")            # empty -> best *.csv in the dir
CFG_MODELS <- strsplit(Sys.getenv("PMX_MODELS", ""), "[,[:space:]]+")[[1]]
CFG_MODELS <- CFG_MODELS[nzchar(CFG_MODELS)]        # empty -> every *.ctl in the dir
CFG_FAMILY <- Sys.getenv("PMX_FAMILY", "ppk")       # S1 looks for <family>_model.ctl
CFG_DIR <- getwd()   # provisional: re-pointed at the model directory right after setwd(D) below
CFG_MAXFIT <- as.integer(Sys.getenv("PMX_MAXFIT", "9999"))
CFG_CAND_MAX <- suppressWarnings(as.integer(Sys.getenv("PMX_CAND_MAX", "6")))   # ladder width
if (!is.finite(CFG_CAND_MAX) || CFG_CAND_MAX < 1L) CFG_CAND_MAX <- 6L
CFG_MANUAL_SELECT <- identical(Sys.getenv("PMX_MANUAL_SELECT", "0"), "1")
CFG_MODELS_EXPLICIT <- length(CFG_MODELS) > 0L   # an explicit --models= list is the user asking for those

CFG_ENDPOINT_RAW <- Sys.getenv("PMX_ENDPOINT", "")
CFG_ENDPOINT <- character(0)
if (nzchar(CFG_ENDPOINT_RAW) && !identical(tolower(CFG_ENDPOINT_RAW), "legacy") &&
    !identical(tolower(CFG_ENDPOINT_RAW), "off")) {
  CFG_ENDPOINT <- strsplit(CFG_ENDPOINT_RAW, "[|\n]")[[1]]
  CFG_ENDPOINT <- trimws(CFG_ENDPOINT[nzchar(trimws(CFG_ENDPOINT))])
}
LEGACY_ENDPOINT <- c("conc <- f", "conc ~ prop(sdRes)")
endpoint_ok <- function(lines) {
  if (!length(lines) || !any(grepl("~", lines, fixed = TRUE))) {
    cat("LADDER_FAIL endpoint block has no '~' residual line:", paste(lines, collapse = " | "), "\n")
    return(FALSE)
  }
  if (any(grepl("ini[[:space:]]*\\(", lines))) {
    cat("LADDER_FAIL endpoint block must not contain ini(): a model({}) block reads 'x <- c(0, 0.3)' as a 0-argument function definition and rxode2 rejects it.\n")
    return(FALSE)
  }
  TRUE
}
if (length(CFG_ENDPOINT) && !endpoint_ok(CFG_ENDPOINT)) quit(status = 0)

CFG_CORES <- pmx_cpu_integer("PMX_MC_CORES",6L)
# Candidate workers share the host physical-core-minus-two budget and remain memory-bounded.
# The actual pool is also capped by pending candidates (normally at most six).
pmx_cpu_setup()

CFG_WORKER <- suppressWarnings(as.numeric(Sys.getenv("PMX_WORKER_TIMEOUT_S", "900")))
if (!is.finite(CFG_WORKER) || CFG_WORKER <= 0) CFG_WORKER <- 900
CFG_RESERVE <- suppressWarnings(as.numeric(Sys.getenv("PMX_LADDER_RESERVE_S", "60")))
if (!is.finite(CFG_RESERVE) || CFG_RESERVE < 0) CFG_RESERVE <- 60
CFG_LIMIT <- suppressWarnings(as.numeric(Sys.getenv("PMX_LIMIT_S", "0")))
if (!is.finite(CFG_LIMIT) || CFG_LIMIT <= 0) CFG_LIMIT <- max(60, CFG_WORKER - 120 - CFG_RESERVE)
CFG_LIMIT <- min(CFG_LIMIT,max(30,CFG_WORKER-120-CFG_RESERVE))
# A socket wait / native estimator is not bounded by R's setTimeLimit.
# The parent below owns a wall-clock deadline and only its own PSOCK workers.
cat("LADDER_LIMIT_S", CFG_LIMIT, "worker_timeout_s", CFG_WORKER, "VER", LADDER_VER, "\n")

PMX_DIR <- Sys.getenv("PMX_DIR", "")
args <- commandArgs(FALSE)
f0 <- sub("^--file=", "", args[grep("^--file=", args)])
D <- if (nzchar(PMX_DIR)) PMX_DIR else
     if (length(f0) && nzchar(f0[1]) && f0[1] != "-") dirname(normalizePath(f0[1], mustWork = FALSE)) else getwd()
if (!nzchar(PMX_DIR) && !length(list.files(D, "\\.csv$"))) {
  for (cand in unique(c(getwd(), Sys.getenv("ANALYSIS_DIR"), dirname(D)))) {
    if (nzchar(cand) && length(list.files(cand, "\\.csv$"))) { D <- cand; break }
  }
}
setwd(D)
cat("LADDER_DIR", getwd(), "\n")
# Workers are separate processes whose wd is the job initial directory, not the model
# directory, so a bare relative candidate path (--models=m01.ctl) dies in the worker with
# "cannot open file ... No such file or directory" -> empty $INPUT -> "$INPUT has 0 fields".
# Pin the worker wd and the candidate paths to the model directory itself.
CFG_DIR <- getwd()
CFG_ROOT <- Sys.getenv("PMX_ROOT","")
if(!nzchar(CFG_ROOT)) CFG_ROOT <- if(basename(CFG_DIR)=="01_screen") dirname(CFG_DIR) else CFG_DIR
CFG_MODELS <- vapply(CFG_MODELS, function(m) {
  if (nzchar(m) && file.exists(m)) normalizePath(m, mustWork = FALSE) else m
}, character(1), USE.NAMES = FALSE)

NONDATA_CSV <- c("ladder_table.csv", "covariates.csv", "covariates_template.csv")
pick_data <- function(dir) {
  csv <- list.files(dir, "\\.(csv|txt|dat|tab)$", ignore.case = TRUE)
  csv <- csv[!csv %in% NONDATA_CSV & !grepl("\\.fit\\.csv$", csv)]
  if (!length(csv)) return("")
  want <- unique(c("ppk_data.csv", "pkpd_data.csv", "tmdd_data.csv", "cqtc_data.csv",
                   "er_data.csv", "data.csv", paste0(CFG_FAMILY, "_data.csv"),
                   "ppk_data.txt", "data.txt", "ppk_data.dat", "data.dat"))
  hit <- csv[csv %in% want]
  if (length(hit)) return(hit[1])
  csv[order(-file.size(file.path(dir, csv)))[1]]   # else the biggest one is the data
}
if (!nzchar(CFG_DATA)) {
  CFG_DATA <- pick_data(".")
  if (!nzchar(CFG_DATA)) { cat("LADDER_FAIL no data file in", getwd(), "\n"); quit(status = 0) }
}
read_pmx_data <- function(path) {
  first <- tryCatch(readLines(path, n = 1L, warn = FALSE), error = function(e) "")
  main <- if (grepl("\t", first, fixed = TRUE)) "\t" else if (grepl(",", first, fixed = TRUE)) "," else ""
  one <- function(sep) read.csv(path, sep = sep, na = c(".", "", "NA"), check.names = FALSE,
                                stringsAsFactors = FALSE, comment.char = "", strip.white = TRUE)
  d <- tryCatch(one(main), error = function(e) NULL)
  for (s in setdiff(c(",", "\t", "", ";"), main)) {
    if (!is.null(d) && ncol(d) >= 2L) break
    d2 <- tryCatch(one(s), error = function(e) NULL)
    if (!is.null(d2) && ncol(d2) >= 2L) d <- d2
  }
  if (is.null(d) || ncol(d) < 2L) {
    cat("LADDER_FAIL could not read", path, "as comma-, tab- or space-separated\n"); quit(status = 0)
  }
  list(data = d, sep = if (nzchar(main)) main else "whitespace")
}
# The client prepares the content-bound identity; the R worker needs no Node runtime.
ROUND_RECORD <- Sys.getenv("PMX_LADDER_RECORD","")
if(!nzchar(ROUND_RECORD)) stop("LADDER_ENTRYPOINT_REQUIRED: use analyses_template/tools/fit_ladder.sh; do not hand-build a worker script")
ROUND_RECORD <- jsonlite::fromJSON(ROUND_RECORD,simplifyVector=FALSE)
screen_status <- function(error,ofv) {
  if(!nzchar(error) && is.finite(ofv)) "completed"
  else if(grepl("not started|not attempted",error,ignore.case=TRUE)) "unstarted"
  else if(grepl("stopped after|cancel",error,ignore.case=TRUE)) "cancelled"
  else if(grepl("time limit|timed out|timeout",error,ignore.case=TRUE)) "timed_out" else "failed"
}
screen_rows <- function(rows,selected=NULL) {
  rows$model <- basename(rows$model)
  rows$round_id <- rep(ROUND_RECORD$key,nrow(rows))
  rows$bic_definition <- rep("native logLik BIC",nrow(rows))
  rows$data_md5 <- rep(ROUND_RECORD$inputs$data,nrow(rows))
  rows$model_md5 <- vapply(rows$model,function(m) {
    pair <- Filter(function(p) identical(p[[1]],m),ROUND_RECORD$inputs$models)
    if(length(pair)==1L) pair[[1]][[2]] else ""
  },"")
  rows$status <- vapply(seq_len(nrow(rows)),function(i) screen_status(rows$error[i],rows$ofv[i]),"")
  rows$selected <- if(is.null(selected) || !length(selected)) rep(FALSE,nrow(rows)) else rows$model %in% basename(as.character(selected))
  rows
}
write_screen_history <- function(rows,selected=NULL) {
  current <- screen_rows(rows,selected)
  old <- if(file.exists("ladder_table.csv")) read.csv("ladder_table.csv",stringsAsFactors=FALSE,check.names=FALSE) else current[0,,drop=FALSE]
  required <- c("model","ofv","npar","bic","secs","error")
  if(!all(required %in% names(old))) stop("LADDER_HISTORY_INVALID: preserve the existing table; do not reset it")
  old$model <- basename(old$model);old$error <- as.character(old$error);old$error[is.na(old$error)] <- ""
  for(n in setdiff(names(current),names(old))) old[[n]] <- if(n=="round_id") rep("legacy",nrow(old)) else if(n=="selected") rep(FALSE,nrow(old)) else rep("",nrow(old))
  old$round_id[is.na(old$round_id) | !nzchar(old$round_id)] <- "legacy"
  missing_status <- is.na(old$status) | !nzchar(old$status)
  if(any(missing_status)) old$status[missing_status] <- vapply(which(missing_status),function(i) screen_status(old$error[i],old$ofv[i]),"")
  old$selected[is.na(old$selected)] <- FALSE
  identity <- function(d) paste(d$round_id,d$data_md5,d$model,d$model_md5,sep="|")
  # Keep original fit duration when an export/cache-only visit returns secs=0.
  hits <- match(identity(current),identity(old))
  for(i in which(!is.na(hits))) if(isTRUE(current$secs[i]==0) && is.finite(old$secs[hits[i]])) current$secs[i] <- old$secs[hits[i]]
  all <- rbind(old[,names(current),drop=FALSE],current)
  all <- all[!duplicated(identity(all),fromLast=TRUE),,drop=FALSE]
  temporary <- paste0("ladder_table.csv.",Sys.getpid(),".tmp")
  write.csv(all,temporary,row.names=FALSE,na="")
  Sys.chmod(temporary,"0644")
  if(!file.rename(temporary,"ladder_table.csv")) stop("LADDER_HISTORY_WRITE_FAILED: previous results preserved")
  invisible(all)
}

record_round <- function(state) {
  snapshot <- ROUND_RECORD
  if(!identical(unname(tools::md5sum(CFG_DATA)),snapshot$inputs$data) ||
     any(vapply(snapshot$inputs$models,function(m) {
       ctl <- CFG_MODELS[basename(CFG_MODELS)==m[[1]]]
       length(ctl)!=1L || !identical(unname(tools::md5sum(ctl)),m[[2]])
     },TRUE))) stop("LADDER_INPUT_CHANGED: do not edit data/candidates while screening")
  snapshot$state <- state
  snapshot$base_md5 <- if(state=="complete") unname(tools::md5sum(file.path(CFG_ROOT,"base_model.ctl"))) else NULL
  if(state=="complete") {
    fit_file <- paste0(sub(".ctl$","",basename(best)),".fit.rds")
    snapshot$selected <- list(candidate=basename(best),fit_file=file.path(if(basename(CFG_DIR)=="01_screen") "01_screen" else "",fit_file),
      fit_md5=unname(tools::md5sum(file.path(CFG_DIR,fit_file))),
      fit_key=readLines(file.path(CFG_DIR,sub(".rds$",".key",fit_file)),n=1L,warn=FALSE),
      contract=FIT_CONTRACT,control=FIT_CONTROL)
    stored_key <- readLines(file.path(CFG_DIR,sub(".rds$",".key",fit_file)),n=2L,warn=FALSE)
    parts <- strsplit(stored_key[1],"|",fixed=TRUE)[[1]]
    snapshot$selected$contract <- parts[8]
    snapshot$selected$control <- parts[9]
    if(length(stored_key)==2L && parts[1]=="FIT3")
      snapshot$selected$settings <- jsonlite::fromJSON(stored_key[2],simplifyVector=FALSE)
  }
  dir.create(file.path(CFG_ROOT,".pmx"),showWarnings=FALSE,recursive=TRUE)
  ledger <- file.path(CFG_ROOT,".pmx","ladder_round.json")
  temporary <- paste0(ledger,".",Sys.getpid(),".tmp")
  jsonlite::write_json(snapshot,temporary,auto_unbox=TRUE,null="null")
  Sys.chmod(temporary,"0644")
  if(!file.rename(temporary,ledger)) stop("LADDER_RECORD_FAILED: completed fits preserved; do not refit")
  cat("LADDER_RECORDED ",state,"\n",sep="")
}

contract <- file.path(Sys.getenv("PMX_TOOLKIT", ""), "analyses_template","tools", "model_contract.R")
if (!file.exists(contract)) stop("Missing analyses_template/tools/model_contract.R; pass PMX_TOOLKIT")
source(contract)

if (!length(CFG_MODELS)) {
  CFG_MODELS <- sort(list.files(".", "\\.ctl$"))
  CFG_MODELS <- CFG_MODELS[!CFG_MODELS %in% c("base_model.ctl", "final_model.ctl","recommended_base.ctl",
                                              paste0(CFG_FAMILY, "_model.ctl"),
                                              "ppk_model.ctl", "pkpd_model.ctl")]
}
# Ladder width. One screening round fits at most CFG_CAND_MAX candidates (house default 6) and then
# promotes its own winner, so a completed round needs no human step. An explicit --models= list is the
# caller asking for exactly those candidates, and --cand-max=N raises the cap deliberately.
if (!CFG_MODELS_EXPLICIT && length(CFG_MODELS) > CFG_CAND_MAX) {
  cat("LADDER_CANDIDATE_CAP requested", length(CFG_MODELS), "-> fitting", CFG_CAND_MAX,
      "(candidates", paste(CFG_MODELS[-seq_len(CFG_CAND_MAX)], collapse = " "),
      "held back; pass --cand-max=N or list them with --models= to fit more)\n")
  CFG_MODELS <- CFG_MODELS[seq_len(CFG_CAND_MAX)]
}
cat("LADDER_MODELS", paste(CFG_MODELS, collapse = " "), "\n")

if(!length(CFG_MODELS)) stop("No candidate control streams")
rd <- read_pmx_data(CFG_DATA)          # also the separator reported on the LADDER_DATA line
preflight <- lapply(CFG_MODELS,function(m) tryCatch({
  pmx_check_indexed_eta(m); pmx_validate_ctl(m); pmx_validate_input_roles(m,CFG_DATA); pmx_read_data(CFG_DATA,m); ""
},error=function(e) conditionMessage(e)))
names(preflight) <- CFG_MODELS
valid <- CFG_MODELS[!nzchar(unlist(preflight))]
if(!length(valid)) {
  tb <- data.frame(model=CFG_MODELS,ofv=NA_real_,npar=NA_integer_,bic=NA_real_,secs=0,
                   error=unlist(preflight),stringsAsFactors=FALSE)
  write_screen_history(tb)
  record_round("failed")
  cat("LADDER_STOP no valid candidate; repair the recorded input/structure defect, do not resubmit unchanged models\n")
  quit(status=1)
}
DATA <- pmx_read_data(CFG_DATA,valid[1])
if (is.null(DATA)) {
  DATA <- rd$data
} else {
  cat("LADDER_READDATA", paste0(CFG_FAMILY, "_model.R read_data()\n"))
}
names(DATA) <- tolower(names(DATA))
cohort_key <- function(d) unname(as.matrix(d[,c("id","time","dv","evid","amt","mdv"),drop=FALSE]))
COHORT <- cohort_key(DATA)
miss <- setdiff(c("time", "dv"), names(DATA))
if (length(miss)) {
  cat("LADDER_FAIL data is missing required column(s):", paste(miss, collapse = " "),
      "- columns present:", paste(names(DATA), collapse = " "), "\n")
  quit(status = 0)
}
if (!"dvid" %in% names(DATA)) DATA$dvid <- 1L
if (!"eps1" %in% names(DATA)) DATA$eps1 <- 0
if (!"eps2" %in% names(DATA)) DATA$eps2 <- 0
has_evid <- "evid" %in% names(DATA)
has_mdv  <- "mdv"  %in% names(DATA)
if (has_evid) DATA$dv[!is.na(DATA$evid) & DATA$evid != 0] <- NA
if (has_mdv)  DATA$dv[!is.na(DATA$mdv)  & DATA$mdv  != 0] <- NA
DOSE_ROWS <- if (has_evid) (!is.na(DATA$evid) & DATA$evid != 0) else
             if ("amt" %in% names(DATA)) (!is.na(DATA$amt) & DATA$amt != 0) else
             rep(FALSE, nrow(DATA))
CMT_MODE <- "keep"
if ("cmt" %in% names(DATA)) {
  spec <- tolower(trimws(Sys.getenv("PMX_CMT_OBS", "auto")))
  cv <- suppressWarnings(as.numeric(DATA$cmt))
  use <- cv[!DOSE_ROWS & !is.na(cv) & cv > 0]
  if (grepl("^[0-9]+$", spec)) {
    CMT_MODE <- "fixed"
    DATA$cmt <- ifelse(DOSE_ROWS, DATA$cmt, as.numeric(spec))
    cat("LADDER_CMT_OBS", spec, "forced (dose rows keep their own CMT)\n")
  } else if (identical(spec, "keep")) {
    cat("LADDER_CMT_OBS keep (dataset CMT used as-is)\n")
  } else if (length(use)) {
    cat("LADDER_CMT_OBS auto: dataset CMT used -", length(use), "observation rows, cmt",
        paste(sort(unique(use)), collapse = "/"), "\n")
  } else {
    CMT_MODE <- "per-model"
    cat("LADDER_CMT_OBS auto: no usable CMT on the observation rows -> derived per model\n")
  }
}
observ <- if (has_evid) (!is.na(DATA$evid) & DATA$evid == 0) else
          if (has_mdv)  (!is.na(DATA$mdv)  & DATA$mdv  == 0) else rep(TRUE, nrow(DATA))
NOBS <- sum(observ & !is.na(DATA$dv))
if (!is.finite(NOBS) || NOBS <= 0) {
  cat("LADDER_FAIL no observation rows: could not find an EVID/MDV/DV pattern that marks",
      "observation records (rows", nrow(DATA), ")\n")
  quit(status = 0)
}
IDC <- intersect(c("id", "subject", "subj", "idnum"), names(DATA))
cat("LADDER_DATA", CFG_DATA, "sep", rd$sep, "rows", nrow(DATA),
    "subjects", if (length(IDC)) length(unique(DATA[[IDC[1]]])) else "?",
    "NOBS", NOBS, "\n")


suppressPackageStartupMessages({ library(nonmem2rx); library(nlmixr2); library(rxode2) })

screen_controls <- pmx_screen_controls()
CTL <- screen_controls$CTL
RX <- screen_controls$RX

ofv_of <- function(fit) for (x in list(fit$objf, fit$ofv, fit$objective, fit$objective_function)) {
  v <- suppressWarnings(tryCatch(as.numeric(x)[1], error = function(e) NA_real_))
  if (length(v) == 1 && is.finite(v)) return(v)
}
npar_of <- function(fit) {
  v <- as.numeric(attr(stats::logLik(fit),"df"))
  if(length(v)!=1L || !is.finite(v) || v<=0) stop("FIT_PARAMETER_COUNT_UNAVAILABLE: native logLik df required")
  v
}

h_text <- function(x) tryCatch(as.character(rlang::hash(x)), error = function(e) as.character(sum(utf8ToInt(x))))
h_file <- function(p) tryCatch(as.character(tools::md5sum(p))[1], error = function(e) "NA")
DATA_KEY <- paste0(h_file(CFG_DATA), ":", sum(file.size(CFG_DATA)))
FIT_CONTRACT <- pmx_screen_contract(valid[1])
FIT_SETTINGS <- pmx_screen_settings(CTL,RX)
FIT_CONTROL <- pmx_screen_digest(FIT_SETTINGS)
cache_key <- function(ctl,ep) paste("FIT3",h_file(ctl),DATA_KEY,
  h_text(list(lines=ep,sds=pmx_endpoint(ctl)$sds,selector=pmx_run_setting(ctl,"PMX_DVID"))),1L,CMT_MODE,Sys.getenv("PMX_CMT_OBS"),
  pmx_screen_contract(ctl),FIT_CONTROL,pmx_screen_recipe,sep="|")
cache_matches <- function(keyfile,ctl,ep) {
  if(!file.exists(keyfile)) return(FALSE)
  stored <- readLines(keyfile,n=2L,warn=FALSE)
  if(!length(stored)) return(FALSE)
  if(identical(stored[1],cache_key(ctl,ep))) {
    if(length(stored)!=2L) stop("LADDER_CACHE_IDENTITY_MISSING: named settings absent; do not refit")
    settings <- jsonlite::fromJSON(stored[2],simplifyVector=FALSE)
    if(!identical(pmx_screen_digest(settings),FIT_CONTROL)) stop("LADDER_CACHE_IDENTITY_CHANGED: named settings changed; do not refit")
    return(TRUE)
  }
  # One exact legacy comparison, using the producer's recorded version, never guessed widths/versions.
  parts <- strsplit(stored[1],"|",fixed=TRUE)[[1]]
  if(length(parts)==10L && parts[1]=="FIT2") {
    expected <- c(h_file(ctl),DATA_KEY,h_text(paste(ep,collapse="|")))
    rx <- RX;rx[intersect(names(rx),"cores")] <- NULL
    raw_control <- h_text(list(CTL=CTL,RX=rx,packages=vapply(
      c("nlmixr2","nlmixr2est","rxode2","nonmem2rx"),function(p) as.character(packageVersion(p)),"")))
    return(identical(parts[2:4],expected) &&
      parts[5]==as.character(ROUND_RECORD$inputs$runtime$version) &&
      identical(parts[6:9],c(CMT_MODE,Sys.getenv("PMX_CMT_OBS"),FIT_CONTRACT,raw_control)))
  }
  FALSE
}

append_row <- function(r) tryCatch({
  # Parent normalizes the schema before workers start; workers append one CSV line.
  r <- screen_rows(r)
  q <- function(x) paste0('"',gsub('"','""',gsub("[\r\n]+"," ",as.character(x))), '"')
  con <- file("ladder_table.csv",open="a");on.exit(close(con),add=TRUE)
  writeLines(paste(vapply(r,q,""),collapse=","),con)
},error=function(e) cat("LADDER_NOTE could not append screening history: ",conditionMessage(e),"\n",sep=""))

translate <- function(m) {
  pmx_validate_ctl(m)
  for (a in list(list(lst = ".res", save = FALSE, validate = FALSE), list(validate = FALSE), list())) {
    out <- tryCatch(do.call(nonmem2rx::nonmem2rx, c(list(file = m,thetaNames=pmx_theta_names(m),etaNames=pmx_eta_names(m)), a)), error = function(e) NULL)
    if (!is.null(out)) return(out)
  }
  stop("nonmem2rx could not translate ", m)
}

resolve_endpoint <- function(m) {
  ep <- pmx_endpoint(m)
  list(lines=ep$lines,sds=ep$sds,src="control-stream")
}
fit_candidate <- function(m) {
  candidate_data <- pmx_read_data(CFG_DATA,m)
  if(!identical(cohort_key(candidate_data),COHORT)) stop("Candidate DATA filters/input mapping change the analysis cohort; compare models on the same records")
  tag <- sub("\\.ctl$", "", m); cache <- paste0(tag, ".fit.rds"); keyf <- paste0(tag, ".fit.key")
  t0 <- Sys.time(); ofv <- NA_real_; np <- NA_integer_; err <- ""; fit <- NULL
  r <- resolve_endpoint(m); ep <- r$lines; sds <- r$sds; src <- r$src
  if (!endpoint_ok(ep)) stop("Invalid endpoint metadata in ",m)
  cat("LADDER_ENDPOINT", m, src, paste(ep, collapse = " | "),
      if (length(sds)) paste0("sd=", paste(signif(sds, 4), collapse = ",")) else "", "\n")
  key <- cache_key(m, ep)
  if (file.exists(cache) && file.exists(keyf) && cache_matches(keyf,m,ep)) {
    cat("LADDER_CACHED", m, "\n")
    fit <- tryCatch(readRDS(cache), error = function(e) NULL)
    if (is.null(fit)) err <- "cache unreadable" else { ofv <- ofv_of(fit); np <- npar_of(fit) }
  } else {
    if (file.exists(cache)) cat("LADDER_STALE_CACHE", m, "(data, .ctl or fitting contract changed - refitting)\n")
    fit <- tryCatch({
    if (identical(CMT_MODE, "per-model")) {
      k <- ctl_obs_cmt(m)
      if (is.na(k)) cat("LADDER_NOTE", m, "observation compartment unreadable - dataset CMT left as is\n")
      else {
        DATA$cmt <<- ifelse(DOSE_ROWS, DATA$cmt, k)
        cat("LADDER_CMT_OBS", m, "derived", k, "from the model's own prediction\n")
      }
    }
      DATA <- candidate_data
      if(!"dvid" %in% names(DATA)) {
        spec <- pmx_run_setting(m,"PMX_DVID")
        if(nzchar(spec)) {
          v <- tolower(trimws(sub("=.*","",spec)))
          lv <- as.numeric(strsplit(sub("^[^=]*=","",spec),",")[[1]])
          if(!v %in% names(DATA)) stop("PMX_DVID source column missing")
          DATA$dvid <- match(DATA[[v]],lv); DATA$dvid[DATA$evid!=0] <- 1L
          if(anyNA(DATA$dvid[DATA$evid==0])) stop("Unmapped observation in PMX_DVID")
        } else if(sum(grepl("~",ep,fixed=TRUE))>1L) stop("Multi-endpoint data require an observation selector in the model or study run settings") else DATA$dvid <- 1L
      }
      if(!"cmt" %in% names(DATA)) {
        if(any(DATA$evid!=0)) stop("Dose records require CMT")
        DATA$cmt <- ctl_obs_cmt(m)
      }
      if(sum(grepl("~",ep,fixed=TRUE))>1L && CMT_MODE!="keep") stop("Multi-endpoint observation compartments must be supplied explicitly; do not collapse them to one CMT")
      if(identical(CMT_MODE,"fixed")) DATA$cmt[DATA$evid==0] <- as.numeric(Sys.getenv("PMX_CMT_OBS"))
      else if(identical(CMT_MODE,"per-model")) DATA$cmt[DATA$evid==0] <- ctl_obs_cmt(m)
      if("dvid" %in% names(DATA) && !"nmdvid" %in% names(DATA)) DATA$nmdvid <- DATA$dvid
      ui <- translate(m)
      cat("LADDER_TRANSLATED", m, "theta", length(ui$theta), "etas", length(ui$eta), "\n")
      ui <- pmx_attach_endpoints(ui,list(lines=ep,sds=sds))
      DATA <- pmx_endpoint_data(ui,DATA)
      warnings <- character()
      f <- withCallingHandlers(nlmixr2(ui, DATA, est = "focei", control = CTL),
        warning=function(w) {warnings <<- c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
      attr(f,"pmx_fit_warnings") <- unique(c(as.character(f$runInfo),warnings))
      pmx_require_fit_quality(f,paste("screen",m))
      if(identical(pmx_fit_quality(f)$state,"warning")) cat("LADDER_FIT_WARNING ",m,": ",paste(pmx_fit_quality(f)$warnings,collapse=" | "),"\n",sep="")
      if(!is.finite(ofv_of(f))) stop("Fit returned no finite objective")
      if(is.numeric(f$convergence) && length(f$convergence) && any(f$convergence!=0)) stop("Fit did not converge")
      pmx_screen_bic(f)
      saveRDS(f, cache)
      writeLines(c(key,as.character(jsonlite::toJSON(FIT_SETTINGS,auto_unbox=TRUE))), keyf)
      f
    }, error = function(e) { err <<- conditionMessage(e); NULL })
    if (!is.null(fit)) { ofv <- ofv_of(fit); np <- npar_of(fit) }
  }
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  if (is.null(fit)) cat("LADDER_FAILED", m, "|", gsub("[\r\n]+", " ", err), "\n")
  cat("LADDER_ROW", m, "ofv", ofv, "npar", np, "secs", secs, "\n")
  row <- data.frame(model = m, ofv = ofv, npar = np,
                    bic = if (!is.null(fit) && is.finite(ofv) && is.finite(np)) pmx_screen_bic(fit) else NA_real_,
                    secs = secs, error = err, stringsAsFactors = FALSE)
  append_row(row)   # survive a job that never reaches the end of the loop
  row
}
safe_fit <- function(m) tryCatch(fit_candidate(m),
  error = function(e) {
    r <- data.frame(model = m, ofv = NA_real_, npar = NA_integer_, bic = NA_real_,
                    secs = NA_real_, error = conditionMessage(e), stringsAsFactors = FALSE)
    append_row(r); r
  })

write_screen_history(data.frame(model=character(),ofv=numeric(),npar=integer(),bic=numeric(),
  secs=numeric(),error=character(),stringsAsFactors=FALSE))

rows <- list(); n_refit <- 0L; queued <- CFG_MODELS
t_start <- Sys.time()
deadline <- as.numeric(t_start)+CFG_LIMIT
cached_row <- function(m) {
  tag <- sub("\\.ctl$","",m); cache <- paste0(tag,".fit.rds"); keyf <- paste0(tag,".fit.key")
  if(!file.exists(cache) || !file.exists(keyf)) return(NULL)
  key <- tryCatch(cache_key(m,resolve_endpoint(m)$lines),error=function(e) NA_character_)
  if(!cache_matches(keyf,m,resolve_endpoint(m)$lines)) return(NULL)
  fit <- tryCatch(readRDS(cache),error=function(e) NULL)
  if(is.null(fit)) return(NULL)
  quality <- pmx_fit_quality(fit)
  if(!quality$ok) return(failed_row(m,paste("Cached fit requires convergence review:",paste(quality$problems,collapse=" | "))))
  ofv <- ofv_of(fit); np <- npar_of(fit)
  if(!is.finite(ofv) || !is.finite(np)) return(NULL)
  data.frame(model=m,ofv=ofv,npar=np,bic=pmx_screen_bic(fit),secs=0,error="",stringsAsFactors=FALSE)
}
failed_row <- function(m,reason) data.frame(model=m,ofv=NA_real_,npar=NA_integer_,bic=NA_real_,
  secs=NA_real_,error=reason,stringsAsFactors=FALSE)
pending <- character(); started <- character()
export_only <- identical(Sys.getenv("PMX_LADDER_EXPORT_ONLY","0"),"1")
terminal_rows <- if(export_only && file.exists("ladder_table.csv")) read.csv("ladder_table.csv",stringsAsFactors=FALSE) else NULL
if(!is.null(terminal_rows)) {
  terminal_rows$error <- as.character(terminal_rows$error)
  terminal_rows$error[is.na(terminal_rows$error)] <- ""
  terminal_rows <- terminal_rows[terminal_rows$round_id==ROUND_RECORD$key,,drop=FALSE]
}
for(m in queued) {
  if(nzchar(preflight[[m]])) rows[[m]] <- failed_row(m,preflight[[m]])
  else {
    old <- if(!is.null(terminal_rows)) terminal_rows[basename(terminal_rows$model)==basename(m),,drop=FALSE] else NULL
    if(export_only && !is.null(old) && nrow(old)==1L && (!is.finite(old$bic) || nzchar(old$error))) {
      rows[[m]] <- failed_row(m,old$error);next
    }
    cached <- cached_row(m)
    if(!is.null(cached)) {rows[[m]] <- cached;cat("LADDER_CACHED",m,"\n")}
    else if(length(pending)>=CFG_MAXFIT) rows[[m]] <- failed_row(m,"Not attempted: explicit maxfit limit; not automatically retried")
    else pending <- c(pending,m)
  }
}
if(identical(Sys.getenv("PMX_LADDER_EXPORT_ONLY","0"),"1") && length(pending))
  stop("LADDER_EXPORT_CACHE_MISSING: export-only never fits models; preserve caches and review their identity")
n_refit <- length(pending)
run_bounded <- function(pending) {
  if(!length(pending)) return(invisible(NULL))
  cpu <- pmx_cpu_plan(length(pending),worker_cap=CFG_CORES,data_bytes=as.numeric(object.size(DATA)))
  pmx_cpu_log("SCREEN",cpu)
  n <- cpu$workers
  cat("LADDER_PARALLEL psock cores",n,"submitted candidates",length(queued),"pending",length(pending),"\n")
  cl <- NULL; pids <- integer()
  cleanup <- function() {
    # Never kill a worker belonging to another queue job.
    for(pid in pids) try(tools::pskill(pid,signal=9L),silent=TRUE)
    if(!is.null(cl)) for(node in cl) try(close(node$con),silent=TRUE)
  }
  on.exit(cleanup(),add=TRUE)
  tryCatch({
    remaining <- max(1,deadline-as.numeric(Sys.time()))
    cl <- parallel::makePSOCKcluster(n,outfile="",rscript_args="--vanilla",setup_timeout=min(60,remaining),timeout=remaining)
    pids <- unlist(parallel::clusterCall(cl,Sys.getpid))
    parallel::clusterExport(cl,varlist=setdiff(ls(envir=globalenv()),c("cl","res")),envir=globalenv())
    parallel::clusterCall(cl,function(threads) {
      pmx_cpu_setup(threads=threads)
      suppressMessages({library(nlmixr2);library(rxode2);library(dplyr);library(lotri)})
      pmx_cpu_setup(threads=threads,rx=TRUE)
      control <- get("RX",envir=.GlobalEnv);control$cores <- threads
      assign("RX",control,envir=.GlobalEnv)
      setwd(CFG_DIR);invisible(NULL)
    },cpu$threads)
    active <- rep(NA_integer_,n);next_task <- 1L
    dispatch <- function(worker) {
      if(next_task>length(pending)) return(invisible(NULL))
      task <- next_task;next_task <<- next_task+1L;active[worker] <<- task
      parallel:::sendCall(cl[[worker]],safe_fit,list(pending[task]),tag=task)
      started <<- c(started,pending[task])
    }
    for(worker in seq_len(n)) dispatch(worker)
    while(any(!is.na(active))) {
      remaining <- deadline-as.numeric(Sys.time());if(remaining<=0) break
      workers <- which(!is.na(active))
      ready <- socketSelect(lapply(cl[workers],function(node) node$con),timeout=min(1,remaining))
      for(worker in workers[ready]) {
        m <- pending[active[worker]]
        value <- tryCatch(parallel:::recvResult(cl[[worker]]),error=function(e) failed_row(m,paste("Fitting worker lost:",conditionMessage(e))))
        if(!is.data.frame(value)) value <- failed_row(m,"Fitting worker returned no usable result")
        rows[[m]] <<- value;active[worker] <- NA_integer_
      }
      for(worker in which(is.na(active))) dispatch(worker)
    }
  },error=function(e) cat("LADDER_WORKER_ERROR",conditionMessage(e),"- no automatic fallback/refit\n"))
}
run_bounded(pending)
for(m in pending) if(is.null(rows[[m]])) {
  # A worker may have persisted a valid fit just before its deadline.
  row <- cached_row(m)
  reason <- if(m %in% started) "Screening time limit reached or fitting worker unavailable; no completed fit; not automatically retried" else
    "Not attempted before screening deadline or worker setup failed; not automatically retried"
  rows[[m]] <- if(!is.null(row)) row else failed_row(m,reason)
}
res <- unname(rows[queued])
budget_truncated <- FALSE
for (i in seq_along(queued)) rows[[queued[i]]] <- res[[i]]   # .ctl order, not finish order
rows <- rows[!vapply(rows, is.null, TRUE)]
tb <- if (length(rows)) do.call(rbind, rows) else NULL
if (is.null(tb) || !nrow(tb)) { cat("LADDER_FAIL no candidate could be read\n"); quit(status = 0) }
tb <- tb[order(tb$bic, na.last = TRUE), ]
print(tb, row.names = FALSE)
write_screen_history(tb)   # current ranking stays separate from cumulative history

wall <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
per <- if (n_refit > 0) wall / n_refit else NA_real_
if (is.finite(per) && per >= 1) {
  cat(sprintf("LADDER_TIME total=%.0fs refitted=%d per_candidate=%.0fs -> PMX_LIMIT_S=%.0f (Inf = no cap); pass --maxfit=N only to deliberately split a round\n",
              wall, n_refit, per, CFG_LIMIT))
} else {
  cat(sprintf("LADDER_TIME total=%.0fs refitted=%d (all served from cache, or fits too fast to size a job from)\n", wall, n_refit))
}


ok <- tb[is.finite(tb$bic) & !nzchar(tb$error), , drop = FALSE]
ROOT <- Sys.getenv("PMX_ROOT", "")
if (!nzchar(ROOT)) ROOT <- if (identical(basename(getwd()), "01_screen")) dirname(getwd()) else getwd()
if (!nrow(ok)) {
  record_round("failed")
  cat("\nLADDER_STOP nothing fitted - recorded failures; no unchanged retry; no base model is promoted\n")
} else {
  best <- ok$model[1]; dest <- file.path(ROOT, "base_model.ctl")
  suggested <- file.path(getwd(),"recommended_base.ctl")
  updated_initials <- function(model) {
    cache <- paste0(sub("\\.ctl$","",model),".fit.rds")
    keyfile <- paste0(sub("\\.ctl$","",model),".fit.key")
    ep <- resolve_endpoint(model)$lines
    if(!file.exists(cache) || !file.exists(keyfile) || !cache_matches(keyfile,model,ep))
      stop("Selected fit cache does not match candidate/data; never publish guessed initials")
    tryCatch(pmx_frozen_ctl(model,readRDS(cache),digits=4L),error=function(e) {
      record_round("export_required")
      stop("LADDER_EXPORT_REQUIRED: ",conditionMessage(e),"; repair export source and resume --export-only; never refit completed candidates")
    })
  }
  writeLines(updated_initials(best),suggested)
  choice <- file.path(ROOT,"base_selection.dcf")
  if(!file.exists(choice)) {
    if (CFG_MANUAL_SELECT) {
      cat("LADDER_NEEDS_SELECTION recommended=",best,"; record Candidate and Reason in base_selection.dcf, then resume\n")
      quit(status=2)
    }
    # House default: the ladder promotes its own winner, so a completed round needs no human step.
    # The winner is the lowest BIC among the candidates fitted in THIS round, on one cohort, with one
    # residual contract. The record is written to disk first, so it can be edited and re-run to override.
    runner_up <- if (nrow(ok) > 1L) sprintf("runner-up %s (dBiC %+.3f); ", ok$model[2], ok$bic[2] - ok$bic[1]) else ""
    writeLines(c(sprintf("Candidate: %s", best),
                 sprintf("Reason: lowest BIC (%.3f) among %d successfully completed candidates on one cohort; %sauto-selected by fit_ladder (cand-max=%d) - edit Candidate/Reason and re-run to override",
                         ok$bic[match(best, ok$model)], nrow(ok), runner_up, CFG_CAND_MAX)), choice)
    cat("LADDER_AUTO_SELECT", best, "BIC", round(ok$bic[match(best,ok$model)], 3),
        "(lowest of", nrow(ok), "fitted; write", choice, "to override; --manual-select to be asked)\n")
  }
  decision <- read.dcf(choice)
  if(!all(c("Candidate","Reason") %in% colnames(decision)) || !nzchar(trimws(decision[1,"Reason"]))) stop("Selection requires Candidate and scientific Reason")
  selected <- basename(trimws(decision[1,"Candidate"]))
  hit <- which(basename(ok$model) == selected)
  if(!length(hit)) stop("Selected candidate is not a successfully fitted model")
  best <- ok$model[hit[1]]
  writeLines(updated_initials(best),dest)
  cat("BASE_INITIALS_UPDATED source=",best," digits=4; candidate sources unchanged\n",sep="")
  write_screen_history(tb,selected=best)
  record_round("complete")
  cat("\nBEST", best, "BIC", round(ok$bic[match(best,ok$model)], 3), "->", dest, "\n")
  agent_dir <- Sys.getenv("PMX_LADDER_AGENT_DIR",CFG_ROOT)
  agent_toolkit <- Sys.getenv("PMX_LADDER_AGENT_TOOLKIT",Sys.getenv("PMX_TOOLKIT"))
  next_command <- paste("sh",shQuote(file.path(agent_toolkit,"analyses_template","tools","run_analysis.sh")),
    shQuote(agent_dir),paste0("--family=",CFG_FAMILY),"--skip-nca --skip-ladder")
  cat("LADDER_HANDOFF screen complete; review selection once, then submit SCM/freeze/report; do not poll or screen again\n")
  cat("LADDER_NEXT ",next_command,"\n",sep="")
  if (nrow(ok) == nrow(tb)) cat("LADDER_OK best=", best, " bic=", round(ok$bic[match(best,ok$model)], 3), "\n", sep = "")
  else cat("LADDER_PARTIAL fitted=", nrow(ok), "/", nrow(tb), " best=", best,
           " bic=", round(ok$bic[match(best,ok$model)], 3), "\n", sep = "")
}
