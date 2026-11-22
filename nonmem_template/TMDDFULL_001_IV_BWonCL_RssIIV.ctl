$PROBLEM TMDD Full Model IV 1cpt | FOCE

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW AGE

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(CENTRAL) COMP=(RECEPTOR) COMP=(COMPLEX)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVKON = THETA(3)
TVKOFF = THETA(4)
TVKDEG = THETA(5)
TVRSS = THETA(6)
TVKINT = THETA(7)

; Covariate effects
FBWCL = (BW/70)**0.75
FAGE = (AGE/40)**THETA(8)

; PK parameters
CL = TVCL * EXP(ETA(1)) * FBWCL * FAGE
VC = TVVC * EXP(ETA(2))

; Binding / target turnover
KON = TVKON
KOFF = TVKOFF
KDEG = TVKDEG
RSS = TVRSS * EXP(ETA(3))
KSYN = KDEG*RSS
KINT = TVKINT
A_0(2) = RSS

$DES
L = A(1)/VC    ; free ligand

DADT(1) = -CL*L -KON*A(1)*A(2) +KOFF*VC*A(3)                        ; free ligand (central), mass
DADT(2) = KSYN - KDEG*A(2) - KON*L*A(2) + KOFF*A(3)                 ; free target, concentration
DADT(3) = KON*L*A(2) - KOFF*A(3) - KINT*A(3)                        ; complex, concentration

$ERROR
LFREE = A(1)/VC    ; free ligand
RFREE = A(2)    ; free target
RTOT = RFREE + A(3)    ; total target

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
(0, 0.3) ; THETA(1) TVCL
(0, 5) ; THETA(2) TVVC
(0, 0.05) ; THETA(3) TVKON
(0, 0.5) ; THETA(4) TVKOFF
(0, 0.5) ; THETA(5) TVKDEG
(0, 5) ; THETA(6) TVRSS
(0, 0.5) ; THETA(7) TVKINT
(0, 1) ; THETA(8) AGEPWR

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) RSS

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT

$COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output
