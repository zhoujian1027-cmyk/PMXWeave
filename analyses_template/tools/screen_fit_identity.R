# Shared screen -> SCM identity. No fitted values or runtime objects are hashed.
# Bump the recipe only for scientific changes to translation/data/endpoint fitting.
pmx_screen_recipe <- "focei-nonmem2rx-2"
pmx_focei_control <- function(cov_method="",tables=FALSE) nlmixr2est::foceiControl(
  print=0,covMethod=cov_method,calcTables=tables,
  rxControl=rxode2::rxControl(atol=1e-8,rtol=1e-6))
pmx_screen_controls <- function() {
  control <- pmx_focei_control()
  list(CTL=control,RX=control$rxControl)
}
pmx_screen_functions <- c("pmx_focei_control","ctl_body","ctl_sigma_sd","ctl_obs_cmt","ctl_eps","derive_endpoint",
  "ctl_endpoint_comment","set_resid_init","pmx_read_data","pmx_theta_names","pmx_eta_names",
  "pmx_endpoint","pmx_validate_ctl","pmx_fixed_parameters","pmx_filter_data")
pmx_screen_contract <- function(ctl=NULL) {
  x <- lapply(setNames(pmx_screen_functions,pmx_screen_functions),function(n)
    paste(deparse(get(n,mode="function")),collapse="\n"))
  policy <- if(is.null(ctl)) NULL else pmx_endpoint_policy(ctl)
  if(!is.null(policy)) x$endpoint_policy <- policy
  as.character(rlang::hash(x))
}
pmx_screen_settings <- function(ctl,rx) {
  out <- list()
  flatten <- function(x,p) {
    if(is.null(x)) {out[[p]] <<- "NULL";return(invisible(NULL))}
    if(is.function(x)) {
      env <- environment(x)
      if(!is.primitive(x) && !isNamespace(env) && !identical(env,baseenv()))
        stop("SCREEN_SETTINGS_UNSUPPORTED: ",p," has a custom closure; do not guess its identity")
      out[[p]] <<- paste(if(is.primitive(x)) "primitive" else environmentName(env),
        paste(deparse(x,width.cutoff=500L),collapse="\n"),sep="|")
      return(invisible(NULL))
    }
    if(is.list(x)) {
      if(!length(x)) {out[[p]] <<- "list()";return(invisible(NULL))}
      nm <- names(x)
      if(is.null(nm)) nm <- as.character(seq_along(x))
      if(anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) stop("SCREEN_SETTINGS_UNSUPPORTED: ambiguous names at ",p)
      for(i in order(nm)) flatten(x[[i]],paste(p,nm[i],sep="."))
      return(invisible(NULL))
    }
    if(!is.atomic(x) || is.object(x)) stop("SCREEN_SETTINGS_UNSUPPORTED: ",p," has type ",typeof(x))
    if(!is.null(dim(x))) out[[paste0(p,".dim")]] <<- paste(dim(x),collapse=",")
    if(!is.null(dimnames(x))) flatten(dimnames(x),paste0(p,".dimnames"))
    if(!is.null(names(x))) out[[paste0(p,".names")]] <<- paste(names(x),collapse="|")
    if(!length(x)) {out[[p]] <<- paste0(typeof(x),"(0)");return(invisible(NULL))}
    for(i in seq_along(x)) {
      v <- x[[i]]
      out[[paste0(p,"[",i,"]")]] <<- if(is.na(v)) "NA" else if(is.numeric(v))
        paste0("number:",sprintf("%.17g",v)) else paste0(typeof(v),":",as.character(v))
    }
  }
  # Core count controls resource use, not the estimation recipe. Keep all tolerances.
  rx <- as.list(rx);rx[intersect(names(rx),"cores")] <- NULL
  ctl <- as.list(ctl)
  if(is.list(ctl$rxControl)) ctl$rxControl[intersect(names(ctl$rxControl),"cores")] <- NULL
  flatten(ctl,"CTL");flatten(rx,"RX")
  for(p in c("nlmixr2","nlmixr2est","rxode2","nonmem2rx"))
    out[[paste0("package.",p)]] <- as.character(utils::packageVersion(p))
  out[order(names(out))]
}
pmx_screen_digest <- function(x) {
  tmp <- tempfile();on.exit(unlink(tmp))
  writeBin(charToRaw(enc2utf8(as.character(jsonlite::toJSON(x,auto_unbox=TRUE,null="null",digits=NA)))),tmp)
  unname(tools::md5sum(tmp))
}
pmx_screen_difference <- function(old,current) {
  nm <- sort(unique(c(names(old),names(current))))
  bad <- nm[!vapply(nm,function(n) identical(old[[n]],current[[n]]),TRUE)]
  if(!length(bad)) return("")
  n <- bad[1]
  value <- function(x) if(is.null(x)) "<missing>" else substr(as.character(x),1L,160L)
  paste0(n,": recorded=",value(old[[n]]),"; current=",value(current[[n]]),
    if(length(bad)>1L) paste0(" (+",length(bad)-1L," other fields)") else "")
}

