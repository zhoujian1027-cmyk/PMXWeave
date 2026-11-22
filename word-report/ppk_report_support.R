# Reporting only: consume frozen fits; never estimate parameters or covariance.
pmx_fit_format <- function(x,digits=3) vapply(x,function(v) if(!is.finite(v)) "" else
  format(signif(v,digits),trim=TRUE,scientific=abs(v)>0 && abs(v)<1e-4),"")
pmx_fit_percent_female <- function(x,female_code=NULL,male_code=NULL) {
  metadata <- pmx_fit_metadata()
  if(length(metadata$levels$SEX) || (is.null(female_code) && is.null(male_code))) {
    x <- pmx_fit_level_display("SEX",x,metadata);female_code <- male_code <- NULL
  }
  x <- tolower(trimws(as.character(x)));x <- x[!is.na(x) & nzchar(x)]
  female <- unique(tolower(c(as.character(female_code),"f","female")))
  male <- unique(tolower(c(as.character(male_code),"m","male")))
  if(!length(x) || any(!x %in% c(female,male))) return(NA_real_)
  round(100*mean(x %in% female),1)
}
pmx_fit_scm_display <- function(rec) {
  if(is.null(rec) || !nrow(rec)) return(rec)
  for(n in intersect(c("Model","Estimate","covar","var"),names(rec))) rec[[n]] <- pmx_fit_term_labels(rec[[n]])
  if("Decision" %in% names(rec)) rec$Decision[!is.na(rec$Decision) &
    tolower(rec$Decision) %in% c("fit failed","failed","fail")] <- "fail"
  rec[,intersect(c("Step","Model","BIC","Estimate","Decision","step","searchType",
    "covar","var","objf","deltObjf","AIC","qchisqr","pchisqr","included"),names(rec)),drop=FALSE]
}
pmx_patient_characteristics <- function(d,continuous,categorical,labels=character(),level_display=function(v,x) x,
                                       id=NULL,study=NULL,label_column="Covariate") {
  if(is.null(study)) {
    candidates <- intersect(c("STUDYID","STUDY","PROTOCOL","STUDY_ID"),names(d))
    candidates <- candidates[vapply(candidates,function(v) any(!is.na(d[[v]]) & nzchar(trimws(as.character(d[[v]])))),TRUE)]
    study <- if(length(candidates)) candidates[1] else NULL
  }
  if(!is.null(id) && id %in% names(d)) {
    keys <- c(if(!is.null(study)) study,id)
    d <- d[!duplicated(d[keys]),,drop=FALSE]
  }
  groups <- list();headers <- character()
  if(!is.null(study)) {
    s <- trimws(as.character(d[[study]]));s[is.na(s) | !nzchar(s)] <- "Study not recorded"
    for(g in sort(unique(s))) {
      groups[[length(groups)+1L]] <- which(s==g)
      headers <- c(headers,paste0(if(grepl("^study",g,ignore.case=TRUE)) g else paste("Study",g),", N = ",sum(s==g)))
    }
  }
  groups[[length(groups)+1L]] <- seq_len(nrow(d));headers <- c(headers,paste0("Total, N = ",nrow(d)))
  rows <- list();prefixes <- character()
  add <- function(label,cells,prefix="") {
    rows[[length(rows)+1L]] <<- c(label,cells);prefixes <<- c(prefixes,prefix)
  }
  lab <- function(v) if(v %in% names(labels)) unname(labels[[v]]) else v
  for(v in intersect(continuous,names(d))) {
    x <- suppressWarnings(as.numeric(as.character(d[[v]])))
    finite <- x[is.finite(x)];a <- abs(finite[finite!=0])
    places <- if(!length(a)) 1L else max(0L,min(6L,ceiling(-log10(stats::median(a)))+2L))
    cells <- vapply(groups,function(i) {
      z <- x[i];z <- z[is.finite(z)];if(!length(z)) return("NE")
      fmt <- function(n) formatC(n,format="f",digits=places)
      paste0(fmt(stats::median(z))," [",fmt(min(z)),", ",fmt(max(z)),"]")
    },"")
    add(lab(v),cells,lab(v))
  }
  for(v in intersect(categorical,names(d))) {
    x <- as.character(d[[v]]);x[!is.na(x) & !nzchar(trimws(x))] <- NA_character_
    add(paste0(lab(v),", N_total = ",sum(!is.na(x))),rep("",length(groups)),lab(v))
    levels <- sort(unique(x[!is.na(x)]))
    for(l in levels) {
      cells <- vapply(groups,function(i) {
        den <- sum(!is.na(x[i]));n <- sum(x[i]==l,na.rm=TRUE)
        if(!den) "NE" else sprintf("%d (%.1f%%)",n,100*n/den)
      },"")
      add(paste0("\u00a0",level_display(v,l)),cells)
    }
    if(anyNA(x)) add("\u00a0Missing",vapply(groups,function(i) as.character(sum(is.na(x[i]))),""))
  }
  if(!length(rows)) add("Patients",vapply(groups,function(i) as.character(length(i)),""))
  out <- as.data.frame(do.call(rbind,rows),stringsAsFactors=FALSE)
  names(out) <- c(label_column,headers);attr(out,"bold_labels") <- prefixes
  attr(out,"stratified_by_study") <- !is.null(study)
  out
}
pmx_fit_characteristics_kable <- function(d,bold_labels=attr(d,"bold_labels")) {
  shown <- d;shown[] <- lapply(shown,function(x) htmltools::htmlEscape(as.character(x)))
  for(i in which(nzchar(bold_labels))) {
    prefix <- bold_labels[i];rest <- substring(as.character(d[[1]][i]),nchar(prefix)+1L)
    shown[[1]][i] <- paste0("<strong>",htmltools::htmlEscape(prefix),"</strong>",htmltools::htmlEscape(rest))
  }
  cat(knitr::kable(shown,format="html",escape=FALSE,row.names=FALSE,caption="Summary of Patient Characteristics",
    align=paste0("l",strrep("c",ncol(d)-1L)),table.attr='class="table baseline-characteristics"'),
    '\n<p class="table-footnote">Continuous variables are presented as median [min, max], while categorical variables are presented as n (%) of patients with nonmissing values. Missing values are reported separately.</p>\n')
}
pmx_fit_vpc_panels <- function(p,ylab,log_ymin=NULL) {
  p <- p + ggplot2::labs(title=NULL)
  lin <- p+ggplot2::labs(x="Time After First Dose (h)",y=paste0(ylab," (linear scale)"))+ggplot2::theme_bw()
  built <- ggplot2::ggplot_build(p)$data
  values <- unlist(lapply(built,function(d) unlist(d[intersect(c("y","ymin","ymax"),names(d))])),use.names=FALSE)
  positive <- values[is.finite(values) & values>0]
  if(!length(positive)) {message("VPC_LOG_UNAVAILABLE: no positive values");print(lin);return(invisible(NULL))}
  floor <- if(is.null(log_ymin)) min(positive)/2 else log_ymin
  if(length(floor)!=1L || !is.finite(floor) || floor<=0) stop("VPC_LOG_YMIN must be a positive display limit or NULL")
  # The log axis clips everything below the floor at the panel edge, so the ribbon itself needs no
  # mapping rewrite. Rebuilding a layer with ggproto() breaks under ggplot2 4.x: the copy loses the
  # plot level data, and the built layer can no longer resolve x = xbin ("object 'xbin' not found").
  clipped <- any(values<floor,na.rm=TRUE)
  lg <- p+ggplot2::scale_y_log10(limits=c(floor,NA),oob=scales::oob_keep)+
    ggplot2::labs(x="Time After First Dose (h)",y=paste0(ylab," (log scale)"),
      caption=if(clipped) paste0("CI portions below ",format(floor,digits=3)," are clipped for log display; simulation values are unchanged.") else NULL)+ggplot2::theme_bw()
  gridExtra::grid.arrange(lin,lg,nrow=2)
}
pmx_fit_eta_labels <- function(ctl,names) {
  mapping <- list();assignments <- list()
  for(line in sub(";.*$","",ctl)) {
    a <- regmatches(line,regexec("^\\s*([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*(.*)$",line))[[1]]
    if(!length(a)) next
    assignments[[a[2]]] <- a[3]
    refs <- regmatches(a[3],gregexpr("ETA\\(\\s*[0-9]+\\s*\\)",a[3],ignore.case=TRUE))[[1]]
    for(ref in refs) {k <- gsub("[^0-9]","",ref);mapping[[k]] <- unique(c(mapping[[k]],a[2]))}
  }
  vapply(names,function(nm) {
    if(grepl("^ETA[_.][A-Za-z]",nm,ignore.case=TRUE)) return(toupper(sub("^ETA[_.]","",nm,ignore.case=TRUE)))
    values <- mapping[[sub("^ETA_?","",nm,ignore.case=TRUE)]]
    known <- c("CL","VC","VP","V","V1","V2","V3","Q","Q2","KA","KA1","KA2",
      "ALAG1","ALAG2","F1","F2","KTR","MTT","VMAX","KM","E0","R0","KIN","KOUT",
      "EMAX","EC50","IMAX","IC50","KE0","RSS","KON","KOFF","KINT","KDEG","KSS")
    seen <- character()
    for(step in seq_len(8L)) {
      if(any(values %in% known)) break
      seen <- unique(c(seen,values))
      next_values <- names(assignments)[vapply(assignments,function(rhs)
        any(vapply(values,function(v) grepl(paste0("\\b",v,"\\b"),rhs,perl=TRUE),logical(1))),logical(1))]
      next_values <- setdiff(next_values,seen)
      if(!length(next_values)) break
      values <- next_values
    }
    preferred <- intersect(values,known)
    if(length(preferred)) paste(preferred,collapse=" / ") else if(length(values)==1L) values else nm
  },"")
}
pmx_fit_parameter_table <- function(fit,ctl=character(),effects=list()) {
  raw <- tryCatch(as.data.frame(fit$parFixedDf),error=function(e) NULL)
  fe <- tryCatch(nlme::fixef(fit),error=function(e) numeric())
  if(is.null(raw) || !nrow(raw)) raw <- data.frame(Estimate=as.numeric(fe),row.names=names(fe))
  if(!nrow(raw)) return(NULL)
  nm <- rownames(raw)
  if("Parameter" %in% names(raw) && all(grepl("^[0-9]+$",nm))) nm <- as.character(raw$Parameter)
  if(anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) stop("REPORT_PARAMETER_NAMES_INVALID: preserve frozen fits; repair reporting names")
  rownames(raw) <- nm
  # parFixedDf is a presentation summary, not the coefficient inventory.
  # Recover omitted fixed effects by NAME from the same frozen fit, never ctl starts.
  missing <- setdiff(names(fe),nm)
  if(length(missing)) {
    extra <- raw[rep(NA_integer_,length(missing)),,drop=FALSE]
    rownames(extra) <- missing
    if(!"Estimate" %in% names(raw)) {raw$Estimate <- NA_real_;extra$Estimate <- NA_real_}
    extra$Estimate <- as.numeric(fe[missing])
    raw <- rbind(raw,extra);nm <- rownames(raw)
  }
  n <- nrow(raw)
  ini <- tryCatch(as.data.frame(fit$iniDf),error=function(e) NULL)
  num <- function(fields) {h <- intersect(fields,names(raw));if(length(h))
    suppressWarnings(as.numeric(sub("%$","",trimws(as.character(raw[[h[1]]]))))) else rep(NA_real_,n)}
  value <- num(c("Estimate","estimate"));se <- num(c("SE","Std. Error","Std.Error"))
  rse <- num(c("%RSE","RSE (%)"));shrink <- num(c("Shrink(SD)%","Shrinkage (%)"))
  bsv <- num(c("BSV(CV% or SD)","BSV(CV%)"));back <- num("Back-transformed")
  lower <- num(c("95% CI lower","CI Lower","CI lower","Lower","lower"))
  upper <- num(c("95% CI upper","CI Upper","CI upper","Upper","upper"))
  covariance <- tryCatch(as.matrix(fit$cov),error=function(e) NULL)
  symbol <- nm;label <- rep("",n)
  for(i in seq_len(n)) {
    if(nm[i] %in% names(fe)) {
      value[i] <- fe[[nm[i]]]
      if(!is.finite(se[i]) && !is.null(covariance) && nm[i] %in% rownames(covariance))
        se[i] <- sqrt(covariance[nm[i],nm[i]])
    }
    if(!is.null(ini) && all(c("name","label") %in% names(ini))) {
      k <- match(nm[i],ini$name)
      if(!is.na(k) && !is.na(ini$label[k])) {
        label[i] <- as.character(ini$label[k])
        if(grepl("THETA",label[i])) symbol[i] <- sub("\\s*\\(.*\\)\\s*$","",
          trimws(sub("^.*THETA\\([0-9]+\\)","",label[i])))
      }
    }
  }
  symbol <- sub("^t[.]","",symbol);short <- sub("^TV","",symbol)
  cov_info <- list();fixed_cov <- list()
  for(parameter in names(effects)) for(effect in effects[[parameter]]) {
    target <- sub("^TV","",parameter)
    key <- sprintf("theta_%s_%s%s",target,tolower(effect$cov),
      if(identical(effect$type,"cat")) effect$level else "")
    title <- paste(unname(pmx_fit_covariate_labels(stats::setNames(toupper(effect$cov),toupper(effect$cov)))),"on",target)
    description <- if(identical(effect$type,"cat")) paste0(pmx_fit_level_display(effect$cov,effect$level)," versus the fitted reference group") else
      paste0(effect$type," covariate coefficient",if(!is.null(effect$ref)) paste0(" (reference ",effect$ref,")") else "")
    if(identical(effect$type,"power") && !is.null(effect$exp)) {
      fixed_cov[[length(fixed_cov)+1L]] <- list(title=title,value=effect$exp)
    } else cov_info[[tolower(key)]] <- list(title=title,description=description)
  }
  keys <- tolower(sub("^t[.]","",nm))
  absent <- setdiff(names(cov_info),unique(c(keys,tolower(symbol))))
  if(length(absent)) stop("REPORT_COVARIATE_ESTIMATE_MISSING: ",paste(absent,collapse=", "),
    "; retained SCM coefficients are absent from the frozen fit; do not substitute ctl initials or rerun fits")
  mu_cov <- tryCatch(as.data.frame(fit$muRefCovariateDataFrame),error=function(e) NULL)
  mu_names <- if(!is.null(mu_cov) && "covariateParameter" %in% names(mu_cov)) as.character(mu_cov$covariateParameter) else character()
  is_cov <- grepl("^theta_",keys) | keys %in% names(cov_info) |
    tolower(symbol) %in% names(cov_info) | nm %in% mu_names
  if(any(is_cov & !is.finite(value))) stop("REPORT_COVARIATE_ESTIMATE_MISSING: non-finite frozen covariate coefficient; preserve fits and report the blocker")
  labels <- c(CL="Clearance",VC="Central volume",V="Volume of distribution",V1="Central volume",
    V2="Peripheral volume",VP="Peripheral volume",Q="Intercompartmental clearance",
    KA="Absorption rate constant",KA1="Absorption rate constant, depot 1",KA2="Absorption rate constant, depot 2",
    ALAG1="Absorption lag time, depot 1",ALAG2="Absorption lag time, depot 2",LAG="Absorption lag time",
    F1="Absorption fraction, depot 1",MTT="Mean transit time",KTR="Transit rate constant",
    VMAX="Maximum elimination rate",KM="Michaelis-Menten constant",E0="Baseline response",
    BASE="Baseline response",R0="Baseline response",KIN="Response production rate",
    KOUT="Response elimination rate",EMAX="Maximum effect",EC50="Concentration at half-maximal effect",
    IC50="Concentration at half-maximal inhibition",IMAX="Maximum inhibition",GAMMA="Hill coefficient",
    SLOPE="Exposure-response slope",KE0="Effect-compartment equilibration rate",
    KON="Drug-target association rate",KOFF="Drug-target dissociation rate",
    KSS="Quasi-steady-state binding constant",KDEG="Target degradation rate",
    RSS="Baseline target concentration",KINT="Drug-target internalization rate")
  desc <- ifelse(short %in% names(labels),unname(labels[short]),symbol)
  for(i in which(is_cov)) {
    info <- cov_info[[keys[i]]]
    if(is.null(info)) info <- cov_info[[tolower(symbol[i])]]
    if(!is.null(info)) {short[i] <- info$title;desc[i] <- info$description}
    else desc[i] <- "Covariate coefficient (fitted scale)"
  }
  is_iiv <- grepl("^ETA_?[0-9]+$|^ETA[_.]",nm,ignore.case=TRUE)
  residual_names <- if(!is.null(ini) && all(c("name","err") %in% names(ini))) ini$name[!is.na(ini$err)] else character()
  is_res <- !is_iiv & !is_cov & (nm %in% residual_names | grepl("^sd|^sig|^eps|resid|prop|add",nm,ignore.case=TRUE))
  display <- value;lo <- lower;hi <- upper
  for(i in seq_len(n)) {
    transform <- if(grepl("logit",label[i],ignore.case=TRUE)) plogis else
      if(grepl("\\blog\\b|\\blog-scale\\b",label[i],ignore.case=TRUE)) exp else identity
    if(!is_iiv[i] && is.finite(value[i]) && is.finite(se[i]) && se[i]>=0 &&
       (!is.finite(lo[i]) || !is.finite(hi[i]))) {
      bounds <- value[i]+c(-1,1)*qnorm(.975)*se[i];lo[i] <- transform(bounds[1]);hi[i] <- transform(bounds[2])
    }
    if(!is_iiv[i]) display[i] <- transform(value[i])
    if(is.finite(back[i])) {
      if(!isTRUE(all.equal(back[i],display[i],tolerance=1e-5))) {lo[i] <- NA_real_;hi[i] <- NA_real_}
      display[i] <- back[i]
    }
    if(is_iiv[i] && is.finite(bsv[i])) {display[i] <- bsv[i];lo[i] <- NA_real_;hi[i] <- NA_real_}
  }
  # nlmixr2's confint reads the frozen covariance and parsed back-transformation;
  # it does not optimize the model. Keep an unavailable interval blank.
  supported_ci <- if(!is.null(covariance) && requireNamespace("nlmixr2est",quietly=TRUE))
    tryCatch(as.data.frame(stats::confint(fit,level=.95,exponentiate=NA)),error=function(e) NULL) else NULL
  if(!is.null(supported_ci) && all(c("estimate","2.5 %","97.5 %") %in% names(supported_ci))) {
    for(i in which(!is_iiv)) {
      k <- match(nm[i],rownames(supported_ci))
      if(!is.na(k)) {
        display[i] <- supported_ci$estimate[k]
        lo[i] <- supported_ci[["2.5 %"]][k];hi[i] <- supported_ci[["97.5 %"]][k]
      }
    }
  }
  missing_rse <- !is_iiv & !is.finite(rse) & is.finite(se) & is.finite(value) & value!=0
  rse[missing_rse] <- 100*se[missing_rse]/abs(value[missing_rse])
  estimate <- pmx_fit_format(display);ci <- is.finite(lo) & is.finite(hi)
  estimate[ci] <- paste0(estimate[ci]," (",pmx_fit_format(lo[ci])," to ",pmx_fit_format(hi[ci]),")")
  short[is_iiv] <- paste0("IIV on ",pmx_fit_eta_labels(ctl,nm[is_iiv]))
  desc[is_iiv] <- ""
  # Residual names describe the fitted error model, not arbitrary sd1/sd2 symbols.
  for(i in which(is_res)) {
    k <- if(!is.null(ini) && "name" %in% names(ini)) match(nm[i],ini$name) else NA_integer_
    kind <- if(!is.na(k) && "err" %in% names(ini)) as.character(ini$err[k]) else NA_character_
    title <- c(add="Additive term",prop="Proportional term",lnorm="Log-normal error term",pow="Power error term")
    short[i] <- if(!is.na(kind) && kind %in% names(title)) title[[kind]] else "Residual error"
    endpoint <- if(!is.na(k) && "condition" %in% names(ini)) as.character(ini$condition[k]) else NA_character_
    conditions <- if(!is.null(ini) && all(c("condition","err") %in% names(ini)))
      unique(na.omit(ini$condition[!is.na(ini$err)])) else character()
    if(length(conditions)>1L && !is.na(endpoint)) short[i] <- paste0(short[i]," (",endpoint,")")
    desc[i] <- ""
    if(identical(kind,"add")) {
      dictionary <- pmx_fit_metadata()$spec
      unit <- character()
      if(!is.null(dictionary)) {
        rows <- dictionary$variable=="DV"
        if("status" %in% names(dictionary)) rows <- rows & !is.na(dictionary$status) & dictionary$status=="confirmed"
        unit <- unique(na.omit(dictionary$unit[rows]))
      }
      log_dv <- grepl("DV[[:space:]]*=[[:space:]]*(LNDV|LOGDV)\\b",paste(ctl,collapse=" "),ignore.case=TRUE,perl=TRUE)
      if(log_dv) unit <- "log scale"
      if(length(unit)==1L && nzchar(unit) && unit!="endpoint-specific") short[i] <- paste0(short[i]," (",unit,")")
    }
  }
  if(anyDuplicated(short[is_res])) short[is_res] <- make.unique(short[is_res],sep=" ")
  rows <- data.frame(Parameter=short,Description=desc,`Estimate`=estimate,
    `%RSE`=pmx_fit_format(rse),`Shrinkage (%)`=ifelse(is_iiv,pmx_fit_format(shrink),""),check.names=FALSE)
  group <- function(text,index) {
    if(!length(index)) return(NULL)
    header <- rows[1,,drop=FALSE];header[] <- "";header$Parameter <- text;rbind(header,rows[index,,drop=FALSE])
  }
  # Mu-referenced fits carry BSV/shrinkage beside the fixed coefficient. Split
  # these into two rows rather than misclassifying clearance/volume as an ETA.
  attached <- which(!is_iiv & !is_res & !is_cov & is.finite(bsv))
  iiv_rows <- rows[is_iiv,,drop=FALSE]
  if(length(attached)) {
    extra <- rows[attached,,drop=FALSE]
    extra$Parameter <- paste0("IIV on ",short[attached])
    extra$Description <- ""
    extra$`Estimate` <- pmx_fit_format(bsv[attached])
    extra$`%RSE` <- "";extra$`Shrinkage (%)` <- pmx_fit_format(shrink[attached])
    iiv_rows <- rbind(iiv_rows,extra)
  }
  # CV% belongs only to log-normal effects. Keep other SDs/covariances separate.
  omega <- tryCatch(as.matrix(fit$omega),error=function(e) NULL)
  iiv_sources <- c(which(is_iiv),attached)
  eta_names <- c(nm[is_iiv],rep(NA_character_,length(attached)))
  mu <- tryCatch(as.data.frame(fit$muRefTable),error=function(e) NULL)
  if(length(attached) && !is.null(mu) && all(c("theta","eta") %in% names(mu)))
    eta_names[length(which(is_iiv))+seq_along(attached)] <- as.character(mu$eta[match(nm[attached],mu$theta)])
  if(length(attached) && !is.null(omega) && !is.null(rownames(omega))) {
    indices <- length(which(is_iiv))+seq_along(attached)
    mapped <- rownames(omega)[match(short[attached],pmx_fit_eta_labels(ctl,rownames(omega)))]
    eta_names[indices] <- ifelse(is.na(eta_names[indices]),mapped,eta_names[indices])
  }
  headings <- rep("Interindividual Variability (reported scale)",nrow(iiv_rows))
  for(i in seq_len(nrow(iiv_rows))) {
    eta <- eta_names[i]
    index <- if(!is.null(ini) && all(c("name","neta1") %in% names(ini))) ini$neta1[match(eta,ini$name)] else NA_integer_
    if(is.na(index) && !is.na(eta) && grepl("^ETA_?[0-9]+$",eta,ignore.case=TRUE))
      index <- as.integer(gsub("[^0-9]","",eta))
    rhs <- toupper(gsub("[[:space:]]","",sub(";.*$","",ctl)))
    rhs <- sub("^[A-Z][A-Z0-9_]*=","",rhs[grepl("^[A-Z][A-Z0-9_]*=",rhs)])
    lognormal <- !is.na(index) && any(grepl(paste0("^(?:[A-Z0-9_.]+\\*)?EXP\\([^/]*ETA\\(",index,"\\)[^/]*\\)$"),rhs,perl=TRUE))
    is_cv <- lognormal || ("BSV(CV%)" %in% names(raw) && is.finite(bsv[iiv_sources[i]]))
    variance <- if(!is.null(omega) && !is.na(eta) && eta %in% rownames(omega)) omega[eta,eta] else NA_real_
    if(!is.finite(variance) && !is.na(index) && !is.null(omega) && index<=nrow(omega)) variance <- omega[index,index]
    if(!is.finite(variance) && is_iiv[iiv_sources[i]]) variance <- value[iiv_sources[i]]
    headings[i] <- "Interindividual Variability"
    iiv_rows$Parameter[i] <- sub("^IIV on ","",iiv_rows$Parameter[i])
    iiv_rows$Estimate[i] <- pmx_fit_format(variance)
    if(is_cv && is.finite(variance) && variance>=0) iiv_rows$Estimate[i] <- paste0(
      iiv_rows$Estimate[i]," (",formatC(100*sqrt(expm1(variance)),format="f",digits=1),")")
    source <- iiv_sources[i]
    # Only an actual variance row can provide variance uncertainty. Never use the
    # structural coefficient's SE/RSE for a mu-referenced attached IIV estimate.
    if(is_iiv[source]) {
      if(!is.finite(rse[source]) && is.finite(se[source]) && se[source]>=0 && is.finite(variance) && variance>0)
        iiv_rows$`%RSE`[i] <- pmx_fit_format(100*se[source]/variance)
      if(is.finite(lower[source]) && is.finite(upper[source])) iiv_rows$Estimate[i] <- paste0(
        iiv_rows$Estimate[i]," [",pmx_fit_format(lower[source])," to ",pmx_fit_format(upper[source]),"]")
    }
    iiv_rows$Description[i] <- ""
  }
  iiv_group <- NULL
  for(heading in unique(headings)) {
    header <- rows[1,,drop=FALSE];header[] <- "";header$Parameter <- heading
    iiv_group <- rbind(iiv_group,header,iiv_rows[headings==heading,,drop=FALSE])
  }
  if(!is.null(omega) && nrow(omega)>1L && !is.null(rownames(omega))) {
    positions <- which(lower.tri(omega) & is.finite(omega) & omega!=0,arr.ind=TRUE)
    eta_labels <- pmx_fit_eta_labels(ctl,rownames(omega))
    for(k in seq_len(nrow(positions))) {
      i <- positions[k,1];j <- positions[k,2]
      extra <- rows[1,,drop=FALSE];extra[] <- ""
      denominator <- sqrt(omega[i,i]*omega[j,j])
      if(!is.finite(denominator) || denominator<=0) next
      extra$Parameter <- paste0("Corr-",eta_labels[j],"-",eta_labels[i])
      extra$Estimate <- pmx_fit_format(omega[i,j]/denominator)
      if(is.null(iiv_group)) {header <- extra;header[] <- "";header$Parameter <- "Interindividual Variability";iiv_group <- header}
      iiv_group <- rbind(iiv_group,extra)
    }
  }
  cov_group <- group("Covariate Effects",which(is_cov & !is_iiv))
  for(effect in fixed_cov) {
    extra <- rows[1,,drop=FALSE];extra[] <- ""
    extra$Parameter <- effect$title;extra$Description <- "Prespecified fixed power exponent (not estimated)"
    extra$`Estimate` <- pmx_fit_format(effect$value)
    if(is.null(cov_group)) {header <- extra;header[] <- "";header$Parameter <- "Covariate Effects";cov_group <- header}
    cov_group <- rbind(cov_group,extra)
  }
  out <- rbind(group("Fixed Effects",which(!is_iiv & !is_res & !is_cov)),cov_group,iiv_group,
    group("Residual Variability",which(is_res)))
  # Section-specific headings keep variance/CV and confidence intervals distinct.
  positions <- which(out$Parameter %in% c("Fixed Effects","Covariate Effects","Interindividual Variability","Residual Variability") & !nzchar(out$Estimate) & !nzchar(out$Description))
  for(i in rev(positions)) {
    heading <- out[i,,drop=FALSE];heading[] <- ""
    heading$Parameter <- "Parameter"
    heading$Description <- if(out$Parameter[i] %in% c("Fixed Effects","Covariate Effects")) "Description" else ""
    heading$Estimate <- if(out$Parameter[i]=="Interindividual Variability") "Estimate (%CV)" else "Estimate (95% CI)"
    heading$`%RSE` <- "RSE (%)"
    heading$`Shrinkage (%)` <- if(out$Parameter[i]=="Interindividual Variability") "Shrinkage (%)" else ""
    out <- rbind(out[seq_len(i),,drop=FALSE],heading,out[if(i<nrow(out)) seq.int(i+1L,nrow(out)) else integer(),,drop=FALSE])
  }
  rownames(out) <- NULL;out
}
pmx_fit_parameter_note <- function(tab) {
  paste("IIV estimates are variances (%CV); CV is shown only for log-normal effects. Corr denotes a correlation coefficient.",
    "Limits (lower to upper) or [lower to upper] are 95% CI. RSE (%) = 100 x SE/abs(estimate) on the fitted scale; IIV RSE refers to variance. Blank cells indicate unavailable uncertainty.",
    if(any(grepl("^Proportional term",tab$Parameter)))
      "The proportional term is a relative SD (0.1 = 10%); additive terms use the observation scale." else "")
}
pmx_fit_kable <- function(tab,caption) {
  if(is.null(tab) || !nrow(tab)) return(invisible(NULL))
  groups <- !nzchar(tab$Description) & !nzchar(tab$Estimate) &
    grepl("^(Fixed Effects|Covariate Effects|Interindividual Variability|Residual Variability)",tab$Parameter)
  headings <- tab$Parameter=="Parameter" & startsWith(tab$Estimate,"Estimate")
  escape <- function(x) htmltools::htmlEscape(as.character(x))
  body <- vapply(seq_len(nrow(tab)),function(i) {
    if(groups[i]) return(paste0('<tr><td colspan="5"><strong>',escape(tab$Parameter[i]),'</strong></td></tr>'))
    values <- vapply(tab[i,,drop=FALSE],function(x) escape(x[1]),"")
    if(headings[i]) values <- paste0('<strong>',values,'</strong>')
    paste0('<tr>',paste0('<td>',values,'</td>',collapse=""),'</tr>')
  },"")
  knitr::asis_output(paste0('<table class="table ppk-parameters"><caption>',escape(caption),'</caption><thead><tr>',
    paste0('<th>',escape(c("Parameter","Description","Estimate","RSE (%)","Shrinkage (%)")),'</th>',collapse=""),
    '</tr></thead><tbody>',paste(body,collapse="\n"),'</tbody></table>\n<p>',pmx_fit_parameter_note(tab),'</p>\n'))
}

