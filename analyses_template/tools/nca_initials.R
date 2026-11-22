#!/usr/bin/env Rscript
Sys.setenv(OMP_NUM_THREADS="1",OMP_THREAD_LIMIT="1",OPENBLAS_NUM_THREADS="1",MKL_NUM_THREADS="1")
args <- c(commandArgs(trailingOnly=TRUE),strsplit(Sys.getenv("PMX_ARGS"),"[[:space:]]+")[[1]])
args <- args[nzchar(args)]
flag <- function(k,default="") {x <- grep(paste0("^--",k,"="),args,value=TRUE); if(length(x)) sub("^[^=]*=","",tail(x,1)) else default}
data <- Sys.getenv("PMX_DATA","")
if(!file.exists(data)) stop("Missing NCA data")
source(file.path(Sys.getenv("PMX_TOOLKIT"),"analyses_template","tools","nca_input.R"))
column <- flag("nca-dv-column","DV")
if(tolower(column) %in% c("lndv","logdv","ln_dv","log_dv") && !nzchar(flag("dv-scale")))
  stop("NCA_SCALE_REQUIRED: declare the actual selected transformed-column scale")
d <- pmx_nca_read(data,column)
for(v in c("id","time","dv","amt","evid")) if(!v %in% names(d)) stop("Missing NCA column: ",v)
scale <- flag("dv-scale","raw"); route <- tolower(flag("route","unknown"))
if(!scale %in% c("raw","log") || !route %in% c("unknown","iv","oral","sc")) stop("Invalid DV scale or route")
depots <- suppressWarnings(as.numeric(flag("depots","")))
tau <- suppressWarnings(as.numeric(flag("tau","")))
blq <- tolower(flag("blq","exclude")); blq_factor <- suppressWarnings(as.numeric(flag("blq-factor","1e4")))
dose_split <- tolower(flag("dose-split","auto")); impute_lz <- tolower(flag("impute-lambda-z","cohort"))
if(nzchar(flag("depots")) && (!is.finite(depots) || depots<0 || depots!=floor(depots))) stop("depots must be a nonnegative integer")
if(nzchar(flag("tau")) && (!is.finite(tau) || tau<=0)) stop("tau must be positive")
if(!blq %in% c("exclude","keep")) stop("--blq must be exclude or keep")
if(!is.finite(blq_factor) || blq_factor<=1) stop("--blq-factor must be > 1")
if(!dose_split %in% c("auto","single","total")) stop("--dose-split must be auto, single or total")
if(!impute_lz %in% c("cohort","off")) stop("--impute-lambda-z must be cohort or off")
obs <- d$evid==0 & d$mdv==0 & is.finite(d$dv)
for(v in c("dvid","cmt")) {
  chosen <- flag(paste0("nca-",v))
  if(nzchar(chosen)) {
    if(!v %in% names(d)) stop("NCA endpoint column missing: ",v)
    code <- suppressWarnings(as.numeric(chosen))
    if(!is.finite(code)) stop("NCA_ENDPOINT_REQUIRED: invalid --nca-",v)
    obs <- obs & !is.na(d[[v]]) & d[[v]]==code
  }
}
if(!nzchar(flag("nca-dvid")) && !nzchar(flag("nca-cmt"))) {
  multi <- any(vapply(intersect(c("dvid","cmt"),names(d)),function(v) length(unique(na.omit(d[[v]][obs])))>1L,TRUE))
  if(multi) stop("Select one PK endpoint using --nca-dvid or --nca-cmt")
}
if(!any(obs)) stop("NCA_ENDPOINT_REQUIRED: selected PK endpoint has no observations")
if(!nzchar(flag("nca-dvid")) && "dvid" %in% names(d) && length(unique(na.omit(d$dvid[obs])))>1L)
  stop("NCA_ENDPOINT_REQUIRED: selected CMT contains multiple DVIDs; specify the PK --nca-dvid")
pmx_nca_scale_check(d,column,scale,obs)
cat("NCA_INPUT column=",column," scale=",scale," pk_dvid=",flag("nca-dvid","unspecified"),
    " pk_cmt=",flag("nca-cmt","unspecified"),"; PD excluded in memory; original data unchanged\n",sep="")
