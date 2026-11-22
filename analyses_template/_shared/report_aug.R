require_vpc_contract <- function(path,outputs) {
  txt <- paste(readLines(path,warn=FALSE),collapse="\n")
  if(!grepl("(?m)^\\$SIGMA",txt,perl=TRUE) || !grepl("EPS\\s*\\(",txt))
    stop("VPC requires the study residual model in the simulator ($SIGMA and EPS); structural-only examples are insufficient")
  if(any(!vapply(outputs,function(nm) grepl(paste0("\\b",nm,"\\b"),txt),TRUE)))
    stop("VPC simulator lacks its required residual observation outputs: ",paste(outputs,collapse=", "))
}
update_cpp_covariates <- function(path, fit, map) {
  cd <- tryCatch(as.data.frame(fit$muRefCovariateDataFrame),error=function(e) NULL)
  if(is.null(cd) || !nrow(cd)) return(invisible(path))
  txt <- readLines(path,warn=FALSE)
  code <- sub("//.*$","",txt)
  start <- grep("^\\$MAIN|^\\$ODE",code)
  if(!length(start)) stop("Simulator has no structural code")
  code <- paste(code[min(start):length(code)],collapse="\n")
  needed <- unique(c(as.character(cd$covariateParameter),as.character(cd$covariate)))
  missing <- needed[!vapply(needed,function(nm) grepl(paste0("\\b",nm,"\\b"),code,ignore.case=TRUE),TRUE)]
  if(length(missing)) stop("Simulator must include the frozen SCM formulas (no generic exponential substitution): ",paste(missing,collapse=", "))
  invisible(path)
}
# Shared report preparation from frozen quantities; no estimation or covariance work.
pmx_report_update_model <- function(mod, est, sigma_map=NULL, residual=TRUE) {
  parameters <- names(mrgsolve::param(mod)); fe <- est$fixef; ini <- est$iniDf
  if(is.null(sigma_map)) sigma_map <- names(fe)[grepl("^(sd|sig|eps)|resid|prop|add",names(fe),ignore.case=TRUE)]
  target <- match(tolower(sub("^t[.]","",names(fe))),tolower(parameters))
  missing <- names(fe)[is.na(target) & !tolower(names(fe)) %in% tolower(sigma_map)]
  if(length(missing)) stop("REPORT_SIMULATOR_PARAMETER_MISMATCH: unmapped fitted parameters: ",paste(missing,collapse=", "))
  use <- which(!is.na(target))
  if(any(!is.finite(fe[use]))) stop("REPORT_SIMULATOR_PARAMETER_MISMATCH: non-finite fitted parameter")
  if(length(use)) mod <- mrgsolve::param(mod,as.list(setNames(as.numeric(fe[use]),parameters[target[use]])))
  idx <- which(is.finite(ini$neta1) & is.finite(ini$neta2) & ini$neta1>0 & ini$neta2>0)
  n <- if(length(idx)) max(ini$neta1[idx],ini$neta2[idx]) else 0L
  omega <- matrix(0,n,n)
  for(i in idx) {omega[ini$neta1[i],ini$neta2[i]] <- ini$est[i];omega[ini$neta2[i],ini$neta1[i]] <- ini$est[i]}
  if(!identical(dim(as.matrix(mrgsolve::omat(mod))),dim(omega)) || any(!is.finite(omega)))
    stop("REPORT_SIMULATOR_OMEGA_MISMATCH: frozen ETA dimensions/order differ")
  if(n) mod <- mrgsolve::omat(mrgsolve::collapse_omega(mod),list(omega))
  if(residual) {
    if(!length(sigma_map) || anyDuplicated(sigma_map)) stop("REPORT_SIGMA_MAP_REQUIRED: name fitted SDs in EPS order")
    sd <- ini$est[match(tolower(sigma_map),tolower(ini$name))]
    if(any(!is.finite(sd) | sd<0)) stop("REPORT_SIGMA_MAP_REQUIRED: fitted residual SD unavailable")
    sigma <- diag(sd^2,nrow=length(sd))
    if(!identical(dim(as.matrix(mrgsolve::smat(mod))),dim(sigma))) stop("REPORT_SIMULATOR_SIGMA_MISMATCH: EPS dimensions differ")
    mod <- mrgsolve::smat(mrgsolve::collapse_sigma(mod),list(sigma))
  }
  mrgsolve::update(mod,atol=min(mod@atol,1e-10),rtol=min(mod@rtol,1e-8))
}

