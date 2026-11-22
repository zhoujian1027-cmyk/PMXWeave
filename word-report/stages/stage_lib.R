#!/usr/bin/env Rscript

.cpu_sources <- vapply(sys.frames(),function(frame) {
  p <- frame$ofile;if(is.character(p) && length(p)) p[1] else ""
},"")
.cpu_sources <- .cpu_sources[basename(.cpu_sources)=="stage_lib.R"]
if(!length(.cpu_sources)) stop("PMX_CPU_TOOLKIT_REQUIRED: source stage_lib.R from its complete toolkit")
source(file.path(dirname(tail(.cpu_sources,1L)),"..","cpu_budget.R"))
pmx_cpu_setup(threads=1L)

`%||%` <- function(a, b) if (is.null(a)) b else a

STAGE_ROOT <- "artifacts"
STAGES <- c("s1", "s1c", "s2", "s3", "s4", "s5")
STAGE_TITLE <- c(s1 = "fit (fit + covariate search; no report concerns)",
                 s1c = "covariance (reuse selected fit; no SCM search)",
                 s2 = "freeze (freeze the fit the report stages read)",
                 s3 = "figures (diagnostics + extracted tables)",
                 s4 = "html (knit the family report)",
                 s5 = "word (assemble the .docx)")

STAGE_GROUP <- c(s1 = "html", s1c = "html", s2 = "html", s3 = "word", s4 = "html", s5 = "word")
GROUP_DIR   <- c(screen = "01_screen", html = "02_html", word = "03_word")

pmx_root <- function() {
  r <- Sys.getenv("PMX_ROOT", "")
  if (identical(r, "")) "" else r
}

pmx_set_root <- function(dir) {
  if (length(dir) && nzchar(dir[1])) {
    d <- normalizePath(dir[1], mustWork = FALSE)
    Sys.setenv(PMX_ROOT = d)
    if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    invisible(d)
  } else invisible(pmx_root())
}

pmx_flat <- function() {
  !nzchar(pmx_root()) || identical(Sys.getenv("PMX_LAYOUT", ""), "flat")
}

group_dir <- function(group) {
  if (pmx_flat()) return(".")
  v <- Sys.getenv(paste0("PMX_DIR_", toupper(group)), "")
  if (nzchar(v)) v else (GROUP_DIR[[group]] %||% ".")
}

gpath <- function(group, ...) {
  if (pmx_flat()) return(file.path(...))
  file.path(group_dir(group), ...)
}

stage_workdir <- function(stage) {
  g <- STAGE_GROUP[[stage]] %||% "."
  d <- if (pmx_flat()) getwd() else file.path(pmx_root(), group_dir(g))
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

pmx_enter <- function(stage) {
  d <- stage_workdir(stage)
  setwd(d)
  d
}

pmx_start <- function(root, stage) {
  if (identical(Sys.getenv("PMX_LAYOUT", ""), "flat")) {
    if (length(root) && nzchar(root[1])) setwd(root[1])
    return(getwd())
  }
  pmx_set_root(root)
  pmx_enter(stage)
}

abs_root <- function(p) {
  if (pmx_flat()) return(p)
  absolute <- grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)",p)
  out <- ifelse(absolute, p, file.path(pmx_root(), p))
  out
}

rel_root <- function(p) {
  if (pmx_flat()) return(p)
  r <- pmx_root()
  pre <- paste0(r, "/")
  vapply(p, function(x) {
    if (!grepl("^(/|[A-Za-z]:)",x)) return(x)
    if (identical(x, r)) return(".")
    if (startsWith(x, pre)) substring(x, nchar(pre) + 1L) else x
  }, "", USE.NAMES = FALSE)
}

script_path <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (!length(m)) return(NA_character_)
  p <- sub("^--file=", "", m[1])
  if (!nzchar(p) || p == "-" || !file.exists(p)) return(NA_character_)
  normalizePath(p, mustWork = FALSE)
}

file_md5  <- function(p) vapply(as.character(p), function(x)
  if (file.exists(x)) unname(tools::md5sum(x)) else NA_character_, "")
file_size <- function(p) vapply(as.character(p), function(x)
  if (file.exists(x)) as.numeric(file.info(x)$size) else NA_real_, numeric(1))

