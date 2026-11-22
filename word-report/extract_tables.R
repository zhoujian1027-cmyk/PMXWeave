#!/usr/bin/env Rscript
ARGS <- commandArgs(trailingOnly = TRUE)
OUT_ARG <- NULL
oi <- which(ARGS == "--out")
if (length(oi)) { OUT_ARG <- ARGS[oi[1] + 1]; ARGS <- ARGS[-c(oi[1], oi[1] + 1)] }
if (!length(ARGS)) stop("usage: Rscript extract_tables.R <report.html | analysis_dir> [--out DIR]")

TARGET <- ARGS[1]
if (dir.exists(TARGET)) {
  cand <- list.files(TARGET, pattern = "_report\\.html$|_analysis\\.html$", full.names = TRUE)
  if (!length(cand)) cand <- list.files(TARGET, pattern = "\\.html$", full.names = TRUE)
  if (!length(cand)) stop("no *.html in ", TARGET)
  HTML <- cand[which.max(file.size(cand))]      # the full report, not a stub
  DIR  <- normalizePath(TARGET)
} else {
  HTML <- TARGET
  DIR  <- dirname(normalizePath(TARGET))
}
stopifnot(file.exists(HTML))
OUTDIR <- if (is.null(OUT_ARG)) file.path(DIR, "table") else
  if (grepl("^(/|\\.)", OUT_ARG)) OUT_ARG else file.path(DIR, OUT_ARG)
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

entities <- function(s) {
  map <- c("&amp;" = "&", "&lt;" = "<", "&gt;" = ">", "&quot;" = "\"",
           "&#39;" = "'", "&apos;" = "'", "&nbsp;" = " ", "&plusmn;" = "\u00b1",
           "&Delta;" = "\u0394", "&delta;" = "\u03b4", "&ge;" = "\u2265",
           "&le;" = "\u2264", "&times;" = "\u00d7", "&minus;" = "\u2212",
           "&ndash;" = "\u2013", "&mdash;" = "\u2014", "&micro;" = "\u00b5")
  for (k in names(map)) s <- gsub(k, map[[k]], s, fixed = TRUE)
  num <- regmatches(s, gregexpr("&#[0-9]+;", s))[[1]]
  for (e in unique(num)) s <- gsub(e, intToUtf8(as.integer(sub("^&#|;$", "", e))),
                                   s, fixed = TRUE)
  s
}
strip_tags <- function(s) trimws(gsub("[[:space:]]+", " ", entities(gsub("<[^>]*>", "", s))))

txt <- paste(readLines(HTML, warn = FALSE), collapse = "\n")
txt <- gsub("(?s)<script[^>]*>.*?</script>", " ", txt, perl = TRUE)
txt <- gsub("(?s)<style[^>]*>.*?</style>", " ", txt, perl = TRUE)

hd <- gregexpr("(?s)<h([1-4])[^>]*>.*?</h\\1>", txt, perl = TRUE)
htxt <- vapply(regmatches(txt, hd)[[1]], strip_tags, "")
hpos <- as.integer(hd[[1]])
section_at <- function(pos) {
  i <- which(hpos < pos)
  if (!length(i)) return("")
  htxt[max(i)]
}

tm <- gregexpr("(?s)<table[^>]*>.*?</table>", txt, perl = TRUE)
tabs <- regmatches(txt, tm)[[1]]
if (!length(tabs) || identical(tabs, character(0)))
  stop("no <table> found in ", HTML, "\n  (were the tables rendered as images?)")
tpos <- as.integer(tm[[1]])