pmx_fit_data_sections <- function(path, result, family, metadata=list()) {
  source_data <- tryCatch({
    header <- readLines(path,n=1L,warn=FALSE)
    sep <- if(grepl("\t",header,fixed=TRUE)) "\t" else
      if(grepl(",",header,fixed=TRUE)) "," else if(grepl(";",header,fixed=TRUE)) ";" else ""
    read.table(path,header=TRUE,sep=sep,quote="\"",comment.char="",check.names=FALSE,
               colClasses="character",na.strings=c("",".","NA"))
  },error=function(e) NULL)
  study_col <- match("STUDYID",toupper(sub("^[@#]","",names(source_data))))
  ids <- if(is.na(study_col)) character() else unique(trimws(source_data[[study_col]]))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  studies <- if(length(ids)==1L) paste("The supplied dataset contained records identified as Study",paste0(ids,".")) else
    if(length(ids)>1L) paste0("The supplied dataset pooled records identified as Studies ",paste(ids,collapse=", "),".") else
      "The supplied dataset was the source of the analysis records. Study identifiers were unavailable."
  endpoints <- switch(family,ppk="drug concentration observations",
                      pkpd="drug concentration and pharmacodynamic response observations",
                      tmdd="drug and target-related observations")
  counts <- c(result$n_subjects,result$n_observations)
  dataset <- if(length(counts)==2L && is.numeric(counts) && all(is.finite(counts))) {
    sprintf("The analysis included %s participants and %s observations for model estimation. The supplied records included %s.",
            format(counts[1],big.mark=",",trim=TRUE),format(counts[2],big.mark=",",trim=TRUE),endpoints)
  } else paste0("The analysis dataset contained recorded dosing events and ",endpoints,".")
  defaults <- list(
    StudiesIncluded=studies,
    AnalysisDataset=dataset,
    BioanalyticalMethods="Assay methods and assay-specific quantification limits were not provided in the analysis materials.",
    DataAssembly="Dosing events, sampling times, endpoint identifiers and covariates were taken from the supplied analysis dataset. The control stream defined the input column roles and the scale used for estimation.",
    BLQHandling="The available analysis materials did not specify a separate procedure for measurements below the lower limit of quantification (LLOQ).",
    DataErrors="The supplied analysis materials did not include a separate record of data queries or corrections.",
    OutlierHandling="Residual diagnostics were used for model evaluation. The supplied analysis materials did not document a residual-based criterion for excluding observations.",
    BaselineResponse="The model specification defined baseline-response initialization. Any separately measured baseline values and their handling should be confirmed from the study records.",
    MissingCovariates="A study-specific procedure for missing covariates was not documented."
  )
  titles <- c(StudiesIncluded="3.1 Studies included in the analysis",
              AnalysisDataset=if(family=="ppk") "3.2 Pharmacokinetic analysis dataset" else "3.2 Analysis dataset",
              BioanalyticalMethods=if(family=="ppk") "3.3 Drug assay" else "3.3 Bioanalytical methods",
              DataAssembly="3.4 Data assembly",
              BLQHandling="3.5.1 Handling of observations below the limit of quantification",
              DataErrors="3.5.2 Handling of suspected data errors",
              OutlierHandling="3.5.3 Handling of outliers")
  if(family=="pkpd") titles <- c(titles,BaselineResponse="3.5.4 Baseline response")
  titles <- c(titles,MissingCovariates=paste0(if(family=="pkpd") "3.5.5" else "3.5.4"," Handling of missing covariates"))
  setNames(lapply(names(titles),function(key) {
    text <- metadata[[key]]
    if(length(text)==1L && !is.na(text) && nzchar(trimws(text))) text else defaults[[key]]
  }),unname(titles))
}