pmx_report_native_rows <- function(fit) {
  original <- as.data.frame(fit$origData)
  table <- as.data.frame(fit)
  fail <- function(reason) stop("REPORT_FIT_ROWS_AMBIGUOUS: ",reason,call.=FALSE)
  rows <- get0(".rownum",envir=fit$env,inherits=FALSE)
  if(is.null(rows)) rows <- table$nlmixrRowNums
  if(!is.numeric(rows) || length(rows)!=nrow(table) || any(!is.finite(rows)) ||
     any(rows!=floor(rows) | rows<0 | rows>nrow(original)))
    fail("native source-row map is missing or invalid; preserve the model and fitted results")
  if(!is.null(table$nlmixrRowNums) && !identical(as.numeric(rows),as.numeric(table$nlmixrRowNums)))
    fail("native source-row maps disagree")
  use <- rows>0L # Zero identifies backend-generated rows, not original observations.
  index <- as.integer(rows[use])
  if(anyDuplicated(index)) fail("native source-row map has duplicate original records")
  for(key in c("ID","TIME")) {
    left <- which(toupper(names(original))==key);right <- which(toupper(names(table))==key)
    if(length(left)!=1L || length(right)!=1L) fail(paste("native row identity lacks unique",key))
    a <- as.character(original[[left]][index]);b <- as.character(table[[right]][use])
    equal <- if(key=="TIME") {
      a <- suppressWarnings(as.numeric(a));b <- suppressWarnings(as.numeric(b))
      all(is.finite(a)) && all(is.finite(b)) && isTRUE(all.equal(a,b,tolerance=1e-10,check.attributes=FALSE))
    } else identical(a,b)
    if(!equal || anyNA(a) || anyNA(b)) fail(paste("native source-row map conflicts with",key))
  }
  for(key in intersect(c("PRED","IPRED","CWRES","IWRES","RES","IRES"),names(table))) {
    if(!is.numeric(table[[key]])) fail(paste("non-numeric native diagnostic",key))
    value <- rep(NA_real_,nrow(original));value[index] <- table[[key]][use]
    original[[key]] <- value
  }
  original
}

# Native post-fit diagnostics use a private clone; no optimization/covariance call.
pmx_report_native_table <- function(fit) {
  if(!inherits(fit,"nlmixr2FitCore")) return(NULL)
  snapshot <- function(x) list(theta=nlmixr2est::fixef(x),omega=x$omega,eta=x$etaMat,objf=x$objf)
  before <- snapshot(fit)
  native <- tryCatch({
    work <- nlmixr2est::nlmixrClone(fit)
    options <- work$table
    if(is.null(options)) options <- list()
    options <- unclass(options)
    options$cwres <- TRUE;options$npde <- FALSE
    options$addDosing <- TRUE;options$subsetNonmem <- FALSE;options$cores <- 1L
    if(any(options$censMethod %in% c(2L,6L))) stop("stored censoring method requires NPDE; report-only CWRES cannot change that method")
    nlmixr2est::addTable(work,updateObject=FALSE,table=do.call(nlmixr2est::tableControl,options))
  },error=function(e) {
    message("REPORT_NATIVE_TABLE_UNAVAILABLE: ",conditionMessage(e));NULL
  })
  if(!identical(before,snapshot(fit))) stop("REPORT_FROZEN_FIT_CHANGED: native diagnostic evaluation altered the source fit")
  if(is.null(native)) return(NULL)
  if(!isTRUE(all.equal(before,snapshot(native),tolerance=1e-10)))
    stop("REPORT_FROZEN_FIT_CHANGED: diagnostic table estimates differ from the frozen fit")
  merged <- pmx_report_native_rows(native)
  if(!is.data.frame(merged) || !all(c("PRED","IPRED","CWRES") %in% names(merged)))
    stop("REPORT_NATIVE_TABLE_INVALID: native predictions/CWRES are missing")
  merged
}