# Estimator-specific three-state verdict. History-order and ETA-reset diagnostics
# do not override a normal optimizer exit; invalid estimates/status still fail.
pmx_fit_quality <- function(fit,warnings=character()) {
  if(is.null(fit)) return(list(ok=FALSE,state="failed",problems="Missing fitted object",warnings=character()))
  if(inherits(fit,"nlmixr2FitCore") && !requireNamespace("nlmixr2est",quietly=TRUE))
    stop("FIT_QUALITY_RUNTIME_REQUIRED: nlmixr2est is needed to read native fit fields; this is not model failure",call.=FALSE)
  notes <- unique(c(as.character(unlist(fit$runInfo)),as.character(attr(fit,"pmx_fit_warnings")),warnings))
  notes <- notes[!is.na(notes) & nzchar(notes)]
  termination <- c(notes,as.character(fit$message))
  problem <- termination[grepl("did not (?:reach.*minimum|converge)|false convergence|(?:iteration|evaluation) limit reached|abnormal termination",termination,ignore.case=TRUE,perl=TRUE)]
  code <- fit$convergence
  normal <- is.numeric(code) && length(code)>0L && all(is.finite(code) & code==0)
  if(is.numeric(code) && any(!is.finite(code) | code!=0)) problem <- c(problem,paste("Optimizer convergence code:",paste(code,collapse=",")))
  history_warning <- any(grepl("(?:last|final) objective function (?:was|is) not at (?:a )?minimum",notes,ignore.case=TRUE,perl=TRUE))
  if(history_warning && !normal) problem <- c(problem,"Objective-history warning without a verified normal optimizer exit")
  fe <- tryCatch(nlme::fixef(fit),error=function(e) NULL)
  ofv <- tryCatch(fit$objf,error=function(e) NULL)
  if(is.null(fe) || any(!is.finite(fe)) || !is.numeric(ofv) || length(ofv)!=1L || !is.finite(ofv))
    problem <- c(problem,"Missing/non-finite fitted coefficients or objective")
  method <- tolower(as.character(unlist(fit$est)))
  bic <- tryCatch(as.numeric(stats::BIC(fit)),error=function(e) NA_real_)
  if(length(method)!=1L || method!="focei") problem <- c(problem,"Expected native FOCEI fit")
  if(length(bic)!=1L || !is.finite(bic)) problem <- c(problem,"Native likelihood BIC unavailable")
  omega <- fit$omega
  if(!is.null(omega) && (any(!is.finite(omega)) || any(diag(as.matrix(omega))<0))) problem <- c(problem,"Invalid fitted random-effect covariance")
  state <- if(length(problem)) "failed" else if(length(notes)) "warning" else "passed"
  list(ok=state!="failed",state=state,problems=unique(problem),warnings=notes,
       convergence=code,message=as.character(fit$message),history_warning=history_warning)
}
pmx_require_fit_quality <- function(fit,context="fit") {
  quality <- pmx_fit_quality(fit)
  if(!quality$ok) stop("FIT_QUALITY_REVIEW_REQUIRED: ",context,": ",paste(quality$problems,collapse=" | "),
    "; preserve fitted estimates/checkpoints; no automatic retry or model change",call.=FALSE)
  invisible(quality)
}

pmx_screen_bic <- function(fit) {
  pmx_require_fit_quality(fit,"native BIC comparison")
  method <- tolower(as.character(unlist(fit$est)))
  if(length(method)!=1L || method!="focei") stop("FIT_ESTIMATION_METHOD_MISMATCH: expected FOCEI, got ",paste(method,collapse=","))
  value <- as.numeric(stats::BIC(fit))
  if(length(value)!=1L || !is.finite(value)) stop("FIT_BIC_UNAVAILABLE: native likelihood BIC required; no manual OFV substitution")
  value
}
