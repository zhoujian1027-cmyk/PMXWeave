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

A <- commandArgs(trailingOnly = TRUE)
FAM <- "ppk"
if ("--family" %in% A) { i <- which(A == "--family"); FAM <- A[i + 1]; A <- A[-c(i, i + 1)] }
pmx_start(A[1], "s2")   # 02_html/ (or the flat folder when PMX_LAYOUT=flat)
FAM <- sub("_data\\.csv$", "", FAM)

stage_require("s2", c("s1","s1c"))                 # gate + hash check of every S1 output
cat("=== S2 freeze:", FAM, "in", getwd(), "===\n")
stage_invalidate(c("s2", "s3", "s4", "s5"))

res_p <- "_scm_final_result.rds"
if (!file.exists(res_p)) stop("S2: ", res_p, " is missing - complete S1/S1C", call. = FALSE)
res <- readRDS(res_p)
source(file.path(.here,"..","..","analyses_template","tools","screen_fit_identity.R"))
pmx_require_fit_quality(res$base,"S2 base")
pmx_require_fit_quality(res$final,"S2 final")

out_final <- file.path(stage_dir("s2"), "final.rds")
ctl_p <- abs_root("final_model.ctl")
if(!file.exists(ctl_p) || is.null(res$ctl) || !identical(readLines(ctl_p,warn=FALSE),res$initial_ctl %||% res$ctl))
  stop("S2: final initial stream differs from the source-bound result")
ctl_fitted <- file.path(stage_dir("s2"),"final_fitted.ctl")
writeLines(res$ctl,ctl_fitted)
saveRDS(list(family = FAM,
             frozen_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             search = res,
             ctl = res$ctl),
        out_final)

sum_p <- "table/_scm_summary.csv"
if (!file.exists(sum_p)) stop("S2: ", sum_p, " is missing - complete S1/S1C", call. = FALSE)
out_sel <- file.path(stage_dir("s2"), "selection.csv")
writeLines(readLines(sum_p, warn = FALSE), out_sel)

if (!requireNamespace("nlmixr2save", quietly = TRUE))
  stop("S2: nlmixr2save is required to publish the fit archive the report reads", call. = FALSE)
