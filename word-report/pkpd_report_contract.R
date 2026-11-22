# Reporting only: explicit endpoints/scales and frozen simulator quantities, no fitting.
pmx_pkpd_contract <- function(ctl,pk=1L,pd=2L,scale=c(PK="auto",PD="auto")) {
  if(length(pk)!=1L || length(pd)!=1L || any(!is.finite(c(pk,pd))) || pk==pd)
    stop("PKPD_ENDPOINT_REQUIRED: distinct PK/PD model endpoint indices")
  text <- readLines(ctl,warn=FALSE)
  input <- paste(ctl_body(ctl,"INPUT"),collapse=" ")
  # A dropped duplicate column is spelled DV=DROP, so the observation alias is the first
  # DV=<name> token that is not an ignored placeholder.
  hits <- regmatches(input,gregexpr("\\bDV=([A-Za-z][A-Za-z0-9_]*)",input,ignore.case=TRUE,perl=TRUE))[[1]]
  alias <- toupper(sub("^.*DV=","",hits,ignore.case=TRUE))
  alias <- alias[!alias %in% c("DROP","NULL","")]
  selected <- if(length(alias)) alias[1] else "DV"
  if(!identical(sort(names(scale)),c("PD","PK")) || any(!scale %in% c("auto","raw","log")))
    stop("PKPD_SCALE_REQUIRED: named PK/PD scales raw or natural log")
  if(any(scale=="auto")) {
    log_error <- grepl("\\bLOG\\s*\\(",paste(ctl_body(ctl,"ERROR"),collapse=" "),ignore.case=TRUE)
    # Two measured DVs are authored with a log DV by default (references/nonmem_rules.md), so an
    # unlabelled response column plus a log $ERROR is the log scale, not an ambiguity.
    inferred <- if(selected %in% c("LNDV","LOGDV","LN_DV","LOG_DV")) "log" else
      if(!identical(as.integer(pk),as.integer(pd)) && log_error) "log" else "raw"
    scale[scale=="auto"] <- inferred
  }
  list(pk=pk,pd=pd,scale=scale,sigma=names(pmx_endpoint(ctl)$sds))
}
pmx_pkpd_natural <- function(value,endpoint,contract,scale=contract$scale) {
  if(!identical(sort(names(scale)),c("PD","PK")) || any(!scale %in% c("raw","log")))
    stop("PKPD_SCALE_REQUIRED: named PK/PD scales raw or natural log")
  for(role in c("PK","PD")) if(scale[[role]]=="log") {
    rows <- !is.na(endpoint) & endpoint==contract[[tolower(role)]]
    value[rows] <- exp(value[rows])
  }
  value
}
pmx_pkpd_aug <- function(a,model_data,contract) {
  bad <- function(reason) stop("PKPD_ENDPOINT_REQUIRED: ",reason,call.=FALSE)
  # nlmixr2's uppercase IPRED is the fitted observation prediction; lowercase
  # ipred can be an unrelated structural intermediate (including a different scale).
  original <- names(a); upper <- toupper(original)
  canonical <- c("DV","PRED","IPRED","RES","WRES","IRES","IWRES","CPRED","CRES","CWRES")
  keep <- rep(TRUE,length(original))
  for(n in unique(upper[duplicated(upper)])) {
    i <- which(upper==n)
    if(!n %in% canonical || sum(original[i]==n)!=1L) bad(paste("ambiguous result columns:",n))
    keep[i[original[i]!=n]] <- FALSE
  }
  a <- a[,keep,drop=FALSE]; names(a) <- upper[keep]
  names(model_data) <- toupper(names(model_data))
  if(anyDuplicated(names(model_data))) bad("duplicate source columns")
  observed <- function(d) {
    use <- rep(TRUE,nrow(d))
    for(n in intersect(c("EVID","MDV"),names(d))) use <- use & !is.na(d[[n]]) & d[[n]]==0
    use
  }
  obs <- observed(a)
  allowed <- c(contract$pk,contract$pd)
  mapped <- NULL
  if("NMDVID" %in% names(a)) {
    if(!all(c("NMDVID","DVID") %in% names(model_data))) bad("source DVID map unavailable")
    lookup <- unique(model_data[observed(model_data),c("NMDVID","DVID"),drop=FALSE])
    if(anyNA(lookup) || anyDuplicated(lookup$NMDVID)) bad("original DVID map is ambiguous")
    mapped <- lookup$DVID[match(a$NMDVID,lookup$NMDVID)]
    if(anyNA(mapped[obs])) bad("original DVID has no source endpoint")
  }
  if("DVID" %in% names(a)) {
    if(!is.null(mapped) && any(a$DVID[obs]!=mapped[obs],na.rm=TRUE)) bad("DVID conflicts with preserved original DVID")
    if(!is.null(mapped)) a$DVID[is.na(a$DVID)] <- mapped[is.na(a$DVID)]
  } else if(!is.null(mapped)) {
    a$DVID <- mapped
  } else {
    p <- contract$endpoints
    if(!"CMT" %in% names(a) || !is.data.frame(p) || !all(c("cmt","dvid") %in% names(p)))
      bad("fitted observation endpoint is missing; never infer it from sorted CMT labels")
    # Numeric backend compartments and explicitly named endpoints are distinct.
    # Do not use factor ordinals: sensitivity states can alter their levels.
    key <- if(is.numeric(a$CMT) && !is.factor(a$CMT)) "cmt" else
      if("var" %in% names(p)) "var" else "cond"
    if(!key %in% names(p)) bad("fitted endpoint label map unavailable")
    lookup <- unique(p[,c(key,"dvid"),drop=FALSE])
    if(anyNA(lookup) || anyDuplicated(lookup[[key]])) bad("ambiguous fitted CMT map")
    a$DVID <- lookup$dvid[match(as.character(a$CMT),as.character(lookup[[key]]))]
  }
  if(anyNA(a$DVID[obs]) || any(!a$DVID[obs] %in% allowed)) bad("unknown fitted endpoint")
  for(n in intersect(c("DV","PRED","IPRED"),names(a))) a[[n]] <- pmx_pkpd_natural(a[[n]],a$DVID,contract)
  a
}
# Convert a declared simulator scale to the fitted observation scale before shared augmentation.
pmx_pkpd_sim_to_model <- function(value, endpoint, contract, scale=contract$scale) {
  if(!identical(sort(names(scale)),c("PD","PK")) || any(!scale %in% c("raw","log")))
    stop("PKPD_SCALE_REQUIRED: named simulator PK/PD scales raw or log")
  for(role in c("PK","PD")) if(scale[[role]]!=contract$scale[[role]]) {
    rows <- !is.na(endpoint) & endpoint==contract[[tolower(role)]]
    if(contract$scale[[role]]=="log") {
      if(any(value[rows]<=0,na.rm=TRUE)) stop("PKPD_SIMULATOR_SCALE_MISMATCH: nonpositive natural prediction")
      value[rows] <- log(value[rows])
    } else value[rows] <- exp(value[rows])
  }
  value
}
