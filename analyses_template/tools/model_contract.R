contract_sources <- vapply(sys.frames(),function(frame) {
  p <- frame$ofile; if(is.character(p) && length(p)) p[1] else ""
},"")
contract_sources <- contract_sources[basename(contract_sources)=="model_contract.R" & file.exists(contract_sources)]
contract_source <- if(length(contract_sources)) tail(contract_sources,1L) else file.path(Sys.getenv("PMX_TOOLKIT",""),"analyses_template","tools","model_contract.R")
if(!file.exists(contract_source)) stop("MODEL_CONTRACT_PATH_REQUIRED: source from a file or set PMX_TOOLKIT to the complete workspace root")
source(file.path(dirname(contract_source),"data_filters.R"),local=TRUE)
source(file.path(dirname(contract_source),"screen_fit_identity.R"),local=TRUE)
ctl_body <- function(path, key) {
  txt <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  if (!length(txt)) return(character(0))
  txt <- sub(";.*$", "", txt)
  hit <- grep(paste0("^\\s*\\$", key, "[^A-Za-z]"), txt, ignore.case = TRUE)
  if (!length(hit)) {
    hit <- grep(paste0("^\\s*\\$", key, "\\s*$"), txt, ignore.case = TRUE)
    if (!length(hit)) return(character(0))
  }
  i <- hit[1]
  after <- grep("^\\s*\\$", txt)
  after <- after[after > i]
  j <- if (length(after)) after[1] - 1L else length(txt)
  b <- txt[i:j]
  b[1] <- sub(paste0("^\\s*\\$", key, "[[:space:]]*"), "", b[1], ignore.case = TRUE)
  b
}
ctl_sigma_sd <- function(path) {
  b <- ctl_body(path, "SIGMA")
  if(any(grepl("BLOCK|SAME|FIX",b,ignore.case=TRUE))) stop("Residual covariance/FIX requires explicit handling")
  if (!length(b)) return(numeric(0))
  t <- unlist(strsplit(b, "[,[:space:]]+")); t <- t[nzchar(t)]
  v <- suppressWarnings(as.numeric(t)); v <- v[!is.na(v)]
  if (!length(v)) return(numeric(0))
  pmax(sqrt(pmax(v, 0)), 0.01)
}
ctl_obs_cmt <- function(path) {
  mb <- paste(ctl_body(path,"MODEL"),collapse=" ")
  comps <- unlist(regmatches(mb,gregexpr("COMP(?:ARTMENT)?\\s*=\\s*\\([^)]*\\)",mb,ignore.case=TRUE,perl=TRUE)))
  explicit <- which(grepl("\\bDEFOBS(?:ERVATION)?\\b",comps,ignore.case=TRUE,perl=TRUE))
  if(length(explicit)>1L) stop("Multiple DEFOBSERVATION compartments")
  if(length(explicit)) return(as.integer(explicit))
  sr <- paste(c(ctl_body(path,"SUBROUTINES"),ctl_body(path,"SUBROUTINE")),collapse=" ")
  hit <- regmatches(sr,regexec("ADVAN\\s*([0-9]+)",sr,ignore.case=TRUE))[[1]]
  if(length(hit)) {
    fixed <- c(`1`=1L,`2`=2L,`3`=1L,`4`=2L,`10`=1L,`11`=1L,`12`=2L)
    v <- unname(fixed[hit[2]])
    if(length(v) && !is.na(v)) return(v)
  }
  # General ADVAN defaults follow MODEL: CENTRAL if named, otherwise first compartment.
  nm <- sub("^[^(]*\\(","",comps)
  nm <- sub("\\)$","",nm)
  nm <- toupper(gsub("[\"']","",trimws(sub("[, ].*$","",nm))))
  central <- which(nm=="CENTRAL")
  if(length(central)==1L) return(as.integer(central))
  if(length(comps)) return(1L)
  # Without MODEL or a built-in default, require an explicit observation setting.
  NA_integer_
}

ctl_eps <- function(path) {
  b <- ctl_body(path, "ERROR")
  if (!length(b)) return(list(kind = character(0), logscale = FALSE))
  s <- toupper(paste(b, collapse = " "))
  logscale <- grepl("(LOG|LN)[[:space:]]*\\(", s, ignore.case = TRUE)
  pos <- gregexpr("EPS[[:space:]]*\\([[:space:]]*[0-9]+[[:space:]]*\\)", s)[[1]]
  if (!length(pos) || pos[1] == -1L) return(list(kind = character(0), logscale = logscale))
  kind <- vapply(seq_along(pos), function(i) {
    pre <- if (pos[i] > 1L) substr(s, max(1L, pos[i] - 20L), pos[i] - 1L) else ""
    if (grepl("[*/][[:space:]]*$", pre)) "prop"
    else if (grepl("\\([[:space:]]*1([.]0*)?[[:space:]]*[+-][[:space:]]*$", pre)) "prop"
    else if (grepl("[+-][[:space:]]*$", pre)) "add"
    else "prop"
  }, character(1))
  list(kind = kind, logscale = logscale && all(kind == "add"))
}
derive_endpoint <- function(ctl) {
  code <- toupper(gsub("[[:space:]]+","",ctl_body(ctl,"ERROR")))
  code <- code[nzchar(code)]
  if(length(code)>1L && grepl("^Y=IPRED",tail(code,1L))) {
    y <- tail(code,1L)
    expression <- regmatches(y,regexec("^Y=IPRED(?:\\+(?:IPRED|W)\\*EPS\\(([0-9]+)\\))?(?:\\+EPS\\(([0-9]+)\\))?$",y))[[1]]
    if(length(expression) && (!grepl("W[*]EPS",y) || "W=IPRED" %in% code)) {
      slot <- which(nzchar(expression[-1L]))
      indices <- as.integer(expression[slot+1L])
      sds <- ctl_sigma_sd(ctl)
      if(length(indices) && all(indices>0L & indices<=length(sds)))
        return(list(lines=paste0("ipred ~ ",paste(paste0(c("prop","add")[slot],"(sd",indices,")"),collapse=" + ")),
                    sds=sds[indices]))
    }
  }
  ep <- ctl_eps(ctl); sds <- ctl_sigma_sd(ctl); k <- ep$kind
  if (!length(k) || length(k) > 4L) return(NULL)      # nothing to derive, or nonsense
  if (length(sds) < length(k)) sds <- c(sds, rep(0.3, length(k) - length(sds)))
  sds <- sds[seq_along(k)]
  terms <- ifelse(k == "prop", sprintf("prop(sd%d)", seq_along(k)),
                                  sprintf("add(sd%d)", seq_along(k)))
  list(lines = c(if (ep$logscale) "conc <- log(f)" else "conc <- f",
                 paste0("conc ~ ", paste(terms, collapse = " + "))),
       sds = sds)
}
# Infer only explicit flat observation branches; never guess endpoint order from data.
pmx_tmdd_error <- function(lines) {
  code <- toupper(gsub("[[:space:]]+","",lines))
  code <- code[nzchar(code)]
  first <- match("IPRED=LOG(0.0001)",code)
  if(is.na(first) || first<=1L || length(code)!=first+9L) return(NULL)
  branches <- code[seq.int(first+2L,length(code))]
  pk <- regmatches(branches[1],regexec("^IF\\(CMT\\.EQ\\.([0-9]+)\\.AND\\.F\\.GT\\.0\\)THEN$",branches[1]))[[1]]
  pd <- regmatches(branches[5],regexec("^IF\\(CMT\\.EQ\\.([0-9]+)(\\.AND\\.F\\.GT\\.0)?\\)THEN$",branches[5]))[[1]]
  if(length(pk)!=2L || length(pd)<2L || pk[2]==pd[2] || code[first+1L]!="Y=IPRED" ||
     !identical(branches[c(3:4,7:8)],c("Y=IPRED+EPS(1)","ENDIF","Y=IPRED+EPS(2)","ENDIF"))) return(NULL)
  assignments <- branches[c(2L,6L)]
  floor_prediction <- c("IPRED=LOG(MAX(LFREE,0.0001))","IPRED=LOG(MAX(RTOT,0.0001))")
  guarded_prediction <- c("IF(LFREE.GT.0)IPRED=LOG(LFREE)","IF(RTOT.GT.0)IPRED=LOG(RTOT)")
  if(identical(assignments,guarded_prediction) && length(pd)==3L && nzchar(pd[3])) {
    prediction <- c("LOG(IFELSE(LFREE>0,LFREE,0.0001))","LOG(IFELSE(RTOT>0,RTOT,0.0001))")
    guard_target <- TRUE
  } else if(identical(assignments,floor_prediction) && (length(pd)==2L || !nzchar(pd[3]))) {
    prediction <- sub("^IPRED=","",assignments)
    guard_target <- FALSE
  } else return(NULL)
  preamble <- code[seq_len(first-1L)]
  if(any(!grepl("^(LTOT|RTOT|LFREE|RFREE)=",preamble)) ||
     anyDuplicated(sub("=.*$","",preamble)) || !all(c("LFREE","RTOT") %in% sub("=.*$","",preamble))) return(NULL)
  list(preamble=preamble,prediction=prediction,selector=paste0("CMT=",pk[2],",",pd[2]),
       guard_target=guard_target)
}

