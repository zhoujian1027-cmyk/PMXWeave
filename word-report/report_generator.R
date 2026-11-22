#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(jsonlite))
.pmx_sd <- local({
  .fa <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), mustWork = FALSE)) else getwd()
})
.pmx_pl <- file.path(.pmx_sd, "preload_word_libs.R")
if (file.exists(.pmx_pl)) { source(.pmx_pl); pmx_preload_word_libs(file.path(.pmx_sd, "lib")) }
for (.p in c("officer","flextable")) {
  .msg <- tryCatch({suppressPackageStartupMessages(library(.p,character.only=TRUE)); NULL},
                   error=function(e) conditionMessage(e))
  if (!is.null(.msg)) {
    .so <- regmatches(.msg,regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*: cannot open shared object file",.msg))
    if (length(.so)) .so <- sub(":.*$","",.so)
    if (!length(.so)) .so <- regmatches(.msg,regexpr("[[:alnum:]_.+-]+\\.so(\\.[0-9]+)*",.msg))
    if (!length(.so)) .so <- "unknown"
    .hint <- switch(.so,
      "libwebpmux.so.3"   = "apt-get install -y libwebpmux3",
      "libwebpdemux.so.2" = "apt-get install -y libwebpdemux2",
      "rebuild the worker image with the missing system library")
    .line <- paste0("WORD_ENV_BROKEN pkg=",.p," missing=",.so,' fix="',.hint,'"')
    cat(.line,"\n")
    try(writeLines(.line,".word_env_broken"),silent=TRUE)
    stop(.line," -- Word assembly cannot start: worker-image environment failure, not a data or model ",
         "failure. Fix the image; resubmitting the same job cannot help.",call.=FALSE)
  }
}
rm(.p,.msg)
.gdir <- dirname(sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1]))
if (is.na(.gdir) || !nzchar(.gdir) ||
    !file.exists(file.path(.gdir,"family")) ||
    !file.exists(file.path(.gdir,"result_narrative.R"))) {
  stop("WORD_SCRIPT_COPY report_generator.R is not running from the toolkit directory (dir=",.gdir,
       "): a copied or hand-built script cannot see family/ or result_narrative.R, and arguments ",
       "appended to a copy are read after they are needed. Do NOT copy or hand-submit this script. ",
       "Use the study wrapper: sh analyses_template/tools/run_er.sh <dir> --word-only (or run_cqtc.sh) -- it stages the ",
       "toolkit, report_narrative.json + report_metadata.dcf into the job and publishes the .docx.",
       call.=FALSE)
}
rm(.gdir)
args <- commandArgs(trailingOnly=TRUE)
getarg <- function(key,default=NULL) {
  ix <- which(args==key)
  if(!length(ix)) return(default)
  if(length(ix)!=1L || ix==length(args)) stop("Missing/duplicate argument: ",key)
  args[ix+1L]
}
value_opts <- c("--family","--data","--out","--fig-dir","--table-dir","--ctl","--fit-log")
used <- unlist(lapply(value_opts,function(k) {i <- which(args==k); if(length(i)) c(i,i+1L)}))
pos <- args[setdiff(seq_along(args),c(used,which(args=="--no-figures")))]
if(length(pos)>1L || any(startsWith(pos,"--"))) stop("Unexpected Word arguments")
dir <- normalizePath(if(length(pos)) pos[1] else getwd(),mustWork=TRUE); setwd(dir)
if (!file.exists(".pmx_staged") && !file.exists(".pmx_run_state")) {
  cat("WORD_OUTSIDE_WRAPPER report_generator.R is running directly in ", dir,
      ": prefer the wrapper -- sh analyses_template/tools/run_er.sh <dir> --word-only (or run_cqtc.sh) stages ",
      "report_narrative.json + report_metadata.dcf + word-report/ itself and publishes the .docx. A ",
      "direct call must supply and publish those by hand.\n", sep = "")
}
filearg <- grep("^--file=",commandArgs(FALSE),value=TRUE)
if(!length(filearg)) stop("Use Rscript to invoke report_generator.R")
sd <- .pmx_sd # Resolve once before setwd(dir); relative invocation stays valid.
fam <- getarg("--family"); if(is.null(fam) || !fam %in% c("ppk","pkpd","tmdd","er","cqtc")) stop("Specify a supported --family")
spec <- new.env(); sys.source(file.path(sd,"family",paste0(fam,".R")),envir=spec); family <- spec$FAMILY
source(file.path(sd,"result_narrative.R"))
data <- getarg("--data",Sys.getenv("PMX_DATA","")); if(!nzchar(data) || !file.exists(data)) stop("Specify the real input with --data")
fitted_ctl <- file.path(dir,c("02_html/artifacts/s2/final_fitted.ctl","artifacts/s2/final_fitted.ctl","final_model.ctl"))
fitted_ctl <- fitted_ctl[file.exists(fitted_ctl)]
ctl <- getarg("--ctl",if(family$kind=="fit" && length(fitted_ctl)) fitted_ctl[1] else NULL)
if(family$kind=="fit") source(file.path(sd,"ppk_report_support.R"))
bundle <- pmx_result_bundle(dir,fam,data,ctl)
if(fam=="ppk") {
  cov_base <- tryCatch(as.matrix(bundle$result$base$cov),error=function(e) NULL)
  if(is.null(cov_base) || !nrow(cov_base) || any(!is.finite(cov_base)))
    stop("PPK_BASE_COVARIANCE_REQUIRED: complete base uncertainty in S1C using the saved fit; no base optimization")
}
prose <- pmx_result_prose(bundle,fam); study_prose <- pmx_study_prose(dir,bundle)
# Optional, study-overridable: one qualitative lead-in sentence per section.
# The engine offers section_leads.R; a study replaces or extends it with
# report_section_leads.R in the study directory, which may call section_lead_default().
section_lead <- local({
  load_lead <- function(path,parent=globalenv()) {
    if(!file.exists(path)) return(NULL)
    e <- new.env(parent=parent)
    ok <- tryCatch({sys.source(path,envir=e);TRUE},error=function(err) {message("SECTION_LEAD_SOURCE: ",conditionMessage(err));FALSE})
    if(!ok) return(NULL)
    f <- get0("section_lead",envir=e,mode="function")
    if(is.function(f)) f else NULL
  }
  eng <- load_lead(file.path(sd,"section_leads.R"))
  if(is.null(eng)) return(NULL)
  study <- load_lead(file.path(dir,"report_section_leads.R"),parent=environment(eng))
  if(is.null(study)) eng else study
})
tables <- getarg("--table-dir",file.path(dir,"table")); figures <- getarg("--fig-dir",file.path(dir,"figure"))
out <- getarg("--out",paste0(toupper(fam),"_report.docx"))
reference <- if(file.exists(file.path(dir,"reference.docx"))) file.path(dir,"reference.docx") else file.path(sd,"reference.docx")
if(!file.exists(reference)) stop("Word reference style is missing")
doc <- read_docx(reference)
# Keep reference styles, headers and footers; remove only its body.
for(i in seq_len(4L)) {
  summary <- officer::docx_summary(doc)
  if(!nrow(summary)) break
  first <- trimws(summary$text[1]); if(is.na(first)) first <- ""
  if(nzchar(first) && !first %in% c("base","x")) break
  doc <- officer::cursor_begin(doc); doc <- officer::body_remove(doc)
}
metadata <- list()
mp <- file.path(dir,"report_metadata.dcf")
if(file.exists(mp)) {m <- read.dcf(mp); metadata <- as.list(m[1,])}
clean <- function(v) length(v)==1L && !is.na(v) && nzchar(trimws(v)) && !grepl("\\[[^]]+\\]|xxxx|template slot|not available",v,ignore.case=TRUE)
paragraph <- function(doc,text,style="Normal") {
  text <- gsub("These are unadjusted quartile summaries with exact binomial intervals.","",text,fixed=TRUE)
  if(!clean(text)) return(doc)
  body_add_par(doc,trimws(text),style=style)
}
report_references <- list()
register_reference <- function(kind,number,caption,file=NULL) {
  report_references[[length(report_references)+1L]] <<- list(kind=kind,number=number,caption=caption,
    file=if(is.null(file)) NULL else basename(file),
    section=if(exists("si",envir=.GlobalEnv,inherits=FALSE)) sections[[get("si",envir=.GlobalEnv)]]$t else NULL)
}
heading <- function(doc,text,level=1L) paragraph(doc,text,paste0("heading ",min(level,3L)))
title <- if(clean(metadata$Title)) metadata$Title else family$title
doc <- paragraph(doc,title,"Title")
cover <- data.frame(Field=c("Analysis","Dataset","Date"),Entry=c(family$label,basename(data),format(Sys.Date(),"%d %b %Y")),stringsAsFactors=FALSE)
for(k in intersect(c("Project","Study","Drug","Indication","Prepared by"),names(metadata))) if(clean(metadata[[k]])) cover <- rbind(cover,data.frame(Field=k,Entry=metadata[[k]]))
reference_text_style <- function(file) {
  con <- unz(file,"word/styles.xml",open="rb")
  styles <- tryCatch(xml2::read_xml(con),finally=close(con))
  ns <- c(w="http://schemas.openxmlformats.org/wordprocessingml/2006/main")
  pick <- function(paths) {
    for(p in paths) {
      value <- xml2::xml_text(xml2::xml_find_all(styles,p,ns))
      if(length(value) && nzchar(value[1])) return(value[1])
    }
    NA_character_
  }
  normal <- "/w:styles/w:style[@w:styleId='Normal']/w:rPr/"
  default <- "/w:styles/w:docDefaults/w:rPrDefault/w:rPr/"
  family <- pick(c(paste0(normal,"w:rFonts/@w:ascii"),paste0(default,"w:rFonts/@w:ascii")))
  size <- suppressWarnings(as.numeric(pick(c(paste0(normal,"w:sz/@w:val"),paste0(default,"w:sz/@w:val"))))/2)
  list(family=if(is.na(family)) "Times New Roman" else family,size=if(is.finite(size) && size>0) size else 11)
}
REPORT_TEXT_STYLE <- reference_text_style(reference)
table_header <- function(x) {
  aliases <- c(EST="Estimate",CI_LB="CI lower",CI_UB="CI upper",DELTA="Delta BIC",sig="Retained")
  if(x %in% names(aliases)) x <- aliases[[x]]
  gsub("_"," ",x,fixed=TRUE)
}
wrap_label <- function(x,width) {
  if(is.na(x) || !nzchar(x)) return(x)
  indent <- regmatches(x,regexpr("^[ \\t\u00a0]*",x,perl=TRUE))
  x <- sub("\\s+(?=\\(N\\s*=)","\n",x,perl=TRUE)
  x <- sub("\\s+(?=median \\[min, max\\])","\n",x,perl=TRUE)
  lines <- unlist(lapply(strsplit(x,"\n",fixed=TRUE)[[1]],function(line) strwrap(line,width=width)))
  paste0(indent,paste(lines,collapse="\n"))
}
add_table <- function(doc,d,caption=NULL,font_size=NULL,bold_prefixes=NULL,indent_rows=NULL) {
  if(is.null(d) || !nrow(d) || !ncol(d)) return(doc)
  is_er_demography <- !is.null(caption) &&
    ((family$id=="er" && grepl("patient demographics|disease characteristics.*baseline",caption,ignore.case=TRUE)) ||
     (family$id=="cqtc" && grepl("summary of demographic",caption,ignore.case=TRUE)) ||
     (family$kind=="fit" && grepl("summary of patient characteristics",caption,ignore.case=TRUE)))
  if(is_er_demography) for(column in intersect(c("Covariate","Covariates","Characteristic"),names(d)))
    d[[column]] <- sub("[[:space:]]+(?:median \\[min, max\\]|n \\(%\\))$","",d[[column]],perl=TRUE)
  is_er_parameter <- family$id=="er" && "Parameter" %in% names(d) && !is.null(caption) &&
    grepl("parameter estimates|base model|full model",caption,ignore.case=TRUE)
  is_er_safety <- family$id=="er" && "Endpoint" %in% names(d) && !is.null(caption) &&
    grepl("summary of exposure.safety endpoints",caption,ignore.case=TRUE)
  d[] <- lapply(d,function(x) {if(is.numeric(x)) x[!is.finite(x)] <- NA_real_; x})
  is_fit_parameter <- family$kind=="fit" && identical(names(d),
    c("Parameter","Description","Estimate","%RSE","Shrinkage (%)"))
  group_rows <- if(is_fit_parameter)
    which(!nzchar(d$Description) & !nzchar(d$`Estimate`) &
      grepl("^(Fixed Effects|Covariate Effects|Interindividual Variability|Residual Variability)",d$Parameter)) else integer()
  parameter_headings <- if(is_fit_parameter) which(d$Parameter=="Parameter" & startsWith(d$Estimate,"Estimate")) else integer()
  labels <- names(d)[tolower(trimws(names(d))) %in% c("covariate","covariates","variables","characteristic","parameter","term","disposition","definition","metric","description","parameter description","endpoint")]
  headers <- vapply(names(d),table_header,"")
  if(is_fit_parameter) headers[headers=="%RSE"] <- "RSE (%)"
  longest <- max(c(0,nchar(unlist(lapply(d,as.character)))),na.rm=TRUE)
  dense <- ncol(d)>=8 || (ncol(d)>=6 && longest>90) || (nrow(d)>35 && ncol(d)>=5)
  if(is.null(font_size)) font_size <- if(dense) max(8,REPORT_TEXT_STYLE$size-2) else REPORT_TEXT_STYLE$size
  max_width <- 6.2
  tokens <- vapply(headers,function(h) {w <- strsplit(h,"[[:space:]]+")[[1]];w[which.max(nchar(w))]},"")
  token_data <- as.data.frame(as.list(setNames(tokens,names(d))),check.names=FALSE)
  repeat {
    probe <- flextable(token_data)
    probe <- set_header_labels(probe,values=as.list(setNames(tokens,names(d))))
    probe <- font(probe,fontname=REPORT_TEXT_STYLE$family,part="all")
    probe <- fontsize(probe,size=font_size,part="all");probe <- bold(probe,part="header")
    probe <- padding(probe,padding=3,part="all")
    minimum <- pmax(.42,dim_pretty(probe)$widths)
    if(sum(minimum)<=max_width || font_size<=8) break
    font_size <- max(8,font_size-1)
  }
  text_min <- if(ncol(d)<=3) 2.4 else 1.7
  label_index <- match(labels,names(d))
  candidate_min <- minimum;candidate_min[label_index] <- pmax(candidate_min[label_index],text_min)
  if(sum(candidate_min)<=max_width) minimum <- candidate_min
  ft <- flextable(d);ft <- set_header_labels(ft,values=as.list(setNames(headers,names(d))))
  ft <- font(ft,fontname=REPORT_TEXT_STYLE$family,part="all")
  ft <- fontsize(ft,size=font_size,part="all");ft <- bold(ft,part="header")
  ft <- padding(ft,padding=3,part="all")
  cap <- rep(if(ncol(d)<=3) 4.2 else 2,ncol(d))
  cap[label_index] <- if(ncol(d)<=3) 4.2 else 2.7
  desired <- pmax(minimum,pmin(dim_pretty(ft)$widths,cap))
  if(sum(minimum)>max_width) {
    widths <- max_width*minimum/sum(minimum)
  } else if(sum(desired)>max_width) {
    extra <- desired-minimum
    widths <- minimum+(max_width-sum(minimum))*extra/sum(extra)
  } else widths <- desired
  if(is_er_demography && length(label_index)==1L && sum(minimum)<=max_width) {
    # Measure actual values as well as labels; use the whole page without hard line breaks.
    desired <- pmax(minimum,dim_pretty(ft)$widths+.08)
    if(sum(desired)<=max_width) widths <- desired+(max_width-sum(desired))/ncol(d)
    else {
      extra <- desired-minimum
      widths <- minimum+(max_width-sum(minimum))*extra/sum(extra)
    }
  }
  if(is_er_safety && identical(names(d),c("Endpoint","N","Events","Patients (%)"))) {
    candidate <- pmax(minimum,c(3.6,.5,.6,1.5));candidate[1] <- candidate[1]-(sum(candidate)-max_width)
    if(candidate[1]>=minimum[1]) widths <- candidate
  }
  if(is_er_parameter && identical(names(d),c("Parameter","Estimate","SE (RSE%)","95% CI","P value"))) {
    candidate <- pmax(minimum,c(3.2,.65,.8,1.1,.45));candidate[1] <- candidate[1]-(sum(candidate)-max_width)
    if(candidate[1]>=minimum[1]) widths <- candidate
  }
  median_col <- grep("^Median .*months, 95% CI",names(d))
  if(length(median_col)==1L && ncol(d)==4L) widths <- c(1.25,.6,.65,3.7)
  if(is_fit_parameter)
    widths <- c(1.3,1.35,1.65,.75,1.15)
  group_text <- if(length(group_rows)) as.character(d$Parameter[group_rows]) else character()
  for(j in label_index) {
    keep_line <- is_er_demography || is_fit_parameter || (is_er_parameter && names(d)[j]=="Parameter") || (is_er_safety && names(d)[j]=="Endpoint")
    d[[j]] <- if(keep_line) gsub("[[:cntrl:]]+"," ",as.character(d[[j]])) else
      vapply(as.character(d[[j]]),wrap_label,"",width=max(16,floor(widths[j]*12*11/font_size)))
  }
  if(length(group_rows)) d$Parameter[group_rows] <- group_text
  if(!is_er_demography && !is_fit_parameter) headers <- vapply(seq_along(headers),function(j) paste(strwrap(headers[j],width=max(6,floor(widths[j]*12*11/font_size))),collapse="\n"),"")
  ft <- flextable(d);ft <- set_header_labels(ft,values=as.list(setNames(headers,names(d))))
  ft <- font(ft,fontname=REPORT_TEXT_STYLE$family,part="all")
  ft <- fontsize(ft,size=font_size,part="all");ft <- align(ft,align="center",part="all")
  if(length(labels)) ft <- align(ft,j=labels,align="left",part="all")
  ft <- valign(ft,valign="center",part="all")
  ft <- bold(ft,part="header");ft <- bg(ft,bg="#E9EFF5",part="header")
  ft <- padding(ft,padding=3,part="header")
  ft <- padding(ft,padding.top=2,padding.bottom=2,padding.left=4,padding.right=4,part="body")
  if(length(indent_rows) && length(labels)) ft <- padding(ft,i=indent_rows,j=labels[1],
    padding.left=4+font_size/2,part="body")
  ft <- width(ft,width=widths)
  if(length(bold_prefixes)) for(style in bold_prefixes) {
    i <- as.integer(style$row);j <- as.character(style$column);prefix <- as.character(style$prefix)
    if(length(i)==1 && is.finite(i) && i>=1 && i<=nrow(d) && j %in% names(d) && nzchar(prefix)) {
      text <- as.character(d[[j]][i])
      if(!is_er_demography && !(is_er_parameter && j=="Parameter") && !(is_er_safety && j=="Endpoint"))
      prefix <- paste(strwrap(prefix,width=max(16,floor(widths[match(j,names(d))]*12*11/font_size))),collapse="\n")
      if(startsWith(text,prefix)) ft <- compose(ft,i=i,j=j,value=as_paragraph(
        as_chunk(prefix,props=officer::fp_text(bold=TRUE,font.size=font_size,font.family=REPORT_TEXT_STYLE$family)),
        as_chunk(substring(text,nchar(prefix)+1))),part="body")
    }
  }
  if(is_fit_parameter) {
    for(row in setdiff(which(!nzchar(d$Description)),group_rows)) ft <- merge_at(ft,i=row,j=1:2,part="body")
    for(row in parameter_headings) {
      ft <- bold(ft,i=row,part="body");ft <- bg(ft,i=row,bg="#E9EFF5",part="body")
    }
  }
  for(row in group_rows) {
    ft <- merge_at(ft,i=row,j=seq_len(ncol(d)),part="body")
    ft <- bold(ft,i=row,bold=TRUE,part="body")
    ft <- align(ft,i=row,align="left",part="body")
  }
  ft <- set_table_properties(ft,layout="fixed",width=1,opts_word=list(split=FALSE,repeat_headers=TRUE))
  if(is_er_demography) {
    ft <- add_footer_lines(ft,values="Continuous variables are presented as median [min, max], while categorical variables are presented as n (%) of patients with nonmissing values. Missing values are reported separately.")
    ft <- font(ft,fontname=REPORT_TEXT_STYLE$family,part="footer")
    ft <- fontsize(ft,size=font_size,part="footer")
    ft <- align(ft,align="left",part="footer")
  }
  if(family$kind=="fit" && "Estimate" %in% names(d)) {
    ft <- add_footer_lines(ft,values=pmx_fit_parameter_note(d))
    ft <- font(ft,fontname=REPORT_TEXT_STYLE$family,part="footer")
    ft <- fontsize(ft,size=font_size,part="footer");ft <- align(ft,align="left",part="footer")
  }
  if(clean(caption)) {
    doc <- paragraph(doc,caption,"Caption")
    if(grepl("^Table [0-9]+[.:]",caption)) register_reference("table",as.integer(sub("^Table ([0-9]+).*","\\1",caption)),caption)
  }
  body_add_flextable(doc,ft)
}
method_paragraph <- function(doc,text) {
  if(!clean(text)) return(doc)
  equation <- grepl("^\\s*(logit\\s*\\(|h\\s*\\(t\\))[^:]*=",text,perl=TRUE)
  if(family$kind=="fit") equation <- equation || grepl("^(θ_i|C_obs,ij|η-shrinkage)\\s*=",text,perl=TRUE)
  note <- grepl("^\\s*(P_?i|β[012]|COV_?i|h0?\\(t\\))\\s*:",text,perl=TRUE)
  if(family$kind=="fit") note <- note || grepl("^(θ_i|θ_T|η_i|Cov_i|Cov_ref|k_cov|C_obs,ij and C_pred,ij|ε_prop,ij and ε_add,ij|SD\\(η_i\\)|ω)\\s*:",text,perl=TRUE)
  if(!equation && !note) return(paragraph(doc,text))
  safe <- gsub("&","&amp;",text,fixed=TRUE)
  safe <- gsub("<","&lt;",safe,fixed=TRUE);safe <- gsub(">","&gt;",safe,fixed=TRUE)
  props <- if(equation) '<w:jc w:val="center"/><w:keepNext/><w:spacing w:before="120" w:after="120"/>' else
    '<w:jc w:val="left"/><w:ind w:left="360" w:firstLine="0"/><w:spacing w:before="0" w:after="40"/>'
  body_add_xml(doc,paste0('<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    '<w:pPr><w:pStyle w:val="Normal"/>',props,'</w:pPr><w:r>',if(equation) '<w:rPr><w:b/></w:rPr>' else '',
    '<w:t xml:space="preserve">',safe,'</w:t></w:r></w:p>'))
}