pmx_est_aug <- function(fit, cpp_sim=NULL, endpoints=NULL, fixed=NULL, sigma_map=NULL, prediction_transform=NULL) {
  frame <- function(x) tryCatch(as.data.frame(x),error=function(e) NULL)
  canonical <- function(d) {
    if(is.null(d)) return(NULL)
    nm <- names(d); upper <- toupper(nm); keep <- rep(TRUE,length(nm))
    for(k in unique(upper[duplicated(upper)])) {
      ix <- which(upper==k); exact <- ix[nm[ix]==k]
      if(length(exact)!=1L) stop("REPORT_FIT_COLUMNS_AMBIGUOUS: ",k)
      keep[setdiff(ix,exact)] <- FALSE
    }
    d <- d[,keep,drop=FALSE];names(d) <- upper[keep];d
  }
  if(is.data.frame(fit) && !inherits(fit,"nlmixr2FitCore")) return(canonical(frame(fit)))
  d <- canonical(frame(fit$origData))
  if(is.null(d) || !nrow(d)) stop("REPORT_FIT_DATA_REQUIRED: frozen fit has no original records")
  if(!"DV" %in% names(d) && "Y" %in% names(d)) d$DV <- d$Y
  if(!"MDV" %in% names(d) && "EVID" %in% names(d)) d$MDV <- as.integer(d$EVID!=0)
  a <- if(is.data.frame(fit)) canonical(pmx_report_native_rows(fit)) else canonical(frame(fit$aug))
  has_native <- !is.null(a) && nrow(a)==nrow(d) && all(c("PRED","IPRED","CWRES") %in% names(a)) && any(is.finite(a$CWRES))
  if(!has_native && !(all(c("PRED","IPRED","CWRES") %in% names(d)) && any(is.finite(d$CWRES)))) {
    native <- pmx_report_native_table(fit)
    if(!is.null(native)) a <- canonical(frame(native))
  }
  if(!is.null(a) && nrow(a) && all(c("PRED","IPRED") %in% names(a))) {
    key <- intersect(c("ID","TIME","EVID","CMT","DVID"),names(a))
    if(nrow(a)!=nrow(d) || !all(c("ID","TIME") %in% key) || !all(key %in% names(d)))
      stop("REPORT_FIT_ROWS_AMBIGUOUS: native predictions lack matching source record keys")
    if(any(!vapply(key,function(k) identical(as.character(a[[k]]),as.character(d[[k]])),TRUE))) {
      rowkey <- function(x) do.call(paste,c(lapply(x[key],as.character),sep="\r"))
      ak <- rowkey(a);dk <- rowkey(d);order <- match(dk,ak)
      if(anyDuplicated(ak) || anyDuplicated(dk) || anyNA(order))
        stop("REPORT_FIT_ROWS_AMBIGUOUS: native predictions cannot be aligned uniquely")
      a <- a[order,,drop=FALSE]
    }
    for(k in intersect(c("PRED","IPRED","CWRES","IWRES","RES","IRES"),names(a))) d[[k]] <- a[[k]]
    return(d)
  }
  if(all(c("PRED","IPRED") %in% names(d))) return(d)
  if(is.null(cpp_sim) || !file.exists(cpp_sim)) stop("REPORT_PREDICTIONS_REQUIRED: native table or paired simulator required")
  if(!all(c("ID","TIME","DV","EVID","CMT") %in% names(d))) stop("REPORT_FIT_DATA_REQUIRED: ID/TIME/DV/EVID/CMT are required")
  if(is.null(fixed)) fixed <- nlmixr2est::fixef(fit)
  est <- list(fixef=fixed,iniDf=as.data.frame(fit$iniDf))
  mod <- pmx_report_update_model(mrgsolve::mread(cpp_sim,quiet=TRUE),est,sigma_map,residual=FALSE)
  mod <- mrgsolve::zero_re(mod) # Both paths are deterministic; individual ETAs are supplied explicitly.
  obs <- !is.na(d$EVID) & d$EVID==0 & !is.na(d$MDV) & d$MDV==0
  ev <- d[,intersect(c("ID","TIME","EVID","AMT","CMT","MDV","ADDL","II","RATE","SS"),names(d)),drop=FALSE]
  names(ev) <- tolower(names(ev));names(ev)[names(ev)=="id"] <- "ID"
  ev$ID <- suppressWarnings(as.numeric(as.character(ev$ID)))
  if(any(!is.finite(ev$ID))) stop("REPORT_SIMULATOR_ID_REQUIRED: numeric subject IDs are required")
  if("NMCMT" %in% names(d)) ev$cmt <- suppressWarnings(as.numeric(as.character(d$NMCMT)))
  ev$cmt <- suppressWarnings(as.numeric(as.character(ev$cmt)))
  ncomp <- length(mrgsolve::init(mod))
  bad <- !is.finite(ev$cmt) | abs(ev$cmt)>ncomp | ev$cmt==0
  if(any(bad & !obs)) stop("REPORT_SIMULATOR_CMT_MISMATCH: invalid dose/event compartment")
  ev$cmt[bad & obs] <- 1L # Explicit endpoint captures select observations, not dose compartments.
  for(nm in names(mrgsolve::param(mod))) {
    source <- match(toupper(nm),names(d))
    if(!is.na(source)) ev[[nm]] <- d[[source]]
  }
  if("DVID" %in% names(d)) {
    target <- names(mrgsolve::param(mod))[tolower(names(mrgsolve::param(mod)))=="dvid"]
    if(!length(target)) target <- "dvid"
    ev[[target]] <- if("NMDVID" %in% names(d)) d$NMDVID else d$DVID
  }
  ev$PMXROW <- seq_len(nrow(d));ev <- ev[order(ev$ID,ev$time,ev$PMXROW),,drop=FALSE]
  captures <- if(length(endpoints)) as.character(endpoints) else "IPRED"
  getpred <- function(idat=NULL) {
    m <- mod
    if(!is.null(idat)) m <- mrgsolve::idata_set(m,idat)
    x <- as.data.frame(mrgsolve::mrgsim(m,data=ev,end=-1,outvars=unique(captures),
      carry_out="PMXROW",etasrc=if(is.null(idat)) "omega" else "idata.all"))
    if(!"PMXROW" %in% names(x) || anyDuplicated(x$PMXROW)) stop("REPORT_PREDICTION_ROWS_AMBIGUOUS: record ids missing/duplicated")
    x <- x[match(seq_len(nrow(d)),x$PMXROW),,drop=FALSE]
    value <- if(!length(endpoints)) x$IPRED else rep(NA_real_,nrow(d))
    if(length(endpoints)) {
      if(!"DVID" %in% names(d)) stop("REPORT_ENDPOINT_REQUIRED: mapped DVID missing")
      for(k in names(endpoints)) {
        hit <- !is.na(d$DVID) & as.character(d$DVID)==k
        if(!endpoints[[k]] %in% names(x)) stop("REPORT_CAPTURE_REQUIRED: ",endpoints[[k]])
        value[hit] <- x[[endpoints[[k]]]][hit]
      }
    }
    if(!is.null(prediction_transform)) value <- prediction_transform(value,d$DVID)
    if(length(value)!=nrow(d) || any(!is.finite(value[obs]))) stop("REPORT_PREDICTIONS_REQUIRED: non-finite observation predictions")
    value
  }
  d$PRED <- getpred()
  et <- frame(fit$ranef);if(is.null(et) || !nrow(et)) et <- frame(fit$eta)
  neta <- nrow(as.matrix(mrgsolve::omat(mod)))
  if(!neta) d$IPRED <- d$PRED else {
    if(is.null(et) || !nrow(et)) stop("REPORT_EBE_REQUIRED: frozen individual ETAs unavailable")
    id <- which(toupper(names(et))=="ID")
    if(length(id)!=1L) stop("REPORT_EBE_REQUIRED: unambiguous EBE subject ID required")
    names(et)[id] <- "ID";et$ID <- suppressWarnings(as.numeric(as.character(et$ID)))
    if(anyNA(et$ID) || anyDuplicated(et$ID) || !all(unique(ev$ID) %in% et$ID)) stop("REPORT_EBE_REQUIRED: missing/duplicate EBE subject ids")
    diagonal <- which(is.finite(est$iniDf$neta1) & est$iniDf$neta1>0 & est$iniDf$neta1==est$iniDf$neta2)
    diagonal <- diagonal[order(est$iniDf$neta1[diagonal])]
    labels <- est$iniDf$name[diagonal]
    ix <- match(tolower(labels),tolower(names(et)))
    if(length(ix)!=neta || anyNA(ix)) {
      ix <- match(paste0("ETA",seq_len(neta)),toupper(names(et)))
      if(anyNA(ix)) stop("REPORT_EBE_MAPPING_REQUIRED: match fitted ETA names/order explicitly")
    }
    idat <- data.frame(ID=et$ID)
    for(i in seq_len(neta)) idat[[paste0("ETA",i)]] <- as.numeric(et[[ix[i]]])
    if(any(!is.finite(as.matrix(idat)))) stop("REPORT_EBE_REQUIRED: non-finite individual ETAs")
    d$IPRED <- getpred(idat)
  }
  d$RES <- d$DV-d$PRED;d$IRES <- d$DV-d$IPRED
  # Weighted residuals require the actual backend calculation, not an invented generic SD.
  if(!"CWRES" %in% names(d)) d$CWRES <- NA_real_
  if(!"IWRES" %in% names(d)) d$IWRES <- NA_real_
  cat("REPORT_PREDICTIONS source=paired_simulator PRED=eta_zero IPRED=frozen_eta weighted_residuals=native_only\n")
  d
}