pmx_named_error <- function(lines) {
  code <- toupper(gsub("[[:space:]]+","",lines))
  code <- code[nzchar(code)]
  first <- grep("^IPRED=(0|LOG\\([0-9.]+\\))$",code)[1]
  if(is.na(first) || length(code)<first+5L || code[first+1L]!="Y=IPRED") return(NULL)
  default <- sub("^IPRED=","",code[first])
  preamble <- if(first>1L) code[seq_len(first-1L)] else character()
  if(any(!grepl("^[A-Z][A-Z0-9_]*=",preamble)) ||
     any(grepl("(^|[^A-Z0-9_])(F|IPRED|Y|EPS)([^A-Z0-9_]|$)",preamble))) return(NULL)
  branches <- code[seq.int(first+2L,length(code))]
  endpoints <- list(); defaults <- list()
  while(length(branches)) {
    sel <- regmatches(branches[1L],regexec(
      "^IF\\((CMT|DVID)\\.EQ\\.([0-9]+)(\\.AND\\.([A-Z][A-Z0-9_]*)\\.GT\\.0)?\\)THEN$",branches[1L]))[[1]]
    if(length(branches)<4L || !length(sel) || !startsWith(branches[2L],"IPRED=") ||
       !startsWith(branches[3L],"Y=IPRED") || branches[4L]!="ENDIF") return(NULL)
    pred <- sub("^IPRED=","",branches[2L])
    y <- sub("^Y=","",branches[3L])
    key <- paste(sel[2L],sel[3L],sep="=")
    branches <- branches[-seq_len(4L)]
    if(y=="IPRED" && !nzchar(sel[4L]) && grepl("^LOG\\([0-9.]+\\)$",pred)) {
      defaults[[key]] <- pred
      next
    }
    test <- sel[5L]
    if(nzchar(test)) {
      if(pred!=paste0("LOG(",test,")")) return(NULL)
      fallback <- defaults[[key]]
      if(is.null(fallback)) fallback <- default
      if(!grepl("^LOG\\([0-9.]+\\)$",fallback)) return(NULL)
      pred <- paste0("LOG(IFELSE(",test,">0,",test,",",sub("^LOG\\((.+)\\)$","\\1",fallback),"))")
    } else if(grepl("\\b(?:F|IPRED|Y|EPS)\\b",pred,perl=TRUE)) return(NULL)
    term <- regmatches(y,regexec("^IPRED(?:\\+IPRED\\*EPS\\(([0-9]+)\\))?(?:\\+EPS\\(([0-9]+)\\))?$",y))[[1]]
    if(!length(term)) return(NULL)
    indices <- which(nzchar(term[-1L]))
    if(!length(indices)) return(NULL)
    endpoints[[length(endpoints)+1L]] <- list(variable=sel[2L],level=sel[3L],prediction=pred,
        eps=as.integer(term[indices+1L]),kind=c("prop","add")[indices],test=test)
  }
  if(length(endpoints)!=2L) return(NULL)
  list(preamble=preamble,endpoints=endpoints)
}

