# One compute budget; independent R workers share it rather than each taking it.
pmx_cpu_integer <- function(name, default) {
  raw <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.numeric(raw))
  if (length(value)!=1L || !is.finite(value) || value<1 || value!=floor(value))
    stop(name, " must be a positive integer")
  as.integer(value)
}
# Linux detectCores(FALSE) may count hardware threads; use allowed-CPU topology.
pmx_physical_cores <- function(status="/proc/self/status",topology="/sys/devices/system/cpu",
                               system=Sys.info()[["sysname"]],detect=parallel::detectCores) {
  if(system!="Linux") {
    n <- if(system %in% c("Windows","Darwin","SunOS")) detect(logical=FALSE) else 1L
    return(if(length(n)==1L && is.finite(n) && n>=1L) as.integer(n) else 1L)
  }
  one <- function(p) if(file.exists(p)) tryCatch(trimws(paste(readLines(p,n=1L,warn=FALSE),collapse="")),error=function(e)"") else ""
  text <- tryCatch(readLines(status,warn=FALSE),error=function(e)character())
  allowed <- sub("^Cpus_allowed_list:[[:space:]]*","",grep("^Cpus_allowed_list:",text,value=TRUE))
  if(length(allowed)!=1L || !grepl("^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$",allowed)) return(1L)
  cpus <- unlist(lapply(strsplit(allowed,",",fixed=TRUE)[[1]],function(x) {
    ends <- as.integer(strsplit(x,"-",fixed=TRUE)[[1]])
    if(anyNA(ends) || tail(ends,1)<ends[1]) return(integer())
    seq.int(ends[1],tail(ends,1))
  }))
  if(!length(cpus)) return(1L)
  keys <- vapply(cpus,function(cpu) {
    dir <- file.path(topology,paste0("cpu",cpu),"topology")
    siblings <- one(file.path(dir,"core_cpus_list"))
    if(!nzchar(siblings)) siblings <- one(file.path(dir,"thread_siblings_list"))
    if(grepl("^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$",siblings)) return(paste0("siblings:",siblings))
    package <- one(file.path(dir,"physical_package_id"));core <- one(file.path(dir,"core_id"))
    if(grepl("^[0-9]+$",package) && grepl("^[0-9]+$",core)) paste(package,core,sep=":") else ""
  },"")
  if(all(nzchar(keys))) length(unique(keys)) else 1L
}
pmx_cpu_budget <- function() {
  automatic <- max(1L,pmx_physical_cores()-2L)
  quota <- Inf
  # A cgroup quota can lower the budget; it cannot increase physical-core capacity.
  paths <- list(c("/sys/fs/cgroup/cpu.max"),c("/sys/fs/cgroup/cpu/cpu.cfs_quota_us","/sys/fs/cgroup/cpu/cpu.cfs_period_us"),
                c("/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us","/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_period_us"))
  for(files in paths) if(all(file.exists(files))) {
    fields <- unlist(strsplit(paste(vapply(files,function(p)readLines(p,n=1L,warn=FALSE),""),collapse=" "),"[[:space:]]+"))
    values <- suppressWarnings(as.numeric(fields))
    if(length(values)==2L && all(is.finite(values)) && all(values>0)) quota <- min(quota,max(1L,floor(values[1]/values[2])))
  }
  as.integer(min(automatic,pmx_cpu_integer("PMX_R_CORES",automatic),quota))
}
pmx_fit_threads <- function() min(7L,pmx_cpu_integer("PMX_FIT_THREADS",7L),pmx_cpu_budget())
# Resource timing is separate from scientific fit/cache identity.
pmx_cpu_timing_host <- function() {
  cpu <- if(file.exists("/proc/cpuinfo")) unique(grep("^(model name|Hardware)[[:space:]]*:",readLines("/proc/cpuinfo",warn=FALSE),value=TRUE)) else Sys.info()["machine"]
  paste(c(Sys.info()[c("sysname","machine")],cpu,parallel::detectCores(logical=TRUE)),collapse="|")
}
# Warm, three-iteration PPK benchmark: a scheduling prior, never a fit/accuracy setting.
pmx_fit_speed <- function(threads) stats::approx(c(1,2,4,7),c(1,1.84,3.51,4.72),
  xout=pmax(1,pmin(7,threads)),rule=2)$y
pmx_cpu_setup <- function(threads=pmx_fit_threads(), rx=FALSE) {
  threads <- max(1L,min(as.integer(threads),pmx_fit_threads()))
  Sys.setenv(OMP_NUM_THREADS=as.character(threads), OMP_THREAD_LIMIT=as.character(threads),
             OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1", BLIS_NUM_THREADS="1")
  if ("RhpcBLASctl" %in% loadedNamespaces()) RhpcBLASctl::blas_set_num_threads(1L)
  if (rx) rxode2::setRxThreads(threads)
  invisible(threads)
}
pmx_available_memory <- function() {
  memory <- Inf
  if (file.exists("/proc/meminfo")) {
    line <- grep("^MemAvailable:",readLines("/proc/meminfo",warn=FALSE),value=TRUE)
    if (length(line)) memory <- as.numeric(gsub("[^0-9]","",line[1]))*1024
  }
  for (pair in list(c("/sys/fs/cgroup/memory.max","/sys/fs/cgroup/memory.current"),
                    c("/sys/fs/cgroup/memory/memory.limit_in_bytes","/sys/fs/cgroup/memory/memory.usage_in_bytes"))) {
    if (!all(file.exists(pair))) next
    limit <- suppressWarnings(as.numeric(readLines(pair[1],n=1L,warn=FALSE)))
    used <- suppressWarnings(as.numeric(readLines(pair[2],n=1L,warn=FALSE)))
    if (is.finite(limit) && is.finite(used)) memory <- min(memory,max(0,limit-used))
  }
  memory
}
pmx_cpu_plan <- function(n, worker_cap=pmx_cpu_integer("PMX_MC_CORES",6L), data_bytes=0) {
  budget <- pmx_cpu_budget()
  # Six processes bound concurrent compilation and memory duplication.
  cap <- min(6L,pmx_cpu_integer("PMX_MAX_MODEL_WORKERS",6L))
  model_mb <- pmx_cpu_integer("PMX_MODEL_MEMORY_MB",2048L)
  reserve_mb <- pmx_cpu_integer("PMX_MEMORY_RESERVE_MB",4096L)
  available <- pmx_available_memory()
  per_worker <- model_mb*1024^2+2*as.numeric(data_bytes)
  memory_cap <- if (is.finite(available)) max(0L,floor((available-reserve_mb*1024^2)/per_worker)) else budget
  if(memory_cap<1L) stop("PMX_MEMORY_BUDGET_BLOCKED: insufficient available memory after the configured memory reserve; no model worker started")
  workers <- max(1L,min(as.integer(n),worker_cap,cap,budget,memory_cap))
  list(budget=budget,workers=workers,threads=min(pmx_fit_threads(),max(1L,budget%/%workers)),
       memory_cap=memory_cap,available_bytes=available)
}
pmx_cpu_log <- function(phase, plan) {
  cat("PMX_CPU_PLAN phase=",phase," budget=",plan$budget," workers=",plan$workers,
      " threads_per_worker=",plan$threads," compute_threads=",plan$workers*plan$threads,
      " memory_worker_cap=",plan$memory_cap,"\n",sep="")
}