if(scale=="log") d$dv[obs] <- exp(d$dv[obs])
# Route: an explicit --route= always wins. Otherwise a dose CMT that is never observed is extravascular.
route_src <- if(route=="unknown") "unresolved" else "flag"
if(route=="unknown" && "cmt" %in% names(d)) {
  dose_cmt <- unique(na.omit(d$cmt[d$evid!=0]))
  obs_cmt  <- unique(na.omit(d$cmt[obs]))
  if(length(dose_cmt) && length(obs_cmt)) {
    route <- if(all(dose_cmt %in% obs_cmt)) "iv" else "oral"
    route_src <- "inferred_from_CMT"
  }
}
obs <- obs & is.finite(d$dv) & d$dv>=0 & is.finite(d$time)

auc_ll <- function(tt,yy) {
  if(length(tt)<2L) return(NA_real_)
  total <- 0
  for(k in seq.int(2L,length(tt))) {
    dt <- tt[k]-tt[k-1]; if(dt<=0) next
    total <- total + if(yy[k]>=yy[k-1] || min(yy[k],yy[k-1])<=0) dt*(yy[k]+yy[k-1])/2 else dt*(yy[k]-yy[k-1])/log(yy[k]/yy[k-1])
  }
  total
}
# Terminal-phase ladder. `allow` is the BLQ mask. >= 3 points -> best adjusted R^2 over the
# candidate windows. Exactly 2 points is returned as `two_point` so the caller can publish it with
# an explicit quality label. Nothing usable -> NA, and the caller may fall back to the cohort median.
lambda_z <- function(tt,yy,tmax,allow,min_points=3L,min_r2=0.7) {
  keep <- which(tt>tmax & yy>0 & allow)
  n <- length(keep)
  if(n<2L) return(list(value=NA_real_,r2=NA_real_,n=n,n_fit=0L,source="none",monotone=NA))
  monotone <- !any(diff(log(yy[keep]))>1e-8)
  if(n>=min_points) {
    best <- NULL
    for(st in seq_len(n-min_points+1L)) {
      ix <- keep[seq.int(st,n)]; fit <- lm(log(yy[ix])~tt[ix])
      a <- summary(fit)$adj.r.squared; b <- coef(fit)[2]
      if(is.finite(a) && is.finite(b) && b<0 && (is.null(best)||a>best$a)) best <- list(a=a,value=-b,n=length(ix))
    }
    if(!is.null(best) && best$a>min_r2) return(list(value=best$value,r2=best$a,n=n,n_fit=best$n,source="terminal_bestadjr2",monotone=monotone))
  }
  if(n==2L) {
    b <- coef(lm(log(yy[keep])~tt[keep]))[2]
    if(is.finite(b) && b<0) return(list(value=-b,r2=NA_real_,n=n,n_fit=2L,source="two_point",monotone=monotone))
  }
  list(value=NA_real_,r2=NA_real_,n=n,n_fit=0L,source="none",monotone=monotone)
}
bateman_ka <- function(tt,yy,dose,k,v) {
  positive <- tt>0 & yy>0; tt <- tt[positive]; yy <- yy[positive]
  if(length(tt)<4L) return(NA_real_)
  objective <- function(p) {
    ka <- exp(p); if(!is.finite(ka)||ka<=k*1.001) return(1e20)
    pred <- dose/v*ka/(ka-k)*(exp(-k*tt)-exp(-ka*tt))
    sum((log(pmax(pred,1e-12))-log(yy))^2)
  }
  f <- tryCatch(optimize(objective,c(log(k*1.01),log(max(k*100,10/max(min(tt),1e-3))))),error=function(e) NULL)
  if(is.null(f)) NA_real_ else exp(f$minimum)
}
# Nominal dose supporting ONE occasion. Records sharing a time but targeting different compartments
# are one administration split across depots; identical AMT there is the nominal dose (F1/F2 split
# it), so summing would double the amount behind CL/F. Differing AMT are separate amounts -> summed.
occasion_dose <- function(grp) {
  total <- 0; split <- FALSE
  for(ttm in unique(d$time[grp])) {
    g <- grp[d$time[grp]==ttm]; a <- d$amt[g]
    if(length(g)>1L && "cmt" %in% names(d) && length(unique(a))==1L && length(unique(d$cmt[g]))>1L &&
       dose_split!="total") { total <- total + a[1]; split <- TRUE }
    else total <- total + sum(a)
  }
  list(amt=total,split=split)
}
rows <- list()
for(u in unique(d$id)) {
  dr <- which(d$id==u & d$evid==1 & is.finite(d$amt) & d$amt>0 & is.finite(d$time))
  row <- data.frame(subject=u,n_obs=0L,auc_ll=NA_real_,cmax=NA_real_,tmax=NA_real_,c_last=NA_real_,
                    lambda_z=NA_real_,lz_source=NA_character_,cl_f=NA_real_,vz_f=NA_real_,ka=NA_real_,
                    quality=NA_character_,status="NO_DOSE",codes="",n_term=0L,n_term_fit=0L,lz_r2=NA_real_,
                    frac_extrap=NA_real_,n_blq_excl=0L,lambda_z_2pt=NA_real_,dose_amt=NA_real_,
                    occ_start=NA_real_,occ_end=NA_real_,stringsAsFactors=FALSE)
  if(length(dr)) {
    start <- min(d$time[dr]); next_dose <- d$time[dr][d$time[dr]>start]
    end <- min(c(if(is.finite(tau)) start+tau else Inf,next_dose),na.rm=TRUE)
    ix <- which(d$id==u & obs & d$time>=start & d$time<end); ix <- ix[order(d$time[ix])]
    row$occ_start <- start; row$occ_end <- end
    row$n_obs <- length(ix); row$status <- "NO_OBSERVATIONS"
    if(length(ix)>=2L) {
      tt <- d$time[ix]-start; yy <- d$dv[ix]
      cmax <- max(yy); tmax <- tt[which.max(yy)]
      row$cmax <- cmax; row$tmax <- tmax; row$c_last <- tail(yy,1)
      row$auc_ll <- auc_ll(tt,yy); row$status <- "DESCRIPTIVE_ONLY"
      codes <- character(0)
      if(which.max(yy)==1L) codes <- c(codes,"CMAX_AT_FIRST_SAMPLE")
      if(tt[1] > 0.2*max(tt)) codes <- c(codes,"FIRST_SAMPLE_LATE_IN_WINDOW")
      # Dose records supporting THIS occasion only. The interval is bounded by the next dose time,
      # so this is exactly the dose behind the extracted profile.
      dri <- dr[d$time[dr]>=start & d$time[dr]<end]; if(!length(dri)) dri <- dr[d$time[dr]==start]
      oc <- occasion_dose(dri); row$dose_amt <- oc$amt
      if(oc$split) codes <- c(codes,"PARALLEL_DEPOT_DOSE_NOT_SUMMED")
      # Ambiguity is judged on the extracted interval, never on the whole subject: a subject
      # carrying several occasions is not by itself ambiguous. Two dose records sharing a time but
      # targeting DIFFERENT compartments are one parallel/dual-depot occasion; a repeated (time,cmt)
      # pair is a genuine duplicate. Either way the profile is still evaluated, only labelled.
      dosekey <- if("cmt" %in% names(d)) paste(d$time[dri],d$cmt[dri]) else d$time[dri]
      uncertain <- length(unique(d$time[dri]))>1L || anyDuplicated(tt)>0L || anyDuplicated(dosekey)>0L
      for(v in intersect(c("ss","addl","rate"),names(d))) uncertain <- uncertain || any(d[[v]][dri]!=0,na.rm=TRUE)
      if(uncertain) codes <- c(codes,"REGIMEN_REQUIRES_STUDY_NCA")
      # Assay-implausible lows would pin the terminal slope to a placeholder. Dropped from the
      # terminal fit and counted; --blq=keep restores them.
      allow <- rep(TRUE,length(tt))
      if(blq=="exclude" && is.finite(cmax) && cmax>0) allow <- yy >= cmax/blq_factor
      row$n_blq_excl <- sum(!allow)
      if(row$n_blq_excl>0L) codes <- c(codes,"BLQ_EXCLUDED_FROM_LAMBDAZ")
      lz <- lambda_z(tt,yy,tmax,allow)
      row$lambda_z <- lz$value; row$n_term <- lz$n; row$n_term_fit <- lz$n_fit; row$lz_r2 <- lz$r2; row$lz_source <- lz$source
      if(lz$source=="two_point") { row$lambda_z_2pt <- lz$value; codes <- c(codes,"LAMBDAZ_2PT_UNSTABLE") }
      if(lz$source=="none") codes <- c(codes, if(lz$n<3L) "LAMBDAZ_LT3_TERMINAL_POINTS" else "NO_VALID_TERMINAL_PHASE")
      if(isTRUE(lz$monotone==FALSE)) codes <- c(codes,"TERMINAL_NONMONOTONE")
      row$codes <- paste(unique(codes),collapse=";")
    } else if(length(ix)) { row$status <- "TOO_FEW_OBSERVATIONS"; row$codes <- "TOO_FEW_OBSERVATIONS" }
  }
  rows[[length(rows)+1L]] <- row
}
table <- do.call(rbind,rows)
addcode <- function(i,code) {
  cur <- table$codes[i]
  table$codes[i] <<- paste(unique(c(if(nzchar(cur)) strsplit(cur,";",fixed=TRUE)[[1]] else character(0),code)),collapse=";")
}
# --- cohort fallback: no profile is left without a terminal rate if any profile has one ---------
if(impute_lz=="cohort") {
  pool <- table$lambda_z[is.finite(table$lambda_z) & table$lambda_z>0]
  if(length(pool)) for(i in which(!is.finite(table$lambda_z))) {
    table$lambda_z[i] <- median(pool); table$lz_source[i] <- "cohort_median"
    addcode(i,"LAMBDAZ_IMPUTED_COHORT_MEDIAN")
  }
}
# --- one value pass: publish CL/V for every profile with a dose, an AUC and a terminal rate ------
for(i in seq_len(nrow(table))) {
  if(!is.finite(table$lambda_z[i]) || table$lambda_z[i]<=0) next
  if(!is.finite(table$auc_ll[i]) || table$auc_ll[i]<=0) next
  if(!is.finite(table$dose_amt[i]) || table$dose_amt[i]<=0) next
  tail_auc <- table$c_last[i]/table$lambda_z[i]
  frac <- tail_auc/(table$auc_ll[i]+tail_auc)
  table$frac_extrap[i] <- frac
  table$cl_f[i] <- table$dose_amt[i]/(table$auc_ll[i]+tail_auc)
  table$vz_f[i] <- table$cl_f[i]/table$lambda_z[i]
  if(frac>0.3) addcode(i,"EXTRAPOLATION_GT_30_PERCENT")
  if(frac>0.6) addcode(i,"EXTRAPOLATION_GT_60_PERCENT")
  if(identical(table$lz_source[i],"cohort_median")) {
    table$quality[i] <- "imputed"; table$status[i] <- "APPROX_IMPUTED_LAMBDAZ"
  } else if(identical(table$lz_source[i],"terminal_bestadjr2") && frac<=0.3) {
    table$quality[i] <- "good"
    table$status[i] <- if(route=="iv") "APPROX_SINGLE_IV" else "APPROX_SINGLE_APPARENT"
  } else if(identical(table$lz_source[i],"two_point") || frac<=0.6) {
    table$quality[i] <- "approx"
    table$status[i] <- if(route=="iv") "APPROX_SINGLE_IV" else "APPROX_SINGLE_APPARENT"
  } else {
    table$quality[i] <- "poor"; table$status[i] <- "APPROX_RANGE_ONLY"
  }
}
# ka: only meaningful for an extravascular route. Computed for every such profile; the header
# decides whether it may become a $THETA entry (not with several depots / an unresolved route).
if(route %in% c("oral","sc")) for(i in seq_len(nrow(table))) {
  if(!is.finite(table$vz_f[i]) || table$vz_f[i]<=0) next
  ix <- which(d$id==table$subject[i] & obs & d$time>=table$occ_start[i] & d$time<table$occ_end[i])
  if(length(ix)<4L) next
  tt <- d$time[ix]-table$occ_start[i]
  table$ka[i] <- bateman_ka(tt,d$dv[ix],table$dose_amt[i],table$lambda_z[i],table$vz_f[i])
}
out <- Sys.getenv("PMX_NCA_OUT",file.path(dirname(data),"01_screen")); dir.create(out,recursive=TRUE,showWarnings=FALSE)
write.csv(table,file.path(out,"nca_initials.csv"),row.names=FALSE)
rich <- is.finite(table$cl_f) & is.finite(table$vz_f)
med <- function(x) {x <- x[is.finite(x)&x>0]; if(length(x)) median(x) else NA_real_}
rng <- function(x) {x <- x[is.finite(x)&x>0]; if(!length(x)) return("NA")
                     sprintf("%.4g [%.4g - %.4g] n=%d",median(x),min(x),max(x),length(x))}