pmx_native_endpoints <- function(ctl) {
  tmdd <- pmx_tmdd_error(ctl_body(ctl,"ERROR"))
  if(!is.null(tmdd)) {
    sigma <- ctl_sigma_sd(ctl)
    if(length(sigma)<2L) stop("TMDD residual terms require two SIGMA variances")
    return(list(lines=c(paste("obs1 <-",tolower(tmdd$prediction[1])),"obs1 ~ add(sd1)",
                        paste("obs2 <-",tolower(tmdd$prediction[2])),"obs2 ~ add(sd2)"),
                sds=setNames(sigma[1:2],c("sd1","sd2")),selector=tmdd$selector,tmdd=tmdd))
  }
  named <- pmx_named_error(ctl_body(ctl,"ERROR"))
  if(!is.null(named)) {
    endpoints <- named$endpoints
  } else {
    code <- toupper(gsub("[[:space:]]+","",ctl_body(ctl,"ERROR")))
    active <- NULL; endpoints <- list()
    for(line in code) {
      match <- regmatches(line,regexec("^(?:ELSE)?IF\\((CMT|DVID)\\.EQ\\.([0-9]+)\\)THEN$",line,perl=TRUE))[[1]]
      if(length(match)) {active <- list(variable=match[2],level=match[3]);next}
      if(line=="ENDIF") {active <- NULL;next}
      if(line=="ELSE" || grepl("^IF.*THEN$",line)) return(NULL)
      if(!grepl("^Y=",line)) next
      if(is.null(active)) return(NULL)
      expression <- sub("^Y=","",line);prediction <- NULL;eps <- integer();kind <- character()
      match <- regmatches(expression,regexec("^(.+)\\*\\(1(?:[.]0*)?\\+EPS\\(([0-9]+)\\)\\)(?:\\+EPS\\(([0-9]+)\\))?$",expression,perl=TRUE))[[1]]
      if(length(match)) {
        prediction <- match[2];eps <- as.integer(match[3]);kind <- "prop"
        if(length(match)>=4L && nzchar(match[4])) {eps <- c(eps,as.integer(match[4]));kind <- c(kind,"add")}
      } else {
        match <- regmatches(expression,regexec("^(.+)\\+EPS\\(([0-9]+)\\)$",expression,perl=TRUE))[[1]]
        if(length(match)) {prediction <- match[2];eps <- as.integer(match[3]);kind <- "add"}
      }
      if(is.null(prediction) || grepl("EPS\\(",prediction) || anyNA(eps) || any(eps<1L)) return(NULL)
      endpoints[[length(endpoints)+1L]] <- c(active,list(prediction=tolower(prediction),eps=eps,kind=kind))
    }
  }
  if(length(endpoints)<2L) return(NULL)
  variables <- vapply(endpoints,`[[`,"","variable");levels <- vapply(endpoints,`[[`,"","level")
  if(length(unique(variables))!=1L || anyDuplicated(levels)) return(NULL)
  sigma <- ctl_sigma_sd(ctl);indices <- unique(unlist(lapply(endpoints,`[[`,"eps")))
  if(any(indices>length(sigma))) stop("Residual terms refer beyond the declared SIGMA variances")
  lines <- unlist(lapply(seq_along(endpoints),function(i) {
    e <- endpoints[[i]];name <- paste0("obs",i)
    c(paste(name,"<-",tolower(e$prediction)),paste(name,"~",paste(paste0(e$kind,"(sd",e$eps,")"),collapse=" + ")))
  }))
  list(lines=lines,sds=setNames(sigma[indices],paste0("sd",indices)),selector=paste0(variables[1],"=",paste(levels,collapse=",")),named=named)
}

# Study run settings take precedence. Old input annotations remain readable, never generated.
pmx_run_setting <- function(ctl,name) {
  value <- Sys.getenv(name,"");if(nzchar(value)) return(value)
  text <- readLines(ctl,warn=FALSE)
  pattern <- paste0(";\\s*",name,"\\s*:")
  hit <- grep(pattern,text,ignore.case=TRUE,value=TRUE)
  if(length(hit)) return(trimws(sub(paste0("^.*",pattern,"\\s*"),"",hit[1],ignore.case=TRUE)))
  if(name=="PMX_DVID") {
    derived <- pmx_native_endpoints(ctl)
    if(!is.null(derived)) return(derived$selector)
  }
  ""
}

pmx_clean_ctl <- function(lines) {
  lines[!grepl("^\\s*;\\s*(?:PMX_(?:ENDPOINT|DVID|RESID_INIT)\\s*:|Skeleton\\s*:|PMX endpoints preserve)",lines,ignore.case=TRUE,perl=TRUE)]
}

ctl_endpoint_comment <- function(path) {
  raw <- pmx_run_setting(path,"PMX_ENDPOINT")
  if(!nzchar(raw)) return(character())
  values <- trimws(strsplit(raw,"[|]")[[1]]);values[nzchar(values)]
}
set_resid_init <- function(ui, sds) {
  if (!length(sds)) return(ui)
  a <- paste(sprintf("%s <- c(0, %s)", if(is.null(names(sds))) paste0("sd",seq_along(sds)) else names(sds), signif(sds, 6)), collapse = ", ")
  out <- tryCatch(eval(parse(text = paste0("ini(ui, ", a, ")"))), error = function(e) NULL)
  if (!is.null(out)) return(out)
  stop("Cannot set residual SD initials without changing their parameter meaning: ",a)
}

pmx_read_data <- function(path, ctl = NULL) {
  raw <- readLines(path,warn=FALSE)
  if(!length(raw)) stop("Empty dataset")
  if(!is.null(ctl)) {
    spec <- paste(ctl_body(ctl,"DATA"),collapse=" ")
    tag <- regmatches(spec,regexec("IGNORE\\s*=\\s*([^ (])",spec,ignore.case=TRUE))[[1]]
    if(length(tag)) raw <- c(raw[1],raw[-1][!startsWith(trimws(raw[-1]),tag[2])])
  }
  head <- raw[1]
  sep <- if(grepl("\t",head,fixed=TRUE)) "\t" else if(grepl(",",head,fixed=TRUE)) "," else if(grepl(";",head,fixed=TRUE)) ";" else ""
  d <- read.table(text=paste(raw,collapse="\n"),header=TRUE,sep=sep,quote="\"",comment.char="",na.strings=c(".","","NA"),check.names=FALSE,stringsAsFactors=FALSE)
  names(d) <- sub("^[@#]", "", names(d))
  if (anyDuplicated(tolower(names(d)))) stop("Duplicate input column names")
  if (!is.null(ctl)) {
    input <- trimws(paste(ctl_body(ctl, "INPUT"), collapse = " "))
    tok <- strsplit(input, "[[:space:],]+")[[1]]; tok <- tok[nzchar(tok)]
    if (length(tok) != ncol(d)) stop("$INPUT has ", length(tok), " fields but data has ", ncol(d), "; adapt the ctl to the original data")
    original_columns <- d
    for (i in seq_along(tok)) {
      nm <- sub("=.*$", "", tok[i])
      if (toupper(nm) %in% c("DROP", "SKIP") || grepl("=(DROP|SKIP)$", tok[i], ignore.case = TRUE)) next
      d[[tolower(nm)]] <- original_columns[[i]]
    }
  }
  for (nm in names(d)) if (!tolower(nm) %in% names(d)) d[[tolower(nm)]] <- d[[nm]]
  names(d) <- tolower(names(d))
  d <- d[,!duplicated(names(d),fromLast=TRUE),drop=FALSE]
  need <- c("id", "time", "dv")
  if (length(setdiff(need, names(d)))) stop("Missing data columns: ", paste(setdiff(need, names(d)), collapse = ", "))
  if (!"evid" %in% names(d)) {
    if (!"amt" %in% names(d) || any(d$amt > 0, na.rm = TRUE)) stop("Dose data require explicit EVID")
    d$evid <- 0L
  }
  if (!"amt" %in% names(d)) d$amt <- 0
  if (!"mdv" %in% names(d)) d$mdv <- as.integer(d$evid != 0 | is.na(d$dv))
  d$dv[d$evid != 0 | d$mdv != 0] <- NA_real_
  for (k in 1:9) if (!paste0("eps", k) %in% names(d)) d[[paste0("eps", k)]] <- 0
  if(!is.null(ctl)) d <- pmx_filter_data(d,ctl)
  original_dvid <- if("dvid" %in% names(d)) d$dvid else NULL
  if(!is.null(ctl)) {
    spec <- pmx_run_setting(ctl,"PMX_DVID")
    if(nzchar(spec)) {
      variable <- tolower(trimws(sub("=.*","",spec)))
      levels <- trimws(strsplit(sub("^[^=]*=","",spec),",")[[1]])
      if(!variable %in% names(d) || anyDuplicated(levels)) stop("Invalid PMX_DVID source/levels")
      mapped <- match(as.character(d[[variable]]),levels)
      mapped[d$evid!=0] <- 1L
      if(anyNA(mapped[d$evid==0 & d$mdv==0])) stop("Unmapped observation in PMX_DVID")
      d$dvid <- mapped
    }
  }
  if(!is.null(original_dvid)) d$nmdvid <- original_dvid
  else if("dvid" %in% names(d)) d$nmdvid <- d$dvid
  d
}

