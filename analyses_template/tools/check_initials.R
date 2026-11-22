#!/usr/bin/env Rscript
Sys.setenv(OMP_NUM_THREADS="1",OMP_THREAD_LIMIT="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1")

args <- commandArgs(trailingOnly = TRUE)
ctl  <- if (length(args) >= 1 && nzchar(args[1])) args[1] else Sys.getenv("PMX_CTL")
data <- if (length(args) >= 2 && nzchar(args[2])) args[2] else Sys.getenv("PMX_DATA")
if (!nzchar(ctl) || !file.exists(ctl)) { cat("INIT_BAD n=1 codes=NO_CTL\n"); quit(save = "no") }

L   <- readLines(ctl, warn = FALSE)
rec <- character(length(L)); cur <- ""
for (i in seq_along(L)) {
  if (grepl("^\\s*\\$", L[i])) cur <- toupper(sub("^\\s*\\$([A-Za-z0-9_]+).*", "\\1", L[i]))
  rec[i] <- cur
}
take <- function(r) { i <- which(rec == r); if (!length(i)) character(0) else L[i] }

tok <- function(code) {                      # -> list of numeric vectors, in order
  code <- sub("\\$[A-Za-z0-9_]+", " ", code)
  hold <- character(0)
  repeat {
    m <- regexpr("\\([^)]*\\)", code)
    if (m[1] == -1) break
    hold <- c(hold, regmatches(code, m))
    code <- sub("\\([^)]*\\)", paste0(" @", length(hold), " "), code)
  }
  parts <- strsplit(code, "[,[:space:]]+")[[1]]; parts <- parts[nzchar(parts)]
  out <- list()
  for (p in parts) {
    if (substr(p, 1, 1) == "@") {
      i <- as.integer(sub("^@", "", p)); inner <- hold[i]
      inner <- substr(inner, 2, nchar(inner) - 1)
      v <- suppressWarnings(as.numeric(strsplit(inner, "[,[:space:]]+")[[1]]))
      v <- v[is.finite(v)]; if (length(v)) out[[length(out) + 1]] <- v
    } else { v <- suppressWarnings(as.numeric(p)); if (is.finite(v)) out[[length(out) + 1]] <- v }
  }
  out
}

parse_rec <- function(lines) {               # -> list(vals=list of vec, names=chr)
  vals <- list(); nms <- character(0)
  for (ln in lines) {
    p <- strsplit(ln, ";", fixed = TRUE)[[1]]
    cmt <- if (length(p) > 1) paste(p[-1], collapse = " ") else ""
    t <- tok(p[1]); if (!length(t)) next
    w <- strsplit(trimws(cmt), "[[:space:]]+")[[1]]; w <- w[nzchar(w)]
    w <- w[!grepl("^[0-9.]+$", w)]
    # "; THETA(1) TVVC" / "; OMEGA(3) IIV KA" -> keep the parameter name, drop the record
    # index. Without this the name became "THETA(1)", so iCL/iV/iKA never matched and the
    # FLIPFLOP, F1_RANGE, TLAG and SCALE checks silently skipped instead of reporting.
    w <- w[!grepl("^(THETA|OMEGA|SIGMA|ETA|EPS)[[:space:]]*\\(?[0-9]*\\)?$", w, ignore.case = TRUE)]
    for (k in seq_along(t)) {
      vals[[length(vals) + 1]] <- t[[k]]
      nms <- c(nms, if (k <= length(w)) w[k] else "")
    }
  }
  if (!length(vals)) return(NULL)
  if (all(!nzchar(nms))) {                   # fallback: TV* assignments in $PK/$PRED
    pk <- c(take("PK"), take("PRED"), take("MODEL"))
    g  <- unlist(regmatches(pk, gregexpr("^\\s*(TV[A-Za-z0-9_]*)\\s*=", pk)))
    if (length(g) == length(vals)) nms <- sub("^\\s*([A-Za-z0-9_]+)\\s*=.*$", "\\1", g)
  }
  if (all(!nzchar(nms))) nms <- paste0("THETA", seq_along(vals))
  list(vals = vals, names = toupper(nms))
}

th <- parse_rec(take("THETA"))
if (is.null(th)) { cat("INIT_BAD n=1 codes=NO_THETA\n"); quit(save = "no") }
om <- parse_rec(take("OMEGA")); sg <- parse_rec(take("SIGMA"))

