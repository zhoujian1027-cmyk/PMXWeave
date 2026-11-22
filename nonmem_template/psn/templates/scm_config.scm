
model=run_base.mod

search_direction=both
p_forward=0.05
p_backward=0.01

gof=p_value
; ofv = judge by dOFV instead; then fill the [ofv_*] sections at the bottom

continuous_covariates=WGT,AGE,CRCL
categorical_covariates=SEX,SMOK,STUDY

threads=8
retries=5
tweak_inits=1
abort_on_fail=0
nm_version=7

directory=scm_run1

;do_not_drop=WGT

;time_varying=CRCL

;logit=PHI

;max_steps=12
;only_successful=1
;base_ofv=1234.5

[test_relations]
CL=WGT,AGE,SEX,SMOK,CRCL,STUDY
V=WGT,AGE,SEX,SMOK,CRCL
KA=WGT
;PHI=DIBMI,SEX

[valid_states]
continuous = 1,2,4
categorical = 1,2

; search_direction=backward.
;[included_relations]
;CL=WGT-2,AGE-3

;[code]
;*:*-6=PARCOV=THETA(1)/(1+EXP(-THETA(2)*(COV-median)))
;PHI:FORM-8=IF(FORM.EQ.1) PHIFORM=0\
;IF(FORM.EQ.2) PHIFORM=THETA(1)
;*:WGT-4=power
;[inits]
;*:*-6=0.5,1
;[lower_bounds]
;CL:AGE-2=-5
;*:*-6=0.01,0.01
;[upper_bounds]
;CL:AGE-2=5
;*:*-6=100,10

;linearize=1
;epsilon=1
; 0 = approximate the error model instead of linearizing it (needs error=)
;error=prop
;do_not_drop=SEX
;nointer=0
;noabort=1
;lst_file=run_base.lst
;update_derivatives=1
;derivatives_data=derivatives_covariates.dta

;[ofv_forward]
;1=3.84
;2=5.99
;3=7.81
;4=9.49
;5=11.07
;6=12.59
;7=14.07
;8=15.51
;9=16.92
;10=18.31
;[ofv_backward]
;1=6.63
;2=9.21
;3=11.34
;4=13.28
;5=15.09
;6=16.81
;7=18.48
;8=20.09
;9=21.67
;10=23.21