# A published control stream must not carry a character column as an estimated field:
# NONMEM/PsN read such a column as text and the run stops in $INPUT. Flag the data
# columns that are not numeric so the report stream can mark them =DROP.
pmx_data_numeric_flags <- function(path, ctl = NULL, max_rows = 20000L) {
  raw <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  if (!length(raw)) return(NULL)
  if (!is.null(ctl)) {
    spec <- paste(ctl_body(ctl, "DATA"), collapse = " ")
    tag <- regmatches(spec, regexec("IGNORE\\s*=\\s*([^ (])", spec, ignore.case = TRUE))[[1]]
    # IGNORE= also applies to a comment line that precedes the header.
    if (length(tag)) raw <- raw[!startsWith(trimws(raw), tag[2])]
    if (!length(raw)) return(NULL)
  }
  head <- raw[1]
  sep <- if (grepl("\t", head, fixed = TRUE)) "\t" else if (grepl(",", head, fixed = TRUE)) "," else if (grepl(";", head, fixed = TRUE)) ";" else ""
  keep <- if (length(raw) > max_rows + 1L) raw[seq_len(max_rows + 1L)] else raw
  d <- tryCatch(read.table(text = paste(keep, collapse = "\n"), header = TRUE, sep = sep,
                           quote = "\"", comment.char = "", na.strings = c(".", "", "NA"),
                           check.names = FALSE, stringsAsFactors = FALSE),
                error = function(e) NULL)
  if (is.null(d) || !ncol(d)) return(NULL)
  flags <- vapply(seq_along(d), function(i) {
    x <- d[[i]]
    if (all(is.na(x))) TRUE else is.numeric(x)   # an all-missing field stays numeric
  }, logical(1))
  stats::setNames(flags, sub("^[@#]", "", names(d)))
}

# Rewrite only the $INPUT block: a data column that is not numeric becomes NAME=DROP, so the
# frozen report stream reads it as a dropped field. Token count and layout are preserved, and
# a field that already carries =DROP/=SKIP/=FIX (or any =) is left untouched.
# data_ctl is the control-stream PATH whose $DATA supplies IGNORE=, exactly as pmx_read_data takes it.
pmx_input_drop_ctl <- function(ctl, path, label = "final_model.ctl", data_ctl = NULL) {
  flags <- pmx_data_numeric_flags(path, data_ctl)
  if (is.null(flags) || !length(flags) || !length(ctl)) return(ctl)
  txt <- sub(";.*$", "", ctl)
  hit <- grep("^\\s*\\$INPUT([^A-Za-z]|$)", txt, ignore.case = TRUE)
  if (!length(hit)) return(ctl)
  i <- hit[1]
  after <- grep("^\\s*\\$", txt)
  after <- after[after > i]
  j <- if (length(after)) after[1] - 1L else length(ctl)
  lines <- ctl; seen <- 0L; changed <- character(0)
  for (ln in i:j) {
    line <- lines[ln]; code <- line; comment <- ""
    sc <- regexpr(";", line, fixed = TRUE)
    if (sc > 0L) { code <- substr(line, 1L, sc - 1L); comment <- substr(line, sc, nchar(line)) }
    m <- gregexpr("[^[:space:]]+", code)[[1]]
    if (m[1] == -1L) next
    lens <- attr(m, "match.length")
    toks <- substring(code, m, m + lens - 1L)
    start <- if (ln == i && grepl("^\\$INPUT$", toks[1], ignore.case = TRUE)) 2L else 1L
    if (start > length(toks)) next
    for (t in seq.int(start, length(toks))) {
      seen <- seen + 1L
      if (seen > length(flags) || isTRUE(flags[[seen]])) next
      if (grepl("=", toks[t], fixed = TRUE)) next
      # A wrapped $INPUT line may close a name with a continuation slash: keep the
      # marker last so the token still reads NAME=DROP.
      if (grepl("/", toks[t], fixed = TRUE)) {
        sl <- regexpr("/", toks[t], fixed = TRUE)
        toks[t] <- paste0(substr(toks[t], 1L, sl - 1L), "=DROP", substr(toks[t], sl, nchar(toks[t])))
      } else {
        toks[t] <- paste0(toks[t], "=DROP")
      }
      changed <- c(changed, sub("^[@#]", "", toks[t]))
    }
    pieces <- character(0); pos <- 1L
    for (t in seq_along(toks)) {
      pieces <- c(pieces, substr(code, pos, m[t] - 1L), toks[t])
      pos <- m[t] + lens[t]
    }
    pieces <- c(pieces, substr(code, pos, nchar(code)))
    lines[ln] <- paste0(paste(pieces, collapse = ""), comment)
  }
  if (length(changed)) cat("CTL_INPUT_DROP ctl=", label, " data=", basename(path),
                           " columns=", paste(changed, collapse = ","), "\n", sep = "")
  lines
}