th_init <- function(i) th$vals[[i]][max(1, min(2, length(th$vals[[i]])))]
th_lo   <- function(i) { v <- th$vals[[i]]; if (length(v) == 1) -Inf else v[1] }
th_up   <- function(i) { v <- th$vals[[i]]; if (length(v) >= 3) v[3] else Inf }
geti <- function(pat) { i <- grep(paste0("^", pat, "$"), th$names); if (length(i)) i[1] else NA_integer_ }
iV  <- geti("(TV)?VC?[0-9]?"); iV2 <- geti("(TV)?V[0-9]")
iCL <- geti("(TV)?CL[0-9]?")
iKA <- geti("(TV)?KA[0-9]?[A-Z]?")
iF1 <- geti("(TV)?F1")
iTL <- geti("(TV)?(A|T)LAG[0-9]*")

BAD <- character(0); ADV <- character(0); SOFT <- character(0)
say <- function(tag, ok, msg) { if (!ok) BAD <<- c(BAD, tag) else invisible(NULL); cat(sprintf("%-9s %-4s %s\n", tag, if (ok) "ok" else "BAD", msg)) }
say_soft <- function(tag, ok, msg) { cat(sprintf("%-9s %-4s %s\n", tag, if (ok) "ok" else "WARN", msg)); if (!ok) { SOFT <<- c(SOFT, tag); ADV <<- c(ADV, sprintf("%s: %s", tag, msg)) } else invisible(NULL) }

for (i in seq_along(th$vals)) {
  lo <- th_lo(i); up <- th_up(i); iv <- th_init(i)
  say("BOUNDS", iv >= lo && iv <= up, sprintf("%s init=%g in [%g, %g]", th$names[i], iv, lo, up))
}

dv_log <- FALSE; obs_max <- NA_real_; tmax <- NA_real_; dose <- NA_real_
if (nzchar(data) && file.exists(data)) {
  d <- try(read.csv(data, stringsAsFactors = FALSE), silent = TRUE)
  if (!inherits(d, "try-error") && nrow(d)) {
    H <- toupper(trimws(names(d)))
    pk <- function(al) { for (a in al) { j <- match(a, H); if (!is.na(j)) return(j) }; NA_integer_ }
    jDV <- pk(c("DV", "CONC", "Y", "LNDV", "CP")); jMDV <- pk(c("MDV", "MDV_"))
    jEV <- pk("EVID"); jAM <- pk(c("AMT", "DOSE")); jT <- pk(c("TIME", "TAD"))
    jI <- pk(c("ID", "ID_"))
    if (!is.na(jDV) && !is.na(jT)) {
      obs <- rep(TRUE, nrow(d))
      if (!is.na(jMDV)) obs <- obs & d[[jMDV]] == 0
      if (!is.na(jEV))  obs <- obs & d[[jEV]] == 0
      obs[is.na(obs)] <- FALSE
      dv <- suppressWarnings(as.numeric(d[[jDV]][obs]))
      tt <- suppressWarnings(as.numeric(d[[jT]][obs]))
      finite <- is.finite(dv) & is.finite(tt)
      dv <- dv[finite]; tt <- tt[finite]
      if (length(dv)) {
        dv_log  <- min(dv) < 0
        obs_max <- if (dv_log) max(dv) else max(dv)
        tmax    <- tt[which.max(dv)]
      }
    }
    if (!is.na(jAM) && !is.na(jEV) && !is.na(jI) && !is.na(jT)) {
      ds <- d[d[[jEV]] == 1, , drop = FALSE]
      if (nrow(ds)) {
        key <- paste(ds[[jI]], ds[[jT]])
        sm  <- tapply(suppressWarnings(as.numeric(ds[[jAM]])), key, sum, na.rm = TRUE)
        sm  <- sm[is.finite(sm) & sm > 0]
        if (length(sm)) dose <- stats::median(sm)
      }
    }
    cat(sprintf("%-9s %-4s %s\n", "DATA", "ok",
      sprintf("obs_max=%g tmax=%g dose=%g scale=%s", obs_max, tmax, dose, if (dv_log) "log" else "linear")))
  }
}

CL <- if (!is.na(iCL)) th_init(iCL) else NA_real_
V  <- if (!is.na(iV))  th_init(iV)  else if (!is.na(iV2)) th_init(iV2) else NA_real_
KA <- if (!is.na(iKA)) th_init(iKA) else NA_real_
F1 <- if (!is.na(iF1)) th_init(iF1) else 1

if (is.finite(CL) && is.finite(V) && is.finite(KA)) {
  k <- CL / V
  say_soft("FLIPFLOP", KA > k, sprintf("ka=%g vs k=CL/V=%g -> need ka > k", KA, k))
  if (KA <= k) ADV <- c(ADV, sprintf("set TVKA initial above %g", signif(k * 1.5, 3)))
}