pmx_fit_method_sections <- function(result,family="ppk") {
  methods <- list(
    "1. Introduction"="This report describes the population pharmacokinetics of the study intervention using the data collected in the included clinical studies.",
    "2. Objectives"=c("Characterize the pharmacokinetics of the study intervention.",
      "Determine the effects of demographic, pathophysiologic, and disease-related covariates on pharmacokinetics to better understand the clinical factors that might affect exposure in individual patients."),
    "4.1 Software and strategy"="The PopPK analysis was performed using the nonlinear mixed effects modeling approach. The typical values of parameters and their variances were estimated using the first-order conditional estimation with interaction (FOCEI) method in nlmixr2.",
    "4.2 Exploratory analysis of data"="Concentration versus time profiles were explored graphically. These profiles were evaluated to compare the PK results across available studies and doses, and to identify potential data inconsistencies. This graphical analysis, together with background knowledge of pharmacokinetics, provided initial directions for structural model selection.",
    "4.3.1 Base model development"=c("Additional model structures were explored, as appropriate. The base model was chosen based on the completed candidate fits, diagnostic plots, reliability of model parameter estimates, and physiological plausibility.",
      "In general, interindividual variability was modeled for PK parameters as follows, as appropriate:",
      "θ_i = θ_T × exp(η_i)","θ_i: Individual model parameter for subject i",
      "θ_T: Typical value of the parameter in the population","η_i: Random interindividual effect with mean zero and variance ω²",
      "For bounded PK parameters, the parameters may be transformed using the logit transformation before modeling interindividual variability. The variance-covariance structure and residual error model are those specified in the selected control stream.",
      "For a combined proportional and additive residual model, residual variability is represented as follows:",
      "C_obs,ij = C_pred,ij × (1 + ε_prop,ij) + ε_add,ij",
      "C_obs,ij and C_pred,ij: Observed and predicted concentrations for subject i at time j",
      "ε_prop,ij and ε_add,ij: Proportional and additive residual random errors with mean zero",
      "The fitted residual structure, endpoint scale, and error terms are those in the selected control stream."),
    "4.3.2 Final model development"=c("The final model was developed by incorporating the effects of relevant covariates on structural model parameters of the base model. Covariate-parameter relationships were evaluated based on physiological plausibility, clinical relevance, and prior knowledge.",
      "For a power covariate relationship, continuous effects are represented as follows:",
      "θ_i = θ_T × exp(η_i) × (Cov_i / Cov_ref)^k_cov",
      "Cov_i: Individual continuous covariate value for subject i","Cov_ref: Population reference value used for normalization",
      "k_cov: Coefficient describing the covariate effect",
      "Categorical effects are evaluated relative to the configured reference group using the functional relationships in the final control stream."),
    "4.4.1 GOF diagnostic plots"="GOF diagnostic plots were generated to examine the appropriateness of the model fit to the observed data. Available diagnostics include observed versus population and individual predictions, residuals versus predictions and time, and individual concentration-time profiles.",
    "4.4.2 pcVPC"="Prediction-corrected visual predictive checks assess the ability of the model to reproduce both the central tendency and variability of the observed concentration data over time. Observed percentiles are compared with the simulated percentiles and their uncertainty; the number of replicates and the correction are those used in the displayed check.",
    "4.4.3 Shrinkage"=c("Shrinkage was assessed for the interindividual random effects available from the fitted model. Shrinkage quantifies the information in the dataset available to derive individual parameter estimates. Empirical Bayes estimates should be interpreted with caution whenever substantial shrinkage exists.",
      "η-shrinkage = 100 × (1 − SD(η_i) / ω)","SD(η_i): Standard deviation of the individual empirical Bayes estimates",
      "ω: Model-estimated standard deviation of the interindividual random effect"))
  if(identical(result$criterion,"bic")) methods[["4.3.2 Final model development"]] <- c(
    methods[["4.3.2 Final model development"]],"A stepwise forward selection and backward deletion strategy was used to identify the final model, with BIC used to guide covariate selection.")
  else if(identical(result$criterion,"chisq") && all(is.finite(c(result$p_forward,result$p_backward))))
    methods[["4.3.2 Final model development"]] <- c(methods[["4.3.2 Final model development"]],
      sprintf("A stepwise forward selection and backward deletion strategy was used to identify the final model. The configured significance levels were p < %g for forward selection and p < %g for backward deletion.",result$p_forward,result$p_backward))
  if(family!="ppk") {
    methods[["4.4.2 VPC and pcVPC"]] <- methods[["4.4.2 pcVPC"]]
    methods[["4.4.2 pcVPC"]] <- NULL
    label <- if(family=="pkpd") "PK/PD" else "TMDD"
    methods <- lapply(methods,function(text) gsub("PopPK",label,text,fixed=TRUE))
    methods[["1. Introduction"]] <- if(family=="pkpd")
      "This report describes the pharmacokinetics and pharmacodynamic responses of the study intervention using the data collected in the included studies." else
      "This report describes target-mediated drug disposition of the study intervention using the data collected in the included studies."
    methods[["2. Objectives"]][1] <- if(family=="pkpd")
      "Characterize the pharmacokinetics and the relationship between exposure and the configured pharmacodynamic endpoints." else
      "Characterize drug disposition and the contributions of linear and target-mediated processes supported by the available data."
    methods[["2. Objectives"]][2] <- if(family=="pkpd")
      "Determine the effects of relevant covariates on the model parameters, exposure and pharmacodynamic response, where supported by the configured analysis." else
      "Evaluate covariate effects on disposition parameters and the implications for predicted exposure and target-related endpoints, where supported by the configured analysis."
    methods[["4.2 Exploratory analysis of data"]] <-
      "Observed endpoint profiles versus time were explored graphically across the available studies and dose groups. Endpoint scales and coding, baseline measurements, and potential data inconsistencies informed structural model selection."
    methods[["4.3.1 Base model development"]] <- c(methods[["4.3.1 Base model development"]],
      if(family=="pkpd") "The PK/PD structure, baseline response, endpoint scales, and residual models are those specified in the selected control stream. Joint and sequential interpretations should reflect the configured modeling strategy." else
      "The TMDD structure and the observed free or total drug and target endpoints are those specified in the selected control stream. Binding, turnover and internalization parameters should be interpreted in light of their uncertainty and the information provided by the sampling design.")
    methods[["4.4.2 VPC and pcVPC"]] <-
      "Visual predictive checks assess the ability of the model to reproduce the central tendency and variability of each observed endpoint over time. Prediction correction is interpreted only for endpoints and checks where it was applied. The replicate count, endpoint scale and uncertainty are those used in the displayed check."
  }
  methods[["4.2 Exploratory analysis of data"]] <- c(methods[["4.2 Exploratory analysis of data"]],
    "Covariate-group profiling uses frozen individual estimates and recorded dose events. Regular repeated-dose summaries use 50 fixed conditioning intervals and the following dosing interval, without a steady-state test or patient-specific fallback. Single-dose/irregular recorded regimens use a common prediction window from the study specification or, by default, the full study sampling-time range. A patient does not need an observed measurement at each prediction time.",
    "Clast denotes the prediction at the end of that window, not a steady-state trough. These descriptive group summaries retain individual regimens and random effects and do not by themselves isolate adjusted covariate effects.")
  # Missing uncertainty is disclosed in the methods, next to the estimation strategy,
  # and never silently presented as an unqualified result.
  disclosure <- if(exists("pmx_covariance_disclosure",mode="function")) pmx_covariance_disclosure(result) else character()
  if(length(disclosure) && length(methods[["4.1 Software and strategy"]]))
    methods[["4.1 Software and strategy"]] <- c(methods[["4.1 Software and strategy"]],disclosure)
  methods
}