pmx_theta_names <- function(ctl) {
  b <- ctl_body(ctl, "THETA"); b <- b[nzchar(trimws(b))]
  if (!length(b)) stop("Missing $THETA")
  nm <- paste0("THETA", seq_along(b))
  pk <- ctl_body(ctl, "PK")
  for (l in pk) {
    m <- regmatches(l, regexec("^\\s*([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*THETA\\(\\s*([0-9]+)\\s*\\)", l, ignore.case = TRUE))[[1]]
    if (length(m) && as.integer(m[3]) <= length(nm)) nm[as.integer(m[3])] <- m[2]
  }
  txt <- readLines(ctl, warn = FALSE)
  for (l in txt) {
    m <- regmatches(l, regexec(";\\s*THETA\\(([0-9]+)\\)\\s+([A-Za-z][A-Za-z0-9_]*)", l, ignore.case = TRUE))[[1]]
    if (length(m) && as.integer(m[2]) <= length(nm)) nm[as.integer(m[2])] <- m[3]
  }
  if (anyDuplicated(tolower(nm))) stop("THETA labels must be unique")
  nm
}

pmx_eta_names <- function(ctl) {
  txt <- readLines(ctl,warn=FALSE)
  code <- sub(";.*$","",txt)
  matches <- unlist(regmatches(code,gregexpr("ETA\\(\\s*[0-9]+\\s*\\)",code,ignore.case=TRUE)))
  if(!length(matches)) return(character(0))
  n <- max(as.integer(gsub("[^0-9]","",matches))); nm <- paste0("ETA",seq_len(n))
  for(l in txt) {
    m <- regmatches(l,regexec(";\\s*ETA\\(([0-9]+)\\)\\s+([A-Za-z][A-Za-z0-9_]*)",l,ignore.case=TRUE))[[1]]
    if(length(m) && as.integer(m[2])<=n) nm[as.integer(m[2])] <- paste0("ETA_",m[3])
  }
  if(anyDuplicated(tolower(nm))) stop("ETA labels must be unique")
  nm
}

pmx_endpoint <- function(ctl) {
  lines <- ctl_endpoint_comment(ctl)
  if (!length(lines)) {
    raw <- Sys.getenv("PMX_ENDPOINT", "")
    if (nzchar(raw)) lines <- trimws(strsplit(raw, "[|]")[[1]])
  }
  er <- toupper(paste(ctl_body(ctl,"ERROR"),collapse=" "))
  multi <- grepl("(DVID|CMT)\\s*\\.EQ\\.",er) &&
    length(grep("^\\s*Y\\s*=",ctl_body(ctl,"ERROR")))>1L
  derived <- if(!length(lines)) pmx_native_endpoints(ctl) else NULL
  if(!length(lines) && is.null(derived)) {
    if(multi) stop("ENDPOINT_CONFIGURATION_REQUIRED: unsupported residual branches; configure the study run without adding control-stream comments")
    err_lines <- ctl_body(ctl,"ERROR")
    residual_line <- grep("^\\s*Y\\s*=",err_lines,value=TRUE,ignore.case=TRUE)
    if(length(residual_line)!=1L || !grepl("EPS",residual_line,ignore.case=TRUE))
      stop("ENDPOINT_CONFIGURATION_REQUIRED: configure this residual model in the study run")
    derived <- derive_endpoint(ctl)
    if(is.null(derived)) stop("ENDPOINT_CONFIGURATION_REQUIRED: residual model cannot be inferred safely")
  }
  if(!length(lines)) lines <- derived$lines
  if (!any(grepl("~", lines, fixed = TRUE)) || any(grepl("ini\\s*\\(", lines))) stop("Invalid PMX_ENDPOINT")
  sds <- if(is.null(derived)) ctl_sigma_sd(ctl) else derived$sds
  residual <- unique(unlist(regmatches(paste(lines,collapse=" "),gregexpr("\\bsd[A-Za-z0-9_]*\\b",paste(lines,collapse=" ")))))
  override <- pmx_run_setting(ctl,"PMX_RESID_INIT")
  if(nzchar(override)) {
    entries <- strsplit(override,",")[[1]]
    nm <- trimws(sub("=.*","",entries)); val <- suppressWarnings(as.numeric(sub("^[^=]*=","",entries)))
    if(anyNA(val) || any(val<=0) || anyDuplicated(nm) || !setequal(nm,residual)) stop("PMX_RESID_INIT must name every residual SD with a positive value")
    sds <- setNames(val,nm)[residual]
  } else {
    if(length(sds)!=length(residual)) stop("Residual initials cannot be mapped from SIGMA; provide PMX_RESID_INIT")
    names(sds) <- residual
  }
  list(lines=lines,sds=sds)
}

pmx_attach_endpoints <- function(ui, ep) {
  ui <- eval(parse(text = paste0("ui %>% model({", paste(ep$lines, collapse = "\n"), "}, append=TRUE)")))
  if(NROW(ui$predDf)>1L) {
    # Keep the NONMEM selector separate from the solver's remapped CMT.
    original <- ui$covariates[tolower(ui$covariates)=="cmt"]
    if(length(original)==1L)
      ui <- do.call(rxode2::rxRename, list(.data=ui,nmcmt=as.name(original)))
  }
  set_resid_init(ui,ep$sds)
}

pmx_build_ui <- function(ctl, effects) {
  pmx_check_indexed_eta(ctl)
  pmx_validate_ctl(ctl)
  edited <- nonmem_add_cov(pmx_expand_records(readLines(ctl, warn = FALSE)), effects)
  work <- "_scm_model.ctl"; writeLines(edited$lines, work)
  on.exit(unlink(work), add = TRUE)
  ep <- pmx_endpoint(work)
  m <- nonmem2rx::nonmem2rx(work, lst = ".res", save = FALSE, validate = FALSE,
                 thetaNames = pmx_theta_names(work),etaNames=pmx_eta_names(work))
  pmx_attach_endpoints(m,ep)
}


# Imported CMT labels select original NONMEM branches, not necessarily rxode2 endpoints.
pmx_endpoint_data <- function(ui, dat) {
  p <- ui$predDf
  if(is.null(p) || nrow(p)<2L) return(dat)
  bad <- function(s) stop("PMX_ENDPOINT_MAPPING: ",s,call.=FALSE)
  if(!all(c("dvid","cmt") %in% names(p))) bad("backend endpoint map unavailable")
  p <- unique(p[,c("dvid","cmt"),drop=FALSE])
  if(any(!is.finite(p$dvid) | p$dvid<1 | p$dvid!=floor(p$dvid)) ||
     any(!is.finite(p$cmt) | p$cmt<1 | p$cmt!=floor(p$cmt)) || anyDuplicated(p$dvid))
    bad("backend endpoints are ambiguous; do not guess their order")
  if(!all(c("dvid","cmt","evid","mdv","dv") %in% names(dat)))
    bad("multi-endpoint data require explicit event and observation coding")
  if(anyNA(dat$evid) || anyNA(dat$mdv)) bad("missing EVID/MDV")
  obs <- dat$evid==0 & dat$mdv==0 & !is.na(dat$dv)
  target <- match(dat$dvid,p$dvid)
  if(anyNA(target[obs])) bad("observed DVID has no residual endpoint")
  # nonmem2rx imports original CMT/DVID selectors as nmcmt/nmdvid.
  if("cmt" %in% tolower(ui$covariates)) bad("untranslated CMT selector; preserve its meaning explicitly")
  if(!"nmcmt" %in% names(dat)) dat$nmcmt <- dat$cmt
  if(!"nmdvid" %in% names(dat)) dat$nmdvid <- dat$dvid
  mapped <- dat$evid==0 & !is.na(target)
  dat$cmt[mapped] <- p$cmt[target[mapped]]
  dat # No event/dose row or source data file is changed.
}