if (!is.na(iF1)) say("F1_RANGE", F1 > 0 && F1 <= 1, sprintf("F1=%g must be in (0,1]", F1))

# Use the same fixed-parameter rule as the fitting gate.
if(!exists("pmx_fixed_parameters",mode="function")) {
  file_arg <- sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE))
  rules <- if(length(file_arg)) file.path(dirname(file_arg[1]),"data_filters.R") else ""
  if(!file.exists(rules)) stop("INIT_BAD codes=NOFIX shared fixed-parameter checker unavailable")
  source(rules)
}
eta_problem <- tryCatch({pmx_check_indexed_eta(ctl);NULL},error=function(e) conditionMessage(e))
if(!is.null(eta_problem)) {cat("INIT_BAD codes=ETA_INDEX ",eta_problem,"\n",sep="");quit(status=1)}
hard_fix <- pmx_fixed_parameters(L)
say("NOFIX",!length(hard_fix),if(length(hard_fix)) paste("unapproved:",paste(hard_fix,collapse=", ")) else "no unapproved fixed parameters")
if(length(hard_fix)) ADV <- c(ADV,"Estimate the named parameters. A PMX_FIXED comment is disclosure, not authorization; the agent cannot approve its own fix.")
if (!is.na(iTL)) {
  tl <- th_init(iTL)
  say_soft("TLAG", !is.finite(tmax) || tl >= 0 && tl < tmax, sprintf("tlag=%g vs observed tmax=%g", tl, tmax))
}

if (is.finite(obs_max) && is.finite(KA) && is.finite(CL) && is.finite(V) && is.finite(dose)) {
  k <- CL / V
  if (KA > k) {
    tm <- log(KA / k) / (KA - k)
    cp <- (F1 * dose / V) * (KA / (KA - k)) * (exp(-k * tm) - exp(-KA * tm))
    if (dv_log) {
      dd <- log(cp) - obs_max
      say_soft("SCALE", abs(dd) < log(10), sprintf("log-space pred peak %.2f vs obs max %.2f (diff %+.2f)", log(cp), obs_max, dd))
    } else {
      r <- cp / obs_max
      say_soft("SCALE", r > 0.1 && r < 10, sprintf("pred peak %g vs obs max %g (ratio %.2f)", cp, obs_max, r))
    }
  } else cat(sprintf("%-9s %-4s %s\n", "SCALE", "skip", "ka <= k, no peak to compare (see FLIPFLOP)"))
}

chk_var <- function(X, tag, lo, hi) {
  if (is.null(X)) { cat(sprintf("%-9s %-4s %s\n", tag, "skip", "no record")); return(invisible()) }
  v <- unlist(X$vals); v <- v[is.finite(v) & v > 0]
  if (!length(v)) return(invisible())
  cv <- 100 * sqrt(v)
  say_soft(tag, all(cv >= lo & cv <= hi), sprintf("implied CV%% = %s", paste(signif(cv, 3), collapse = ", ")))
}
chk_var(om, "OMEGA", 3, 100)
chk_var(sg, "SIGMA", 1, 150)

out <- sub("\\.ctl$", ".initials.txt", ctl, ignore.case = TRUE)
if (identical(out, ctl)) out <- paste0(ctl, ".initials.txt")
writeLines(c(sprintf("# %s  %s", ctl, format(Sys.time())),
             sprintf("# checks: hard=BOUNDS,F1_RANGE,NOFIX soft=FLIPFLOP,TLAG,SCALE,OMEGA,SIGMA"),
             sprintf("# bad=%d codes=%s soft=%d softcodes=%s", length(BAD), if (length(BAD)) paste(unique(BAD), collapse = ",") else "-",
                     length(SOFT), if (length(SOFT)) paste(unique(SOFT), collapse = ",") else "-"),
             sprintf("# advice: %s", if (length(ADV)) paste(ADV, collapse = "; ") else "-")), out)

if (!length(BAD)) {
  cat(sprintf("INIT_OK thetas=%d checks=8 bad=0 soft=%d file=%s\n", length(th$vals), length(SOFT), out))
  if (length(SOFT)) cat(sprintf("INIT_WARN n=%d codes=%s advice=%s\n", length(SOFT), paste(unique(SOFT), collapse = ","),
                                paste(ADV, collapse = "; ")))
} else {
  cat(sprintf("INIT_BAD n=%d codes=%s advice=%s\n", length(BAD), paste(unique(BAD), collapse = ","),
              if (length(ADV)) paste(ADV, collapse = "; ") else "use template defaults"))
}
quit(save = "no")