nq <- function(k) sum(!is.na(table$quality) & table$quality==k)
use <- which(table$quality %in% c("good","approx"))
if(length(use)<3L) use <- which(rich)
cl_use <- med(table$cl_f[use]); vz_use <- med(table$vz_f[use]); ka_use <- med(table$ka[use])
sfx <- if(route=="iv") "" else "/F"                                        # 1-char label suffix, /F for extravascular
ka_line <- if(is.finite(ka_use) && route %in% c("oral","sc") && (!is.finite(depots) || depots==1)) sprintf(" KA=%.6g",ka_use) else ""
allcodes <- unlist(strsplit(table$codes,";",fixed=TRUE)); allcodes <- allcodes[nzchar(allcodes)]
block <- c("; Approximate PK starting values. Screening only: use them as fits, not as results.",
           sprintf("; route=%s (source=%s); DV column=%s scale=%s",route,route_src,column,scale),
           sprintf("; evaluable=%d/%d profiles published CL/V; quality: good=%d approx=%d poor=%d imputed=%d",
                   sum(rich),nrow(table),nq("good"),nq("approx"),nq("poor"),nq("imputed")),
           sprintf("; lambda_z [min - max] h^-1: %s",rng(table$lambda_z)),
           sprintf("; CL/F [min - max]: %s",rng(table$cl_f)),
           sprintf("; V/F  [min - max]: %s",rng(table$vz_f)),
           sprintf("; $THETA below uses the good+approx median (n=%d); median over ALL finite profiles: CL/F=%.4g V/F=%.4g",
                   length(use),med(table$cl_f),med(table$vz_f)),
           "; a single-phase NCA over a multi-phase profile is a range, not a point estimate; frac_extrap and quality are per subject",
           sprintf("; settings: lambda_z=max.adj.R^2(>0.7) over >=3 terminal points, else 2-point only when n=2, else cohort median (%s); blq=%s factor=%.6g dose-split=%s tau=%s",
                   impute_lz,blq,blq_factor,dose_split,if(is.finite(tau)) format(tau) else "unset"),
           paste0("; explicit absorption structure hint: ",if(is.finite(depots)) depots else "unspecified",
                  " depot(s); NCA does not determine their rates."))
