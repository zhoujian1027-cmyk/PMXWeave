# Shared report intake: semantic selection belongs to the agent, not a column-name guesser.
pmx_covariate_intake <- function(config, family, envir=parent.frame(), audit=TRUE) {
  fail <- function(message) stop("PMX_COVARIATE_INTAKE_REQUIRED: ", message, call.=FALSE)
  if(length(config)!=1L || is.na(config) || !nzchar(config) || !file.exists(config))
    fail("review the actual study data and save pmx_config.R before analysis; no configuration is not a no-covariate decision")
  cfg <- new.env(parent=envir)
  sys.source(config, envir=cfg)
  if(!exists("COVARIATE_REVIEW",cfg,inherits=FALSE))
    fail("pmx_config.R needs COVARIATE_REVIEW: data.frame(variable, role, reason), covering the inspected fields")
  review <- cfg$COVARIATE_REVIEW
  if(!is.data.frame(review) || !all(c("variable","role","reason") %in% names(review)) || !nrow(review))
    fail("COVARIATE_REVIEW must have nonempty variable/role/reason rows")
  review <- review[,c("variable","role","reason"),drop=FALSE]
  review[] <- lapply(review,as.character)
  review$variable <- trimws(review$variable); review$role <- tolower(trimws(review$role))
  if(anyNA(review$variable) || any(!nzchar(review$variable)) || anyDuplicated(tolower(review$variable)) ||
     anyNA(review$role) || any(!review$role %in% c("continuous","categorical","prespecified","excluded")))
    fail("each reviewed field needs one unique name and role continuous/categorical/prespecified/excluded")
  omitted <- review$role=="excluded"
  if(any(is.na(review$reason[omitted]) | !nzchar(trimws(review$reason[omitted]))))
    fail("every excluded field needs its data/role reason or the explicit user restriction")
  if(family!="cqtc" && any(review$role=="prespecified"))
    fail("prespecified is reserved for c-QTc base adjustments; retain each fit-family variable's continuous/categorical role and declare both parameter pairs, including existing base effects")
  names_for <- function(role) review$variable[review$role %in% role]
  declared <- function(name) {
    if(!exists(name,cfg,inherits=FALSE)) fail(paste("pmx_config.R must explicitly set",name,"from the reviewed data"))
    x <- get(name,cfg,inherits=FALSE)
    if(!is.character(x) || anyNA(x) || any(!nzchar(x)) || anyDuplicated(tolower(x)))
      fail(paste(name,"must be a unique character vector; character() explicitly declares none"))
    tolower(x)
  }
  same <- function(x,y) identical(sort(tolower(x)),sort(tolower(y)))
  if(family=="er") {
    differences <- function(key, role) {
      configured <- declared(key)
      reviewed <- names_for(role)
      missing <- reviewed[!tolower(reviewed) %in% configured]
      extra <- setdiff(configured,tolower(reviewed))
      c(if(length(missing)) paste(key,"missing reviewed fields:",paste(missing,collapse=", ")),
        if(length(extra)) paste(key,"has fields without a matching review role:",paste(extra,collapse=", ")))
    }
    mismatch <- c(differences("CON_COV","continuous"),differences("CAT_COV","categorical"))
    if(length(mismatch)) fail(paste(mismatch,collapse="; "))
  } else if(family=="cqtc") {
    optional <- names_for(c("continuous","categorical")); prescribed <- names_for("prespecified")
    want <- declared("cov_want"); cats <- declared("cov_categorical")
    if(!same(setdiff(want,tolower(prescribed)),optional) ||
       !same(cats,names_for("categorical")))
      fail("cov_want/cov_categorical must match the reviewed optional fields; preserve baseline QTcF in mandatory_cov")
  } else if(!family %in% c("ppk","pkpd","tmdd")) fail("unknown report family")
  # Apply study overrides only after validating explicit declarations, never example defaults.
  list2env(as.list(cfg,all.names=TRUE),envir=envir)
  if(audit) {
    dir.create("table",showWarnings=FALSE)
    write.csv(review,"table/_covariate_scope.csv",row.names=FALSE,na="")
  }
  cat("COVARIATE_INTAKE family=",family," continuous=",length(names_for("continuous")),
      " categorical=",length(names_for("categorical"))," prespecified=",length(names_for("prespecified")),
      " excluded=",sum(omitted),"\n",sep="")
  review
}

pmx_covariate_pair_coverage <- function(configured, review, params) {
  included <- tolower(review$variable[review$role %in% c("continuous","categorical")])
  pairs <- do.call(rbind,lapply(configured,function(cd) do.call(rbind,lapply(names(cd$eff),function(p)
    do.call(rbind,lapply(cd$eff[[p]],function(e) data.frame(param=toupper(p),covariate=tolower(e$cov),type=e$type)))))))
  if(is.null(pairs)) pairs <- data.frame(param=character(),covariate=character(),type=character())
  if(any(!pairs$covariate %in% included)) stop("SCM_SCOPE_MISMATCH: CSV tests fields not included in COVARIATE_REVIEW",call.=FALSE)
  kind <- setNames(review$role,tolower(review$variable))[pairs$covariate]
  if(any((kind=="categorical") != (pairs$type=="cat")))
    stop("SCM_SCOPE_MISMATCH: CSV effect type disagrees with reviewed continuous/categorical role",call.=FALSE)
  key <- function(p,c) paste(toupper(p),tolower(c),sep=":")
  have <- key(pairs$param,pairs$covariate)
  excluded <- attr(configured,"excluded")
  if(!is.null(excluded) && nrow(excluded)) have <- c(have,key(excluded$param,excluded$covariate))
  grid <- expand.grid(param=params,covariate=included,stringsAsFactors=FALSE)
  missing <- setdiff(key(grid$param,grid$covariate),have)
  if(length(included) && !length(params)) stop("SCM_PARAMETER_SCOPE: cannot resolve the CL/central-volume THETA symbols from $PK; preserve the model and resolve the mapping",call.=FALSE)
  if(length(missing)) stop("SCM_SCOPE_INCOMPLETE: declare every reviewed covariate on the model's CL and central-volume THETA symbols (",paste(params,collapse=", "),") in covariates.csv; missing ",paste(missing,collapse=", "),call.=FALSE)
  invisible(TRUE)
}