doc <- add_table(doc,cover)
doc <- body_add_break(doc)
doc <- heading(doc,"Table of Contents"); doc <- body_add_par(doc,"[[PMX_TOC:1-3]]",style="Normal")
result <- bundle$result
fit_methods <- if(family$kind=="fit")
  c(pmx_fit_data_sections(data,result,fam,metadata),pmx_fit_method_sections(result,fam)) else list()
label_file <- pmx_report_asset(dir,"labels.csv")
report_labels <- if(file.exists(label_file)) read.csv(label_file,stringsAsFactors=FALSE) else data.frame()
generic_drug <- nrow(report_labels)>0 && any(report_labels$key=="DRUG" & tolower(trimws(report_labels$value))=="drug")
er_source_data <- if(fam=="er") read.csv(data,check.names=FALSE,stringsAsFactors=FALSE) else NULL
er_abbreviations <- c(MRD="Measurable residual disease", OR="Odds ratio", ORR="Objective response rate",
  OS="Overall survival", PFS="Progression-free survival", PK="Pharmacokinetic(s)",
  SAE="Serious adverse event", TEAE="Treatment-emergent adverse event", TRAE="Treatment-related adverse event")
section_key <- c("1. Introduction"="Introduction", "2. Objectives"="Objectives",
  "3.2 Exposure Measures"="ExposureMeasures", "3.3 Data Assembly"="DataAssembly",
  "3.4 Data Handling"="DataHandling", "3.5 Exposure-Response Analysis and Modelling Methods"="Methods",
  "3.5.1 Covariate Analysis"="CovariateAnalysis", "3.5.2 Software"="Software", "7. References"="References")
