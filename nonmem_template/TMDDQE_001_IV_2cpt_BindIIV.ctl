$PROBLEM TMDD QE Model IV 2cpt | FOCE

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID SEX AGE

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(CENTRAL) COMP=(PERIPH) COMP=(RECEPTOR)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVQ = THETA(3)
TVVP = THETA(4)
TVKD = THETA(5)
TVKDEG = THETA(6)
TVRSS = THETA(7)
TVKINT = THETA(8)

; Covariate effects
IF (SEX.EQ.2) THEN
  FSEX = THETA(9)
ELSE
  FSEX = 1
ENDIF
FAGE = (AGE/40)**THETA(10)

; PK parameters
CL = TVCL * EXP(ETA(1)) * FSEX * FAGE
VC = TVVC * EXP(ETA(2))
Q = TVQ
VP = TVVP
K12 = Q/VC
K21 = Q/VP

; Quasi-equilibrium binding / target turnover
KD = TVKD * EXP(ETA(3))
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(3) = RSS

$DES
L = 0.5*((A(1)/VC - A(3) - KD) + SQRT((A(1)/VC - A(3) - KD)**2 + 4*KD*A(1)/VC))    ; free ligand

DADT(1) = -CL*L -KINT*(A(3)*L/(KD+L))*VC -K12*L*VC +K21*A(2)       ; total ligand (central), mass
DADT(2) = K12*L*VC - K21*A(2)                                       ; free ligand (peripheral), mass
DADT(3) = KSYN - KDEG*(A(3)*KD/(KD+L)) - KINT*(A(3)*L/(KD+L))    ; total target, concentration

$ERROR
LTOT = A(1)/VC    ; total ligand
RTOT = A(3)    ; total target
LFREE = 0.5*((LTOT - RTOT - KD) + SQRT((LTOT - RTOT - KD)**2 + 4*KD*LTOT))    ; free ligand
RFREE = RTOT*KD/(KD+LFREE)    ; free target

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
(0, 5) ; THETA(5) TVKD
(0, 0.5) ; THETA(6) TVKDEG
(0, 5) ; THETA(7) TVRSS
(0, 0.5) ; THETA(8) TVKINT
1 ; THETA(9) SEXEFF
(0, 1) ; THETA(10) AGEPWR

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) KD

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=1 INTER MAXEVAL=9999 SIGL=9 NOABORT

$COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output FORMAT=1PE10.4
