# NCA owns its response selection; fitting aliases must not change this reader.
pmx_nca_read <- function(path,column="DV") {
  lines <- readLines(path,warn=FALSE)
  if(!length(lines)) stop("Empty NCA data")
  sep <- if(grepl("\t",lines[1],fixed=TRUE)) "\t" else if(grepl(",",lines[1],fixed=TRUE)) "," else if(grepl(";",lines[1],fixed=TRUE)) ";" else ""
  d <- read.table(text=paste(lines,collapse="\n"),header=TRUE,sep=sep,quote="\"",comment.char="",
    na.strings=c(".","","NA"),check.names=FALSE,stringsAsFactors=FALSE)
  names(d) <- tolower(sub("^[@#]","",names(d)))
  if(anyDuplicated(names(d))) stop("Duplicate NCA columns")
  column <- tolower(column)
  if(!column %in% names(d)) stop("NCA_INPUT_REQUIRED: missing response column ",column)
  attr(d,"nca_raw_dv") <- d$dv
  d$dv <- d[[column]]
  if(!is.numeric(d$dv)) stop("NCA_INPUT_REQUIRED: selected response must be numeric")
  if(!"evid" %in% names(d)) {
    if(!"amt" %in% names(d) || any(d$amt>0,na.rm=TRUE)) stop("Dose records require EVID")
    d$evid <- 0L
  }
  if(!"amt" %in% names(d)) d$amt <- 0
  if(!"mdv" %in% names(d)) d$mdv <- as.integer(d$evid!=0 | is.na(d$dv))
  d$dv[d$evid!=0 | d$mdv!=0] <- NA_real_
  d
}
pmx_nca_scale_check <- function(d,column,scale,obs) {
  column <- tolower(column)
  if(!scale %in% c("raw","log")) stop("NCA_SCALE_REQUIRED: raw or natural log")
  raw <- attr(d,"nca_raw_dv"); logged <- d$lndv
  if(!is.null(raw) && !is.null(logged)) {
    use <- which(obs)
    consistent <- length(use)>0L && all(is.finite(raw[use]) & raw[use]>0 & is.finite(logged[use])) &&
      all(abs(log(raw[use])-logged[use])<=1e-6*(1+abs(logged[use])))
    if(consistent && ((column=="dv" && scale=="log") || (column=="lndv" && scale=="raw")))
      stop("NCA_SCALE_MISMATCH: DV is raw and LNDV=log(DV); use DV/raw or LNDV/log, independently of the fit response")
  }
  if(scale=="log" && any(!is.finite(exp(d$dv[obs])))) stop("NCA_SCALE_MISMATCH: transformed response overflows")
  invisible(TRUE)
}