# ONE-line digest, first in the file. NCA is a screening step, not a deliverable: read THIS line
# (or the final NCA_OK line) and nothing else - never the per-subject nca_initials.csv.
if(any(rich)) block <- c(sprintf("; INITIALS TVCL%s=%.6g TVV%s=%.6g%s  <-- the only digits needed here (n=%d good+approx)",
                                 sfx,cl_use,sfx,vz_use,ka_line,length(use)), block)
if(length(allcodes)) block <- c(block,paste0("; status codes: ",paste(sprintf("%s=%d",names(table(allcodes)),table(allcodes)),collapse=" ")))
if(any(rich)) {
  block <- c(block,"$THETA",
             sprintf(" (0, %.6g) ; TVCL%s",cl_use,if(route=="iv") "" else "/F"),
             sprintf(" (0, %.6g) ; TVV%s",vz_use,if(route=="iv") "" else "/F"))
  if(is.finite(ka_use) && route %in% c("oral","sc")) {
    if(!is.finite(depots) || depots==1) block <- c(block,sprintf(" (0, %.6g) ; TVKA (single absorption approximation)",ka_use))
    else block <- c(block,sprintf("; ka approximation (NOT a $THETA entry - %s depots declared): %s",format(depots),rng(table$ka)))
  }
} else block <- c(block,"; no profile produced CL/V (no dose, or fewer than 2 observations, or no terminal rate at all)")
if(route=="unknown") block <- c(block,"; ROUTE_UNRESOLVED: CL/V are NOT labelled /F and no ka was produced - pass --route=iv|oral|sc")
block <- c(block,"; OMEGA/SIGMA and additional absorption/TMDD/PD parameters require justified model-specific initials.")
writeLines(block,file.path(out,"nca_initials.txt")); writeLines(block,file.path(out,".nca_initials.txt"))
Sys.chmod(file.path(out,c("nca_initials.csv","nca_initials.txt",".nca_initials.txt")),"0644")
cat(paste(block,collapse="\n"),"\n")
cat(if(any(rich)) "NCA_OK" else "NCA_SPARSE"," n_rich=",sum(rich)," n_tot=",nrow(table),
    if(any(rich)) sprintf(" INITIALS TVCL%s=%.6g TVV%s=%.6g%s",sfx,cl_use,sfx,vz_use,ka_line) else "",
    " table=",file.path(out,"nca_initials.csv"),"\n",sep="")