# Observation scale
pmx_ctl_lines <- function(ctl) {
  ctl <- as.character(ctl)
  if (length(ctl) == 1L && !grepl("[\n$]", ctl) && file.exists(ctl)) return(readLines(ctl, warn = FALSE))
  ctl
}

# One named block of a NONMEM control stream (e.g. "ERROR"), without the following block.
pmx_ctl_block <- function(ctl, name) {
  lines <- pmx_ctl_lines(ctl)
  start <- grep(paste0("^\\s*\\$", name, "\\b"), lines, ignore.case = TRUE, perl = TRUE)
  if (!length(start)) return("")
  start <- start[1]
  stop <- grep("^\\s*\\$[A-Za-z]", lines, perl = TRUE)
  stop <- stop[stop > start]
  end <- if (length(stop)) stop[1] - 1L else length(lines)
  paste(sub(";.*$","",lines[start:end]), collapse = "\n")
}

# Which column the fit reads as DV. "DV" means the dataset's own DV column.
pmx_dv_alias <- function(ctl) {
  input <- pmx_ctl_block(ctl, "INPUT")
  hits <- regmatches(input, gregexpr("\\bDV\\s*=\\s*([A-Za-z][A-Za-z0-9_]*)", input, ignore.case = TRUE, perl = TRUE))[[1]]
  alias <- toupper(sub("^.*=\\s*", "", hits))
  alias <- alias[!alias %in% c("DROP", "NULL", "")]
  if (length(alias)) alias[1] else "DV"
}