if(fam=="cqtc") section_key <- c(section_key,
  "2. Data"="DataSources",
  "2.1. Dataset Creation Methods"="DatasetCreation","2.1.1. Concentration Units"="ConcentrationUnits",
  "2.1.2. ECG Endpoint"="ECGEndpoint","2.2. Handling of Missing Data"="MissingData",
  "2.2.1. Missing Pharmacokinetic Data"="MissingPK","2.2.2. Missing Safety Data"="MissingQTc",
  "3. Methodology"="Methods","3.1. Software and Hardware"="Software",
  "4.1. Data Description"="DataDescription","4.2.1. Data Exploration"="DataExploration",
  "4.2.2. Base Model"="BaseModel","4.2.3. Full Model"="FullModel",
  "4.2.4. Diagnostics"="Diagnostics","4.2.5. Simulations"="Simulations")
section_text <- function(title) {
  text <- study_prose$SectionResults[[title]]
  if(!length(text)) {
    text <- result$section_results[[title]]
    if(fam=="er" && grepl("^4[.]3[.][0-9]+ ",title) && length(text) &&
       any(grepl("Exposure curves, where available, are exploratory unadjusted fits",unlist(text),fixed=TRUE)))
      text <- paste0("[Exposure-safety trend for ",sub("^4[.]3[.][0-9]+ +","",title),": interpretation pending.]")
    if(fam=="er" && grepl("Graphical analyses for ",title,fixed=TRUE) &&
       any(grepl("Graphical analyses were conducted|Kaplan-Meier plots and median",unlist(text))))
      text <- paste0("[Exposure-response trend for ",sub(".* Graphical analyses for ","",title),": interpretation pending.]")
    if(fam=="er" && grepl(" regression for ",title,fixed=TRUE) && length(text) &&
       startsWith(text[1],"The base model contains exposure only. The full model adds covariates"))
      text[1] <- paste0("[Regression effects for ",sub(".* regression for ","",title),": interpretation pending.]")
  }
  if(length(text)) return(unlist(text,use.names=FALSE))
  if(family$kind=="fit" && length(fit_methods[[title]])) return(fit_methods[[title]])
  key <- unname(section_key[title]); if(is.na(key)) return(character())
  text <- study_prose[[key]]
  if(!length(text) && fam %in% c("er","cqtc")) text <- result$report_sections[[key]]
  unlist(text,use.names=FALSE)
}
# Tables and figures are keyed by their manifest, never by fixed positional numbers.
read_manifest <- function(path) {if(file.exists(path)) read.csv(path,check.names=FALSE,stringsAsFactors=FALSE) else data.frame()}
tm <- read_manifest(file.path(tables,"_html_tables.csv")); fm <- read_manifest(file.path(figures,"_html_figures.csv"))
html_only_assets <- character()
if(fam=="cqtc") {
  if(nrow(tm)) {
    key <- paste(tm$section,tm$caption)
    omit <- grepl("concentration.?qtc.*relationship.*goodness.of.fit",key,ignore.case=TRUE)
    html_only_assets <- c(html_only_assets,file.path(tables,tm$file[omit]))
    tm <- tm[!omit,,drop=FALSE]
  }
  if(nrow(fm)) {
    caption <- if("caption" %in% names(fm)) fm$caption else rep("",nrow(fm))
    key <- paste(fm$section,caption)
    omit <- grepl("hysteresis|qtc.*visit.*tumou?r type",key,ignore.case=TRUE)
    html_only_assets <- c(html_only_assets,file.path(figures,fm$file[omit]))
    fm <- fm[!omit,,drop=FALSE]
  }
}
if(family$kind=="fit") {
  policy <- pmx_fit_word_figures(fm)
  html_only_assets <- c(html_only_assets,file.path(figures,policy$omitted))
  fm <- policy$keep
}
if(family$kind=="fit") {
  if(fam=="ppk" && nrow(tm)) tm <- tm[!grepl("candidate model screening history",tm$caption,ignore.case=TRUE),,drop=FALSE]
  if(nrow(fm)) {
    if(nrow(fm)) {
      html <- file.path(dir,paste0(fam,"_report.html"))
      if(!file.exists(html) || !all(c("source_html_md5","image_md5") %in% names(fm)))
        stop("WORD_HTML_FIGURES_REQUIRED: extract the current HTML in S3; do not fit again")
      if(anyNA(fm$source_html_md5) || any(fm$source_html_md5!=unname(tools::md5sum(html))))
        stop("WORD_HTML_FIGURES_STALE: refresh HTML extraction only")
      for(i in seq_len(nrow(fm))) {
        if(basename(fm$file[i])!=fm$file[i] || !file.exists(file.path(figures,fm$file[i])) ||
           !identical(as.character(fm$image_md5[i]),unname(tools::md5sum(file.path(figures,fm$file[i])))))
          stop("WORD_HTML_FIGURE_CHANGED: ",fm$file[i],"; refresh extraction, never refit")
      }
    }
  }
}

