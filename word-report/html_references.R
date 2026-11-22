#!/usr/bin/env Rscript
# Presentation only, before extraction/hashing. No fitting or numerical interpretation.
pmx_html_text <- function(node) trimws(gsub("[[:space:]]+"," ",xml2::xml_text(node)))

pmx_html_images <- function(doc) {
  xml2::xml_find_all(doc,".//img[starts-with(@src,'data:image/png;base64,') or starts-with(@src,'data:image/jpeg;base64,') or starts-with(@src,'data:image/jpg;base64,')]")
}

pmx_html_figure_heading <- function(img) {
  h <- xml2::xml_find_first(img,"preceding::*[self::h1 or self::h2 or self::h3 or self::h4][1]")
  if(inherits(h,"xml_missing")) "" else pmx_html_text(h)
}

pmx_html_figure_caption <- function(img) {
  caption <- "self::figcaption or (self::p and contains(concat(' ',normalize-space(@class),' '),' caption '))"
  node <- xml2::xml_find_first(img,
    "preceding-sibling::*[1][self::span and @class='pmx-figure-caption']")
  if(!inherits(node,"xml_missing")) return(node)

  node <- xml2::xml_find_first(img,paste0("following-sibling::*[1][",caption,"]"))
  if(!inherits(node,"xml_missing")) return(node)

  block <- xml2::xml_parent(img)
  for(level in seq_len(2L)) {
    if(xml2::xml_name(block) %in% c("body","html")) break
    images <- pmx_html_images(block)
    if(length(images) && identical(xml2::xml_path(img),xml2::xml_path(images[[length(images)]]))) {
      node <- xml2::xml_find_first(block,paste0("./*[",caption,"] | following-sibling::*[1][",caption,"]"))
      if(!inherits(node,"xml_missing")) return(node)
    }
    block <- xml2::xml_parent(block)
  }
  node
}

pmx_html_figure_extension <- function(img) {
  if(startsWith(xml2::xml_attr(img,"src"),"data:image/png;")) "png" else "jpg"
}