# Follow the Y assignment, including intermediate predictions, rather than any unrelated LOG().
pmx_dv_is_log <- function(ctl) {
  alias <- pmx_dv_alias(ctl)
  if(alias %in% c("LNDV","LOGDV","LN_DV","LOG_DV","LOG")) return(TRUE)
  lines <- strsplit(pmx_ctl_block(ctl,"ERROR"),"\n")[[1]]
  assignments <- regmatches(lines,regexec("^\\s*([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*(.+)$",lines,perl=TRUE))
  assignments <- Filter(function(x)length(x)==3L,assignments)
  rhs <- split(vapply(assignments,`[`,"",3L),toupper(vapply(assignments,`[`,"",2L)))
  log_value <- function(x,seen=character()) {
    if(grepl("\\b(?:LOG|DLOG)\\s*\\(",x,ignore.case=TRUE,perl=TRUE)) return(TRUE)
    variables <- unique(toupper(unlist(regmatches(x,gregexpr("[A-Za-z][A-Za-z0-9_]*",x)))))
    any(vapply(setdiff(intersect(variables,names(rhs)),c(seen,"Y")),function(v)
      any(vapply(rhs[[v]],log_value,TRUE,seen=c(seen,v))),TRUE))
  }
  scale <- vapply(rhs$Y,log_value,TRUE)
  if(length(unique(scale))>1L) stop("REPORT_DV_SCALE_REQUIRED: mixed endpoint scales require an explicit per-endpoint contract")
  length(scale)>0L && all(scale)
}
pmx_dv_needs_natural <- function(ctl) pmx_dv_is_log(ctl)

pmx_natural <- function(x, ctl) {
  if (pmx_dv_needs_natural(ctl)) exp(x) else x
}

