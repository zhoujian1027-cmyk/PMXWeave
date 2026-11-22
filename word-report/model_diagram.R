# Shared diagram templates: select species/flows from source, never infer a model from a title.
pmx_diagram_spec <- function(ctl, family, options=list()) {
  fail <- function(s) stop("MODEL_DIAGRAM_SPEC_REQUIRED: ",s,"; set STRUCTURE_CONFIG in the report Rmd after reviewing the actual model. Do not refit.",call.=FALSE)
  if(!is.character(ctl) || !length(ctl)) fail("native CTL/CPP source is unavailable")
  if(length(ctl)==1L && file.exists(ctl)) ctl <- readLines(ctl,warn=FALSE)
  code <- toupper(gsub("[[:space:]]+","",sub("//.*$","",sub(";.*$","",ctl))))
  code <- paste(code,collapse="\n")
  has <- function(n) grepl(paste0("(?<![A-Z0-9_])(?:TV)?",n,"(?![A-Z0-9_])"),code,perl=TRUE)
  choose <- function(n,required=TRUE) {hit<-n[vapply(n,has,logical(1))];if(!length(hit)) {if(required) fail(paste("missing parameter",paste(n,collapse="/")));return("")};hit[1]}
  family <- tolower(family)
  is_tgi <- has("W0") || has("LAM0") || has("LAMBDA0") || (has("KG") && has("KD")) || has("ALPHA0")
  if(family=="pkpd" && is_tgi) family <- "tgi"
  if(!family %in% c("ppk","pkpd","tmdd","tgi")) fail("unsupported diagram family")
  if(family=="ppk" && (has("KSS") || has("KON") || is_tgi || has("SLOPE") || has("KOUT"))) fail("PPK diagram conflicts with binding/PD/tumor terms")
  route <- if(has("KA1") && has("KA2")) "parallel" else if(has("KA")) "oral" else "iv"
  if(route=="iv" && grepl("DEPOT|GUT",code)) fail("absorption model needs an explicit supported route")
  peripheral <- if(has("Q2")) 2L else if(has("Q") || has("Q1")) 1L else 0L
  if(has("Q3") || has("MAT") || has("MTT") || grepl("(?<![A-Z0-9_])TRANSIT[0-9]*(?![A-Z0-9_])",code,perl=TRUE)) fail("transit or extended distribution needs an authored source-matched SVG")
  if(route=="parallel" && !(has("F1") || has("LGTF1") || has("FRAC1"))) fail("parallel absorption lacks its fraction definition")
  central_volume <- choose(c("VC","V1","V"),FALSE)
  if(!nzchar(central_volume) && has("V2") &&
     grepl("\\$SUBROUTINESADVAN(?:2|4|12)(?![0-9])",code,perl=TRUE)) central_volume <- "V2"
  if(!nzchar(central_volume)) fail("central volume mapping is unavailable")
  peripheral_volume <- if(central_volume=="V2") c("VP","V3") else c("VP","V2")
  second_volume <- if(central_volume=="V2") c("VP2","V4") else c("VP2","V3")
  labels <- list(title=switch(family,ppk="Population pharmacokinetic model",pkpd="Pharmacokinetic–pharmacodynamic model",tmdd="Target-mediated drug disposition",tgi="Tumor growth inhibition model"),
    drug=if(family=="tmdd") "Drug" else "Central",drug_sub=central_volume,
    clearance=choose("CL"))
  if(has("VMAX") && has("KM")) labels$clearance <- paste(labels$clearance,"+ MM",sep=" ")
  if(route=="oral") labels$ka <- choose("KA")
  if(route=="parallel") {
    labels$ka1 <- choose("KA1");labels$ka2 <- choose("KA2")
    labels$fraction1 <- choose(c("F1","FRAC1","LGTF1"))
    lag<-choose(c("ALAG2","TLAG","TLAG2","LG2"),FALSE)
    labels$fraction2 <- paste(c("1 − F1",lag[nzchar(lag)]),collapse=" · ")
  }
  if(peripheral>0) {labels$q<-choose(c("Q","Q1"));labels$peripheral_sub<-choose(peripheral_volume)}
  if(peripheral>1) {labels$q2<-choose("Q2");labels$peripheral2_sub<-choose(second_volume)}
  spec<-list(family=family,route=route,peripheral=peripheral,labels=labels)
  if(family=="tmdd") {
    mode<-if(has("KON") && has("KOFF")) "full" else if(has("KSS")) "qss" else if(has("KON")) "irreversible" else if(has("KD")) "qe" else fail("binding approximation is ambiguous")
    spec$binding<-if(mode=="irreversible") "irreversible" else "reversible"
    spec$binding_model<-mode
    labels$binding_label<-switch(mode,qss="KSS",qe="KD",full="KON",irreversible="KON")
    if(mode=="full") labels$dissociation_label<-"KOFF"
    labels$synthesis<-choose(c("KSYN","KIN"));labels$target_loss<-choose(c("KDEG","KOUT"));labels$internalization<-choose("KINT")
  }
  if(family=="pkpd") {
    turnover <- has("KIN") && has("KOUT")
    if(turnover && has("KE0")) fail("combined effect-site/turnover model needs a source-matched SVG")
    spec$pd<-if(turnover) "turnover" else if(has("KE0")) "effect" else if(has("SLOPE") || has("EMAX")) "direct" else fail("PD relationship is not identified")
    labels$effect<-if(has("SLOPE")) "Slope" else if(has("EMAX") && has("EC50")) "Emax / EC50" else "Effect"
    if(spec$pd=="effect") labels$ke0<-choose("KE0")
    if(turnover) {
      patterns<-c(inhibit_kin="KIN\\*\\(1-",stimulate_kin="KIN\\*\\(1\\+",inhibit_kout="KOUT\\*\\(1-",stimulate_kout="KOUT\\*\\(1\\+")
      mode<-names(patterns)[vapply(patterns,grepl,logical(1),x=code)]
      if(length(mode)==1L) spec$turnover<-mode else if(is.null(options$turnover)) fail("which turnover rate is affected is ambiguous")
      labels$synthesis<-"Kin";labels$target_loss<-"Kout"
    }
  }
  if(family=="tgi") {
    if(grepl("W1.*W2.*W3.*W4",code) && has("K1") && has("K2")) {spec$tgi<-"transit";labels$growth<-"Growth";labels$damage<-"K2 · C";labels$transit<-"K1"}
    else if((has("KG") && has("KD")) || (has("ALPHA0") && has("EMAX"))) {
      spec$tgi<-"single";labels$growth<-if(has("KG")) "Kg" else "Growth"
      labels$tumor_loss<-if(has("KD")) "KD · C" else "Drug-related loss"
      labels$effect<-if(has("KD") && has("LAMBDA")) "Drug effect · resistance" else "Drug effect"
    } else fail("tumor growth/damage structure is not supported by the minimal skeleton")
  }
  spec$labels<-labels
  allowed<-c("route","peripheral","pd","turnover","binding","tgi","labels")
  if(length(setdiff(names(options),allowed))) fail("unrecognized STRUCTURE_CONFIG field")
  # Explicit settings resolve source ambiguity, but cannot silently contradict detected topology.
  for(n in intersect(names(options),setdiff(allowed,c("turnover","labels"))))
    if(!identical(as.character(options[[n]]),as.character(spec[[n]]))) fail(paste("configuration contradicts source:",n))
  if(!is.null(options$turnover)) {
    if(!identical(spec$pd,"turnover") || !options$turnover %in% c("inhibit_kin","stimulate_kin","inhibit_kout","stimulate_kout")) fail("invalid turnover mechanism")
    if(!is.null(spec$turnover) && options$turnover!=spec$turnover) fail("turnover mechanism contradicts source")
    spec$turnover<-options$turnover
  }
  if(identical(spec$pd,"turnover")) {
    words<-strsplit(spec$turnover,"_",fixed=TRUE)[[1]]
    spec$labels$effect<-paste(if(words[1]=="inhibit") "Inhibits" else "Stimulates",if(words[2]=="kin") "Kin" else "Kout")
  }
  if(!is.null(options$labels)) {
    if(!is.list(options$labels) || length(setdiff(names(options$labels),names(spec$labels)))) fail("unknown label override")
    for(n in names(options$labels)) {
      value<-options$labels[[n]]
      if(!is.character(value) || length(value)!=1L || !nzchar(value) || nchar(value)>72 || grepl("[\r\n]",value)) fail("labels must be short single-line text")
      spec$labels[[n]]<-value
    }
  }
  spec
}