# Compatibility for already published PPK report sources.
pmx_ppk_format <- pmx_fit_format
pmx_ppk_eta_labels <- pmx_fit_eta_labels
pmx_ppk_parameter_table <- pmx_fit_parameter_table
pmx_ppk_kable <- pmx_fit_kable
pmx_ppk_method_sections <- pmx_fit_method_sections

# Native weighted residuals only: never manufacture CWRES from DV/PRED or substitute IWRES.
pmx_fit_observations <- function(a, endpoint=NULL, endpoint_column="DVID") {
  keep <- rep(TRUE,nrow(a))
  for(n in intersect(c("EVID","MDV"),names(a))) keep <- keep & !is.na(a[[n]]) & a[[n]]==0
  a <- a[keep,,drop=FALSE]
  if(!is.null(endpoint)) {
    if(!endpoint_column %in% names(a) || anyNA(a[[endpoint_column]]))
      stop("REPORT_ENDPOINT_REQUIRED: diagnostic endpoint map unavailable")
    a <- a[a[[endpoint_column]]==endpoint,,drop=FALSE]
  } else if(endpoint_column %in% names(a) && length(unique(na.omit(a[[endpoint_column]])))>1L)
    stop("REPORT_ENDPOINT_REQUIRED: select an endpoint; never pool different observation types")
  a
}
pmx_fit_residual_plots <- function(a, endpoint=NULL, role="PK", ylab="Concentration", endpoint_column="DVID") {
  a <- pmx_fit_observations(a,endpoint,endpoint_column)
  if(!"CWRES" %in% names(a) || !any(is.finite(a$CWRES))) return(list())
  a <- a[is.finite(a$CWRES),,drop=FALSE]
  limit <- max(1,abs(a$CWRES))
  plots <- list()
  for(x in c("PRED","TIME")) {
    if(!x %in% names(a)) next
    d <- a[is.finite(a[[x]]),,drop=FALSE]
    if(!nrow(d)) next
    p <- ggplot2::ggplot(d,ggplot2::aes(x=.data[[x]],y=CWRES)) +
      ggplot2::geom_point(shape=1,colour="blue",alpha=0.5) +
      ggplot2::geom_hline(yintercept=0,colour="red") +
      ggplot2::coord_cartesian(ylim=c(-limit,limit)) +
      ggplot2::labs(x=if(x=="TIME") "Time (h)" else paste("Population predicted",ylab),
                    y=paste(role,"CWRES")) + ggplot2::theme_bw()
    if(nrow(d)>=10L && length(unique(d[[x]]))>=4L)
      p <- p+ggplot2::geom_smooth(method="loess",span=0.95,se=FALSE,colour="darkblue")
    plots[[x]] <- p
  }
  plots
}
pmx_fit_gof_plots <- function(a, endpoint=NULL, role="PK", ylab="Concentration", extra=FALSE, endpoint_column="DVID") {
  a <- pmx_fit_observations(a,endpoint,endpoint_column)
  if(!nrow(a)) stop("REPORT_ENDPOINT_REQUIRED: no diagnostic observations for ",role)
  plots <- list()
  if(!extra) for(x in c("PRED","IPRED")) for(logarithmic in c(FALSE,TRUE)) {
    if(!all(c(x,"DV") %in% names(a))) next
    keep <- is.finite(a[[x]]) & is.finite(a$DV)
    if(logarithmic) keep <- keep & a[[x]]>0 & a$DV>0
    d <- a[keep,,drop=FALSE];if(!nrow(d)) next
    lim <- range(d[[x]],d$DV)
    if(diff(lim)==0) lim <- if(logarithmic) lim*c(0.9,1.1) else lim+c(-1,1)*max(abs(lim[1])*0.05,1e-4)
    p <- ggplot2::ggplot(d,ggplot2::aes(x=.data[[x]],y=DV)) +
      ggplot2::geom_point(shape=1,colour="blue",alpha=0.5) +
      ggplot2::geom_abline(slope=1,intercept=0,colour="red") +
      ggplot2::coord_equal(xlim=lim,ylim=lim) +
      ggplot2::labs(x=paste(if(x=="PRED") "Population predicted" else "Individual predicted",ylab),
        y=paste("Observed",ylab,if(logarithmic) "(log scale)" else "(linear scale)")) + ggplot2::theme_bw()
    if(logarithmic) p <- p+ggplot2::scale_x_log10()+ggplot2::scale_y_log10()
    plots[[length(plots)+1L]] <- p
  }
  if(extra) {
    if(all(c("IPRED","IWRES") %in% names(a))) {
      d <- a[is.finite(a$IPRED) & is.finite(a$IWRES),,drop=FALSE]
      if(nrow(d)) plots[[length(plots)+1L]] <- ggplot2::ggplot(d,ggplot2::aes(IPRED,abs(IWRES))) +
        ggplot2::geom_point(shape=1,colour="blue",alpha=0.4) +
        ggplot2::labs(x=paste("Individual predicted",ylab),y="|IWRES|") + ggplot2::theme_bw()
    }
    if("CWRES" %in% names(a)) {
      d <- a[is.finite(a$CWRES),,drop=FALSE]
      if(nrow(d)>=2L) plots[[length(plots)+1L]] <- ggplot2::ggplot(d,ggplot2::aes(sample=CWRES)) +
        ggplot2::stat_qq(size=0.6,alpha=0.4,colour="blue")+ggplot2::stat_qq_line(colour="red") +
        ggplot2::labs(x="Theoretical quantiles",y="CWRES")+ggplot2::theme_bw()
    }
    if(all(c("TIME","DV","IPRED","PRED","ID") %in% names(a)))
      plots[[length(plots)+1L]] <- ggplot2::ggplot(a,ggplot2::aes(TIME)) +
        ggplot2::geom_point(ggplot2::aes(y=DV),shape=1,colour="grey45",alpha=0.4) +
        ggplot2::geom_line(ggplot2::aes(y=IPRED,group=ID,colour="IPRED"),alpha=0.15) +
        ggplot2::geom_line(ggplot2::aes(y=PRED,group=ID,colour="PRED"),alpha=0.15,linetype=2) +
        ggplot2::scale_colour_manual(values=c(IPRED="blue",PRED="red"),name="") +
        ggplot2::labs(x="Time (h)",y=ylab)+ggplot2::theme_bw()
  }
  plots
}