pmx_observed_dv <- function(d, ctl, convert=NULL) {
  alias <- pmx_dv_alias(ctl)
  raw <- names(d)[toupper(names(d))=="DV"]
  use_raw <- length(raw)>0L && alias!="DV"
  hit <- if(use_raw) raw else names(d)[toupper(names(d))==alias]
  if(!length(hit)) stop("REPORT_DV_MISSING: no selected response column ",alias)
  cat("REPORT_OBSERVED_DV source=",if(use_raw) "retained_natural" else "model_response", " name=",hit[1],"\n",sep="")
  value <- d[[hit[1]]]
  if(use_raw) value else if(is.null(convert)) pmx_natural(value,ctl) else convert(value)
}

# Natural-scale predictions
pmx_fit_natural <- function(aug, ctl) {
  if (!is.data.frame(aug) || !nrow(aug)) return(aug)
  cat("REPORT_DV_SCALE alias=", pmx_dv_alias(ctl), " model=", if (pmx_dv_is_log(ctl)) "log" else "raw",
      " convert=", pmx_dv_needs_natural(ctl), "\n", sep = "")
  if (!pmx_dv_needs_natural(ctl)) return(aug)
  for (nm in intersect(c("DV", "PRED", "IPRED"), names(aug))) aug[[nm]] <- exp(aug[[nm]])
  aug
}

# Positive axis limits
pmx_log_limits <- function(values, fallback = c(0.01, 1)) {
  v <- suppressWarnings(as.numeric(values))
  v <- v[is.finite(v) & v > 0]
  if (!length(v)) return(fallback)
  lim <- range(v)
  if (lim[1] == lim[2]) lim <- lim * c(0.9, 1.1)
  lim
}

# Re-evaluate only deterministic predictions; never optimize or update uncertainty.
pmx_native_population <- function(fit,convert=function(value,endpoint) value) {
  work <- nlmixr2est::nlmixrClone(fit)
  before <- list(theta=nlmixr2est::fixef(fit),omega=fit$omega,eta=fit$etaMat,objf=fit$objf)
  d <- as.data.frame(work$origData)
  if("PMX_REPORT_ROW" %in% names(d)) stop("PMX_NATIVE_REFERENCE_INVALID: reserved row marker already exists")
  d$PMX_REPORT_ROW <- seq_len(nrow(d))
  pars <- work$theta
  for(matrix in list(work$omega,work$simulationSigma)) {
    if(!is.null(matrix) && nrow(matrix)>0L) {
      if(is.null(rownames(matrix))) stop("PMX_NATIVE_REFERENCE_INVALID: random-effect names unavailable")
      pars[rownames(matrix)] <- 0
    }
  }
  x <- as.data.frame(rxode2::rxSolve(work$simulationModel,params=pars,events=d,
    atol=1e-12,rtol=1e-10,cores=1L,addDosing=TRUE,subsetNonmem=FALSE,keep="PMX_REPORT_ROW"))
  key <- function(z,name) {
    at <- which(toupper(names(z))==name)
    if(length(at)!=1L) stop("PMX_NATIVE_REFERENCE_INVALID: missing/ambiguous ",name)
    z[[at]]
  }
  rows <- x$PMX_REPORT_ROW
  if(!is.numeric(rows) || anyNA(rows) || any(rows!=floor(rows) | rows<0 | rows>nrow(d)))
    stop("PMX_NATIVE_REFERENCE_INVALID: source-row map unavailable")
  use <- rows>0L
  if(anyDuplicated(rows[use])) stop("PMX_NATIVE_REFERENCE_INVALID: duplicate source records")
  obs <- key(d,"EVID")==0 & key(d,"MDV")==0
  take <- match(which(obs),rows)
  if(anyNA(take) || !"ipredSim" %in% names(x)) stop("PMX_NATIVE_REFERENCE_INVALID: observation coverage/prediction missing")
  if(!identical(as.character(key(x,"ID")[take]),as.character(key(d,"ID")[obs])) ||
     !isTRUE(all.equal(key(x,"TIME")[take],key(d,"TIME")[obs],check.attributes=FALSE,tolerance=1e-10)))
    stop("PMX_NATIVE_REFERENCE_INVALID: source-row identities disagree")
  endpoint <- if(any(toupper(names(d))=="DVID")) key(d,"DVID")[obs] else rep(1L,sum(obs))
  out <- data.frame(ID=as.character(key(d,"ID")[obs]),time=key(d,"TIME")[obs],dvid=endpoint,
    PRED=convert(x$ipredSim[take],endpoint))
  after <- list(theta=nlmixr2est::fixef(fit),omega=fit$omega,eta=fit$etaMat,objf=fit$objf)
  if(!identical(before,after)) stop("REPORT_FROZEN_FIT_CHANGED: deterministic reference altered fitted quantities")
  attr(out,"solver") <- list(atol=1e-12,rtol=1e-10,frozen=work$rxControlWithVar[c("atol","rtol")])
  out
}