# Cover, control and abbreviation tables are front matter: this generator builds
# the cover and the table of contents itself, so those rows are emitted once,
# directly after the contents, instead of being routed into a results section.
front_rows <- if(nrow(tm)) {
  key <- paste(if("section" %in% names(tm)) as.character(tm$section) else "",
               if("caption" %in% names(tm)) as.character(tm$caption) else "")
  which(grepl("^(title page|list of abbreviations|list of tables|list of figures|report control)$",
              trimws(if("section" %in% names(tm)) as.character(tm$section) else ""),ignore.case=TRUE) |
        grepl("report control|list of abbreviations|list of tables|list of figures",key,ignore.case=TRUE))
} else integer()
safe_asset <- function(base,file) {
  if(!clean(file) || basename(file)!=file) stop("Manifest asset must be a filename")
  path <- file.path(base,file); if(!file.exists(path)) stop("Manifest asset is missing: ",file)
  path
}
# Restore each family's original numbered heading tree. Existing content is only relocated.
sections <- family$sections
section_title <- function(text) {
  if(grepl("[DRUG]",text,fixed=TRUE)) {
    drug <- if(clean(metadata$Drug)) metadata$Drug else ""
    text <- gsub("[DRUG]",drug,text,fixed=TRUE)
    text <- gsub("[[:space:]]+"," ",text)
  }
  text
}
normal_title <- function(x) {
  x <- sub("^[0-9]+([.][0-9]+)*[.]?[[:space:]]*","",x)
  trimws(gsub("[^a-z0-9]+"," ",tolower(x)))
}
# ER endpoints remain study-driven, following the old 4.2.x / 4.3.x layout.
if(fam=="er") {
  result_asset <- function(name) pmx_report_asset(dir,name)
  efficacy <- read_manifest(result_asset("endpoints.csv"))
  safety <- read_manifest(result_asset("safety_endpoints.csv"))
  endpoint_titles <- function(manifest) {
    if(!nrow(manifest) || !all(c("section","label") %in% names(manifest))) return(character())
    paste(manifest$section,manifest$label)
  }
  dynamic <- unique(c(endpoint_titles(efficacy),as.character(efficacy$sec_plot),
                      as.character(efficacy$sec_model),endpoint_titles(safety),as.character(safety$sec_model),
                      as.character(tm$section),as.character(fm$section)))
  dynamic <- dynamic[!is.na(dynamic) & grepl("^4[.][23][.][0-9]+",dynamic)]
  dynamic <- dynamic[!duplicated(sub("[[:space:]].*$","",dynamic))]
  for(parent in c("4.2","4.3")) {
    titles <- dynamic[startsWith(dynamic,paste0(parent,"."))]
    if(!length(titles)) next
    numbers <- sub("[[:space:]].*$","",titles)
    parts <- strsplit(numbers,".",fixed=TRUE)
    order_key <- vapply(parts,function(v) paste(sprintf("%06d",as.integer(v)),collapse="."),"")
    titles <- titles[order(order_key)]
    extra <- lapply(titles,function(t) list(h=length(strsplit(sub("[[:space:]].*$","",t),".",fixed=TRUE)[[1]]),t=t))
    position <- which(vapply(sections,function(x) startsWith(x$t,paste0(parent," ")),TRUE))
    if(length(position)) sections <- append(sections,extra,after=position[1])
  }
}
find_section <- function(prefix) {
  hit <- which(vapply(sections,function(x) identical(x$t,prefix) || startsWith(x$t,paste0(prefix," ")),TRUE))
  if(length(hit)) hit[1] else NA_integer_
}
route_asset <- function(section,caption="") {
  text <- paste(section,caption)
  text[is.na(text)] <- ""
  text <- paste(text,collapse=" ")
  if(fam=="cqtc") {
    key <- normal_title(text)
    prefix <- if(grepl("outlier|visit|time profiles|hysteresis|binned means",key)) "4.2.1." else
      if(grepl("diagnostic|goodness of fit|model statistics|final model",key)) "4.2.4." else
      if(grepl("covariate|full model",key)) "4.2.3." else
      if(grepl("base model|fixed effect parameters|random effect parameters",key)) "4.2.2." else
      if(grepl("simulation",key)) "4.2.5." else ""
    if(nzchar(prefix)) return(find_section(prefix))
  }
  if(fam=="er" && grepl("demographics|disease characteristics.*baseline",caption,ignore.case=TRUE)) return(find_section("4.1"))
  if(fam=="ppk" && grepl("covariate search run record|scm run record",caption,ignore.case=TRUE)) return(find_section("Appendix C:"))
  if(fam=="er" && grepl("summary of exposure metrics",caption,ignore.case=TRUE)) return(find_section("3.2"))
  if(family$kind=="fit" && grepl("model structure",text,ignore.case=TRUE)) return(find_section("5.2"))
  if(!is.na(section) && nzchar(section)) {
    hit <- which(vapply(sections,function(x) identical(trimws(x$t),trimws(section)),TRUE))
    if(length(hit)) return(hit[1])
  }
  # Studies usually number the appendix ("Appendix 1: Analysis Populations and
  # Disposition") while the family tree keeps it unnumbered, so neither the exact
  # nor the normalised title match fires. Match the prefix before any keyword
  # fallback, otherwise appendix tables land in the first results section.
  if(grepl("^appendix",text,ignore.case=TRUE)) {
    hit <- which(vapply(sections,function(x) grepl("^appendix[[:space:]]+[0-9]+",x$t,ignore.case=TRUE),TRUE))
    if(!length(hit)) hit <- which(vapply(sections,function(x) grepl("^appendix",x$t,ignore.case=TRUE),TRUE))
    if(length(hit)) return(hit[1])
  }
  if(family$kind=="regression" && !is.na(section) && nzchar(section)) {
    hit <- which(vapply(sections,function(x) identical(normal_title(x$t),normal_title(section)),TRUE))
    if(length(hit)) return(hit[1])
  }
  if(family$kind=="fit") {
    if(grepl("(?:model.predicted(?: steady.state)?|steady.state|observed.regimen) (?:(?:PK|drug) exposure|(?:PD|target) response|exposure) by",caption,ignore.case=TRUE,perl=TRUE)) {
      mapping <- c("sex"="5.6.1","race"="5.6.2","age"="5.6.3",
        "body weight"="5.6.4","bmi"="5.6.5","albumin"="5.6.6","creatinine clearance"="5.6.7")
      variable <- sub("^.*(?:model.predicted(?: steady.state)?|steady.state|observed.regimen) (?:(?:PK|drug) exposure|(?:PD|target) response|exposure) by[[:space:]]+","",caption,ignore.case=TRUE,perl=TRUE)
      hits <- mapping[vapply(names(mapping),function(v) grepl(paste0("\\b",v,"\\b"),tolower(variable),perl=TRUE),TRUE)]
      if(fam=="tmdd") hits <- sub("^5[.]6","5.7",hits)
      if(length(hits)==1L) return(find_section(unname(hits)))
    }
    if(grepl("dataset summary|patient characteristics|demographic|laboratory",text,ignore.case=TRUE))
      return(find_section("5.1"))
    prefix <- if(grepl("occupancy",text,ignore.case=TRUE) && fam=="tmdd") "6.1" else
      if(grepl("nonlinear|dose.normalized",text,ignore.case=TRUE) && fam=="tmdd") "5.6" else
      if(grepl("steady.state|observed.regimen|exposure versus|exposure vs|exposure.by|impact of covariates",text,ignore.case=TRUE)) if(fam=="tmdd") "5.7" else "5.6" else
      if(grepl("covariate search|scm|stepwise|covariate summary|demographic|laboratory|patient characteristics",text,ignore.case=TRUE)) "5.3" else
      if(grepl("base model|base parameter|candidate model screening",text,ignore.case=TRUE)) "5.2" else
      if(grepl("goodness.of.fit|diagnostic|vpc|bootstrap|shrinkage|individual fit|ebe distribution",text,ignore.case=TRUE)) "5.5" else
      if(grepl("parameter|estimate",text,ignore.case=TRUE)) "5.4" else
      if(grepl("data|sample|concentration.time|mean.*dose|covariate correlation",text,ignore.case=TRUE)) "5.1" else "5."
    if(prefix=="5.") return(find_section("5."))
  } else if(fam=="er") {
    prefix <- if(grepl("safety|adverse",text,ignore.case=TRUE)) "4.3" else
      if(grepl("efficacy|response|logistic|cox|hazard",text,ignore.case=TRUE)) "4.2" else
      if(grepl("exposure measures",text,ignore.case=TRUE)) "3.2" else
      if(grepl("study|studies|regimen",text,ignore.case=TRUE)) "3.1" else "4.1"
  } else {
    prefix <- if(grepl("software|hardware",text,ignore.case=TRUE)) "3.1." else
      if(grepl("study|studies|dosing regimen",text,ignore.case=TRUE)) "2." else
      if(grepl("disposition|demographic|characteristic|data description",text,ignore.case=TRUE)) "4.1." else "4.2."
  }
  find_section(prefix)
}
if(fam=="er" && length(unlist(result$covariates[c("continuous","categorical")])) &&
   !any(grepl("demographics|disease characteristics.*baseline",tm$caption,ignore.case=TRUE)))
  stop("ER_POPULATION_TABLE_MISSING: baseline summary was not extracted from HTML; repair its HTML table markup/export, not repeated Word rendering")
