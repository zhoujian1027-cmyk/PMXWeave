$PROBLEM TMDD Full Model PO 2cpt | FOCE

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW AGE

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(DEPOT) COMP=(CENTRAL) COMP=(PERIPH) COMP=(RECEPTOR) COMP=(COMPLEX)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVKA = THETA(3)
TVQ = THETA(4)
TVVP = THETA(5)
TVKON = THETA(6)
TVKOFF = THETA(7)
TVKDEG = THETA(8)
TVRSS = THETA(9)
TVKINT = THETA(10)

; Covariate effects
FBWV = (BW/70)**1
FAGE = (AGE/40)**THETA(11)

; PK parameters
CL = TVCL * EXP(ETA(1)) * FAGE
VC = TVVC * EXP(ETA(2)) * FBWV
KA = TVKA * EXP(ETA(3))
Q = TVQ
VP = TVVP
K12 = Q/VC
K21 = Q/VP

; Binding / target turnover
KON = TVKON
KOFF = TVKOFF * EXP(ETA(4))
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(4) = RSS

$DES
L = A(2)/VC    ; free ligand

DADT(1) = -KA*A(1)                                                  ; ligand (depot), mass
DADT(2) = KA*A(1) -CL*L -KON*A(2)*A(4) +KOFF*VC*A(5) -K12*A(2) +K21*A(3); free ligand (central), mass
DADT(3) = K12*A(2) - K21*A(3)                                       ; free ligand (peripheral), mass
DADT(4) = KSYN - KDEG*A(4) - KON*L*A(4) + KOFF*A(5)                 ; free target, concentration
DADT(5) = KON*L*A(4) - KOFF*A(5) - KINT*A(5)                        ; complex, concentration

$ERROR
LFREE = A(2)/VC    ; free ligand
RFREE = A(4)    ; free target
RTOT = RFREE + A(5)    ; total target

IPRED = LOG(0.0001)
Y     = IPRED

IF (CMT.EQ.2.AND.F.GT.0) THEN
  IF (LFREE.GT.0) IPRED = LOG(LFREE)
  Y = IPRED + EPS(1)
ENDIF

IF (CMT.EQ.4.AND.F.GT.0) THEN
  IF (RTOT.GT.0) IPRED = LOG(RTOT)
  Y = IPRED + EPS(2)
ENDIF

$THETA
(0, 0.3) ; THETA(1) TVCL
(0, 5) ; THETA(2) TVVC
(0, 1) ; THETA(3) TVKA
(0, 0.3) ; THETA(4) TVQ
(0, 5) ; THETA(5) TVVP
(0, 0.05) ; THETA(6) TVKON
(0, 0.5) ; THETA(7) TVKOFF
(0, 0.5) ; THETA(8) TVKDEG
(0, 5) ; THETA(9) TVRSS
(0, 0.5) ; THETA(10) TVKINT
(0, 1) ; THETA(11) AGEPWR

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) KA
0.2         ; ETA(4) KOFF

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT

$COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output