pmx_sim_prediction_check <- function(native,population,keys=c("ID","time"),tag="VPC",
    rtol=NULL,atol=NULL,reference=NULL,diagnostics=NULL) {
  setting <- function(value,name,default) {
    if(is.null(value)) value <- suppressWarnings(as.numeric(Sys.getenv(name,as.character(default))))
    if(length(value)!=1L || !is.finite(value) || value<0) stop("PMX_SIM_CHECK_SETTING_INVALID: ",name)
    value
  }
  rtol <- setting(rtol,"PMX_SIM_CHECK_RTOL",1e-3);atol <- setting(atol,"PMX_SIM_CHECK_ATOL",1e-8)
  if(rtol==0 && atol==0) stop("PMX_SIM_CHECK_SETTING_INVALID: at least one tolerance must be positive")
  reason <- Sys.getenv("PMX_SIM_CHECK_REASON","")
  if((rtol>1e-3 || atol>1e-8) && (!nzchar(trimws(reason)) || Sys.getenv("PMX_SIM_CHECK_APPROVED","")!="true"))
    stop("PMX_SIM_CHECK_APPROVAL_REQUIRED: do not loosen tolerances automatically; a human-approved reason is required")
  record_failure <- function(reason) {
    if(!is.null(diagnostics)) {
      dir.create(dirname(diagnostics),recursive=TRUE,showWarnings=FALSE)
      jsonlite::write_json(list(schema=1L,tag=tag,state="record_mismatch",reason=reason,rtol=rtol,atol=atol),
        diagnostics,auto_unbox=TRUE,pretty=TRUE)
    }
    stop("PMX_SIMULATOR_RECORD_MISMATCH: ",tag,": ",reason,
      if(is.null(diagnostics)) "" else paste0(" diagnostics=",diagnostics),call.=FALSE)
  }
  prepare <- function(d,value) {
    if(!nrow(d) || !all(c(keys,value) %in% names(d))) record_failure("missing prediction records/keys")
    d <- unique(d[,c(keys,value),drop=FALSE])
    if(anyNA(d) || any(!is.finite(d[[value]]))) record_failure("non-finite predictions or missing keys")
    for(k in keys) d[[k]] <- as.character(d[[k]])
    if(anyDuplicated(d[,keys,drop=FALSE])) record_failure("conflicting predictions at duplicate keys")
    d
  }
  compare <- function(a,b) {
    z <- merge(prepare(a,"PRED"),prepare(b,"POP_PRED"),by=keys,all=TRUE,sort=FALSE)
    if(nrow(z)!=nrow(unique(a[,keys,drop=FALSE])) || nrow(z)!=nrow(unique(b[,keys,drop=FALSE])) || anyNA(z))
      record_failure("native/simulator record coverage differs; never drop unmatched rows")
    z$abs_delta <- abs(z$PRED-z$POP_PRED)
    z$rel_delta <- z$abs_delta/pmax(abs(z$PRED),abs(z$POP_PRED),atol,.Machine$double.eps)
    z$failed <- z$abs_delta>atol+rtol*pmax(abs(z$PRED),abs(z$POP_PRED));z
  }
  metrics <- function(z) list(records=nrow(z),failed=sum(z$failed),max_abs=max(z$abs_delta),max_rel=max(z$rel_delta))
  check <- compare(native,population)
  summary <- list(schema=1L,tag=tag,state="matched",rtol=rtol,atol=atol,override_reason=reason,frozen=metrics(check))
  detail <- check;failure <- NULL
  if(any(check$failed)) {
    summary$state <- "mismatch"
    if(is.function(reference)) {
      refined <- tryCatch(reference(),error=function(e) {failure <<- conditionMessage(e);NULL})
      if(!is.null(refined)) {
        strict <- compare(refined,population);summary$strict <- metrics(strict);summary$solver <- attr(refined,"solver")
        if(!any(strict$failed)) summary$state <- "numerical_drift_verified" else detail <- strict
      }
    }
  }
  groups <- setdiff(keys,c("ID","time","TIME"))
  if(length(groups)) summary$endpoints <- lapply(split(check,interaction(check[groups],drop=TRUE)),metrics)
  summary$worst_records <- head(detail[order(detail$rel_delta,decreasing=TRUE),,drop=FALSE],20L)
  if(!is.null(failure)) summary$reference_error <- failure
  if(!is.null(diagnostics)) {
    dir.create(dirname(diagnostics),recursive=TRUE,showWarnings=FALSE)
    jsonlite::write_json(summary,diagnostics,auto_unbox=TRUE,pretty=TRUE,na="null",digits=16)
  }
  message <- sprintf("%s records=%d failed=%d max_abs=%.8g max_rel=%.8g rtol=%.8g atol=%.8g%s",
    tag,nrow(detail),sum(detail$failed),max(detail$abs_delta),max(detail$rel_delta),rtol,atol,
    if(is.null(diagnostics)) "" else paste0(" diagnostics=",diagnostics))
  if(summary$state=="mismatch") stop("PMX_SIMULATOR_PREDICTION_MISMATCH: ",message,
    "; check equations/parameters/events/covariates/scale and the saved strict-reference diagnosis; do not refit or loosen automatically",
    if(is.null(failure)) "" else paste0("; reference: ",failure),call.=FALSE)
  cat(if(summary$state=="matched") "PMX_SIMULATOR_PREDICTIONS_OK " else "PMX_SIMULATOR_NUMERICAL_DRIFT_VERIFIED ",message,"\n",sep="")
  attr(check,"validation") <- summary
  invisible(check)
}

