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

A <- commandArgs(trailingOnly=TRUE)
FAM <- "ppk"
if("--family" %in% A) { i <- which(A=="--family"); FAM <- A[i+1]; A <- A[-c(i,i+1)] }
pmx_start(A[1],"s1c")
FAM <- sub("_data\\.csv$","",FAM)
if(!stage_current("s1",FAM)) stop("S1C requires the current S1 search checkpoint; never refit in covariance")
stage_require("s1c","s1")
stage_invalidate("s1c")
pmx_covariance_state("PENDING","Independent covariance job; search estimates remain complete")
status <- tryCatch(system2("Rscript",c(shQuote(file.path(.here,"..","run_pipeline.R")),".",
  "--family",FAM,"--phase","covariance")),error=function(e) { cat(conditionMessage(e),"\n"); 1L })
if(status!=0L) {
  pmx_covariance_state(if(status==3L) "DEFERRED" else "FAILED",
    paste("s1c exit",status,"; preserve search checkpoint/caches; repair the covariance cause"))
  cat("S1C_STOP estimates complete; uncertainty incomplete; no report completion\n")
  quit(save="no",status=status)
}
r <- readRDS("_scm_final_result.rds")
cov_state <- r$covariance$state
if(!is.character(cov_state) || !cov_state %in% c("complete","unestimable"))
  stop("S1C returned without completed or explicitly unestimable final covariance")
if(identical(cov_state,"unestimable")) {
  # run_pipeline.R only writes this state under the explicit opt-in; check it again
  # here so a hand-edited result cannot silently turn missing uncertainty into success.
  if(!tolower(trimws(Sys.getenv("PMX_COV_UNESTIMABLE_CONTINUE",""))) %in% c("true","1","yes","on"))
    stop("S1C_UNESTIMABLE_NOT_AUTHORIZED: covariance is not estimable but PMX_COV_UNESTIMABLE_CONTINUE is not set")
  methods <- paste(r$covariance$methods,collapse="/")
  cat("S1C_UNESTIMABLE estimates complete; post-fit covariance not estimable by ",methods,
      "; estimates preserved, report SE/RSE left blank with disclosure\n",sep="")
  pmx_covariance_state("UNESTIMABLE",paste("post-fit covariance not estimable (",methods,
    "); estimates preserved; report uncertainty blank with disclosure"))
  stage_invalidate(c("s2","s3","s4","s5"))
  stage_close("s1c",stage_inputs("s1c",FAM),stage_outputs("s1c",FAM),
    note="Explicit PMX_COV_UNESTIMABLE_CONTINUE: covariance not estimable; estimates preserved, report uncertainty left blank with disclosure")
  quit(save="no",status=0)
}
base_requested <- tolower(Sys.getenv("PMX_COV_BASE",if(FAM=="ppk") "true" else "false")) %in% c("true","1","yes")
if(base_requested && identical(r$covariance$base_method,"not_requested"))
  stop("S1C_BASE_COVARIANCE_REQUIRED: preserve search fits and complete base uncertainty")
pmx_covariance_state("COMPLETE",paste("final method",r$covariance$final_method,"; base",r$covariance$base_method))
stage_invalidate(c("s2","s3","s4","s5"))
stage_close("s1c",stage_inputs("s1c",FAM),stage_outputs("s1c",FAM),
  note="Requested base/final uncertainty complete; search fits reused without optimization")