pmx_diagram_validate <- function(doc,spec) {
  bad<-function(s)stop("MODEL_DIAGRAM_INVALID: ",s,call.=FALSE)
  if(length(xml2::xml_find_all(doc,"//*[local-name()='script' or local-name()='image' or local-name()='use']")))bad("external or scripted artwork is forbidden")
  ids<-xml2::xml_attr(xml2::xml_find_all(doc,"//*[@id]"),"id")
  if(anyDuplicated(ids))bad("duplicate node/edge identifiers")
  edges<-xml2::xml_find_all(doc,"//*[@data-from]")
  for(e in edges) {
    refs<-strsplit(paste(xml2::xml_attr(e,"data-from"),xml2::xml_attr(e,"data-to"))," +")[[1]]
    if(any(!refs %in% c(ids,"outside")))bad("unconnected or nonexistent edge target")
    if(xml2::xml_attr(e,"data-role")=="effect") {
      target<-xml2::xml_find_first(doc,paste0("//*[@id='",xml2::xml_attr(e,"data-to"),"']"))
      if(xml2::xml_name(target)!="polyline")bad("rate effect must terminate on a rate arrow")
      pts<-function(x)matrix(as.numeric(strsplit(gsub(","," ",xml2::xml_attr(x,"points"))," +")[[1]]),ncol=2,byrow=TRUE)
      p<-pts(e);t<-pts(target);end<-p[nrow(p),]
      on_segment<-function(a,b) {d<-b-a;abs(sum((end-a)*c(-d[2],d[1])))<1e-6 && sum((end-a)*d)>=0 && sum((end-b)*d)<=0}
      if(!any(vapply(seq_len(nrow(t)-1L),function(i)on_segment(t[i,],t[i+1,]),logical(1))))bad("effect endpoint misses its rate shaft")
    }
  }
  e<-xml2::xml_find_first(doc,"//*[@id='clearance']")
  if(xml2::xml_attr(e,"data-from")!="drug" || xml2::xml_attr(e,"data-to")!="outside")bad("clearance must remove drug from the system")
  if(spec$family=="tmdd") {
    refs<-function(id,n)xml2::xml_attr(xml2::xml_find_first(doc,paste0("//*[@id='",id,"']")),n)
    if(refs("association","data-from")!="drug target" || refs("association","data-to")!="complex")bad("binding must consume drug and target")
    if(spec$binding=="reversible" && (refs("dissociation","data-from")!="complex" || refs("dissociation","data-to")!="drug target"))bad("dissociation must release both reactants")
    if(refs("internalization","data-from")!="complex" || refs("target_loss","data-from")!="target")bad("target and complex losses are misassigned")
  }
  invisible(TRUE)
}