pmx_vpc_population <- function(observed,population,keys=c("ID","time")) {
  index <- do.call(paste,c(lapply(population[keys],as.character),sep="\r"))
  if(anyDuplicated(index)) stop("PMX_SIMULATOR_RECORD_MISMATCH: population reference is not unique")
  order <- match(do.call(paste,c(lapply(observed[keys],as.character),sep="\r")),index)
  if(anyNA(order)) stop("PMX_SIMULATOR_RECORD_MISMATCH: an observation lacks its verified population prediction")
  observed$PRED <- population$POP_PRED[order];observed
}

# Every replicate retains the same observed record multiset; failed solves cannot quietly disappear.
pmx_vpc_records <- function(observed,simulated,nsim,keys=c("ID","time")) {
  if(any(!is.finite(observed$DV)) || any(!is.finite(simulated$IPRED)) || any(!is.finite(simulated$PRED)))
    stop("PMX_VPC_NONFINITE: observed/simulated values must be finite; retain errors instead of dropping rows")
  signature <- function(d) {
    d <- d[,keys,drop=FALSE];for(k in keys)d[[k]] <- as.character(d[[k]])
    if(anyNA(d)) stop("PMX_VPC_RECORD_MISMATCH: missing record keys")
    d <- d[do.call(order,d),,drop=FALSE];rownames(d)<-NULL;d
  }
  target <- signature(observed)
  reps <- sort(unique(simulated$rep))
  if(!identical(as.integer(reps),seq_len(nsim))) stop("PMX_VPC_RECORD_MISMATCH: missing or unexpected simulation replicate")
  for(i in reps) if(!identical(signature(simulated[simulated$rep==i,,drop=FALSE]),target))
    stop("PMX_VPC_RECORD_MISMATCH: replicate ",i," differs from observed subject-time-endpoint records")
  invisible(TRUE)
}

# Data parameters belong to the frozen simulator, not just newly retained SCM effects.
pmx_sim_covariates <- function(mod,events,data,required=character(),fixed=character()) {
  parameters <- names(mrgsolve::param(mod))
  fixed <- tolower(sub("^t[.]","",fixed))
  parameters <- parameters[!tolower(parameters) %in% c(fixed,"dvid")]
  for(cv in required) if(!any(tolower(parameters)==tolower(cv)))
    stop("REPORT_SIMULATOR_COVARIATE_MISMATCH: missing frozen covariate parameter ",cv)
  for(target in parameters) {
    source <- which(tolower(names(data))==tolower(target))
    if(length(source)>1L) stop("REPORT_SIMULATOR_COVARIATE_MISMATCH: ambiguous data parameter ",target)
    if(length(source)==1L) events[[target]] <- data[[source]]
  }
  events
}