publish <- function(obj, nm, what) {
  if (is.null(obj)) stop("S2: missing ",what," fitted object; complete S1/S1C")
  p <- abs_root(gpath("html", paste0(FAM, "_", nm)))
  unlink(paste0(p, ".zip"))
  ok <- tryCatch({ nlmixr2save::saveFit(obj, p); TRUE },
                 error = function(e) stop("S2 archive ",nm," failed: ",conditionMessage(e),call.=FALSE))
  if (ok) cat("S2_ARCHIVE", rel_root(paste0(p, ".zip")), "\n", sep = "")
  invisible(NULL)
}
cpp_translate <- function(ctl,fam,kind=c("sim","ebe"),fit,effects) {
  kind <- match.arg(kind); sim_mode <- kind=="sim"
  blocks <- list(); current <- NULL
  for(l in ctl) {
    if(grepl("^\\s*\\$",l)) {
      current <- toupper(sub("^\\s*\\$([A-Za-z0-9]+).*$","\\1",l))
      l <- sub("^\\s*\\$[A-Za-z0-9]+","",l)
    }
    if(!is.null(current)) blocks[[current]] <- c(blocks[[current]],l)
  }
  code <- function(x) { x <- trimws(sub(";.*$","",x)); x[nzchar(x)] }
  all_code <- unlist(lapply(blocks[c("PK","DES","ERROR")],code))
  if(nzchar(Sys.getenv("PMX_ENDPOINT","")) || any(grepl(";\\s*PMX_ENDPOINT:",ctl,ignore.case=TRUE)))
    stop("A custom residual contract requires an authored paired simulator")
  if(any(grepl("^CALL\\b|^D[0-9]+\\s*=",all_code,ignore.case=TRUE)) || !length(code(blocks$DES)) ||
     any(grepl("^IF\\b|^ELSE|^ENDIF",code(c(blocks$PK,blocks$DES)),ignore.case=TRUE)))
    stop("Structural branches, model-defined duration or analytic ADVAN need an authored paired simulator")
  contract <- local({
    p <- tempfile(fileext=".ctl"); writeLines(ctl,p); on.exit(unlink(p))
    source(file.path(.here,"..","..","analyses_template","tools","model_contract.R"),local=TRUE)
    list(theta=pmx_theta_names(p),endpoints=pmx_native_endpoints(p))
  })
  theta_names <- contract$theta
  theta_rows <- code(blocks$THETA)
  theta_values <- vapply(theta_rows,function(l) {
    z <- suppressWarnings(as.numeric(regmatches(l,gregexpr("[-+]?[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?",l))[[1]]))
    z <- z[is.finite(z)]; if(length(z)==1L) z[1] else z[2]
  },0)
  omega <- as.matrix(fit$omega); neta <- nrow(omega)
  if(is.null(neta)) neta <- 0L
  cmts <- regmatches(paste(ctl,collapse=" "),gregexpr("COMP\\s*=\\s*\\(\\s*[A-Za-z_][A-Za-z0-9_]*",paste(ctl,collapse=" ")))[[1]]
  cmts <- sub(".*\\(\\s*","",cmts)
  if(!length(cmts) || length(theta_names)!=length(theta_values)) stop("Missing explicit compartment/parameter mapping")
  cov_defaults <- numeric()
  for(group in effects) for(e in group) {
    value <- e$ref %||% e$level
    if(is.null(value) || !is.finite(value)) stop("Covariate requires an explicit reference: ",e$cov)
    cov_defaults[toupper(e$cov)] <- value
  }
  number <- function(v) {
    s <- format(v,digits=15,scientific=FALSE,trim=TRUE)
    if(!grepl("[.eE]",s)) paste0(s,".0") else s
  }
  aliases <- list()
  cpp <- function(x) {
    if(is.numeric(x)) return(number(x))
    if(is.symbol(x)) {
      n <- as.character(x)
      if(toupper(n) %in% names(cov_defaults)) n <- toupper(n)
      if(n %in% names(aliases)) n <- aliases[[n]]
      return(n)
    }
    if(!is.call(x)) stop("Unsupported expression node")
    op <- as.character(x[[1]]); args <- as.list(x)[-1]
    if(op=="(") return(paste0("(",cpp(args[[1]]),")"))
    if(op %in% c("=","<-")) return(paste(cpp(args[[1]]),"=",cpp(args[[2]])))
    if(op=="^") return(paste0("pow(",cpp(args[[1]]),",",cpp(args[[2]]),")"))
    if(op %in% c("+","-","*","/","==","!=","<",">","<=",">=")) {
      if(length(args)==1L) return(paste0("(",op,cpp(args[[1]]),")"))
      return(paste0("(",cpp(args[[1]])," ",op," ",cpp(args[[2]]),")"))
    }
    if(op %in% c("ETA","EPS")) return(paste0(op,"(",as.integer(args[[1]]),")"))
    if(op=="IFELSE") return(paste0("(",cpp(args[[1]])," ? ",cpp(args[[2]])," : ",cpp(args[[3]]),")"))
    functions <- c(EXP="exp",LOG="log",LN="log",SQRT="sqrt",ABS="fabs",LOG10="log10",MIN="fmin",MAX="fmax",SIN="sin",COS="cos",TAN="tan")
    fn <- unname(functions[toupper(op)])
    if(is.na(fn)) stop("Unsupported function: ",op)
    paste0(fn,"(",paste(vapply(args,cpp,""),collapse=","),")")
  }
  subst <- function(l) {
    for(k in rev(seq_along(theta_names))) l <- gsub(paste0("THETA\\(\\s*",k,"\\s*\\)"),theta_names[k],l)
    for(k in rev(seq_along(cmts))) {
      l <- gsub(paste0("DADT\\(\\s*",k,"\\s*\\)"),paste0("dxdt_",cmts[k]),l)
      l <- gsub(paste0("\\bA\\(\\s*",k,"\\s*\\)"),cmts[k],l)
    }
    l <- gsub("([0-9])[dD]([-+]?[0-9]+)","\\1e\\2",l)
    operators <- c(EQ="==",NE="!=",LT="<",GT=">",LE="<=",GE=">=")
    for(name in names(operators)) {
      l <- gsub(paste0("\\.",name,"\\."),operators[[name]],l,ignore.case=TRUE)
    }
    expr <- parse(text=l)
    if(length(expr)!=1L) stop("One assignment per line required")
    text <- cpp(expr[[1]])
    if(is.call(expr[[1]]) && as.character(expr[[1]][[1]]) %in% c("=","<-")) {
      lhs <- as.character(expr[[1]][[2]])
      rhs <- trimws(sub("^[^=]*=","",text))
      dose_flag <- grepl("^(F|ALAG)[0-9]+$",lhs)
      if((lhs %in% theta_names || dose_flag) && !identical(lhs,rhs) && !lhs %in% names(aliases)) {
        alias <- if(dose_flag) paste0("PMX_",lhs) else paste0(lhs,"_SCM")
        aliases[[lhs]] <<- alias
        text <- sub("^[^=]*=",paste0(alias," ="),text)
      }
    }
    text
  }
  pk <- vapply(code(blocks$PK),function(line) {
    initial <- regmatches(line,regexec("^A_0\\s*\\(\\s*([0-9]+)\\s*\\)\\s*=\\s*(.+)$",line))[[1]]
    if(!length(initial)) return(subst(line))
    index <- as.integer(initial[2])
    if(index<1L || index>length(cmts)) stop("Invalid initial-condition compartment")
    paste0(cmts[index],"_0 = ",subst(initial[3]))
  },"")
  pk <- pk[!vapply(pk,function(l) identical(trimws(sub("=.*$","",l)),trimws(sub("^[^=]*=","",l))),TRUE)]
  declared <- character()
  declarations <- vapply(pk,function(line) {
    lhs <- trimws(sub("=.*$","",line))
    declare <- !lhs %in% c(declared,paste0(cmts,"_0"))
    declared <<- unique(c(declared,lhs))
    paste0(if(declare) "double " else "",line,";")
  },"")
  flags <- character()
  flag_source <- code(blocks$PK)
  flag_source <- flag_source[grepl("^\\s*(F|ALAG)[0-9]+\\s*=",flag_source)]
  for(l in flag_source) {
    lhs <- trimws(sub("=.*$","",l)); rhs <- aliases[[lhs]] %||% lhs
    if(grepl("^(F|ALAG)[0-9]+$",lhs)) {
      index <- as.integer(gsub("[^0-9]","",lhs))
      if(index<1L || index>length(cmts)) stop("Invalid dose flag compartment")
      flag <- if(startsWith(lhs,"ALAG")) "ALAG" else "F"
      flags <- c(flags,paste0(flag,"_",cmts[index]," = ",rhs,";"))
    }
  }
  # DES scalar intermediates need declarations; derivative macros and existing PK variables do not.
  known <- unique(c(theta_names,names(cov_defaults),cmts,trimws(sub("=.*$","",pk))))
  derivatives <- paste0("dxdt_",cmts)
  ode <- vapply(code(blocks$DES),function(line) {
    text <- subst(line);lhs <- trimws(sub("=.*$","",text))
    if(!grepl("^[A-Za-z_][A-Za-z0-9_]*$",lhs)) stop("Unsupported DES assignment target: ",lhs)
    declare <- !lhs %in% c(known,derivatives)
    known <<- unique(c(known,lhs))
    if(declare) declared <<- c(declared,lhs)
    paste0(if(declare) "double " else "",text,";")
  },"")
  error <- code(blocks$ERROR)
  endpoint <- contract$endpoints; responses <- character()
  secondary <- if(fam=="tmdd") "IPRED_TARGET" else "IPRED_PD"
  if(!is.null(endpoint$tmdd)) {
    error <- endpoint$tmdd$preamble
    prediction <- endpoint$tmdd$prediction
  } else if(!is.null(endpoint$named)) {
    error <- endpoint$named$preamble
    prediction <- vapply(endpoint$named$endpoints,function(e) e$prediction,"")
  } else if(!is.null(endpoint)) {
    if(!fam %in% c("pkpd","tmdd") || sum(grepl("<-",endpoint$lines,fixed=TRUE))!=2L)
      stop("Family requires an explicit supported two-endpoint observation contract")
    # Reuse the estimator's flat endpoint parser; only the Y selector is removed.
    outside <- character();active <- FALSE
    for(line in error) {
      if(grepl("^(ELSE)?IF\\s*\\((CMT|DVID)\\s*\\.EQ\\.\\s*[0-9]+\\s*\\)\\s*THEN$",line,ignore.case=TRUE)) {
        active <- TRUE;next
      }
      if(toupper(line)=="ENDIF") {if(!active) stop("Unmatched residual ENDIF");active <- FALSE;next}
      if(active) {
        if(!grepl("^Y\\s*=",line)) stop("Only flat endpoint Y assignments are supported")
        responses <- c(responses,trimws(sub("^Y\\s*=","",line)))
      } else outside <- c(outside,line)
    }
    if(active || length(responses)!=2L || any(grepl("^Y\\s*=",outside))) stop("Ambiguous endpoint branches")
    prediction <- toupper(trimws(sub("^.*<-","",endpoint$lines[grepl("<-",endpoint$lines,fixed=TRUE)])))
    error <- outside
  }
  if(!sim_mode) error <- error[!grepl("EPS\\s*\\(",error)]
  local_names <- character();table <- character()
  table_assignment <- function(text) {
    lhs <- trimws(sub("=.*$","",text))
    define <- !lhs %in% c(declared,local_names)
    local_names <<- unique(c(local_names,lhs))
    paste0(if(define) "double " else "",text,";")
  }
  for(line in error) {
    guard <- regmatches(line,regexec("^IF\\s*\\((.+)\\)\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.+)$",line,ignore.case=TRUE))[[1]]
    if(length(guard)) {
      if(!guard[3] %in% local_names || grepl("EPS\\s*\\(",line)) stop("Guard must update an existing deterministic prediction variable")
      table <- c(table,paste0("if (",subst(guard[2]),") ",guard[3]," = ",subst(guard[4]),";"));next
    }
    text <- subst(line);lhs <- trimws(sub("=.*$","",text))
    if(!grepl("^[A-Za-z_][A-Za-z0-9_]*$",lhs)) stop("Unsupported ERROR assignment target: ",lhs)
    table <- c(table,table_assignment(text))
  }
  if(!is.null(endpoint)) {
    table <- c(table,table_assignment(paste("IPRED =",subst(prediction[1]))),
                     table_assignment(paste(secondary,"=",subst(prediction[2]))))
    captures <- c("IPRED",secondary)
    if(sim_mode) {
      observed <- if(fam=="pkpd") c("DV_PK","DV_PD") else c("DV_L","DV_R")
      if(!is.null(endpoint$tmdd)) {
        central <- as.integer(sub("^CMT=([0-9]+),.*$","\\1",endpoint$tmdd$selector))
        responses <- c(paste0("IPRED + (",cmts[central]," > 0.0 ? EPS(1) : 0.0)"),if(endpoint$tmdd$guard_target) "IPRED_TARGET + (RTOT > 0.0 ? EPS(2) : 0.0)" else "IPRED_TARGET + EPS(2)")
      } else if(!is.null(endpoint$named)) {
        responses <- vapply(seq_along(captures),function(i) {
          e <- endpoint$named$endpoints[[i]]
          value <- captures[i]
          terms <- paste0(ifelse(e$kind=="prop",paste0(value," * "),""),"EPS(",e$eps,")")
          noise <- paste(terms,collapse=" + ")
          if(nzchar(e$test)) noise <- paste0("(",e$test," > 0.0 ? ",noise," : 0.0)")
          paste(value,"+",noise)
        },"")
      } else responses <- vapply(responses,subst,"")
      table <- c(table,vapply(paste(observed,"=",responses),table_assignment,""))
      captures <- c(captures,observed)
    }
  } else {
    if(!"IPRED" %in% local_names) {
      if(!"F" %in% local_names) stop("ERROR must explicitly define F/IPRED")
      table <- c(table,table_assignment("IPRED = F"))
    }
    captures <- "IPRED"
    if(sim_mode) {
      if(!"Y" %in% local_names || !any(grepl("EPS\\(",error))) stop("VPC requires an explicit SIGMA/EPS/Y contract")
      table <- c(table,table_assignment("PRED = IPRED"),table_assignment("DV = Y"));captures <- c(captures,"PRED","DV")
    }
  }
  sigma <- code(blocks$SIGMA)
  if(sim_mode && any(grepl("BLOCK|SAME|FIX",sigma,ignore.case=TRUE))) stop("VPC requires diagonal SIGMA")
  omega_lines <- if(neta) c("$OMEGA @block",vapply(seq_len(neta),function(i) paste(format(omega[i,seq_len(i)],digits=12,trim=TRUE),collapse=" "),"")) else NULL
  out <- c(paste("$PROB",toupper(fam),kind,"(mrgsolve translation of the frozen control stream by stage 2)"),
    paste("$PARAM",paste(paste0(theta_names," = ",format(theta_values,digits=12,trim=TRUE)),collapse=", ")),
    if(length(cov_defaults)) paste("$PARAM",paste(paste0(names(cov_defaults)," = ",cov_defaults),collapse=", ")),
    paste("$CMT",paste(cmts,collapse=" ")),omega_lines,if(sim_mode) c("$SIGMA",sigma),
    "$MAIN",declarations,flags,"$ODE",ode,
    "$TABLE",table,paste("$CAPTURE",paste(if(sim_mode) captures else "IPRED",collapse=" ")))
  paste(out,collapse="\n")
}
sim_contract <- file.path(Sys.getenv("PMX_TOOLKIT", ""), "analyses_template","tools", "simulator_contract.R")
if (!file.exists(sim_contract)) sim_contract <- file.path(.here, "..", "..", "analyses_template","tools", "simulator_contract.R")
if (!file.exists(sim_contract)) stop("S2_SIMULATOR_CONTRACT_MISSING: analyses_template/tools/simulator_contract.R not found; set PMX_TOOLKIT", call. = FALSE)
source(sim_contract)
provenance_p <- file.path(stage_dir("s2"),"simulators.dcf")
previous_sources <- if(file.exists(provenance_p)) as.data.frame(read.dcf(provenance_p),stringsAsFactors=FALSE) else NULL
if(!is.null(previous_sources) && (!all(c("File","Origin","MD5","SourceMD5") %in% names(previous_sources)) || anyDuplicated(previous_sources$File)))
  stop("S2_SIMULATOR_PROVENANCE_INVALID: inspect simulators.dcf; do not infer ownership from a header")