pmx_endpoint_policy <- function(ctl) {
  if(sum(grepl("~",pmx_endpoint(ctl)$lines,fixed=TRUE))<2L) return(NULL)
  policy <- list(version="rx-endpoints-1",adapter=paste(deparse(body(pmx_endpoint_data)),collapse="\n"))
  if(any(grepl("\\bCMT\\b",ctl_body(ctl,"ERROR"),ignore.case=TRUE)))
    policy$cmt_normalization <- paste(deparse(body(pmx_attach_endpoints)),collapse="\n")
  policy
}

pmx_default_candidates <- function(ctl, dat, refs, configured = NULL) {
  pk <- ctl_body(ctl, "PK")
  assigned <- function(name) {
    lines <- pk[grepl(paste0("^\\s*",name,"\\s*="),pk,ignore.case=TRUE)]
    if(length(lines)!=1L) return(character())
    trimws(sub("^[^=]*=", "", lines))
  }
  central <- ctl_obs_cmt(ctl)
  scale <- if(is.finite(central)) assigned(paste0("S",central)) else character()
  volume <- if(length(scale) && grepl("^[A-Za-z][A-Za-z0-9_]*$",scale)) scale else {
    sr <- paste(ctl_body(ctl,"SUBROUTINES"),collapse=" ")
    if(grepl("ADVAN\\s*(4|12)\\b",sr,ignore.case=TRUE,perl=TRUE)) "V2" else
      if(grepl("ADVAN\\s*(3|11)\\b",sr,ignore.case=TRUE,perl=TRUE)) "V1" else
        if(grepl("ADVAN\\s*(1|2)\\b",sr,ignore.case=TRUE,perl=TRUE)) "V" else "VC"
  }
  volume_rhs <- assigned(volume)
  central_tv <- unlist(regmatches(volume_rhs,gregexpr("\\bTV[A-Za-z0-9_]*\\b",volume_rhs,perl=TRUE)))
  theta_tv <- unique(sub("^\\s*([A-Za-z0-9_]+).*","\\1",pk[grepl(
    "^\\s*TV[A-Za-z0-9_]*\\s*=\\s*THETA",pk,ignore.case=TRUE)]))
  # Canonical names are fallback aliases only when the structural role is unavailable.
  if(!length(central_tv)) central_tv <- theta_tv[toupper(theta_tv) %in% c("TVVC","TVV1","TVV")]
  params <- theta_tv[toupper(theta_tv) %in% toupper(c("TVCL",central_tv))]
  reserved <- c("id","time","dv","lndv","logdv","ln_dv","log_dv","amt","rate","evid","cmt","dvid","nmdvid","nmcmt","mdv","ii","addl","ss","occ",
    "study","studyid","studyn","usubjid","subjid","sid","date","datetime","tad","tfd","visit","visitnum",
    "blq","lloq","uloq","limit","cens","exclf","excl","drop","skip","dose","ady","doseid","dosenum")
  configured <- configured %||% list(); excluded <- attr(configured,"excluded")
  # Report intake selects variables from actual data; CSV owns their explicit effect definitions.
  review <- attr(configured,"review")
  # Resolve the declared param column against the model's actual $PK THETA symbols BEFORE the
  # reviewed-scope coverage check. A CSV that names derived quantities (CL/VC) instead of the
  # THETA symbols (TVCL/TVVC) would otherwise surface as "every reviewed pair is missing",
  # which hides the real mistake behind a full coverage failure.
  declared_params <- unique(unlist(lapply(configured,function(cd) names(cd$eff))))
  match_param <- function(p) {
    hit <- which(toupper(params)==toupper(trimws(p)))
    if(length(hit)) params[hit[1]] else NA_character_
  }
  if(length(declared_params)) {
    if(!length(params))
      stop("SCM_PARAMETER_SCOPE: cannot resolve the CL/central-volume THETA symbols from $PK; preserve the model and resolve the mapping",call.=FALSE)
    resolved <- vapply(declared_params,match_param,character(1))
    if(anyNA(resolved))
      stop("SCM_PARAMETER_SCOPE: covariates.csv param must be the exact CL/central-volume THETA symbol from $PK (",paste(params,collapse=", "),"); unsupported targets: ",paste(declared_params[is.na(resolved)],collapse=", "),". A derived parameter name such as CL or VC is not a THETA symbol",call.=FALSE)
    # Keep the exact $PK spelling so downstream builders never lose a pair to a case difference.
    for(i in seq_along(configured)) {
      nm <- names(configured[[i]]$eff)
      if(!length(nm)) next
      canon <- unname(vapply(nm,match_param,character(1)))
      if(anyDuplicated(canon))
        stop("SCM_COVARIATE_CONFIG_INVALID: duplicate parameter targets in candidate ",configured[[i]]$lab %||% i,call.=FALSE)
      names(configured[[i]]$eff) <- canon
    }
  }
  if(!is.null(review)) pmx_covariate_pair_coverage(configured,review,params)
  out <- list(); plan <- list()
  for (cd in configured) {
    keep <- list()
    for (p in names(cd$eff)) {
      if(!toupper(p) %in% toupper(params))
        stop("SCM_PARAMETER_SCOPE: use the exact CL/central-volume THETA names from $PK (",paste(params,collapse=", "),"); unsupported targets: ",p)
      for (e in cd$eff[[p]]) {
        cov <- tolower(trimws(e$cov))
        col <- match(cov, tolower(names(dat)))
        if(is.na(col)) stop("SCM_COVARIATE_MISSING: ",cov," is declared in covariates.csv but is not a column of the analysis dataset")
        x <- suppressWarnings(as.numeric(as.character(dat[[col]])))
        if(any(!is.finite(x))) stop("SCM_COVARIATE_POLICY_REQUIRED: ",cov," has missing/non-numeric values; declare coding/missingness in covariates.csv")
        if(length(unique(x))<2L) stop("SCM_COVARIATE_NOT_ESTIMABLE: ",cov," has no variation in the analysis dataset")
        # Do not double-apply an effect already present in the base control stream.
        individual <- sub("^TV","",p,ignore.case=TRUE)
        lines <- pk[grepl(paste0("^\\s*(",p,"|",individual,")\\s*="),pk,ignore.case=TRUE)]
        if(any(grepl(paste0("\\b",cov,"\\b"),lines,ignore.case=TRUE))) {
          plan[[length(plan)+1L]] <- data.frame(Parameter=p,Covariate=toupper(cov),Status="prespecified",Reason="Effect already present in base model")
          next
        }
        keep[[p]] <- c(keep[[p]],list(e))
        plan[[length(plan)+1L]] <- data.frame(Parameter=p,Covariate=toupper(cov),Status="configured",Reason="")
      }
    }
    if(length(keep)) out[[length(out)+1L]] <- list(lab=cd$lab,sl=cd$sl %||% cd$lab,eff=keep)
  }
  if(!is.null(excluded) && nrow(excluded)) for(i in seq_len(nrow(excluded)))
    plan[[length(plan)+1L]] <- data.frame(Parameter=excluded$param[i],Covariate=toupper(excluded$covariate[i]),
                                          Status="user_excluded",Reason=excluded$user_instruction[i])
  dir.create("table",showWarnings=FALSE)
  if(length(plan)) write.csv(unique(do.call(rbind,plan)),"table/_scm_candidate_plan.csv",row.names=FALSE,na="")
  if(anyDuplicated(vapply(out,function(cd) cd$lab,""))) stop("SCM_COVARIATE_CONFIG_INVALID: candidate labels must be unique")
  cat("SCM_COVERAGE candidates=",length(out),
      if(length(out)) "; pairs declared in covariates.csv; table/_scm_candidate_plan.csv\n"
      else "; no testable additional pairs; consult reviewed scope/prespecified effects, not a no-effect conclusion\n",sep="")
  out
}

