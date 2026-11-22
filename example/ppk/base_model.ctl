$PROBLEM 2-cmt PO, parallel elimination: linear CL + Michaelis-Menten | FOCEI | prop
; Template: nonmem_template/ADVAN13_013_parallel_mm_2cpt_prop_BWonCL_BWonV_SEXonCL_AGEonCL_IOV.ctl
; Requested adaptation: no covariates/IOV; IIV on VC, CL, KA and VMAX only.

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW SEX AGE RACE BMI ALB CRCL DOSE=DROP ADY

$DATA ppk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(DEPOT) COMP=(CENTRAL) COMP=(PERIPH)

$PK
; Typical values
TVVC = THETA(1)
TVCL = THETA(2)
TVKA = THETA(3)
TVVP = THETA(4)
TVQ = THETA(5)
TVVMAX = THETA(6)
TVKM = THETA(7)
; Individual parameters
VC = TVVC * EXP(ETA(1))
CL = TVCL * EXP(ETA(2))
KA = TVKA * EXP(ETA(3))
VP = TVVP
Q = TVQ
K23 = Q/VC
K32 = Q/VP
VMAX = TVVMAX * EXP(ETA(4))
KM = TVKM

$DES
K12 = KA
K20 = CL/VC
C2 = A(2)/VC
DADT(1) = -K12*A(1)
DADT(2) = K12*A(1) + K32*A(3) - K23*A(2) - K20*A(2) - (VMAX*C2)/(KM+C2)
DADT(3) = K23*A(2) - K32*A(3)

$ERROR
F = A(2)/VC
Y = F + F * EPS(1)

$THETA
(0, 50) ; THETA(1) TVVC
(0, 5) ; THETA(2) TVCL
(0, 1) ; THETA(3) TVKA
(0, 50) ; THETA(4) TVVP
(0, 10) ; THETA(5) TVQ
(0, 1) ; THETA(6) TVVMAX
(0, 1) ; THETA(7) TVKM

$OMEGA
0.2         ; IIV_VC
0.2         ; IIV_CL
0.2         ; IIV_KA
0.2         ; IIV_VMAX

$SIGMA
0.1 ; Proportional variance

$ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT PRINT=5

$COVARIANCE UNCONDITIONAL PRINT=E MATRIX=S

$TABLE ID TIME DV PRED IPRED CWRES ETA(1) ETA(2) ETA(3) ETA(4) NOPRINT ONEHEADER FILE=output.tab FORMAT=1PE10.4