# Fit-family Word selection; all omitted HTML diagnostics remain available as evidence.
pmx_fit_word_figures <- function(manifest) {
  if(!nrow(manifest)) return(list(keep=manifest,omitted=character()))
  caption <- if("caption" %in% names(manifest)) manifest$caption else rep("",nrow(manifest))
  key <- paste(manifest$section,caption)
  dose_impact <- grepl("(exposure|response)[[:space:]]+by[[:space:]]+dose([[:space:](]|$)",caption,ignore.case=TRUE) &
    grepl("model.predicted|steady.state|observed.regimen",caption,ignore.case=TRUE)
  omit <- dose_impact | grepl("EBE Distributions|distribution[s]? of (the )?EBE|Individual Fits|Covariate[ -]Correlation",key,ignore.case=TRUE) |
    grepl("weighted.residual diagnostics and fitted time profiles",caption,ignore.case=TRUE)
  list(keep=manifest[!omit,,drop=FALSE],omitted=manifest$file[omit])
}

# One impact-figure layout for PPK, PKPD and TMDD; all values are frozen-report quantities.
pmx_fit_covariate_figures <- function(d,sections,labels,roles,ylabels,positive_roles=names(roles)[1]) {
  out <- list()
  if(!"BASIS" %in% names(d)) d$BASIS <- "steady-state"
  for(cv in names(sections)) for(role in names(roles)) for(basis in unique(d$BASIS)) {
    rows <- d$ROLE==role & d$BASIS==basis & !is.na(d[[cv]]) & is.finite(d$EXPO)
    if(role %in% positive_roles) rows <- rows & d$EXPO>0
    shown <- d[rows,,drop=FALSE]
    if(!nrow(shown) || length(unique(shown[[cv]]))<2L) next
    metric_order <- if(identical(role,names(roles)[1])) c("Cmax","Cavg","Ctrough","Clast") else paste0(role,c("max","avg","end"))
    shown$METRIC <- factor(shown$METRIC,levels=intersect(metric_order,unique(as.character(shown$METRIC))))
    recorded <- basis %in% c("recorded-regimen","observed-regimen")
    window <- if("WINDOW_HOURS" %in% names(shown)) unique(shown$WINDOW_HOURS) else numeric()
    groups <- unique(as.character(shown[[cv]]))
    label_width <- (function(x) {
      grDevices::pdf(NULL);on.exit(grDevices::dev.off())
      max(graphics::strwidth(x,units="inches",cex=10/12))
    })(groups)
    columns <- if(length(groups)*(label_width+.15)>3.6) 1L else 2L
    height <- 1.5+3.1*ceiling(nlevels(shown$METRIC)/columns)
    out[[length(out)+1L]] <- list(variable=cv,role=role,data=shown,positive=role %in% positive_roles,
      columns=columns,height=height,
      ylab=ylabels[[role]],caption=paste(c("Model-predicted",if(!recorded) "steady-state",roles[[role]],"by",labels[[cv]]),collapse=" "),
      subtitle=if(length(window)==1L) paste(if(recorded) "Recorded dosing; prediction window:" else "Fixed 50 conditioning intervals; dosing interval:",
        format(window,digits=5),"h",if(recorded) "from first dose" else "") else NULL)
  }
  out
}
pmx_fit_show_covariate_figures <- function(specs,sections,labels,result_text=function(x) NULL) {
  last_section <- ""
  for(spec in specs) {
    cv <- spec$variable;section <- sections[[cv]]
    if(!identical(last_section,section)) {
      cat("\n\n### ",section,"\n\n",sep="");result_text(section);last_section <- section
    }
    p <- ggplot2::ggplot(spec$data,ggplot2::aes(.data[[cv]],EXPO)) +
      ggplot2::geom_boxplot(fill="steelblue",alpha=0.5,outlier.size=0.6) +
      ggplot2::geom_jitter(width=0.2,alpha=0.3,size=0.5) +
      ggplot2::facet_wrap(~METRIC,ncol=spec$columns,scales="free_y") +
      ggplot2::labs(x=labels[[cv]],y=spec$ylab,caption=spec$subtitle)+
      ggplot2::theme_bw(base_size=12)+ggplot2::theme(axis.text.x=ggplot2::element_text(size=10),
        panel.spacing=grid::unit(1,"lines"))
    p <- p + ggplot2::scale_x_discrete(guide=ggplot2::guide_axis(check.overlap=FALSE))
    if(spec$positive) p <- p+ggplot2::scale_y_log10()
    print(p)
  }
  if(!length(specs))
    cat("\nNo covariate-impact figure is estimable from the available regimen predictions and baseline groups.\n")
}