pmx_ctl_number <- function(x,digits=12L) vapply(x,function(v) {
  if(!is.finite(v)) stop("Non-finite control-stream estimate")
  format(signif(v,digits),digits=digits,trim=TRUE,scientific=(v!=0 && (abs(v)<1e-4 || abs(v)>=1e6)))
},"")
pmx_frozen_ctl <- function(ctl, fit, effects=list(), digits=12L, partial=FALSE) {
  lines <- pmx_expand_records(readLines(ctl, warn = FALSE))
  if(length(effects)) lines <- nonmem_add_cov(lines,effects)$lines
  temp <- tempfile(fileext=".ctl", tmpdir=getwd()); writeLines(lines, temp)
  on.exit(unlink(temp), add=TRUE)
  nm <- pmx_theta_names(temp); fe <- fixef(fit)
  key <- tolower(sub("^t[.]", "", names(fe)))
  block <- ""; k <- 0L
  for (i in seq_along(lines)) {
    if (grepl("^\\s*\\$", lines[i])) block <- toupper(sub("^\\s*\\$([A-Za-z0-9]+).*$", "\\1", lines[i]))
    if (block != "THETA" || grepl("^\\s*;|^\\s*\\$", lines[i]) || !nzchar(trimws(sub(";.*", "", lines[i])))) next
    k <- k+1L; hit <- match(tolower(nm[k]), key)
    if (is.na(hit) || !is.finite(fe[hit])) {
      # partial = warm-start mode: an appended covariate effect has no fitted THETA yet.
      if (isTRUE(partial)) next else stop("Missing fitted THETA: ", nm[k])
    }
    s <- sub(";.*", "", lines[i]); comment <- if (grepl(";",lines[i])) sub("^[^;]*", "", lines[i]) else ""
    if (grepl("\\(",s)) {
      vals <- strsplit(sub(".*\\(([^)]*)\\).*", "\\1", s), ",")[[1]]
      if (length(vals)<2L) stop("Unsupported THETA tuple")
      v <- fe[hit]; start <- as.numeric(pmx_ctl_number(v,digits))
      lo <- suppressWarnings(as.numeric(vals[1])); hi <- if(length(vals)>2L) suppressWarnings(as.numeric(vals[3])) else Inf
      # Short initials must not round an interior estimate onto a bound.
      use_digits <- if((is.finite(lo) && v>lo && start<=lo) || (is.finite(hi) && v<hi && start>=hi)) 12L else digits
      vals[2] <- pmx_ctl_number(v,use_digits)
      s <- sub("\\([^)]*\\)", paste0("(",paste(trimws(vals),collapse=","),")"),s)
    } else s <- sub("[-+]?[0-9]*\\.?[0-9]+([eEdD][-+]?[0-9]+)?", pmx_ctl_number(fe[hit],digits),s)
    lines[i] <- paste(trimws(s),comment)
  }
  om <- as.matrix(fit$omega); row <- 0L; blocksize <- 0L; offset <- 0L
  omega_digits <- digits
  if(digits<12L && nrow(om)>0L &&
     !inherits(try(chol(om),silent=TRUE),"try-error") &&
     inherits(try(chol(signif(om,digits)),silent=TRUE),"try-error")) omega_digits <- 12L
  block <- ""; sig <- 0L
  ep <- pmx_endpoint(temp); sd_names <- unique(unlist(regmatches(paste(ep$lines,collapse=" "),gregexpr("sd[A-Za-z0-9_]*",paste(ep$lines,collapse=" ")))))
  native_residual <- pmx_native_endpoints(temp)
  if(!length(ctl_endpoint_comment(temp)) && !is.null(native_residual))
    sd_names <- paste0("sd",seq_along(ctl_sigma_sd(temp)))
  for (i in seq_along(lines)) {
    if (grepl("^\\s*\\$",lines[i])) {
      block <- toupper(sub("^\\s*\\$([A-Za-z0-9]+).*$","\\1",lines[i]))
      if (block=="OMEGA") {
        header <- trimws(sub(";.*$","",lines[i]))
        if (grepl("\\b(SAME|FIX)\\b",header,ignore.case=TRUE,perl=TRUE)) stop("Freeze requires explicit OMEGA records without SAME/header FIX")
        if (blocksize>0L) {
          if(row!=blocksize) stop("OMEGA BLOCK has an incomplete lower triangle")
          offset <- offset+blocksize
        }
        match_block <- regmatches(header,regexec("\\bBLOCK\\s*\\(\\s*([0-9]+)\\s*\\)",header,ignore.case=TRUE,perl=TRUE))[[1]]
        if(grepl("\\bBLOCK\\b",header,ignore.case=TRUE,perl=TRUE) && !length(match_block))
          stop("Invalid OMEGA BLOCK dimension: ",header)
        blocksize <- if(length(match_block)) as.integer(match_block[2]) else 0L
        if(blocksize>0L && offset+blocksize>nrow(om)) stop("Fitted OMEGA dimensions disagree with the control stream")
        row <- 0L
      }
      next
    }
    s <- trimws(sub(";.*","",lines[i])); if (!nzchar(s)) next
    if (block=="OMEGA") {
      vals <- strsplit(s,"[[:space:]]+")[[1]]; numeric_tokens <- suppressWarnings(as.numeric(vals)); pos <- which(is.finite(numeric_tokens))
      if (blocksize>0L) {
        row <- row+1L
        if(length(pos)!=row) stop("OMEGA BLOCK requires one lower-triangle row per line")
        v <- om[offset+row, offset+seq_len(row)]
      } else { if(length(pos)!=1L) stop("Diagonal OMEGA requires one value per line"); offset <- offset+1L; v <- om[offset,offset] }
      vals[pos] <- pmx_ctl_number(v,omega_digits)
      lines[i] <- paste(paste(vals,collapse=" "),if(grepl(";",lines[i]))sub("^[^;]*","",lines[i])else "")
    } else if (block=="SIGMA") {
      if(grepl("BLOCK|SAME",s,ignore.case=TRUE)) stop("Residual covariance needs an explicit export hook")
      sig <- sig+1L
      if(sig>length(sd_names)) stop("SIGMA and endpoint residual parameters disagree")
      hit <- match(tolower(sd_names[sig]),key)
      if(is.na(hit)) stop("Missing fitted residual parameter ",sd_names[sig])
      lines[i] <- sub("[-+]?[0-9]*\\.?[0-9]+([eEdD][-+]?[0-9]+)?",pmx_ctl_number(fe[hit]^2,digits),lines[i])
    }
  }
  if(blocksize>0L && row!=blocksize) stop("OMEGA BLOCK has an incomplete lower triangle")
  pmx_clean_ctl(lines)
}