pmx_diagram_png <- function(doc,file,width=NULL) {
  # The same selected SVG primitives produce PNG for both self-contained HTML and Word extraction.
  canvas_width<-as.numeric(xml2::xml_attr(xml2::xml_root(doc),"width"))
  canvas_height<-as.numeric(xml2::xml_attr(xml2::xml_root(doc),"height"))
  if(is.null(width))width<-canvas_width
  height<-round(width/canvas_width*canvas_height);res<-144
  grDevices::png(file,width=width,height=height,res=res,type=if(capabilities("cairo")) "cairo" else getOption("bitmapType"))
  on.exit(grDevices::dev.off(),add=TRUE);grid::grid.newpage()
  num<-function(n,a,default=0){v<-as.numeric(xml2::xml_attr(n,a));if(is.na(v))default else v}
  col<-function(n,a,default=NA_character_){v<-xml2::xml_attr(n,a);if(is.na(v)||v=="none")default else v}
  unitx<-function(x)grid::unit(x/canvas_width,"npc");unity<-function(y)grid::unit(1-y/canvas_height,"npc")
  shapes<-xml2::xml_find_all(doc,"//*[local-name()='rect' or local-name()='text' or local-name()='polyline'][not(ancestor::*[local-name()='defs'])]")
  for(n in shapes) {
    type<-xml2::xml_name(n);lwd<-num(n,"stroke-width",1)*72/res
    if(type=="rect") grid::grid.roundrect(x=unitx(num(n,"x")+num(n,"width")/2),y=unity(num(n,"y")+num(n,"height")/2),width=grid::unit(num(n,"width")/canvas_width,"npc"),height=grid::unit(num(n,"height")/canvas_height,"npc"),r=grid::unit(num(n,"rx")/canvas_width,"npc"),gp=grid::gpar(fill=col(n,"fill"),col=col(n,"stroke"),lwd=lwd))
    if(type=="text") {
      anchor<-xml2::xml_attr(n,"text-anchor");just<-if(is.na(anchor)||anchor=="start") "left" else if(anchor=="end") "right" else "centre"
      grid::grid.text(xml2::xml_text(n),x=unitx(num(n,"x")),y=unity(num(n,"y")),just=c(just,"bottom"),gp=grid::gpar(fontfamily="sans",fontsize=num(n,"font-size",24)*72/res,col=col(n,"fill","#222222")))
    }
    if(type=="polyline") {
      p<-matrix(as.numeric(strsplit(gsub(","," ",xml2::xml_attr(n,"points"))," +")[[1]]),ncol=2,byrow=TRUE)
      grid::grid.lines(unitx(p[,1]),unity(p[,2]),gp=grid::gpar(col=col(n,"stroke","#222222"),lwd=lwd,lty=if(is.na(xml2::xml_attr(n,"stroke-dasharray"))) "solid" else "dashed"))
      marker<-xml2::xml_attr(n,"marker-end")
      if(!is.na(marker)) {
        v<-p[nrow(p),]-p[nrow(p)-1L,];v<-v/sqrt(sum(v*v));side<-c(-v[2],v[1]);tip<-p[nrow(p),]
        if(grepl("bar",marker)) {a<-tip-12*side;b<-tip+12*side;grid::grid.lines(unitx(c(a[1],b[1])),unity(c(a[2],b[2])),gp=grid::gpar(col="#222222",lwd=lwd))}
        else {pts<-rbind(tip,tip-16*v+6*side,tip-16*v-6*side);grid::grid.polygon(unitx(pts[,1]),unity(pts[,2]),gp=grid::gpar(fill="#222222",col="#222222"))}
      }
    }
  }
  invisible(file)
}

