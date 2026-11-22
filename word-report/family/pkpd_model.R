MODEL <- list(
  id="pkpd", data_csv="pkpd_data.csv", model_ctl="base_model.ctl",
  refs=c(bw=70, age=40, crcl=90), ref_units=c(bw="kg",age="y",crcl="mL/min"),
  labels=character(0), typical=character(0), residual=character(0),
  read_data=function(path) pmx_read_data(path), build=function(effects) stop("Model contract not configured"),
  candidates=function(ref) list(),
  fit=function(ui,dat,cov,cov_method="s") {
    est <- Sys.getenv("PMX_EST", "focei")
    if(est!="focei") stop("This backend supports FOCEI; use NONMEM/PsN for SAEM or BAYES control streams")
    nlmixr2(ui,dat,est=est,control=pmx_focei_control(if(cov) cov_method else "",cov))
  },
  output=function(final,chosen,refs) lst_text(final,chosen,refs,title="nlmixr2 FOCEI — PKPD model imported from control stream")
)
