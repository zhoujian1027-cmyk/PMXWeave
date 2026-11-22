#!/usr/bin/env Rscript
# Explicit installation only; ordinary invocation checks the active R library.
args <- commandArgs(TRUE)
if(length(args)>1L || (length(args) && !args %in% c("--check","--install")))
  stop("usage: Rscript analyses_template/tools/install_dependencies.R [--check|--install]")
packages <- c("nlmixr2","nlmixr2est","nlmixr2extra","rxode2","lotri","nonmem2rx",
              "nlmixr2save","mrgsolve","tidyverse","dplyr","tidyr","tibble","readr",
              "stringr","ggplot2","scales","haven","lme4","nlme","survival","survminer",
              "cowplot","tidyvpc","gridExtra","htmltools","jsonlite","rlang","xml2",
              "knitr","rmarkdown","officer","flextable","ragg")
present <- rownames(installed.packages())
missing <- setdiff(packages,present)
if(identical(args,"--install") && length(missing)) {
  install.packages(missing,repos="https://cloud.r-project.org")
  missing <- setdiff(packages,rownames(installed.packages()))
}
cat("R:",R.version.string,"\n")
cat("Required direct packages:",length(packages),"\n")
cat("Missing:",if(length(missing))paste(missing,collapse=", ") else "none","\n")
cat("Optional: RhpcBLASctl for explicit BLAS thread control\n")
if(requireNamespace("rmarkdown",quietly=TRUE))
  cat("Pandoc available:",rmarkdown::pandoc_available(),"\n")
cat("Compiler and system-library availability must be verified for the execution host.\n")
quit(status=if(length(missing))1L else 0L)
