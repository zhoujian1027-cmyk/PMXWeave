#!/usr/bin/env Rscript
ARGS <- commandArgs(trailingOnly = TRUE)
OUT_ARG <- NULL
oi <- which(ARGS == "--out")
if (length(oi)) { OUT_ARG <- ARGS[oi[1] + 1]; ARGS <- ARGS[-c(oi[1], oi[1] + 1)] }
if (!length(ARGS)) stop("usage: Rscript extract_figures.R <report.html | analysis_dir> [--out DIR]")

TARGET <- ARGS[1]
is_dir <- dir.exists(TARGET)
if (is_dir) {
  cand <- list.files(TARGET, pattern = "_report\\.html$", full.names = TRUE)
  if (!length(cand)) stop("no *_report.html in ", TARGET)
  if (length(cand) > 1) cat("note: several HTMLs, using ", basename(cand[1]), "\n", sep = "")
  HTML <- cand[1]
  DIR  <- normalizePath(TARGET)
} else {
  HTML <- TARGET
  DIR  <- dirname(normalizePath(TARGET))
}
stopifnot(file.exists(HTML))
OUTDIR <- if (is.null(OUT_ARG)) file.path(DIR, "figure") else
  if (grepl("^(/|\\.)", OUT_ARG)) OUT_ARG else file.path(DIR, OUT_ARG)
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

entry <- sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
source(file.path(dirname(normalizePath(entry,mustWork=TRUE)),"html_references.R"))

png_size <- function(bytes) {
  if(length(bytes)<24L) return(c(NA_integer_,NA_integer_))
  u32 <- function(i) sum(as.integer(bytes[i:(i+3)])*c(256^3,256^2,256,1))
  c(u32(17L),u32(21L))
}

doc <- xml2::read_html(HTML)
images <- pmx_html_images(doc)
if(!length(images)) stop("no embedded PNG/JPEG found in ",HTML,
  "\n  (was the report knitted with self_contained: true?)")
source_hash <- unname(tools::md5sum(HTML))
rows <- lapply(seq_along(images),function(i) {
  img <- images[[i]]
  ext <- pmx_html_figure_extension(img)
  file <- sprintf("html_fig_%02d.%s",i,ext)
  dest <- file.path(OUTDIR,file)
  encoded <- sub("^[^,]*,","",xml2::xml_attr(img,"src"))
  bytes <- jsonlite::base64_dec(gsub("[[:space:]]","",encoded))
  writeBin(bytes,dest)
  size <- if(ext=="png") png_size(bytes) else c(NA_integer_,NA_integer_)
  cap <- pmx_html_figure_caption(img)
  caption <- if(inherits(cap,"xml_missing")) "" else pmx_html_text(cap)
  data.frame(n=i,file=file,section=pmx_html_figure_heading(img),caption=caption,
    width_px=size[1],height_px=size[2],bytes=length(bytes),source_html_md5=source_hash,
    image_md5=unname(tools::md5sum(dest)),stringsAsFactors=FALSE)
})
manifest <- do.call(rbind,rows)
write.csv(manifest, file.path(OUTDIR, "_html_figures.csv"), row.names = FALSE)
Sys.chmod(list.files(OUTDIR, full.names = TRUE), mode = "0644")

cat("source :", HTML, " (", round(file.size(HTML) / 1e6, 1), " MB )\n", sep = "")
cat("written:", nrow(manifest), "figures ->", OUTDIR, "\n")
print(manifest, row.names = FALSE)
