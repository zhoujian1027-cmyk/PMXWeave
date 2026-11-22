
# Objects some loader in this process may ask for by SONAME. Never dlopen an arbitrary file.
pmx_word_preload_names <- c("libwebpmux.so.3", "libwebpdemux.so.2")

# Can the system resolve this SONAME on its own? ldconfig -p is the linker's own view, and the
# fallback list covers an image with no ldconfig (or a lib staged into a standard directory).
pmx_word_soname_resolvable <- function(so) {
  ld <- tryCatch(suppressWarnings(system2("ldconfig", "-p", stdout = TRUE, stderr = FALSE)),
                 error = function(e) character(0))
  if (!length(ld)) {
    ld <- tryCatch(suppressWarnings(system2("/sbin/ldconfig", "-p", stdout = TRUE, stderr = FALSE)),
                   error = function(e) character(0))
  }
  if (length(ld) && any(grepl(so, ld, fixed = TRUE))) return(TRUE)
  dirs <- c(strsplit(Sys.getenv("LD_LIBRARY_PATH", ""), ":")[[1]],
            "/lib", "/usr/lib", "/usr/local/lib",
            Sys.glob("/lib/*-linux-gnu"), Sys.glob("/usr/lib/*-linux-gnu"))
  any(vapply(dirs[nzchar(dirs)], function(d) file.exists(file.path(d, so)), TRUE))
}

# Directories searched for the staged objects, in order. `dirs` (study/script specific) comes first.
pmx_word_lib_dirs <- function(dirs = NULL) {
  cand <- c(dirs,
            Sys.getenv("PMX_WORD_LIB", ""),
            file.path(getwd(), ".pmx", "word-report", "lib"),
            file.path(getwd(), "word-report", "lib"),
            file.path(getwd(), ".pmx", "pmx_workspace", "word-report", "lib"))
  cand <- cand[nzchar(cand)]
  unique(cand[dir.exists(cand)])
}

# Map every staged object the system cannot resolve. Returns the SONAMEs mapped, invisibly.
pmx_preload_word_libs <- function(dirs = NULL, verbose = FALSE) {
  mapped <- character(0)
  for (so in pmx_word_preload_names) {
    if (so %in% mapped) next
    if (pmx_word_soname_resolvable(so)) {
      if (verbose) message("PRELOAD_WORD_LIBS_SYSTEM ", so, " already resolvable; nothing staged")
      next
    }
    for (d in pmx_word_lib_dirs(dirs)) {
      f <- file.path(d, so)
      if (!file.exists(f)) next
      ok <- tryCatch({ dyn.load(f); TRUE },
                     error = function(e) { if (verbose) message("PRELOAD_SKIP ", f, ": ", conditionMessage(e)); FALSE })
      if (ok) { mapped <- c(mapped, so); break }
    }
  }
  if (length(mapped)) message("PRELOAD_WORD_LIBS ", paste(mapped, collapse = ", "))
  invisible(mapped)
}
