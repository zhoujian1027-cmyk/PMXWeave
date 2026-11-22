#!/usr/bin/env Rscript
.this <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
.here <- if (!is.na(.this) && .this != "-" &&
             file.exists(file.path(dirname(.this), "stage_lib.R"))) dirname(.this) else {
  cand <- c(Sys.getenv("STAGES_DIR", ""), getwd(), file.path(getwd(), "stages"))
  cand <- cand[nzchar(cand)]
  hit  <- cand[file.exists(file.path(cand, "stage_lib.R"))]
  if (!length(hit)) stop("cannot locate stages/stage_lib.R - set STAGES_DIR", call. = FALSE)
  hit[1]
}
HERE <- normalizePath(.here, winslash = "/", mustWork = TRUE)
source(file.path(HERE, "stage_lib.R"))

A <- commandArgs(trailingOnly = TRUE)
opt <- function(flag, default = NULL) {
  if (flag %in% A) A[which(A == flag)[1] + 1] else default
}
has <- function(flag) flag %in% A
FAM   <- opt("--family", "ppk")
FROM  <- opt("--from"); TO <- opt("--to"); ONLY <- opt("--only")
ONLY_STATUS <- has("--status"); FRESH <- has("--fresh"); NSIM <- opt("--nsim", "")
FORCE <- has("--force"); JOB_WINDOW <- has("--job-window")

drop <- function(x) { i <- which(A == x); if (length(i)) A <<- A[-c(i, i + 1)] }
for (f in c("--family", "--from", "--to", "--only", "--nsim")) drop(f)
A <- setdiff(A, c("--status", "--fresh", "--force", "--job-window"))
if (length(A) && nzchar(A[1])) setwd(A[1])
ROOT <- getwd()
if (!identical(Sys.getenv("PMX_LAYOUT", ""), "flat")) pmx_set_root(ROOT)
FAM <- sub("_data\\.csv$", "", FAM)
if (!is.null(FROM)) FROM <- tolower(FROM)
if (!is.null(TO))   TO   <- tolower(TO)
if (!is.null(ONLY)) ONLY <- tolower(ONLY)

for (x in c(FROM, TO, ONLY))
  if (!is.null(x) && !(x %in% STAGES))
    stop("unknown stage '", x, "' (known: ", paste(STAGES, collapse = ", "), ")", call. = FALSE)

gate_table <- function() {
  rows <- lapply(STAGES, function(s) data.frame(
    stage = s, state = if (stage_current(s,FAM)) "DONE" else "missing or stale",
    when = if (stage_done(s))
             sub("^when\t", "", grep("^when\t", readLines(gate_path(s), warn = FALSE), value = TRUE)[1])
           else "-", stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

cat("\n=== stages:", FAM, "|", getwd(), "===\n")
print(gate_table(), row.names = FALSE)
cat("\n")
if (ONLY_STATUS) {
  execution <- c("s1","s1c","s2","s4","s3","s5")
  nxt <- execution[vapply(execution,function(s)!stage_current(s,FAM),TRUE)][1]
  cat(if (is.na(nxt)) "all stages complete\n" else
    paste0("next stage: ", nxt, "  ->  Rscript ", file.path(HERE, paste0(nxt, "_",
      c(s1="fit", s1c="covariance", s2="freeze", s3="figures", s4="html", s5="word")[[nxt]], ".R")),
      " ", shQuote(ROOT), " --family ", FAM, "\n"))
  quit(status = 0)
}

ORDER <- c("s1","s1c","s2","s4","s3","s5")
plan <- ORDER
if (!is.null(ONLY)) {
  plan <- ONLY
} else {
  if (!is.null(FROM)) plan <- plan[seq(match(FROM, ORDER), length(plan))]
  if (!is.null(TO)) {
    idx <- match(TO,plan); if(is.na(idx)) stop("--to precedes --from in execution order")
    plan <- plan[seq_len(idx)]
  }
}
if(!is.null(FROM) && FROM %in% c("s4","s3","s5") && !stage_current("s2",FAM)) {
  if(!all(vapply(c("s1","s1c"),function(s)stage_current(s,FAM),TRUE)))
    stop("REPORT_FREEZE_REVIEW_REQUIRED: S2 is stale and upstream gates do not match; preserve fitted results, inspect the named input/source change, never start SCM automatically")
  plan <- unique(c("s2",plan))
  cat("STAGES_REPORT_PREP refreshing S2 simulator validation from completed S1/S1C; no estimation\n")
}

stage_script <- function(s) file.path(HERE, paste0(s, "_",
  c(s1 = "fit", s1c = "covariance", s2 = "freeze", s3 = "figures", s4 = "html", s5 = "word")[[s]], ".R"))
stage_needs <- list(s1 = character(0), s1c = "s1", s2 = c("s1","s1c"), s3 = "s4", s4 = "s2", s5 = "s3")
ORDER <- c("s1", "s1c", "s2", "s4", "s3", "s5")
plan  <- ORDER[ORDER %in% plan]

cat("plan:", paste(plan, collapse = " -> "), "\n\n")
for (s in plan) {
  need <- stage_needs[[s]]
  missing_gate <- need[!vapply(need,function(up)stage_current(up,FAM),TRUE)]
  if (length(missing_gate)) {
    cat("STOP: stage ", s, " needs gate(s) ", paste(missing_gate, collapse = ", "),
        " - run: Rscript ", stage_script(missing_gate[1]), " ", shQuote(ROOT), " --family ", FAM, "\n", sep = "")
    quit(status = 1)
  }
  if (!FRESH && !FORCE && stage_current(s,FAM)) {
    cat("skip ", s, ": gate present and inputs unchanged\n", sep = "")
    next
  }
  args <- c(shQuote(stage_script(s)), shQuote(ROOT), "--family", FAM)
  if (s == "s1" && FRESH) args <- c(args, "--fresh")
  if (s == "s3" && nzchar(NSIM)) args <- c(args, "--nsim", NSIM)
  status <- system2("Rscript", args)
  if (status == 3) {
    cat("\nSTAGES_DEFER stage ", s, " stopped on its job budget. No gate written; nothing lost.\n",
        "      Re-run the same command to resume (finished stages are skipped, cached fits are reused).\n", sep = "")
    quit(status = 3)
  }
  if (status != 0) {
    cat("\nSTOP: stage ", s, " failed (exit ", status, "). No gate written.\n",
        "      Downstream stages are blocked; fix this stage, do not re-run the pipeline.\n", sep = "")
    quit(status = status)
  }
  remaining <- plan[match(s,plan)+seq_len(length(plan)-match(s,plan))]
  if(JOB_WINDOW && s %in% c("s1","s1c") && length(remaining) &&
     any(!vapply(remaining,function(up)stage_current(up,FAM),TRUE))) {
    cat("STAGES_CHECKPOINT completed=",s," next=",remaining[1],
        "; continue in a fresh job; completed stages remain cached\n",sep="")
    quit(status=3)
  }
}

cat("\n=== gates after this run ===\n")
print(gate_table(), row.names = FALSE)
done <- all(vapply(STAGES,function(s)stage_current(s,FAM),TRUE))
cat(if (done) "\nAll stages complete.\n" else
  paste0("\nRemaining: ",
         paste(STAGES[!vapply(STAGES, stage_done, TRUE)], collapse = ", "), "\n"))
quit(status = if (done || all(vapply(plan,function(s)stage_current(s,FAM),TRUE))) 0 else 2)