pmx_fit_has_capture <- function(path,capture) {
  lines <- grep("^\\s*\\$CAPTURE",readLines(path,warn=FALSE),value=TRUE)
  grepl(paste0("\\b",capture,"\\b"),paste(lines,collapse=" "))
}
pmx_fit_ebe_source <- function(ebe,paired,secondary="IPRED2") {
  if(!pmx_fit_has_capture(ebe,secondary) && pmx_fit_has_capture(paired,secondary)) paired else ebe
}
# Summarize one prediction interval; no steady-state/periodicity test.
pmx_fit_profile_metrics <- function(profile,column,convert,start,window) {
  unavailable <- c(max=NA_real_,avg=NA_real_,end=NA_real_)
  if(!column %in% names(profile)) return(unavailable)
  take <- profile$time>=start & profile$time<=start+window
  value <- convert(profile[[column]][take]);time <- profile$time[take]
  if(length(value)<2L || any(!is.finite(value)) || any(!is.finite(time)) || window<=0)
    return(unavailable)
  c(max=max(value),avg=sum(diff(time)*(head(value,-1)+tail(value,-1))/2)/window,end=tail(value,1))
}

# Join source selector codes to frozen canonical endpoints; never equate dose CMT with endpoint.
pmx_fit_endpoint_view <- function(d,native,resolve,allowed=c(1L,2L)) {
  names(native) <- toupper(names(native))
  observed <- function(x) {
    keep <- rep(TRUE,nrow(x))
    for(n in intersect(c("EVID","MDV"),names(x))) keep <- keep & !is.na(x[[n]]) & x[[n]]==0
    keep
  }
  source <- native[observed(native),,drop=FALSE]
  ep <- rep(NA_integer_,nrow(d));mapped <- FALSE
  if("DVID" %in% names(source)) for(pair in list(c("DVID","NMDVID"),c("CMT","NMCMT"))) {
    if(!pair[1] %in% names(d) || !pair[2] %in% names(source)) next
    map <- unique(data.frame(code=as.character(source[[pair[2]]]),endpoint=resolve(data.frame(DVID=source$DVID))))
    if(anyNA(map) || anyDuplicated(map$code) || any(!map$endpoint %in% allowed))
      stop("REPORT_ENDPOINT_REQUIRED: frozen source-to-endpoint map is ambiguous")
    ep <- map$endpoint[match(as.character(d[[pair[1]]]),map$code)];mapped <- TRUE
    break
  }
  fallback <- resolve(d)
  use <- !mapped & is.na(ep) & !is.na(fallback) & fallback %in% allowed
  ep[use] <- fallback[use]
  if(anyNA(ep[observed(d)]) || any(!ep[observed(d)] %in% allowed))
    stop("REPORT_ENDPOINT_REQUIRED: unmapped source observations; preserve input CMT/DVID")
  d$ENDPOINT <- ep
  d
}

# Recover consistent subject-level fields without treating a missing first dose-row value as baseline.
pmx_fit_baseline_view <- function(data,variables,id="ID") {
  out <- data[!duplicated(data[[id]]),c(id,intersect(variables,names(data))),drop=FALSE]
  for(i in seq_len(nrow(out))) for(v in setdiff(names(out),id)) {
    x <- data[[v]][as.character(data[[id]])==as.character(out[[id]][i])]
    x <- unique(x[!is.na(x) & nzchar(trimws(as.character(x)))])
    out[[v]][i] <- if(length(x)==1L) x[1] else NA
  }
  out
}
pmx_fit_exposure <- function(mod,idat,data,captures,convert,eta_source="idata.all",audit_file="table/_exposure_audit.csv",
                             prediction_window=NULL,metadata_file=file.path(Sys.getenv("PMX_ROOT",getwd()),"report_metadata.dcf")) {
  mod <- mrgsolve::zero_re(mod)
  param_names <- names(mrgsolve::param(mod))
  event_names <- c("ID","TIME","AMT","CMT","EVID","MDV","II","ADDL","RATE","SS","DVID","ENDPOINT")
  cov_names <- names(data)[tolower(names(data)) %in% tolower(param_names) & !names(data) %in% event_names]
  fields <- pmx_fit_baseline_view(data,cov_names)
  doses <- data[data$EVID==1 & is.finite(data$AMT) & data$AMT>0,,drop=FALSE]
  obs <- data[!is.na(data$EVID) & data$EVID==0 & is.finite(data$TIME),,drop=FALSE]
  if("MDV" %in% names(obs)) obs <- obs[!is.na(obs$MDV) & obs$MDV==0,,drop=FALSE]
  if("DV" %in% names(obs)) obs <- obs[is.finite(obs$DV),,drop=FALSE]
  ids <- as.character(idat$ID)
  windows <- vapply(ids,function(id) {
    ev <- doses[as.character(doses$ID)==id,,drop=FALSE];o <- obs[as.character(obs$ID)==id,,drop=FALSE]
    if(!nrow(ev)||!nrow(o)) return(NA_real_)
    last <- max(o$TIME)
    last-min(ev$TIME)
  },0.0)
  study_window <- if(any(is.finite(windows)&windows>0)) max(windows[is.finite(windows)&windows>0]) else NA_real_
  if(is.null(prediction_window) && file.exists(metadata_file)) {
    metadata <- read.dcf(metadata_file)
    if("PredictionWindowHours" %in% colnames(metadata)) prediction_window <- suppressWarnings(as.numeric(metadata[1,"PredictionWindowHours"]))
  }
  if(!is.null(prediction_window) && (length(prediction_window)!=1L || !is.finite(prediction_window) || prediction_window<=0))
    stop("REPORT_PREDICTION_WINDOW_INVALID: PredictionWindowHours must be one positive finite duration in hours")
  window_source <- if(is.null(prediction_window)) "study-time-range" else "configured"
  common_window <- if(is.null(prediction_window)) study_window else prediction_window
  pieces <- list();audit <- list()
  add_audit <- function(id,status,reason,basis="",window=NA_real_)
    audit[[length(audit)+1L]] <<- data.frame(ID=id,Status=status,Reason=reason,Basis=basis,Window_hours=window,Window_source=if(basis=="steady-state") "recorded-interval" else window_source)
  number <- function(x) suppressWarnings(as.numeric(as.character(x)))
  for(id in ids) {
    rows <- doses[as.character(doses$ID)==id,,drop=FALSE]
    if(!nrow(rows)) {add_audit(id,"unavailable","No positive recorded dose");next}
    if(any(!is.finite(rows$TIME)) || anyNA(rows$CMT)) {add_audit(id,"unavailable","Invalid dose time or compartment");next}
    individual <- idat[as.character(idat$ID)==id,,drop=FALSE]
    if(nrow(individual)!=1L) stop("REPORT_EBE_REQUIRED: exactly one frozen EBE record per subject")
    for(nm in intersect(param_names,tolower(names(individual)))) individual[[nm]] <- individual[[names(individual)[match(nm,tolower(names(individual)))]]]
    baseline <- fields[as.character(fields$ID)==id,,drop=FALSE]
    bad <- FALSE
    for(v in cov_names) {
      target <- param_names[match(tolower(v),tolower(param_names))]
      value <- if(nrow(baseline)==1L) number(baseline[[v]]) else NA_real_
      if(length(value)!=1L || !is.finite(value)) {bad <- TRUE;break}
      individual[[target]] <- value
    }
    if(bad) {add_audit(id,"unavailable","Missing, nonnumeric or changing model covariate; no default substituted");next}
    for(v in intersect(c("RATE","II","ADDL","SS"),names(rows)))
      if(any(!is.finite(number(rows[[v]])))) bad <- TRUE
    if(bad || ("RATE" %in% names(rows) && any(rows$RATE<0))) {
      add_audit(id,"unavailable","Incomplete or model-defined dose event needs an explicit regimen contract");next
    }
    taus <- if("II" %in% names(rows)) unique(rows$II[rows$II>0]) else numeric()
    if(!length(taus)) taus <- unique(diff(sort(unique(rows$TIME))))
    taus <- taus[is.finite(taus)&taus>0]
    combos <- unique(rows[,intersect(c("AMT","CMT","RATE"),names(rows)),drop=FALSE])
    repeated <- length(unique(rows$TIME))>1L || ("ADDL" %in% names(rows)&&any(rows$ADDL>0)) || ("SS" %in% names(rows)&&any(rows$SS>0))
    regular <- repeated && length(taus)==1L && !anyDuplicated(combos$CMT)
    basis <- "recorded-regimen";profile <- NULL;why <- if(repeated) "Actual recorded regimen; no identified regular steady-state schedule" else "Single recorded administration; no repeat interval invented"
    simulate <- function(ev,grid) {
      x <- as.data.frame(mrgsolve::mrgsim(mod,data=ev,idata=individual,tgrid=grid,
        outvars=unname(captures),etasrc=eta_source,obsonly=TRUE,recsort=2))
      for(role in names(captures)) x[[captures[[role]]]] <- convert[[role]](x[[captures[[role]]]])
      x
    }
    if(regular) {
      tau <- taus[1];start <- tau*50
      ev <- data.frame(ID=individual$ID,time=0,amt=combos$AMT,cmt=combos$CMT,evid=1L,ii=tau,addl=50L)
      if("RATE" %in% names(combos)) ev$rate <- combos$RATE
      profile <- simulate(ev,seq(start,start+tau,length.out=241))
      basis <- "steady-state";window <- tau;why <- "Recorded regular regimen; fixed 50 conditioning intervals"
    }
    if(is.null(profile)) {
      if(!is.finite(common_window)) {add_audit(id,"unavailable","No prediction window available; set PredictionWindowHours");next}
      start <- min(rows$TIME);window <- common_window
      ev <- rows[,intersect(event_names[!event_names %in% c("MDV","DVID","ENDPOINT")],names(rows)),drop=FALSE]
      names(ev) <- tolower(names(ev));names(ev)[names(ev)=="id"] <- "ID"
      ev <- ev[ev$time<=start+window,,drop=FALSE]
      profile <- simulate(ev,seq(start,start+window,length.out=241))
    }
    for(role in names(captures)) {
      values <- pmx_fit_profile_metrics(profile,captures[[role]],identity,start,window)
      if(!all(is.finite(values))) {add_audit(id,"unavailable",paste(role,"predictions unavailable"),basis,window);next}
      primary <- identical(role,names(captures)[1])
      metrics <- if(primary) c("Cmax","Cavg",if(basis=="steady-state") "Ctrough" else "Clast") else
        paste0(role,c("max","avg","end"))
      pieces[[length(pieces)+1L]] <- data.frame(ID=individual$ID,ROLE=role,METRIC=metrics,EXPO=unname(values),BASIS=basis,WINDOW_HOURS=window)
      add_audit(id,"available",paste(role,why),basis,window)
    }
  }
  log <- if(length(audit)) do.call(rbind,audit) else data.frame(ID=character(),Status=character(),Reason=character(),Basis=character(),Window_hours=numeric(),Window_source=character())
  dir.create(dirname(audit_file),recursive=TRUE,showWarnings=FALSE);write.csv(log,audit_file,row.names=FALSE,na="")
  message("EXPOSURE_REPORT ",paste(names(table(log$Status)),table(log$Status),sep="=",collapse=" "),"; ",audit_file)
  values <- if(length(pieces)) do.call(rbind,pieces) else data.frame(ID=idat$ID[FALSE],ROLE=character(),METRIC=character(),EXPO=numeric(),BASIS=character(),WINDOW_HOURS=numeric())
  list(values=values,audit=log,common_window=common_window,window_source=window_source,study_window=study_window)
}

