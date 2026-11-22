# The queue reserves publication/cleanup outside the stage cap.
pmx_scm_window <- function(stage,worker,headroom,requested=stage,remaining=Inf) {
  if(any(!is.finite(c(stage,worker,headroom,requested))) || stage<=0 || worker<=60 ||
     headroom<0 || requested<=0 || length(remaining)!=1L || is.na(remaining))
    stop("SCM_BUDGET_INVALID: finite positive limits and nonnegative headroom required")
  limit <- min(stage,min(worker,900)-max(headroom,20),requested,remaining)
  if(limit<60) stop("SCM_BUDGET_INVALID: less than 60s remain under the existing hard caps")
  limit
}
PMX_ADMIT_MARGIN_S <- function(window) min(60,max(20,0.05*window))
pmx_scm_admit <- function(required,left,window,defer_work,what) {
  if(any(!is.finite(c(required,left,window))) || required<0 || window<=0)
    stop("SCM_BUDGET_INVALID: invalid admission estimate")
  if(required>window)
    stop(sprintf("SCM_BUDGET_INFEASIBLE: %s needs %.0fs; fresh window %.0fs; no fit started. Preserve caches; unchanged resubmission cannot help.",what,required,window),call.=FALSE)
  # A fit admitted with no slack is killed by the stage cap and its whole window is lost, so an
  # estimate that cannot finish must defer instead of starting (the earlier 780s timeout).
  margin <- PMX_ADMIT_MARGIN_S(window)
  if(required+margin>left)
    defer_work(sprintf("%s needs %.0fs (+%.0fs safety margin); %.0fs remain",what,required,margin,left))
  invisible(TRUE)
}
# Workers produce private, source-keyed receipts. Only the parent commits study state.
pmx_scm_save_state <- function(value,path) {
  temporary <- paste0(path,".",Sys.getpid(),".tmp")
  on.exit(if(file.exists(temporary)) unlink(temporary),add=TRUE)
  saveRDS(value,temporary)
  if(!file.rename(temporary,path)) stop("SCM_CHECKPOINT_WRITE_FAILED: completed fit caches preserved")
  invisible(NULL)
}
pmx_scm_failure_cached <- function(path) {
  if(!file.exists(path)) return(FALSE)
  previous <- readRDS(path)
  message <- paste(previous$reason,previous$diagnostic$message,collapse=" ")
  if(grepl("could not find function|SCM_PARALLEL_DEPENDENCY_MISSING",message))
    stop("SCM_TOOLCHAIN_FAILURE_CACHED: ",path,
         "; preserved toolchain failure is not evidence of a nonsignificant covariate; review before resuming",call.=FALSE)
  TRUE
}
# Reclassify only the exact historical warning-only rejection. Keep its failure
# record and reuse its native estimates; other failed fits are never reopened.
pmx_scm_recover_fit <- function(path,key) {
  if(!file.exists(path)) return(NULL)
  previous <- readRDS(path)
  if(!identical(previous$key,key) || !identical(previous$reason,"Optimizer minimum not demonstrated") || is.null(previous$estimate)) return(NULL)
  fit <- previous$estimate;quality <- pmx_fit_quality(fit)
  if(!quality$ok || !isTRUE(quality$history_warning) || !identical(quality$state,"warning")) return(NULL)
  pmx_screen_bic(fit) # Require this runtime's native FOCEI likelihood, not a reconstructed BIC.
  attr(fit,"pmx_quality_reclassified") <- list(reason=previous$reason,record=basename(path),refit=FALSE)
  fit
}
pmx_scm_pending <- function(key) file.path("_scm_sel_cache",paste0(key,".parallel_pending.rds"))
pmx_scm_isolated_build <- function(builder,ctl,effects) {
  ctl <- normalizePath(ctl,mustWork=TRUE)
  previous <- getwd(); private <- tempfile("pmx_scm_build_")
  if(!dir.create(private)) stop("SCM_PARALLEL_BUILD_DIRECTORY_FAILED")
  on.exit({setwd(previous);unlink(private,recursive=TRUE)},add=TRUE)
  setwd(private)
  builder(ctl,effects)
}
pmx_scm_worker <- function(task) {
  context <- get(".pmx_scm_context",envir=.GlobalEnv)
  started <- Sys.time(); diagnostic <- NULL; warnings <- character()
  fit <- tryCatch(withCallingHandlers(
    {
      ui <- context$model$build(task$effects, context$start_ctl)
      context$model$fit(ui,pmx_endpoint_data(ui,context$data),cov=FALSE)
    },
    warning=function(w) {warnings <<- c(warnings,conditionMessage(w));invokeRestart("muffleWarning")},
    error=function(e) diagnostic <<- list(message=conditionMessage(e),
      call=paste(deparse(conditionCall(e)),collapse=" "),
      stack=vapply(tail(sys.calls(),12L),function(x)paste(deparse(x),collapse=" "),""))),
    error=function(e)e)
  if (inherits(fit,"error") && grepl("could not find function",conditionMessage(fit),fixed=TRUE))
    stop("SCM_PARALLEL_DEPENDENCY_MISSING: ",conditionMessage(fit),
         "; toolchain error, not a failed statistical model",call.=FALSE)
  result <- list(schema=1L,key=task$key,tag=task$tag,fit=fit,diagnostic=diagnostic,warnings=warnings,
                 elapsed=as.numeric(difftime(Sys.time(),started,units="secs")),threads=context$threads)
  temporary <- paste0(task$pending,".",Sys.getpid(),".tmp")
  saveRDS(result,temporary)
  if (!file.rename(temporary,task$pending)) stop("SCM_PARALLEL_RECEIPT_WRITE_FAILED")
  list(key=task$key,tag=task$tag)
}
pmx_scm_prefetch <- function(tasks, context, fit_commit, cached, need, left, defer_work,
                             scaled_need=function(threads)need(),window=left()) {
  if (!length(tasks)) return(invisible(NULL))
  # Consume durable receipts before making another resource/budget decision.
  for (task in tasks) if (file.exists(task$pending)) fit_commit(task$effects,task$tag)
  tasks <- Filter(function(task)!cached(task),tasks)
  if (!length(tasks)) return(invisible(NULL))
  plan <- pmx_cpu_plan(length(tasks),data_bytes=as.numeric(object.size(context$data)))
  while(plan$workers>1L && scaled_need(plan$threads)+20>left())
    plan <- pmx_cpu_plan(length(tasks),worker_cap=plan$workers-1L,
                         data_bytes=as.numeric(object.size(context$data)))
  pmx_cpu_log("SCM",plan)
  if (plan$workers==1L) {
    pmx_scm_admit(scaled_need(plan$threads)+10,left(),window,defer_work,"SCM serial fit")
    pmx_cpu_setup(rx=TRUE)
    return(invisible(NULL)) # Existing serial path respects the single-fit thread cap.
  }
  pmx_scm_admit(scaled_need(plan$threads)+20,left(),window,defer_work,"SCM parallel setup/fit")
  cl <- NULL; pids <- integer(); active <- rep(NA_integer_,plan$workers)
  cursor <- 1L; collected <- rep(FALSE,length(tasks)); window_expired <- FALSE
  cleanup <- function() {
    # Only PIDs returned by this cluster are owned here. Never kill unrelated R jobs.
    for (pid in pids) try(tools::pskill(pid,signal=9L),silent=TRUE)
    if (!is.null(cl)) for (node in cl) try(close(node$con),silent=TRUE)
    pids <<- integer(); cl <<- NULL
  }
  on.exit(cleanup(),add=TRUE)
  tryCatch({
    cl <- parallel::makePSOCKcluster(plan$workers,outfile="",rscript_args="--vanilla",
           setup_timeout=min(40,max(1,left()-10)),timeout=max(1,left()))
    pids <- unlist(parallel::clusterCall(cl,Sys.getpid))
    # Model construction uses the same parent helpers; do not source the executable driver.
    helpers <- c("%||%","theta_block","theta_count","theta_append","cov_start","nonmem_add_cov","pmx_scm_isolated_build")
    missing <- helpers[!vapply(helpers,exists,TRUE,envir=.GlobalEnv,mode="function",inherits=FALSE)]
    if(length(missing)) stop("SCM_PARALLEL_DEPENDENCY_MISSING: ",paste(missing,collapse=", "))
    parallel::clusterExport(cl,helpers,envir=.GlobalEnv)
    parallel::clusterCall(cl,function(context,threads) {
      Sys.setenv(OMP_NUM_THREADS=as.character(threads),OMP_THREAD_LIMIT=as.character(threads),
                 OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1",BLIS_NUM_THREADS="1")
      suppressPackageStartupMessages({library(nlmixr2);library(rxode2);library(dplyr);library(lotri)})
      source(context$contract,local=.GlobalEnv)
      builder <- pmx_build_ui
      assign("pmx_build_ui",function(ctl,effects) pmx_scm_isolated_build(builder,ctl,effects),envir=.GlobalEnv)
      rxode2::setRxThreads(threads)
      setwd(context$dir)
      context$threads <- threads
      assign("START_EFFECTS",context$start_effects %||% numeric(0),envir=.GlobalEnv)
      assign(".pmx_scm_context",context,envir=.GlobalEnv)
      invisible(NULL)
    },context,plan$threads)
    dispatch <- function(worker) {
      if (cursor>length(tasks) || left()<scaled_need(plan$threads)+10) return(invisible(NULL))
      index <- cursor; cursor <<- cursor+1L; active[worker] <<- index
      parallel:::sendCall(cl[[worker]],pmx_scm_worker,list(tasks[[index]]),tag=index)
    }
    for (worker in seq_len(plan$workers)) dispatch(worker)
    while (any(!is.na(active))) {
      if (left()<=10) {window_expired <- TRUE; break}
      busy <- which(!is.na(active))
      ready <- socketSelect(lapply(cl[busy],function(node)node$con),timeout=min(1,max(0,left()-10)))
      for (worker in busy[ready]) {
        index <- active[worker]; task <- tasks[[index]]
        receipt <- parallel:::recvResult(cl[[worker]])
        if (inherits(receipt,"try-error")) stop(as.character(receipt),call.=FALSE)
        if (!is.list(receipt) || !identical(receipt$key,task$key) ||
            !identical(receipt$tag,task$tag) || !file.exists(task$pending))
          stop("SCM_PARALLEL_WORKER_LOST: missing/mismatched receipt for ",task$tag)
        fit_commit(task$effects,task$tag)
        collected[index] <- TRUE; active[worker] <- NA_integer_
      }
      for (worker in which(is.na(active))) dispatch(worker)
    }
    cleanup()
  },error=function(e) {
    cleanup()
    # Preserve a completed fit even if another worker failed before its notice was received.
    for (task in tasks) if (file.exists(task$pending)) fit_commit(task$effects,task$tag)
    stop("SCM_PARALLEL_BLOCKED: ",conditionMessage(e),
         "; completed caches preserved; no automatic serial fallback/refit",call.=FALSE)
  })
  for (index in seq_along(tasks)) if (!collected[index] && file.exists(tasks[[index]]$pending)) {
    fit_commit(tasks[[index]]$effects,tasks[[index]]$tag); collected[index] <- TRUE
  }
  if (window_expired || !all(collected))
    defer_work("SCM parallel window complete; resume unfinished candidates using committed caches")
  invisible(NULL)
}