stage_dir <- function(stage) {
  d <- file.path(stage_workdir(stage), STAGE_ROOT, stage)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

gate_path <- function(stage) file.path(stage_dir(stage), paste0(toupper(stage), "_DONE"))
manifest_path <- function(stage) file.path(stage_dir(stage), "MANIFEST.tsv")

stage_done <- function(stage) {
  d <- if(pmx_flat()) getwd() else file.path(pmx_root(),group_dir(STAGE_GROUP[[stage]]))
  file.exists(file.path(d,STAGE_ROOT,stage,paste0(toupper(stage),"_DONE")))
}

manifest_rows <- function(paths, kind) {
  paths <- unique(paths[!is.na(paths) & nzchar(paths)])
  if (!length(paths)) return(data.frame(kind = character(0), path = character(0),
                                        md5 = character(0), bytes = numeric(0),
                                        stringsAsFactors = FALSE))
  ap <- abs_root(paths)
  data.frame(kind = kind, path = rel_root(ap), md5 = vapply(ap, file_md5, ""),
             bytes = vapply(ap, file_size, 0), stringsAsFactors = FALSE)
}

manifest_write <- function(stage, inputs, outputs, note = "") {
  stage_dir(stage)   # a manifest must be writable on the very first run
  head_lines <- c(
    paste0("# stage\t", stage),
    paste0("# title\t", STAGE_TITLE[[stage]] %||% stage),
    paste0("# when\t", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("# r\t", R.version.string),
    paste0("# root\t", if (pmx_flat()) "." else pmx_root()),
    paste0("# script\t", basename(script_path() %||% "?")),
    paste0("# script_md5\t", file_md5(script_path() %||% "")),
    paste0("# contract\t",stage_contract(stage)),
    paste0("# note\t", gsub("[\t\r\n]+", " ", note)))
  body <- rbind(manifest_rows(inputs, "in"), manifest_rows(outputs, "out"))
  p <- manifest_path(stage)
  writeLines(c(head_lines, "kind\tpath\tmd5\tbytes",
               apply(body, 1, paste, collapse = "\t")), p)
  p
}

manifest_read <- function(stage) {
  p <- manifest_path(stage)
  if (!file.exists(p)) return(NULL)
  ln <- readLines(p, warn = FALSE)
  ln <- ln[!grepl("^#", ln)]
  if (length(ln) < 2) return(NULL)
  utils::read.delim(text = paste(ln, collapse = "\n"), stringsAsFactors = FALSE)
}

stage_require <- function(stage, requires) {
  miss <- requires[!vapply(requires, stage_done, TRUE)]
  if (length(miss))
    stop("stage ", stage, " cannot start: gate(s) missing for ",
         paste(miss, collapse = ", "), ". Run those stages first (see stages/STAGES.md).",
         call. = FALSE)
  for (up in requires) {
    m <- manifest_read(up)
    if (is.null(m)) stop("stage ", up, " has a gate but no readable MANIFEST.tsv", call. = FALSE)
    out <- m[m$kind == "out", , drop = FALSE]
    for (i in seq_len(nrow(out))) {
      ap <- abs_root(out$path[i])
      if (!file.exists(ap))
        stop("stage ", stage, ": artifact ", out$path[i], " recorded by ", up,
             " is gone - re-run ", up, call. = FALSE)
      if (nzchar(out$md5[i]) && !identical(as.character(file_md5(ap)), as.character(out$md5[i])))
        stop("stage ", stage, ": artifact ", out$path[i], " changed since ", up,
             " produced it (hash mismatch). Re-run ", up, ".", call. = FALSE)
    }
  }
  invisible(TRUE)
}

stage_close <- function(stage, inputs, outputs, note = "", min_bytes = 1) {
  ap <- abs_root(outputs)
  miss <- outputs[!file.exists(ap)]
  if (length(miss))
    stop("stage ", stage, " produced no ", paste(miss, collapse = ", "),
         " - refusing to write the gate", call. = FALSE)
  empty <- outputs[file_size(ap) < min_bytes]
  if (length(empty))
    stop("stage ", stage, " wrote empty ", paste(empty, collapse = ", "),
         " - refusing to write the gate", call. = FALSE)
  manifest_write(stage, inputs, outputs, note)
  writeLines(c(paste0("stage\t", stage),
               paste0("when\t", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
               paste0("outputs\t", length(outputs)),
               paste0("note\t", gsub("[\t\r\n]+", " ", note))), gate_path(stage))
  cat("\n[", toupper(stage), "] GATE WRITTEN: ", gate_path(stage), "\n", sep = "")
  invisible(TRUE)
}

stage_invalidate <- function(stages = STAGES) {
  g <- unlist(lapply(as.character(stages), function(s) {
    p <- tryCatch(gate_path(s), error = function(e) NA_character_)
    if (length(p) == 1L && !is.na(p) && file.exists(p)) p else NULL
  }))
  if (length(g)) { file.remove(g); cat("cleared stale gate(s):", paste(basename(g), collapse = ", "), "\n") }
  invisible(NULL)
}

pmx_covariance_state <- function(state,note="") {
  p <- abs_root(gpath("html","_scm_covariance_state.dcf"))
  write.dcf(data.frame(Analysis_state="ESTIMATES_COMPLETE",Covariance_state=state,
    # UNESTIMABLE is an explicit, disclosed decision to continue without covariance;
    # it is not a silent success and it is not a blocked stage.
    Report_state=if(state %in% c("COMPLETE","UNESTIMABLE")) "READY_TO_FREEZE" else "BLOCKED_UNCERTAINTY",
    Note=note,stringsAsFactors=FALSE),file=p)
}

stage_outputs <- function(stage, fam) switch(stage,
  s1 = c(gpath("html",c(paste0(fam,"_scm_search_result.rds"),"table/_scm_summary.csv","table/_scm_runrecord.csv")),"final_model.ctl"),
  s1c = gpath("html",c("table/tbl_10.csv","_nlmixr2_output.txt","_scm_final_result.rds","_scm_covariance_state.dcf")),
  s2 = c(gpath("html",STAGE_ROOT,"s2",c("final.rds","selection.csv","final_fitted.ctl","simulators.dcf")),
         "final_model.ctl","final_model.cpp",gpath("html",paste0(fam,"_ebe.cpp")),
         gpath("html",paste0(fam,c("_estimates.zip","_scm_final.zip")))),
  s3 = {
    figdir <- gpath("word", "figure")
    png <- list.files(abs_root(figdir), pattern = "^html_fig_.*[.](png|jpg|jpeg)$")
    c(gpath("word", "figure", "_html_figures.csv"),
      if (length(png)) gpath("word", "figure", png) else character(0),
      gpath("word", "table", "_html_tables.csv"),
      gpath("word","table",intersect(c("_scm_summary.csv","_scm_runrecord.csv"),list.files(abs_root(gpath("word","table"))))),
      gpath("word","table",list.files(abs_root(gpath("word","table")),pattern="^html_tbl_.*[.]csv$")))
  },
  s4 = c(paste0(fam, "_report.html"),
    if(file.exists(abs_root(gpath("html","table/_simulator_validation.json")))) gpath("html","table/_simulator_validation.json")),
  s5 = paste0(fam, "_report.docx"),
  character(0))

stage_inputs_data <- function(stage, fam) switch(stage,
  s1 = c(Sys.getenv("PMX_DATA",paste0(fam,"_data.csv")),"base_model.ctl",
         if(file.exists(abs_root("covariates.csv"))) "covariates.csv" else character(0),
         if(file.exists(abs_root("pmx_config.R"))) "pmx_config.R" else character(0),
         if(file.exists(abs_root("base_selection.dcf"))) "base_selection.dcf" else character(0)),
  s1c = stage_outputs("s1",fam),
  s2 = c(stage_outputs("s1", fam),stage_outputs("s1c",fam),"final_model.ctl"),
  s3 = c(stage_outputs("s2",fam),stage_outputs("s4",fam)),
  s4 = c(if(file.exists(abs_root("data_spec.csv"))) "data_spec.csv" else character(),
         Sys.getenv("PMX_DATA",paste0(fam,"_data.csv")),stage_outputs("s2",fam),gpath("html",paste0(fam,"_report.Rmd")),
         if(file.exists(abs_root("pmx_config.R"))) "pmx_config.R" else character(),
         if(file.exists(abs_root("report_metadata.dcf"))) "report_metadata.dcf" else character(),
         "final_model.cpp",gpath("html",paste0(fam,"_ebe.cpp"))),
  s5 = c(stage_outputs("s3", fam),stage_outputs("s2",fam), "final_model.ctl",
         gpath("html", "_nlmixr2_output.txt"),
         intersect(c("data_spec.csv","report_metadata.dcf","report_narrative.json","report_section_leads.R"),list.files(abs_root(".")))),
  character(0))

stage_outs_abs <- function(stage, fam) abs_root(stage_outputs(stage, fam))
stage_ins_abs  <- function(stage, fam) abs_root(stage_inputs(stage, fam))

stage_contract <- function(stage) paste(Sys.getenv(c("PMX_DATA","PMX_EST","PMX_ENDPOINT","PMX_DVID","PMX_RESID_INIT","PMX_CMT_OBS","SCM_CRITERION","SCM_P_FWD","SCM_P_BCK","PMX_EXPOSURE_LABEL",
  if(stage!="s1") c("PMX_COV_METHOD","PMX_COV_FALLBACK","PMX_COV_BASE"),
  if(stage %in% c("s4","s3","s5")) c("PMX_SIM_CHECK_RTOL","PMX_SIM_CHECK_ATOL","PMX_SIM_CHECK_REASON","PMX_SIM_CHECK_APPROVED"))),collapse="|")
stage_current <- function(stage,fam) {
  if(!stage_done(stage)) return(FALSE)
  m <- manifest_read(stage); if(is.null(m)) return(FALSE)
  meta <- readLines(manifest_path(stage),warn=FALSE)
  contract <- grep("^# contract\t",meta,value=TRUE)
  if(length(contract)!=1L || sub("^# contract\t","",contract)!=stage_contract(stage)) return(FALSE)
  expected <- unique(stage_inputs(stage,fam))
  if(!setequal(m$path[m$kind=="in"],rel_root(abs_root(expected)))) return(FALSE)
  if(anyNA(m$md5)) return(FALSE)
  for(i in seq_len(nrow(m))) {
    p <- abs_root(m$path[i])
    if(!file.exists(p) || !identical(as.character(file_md5(p)),as.character(m$md5[i]))) return(FALSE)
  }
  TRUE
}
stage_code_inputs <- function(stage) {
  here <- if(exists(".here",inherits=TRUE)) get(".here",inherits=TRUE) else Sys.getenv("STAGES_DIR","")
  wr <- normalizePath(file.path(here,".."),mustWork=FALSE)
  here <- normalizePath(here,mustWork=FALSE)
  common <- c(file.path(here,"stage_lib.R"),file.path(here,"run_stages.R"),file.path(here,paste0(stage,"_",c(s1="fit",s1c="covariance",s2="freeze",s3="figures",s4="html",s5="word")[[stage]],".R")))
  extra <- switch(stage,
    s1=c(file.path(wr,"run_pipeline.R"),list.files(file.path(wr,"family"),pattern="_model[.]R$",full.names=TRUE),file.path(wr,"..","analyses_template","tools",c("model_contract.R","data_filters.R","covariate_intake.R","screen_fit_identity.R"))),
    s1c=c(file.path(wr,"run_pipeline.R"),list.files(file.path(wr,"family"),pattern="_model[.]R$",full.names=TRUE),file.path(wr,"..","analyses_template","tools","model_contract.R"),file.path(wr,"..","analyses_template","tools",c("data_filters.R","screen_fit_identity.R"))),
    s2=file.path(wr,"..","analyses_template","tools",c("model_contract.R","simulator_contract.R")),
    s3=file.path(wr,c("extract_figures.R","extract_tables.R")),
    s4=c(file.path(wr,"pkpd_report_contract.R"),file.path(wr,"ppk_report_support.R")),
    s5=c(file.path(wr,c("report_generator.R","apply_reference.py","result_narrative.R")),list.files(file.path(wr,"family"),pattern="[.]R$",full.names=TRUE),list.files(wr,pattern="[.]docx$",full.names=TRUE)),character(0))
  normalizePath(unique(c(common,extra)),mustWork=FALSE)
}

stage_inputs <- function(stage,fam) {
  extra <- character()
  if(stage=="s5" && file.exists(abs_root("report_narrative.json")) && requireNamespace("jsonlite",quietly=TRUE)) {
    note <- tryCatch(jsonlite::fromJSON(abs_root("report_narrative.json"),simplifyVector=FALSE),error=function(e) NULL)
    if(length(note$evidence)) {
      extra <- vapply(note$evidence,function(e) if(is.character(e$file) && length(e$file)==1L) e$file else "","")
      extra <- extra[nzchar(extra) & !grepl("^(/|[A-Za-z]:)|[.][.]",extra)]
    }
  }
  if(stage=="s4" && fam=="ppk") {
    screen <- gpath("screen","ladder_table.csv")
    if(file.exists(abs_root(screen))) extra <- c(extra,screen)
  }
  unique(c(stage_inputs_data(stage,fam),stage_code_inputs(stage),extra))
}