table_sections <- if(nrow(tm)) vapply(seq_len(nrow(tm)),function(i) route_asset(tm$section[i],tm$caption[i]),0L) else integer()
figure_sections <- if(nrow(fm)) vapply(seq_len(nrow(fm)),function(i) route_asset(fm$section[i],if("caption" %in% names(fm)) fm$caption[i] else ""),0L) else integer()
structure_figures <- if(family$kind=="fit" && nrow(fm))
  which(grepl("model structure",paste(fm$section,if("caption" %in% names(fm)) fm$caption else ""),ignore.case=TRUE)) else integer()
if(family$kind=="fit" && !"--no-figures" %in% args) {
  if(!length(structure_figures)) stop("WORD_MODEL_STRUCTURE_REQUIRED: refresh the family Rmd and resume from S4 to render/extract its base model structure; do not refit")
  dimensions <- suppressWarnings(as.numeric(unlist(fm[structure_figures,c("width_px","height_px")],use.names=FALSE)))
  if(any(!is.finite(dimensions) | dimensions<=0)) stop("WORD_MODEL_STRUCTURE_REQUIRED: invalid structure image dimensions; refresh S4/S3, not fitting")
}
table_no <- 0L; figure_no <- 0L; emitted_figures <- integer()
display_caption <- function(text) {
  text <- sub("^(Table|Figure)[[:space:]]+[0-9]+[.:]?[[:space:]]*","",text)
  trimws(sub("^[0-9]+([.][0-9]+)*[.]?[[:space:]]+","",text))
}
er_format_coef <- function(x,digits=2) {
  vapply(x,function(value) {
    if(!is.finite(value)) return("NE")
    a <- abs(value)
    if(a==0) return("0")
    if(a<0.0001) return(sub("e([+-])0+","e\\1",formatC(value,digits=digits-1,format="e")))
    places <- if(a>=1) digits else max(digits,digits-1-floor(log10(a)))
    text <- formatC(value,digits=places,format="f")
    text <- sub("0+$","",text);sub("\\.$","",text)
  },"",USE.NAMES=FALSE)
}
er_same_full <- function(m) {
  if(!is.null(m$full_equals_base)) return(isTRUE(m$full_equals_base))
  if(length(m$retained) || !clean(m$formula) || !clean(m$base_formula) ||
     !identical(gsub("[[:space:]]","",m$formula),gsub("[[:space:]]","",m$base_formula))) return(FALSE)
  a <- m$estimates;b <- m$base_estimates
  !is.null(a) && !is.null(b) && identical(a$term,b$term) &&
    isTRUE(all.equal(a$estimate,b$estimate,tolerance=1e-10)) &&
    (is.null(m$base_n) || identical(m$n,m$base_n))
}
er_same_full_text <- function(m) {
  if(identical(m$assessment,"partial")) return(paste0("Covariate assessment was incomplete: ",paste(m$failed_covariates,collapse=", ")," could not be evaluated. The full model has the base structure; failed assessment is not evidence of no effect."))
  if(!is.null(m$screening_evaluable) && m$screening_evaluable==0L)
    "No evaluable covariate-screening results were available. The full model is the same as the base model."
  else "No covariates met the configured selection criteria. The full model is the same as the base model."
}
er_display_terms <- function(text) {
  for(m in result$models) if(clean(m$exposure)) text[text==m$exposure] <-
    if(identical(result$scale,"log")) paste0("Log(",sub("^L","",m$exposure),")") else m$exposure
  text
}
figure_role <- rep("",nrow(fm))
figure_caption <- if("caption" %in% names(fm)) as.character(fm$caption) else rep("",nrow(fm))
if(fam=="er" && nrow(efficacy)) for(row in seq_len(nrow(efficacy))) {
  endpoint <- efficacy$label[row];binary <- identical(efficacy$kind[row],"binary")
  model <- if(binary) "logistic regression" else "Cox regression"
  plot_rows <- which(fm$section==efficacy$sec_plot[row])
  model_rows <- which(fm$section==efficacy$sec_model[row])
  if(length(plot_rows)) {
    figure_role[plot_rows] <- "graphical"
    figure_caption[plot_rows] <- paste0(if(binary) "Response rate of " else "Kaplan-Meier plot of ",endpoint," by exposure quartile")
    if(binary && length(plot_rows)>1L && !is.na(efficacy$sec_model[row])) {
      curve <- plot_rows[-1]
      figure_role[curve] <- "base_curve";figure_sections[curve] <- find_section(efficacy$sec_model[row])
      figure_caption[curve] <- paste0("Logistic regression plot of ",endpoint," by exposure")
    }
  }
  for(fi in model_rows) {
    curve <- !is.na(figure_caption[fi]) && grepl("logistic regression (on exposure|plot of)",figure_caption[fi],ignore.case=TRUE)
    figure_role[fi] <- if(curve) "base_curve" else "covariate_effect"
    figure_caption[fi] <- if(curve) paste0("Logistic regression plot of ",endpoint," by exposure") else
      paste0("Covariate effect plot of ",endpoint," ",model," full model")
  }
}
if(fam=="er" && nrow(safety) && "sec_model" %in% names(safety)) {
  model_rows <- which(fm$section %in% safety$sec_model[!is.na(safety$sec_model)])
  figure_role[model_rows] <- "covariate_effect"
} else if(fam=="er" && nrow(safety) && all(c("sec_full","label") %in% names(safety))) {
  for(row in seq_len(nrow(safety))) {
    indices <- which(fm$section==safety$sec_full[row])
    captions <- paste0(c("Event rate of ","Logistic regression plot of ","Cumulative event probability of "),
      safety$label[row],c(" by exposure quartile"," by exposure"," by exposure quartile"))
    for(j in seq_len(min(length(indices),length(captions)))) figure_caption[indices[j]] <- captions[j]
  }
}