pmx_html_references <- function(file) {
  doc <- xml2::read_html(file)
  text <- pmx_html_text
  title <- function(x) trimws(sub("^[0-9]+([.][0-9]+)*[.]?[[:space:]]+","",
    sub("^(Table|Figure)[[:space:]]+[0-9]+[.:]?[[:space:]]*","",x)))
  refs <- list();aliases <- list()
  register <- function(kind,n,caption,key,anchor) {
    ref <- list(kind=kind,n=n,caption=caption,anchor=anchor,label=paste(kind,n))
    refs[[length(refs)+1L]] <<- ref
    for(alias in unique(c(key,title(caption)))) if(nzchar(alias)) {
      token <- paste0(tolower(kind),":",alias)
      old <- aliases[[token]]
      aliases[[token]] <<- if(is.null(old)) ref else if(identical(old$anchor,anchor)) old else list(ambiguous=TRUE)
    }
  }
  table_index <- 0L;table_number <- 0L
  for(tab in xml2::xml_find_all(doc,"//table")) {
    cap <- xml2::xml_find_first(tab,"./caption")
    header <- xml2::xml_find_all(tab,"./thead//th")
    if(!length(header) && inherits(cap,"xml_missing")) next
    if(!length(xml2::xml_find_all(tab,".//tr/*[self::td or self::th]"))) next
    table_index <- table_index+1L
    caption <- if(inherits(cap,"xml_missing")) "" else title(text(cap))
    if(!nzchar(caption)) {
      h <- xml2::xml_find_first(tab,"preceding::*[self::h1 or self::h2 or self::h3 or self::h4][1]")
      caption <- if(inherits(h,"xml_missing")) "Analysis results" else title(text(h))
    }
    # Front matter keeps its existing unnumbered convention.
    if(grepl("abbreviations|report control|synopsis",caption,ignore.case=TRUE)) next
    table_number <- table_number+1L;anchor <- paste0("pmx-html-table-",table_number)
    if(inherits(cap,"xml_missing")) cap <- xml2::xml_add_child(tab,"caption",.where=0)
    xml2::xml_text(cap) <- paste0("Table ",table_number,". ",caption)
    xml2::xml_set_attr(tab,"id",anchor)
    register("Table",table_number,caption,sprintf("html_tbl_%02d.csv",table_index),anchor)
  }
  images <- pmx_html_images(doc)
  for(i in seq_along(images)) {
    img <- images[[i]]
    cap <- pmx_html_figure_caption(img)
    caption <- if(inherits(cap,"xml_missing")) "" else title(text(cap))
    if(!nzchar(caption)) {
      alt <- xml2::xml_attr(img,"alt")
      if(!is.na(alt) && nzchar(trimws(alt)) && !grepl("^plot of chunk",alt,ignore.case=TRUE))
        caption <- title(alt)
    }
    if(!nzchar(caption)) caption <- title(pmx_html_figure_heading(img))
    if(!nzchar(caption)) caption <- "Analysis figure"

    anchor <- paste0("pmx-html-figure-",i)
    caption_id <- paste0(anchor,"-caption")
    xml2::xml_set_attr(img,"id",anchor)
    xml2::xml_set_attr(img,"aria-describedby",caption_id)
    if(!inherits(cap,"xml_missing")) xml2::xml_remove(cap)
    cap <- xml2::xml_add_sibling(img,"span",class="pmx-figure-caption",id=caption_id,
      style="display:block; margin:0.5em 0; font-weight:600;",.where="before")
    xml2::xml_text(cap) <- paste0("Figure ",i,". ",caption)
    register("Figure",i,caption,sprintf("html_fig_%02d.%s",i,pmx_html_figure_extension(img)),anchor)
  }
  prose_xpath <- "//p[not(ancestor::table) and not(@class='caption') and not(ancestor::*[@id='TOC'])]"
  prose <- xml2::xml_find_all(doc,prose_xpath)
  banned <- "These are unadjusted quartile summaries with exact binomial intervals."
  prose_text <- ".//text()[not(ancestor::span[@class='pmx-figure-caption'])]"
  for(p in prose) for(t in xml2::xml_find_all(p,prose_text)) {
    s <- gsub(banned,"",xml2::xml_text(t),fixed=TRUE)
    tokens <- regmatches(s,gregexpr("\\{\\{(?:figure|table):[^{}]+\\}\\}",s,perl=TRUE))[[1]]
    for(token in unique(tokens)) {
      key <- substring(token,3L,nchar(token)-2L);ref <- aliases[[key]]
      if(is.null(ref) || isTRUE(ref$ambiguous)) stop("HTML_REFERENCE_STOP: unknown/ambiguous asset ",token)
      s <- gsub(token,ref$label,s,fixed=TRUE)
    }
    xml2::xml_text(t) <- s
  }
  body <- paste(vapply(prose,function(p) paste(xml2::xml_text(xml2::xml_find_all(p,prose_text)),collapse=""),""),collapse="\n")
  for(ref in refs) {
    if(grepl(paste0("\\b",ref$label,"\\b"),body,perl=TRUE)) next
    target <- xml2::xml_find_first(doc,paste0("//*[@id='",ref$anchor,"']"))
    if(ref$kind=="Figure") target <- xml2::xml_parent(target)
    p <- xml2::xml_add_sibling(target,"p",.where="before")
    a <- xml2::xml_add_child(p,"a",href=paste0("#",ref$anchor))
    xml2::xml_text(a) <- ref$label
    # A locator supplies coverage, never a trend/adequacy/balance claim.
  }
  xml2::write_html(doc,file)
  invisible(file)
}
if(sys.nframe()==0L) {
  args <- commandArgs(trailingOnly=TRUE)
  if(length(args)!=1L) stop("usage: html_references.R <report.html>")
  pmx_html_references(args[1])
}