# Warm-start control stream: authored records and bounds, initials taken from a completed fit.
pmx_warm_ctl <- function(ctl, fit, effects=list(), dir=getwd(), digits=12L) {
  text <- pmx_frozen_ctl(ctl, fit, effects, digits=digits, partial=TRUE)
  path <- file.path(dir, "_scm_warm.ctl")
  writeLines(text, path)
  path
}

pmx_validate_input_roles <- function(ctl,data) {
  header <- readLines(data,n=1L,warn=FALSE)
  sep <- if(grepl("\t",header,fixed=TRUE)) "\t" else if(grepl(",",header,fixed=TRUE)) "," else if(grepl(";",header,fixed=TRUE)) ";" else ""
  columns <- names(read.table(text=header,header=TRUE,sep=sep,quote="\"",comment.char="",check.names=FALSE,nrows=0L))
  columns <- sub("^[@#]","",columns)
  tokens <- unlist(strsplit(trimws(paste(ctl_body(ctl,"INPUT"),collapse=" ")),"[[:space:],]+"))
  tokens <- tokens[nzchar(tokens)]
  if(length(tokens)!=length(columns)) stop("INPUT_ROLE_MISMATCH: $INPUT has ",length(tokens)," fields but data has ",length(columns))
  active <- toupper(tokens[!grepl("^(DROP|SKIP)$|=(DROP|SKIP)$",tokens,ignore.case=TRUE)])
  roles <- sub("=.*$","",active)
  if(any(vapply(c("ID","TIME","DV"),function(x)sum(roles==x)!=1L,TRUE)))
    stop("INPUT_ROLE_MISMATCH: exactly one active ID, TIME and DV mapping is required")
  reserved <- c("ID","TIME","DV","AMT","EVID","CMT","DVID","MDV","RATE","II","ADDL","SS","OCC")
  for(i in seq_along(tokens)) {
    parts <- strsplit(toupper(tokens[i]),"=",fixed=TRUE)[[1]];target <- parts[1]
    if(!target %in% reserved || any(parts %in% c("DROP","SKIP"))) next
    explicit <- length(parts)==2L && identical(parts[2],toupper(columns[i]))
    if(toupper(columns[i])!=target && !explicit)
      stop("INPUT_ROLE_MISMATCH: position ",i," maps ",target," to original column ",columns[i],
           "; preserve the original role, or declare the intended alias explicitly (",target,"=",columns[i],") with a matching endpoint scale")
  }
  invisible(TRUE)
}

pmx_configure_model <- function(model, ctl, data) {
  pmx_validate_input_roles(ctl,data)
  pmx_validate_ctl(ctl)
  est <- toupper(paste(ctl_body(ctl,"ESTIMATION"),collapse=" "))
  if(grepl("SAEM|BAYES|METHOD\\s*=\\s*(0|2)",est)) stop("Selected ctl estimator is not FOCEI; use a compatible NONMEM/PsN backend")
  model$model_ctl <- ctl; model$data_csv <- data
  model$read_data <- function(path) {
    d <- pmx_read_data(path, ctl)
    if (!"dvid" %in% names(d)) {
      spec <- pmx_run_setting(ctl,"PMX_DVID")
      if(nzchar(spec)) {
        var <- tolower(trimws(sub("=.*","",spec)))
        levels <- suppressWarnings(as.numeric(strsplit(sub("^[^=]*=","",spec),",")[[1]]))
        if(!var %in% names(d) || anyNA(levels)) stop("Invalid PMX_DVID mapping")
        d$dvid <- match(d[[var]],levels); d$dvid[d$evid!=0] <- 1L
        if(anyNA(d$dvid[d$mdv==0])) stop("Unmapped observation endpoint")
      } else {
        ep <- pmx_endpoint(ctl)
        if(sum(grepl("~",ep$lines,fixed=TRUE))>1L) stop("Multi-endpoint data require an unambiguous observation selector in the model or study run settings")
        d$dvid <- 1L
      }
    }
    if(!"cmt" %in% names(d)) {
      if(any(d$evid!=0)) stop("Dose records require explicit CMT")
      d$cmt <- ctl_obs_cmt(ctl)
    }
    d
  }
  # ctl_start begins a candidate at the current model's fitted estimates instead of the
  # authored .ctl initials; the authored control stream still defines every record and bound.
  model$build <- function(effects, ctl_start = NULL)
    pmx_build_ui(if (is.null(ctl_start)) ctl else ctl_start, effects)
  model$typical <- pmx_theta_names(ctl)
  model$labels <- setNames(model$typical,model$typical)
  ep <- pmx_endpoint(ctl)
  residual_names <- unique(unlist(regmatches(paste(ep$lines,collapse=" "),gregexpr("sd[A-Za-z0-9_]*",paste(ep$lines,collapse=" ")))))
  model$residual <- setNames(rep("Residual error standard deviation",length(residual_names)),residual_names)
  model$candidates <- function(ref,configured=NULL) pmx_default_candidates(ctl,model$read_data(data),ref,configured)
  model$ctl_out <- function(final,chosen,refs,added) pmx_frozen_ctl(ctl,final,added)
  model
}