add_manifest_table <- function(doc,i) {
  file <- safe_asset(tables,tm$file[i]); tab <- read.csv(file,check.names=FALSE,stringsAsFactors=FALSE)
  front_label <- paste(tm$section[i],tm$caption[i])
  if(family$kind=="fit" && grepl("base model parameter estimates|population parameter estimates|final model parameter estimates",tm$caption[i],ignore.case=TRUE)) {
    state <- if(grepl("base model parameter estimates",tm$caption[i],ignore.case=TRUE)) "base" else "final"
    tab <- pmx_fit_parameter_table(result[[state]],if(state=="base") result$initial_ctl else result$ctl,
      if(state=="final") result$added else list())
    if(is.null(tab) || !nrow(tab)) stop("REPORT_PARAMETER_TABLE_REQUIRED: frozen ",state," parameters unavailable; do not refit for reporting")
  }
  if(!nrow(tab)) return(doc)
  if(family$kind=="fit" && grepl("covariate search run record|scm run record",front_label,ignore.case=TRUE))
    tab <- pmx_fit_scm_display(tab)
  is_parameter <- fam=="er" && grepl("parameter estimates|base model|full model",front_label,ignore.case=TRUE) && any(c("Term","Parameter") %in% names(tab))
  parameter_styles <- list()
  if(is_parameter && "Term" %in% names(tab)) names(tab)[names(tab)=="Term"] <- "Parameter"
  is_screen <- (fam=="er" && grepl("univariable|univariate",front_label,ignore.case=TRUE)) ||
    (fam=="cqtc" && grepl("covariate analysis",front_label,ignore.case=TRUE))
  if(is_screen) tab[] <- lapply(tab,function(v) { v <- as.character(v);v[is.na(v) | v=="NA"] <- "";v })
  if(is_screen && all(c("Covariate","Estimate") %in% names(tab))) {
    indented <- startsWith(tab$Covariate,"\u00a0")
    fields <- intersect(c("BIC","Delta BIC","Retained"),names(tab))
    for(parent in which(!indented & !nzchar(tab$Estimate))) {
      children <- seq.int(parent+1L,nrow(tab))
      if(parent==nrow(tab)) next
      boundary <- which(!indented[children])
      if(length(boundary)) children <- if(boundary[1]>1L) children[seq_len(boundary[1]-1L)] else integer()
      for(field in fields) if(length(children)) {
        values <- tab[[field]][children];available <- which(nzchar(values))
        if(!nzchar(tab[[field]][parent]) && length(available)) tab[[field]][parent] <- values[available[1]]
        tab[[field]][children] <- ""
      }
    }
  }

  if(fam=="er" && grepl("report control",front_label,ignore.case=TRUE)) return(doc)
  abbreviation <- fam=="er" && all(c("Abbreviation","Definition") %in% names(tab))
  if(fam=="cqtc") {
    key <- tolower(gsub("[^[:alnum:]]","",names(tab)))
    tab <- tab[,!key %in% c("r2marginal","r2conditional","r2m","r2c"),drop=FALSE]
  }
  if(fam=="er" && all(c("Abbreviation","Definition") %in% names(tab))) {
    h <- match(tab$Abbreviation,names(er_abbreviations)); use <- !is.na(h)
    tab$Definition[use] <- unname(er_abbreviations[h[use]])
  }
  if(fam=="er" && "Patients with response" %in% names(tab) &&
     all(c("STUDYID","TRT","SAFEFL","EFFFL","ORR") %in% names(er_source_data)) &&
     all(na.omit(er_source_data$ORR) %in% c(0,1))) {
    counts <- vapply(seq_len(nrow(tab)),function(j) {
      if(identical(tab$Study[j],"Total")) return(NA_integer_)
      hit <- er_source_data$STUDYID==tab$Study[j] & er_source_data$TRT==tab$Treatment[j] &
        er_source_data$SAFEFL==1 & er_source_data$EFFFL==1 & er_source_data$ORR==1
      as.integer(sum(hit,na.rm=TRUE))
    },0L)
    counts[tab$Study=="Total"] <- sum(counts,na.rm=TRUE)
    tab$`Patients with response` <- counts
  }
  if(fam=="er" && generic_drug) tab[] <- lapply(tab,function(v) if(is.character(v)) gsub("\\bdrug\\b","study treatment",v,ignore.case=TRUE) else v)
  if(fam=="er" && grepl("Summary of .* by exposure quartile",tm$caption[i],ignore.case=TRUE) &&
     names(tab)[1] %in% c("V1","X","") && all(grepl("^median[0-9]*$",as.character(tab[[1]])))) tab <- tab[,-1,drop=FALSE]
  if(fam=="er" && grepl("full model",tm$caption[i],ignore.case=TRUE)) {
    candidates <- Filter(function(m) identical(m$endpoint,sub(".*for |.*: ","",tm$caption[i])) ||
      grepl(paste0("\\b",m$endpoint,"\\b"),tm$caption[i]),result$models)
    if(length(candidates)==1L) {
      if(er_same_full(candidates[[1]])) return(doc)
      formatted <- candidates[[1]]$parameter_table
      if(is_parameter && !is.null(formatted) && nrow(formatted)) {
        tab <- as.data.frame(formatted,check.names=FALSE,stringsAsFactors=FALSE)
        prefixes <- unlist(candidates[[1]]$parameter_bold_labels,use.names=FALSE)
        parameter_styles <- lapply(which(!is.na(prefixes) & nzchar(prefixes)),function(row)
          list(row=row,column="Parameter",prefix=prefixes[row]))
      }
      co <- candidates[[1]]$estimates
      labels <- as.character(unlist(candidates[[1]]$term_labels))
      hit <- match(er_display_terms(as.character(tab$Parameter)),er_display_terms(co$term))
      if(length(labels)==nrow(co)) {
        missing <- is.na(hit);hit[missing] <- match(as.character(tab$Parameter[missing]),labels)
      }
      if(length(hit)==nrow(tab) && all(!is.na(hit))) {
        e <- co$estimate[hit]; se <- co$se[hit]; lo <- e-qnorm(.975)*se; hi <- e+qnorm(.975)*se
        fmt <- er_format_coef
        tab$Estimate <- fmt(e)
        tab$`SE (RSE%)` <- paste0(fmt(se)," (",round(100*se/abs(e),1),")")
        tab$`95% CI` <- paste0(fmt(lo)," to ",fmt(hi))
      }
    }
  }
  if(fam=="er" && ("Estimate" %in% names(tab))) for(column in intersect(c("Estimate","SE","SE (RSE%)","95% CI","P value"),names(tab)))
    tab[[column]] <- vapply(as.character(tab[[column]]),function(cell) {
      if(is.na(cell)) return("")
      pattern <- "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?"
      positions <- gregexpr(pattern,cell,perl=TRUE)
      values <- regmatches(cell,positions)[[1]]
      regmatches(cell,positions) <- list(er_format_coef(as.numeric(values)))
      cell
    },"")
  if(fam=="er" && grepl("base model|full model",tm$caption[i],ignore.case=TRUE))
    tab <- tab[,!names(tab) %in% "Effect (95% CI)",drop=FALSE]
  if(fam=="cqtc" && grepl("summary of outliers",tm$caption[i],ignore.case=TRUE) &&
     clean(result$outliers$description)) doc <- paragraph(doc,result$outliers$description)
  styles <- if("bold_prefixes" %in% names(tm) && !is.na(tm$bold_prefixes[i]) && nzchar(tm$bold_prefixes[i]))
    tryCatch(jsonlite::fromJSON(tm$bold_prefixes[i],simplifyVector=FALSE),error=function(e) list()) else list()
  if(fam=="er" && is_screen && all(c("Covariate","Delta BIC") %in% names(tab))) {
    parent <- !grepl("^[ \\t\u00a0]",tab$Covariate,perl=TRUE)
    if(length(parent) && parent[1]) {
      blocks <- split(seq_len(nrow(tab)),cumsum(parent))
      delta <- vapply(blocks,function(rows) {
        x <- suppressWarnings(as.numeric(tab$`Delta BIC`[rows]));x <- x[is.finite(x)]
        if(length(x)) x[1] else Inf
      },0.0)
      row_order <- unlist(blocks[order(delta,seq_along(blocks))],use.names=FALSE)
      tab <- tab[row_order,,drop=FALSE]
      styles <- lapply(styles,function(style) {style$row <- match(as.integer(style$row),row_order);style})
    }
  }
  if(is_parameter && "Parameter" %in% names(tab)) tab$Parameter <- er_display_terms(tab$Parameter)
  if(length(parameter_styles)) styles <- parameter_styles
  if(abbreviation) {
    doc <- body_add_break(doc);doc <- heading(doc,"List of abbreviations")
    return(add_table(doc,tab,bold_prefixes=styles))
  }
  table_no <<- table_no+1L
  label <- if(clean(tm$caption[i])) tm$caption[i] else if(clean(tm$section[i])) tm$section[i] else "Analysis table"
  label <- display_caption(label)
  if(fam=="er" && nrow(efficacy)) {
    hits <- which(vapply(efficacy$label,function(endpoint) grepl(endpoint,label,fixed=TRUE),TRUE))
    if(length(hits)==1L) {
      endpoint <- efficacy$label[hits];model <- if(efficacy$kind[hits]=="binary") "logistic regression" else "Cox regression"
      if(grepl("base model|full model",label,ignore.case=TRUE))
        label <- paste("Parameter estimates of",endpoint,model,if(grepl("full model",label,ignore.case=TRUE)) "full model" else "base model")
      else if(grepl("univariable|univariate",label,ignore.case=TRUE))
        label <- paste("Univariable covariate screening of",endpoint,model)
      else if(grepl("by exposure quartile",label,ignore.case=TRUE))
        label <- paste("Median",endpoint,"and 95% CI by exposure quartile")
    }
  }
  is_appendix <- fam=="er" && grepl("^appendix",tm$section[i],ignore.case=TRUE)
  if(is_appendix) label <- sub("^Appendix[[:space:]]+[0-9]+[.:]?[[:space:]]*","",label,ignore.case=TRUE)
  is_screen <- (fam=="er" && grepl("univariable|univariate",label,ignore.case=TRUE)) ||
    (fam=="cqtc" && grepl("covariate analysis",label,ignore.case=TRUE))
  if(is_screen) tab <- tab[,!names(tab) %in% c("OR","HR"),drop=FALSE]
  demography <- fam=="cqtc" && grepl("summary of demographic",label,ignore.case=TRUE)
  label_column <- if((is_screen || demography) && "Covariate" %in% names(tab)) "Covariate" else if(is_parameter) "Parameter" else ""
  indent_rows <- if(nzchar(label_column)) which(startsWith(tab[[label_column]],"\u00a0")) else integer()
  if(length(indent_rows)) tab[[label_column]][indent_rows] <- sub("^\u00a0","",tab[[label_column]][indent_rows])
  doc <- add_table(doc,tab,paste0("Table ",table_no,if(is_appendix) ": " else ". ",label),bold_prefixes=styles,
    font_size=if(is_screen) max(8,REPORT_TEXT_STYLE$size-1) else NULL,indent_rows=indent_rows)
  if(length(report_references)) report_references[[length(report_references)]]$file <<- basename(tm$file[i])
  doc
}
add_manifest_figure <- function(doc,i) {
  if(i %in% emitted_figures) return(doc)
  label <- function(j) display_caption(if(clean(figure_caption[j])) figure_caption[j] else
    if(clean(fm$section[j])) fm$section[j] else "Analysis figure")
  caption <- label(i)
  indices <- i
  indices <- which(!is.na(figure_sections) & figure_sections==figure_sections[i] &
    vapply(seq_len(nrow(fm)),function(j) identical(label(j),caption),TRUE))
  indices <- setdiff(indices,emitted_figures)
  valid <- vapply(indices,function(j) {
    dimensions <- suppressWarnings(as.numeric(c(fm$width_px[j],fm$height_px[j])))
    all(is.finite(dimensions) & dimensions>0)
  },TRUE)
  if(any(!valid)) message("FIGURE_DIMENSIONS: omitted ",paste(fm$file[indices[!valid]],collapse=", "))
  indices <- indices[valid];if(!length(indices)) return(doc)
  figure_no <<- figure_no+1L;emitted_figures <<- c(emitted_figures,indices)
  doc <- paragraph(doc,paste0("Figure ",figure_no,". ",caption),"Caption")
  for(k in seq_along(indices)) {
    j <- indices[k];file <- safe_asset(figures,fm$file[j])
    register_reference("figure",figure_no,paste0("Figure ",figure_no,". ",caption),fm$file[j])
    if(length(indices)>1L) doc <- paragraph(doc,LETTERS[k],"Caption")
    width <- as.numeric(fm$width_px[j]);height <- as.numeric(fm$height_px[j])
    w <- min(6.2,7.8*width/height);h <- w*height/width
    doc <- body_add_img(doc,src=file,width=w,height=h)
  }
  doc
}