source_records <- list()
cpp_needed <- character()
for (tw in list(list(file = "final_model.cpp",   kind = "sim", what = "mrgsolve translation of the final model"),
                list(file = paste0(FAM, "_ebe.cpp"), kind = "ebe", what = "EBE exposure simulator"))) {
  dst <- if(tw$kind=="sim") abs_root(tw$file) else abs_root(gpath("html",tw$file))
  ctl_now <- res$ctl
  if (is.null(ctl_now) && file.exists(ctl_p)) ctl_now <- readLines(ctl_p, warn = FALSE)
  src <- tryCatch(cpp_translate(ctl_now,FAM,tw$kind,res$final,res$added),error=function(e)e)
  prior_record <- if(is.null(previous_sources)) NULL else previous_sources[previous_sources$File==rel_root(dst),,drop=FALSE]
  if(!is.null(prior_record) && !nrow(prior_record)) prior_record <- NULL
  decision <- pmx_simulator_action(dst,if(inherits(src,"error")) NULL else src,prior_record)
  if(decision$action=="preserve") {
    cat("S2_CPP_PRESERVED ",rel_root(dst)," origin=",decision$origin,"; compile/capture and S4 prediction validation still required\n",sep="")
    source_records[[length(source_records)+1L]] <- data.frame(File=rel_root(dst),Origin=decision$origin,
      MD5=decision$md5,SourceMD5=unname(tools::md5sum(ctl_fitted)))
    next
  }
  if(decision$action=="author") {
    cpp_needed <- c(cpp_needed,rel_root(dst))
    prior <- if(file.exists(dst)) unname(tools::md5sum(dst)) else "missing"
    cat("S2_SIMULATOR_REQUIRED file=",rel_root(dst)," prior_md5=",prior," source=",rel_root(ctl_fitted),
        " source_md5=",unname(tools::md5sum(ctl_fitted)),"\n",sep="")
    cat("S2_TRANSLATION_REASON ",rel_root(dst),": ",
        if(inherits(src,"error")) conditionMessage(src) else "unsupported translation","\n",sep="")
    next
  }
  if (file.exists(dst) && identical(paste(readLines(dst, warn = FALSE), collapse = "\n"), src)) {
    cat("S2_CPP_KEPT ", rel_root(dst), " (unchanged)\n", sep = "")
    source_records[[length(source_records)+1L]] <- data.frame(File=rel_root(dst),Origin="generated",
      MD5=unname(tools::md5sum(dst)),SourceMD5=unname(tools::md5sum(ctl_fitted)))
    next
  }
  writeLines(src, dst)
  cat("S2_CPP ", rel_root(dst), "\n", sep = "")
  source_records[[length(source_records)+1L]] <- data.frame(File=rel_root(dst),Origin="generated",
    MD5=unname(tools::md5sum(dst)),SourceMD5=unname(tools::md5sum(ctl_fitted)))
}

