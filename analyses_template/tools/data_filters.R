
pmx_expand_records <- function(lines) {
  out <- character(0)
  for(l in lines) {
    m <- regmatches(l,regexec("^\\s*(\\$(?:THETA|OMEGA|SIGMA)(?:\\s+(?:BLOCK|DIAGONAL)\\([0-9]+\\))?)\\s+([-+.(0-9].*)$",l,ignore.case=TRUE,perl=TRUE))[[1]]
    out <- c(out,if(length(m)) c(m[2],m[3]) else l)
  }
  out
}
# Shared by initial checks and fitting. A disclosure is not human authorization.
pmx_fixed_parameters <- function(txt) {
  approved <- toupper(gsub("\\s+","",strsplit(Sys.getenv("PMX_FIXED_APPROVED",""),";",fixed=TRUE)[[1]]))
  number <- function(x) {v <- suppressWarnings(as.numeric(gsub("[dD]","e",x))); if(is.finite(v)) format(v,digits=15,trim=TRUE,scientific=FALSE) else x}
  approved <- vapply(approved,function(x) {
    pair <- strsplit(x,"=",fixed=TRUE)[[1]]
    if(length(pair)==2L) paste0(pair[1],"=",number(pair[2])) else ""
  },"")
  blocked <- character();record <- "";index <- 0L
  add <- function(name,value,line) {
    entry <- paste0(name,"=",number(value))
    if(!entry %in% approved || !grepl(";\\s*PMX_FIXED\\s*:",line,ignore.case=TRUE))
      blocked <<- c(blocked,entry)
  }
  vocab <- "^(TV[A-Z0-9_]*|F[0-9]*|LF1|BIO[A-Z0-9_]*|FRAC[A-Z0-9_]*|CL|VC|V[0-9]*|Q[0-9]*|VP|VSS|KA[0-9]*|KE|K[0-9]+|VMAX|KM|KIN|KOUT|EC50|IC50|EMAX|IMAX|HILL|GAMMA|MTT|TLAG|ALAG[0-9]*|LAG[0-9]*|KON|KOFF|KDEG|KD|KG|RSS|KINT|W0|BASE)$"
  for(line in txt) {
    code <- toupper(trimws(sub(";.*$","",line)))
    if(grepl("^\\$",code)) {record <- sub("^\\$([A-Z0-9_]+).*","\\1",code);index <- 0L;code <- trimws(sub("^\\$[A-Z0-9_]+","",code))}
    if(record %in% c("THETA","OMEGA","SIGMA") && nzchar(code)) {
      if(grepl("^(BLOCK|DIAGONAL)\\s*\\(",code)) {
        if(grepl("\\bFIX(?:ED)?\\b",code,perl=TRUE)) blocked <- c(blocked,paste0(record," header FIX"))
        next
      }
      index <- index+1L
      raw <- trimws(gsub("\\bFIX(?:ED)?\\b","",code,perl=TRUE))
      values <- suppressWarnings(as.numeric(gsub("[dD]","e",strsplit(gsub("[()]","",raw),"[,[:space:]]+")[[1]])))
      values <- values[is.finite(values)]
      pinned_bounds <- record=="THETA" && length(values)==3L && values[1]==values[3]
      if(grepl("\\bFIX(?:ED)?\\b",code,perl=TRUE) || pinned_bounds) {
        if(length(values)) add(paste0(record,"(",index,")"),as.character(values[if(record=="THETA" && length(values)>1L) 2L else 1L]),line)
        else blocked <- c(blocked,paste0(record,"(",index,") FIX"))
      }
    }
    if(record %in% c("PK","PRED","MAIN","DES")) {
      m <- regmatches(code,regexec("(?:^|\\s)((?:F_|ALAG_|D_|R_)?[A-Z][A-Z0-9_]*)\\s*=\\s*([-+]?[0-9]*\\.?[0-9]+(?:[ED][-+]?[0-9]+)?)\\s*$",code,perl=TRUE))[[1]]
      if(length(m) && (grepl(vocab,sub("^(F_|ALAG_|D_|R_)","",m[2])) || grepl("^(F_|ALAG_)",m[2])))
        add(m[2],m[3],line)
    }
  }
  unique(blocked)
}
pmx_validate_ctl <- function(ctl) {
  txt <- readLines(ctl,warn=FALSE)
  if(any(grepl("^\\s*\\$OMEGA.*(SAME|FIX)",txt,ignore.case=TRUE))) stop("OMEGA SAME/header FIX requires a dedicated export backend")
  if(any(grepl("^\\s*\\$SIGMA.*(BLOCK|SAME|FIX)",txt,ignore.case=TRUE))) stop("SIGMA covariance/SAME/header FIX requires a dedicated residual/export backend")
  if(sum(grepl("^\\s*\\$THETA(?:\\s|$)",txt,ignore.case=TRUE,perl=TRUE))!=1L) stop("Use one THETA record, one parameter per line")
  b <- ctl_body(ctl,"THETA"); b <- trimws(b[nzchar(trimws(b))])
  if(any(!grepl("^(\\([^()]+\\)|[-+0-9.eEdD]+)\\s*(FIX|FIXED)?$",b,ignore.case=TRUE))) stop("THETA requires one scalar or bound tuple per line")
  if(sum(grepl("^\\s*\\$SIGMA",txt,ignore.case=TRUE))!=1L) stop("Use one SIGMA record with one variance per line")
  # Workspace contract: dual parallel depots include an estimated relative delay.
  model_code <- toupper(paste(ctl_body(ctl,"MODEL"),collapse=" "))
  pk <- toupper(ctl_body(ctl,"PK"))
  dual <- grepl("DEPOT1",model_code,fixed=TRUE) && grepl("DEPOT2",model_code,fixed=TRUE)
  if(dual) {
    assignments <- regmatches(pk,regexec("^\\s*([A-Z][A-Z0-9_]*)\\s*=\\s*(.+)$",pk,perl=TRUE))
    assignments <- assignments[lengths(assignments)>0]
    rhs <- setNames(vapply(assignments,function(x) x[3],""),vapply(assignments,function(x) x[2],""))
    estimated <- function(expr,seen=character()) {
      theta <- unlist(regmatches(expr,gregexpr("THETA\\s*\\(\\s*[0-9]+\\s*\\)",expr,perl=TRUE)))
      if(length(theta)) {
        index <- as.integer(gsub("[^0-9]","",theta))
        return(any(index<=length(b) & !grepl("FIX",b[index],fixed=TRUE)))
      }
      tokens <- unique(unlist(regmatches(expr,gregexpr("[A-Z][A-Z0-9_]*",expr,perl=TRUE))))
      tokens <- setdiff(intersect(tokens,names(rhs)),seen)
      any(vapply(tokens,function(v) estimated(rhs[[v]],c(seen,v)),TRUE))
    }
    lag <- intersect(c("ALAG1","ALAG2"),names(rhs))
    if(!length(lag) || !any(vapply(lag,function(v) estimated(rhs[[v]],v),TRUE)))
      stop("PARALLEL_TLAG_REQUIRED: parallel absorption in this workspace requires estimated TLAG, e.g. TVALAG2 = THETA(k), ALAG2 = TVALAG2; do not remove it or pin it to zero")
  }
  fixed <- pmx_fixed_parameters(txt)
  if(length(fixed)) stop("Unapproved fixed parameter(s): ",paste(fixed,collapse=", "),
    "; estimate them. PMX_FIXED comments and scientific guesses are not approval. Only explicit user-approved name=value entries in PMX_FIXED_APPROVED permit disclosed constants.")

}
pmx_filter_data <- function(d,ctl) {
  spec <- paste(ctl_body(ctl,"DATA"),collapse=" ")
  rules <- unlist(regmatches(spec,gregexpr("(?:IGNORE|ACCEPT)\\s*=\\s*\\([^)]*\\)",spec,ignore.case=TRUE,perl=TRUE)))
  if(!length(rules)) return(d)
  interpret <- function(node) {
    if(is.atomic(node)) return(node)
    if(is.name(node)) {
      nm <- tolower(as.character(node)); if(!nm %in% names(d)) stop("Unknown DATA filter column: ",nm)
      return(d[[nm]])
    }
    op <- as.character(node[[1]])
    if(!op %in% c("(","==","!=",">",">=","<","<=","&","|","!","-","+")) stop("Unsupported DATA filter operator")
    args <- lapply(as.list(node)[-1],interpret)
    do.call(get(op,envir=baseenv()),args)
  }
  ignore <- rep(FALSE,nrow(d)); accept <- rep(FALSE,nrow(d)); has_accept <- FALSE
  for(rule in rules) {
    is_accept <- grepl("^ACCEPT",trimws(rule),ignore.case=TRUE)
    expr <- sub("^[^(]*\\((.*)\\)$","\\1",rule)
    for(pair in list(c("EQ","=="),c("NE","!="),c("GT",">"),c("GE",">="),c("LT","<"),c("LE","<="),c("AND","&"),c("OR","|"),c("NOT","!"))) expr <- gsub(paste0("[.]",pair[1],"[.]"),pair[2],expr,ignore.case=TRUE)
    ast <- parse(text=expr)
    if(length(ast)!=1L) stop("DATA filter must be a single expression")
    v <- interpret(ast[[1]]); if(length(v)==1L) v <- rep(v,nrow(d))
    if(!is.logical(v) || length(v)!=nrow(d) || anyNA(v)) stop("DATA filter must produce one nonmissing logical per row; declare missing-value policy")
    if(is_accept) {accept <- accept|v; has_accept <- TRUE} else ignore <- ignore|v
  }
  d[!ignore & (!has_accept|accept),,drop=FALSE]
}

pmx_check_indexed_eta <- function(ctl) {
  code <- paste(sub(";.*$","",readLines(ctl,warn=FALSE)),collapse="\n")
  refs <- regmatches(code,gregexpr("\\bETA\\s*\\([^)]*\\)",code,perl=TRUE,ignore.case=TRUE))[[1]]
  index <- sub("^ETA\\s*\\((.*)\\)$","\\1",refs,ignore.case=TRUE)
  bad <- refs[!grepl("^[[:space:]]*[1-9][0-9]*[[:space:]]*$",index)]
  if(length(bad)) stop("MODEL_CONTRACT_DYNAMIC_ETA_UNSUPPORTED: ",paste(unique(bad),collapse=", "),
    "; nonmem2rx backend requires literal ETA indices. Author a supported explicit occasion structure before screening; never rewrite/resubmit an ended slot")
  invisible(TRUE)
}