summary_section <- which(vapply(sections,function(x) x$t %in% c("Summary","Synopsis","Executive Summary"),TRUE))[1]
methods_section <- find_section(if(family$kind=="fit") "4.1" else if(fam=="er") "3.5" else "3.")
regression_estimates <- find_section(if(fam=="er") "4.2" else "4.2.3.")
model_sections <- if(family$kind=="regression") vapply(result$models,function(m) {
  if(fam=="er") for(manifest in list(safety,efficacy)) {
    if(!nrow(manifest) || !all(c("label","sec_model","section") %in% names(manifest))) next
    endpoint <- which(manifest$label==m$endpoint)
    if(!length(endpoint)) next
    row <- endpoint[1]
    target <- match(manifest$sec_model[row],vapply(sections,function(x) x$t,""))
    if(!is.na(target)) return(target)
    target <- find_section(paste(manifest$section[row],manifest$label[row]))
    if(!is.na(target)) return(target)
  }
  regression_estimates
},0L) else integer()
discussion_section <- which(vapply(sections,function(x) grepl("^[0-9]+[.] Discussion$",x$t),TRUE))[1]
conclusion_section <- which(vapply(sections,function(x) grepl("^[0-9]+[.] Conclusions?$",x$t),TRUE))[1]
if(length(front_rows)) for(i in front_rows) doc <- add_manifest_table(doc,i)
for(si in seq_along(sections)) {
  block <- sections[[si]]
  if((!is.na(summary_section) && si==summary_section) || (fam=="er" && identical(block$t,"1. Introduction"))) doc <- body_add_break(doc)
  if(fam=="er" && identical(block$t,"7. References") && !length(section_text(block$t))) next
  if(fam=="er" && identical(block$t,"APPENDIX")) {
    doc <- body_add_break(doc)
    doc <- body_add_xml(doc,paste0('<w:p xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
      '<w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/><w:keepNext/></w:pPr>',
      '<w:r><w:t>APPENDIX</w:t></w:r></w:p>'))
  } else doc <- heading(doc,section_title(block$t),block$h)
  same_notes <- if(fam=="er") unique(vapply(Filter(er_same_full,result$models[which(model_sections==si)]),er_same_full_text,"")) else character()
  for(text in same_notes) doc <- paragraph(doc,text)
  forest_missing <- fam=="er" && any(vapply(result$models[which(model_sections==si)],
    function(m) identical(m$forest$state,"not_estimable"),TRUE))
  forest_note <- if(forest_missing) "A covariate-effect plot could not be estimated for this endpoint." else character()
  for(text in forest_note) doc <- paragraph(doc,text)
  if(fam %in% c("er","cqtc","ppk","pkpd","tmdd")) for(text in setdiff(section_text(block$t),c(same_notes,forest_note))) {
    if((fam=="er" && identical(block$t,"3.5 Exposure-Response Analysis and Modelling Methods")) ||
       (family$kind=="fit" && startsWith(block$t,"4.")))
      doc <- method_paragraph(doc,text)
    else if(fam=="er" && length(text)==1L && !is.na(text) &&
      (startsWith(text,"[Exposure-response trend for ") || startsWith(text,"[Regression effects for ") ||
       startsWith(text,"[Exposure-safety trend for ")) &&
      endsWith(text,": interpretation pending.]")) doc <- body_add_par(doc,text,style="Normal")
    else doc <- paragraph(doc,text)
  }
  # One qualitative lead-in sentence, above the section's own tables and figures.
  # The digit filter is the guarantee that a lead-in can never restate, or
  # contradict, a value that is tabulated further down the same section.
  if(family$kind!="fit" && is.function(section_lead) && !length(section_text(block$t))) {
    lead <- tryCatch(as.character(section_lead(fam,block$t,dir,result)),error=function(err) {message("SECTION_LEAD: ",conditionMessage(err));character()})
    lead <- lead[!is.na(lead) & nzchar(trimws(lead)) & !grepl("[0-9]",lead)]
    for(text in lead) doc <- paragraph(doc,text)
  }
  if(family$kind=="fit" && si==find_section("5.5"))
    for(note in c(pmx_fit_optimization_note(result$final),pmx_fit_simulator_note(dir))) doc <- paragraph(doc,note)
  if(family$kind=="fit" && si==find_section("5.5") &&
     !any(grepl("CWRES diagnostics",figure_caption,ignore.case=TRUE)))
    doc <- paragraph(doc,"No native CWRES diagnostic was available in the current report assets; no replacement residuals were calculated for presentation.")
  impact_prefix <- if(fam=="tmdd") "5.7" else "5.6"
  if(family$kind=="fit" && si==find_section(impact_prefix) &&
     !any(vapply(figure_sections,function(j) !is.na(j) && startsWith(sections[[j]]$t,impact_prefix),TRUE)))
    doc <- paragraph(doc,"No evaluable covariate-impact figures were available in the current frozen report inputs; this is not evidence of no covariate effect.")
  if(!is.na(summary_section) && si==summary_section) for(text in prose) doc <- paragraph(doc,text)
  if(!is.na(methods_section) && si==methods_section) {
    if(family$kind=="regression") {
      if(fam!="er") for(m in result$models) if(clean(m$formula)) doc <- paragraph(doc,paste0(m$endpoint,": ",m$formula,"."))
      if(clean(result$exposure_label)) doc <- paragraph(doc,paste0("Exposure metric: ",result$exposure_label,"."))
    } else if(family$kind!="fit") {
      doc <- paragraph(doc,"The supplied control stream was imported into the FOCEI fitting backend. Parameter estimates and covariate selection below come from the frozen analysis results.")
    }
  }
  if(fam=="er" && !"--no-figures" %in% args) for(fi in which(figure_sections==si & figure_role=="graphical"))
    doc <- add_manifest_figure(doc,fi)
  if(family$kind=="fit" && !"--no-figures" %in% args)
    for(fi in setdiff(structure_figures[figure_sections[structure_figures]==si],emitted_figures))
      doc <- add_manifest_figure(doc,fi)
  for(i in setdiff(which(table_sections==si),front_rows)) {
    doc <- add_manifest_table(doc,i)
    if(fam=="er" && grepl("base model",tm$caption[i],ignore.case=TRUE) && !"--no-figures" %in% args)
      for(fi in setdiff(which(figure_sections==si & figure_role=="base_curve"),emitted_figures)) doc <- add_manifest_figure(doc,fi)
  }
  if(family$kind=="regression") {
    for(mi in which(model_sections==si)) {
      m <- result$models[[mi]]
      if(fam=="er" && er_same_full(m)) next
      full_rows <- if(fam=="er" && nrow(tm)) which(table_sections==si & grepl("full model",tm$caption,ignore.case=TRUE) &
                                      grepl(m$endpoint,tm$caption,fixed=TRUE)) else if(fam=="cqtc" &&
                                      isTRUE(result$full_equals_final) && nrow(tm))
        which(table_sections==si & grepl("full model parameter estimates",tm$caption,ignore.case=TRUE)) else integer()
      full_present <- any(vapply(full_rows,function(i) nrow(read.csv(safe_asset(tables,tm$file[i]),
                                         check.names=FALSE,stringsAsFactors=FALSE))>0,TRUE))
      if(full_present) next
      tab <- m$estimates
      if(fam=="er") {
        tab <- tab[,c("term","estimate","se"),drop=FALSE]
        if(length(m$term_labels)) {
          labels <- as.character(unlist(m$term_labels)[match(tab$term,names(m$term_labels))])
          mapped <- !is.na(labels) & nzchar(labels)
          tab$term[mapped] <- labels[mapped]
        }
      }
      if(nrow(tab)) {
        table_no <- table_no+1L; names(tab) <- c("Parameter","Estimate","Standard error")
        parameter_styles <- list();indent_rows <- integer()
        if(fam=="er" && !is.null(m$parameter_table)) {
          tab <- as.data.frame(m$parameter_table,check.names=FALSE,stringsAsFactors=FALSE)
          prefixes <- unlist(m$parameter_bold_labels,use.names=FALSE)
          parameter_styles <- lapply(which(!is.na(prefixes) & nzchar(prefixes)),function(row)
            list(row=row,column="Parameter",prefix=prefixes[row]))
          indent_rows <- which(startsWith(tab$Parameter,"\u00a0"))
          tab$Parameter[indent_rows] <- sub("^\u00a0","",tab$Parameter[indent_rows])
        } else if(fam=="er") for(column in c("Estimate","Standard error")) tab[[column]] <- er_format_coef(tab[[column]])
        label <- if(fam=="er") paste("Parameter estimates of",m$endpoint,if(m$kind=="OR") "logistic regression" else "Cox regression","full model") else paste(m$endpoint,"final model estimates")
        doc <- add_table(doc,tab,paste0("Table ",table_no,". ",label),bold_prefixes=parameter_styles,indent_rows=indent_rows)
      }
    }
  }
  if(fam=="ppk" && si==find_section("Appendix C:") &&
     !any(table_sections==si & grepl("covariate search run record|scm run record",tm$caption,ignore.case=TRUE))) {
    rec <- result$rec
    if(is.null(rec) || !nrow(rec)) stop("PPK_SCM_RECORD_REQUIRED: frozen SCM record missing; do not rerun fits for formatting")
    rec <- pmx_fit_scm_display(rec)
    rec[] <- lapply(rec,function(x) {x <- as.character(x);x[is.na(x)] <- "";x})
    table_no <- table_no+1L
    doc <- add_table(doc,rec,paste0("Table ",table_no,". Covariate search run record (forward and backward steps)"))
  }
  if(family$kind=="fit") for(state in c("base","final")) {
    destination <- find_section(if(state=="base") "5.2" else "5.4")
    if(!is.na(destination) && si==destination) {
      fitted <- result[[state]]
      if(family$kind=="fit") {
        supplied <- which(table_sections==si & grepl(if(state=="base") "base model parameter estimates" else
          "population parameter estimates|final model parameter estimates",tm$caption,ignore.case=TRUE))
        if(length(supplied)) next
        tab <- pmx_fit_parameter_table(fitted,if(state=="base") result$initial_ctl else result$ctl,if(state=="final") result$added else list())
        if(!is.null(tab) && nrow(tab)) {
          table_no <- table_no+1L
          doc <- add_table(doc,tab,paste0("Table ",table_no,". ",state," model parameter estimates"))
        }
        next
      }
      tab <- tryCatch(as.data.frame(fitted$parFixedDf),error=function(e) NULL)
      if(!is.null(tab) && nrow(tab)) {
        # A frozen parFixedDf can already carry a column named "Parameter" (run_pipeline.R:610 does
        # pf$Parameter <- rownames(pf)). Prepending the row names then yields TWO columns with that
        # name and flextable() dies with "duplicated col_keys: Parameter". Drop the pre-existing
        # column first - the row names are the authoritative parameter labels here.
        tab <- tab[, setdiff(names(tab),"Parameter"), drop=FALSE]
        if(!"Parameter" %in% names(tab)) tab <- data.frame(Parameter=rownames(tab),tab,check.names=FALSE,row.names=NULL)
        tab <- tab[, make.unique(names(tab)), drop=FALSE]
        table_no <- table_no+1L
        doc <- add_table(doc,tab,paste0("Table ",table_no,". ",state," model parameter estimates"))
      }
    }
  }
  if(!"--no-figures" %in% args) for(i in setdiff(which(figure_sections==si),emitted_figures)) doc <- add_manifest_figure(doc,i)
  if(!is.na(discussion_section) && si==discussion_section) {
    for(text in study_prose$Discussion) doc <- paragraph(doc,text)
    if(is.na(conclusion_section)) for(text in study_prose$Conclusion) doc <- paragraph(doc,text)
  }
  if(!is.na(conclusion_section) && si==conclusion_section) {
    if(is.na(discussion_section)) for(text in study_prose$Discussion) doc <- paragraph(doc,text)
    for(text in study_prose$Conclusion) doc <- paragraph(doc,text)
  }
  if(family$kind=="fit" && startsWith(block$t,"D.2 ")) doc <- pmx_fit_output_word(doc,result$final)
  if(family$kind=="fit" && startsWith(block$t,"D.1 ")) {
    appendix_ctl <- file.path(dir,"final_model.ctl")
    if(!file.exists(appendix_ctl)) stop("Appendix requires the published final_model.ctl")
    source_lines <- readLines(appendix_ctl,warn=FALSE)
    if(!is.null(result$initial_ctl) && !identical(source_lines,result$initial_ctl))
      stop("Published final_model.ctl differs from the frozen initial stream")
    source_lines <- source_lines[!grepl("^\\s*;\\s*(?:PMX_(?:ENDPOINT|DVID|RESID_INIT)\\s*:|Skeleton\\s*:|PMX endpoints preserve)",source_lines,ignore.case=TRUE,perl=TRUE)]
    for(line in source_lines) doc <- body_add_par(doc,line,style="Normal")
  }
}
# Machine-facing evidence and diagnostics are separate files, never report-body placeholders.
assets <- c(if(family$kind=="fit") file.path(dir,"data_spec.csv") else character(),bundle$path,data,file.path(tables,"_html_tables.csv"),file.path(figures,"_html_figures.csv"),if(nrow(tm)) file.path(tables,tm$file) else character(),if(nrow(fm)) file.path(figures,fm$file) else character(),html_only_assets,ctl,if(family$kind=="fit") file.path(dir,"final_model.ctl") else character())
assets <- unique(assets[!is.na(assets)&file.exists(assets)])
relative_asset <- function(p) {
  root <- paste0(normalizePath(dir,winslash="/"),"/"); path <- normalizePath(p,winslash="/")
  if(startsWith(path,root)) substring(path,nchar(root)+1L) else path
}
evidence <- list(schema=1L,source_md5=bundle$md5,source_file=relative_asset(bundle$path),references=report_references,files=lapply(assets,function(p) list(file=relative_asset(p),md5=unname(tools::md5sum(p)))))
if(family$kind=="fit") {
  policy <- pmx_narrative_policy(dir,fam)
  gate <- pmx_narrative_gate(dir,bundle)
  active <- vapply(report_references,function(r) if(is.null(r$section)) "" else r$section,"")
  targets <- unique(c(pmx_fit_targets(fam)[seq_len(5L)],intersect(active,names(result$section_results))))
  covered <- names(gate$section_results)
  state <- if(!policy$required) "omitted" else if(isTRUE(gate$ok) && all(targets %in% covered)) "accepted" else "required"
  evidence$narrative <- list(required=policy$required,state=state,reason=if(!policy$required) policy$reason else gate$reason,
    required_sections=c("Discussion","Conclusion"),required_result_targets=targets)
}
dir.create(file.path(dir,"output"),recursive=TRUE,showWarnings=FALSE)
if(fam %in% c("er","cqtc")) {
  context_result <- bundle$result
  for(nm in c("labels","units")) if(!is.null(context_result$covariates[[nm]]))
    context_result$covariates[[nm]] <- as.list(context_result$covariates[[nm]])
  jsonlite::write_json(list(schema=1L,family=fam,source_md5=bundle$md5,
    source_file=relative_asset(bundle$path),result=context_result),
    file.path(dir,"output","report_context.json"),pretty=TRUE,auto_unbox=TRUE,
    dataframe="rows",digits=NA,na="null",null="null")
}
if(family$kind=="fit") {
  context_result <- list(family=fam,data_md5=result$data_md5,selection=result$selection,
    n_subjects=result$n_subjects,n_observations=result$n_observations,criterion=result$criterion,
    p_forward=result$p_forward,p_backward=result$p_backward,chosen=result$chosen,refs=as.list(result$refs),
    data_spec=pmx_fit_metadata()$spec,category_labels=pmx_fit_metadata()$levels,
    covariance=result$covariance,covariate_assessment=result$assessment,control_stream=result$ctl,section_results=result$section_results,
    base_parameters=pmx_fit_parameter_table(result$base,result$initial_ctl),
    final_parameters=pmx_fit_parameter_table(result$final,result$ctl,result$added),search_record=pmx_fit_scm_display(result$rec))
  context <- file.path(dir,"output","report_context.json")
  jsonlite::write_json(list(schema=1L,family=fam,source_md5=bundle$md5,
    source_file=relative_asset(bundle$path),result=context_result),context,
    pretty=TRUE,auto_unbox=TRUE,dataframe="rows",digits=NA,na="null",null="null")
  evidence$family <- fam
  evidence$files <- c(evidence$files,list(list(file=relative_asset(context),md5=unname(tools::md5sum(context)))))
}
jsonlite::write_json(evidence,file.path(dir,"output","report_evidence.json"),pretty=TRUE,auto_unbox=TRUE)
tmp <- paste0(out,".tmp.docx"); print(doc,target=tmp)
python <- Sys.getenv("PMX_PYTHON","")
if(!nzchar(python)) python <- Sys.which("python3")
if(!nzchar(python)) python <- Sys.which("python")
if(!nzchar(python)) stop("Word field assembly requires Python; set PMX_PYTHON")
status <- system2(python,c(shQuote(file.path(sd,"apply_reference.py")),shQuote(tmp),shQuote(reference),shQuote(file.path(dir,"output","report_evidence.json"))))
if(status!=0L) stop("Word reference/field assembly failed; previous Word output was not replaced")
if(!file.copy(tmp,out,overwrite=TRUE)) stop("Cannot publish Word file")
unlink(tmp)
cat("WORD_WRITTEN ",out,"; ",table_no," tables; ",figure_no," figures. Narrative completion requires current evidence unless the user opted out.\n",sep="")