# Keep numeric grouping cutpoints; show the actual finite range of each baseline group.
pmx_fit_range_groups <- function(x,breaks=NULL,reference=x,right=TRUE) {
  numeric <- function(z) suppressWarnings(as.numeric(as.character(z)))
  values <- numeric(x);ref <- numeric(reference);ref <- ref[is.finite(ref)]
  if(!length(ref) || length(unique(ref))<2L) return(factor(rep(NA_character_,length(values))))
  if(is.null(breaks)) breaks <- unique(as.numeric(stats::quantile(ref,c(0,.25,.5,.75,1),na.rm=TRUE)))
  if(length(breaks)<2L || anyNA(breaks) || any(diff(breaks)<=0)) stop("REPORT_COVARIATE_GROUPS_INVALID: ordered unique breakpoints required")
  ref_group <- cut(ref,breaks=breaks,right=right,include.lowest=TRUE,labels=FALSE)
  value_group <- cut(values,breaks=breaks,right=right,include.lowest=TRUE,labels=FALSE)
  groups <- sort(unique(ref_group[!is.na(ref_group)]))
  bounds <- lapply(groups,function(g) range(ref[ref_group==g]))
  for(digits in 4:15) {
    shown <- lapply(bounds,pmx_fit_format,digits=digits)
    labels <- vapply(seq_along(bounds),function(i)
      if(bounds[[i]][1]==bounds[[i]][2]) shown[[i]][1] else paste(shown[[i]],collapse="\u2013"),"")
    collapsed <- any(vapply(seq_along(bounds),function(i) diff(bounds[[i]])>0 && shown[[i]][1]==shown[[i]][2],TRUE))
    if(!anyDuplicated(labels) && !collapsed) break
  }
  factor(value_group,levels=groups,labels=labels)
}

# Descriptive display groups only; preserve all raw covariates and fitted effects.
pmx_fit_impact_groups <- function(variable,x,reference=x) {
  key <- toupper(variable);metadata <- pmx_fit_metadata()
  cuts <- NULL;spec <- metadata$spec
  if(!is.null(spec) && "group_cutpoints" %in% names(spec)) {
    rows <- spec$variable==key
    if("status" %in% names(spec)) rows <- rows & !is.na(spec$status) & spec$status=="confirmed"
    declared <- unique(na.omit(spec$group_cutpoints[rows]));declared <- declared[nzchar(trimws(declared))]
    if(length(declared)>1L) stop("REPORT_COVARIATE_GROUPS_INVALID: conflicting data_spec.csv cutpoints for ",key)
    if(length(declared)) cuts <- strsplit(trimws(declared),"[;,[:space:]]+")[[1]]
  }
  if(is.null(cuts)) {
    label <- unname(pmx_fit_covariate_labels(stats::setNames(key,key)))
    match <- regmatches(label,regexec("\\(([^()]*)\\)$",label))[[1]]
    unit <- if(length(match)==2L) tolower(gsub("[[:space:]^]","",gsub("\u00b2","2",match[2],fixed=TRUE))) else ""
    known <- switch(key,BW=unit %in% c("kg","kilogram","kilograms"),
      WTBL=unit %in% c("kg","kilogram","kilograms"),BMI=unit=="kg/m2",
      AGE=unit %in% c("years","year","yr","yrs","y"),CRCL=unit=="ml/min",FALSE)
    if(known) cuts <- switch(key,BW=c(60,80),WTBL=c(60,80),BMI=c(25,30),AGE=65,CRCL=c(30,60,90))
    else if(key %in% c("BW","WTBL","BMI","AGE")) {
      ref <- suppressWarnings(as.numeric(as.character(reference)));ref <- ref[is.finite(ref)]
      step <- switch(key,BW=10,WTBL=10,BMI=5,AGE=5)
      cuts <- if(length(ref)) unique(round(stats::quantile(ref,c(.25,.5,.75))/step)*step) else numeric()
      cuts <- cuts[cuts>min(c(ref,Inf)) & cuts<=max(c(ref,-Inf))]
    } else return(pmx_fit_range_groups(x,reference=reference))
  }
  cuts <- suppressWarnings(as.numeric(cuts))
  if(anyNA(cuts) || any(diff(cuts)<=0)) stop("REPORT_COVARIATE_GROUPS_INVALID: ordered unique numeric cutpoints required")
  cuts <- cuts[is.finite(cuts)]
  value <- suppressWarnings(as.numeric(as.character(x)));value[!is.finite(value)] <- NA_real_
  if(!length(cuts)) return(factor(ifelse(is.na(value),NA_character_,"All values")))
  shown <- format(cuts,trim=TRUE,scientific=FALSE)
  labels <- c(paste0("<",shown[1]),if(length(cuts)>1L) paste0(head(shown,-1),"\u2013<",tail(shown,-1)),paste0("\u2265",tail(shown,1)))
  droplevels(cut(value,breaks=c(-Inf,cuts,Inf),labels=labels,right=FALSE,include.lowest=TRUE))
}

pmx_fit_optimization_note <- function(fit) {
  warnings <- unique(c(as.character(unlist(fit$runInfo)),as.character(attr(fit,"pmx_fit_warnings"))))
  history <- any(grepl("(?:last|final) objective function (?:was|is) not at (?:a )?minimum",warnings,ignore.case=TRUE,perl=TRUE))
  if(!history) return(character())
  code <- fit$convergence
  if(is.numeric(code) && length(code) && all(is.finite(code) & code==0))
    "The optimizer exited normally but warned that the last objective-history entry was not the lowest. This diagnostic is retained; it does not establish optimization failure or model adequacy. Small model-selection differences and parameter uncertainty require caution, and covariance completion does not resolve the warning."
  else "The fit carries an objective-history warning without a verified normal optimizer exit. Its estimates require review; covariance completion does not establish convergence or model adequacy."
}