pmx_model_diagram <- function(ctl,family,template_dir,out_dir,options=list(),render_png=TRUE,svg_name="model_structure.svg",show_title=TRUE) {
  if(!requireNamespace("xml2",quietly=TRUE))stop("MODEL_DIAGRAM_RUNTIME_REQUIRED: xml2 is required; preserve fits",call.=FALSE)
  spec<-pmx_diagram_spec(ctl,family,options)
  template<-file.path(template_dir,paste0(spec$family,".svg"))
  if(!file.exists(template))stop("MODEL_DIAGRAM_TEMPLATE_REQUIRED: use the complete toolkit",call.=FALSE)
  doc<-xml2::read_xml(template)
  selected<-c(route=spec$route,peripheral=if(spec$peripheral>0) "one" else "none",peripheral2=if(spec$peripheral>1) "yes" else "no",binding=spec$binding,binding_model=spec$binding_model,pd=spec$pd,turnover=spec$turnover,tgi=spec$tgi)
  groups<-xml2::xml_find_all(doc,"//*[@data-option]")
  for(g in rev(groups)) {
    name<-xml2::xml_attr(g,"data-option");wanted<-xml2::xml_attr(g,"data-value")
    if(!name %in% names(selected) || selected[[name]]!=wanted)xml2::xml_remove(g)
    else xml2::xml_attr(g,"style")<-NA_character_
  }
  for(t in xml2::xml_find_all(doc,"//*[@data-label]")) {
    key<-xml2::xml_attr(t,"data-label")
    if(!is.null(spec$labels[[key]]))xml2::xml_text(t)<-spec$labels[[key]]
  }
  if(spec$family=="ppk") {
    width<-if(spec$peripheral>1)1000 else 760;height<-740
    canvas<-xml2::xml_root(doc)
    xml2::xml_attr(canvas,"width")<-as.character(width)
    xml2::xml_attr(canvas,"height")<-as.character(height)
    xml2::xml_attr(canvas,"viewBox")<-paste(0,0,width,height)
    bg<-xml2::xml_find_first(doc,"/*/*[local-name()='rect']")
    xml2::xml_attr(bg,"width")<-as.character(width);xml2::xml_attr(bg,"height")<-as.character(height)
    title<-xml2::xml_find_first(doc,"//*[@data-label='title']")
    xml2::xml_attr(title,"x")<-as.character(width/2)
  }
  if(!isTRUE(show_title)) xml2::xml_remove(xml2::xml_find_all(doc,"//*[@data-label='title']"))
  pmx_diagram_validate(doc,spec)
  if(length(svg_name)!=1L || is.na(svg_name) || basename(svg_name)!=svg_name || !grepl("[.]svg$",svg_name,ignore.case=TRUE)) stop("DIAGRAM_OUTPUT: SVG basename required",call.=FALSE)
  dir.create(out_dir,showWarnings=FALSE,recursive=TRUE)
  svg<-file.path(out_dir,svg_name);png<-file.path(out_dir,"model_structure.png")
  xml2::write_xml(doc,svg)
  if(render_png) pmx_diagram_png(doc,png) else png<-NULL
  Sys.chmod(c(svg,png),"0644")
  structure(list(svg=normalizePath(svg),png=if(!is.null(png))normalizePath(png) else NULL,spec=spec),class="pmx_model_diagram")
}

# Direct invocation only; sourcing from a report never runs the command-line entry.
if(sys.nframe()==0L) {
  args<-commandArgs(trailingOnly=TRUE)
  svg_only<-"--svg-only" %in% args;args<-args[args!="--svg-only"]
  if(length(args)!=3L || any(startsWith(args,"--")))
    stop("usage: Rscript model_diagram.R <actual.ctl-or.cpp> <ppk|pkpd|tmdd|tgi> <output-dir> [--svg-only]",call.=FALSE)
  entry<-sub("^--file=","",grep("^--file=",commandArgs(FALSE),value=TRUE)[1])
  toolkit<-dirname(dirname(normalizePath(entry,mustWork=TRUE)))
  result<-pmx_model_diagram(args[1],args[2],file.path(toolkit,"analyses_template","diagrams"),args[3],render_png=!svg_only)
  cat("MODEL_DIAGRAM_SVG ",result$svg,"\n",sep="")
  if(!is.null(result$png))cat("MODEL_DIAGRAM_PNG ",result$png,"\n",sep="")
}
