pmx_fit_targets <- function(family="ppk") {
  prefix <- if(family=="tmdd") "5.7" else "5.6"
  common <- c("5.1 Data","5.2 Base model","5.3 Covariate selection","5.4 Final model","5.5 Model evaluation")
  covariates <- paste0(prefix,".",seq_len(7)," ",c("Sex","Race","Age","Body weight",
    "BMI","Albumin","Renal function (creatinine clearance)"))
  c(common,covariates,if(family=="tmdd") c("5.6 Nonlinear pharmacokinetics","6.1 Predicted Receptor Occupancy"))
}
pmx_ppk_targets <- function() pmx_fit_targets("ppk")
# Result-backed prose only. Clinical conclusions must be supplied separately with current evidence.
pmx_report_asset <- function(dir,rel) {
  rel <- gsub("\\\\","/",rel)
  name <- basename(rel)
  if(!grepl("/",rel,fixed=TRUE) || grepl("^output/[^/]+$",rel)) {
    candidate <- if(name %in% c("report_results.rds","labels.csv","endpoints.csv","safety_endpoints.csv"))
      file.path(dir,"output",name) else if(grepl("^tbl_.*[.]csv$",name)) file.path(dir,"table","analysis",name) else ""
    if(nzchar(candidate) && file.exists(candidate)) return(candidate)
  }
  exact <- file.path(dir,rel)
  if(file.exists(exact)) return(exact)
  if(grepl("^(output|02_html)/[^/]+$",rel)) file.path(dir,name) else exact
}
pmx_result_bundle <- function(dir,family,data,ctl=NULL) {
  paths <- if(family %in% c("er","cqtc")) file.path(dir,c("output/report_results.rds","report_results.rds")) else
    file.path(dir,c("02_html/artifacts/s2/final.rds","artifacts/s2/final.rds"))
  paths <- paths[file.exists(paths)]
  if(!length(paths)) stop("Current structured report results are required; see word-report/README.md")
  path <- paths[1]; raw <- readRDS(path)
  out <- if(family %in% c("er","cqtc")) raw else raw$search
  if(is.null(out)) stop("Frozen result contract is incomplete")
  if(is.null(out$data_md5)) stop("Result has no input fingerprint; refresh the frozen result contract")
  if(!identical(as.character(out$data_md5),unname(tools::md5sum(data)))) stop("Results belong to different input data")
  if(family %in% c("er","cqtc")) {
    if(!identical(out$family,family) || !identical(out$schema,1L)) stop("Unsupported report result schema/family")
  } else if(!is.null(ctl) && file.exists(ctl) && !identical(readLines(ctl,warn=FALSE),out$ctl)) stop("Control stream differs from the frozen final result")
  if(family %in% c("ppk","pkpd","tmdd")) {
    out$family <- family
    out$section_results <- setNames(rep(list(character()),length(pmx_fit_targets(family))),pmx_fit_targets(family))
  }
  list(result=out,path=path,md5=unname(tools::md5sum(path)))
}
pmx_covariance_disclosure <- function(result) {
  # A mandatory, non-optional statement whenever uncertainty was not estimated.
  cov <- result$covariance
  if(!is.list(cov) || identical(cov$state,"complete")) return(character())
  if(is.character(cov$disclosure) && length(cov$disclosure) && nzchar(trimws(paste(cov$disclosure,collapse=" "))))
    return(paste(unlist(cov$disclosure,use.names=FALSE),collapse=" "))
  paste0("Model parameter uncertainty could not be estimated at the completed estimates of this run. ",
    "Standard errors, relative standard errors and confidence intervals are therefore not available and are ",
    "left blank; the point estimates and the model fit are unaffected, but the precision of the estimates ",
    "cannot be quantified from these results.")
}
pmx_result_prose <- function(bundle,family) {
  # Interpretation is authored from evidence; parameter tables already carry the numbers.
  pmx_covariance_disclosure(bundle$result)
}
# One gate for every consumer of the optional study prose: the Word generator
# and the HTML report must accept or reject report_narrative.json identically,
# otherwise the two deliverables can disagree about the same frozen results.
pmx_narrative_paragraphs <- function(v) {
  v <- unlist(v,use.names=FALSE)
  v[is.character(v) & !is.na(v) & nzchar(trimws(v)) &
    !grepl("\\[[^]]+\\]|not available|file not found|template slot|traceback|error:",v,ignore.case=TRUE)]
}
pmx_narrative_policy <- function(dir,family) {
  if(!family %in% c("ppk","pkpd","tmdd")) return(list(required=TRUE,reason=""))
  p <- file.path(dir,"report_metadata.dcf")
  mode <- "required";reason <- ""
  if(file.exists(p)) {
    m <- read.dcf(p)
    if(nrow(m)!=1L) stop("Report metadata must contain one record")
    if("Narrative" %in% colnames(m)) mode <- tolower(trimws(m[1,"Narrative"]))
    if("NarrativeReason" %in% colnames(m)) reason <- trimws(m[1,"NarrativeReason"])
  }
  if(!mode %in% c("required","omit")) stop("Narrative must be required or omit")
  if(mode=="omit" && (is.na(reason) || !nzchar(reason))) stop("Narrative omission requires the user's explicit request in NarrativeReason")
  list(required=mode!="omit",reason=reason)
}
pmx_required_result_targets <- function(dir,bundle) {
  if(!bundle$result$family %in% c("ppk","pkpd","tmdd")) return(character())
  common <- pmx_fit_targets(bundle$result$family)[seq_len(5L)]
  p <- file.path(dir,"output","report_evidence.json")
  e <- if(file.exists(p)) tryCatch(jsonlite::fromJSON(p,simplifyVector=FALSE),error=function(err) NULL) else NULL
  if(is.null(e) || !identical(e$source_md5,bundle$md5)) return(common)
  active <- vapply(e$references,function(r) if(is.null(r$section)) "" else r$section,"")
  unique(c(common,intersect(active,names(bundle$result$section_results))))
}
pmx_narrative_gate <- function(dir,bundle) {
  policy <- pmx_narrative_policy(dir,bundle$result$family)
  if(!policy$required) return(list(ok=FALSE,reason="NARRATIVE_OMITTED",sections=list()))
  p <- file.path(dir,"report_narrative.json")
  if(!file.exists(p)) return(list(ok=FALSE,reason="NARRATIVE_ABSENT",sections=list()))
  x <- tryCatch(jsonlite::fromJSON(p,simplifyVector=FALSE),error=function(e) {message("NARRATIVE_PARSE: ",conditionMessage(e)); NULL})
  if(is.null(x) || !identical(x$source_md5,bundle$md5)) {message("NARRATIVE_STALE: optional study prose omitted; refresh it from the current result"); return(list(ok=FALSE,reason="NARRATIVE_STALE",sections=list()))}
  if(!length(x$evidence)) {message("NARRATIVE_NO_EVIDENCE: optional study prose omitted"); return(list(ok=FALSE,reason="NARRATIVE_NO_EVIDENCE",sections=list()))}
  for(e in x$evidence) {
    if(is.null(e$file) || is.null(e$md5) || grepl("^(/|[A-Za-z]:)",e$file) || ".." %in% strsplit(gsub("\\\\","/",e$file),"/",fixed=TRUE)[[1]]) {message("NARRATIVE_BAD_EVIDENCE");return(list(ok=FALSE,reason="NARRATIVE_BAD_EVIDENCE",sections=list()))}
    file <- pmx_report_asset(dir,e$file)
    if(!file.exists(file) || !identical(unname(tools::md5sum(file)),e$md5)) {message("NARRATIVE_CHANGED_EVIDENCE: ",e$file); return(list(ok=FALSE,reason="NARRATIVE_CHANGED_EVIDENCE",sections=list()))}
  }
  if(isTRUE(bundle$result$family %in% c("er","cqtc","ppk","pkpd","tmdd")) &&
     (!is.list(x$sections) || any(vapply(c("Discussion","Conclusion"),function(nm)
       !length(pmx_narrative_paragraphs(x$sections[[nm]])),TRUE)))) {
    message("NARRATIVE_INCOMPLETE: both Discussion and Conclusion require supported paragraphs")
    return(list(ok=FALSE,reason="NARRATIVE_INCOMPLETE",sections=list()))
  }
  details <- if(is.null(x$section_results)) list() else x$section_results
  if(length(details)) {
    keys <- names(details)
    invalid <- !is.list(details) || is.null(keys) || any(!grepl(if(isTRUE(bundle$result$family %in% c("ppk","pkpd","tmdd"))) "^[56]([.][0-9]+)*[.]? +[^\\r\\n]+$" else "^4([.][0-9]+)*[.]? +[^\\r\\n]+$",keys,perl=TRUE))
    if(!invalid && isTRUE(bundle$result$family %in% c("er","ppk","pkpd","tmdd"))) invalid <- any(!keys %in% names(bundle$result$section_results))
    if(!invalid) invalid <- any(vapply(details,function(v) {
      all <- unlist(v,use.names=FALSE)
      !length(all) || length(pmx_narrative_paragraphs(v))!=length(all)
    },TRUE))
    if(invalid) {message("NARRATIVE_BAD_SECTION_RESULTS: review the current result-section targets");return(list(ok=FALSE,reason="NARRATIVE_BAD_SECTION_RESULTS",sections=list()))}
  }
  missing <- setdiff(pmx_required_result_targets(dir,bundle),names(details))
  if(length(missing)) {
    message("NARRATIVE_INCOMPLETE_RESULTS: ",paste(missing,collapse="; "))
    return(list(ok=FALSE,reason="NARRATIVE_INCOMPLETE_RESULTS",sections=list()))
  }
  list(ok=TRUE,reason="NARRATIVE_OK",source_md5=x$source_md5,sections=x$sections,section_results=details)
}
# Convenience for a study report (Rmd or script): NULL when the narrative is
# absent, stale, unverifiable or has no usable paragraph, so the caller falls
# back to its own result-backed prose instead of printing a placeholder.
pmx_narrative_sections <- function(dir,family,data,ctl=NULL) {
  bundle <- tryCatch(pmx_result_bundle(dir,family,data,ctl),error=function(e) {message("NARRATIVE_NO_RESULT: ",conditionMessage(e)); NULL})
  if(is.null(bundle)) return(NULL)
  gate <- pmx_narrative_gate(dir,bundle)
  if(!isTRUE(gate$ok)) return(NULL)
  keep <- intersect(names(gate$sections),c("Introduction","Objectives","ExposureMeasures","DataAssembly","DataHandling","Methods","CovariateAnalysis","Software","References","Discussion","Conclusion","DataSources","DatasetCreation","ConcentrationUnits","ECGEndpoint","MissingData","MissingPK","MissingQTc","DataDescription","DataExploration","BaseModel","FullModel","Diagnostics","Simulations"))
  out <- lapply(gate$sections[keep],function(v) {
    v <- unlist(v,use.names=FALSE)
    v[is.character(v) & !is.na(v) & nzchar(trimws(v)) & !grepl("\\[[^]]+\\]|not available|file not found|template slot|traceback|error:",v,ignore.case=TRUE)]
  })
  out <- out[vapply(out,length,0L)>0L]
  if(!length(out)) NULL else out
}
pmx_study_prose <- function(dir,bundle) {
  gate <- pmx_narrative_gate(dir,bundle)
  if(!isTRUE(gate$ok)) return(list())
  keep <- intersect(names(gate$sections),c("Introduction","Objectives","ExposureMeasures","DataAssembly","DataHandling","Methods","CovariateAnalysis","Software","References","Discussion","Conclusion","DataSources","DatasetCreation","ConcentrationUnits","ECGEndpoint","MissingData","MissingPK","MissingQTc","DataDescription","DataExploration","BaseModel","FullModel","Diagnostics","Simulations"))
  out <- lapply(gate$sections[keep],function(v) {
    v <- unlist(v,use.names=FALSE)
    v[is.character(v) & !is.na(v) & nzchar(trimws(v)) & !grepl("\\[[^]]+\\]|not available|file not found|template slot|traceback|error:",v,ignore.case=TRUE)]
  })
  out <- out[vapply(out,length,0L)>0L]
  if(length(gate$section_results)) out$SectionResults <- lapply(gate$section_results,pmx_narrative_paragraphs)
  out
}