## A translation that exists is not a translation that works. Compile it and check the
## family capture contract here, so an uncompilable or incomplete-authored simulator fails at
## freeze time with the compiler message instead of crashing the stage-4 knit much later.
sim_bad <- character()
for (tw in list(list(file = "final_model.cpp", fam = FAM, kind = "sim"),
                list(file = paste0(FAM, "_ebe.cpp"), fam = FAM, kind = "ebe"))) {
  dst <- if (identical(tw$file, "final_model.cpp")) abs_root(tw$file) else abs_root(gpath("html", tw$file))
  if (!file.exists(dst)) next
  chk <- pmx_check_simulator(dst, tw$fam, compile = TRUE, kind = tw$kind)
  if (isTRUE(chk$ok)) { cat("S2_SIMULATOR_OK ", rel_root(dst), "\n", sep = ""); next }
  cat("S2_SIMULATOR_INVALID file=", rel_root(dst), " reason=", chk$error, "\n", sep = "")
  sim_bad <- c(sim_bad, rel_root(dst))
}
if (length(sim_bad)) stop("S2_SIMULATOR_INVALID: ", paste(unique(sim_bad), collapse = ", "),
  "; the paired simulator must compile and capture ", paste(pmx_sim_contract(FAM), collapse = "/"),
  ". mrgsolve_template/ files are model skeletons: add the required captures (and declare every",
  " data item the $TABLE reads, e.g. $INPUT DVID), keep the fitted parameters, or delete the file",
  " so stage 2 translates the control stream itself; then resume --from=s2.",
  call. = FALSE)
required_cpp <- c(abs_root("final_model.cpp"),abs_root(gpath("html",paste0(FAM,"_ebe.cpp"))))
cpp_needed <- unique(c(cpp_needed,rel_root(required_cpp[!file.exists(required_cpp)])))
if(length(cpp_needed)) stop("S2_MODEL_CONTRACT_UNSUPPORTED: author only ",paste(cpp_needed,collapse=", "),
  "; source ",rel_root(ctl_fitted),"; preserve SCM/covariance; resume --from=s2. Do not refit.",call.=FALSE)
write.dcf(do.call(rbind,source_records),provenance_p)
publish(res$base,"estimates","base")
publish(res$final,"scm_final","final")
cat("frozen: ", out_final, "\n         ", out_sel, "\n", sep = "")
stage_close("s2", inputs = stage_inputs("s2", FAM),
            outputs = stage_outputs("s2", FAM),
            note = "the only source S3-S5 may read for fitted quantities")
