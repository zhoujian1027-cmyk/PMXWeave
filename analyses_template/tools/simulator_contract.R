## Paired-simulator contract: ONE home for "what a family's mrgsolve translation must expose".
##
## Stage 2 must refuse a translation that cannot be compiled or that does not carry the
## capture names the family report consumes. Otherwise the defect surfaces at stage 4 as a
## knit crash (e.g. a hand-authored final_model.cpp using DVID without declaring it, which
## fails the C++ build with "'DVID' was not declared in this scope" and then leaves every
## prediction NA in the report). Family report Rmds pass the same names to
## require_vpc_contract(), so this file is the single source of that list.
##
## Every capture must be on the fitted observation scale: the report converts DV, PRED and
## IPRED together from the declared DV scale, so a simulator that emits natural-scale values
## for a log-transformed DV is rejected at the prediction check, not silently mislabelled.
## This file checks names and compilation only; the numeric scale is verified at report time by
## pmx_sim_prediction_check() (analyses_template/_shared/report_aug.R), which compares zero-ETA/
## zero-EPS predictions by subject/time/endpoint and rejects deterministic mismatches.
##
## Add a family here only together with its report's require_vpc_contract() call.
pmx_sim_contract <- function(family, kind = "sim") {
  fam <- tolower(as.character(family)[1])
  need <- switch(fam,
    pkpd = c("IPRED", "IPRED_PD", "DV_PK", "DV_PD"),
    ppk  = c("IPRED", "DV"),
    tmdd = c("IPRED", "IPRED_TARGET", "DV_L", "DV_R"),
    character(0))
  # The *_ebe.cpp exposure simulator is simulated with outvars="IPRED" only: it reports the
  # individual prediction of the exposure endpoint and nothing else.
  if (identical(tolower(as.character(kind)[1]), "ebe")) return("IPRED")
  need
}

## Compile a translation and check its captures.
## path        .cpp translation
## family      family id (selects pmx_sim_contract)
## compile     TRUE compiles with mrgsolve::mread, FALSE only reads the $CAPTURE lines
## returns     list(ok, family, path, required, missing, error)
pmx_check_simulator <- function(path, family, compile = TRUE, kind = "sim") {
  need <- pmx_sim_contract(family, kind)
  out <- list(ok = FALSE, family = tolower(as.character(family)[1]), path = path,
              required = need, missing = need, error = NULL)
  if (!file.exists(path)) {
    out$error <- paste("missing file", path)
    return(out)
  }
  cap <- character(0)
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  if (is.null(lines)) {
    out$error <- paste("cannot read", path)
    return(out)
  }
  for (ln in lines) {
    if (grepl("^\\s*\\$CAPTURE", ln)) {
      cap <- c(cap, strsplit(sub("^\\s*\\$CAPTURE", "", ln), "[[:space:]]+")[[1]])
    }
  }
  cap <- cap[nzchar(cap)]
  if("IPRED2" %in% cap && out$family %in% c("pkpd","tmdd"))
    cap <- c(cap, if(out$family=="tmdd") "IPRED_TARGET" else "IPRED_PD")
  out$missing <- setdiff(need, cap)
  if (length(out$missing)) {
    out$error <- paste0("translation does not capture ", paste(out$missing, collapse = ", "),
                        " (captures: ", paste(cap, collapse = " "), ")")
    return(out)
  }
  if (isTRUE(compile)) {
    mod <- tryCatch(mrgsolve::mread(path, quiet = TRUE),
                    error = function(e) structure(list(message = conditionMessage(e)), class = "sim_error"))
    if (inherits(mod, "sim_error")) {
      out$error <- paste("does not compile:", mod$message)
      return(out)
    }
  }
  out$ok <- TRUE
  out
}

# Explicit provenance owns regeneration; a descriptive first line is not authorship.
pmx_simulator_action <- function(path,generated,previous=NULL) {
  if(!is.null(previous) && (nrow(previous)!=1L || anyNA(previous[c("Origin","MD5")]) ||
      !previous$Origin %in% c("generated","edited_generated","existing") || !grepl("^[a-f0-9]{32}$",previous$MD5)))
    stop("S2_SIMULATOR_PROVENANCE_INVALID: inspect the recorded origin/hash")
  present <- file.exists(path) && file.info(path)$size>0
  current <- if(present) unname(tools::md5sum(path)) else "missing"
  can_generate <- is.character(generated) && length(generated)==1L && !is.na(generated)
  if(present && !is.null(previous) && previous$Origin=="generated" && identical(current,previous$MD5))
    return(list(action=if(can_generate) "generate" else "author",origin="generated",md5=current))
  if(present) {
    origin <- if(!is.null(previous) && previous$Origin=="generated") "edited_generated" else
      if(!is.null(previous)) previous$Origin else "existing"
    return(list(action="preserve",origin=origin,md5=current))
  }
  list(action=if(can_generate) "generate" else "author",origin="generated",md5=current)
}
