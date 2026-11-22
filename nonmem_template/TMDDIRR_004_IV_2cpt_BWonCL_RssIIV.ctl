$PROBLEM TMDD Irreversible Binding IV 2cpt | FOCE

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(CENTRAL) COMP=(PERIPH) COMP=(RECEPTOR) COMP=(COMPLEX)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVQ = THETA(3)
TVVP = THETA(4)
TVKON = THETA(5)
TVKDEG = THETA(6)
TVRSS = THETA(7)
TVKINT = THETA(8)

; Covariate effects
FBWCL = (BW/70)**0.75

; PK parameters
CL = TVCL * EXP(ETA(1)) * FBWCL
VC = TVVC * EXP(ETA(2))
Q = TVQ
VP = TVVP
K12 = Q/VC
K21 = Q/VP

; Binding (irreversible) / target turnover
KON = TVKON
KDEG = TVKDEG
RSS = TVRSS * EXP(ETA(3))
KSYN = KDEG*RSS
KINT = TVKINT
A_0(3) = RSS

$DES
L = A(1)/VC    ; free ligand

DADT(1) = -CL*L -KON*A(1)*A(3) -K12*A(1) +K21*A(2)                  ; free ligand (central), mass
DADT(2) = K12*A(1) - K21*A(2)                                       ; free ligand (peripheral), mass
DADT(3) = KSYN - KDEG*A(3) - KON*L*A(3)                             ; free target, concentration
DADT(4) = KON*L*A(3) - KINT*A(4)                                    ; complex, concentration

$ERROR
LFREE = A(1)/VC    ; free ligand
RFREE = A(3)    ; free target
RTOT = RFREE + A(4)    ; total target

IPRED = LOG(0.0001)
Y     = IPRED

IF (CMT.EQ.1.AND.F.GT.0) THEN
  IF (LFREE.GT.0) IPRED = LOG(LFREE)
  Y = IPRED + EPS(1)
ENDIF

IF (CMT.EQ.3.AND.F.GT.0) THEN
  IF (RTOT.GT.0) IPRED = LOG(RTOT)
  Y = IPRED + EPS(2)
ENDIF

$THETA
(0, 0.3) ; THETA(1) TVCL
(0, 5) ; THETA(2) TVVC
(0, 0.3) ; THETA(3) TVQ
(0, 5) ; THETA(4) TVVP
(0, 0.05) ; THETA(5) TVKON
(0, 0.5) ; THETA(6) TVKDEG
(0, 5) ; THETA(7) TVRSS
(0, 0.5) ; THETA(8) TVKINT

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
