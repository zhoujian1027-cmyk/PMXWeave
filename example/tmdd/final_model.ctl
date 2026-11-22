$PROBLEM TMDD QSS Model IV 1cpt+Rss | FOCE

$INPUT ID TIME DV=DROP DV=LNDV AMT EVID CMT MDV ADDL II RATE STUDYID BW SEX AGE RACE WTBL BMI ALB CRCL DOSE=DROP

$DATA tmdd_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(CENTRAL) COMP=(RECEPTOR)

$PK
; Typical values (starting estimates = tmdd1.cpp true values)
TVCL = THETA(1)
TVVC = THETA(2) * (age/40)**THETA(7)
TVKSS = THETA(3)
TVKDEG = THETA(4)
TVRSS = THETA(5)
TVKINT = THETA(6)

; PK parameters (ligand)
CL = TVCL * EXP(ETA(1))
VC = TVVC * EXP(ETA(2))

; Quasi-steady-state binding / target turnover
KSS = TVKSS * EXP(ETA(3))
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(2) = RSS    ; baseline total target concentration

$DES
LTOT = A(1)/VC    ; total ligand, concentration
RTOT = A(2)    ; total target, concentration
DISCR = LTOT - RTOT - KSS
L = 0.5*(DISCR + SQRT(MAX(0.0, DISCR**2 + 4*KSS*LTOT)))    ; free ligand
P = RTOT*L/(KSS+L)    ; complex
R = RTOT*KSS/(KSS+L)    ; free target
DADT(1) = -CL*L - KINT*P*VC    ; total ligand (central), mass
DADT(2) = KSYN - KDEG*R - KINT*P    ; total target, concentration

$ERROR
LTOT = A(1)/VC    ; total ligand
RTOT = A(2)       ; total target
LFREE = 0.5*((LTOT - RTOT - KSS) + SQRT((LTOT - RTOT - KSS)**2 + 4*KSS*LTOT))    ; free ligand

IPRED = LOG(0.0001)
Y     = IPRED

IF (CMT.EQ.1.AND.F.GT.0) THEN
  IF (LFREE.GT.0) IPRED = LOG(LFREE)
  Y = IPRED + EPS(1)
ENDIF

IF (CMT.EQ.2.AND.F.GT.0) THEN
  IF (RTOT.GT.0) IPRED = LOG(RTOT)
  Y = IPRED + EPS(2)
ENDIF

$THETA
(0, 0.5) ; THETA(1) TVCL [L/h]
(0, 10) ; THETA(2) TVVC [L]
(0, 5) ; THETA(3) TVKSS [nM]
(0, 0.01) ; THETA(4) TVKDEG [1/h]
(0, 12) ; THETA(5) TVRSS [nM]
(0, 0.02) ; THETA(6) TVKINT [1/h]

0.00119308494394 ; THETA(7) theta_VC_age

$OMEGA
0.3         ; ETA(1) CL
0.3         ; ETA(2) VC
0.3         ; ETA(3) KSS

$SIGMA
0.2 ; PK (free ligand) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT

$COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME EVID CMT MDV STUDYID BW SEX AGE RACE WTBL BMI ALB CRCL DV PRED IPRED CWRES NOPRINT ONEHEADER FILE=output FORMAT=1PE10.4