# Reject failed/separated regression fits before tables, BIC or fitted curves.
pmx_regression_checked <- function(expr) {
  warnings <- character()
  fit <- withCallingHandlers(expr,warning=function(w) {warnings <<- c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
  bad <- warnings[grepl("did not converge|failed to converge|converged before|coefficient may be infinite|coefficients may be infinite|probabilities numerically 0 or 1|ran out of iterations",warnings,ignore.case=TRUE)]
  if(inherits(fit,"glm") && (!isTRUE(fit$converged) || isTRUE(fit$boundary))) bad <- c(bad,"Binomial optimization failed or reached a boundary")
  if(inherits(fit,"glm") && identical(fit$family$family,"binomial") && all(is.finite(stats::coef(fit)))) {
    use <- fit$prior.weights>0
    y <- fit$y[use]
    direction <- as.numeric(stats::model.matrix(fit)[use,,drop=FALSE] %*% stats::coef(fit))
    if(length(y) && all(y %in% c(0,1)) && all((2*y-1)*direction>sqrt(.Machine$double.eps)))
      bad <- c(bad,"Complete separation: fitted coefficient direction strictly separates the binary outcomes")
  }
  if(any(!is.finite(stats::coef(fit))) || any(!is.finite(stats::vcov(fit)))) bad <- c(bad,"Non-finite/aliased coefficients or covariance")
  if(length(bad)) stop("REGRESSION_FIT_UNUSABLE: ",paste(unique(bad),collapse=" | "),call.=FALSE)
  attr(fit,"pmx_fit_warnings") <- warnings
  fit
}

# Study metadata changes presentation only; raw data and frozen model codes stay unchanged.
pmx_fit_metadata <- function(config=NULL) {
  if(is.null(config)) {
    root <- Sys.getenv("PMX_ROOT","");config <- file.path(if(nzchar(root)) root else getwd(),"pmx_config.R")
  }
  cfg <- new.env(parent=globalenv());if(file.exists(config)) sys.source(config,cfg)
  path <- file.path(dirname(config),"data_spec.csv")
  spec <- if(file.exists(path)) read.csv(path,colClasses="character",check.names=FALSE,
    na.strings=c("","NA"),stringsAsFactors=FALSE) else NULL
  if(!is.null(spec)) {
    required <- c("variable","label","type","unit","code","value_label")
    if(!all(required %in% names(spec))) stop("REPORT_DATA_SPEC_INVALID: required columns: ",paste(required,collapse=", "))
    spec$variable <- toupper(trimws(spec$variable))
    if(anyNA(spec$variable) || any(!nzchar(spec$variable))) stop("REPORT_DATA_SPEC_INVALID: variable required")
    coded <- !is.na(spec$code)
    if(anyDuplicated(paste(spec$variable[coded],spec$code[coded],sep="\r")))
      stop("REPORT_DATA_SPEC_INVALID: duplicate variable/code rows")
    for(v in unique(spec$variable)) for(field in c("label","unit","type")) {
      z <- unique(na.omit(spec[[field]][spec$variable==v]))
      if(length(z)>1L) stop("REPORT_DATA_SPEC_INVALID: inconsistent ",field," for ",v)
    }
  }
  levels <- if(exists("COV_LEVELS",cfg,inherits=FALSE)) cfg$COV_LEVELS else list()
  if(!is.list(levels) || (length(levels) && is.null(names(levels)))) stop("REPORT_COV_LEVELS_INVALID: named list required")
  names(levels) <- toupper(names(levels))
  for(v in names(levels)) if(is.null(names(levels[[v]])) || anyDuplicated(names(levels[[v]])))
    stop("REPORT_COV_LEVELS_INVALID: named unique codes required for ",v)
  if(!is.null(spec)) for(v in unique(spec$variable)) {
    rows <- spec$variable==v & !is.na(spec$code) & !is.na(spec$value_label)
    if("status" %in% names(spec)) rows <- rows & !is.na(spec$status) & tolower(spec$status)=="confirmed"
    if(any(rows)) {
      map <- stats::setNames(spec$value_label[rows],spec$code[rows])
      levels[[v]] <- c(map,levels[[v]][setdiff(names(levels[[v]]),names(map))])
    }
  }
  list(config=cfg,spec=spec,levels=levels,path=path)
}
pmx_fit_level_display <- function(variable,x,metadata=pmx_fit_metadata()) {
  x <- as.character(x);map <- metadata$levels[[toupper(variable)]]
  out <- x
  if(length(map)) {
    k <- match(x,names(map));use <- !is.na(k);out[use] <- unname(map[k[use]])
  }
  numeric_code <- !is.na(x) & grepl("^[+-]?[0-9]+(?:[.][0-9]+)?$",trimws(x),perl=TRUE)
  unresolved <- numeric_code & (is.null(map) | !x %in% names(map))
  if(any(unresolved)) stop("REPORT_CATEGORY_LABEL_REQUIRED: ",toupper(variable)," codes ",
    paste(unique(x[unresolved]),collapse=", ")," need confirmed data_spec.csv or COV_LEVELS labels; never guess")
  out
}
pmx_fit_category_group <- function(variable,x) {
  metadata <- pmx_fit_metadata();codes <- sort(unique(as.character(x[!is.na(x)])))
  factor(pmx_fit_level_display(variable,x,metadata),levels=unique(pmx_fit_level_display(variable,codes,metadata)))
}
# Shared labels/units for every fit-family summary; values are never converted.
pmx_fit_covariate_labels <- function(labels,config=NULL) {
  metadata <- pmx_fit_metadata(config);cfg <- metadata$config;spec <- metadata$spec
  named <- function(name) {
    x <- if(exists(name,cfg,inherits=FALSE)) get(name,cfg) else character()
    if(length(x) && (is.null(names(x)) || anyDuplicated(toupper(names(x))))) stop("REPORT_COVARIATE_LABELS_INVALID: named ",name," required")
    stats::setNames(as.character(x),toupper(names(x)))
  }
  custom <- named("COV_LABEL");units <- named("COV_UNIT")
  review <- if(exists("COVARIATE_REVIEW",cfg,inherits=FALSE)) cfg$COVARIATE_REVIEW else NULL
  for(v in names(labels)) {
    key <- toupper(v)
    if(key %in% names(custom) && !is.na(custom[[key]]) && nzchar(custom[[key]])) labels[[v]] <- custom[[key]]
    unit <- if(key %in% names(units)) units[[key]] else NA_character_
    if(is.na(unit) && is.data.frame(review) && "variable" %in% names(review)) {
      row <- review[toupper(review$variable)==key,,drop=FALSE]
      if(nrow(row)==1L) {
        if("unit" %in% names(row)) unit <- as.character(row$unit)
        else if(all(c("role","reason") %in% names(row)) && row$role=="continuous") {
          match <- regmatches(row$reason,regexec("\\([^()]*[0-9][[:space:]]+([^()]+)\\)[[:space:]]*$",row$reason))[[1]]
          if(length(match)==2L) unit <- trimws(match[2])
        }
      }
    }
    if(!is.null(spec)) {
      rows <- spec[spec$variable==key,,drop=FALSE]
      if(nrow(rows)) {
        title <- unique(na.omit(rows$label));declared_unit <- unique(na.omit(rows$unit[if("status" %in% names(rows)) !is.na(rows$status) & tolower(rows$status)=="confirmed" else rep(TRUE,nrow(rows))]))
        if(length(title)) labels[[v]] <- title[1]
        if(length(declared_unit)) unit <- declared_unit[1]
      }
    }
    if(length(unit)==1L && !is.na(unit) && nzchar(unit) && !grepl("\\([^()]+\\)$",labels[[v]]))
      labels[[v]] <- paste0(labels[[v]]," (",unit,")")
  }
  labels
}

# Decode displayed coefficient identifiers; retain run ids and frozen numeric values.
pmx_fit_term_labels <- function(text) {
  metadata <- pmx_fit_metadata();variables <- unique(c(names(metadata$levels),metadata$spec$variable))
  labels <- pmx_fit_covariate_labels(stats::setNames(variables,variables))
  vapply(as.character(text),function(line) {
    if(is.na(line)) return(NA_character_)
    pattern <- "theta_[A-Za-z0-9]+_[A-Za-z0-9_.]+(?==)"
    hits <- gregexpr(pattern,line,perl=TRUE);tokens <- regmatches(line,hits)[[1]]
    if(length(tokens)) regmatches(line,hits) <- list(vapply(tokens,function(token) {
      part <- strsplit(token,"_",fixed=TRUE)[[1]];target <- toupper(part[2]);key <- paste(part[-c(1,2)],collapse="_")
      for(v in variables[order(nchar(variables),decreasing=TRUE)]) {
        if(!startsWith(tolower(key),tolower(v))) next
        suffix <- substring(key,nchar(v)+1L)
        if(nzchar(suffix) && !v %in% names(metadata$levels)) next
        level <- if(nzchar(suffix)) paste0(": ",pmx_fit_level_display(v,suffix,metadata)) else ""
        return(paste0(labels[[v]],level," on ",target))
      }
      token
    },""))
    exact <- match(toupper(line),variables)
    if(!is.na(exact)) return(unname(labels[exact]))
    for(v in variables[grepl("^[A-Za-z][A-Za-z0-9_]*$",variables)])
      line <- gsub(paste0("\\b",v,"(?=\\s+on\\s|on[A-Za-z])"),labels[[v]],line,ignore.case=TRUE,perl=TRUE)
    line
  },"")
}

# D.2 is a native summary of the frozen final fit, not a second analysis job.
pmx_fit_output_text <- function(fit) {
  if(!requireNamespace("nlmixr2est",quietly=TRUE)) stop("WORD_FIT_OUTPUT_REQUIRED: nlmixr2est native printer is unavailable")
  old <- options(width=90,cli.width=90,cli.num_colors=1,cli.unicode=FALSE,crayon.enabled=FALSE)
  on.exit(options(old))
  text <- capture.output(print(fit))
  gsub("\033\\[[0-9;]*[[:alpha:]]","",text,perl=TRUE)
}
pmx_fit_output_word <- function(doc,fit) {
  style <- officer::fp_text(font.family="Courier New",font.size=8)
  for(line in pmx_fit_output_text(fit)) doc <- officer::body_add_fpar(doc,
    officer::fpar(officer::ftext(line,prop=style),fp_p=officer::fp_par(padding=0,line_spacing=1)))
  doc
}

pmx_fit_simulator_note <- function(dir=".") {
  candidates <- file.path(dir,c("table/_simulator_validation.json","02_html/table/_simulator_validation.json"))
  path <- candidates[file.exists(candidates)][1]
  if(is.na(path)) return(character())
  diagnostic <- jsonlite::read_json(path,simplifyVector=TRUE)
  if(!identical(diagnostic$state,"numerical_drift_verified")) return(character())
  "A tighter native solve at unchanged parameter estimates agreed with the report simulator. Prediction correction used the validated population reference; the original fitted estimates and uncertainty were retained."
}