cell_text <- function(row, tag) {
  m <- regmatches(row, gregexpr(paste0("(?s)<", tag, "[^>]*>.*?</", tag, ">"), row, perl = TRUE))[[1]]
  vapply(m,function(cell) {
    text <- strip_tags(cell)
    if(grepl('data-indent=["\']1["\']',cell,perl=TRUE)) paste0("\u00a0",text) else text
  },"")
}
rows_of <- function(block, tag) {
  m <- regmatches(block, gregexpr("(?s)<tr[^>]*>.*?</tr>", block, perl = TRUE))[[1]]
  lapply(m, cell_text, tag = tag)
}
max_cols <- function(rs) if (length(rs)) max(vapply(rs, length, 0L)) else 0L
bold_cells <- function(block,cols,drop_first=FALSE) {
  rows <- regmatches(block,gregexpr("(?s)<tr[^>]*>.*?</tr>",block,perl=TRUE))[[1]]
  if(drop_first) rows <- rows[-1]
  out <- list()
  for(i in seq_along(rows)) {
    cells <- regmatches(rows[i],gregexpr("(?s)<td[^>]*>.*?</td>",rows[i],perl=TRUE))[[1]]
    for(j in seq_along(cells)) {
      text <- regmatches(cells[j],regexpr("(?s)<strong[^>]*>.*?</strong>|<b[^>]*>.*?</b>",cells[j],perl=TRUE))
      if(length(text) && nzchar(text) && j<=length(cols))
        out[[length(out)+1L]] <- list(row=i,column=cols[j],prefix=strip_tags(text))
    }
  }
  jsonlite::toJSON(out,auto_unbox=TRUE)
}

manifest <- NULL; idx <- 0L
for (i in seq_along(tabs)) {
  blk <- tabs[i]
  cap <- regmatches(blk, regexpr("(?s)<caption>.*?</caption>", blk, perl = TRUE))
  cap <- if (length(cap)) strip_tags(cap) else ""
  head_blk <- regmatches(blk, regexpr("(?s)<thead>.*?</thead>", blk, perl = TRUE))
  body_blk <- regmatches(blk, regexpr("(?s)<tbody>.*?</tbody>", blk, perl = TRUE))
  hdr <- if (length(head_blk)) rows_of(head_blk, "th") else list()
  if (!length(hdr) || !any(nzchar(hdr[[1]]))) {
    if (!nzchar(cap)) next
    all <- rows_of(blk, "td")
    if (!length(all)) next
    hdr <- list(all[[1]]); bod <- all[-1]
  } else {
    bod <- if (length(body_blk)) rows_of(body_blk, "td") else list()
  }
  nc <- max(max_cols(hdr), max_cols(bod))
  if (nc < 1) next
  pad <- function(v) c(v, rep("", nc - length(v)))
  m <- matrix("", nrow = length(bod), ncol = nc)
  for (r in seq_along(bod)) m[r, ] <- pad(bod[[r]])
  df <- as.data.frame(m, stringsAsFactors = FALSE)
  names(df) <- make.unique(ifelse(nzchar(pad(hdr[[1]]))[seq_len(nc)], pad(hdr[[1]]), paste0("V", seq_len(nc))))
  idx <- idx + 1L
  file <- sprintf("html_tbl_%02d.csv", idx)
  write.csv(df, file.path(OUTDIR, file), row.names = FALSE)
  manifest <- rbind(manifest, data.frame(
    n = idx, html_index = i, file = file, caption = cap, section = section_at(tpos[i]),
    cols = nc, rows = nrow(df), bold_prefixes = as.character(bold_cells(if(length(body_blk)) body_blk else blk,names(df),drop_first=!length(body_blk))),
    check.names = FALSE, stringsAsFactors = FALSE))
}
if (is.null(manifest)) stop("no table with a header row found in ", HTML)
write.csv(manifest, file.path(OUTDIR, "_html_tables.csv"), row.names = FALSE)
Sys.chmod(list.files(OUTDIR, full.names = TRUE), mode = "0644")

cat("source :", HTML, " (", round(file.size(HTML) / 1e6, 1), " MB )\n", sep = "")
cat("written:", nrow(manifest), "tables ->", OUTDIR, "\n")
print(manifest, row.names = FALSE)
