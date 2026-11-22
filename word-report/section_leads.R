# Engine default for the optional per-section lead-in sentence.
#
# A study may replace or extend this file with report_section_leads.R in the
# study directory. That file may call section_lead_default() to keep the generic
# behaviour and add study-specific sentences on top.
#
# Contract: section_lead_default(fam, section, dir, result) -> character()
#   fam     family id ("ppk", "pkpd", "tmdd", "er", "cqtc")
#   section the section heading exactly as it appears in family/<fam>.R
#   dir     the study directory (table/, figure/, output/ live under it)
#   result  the frozen result contract (report_results.rds / S2 final.rds)
#
# Rules the generator enforces on whatever this returns: one sentence per
# section, no digit anywhere in it, and it is placed immediately under the
# heading. A sentence therefore states the direction or the reading of the
# section's own display, never a value: every value is already tabulated in the
# same section, and repeating it here is how two parts of a report start to
# disagree. A section with nothing result-dependent to say returns character(0)
# and stays a bare heading, rather than receiving filler.

.sl_norm <- function(x) {
  x <- as.character(x)[1]
  if(is.na(x)) return("")
  x <- sub("^[0-9]+([.][0-9]+)*[.]?[[:space:]]*","",trimws(x))
  trimws(gsub("[^a-z0-9]+"," ",tolower(x)))
}
.sl_models <- function(result) {
  m <- if(is.list(result) && !is.null(result$models)) result$models else list()
  m[vapply(m,function(x) is.list(x) && is.data.frame(x$estimates),TRUE)]
}
.sl_endpoint <- function(section,result) {
  labs <- vapply(.sl_models(result),function(m) if(is.null(m$endpoint)) NA_character_ else as.character(m$endpoint)[1],character(1))
  labs <- labs[!is.na(labs) & nzchar(labs)]
  if(!length(labs)) return(NULL)
  hit <- labs[vapply(labs,function(L) isTRUE(grepl(paste0("\\b",L,"\\b"),section,ignore.case=TRUE,perl=TRUE)),TRUE)]
  if(!length(hit)) return(NULL)
  hit[which.max(nchar(hit))]
}
# Direction only, from the frozen estimate and its standard error: the sentence
# says which way the association went, and whether the interval excluded no
# association. It carries no magnitude, so it cannot contradict the table.
.sl_direction <- function(m) {
  co <- m$estimates
  if(is.null(co) || ncol(co) < 3L) return(NULL)
  hit <- which(as.character(co[[1]]) == as.character(m$exposure)[1])
  if(length(hit) != 1L) return(NULL)
  e <- suppressWarnings(as.numeric(co[[2]][hit])); se <- suppressWarnings(as.numeric(co[[3]][hit]))
  if(!is.finite(e) || !is.finite(se) || se <= 0) return(NULL)
  kind <- if(is.null(m$kind)) "" else as.character(m$kind)[1]
  if(abs(e) <= qnorm(0.975)*se) return("the fitted association was not distinguishable from no association")
  if(kind %in% c("OR","HR")) {
    if(kind == "OR") {
      if(e > 0) "the probability of the outcome increased with higher exposure" else "the probability of the outcome decreased with higher exposure"
    } else {
      if(e > 0) "the event occurred earlier at higher exposure" else "the event occurred later at higher exposure"
    }
  } else if(e > 0) "the fitted trend increased with higher exposure" else "the fitted trend decreased with higher exposure"
}

section_lead_default <- function(fam,section,dir=NULL,result=NULL) {
  key <- .sl_norm(section)
  if(!nzchar(key)) return(character())
  # Sections that report no result of their own.
  if(grepl("^(synopsis|executive summary|summary|abstract|introduction|objectives|background|references|appendix|appendix |table of contents|title page|list of|revision history|approval|signature|software|data assembly|data handling|analysis populations|disposition|glossary)",key)) return(character())
  if(grepl("^(discussion|conclusions?)$",key)) return(character())
  if(grepl("population",key)) return("The characteristics of the analysed population are summarised below.")
  if(grepl("^(safety|adverse|toxicit|tolerab|sae|ae |adverse events|clinical laboratory|ecg|vital)",key) ||
     grepl("(safety|adverse|toxicit|tolerab|sae)",key)) return(if(fam=="er") character() else "The observed safety summaries and any fitted exposure associations are presented below.")
  ep <- if(is.null(result)) NULL else .sl_endpoint(section,result)
  if(!is.null(ep)) {
    ms <- .sl_models(result)
    idx <- which(vapply(ms,function(m) !is.null(m$endpoint) && identical(as.character(m$endpoint)[1],ep),TRUE))
    txt <- if(length(idx)) .sl_direction(ms[[idx[1]]]) else NULL
    if(is.null(txt)) return(paste0(ep,": the estimate and its interval are tabulated below."))
    return(paste0(ep,": ",txt,"."))
  }
  if(grepl("exposure measure|exposure metric|exposure definition|exposure variable|dose and exposure",key))
    return("The exposure measure is the one defined in the methods, and it is used on the same scale in every model below.")
  if(grepl("covariate",key))
    return("Candidate covariates are retained only where they improve the fit beyond exposure alone, and each retained effect is tabulated below.")
  if(grepl("diagnostic|goodness|model evaluation|model qualification|observation versus|visual predictive|individual fit|parameter estimate|model estimate",key))
    return("The display below describes the current model; it is a diagnostic of this fit and does not by itself establish predictive performance.")
  if(grepl("patient|population|demograph|baseline|disposition|characteristic",key))
    return("The characteristics of the analysed population are summarised below.")
  character()
}

# The generator looks up section_lead(); keeping this alias means the study
# override can be a thin wrapper.
section_lead <- section_lead_default
