$PROBLEM TMDD QSS Model IV 1cpt | BAYES

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(CENTRAL) COMP=(RECEPTOR)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVKSS = THETA(3)
TVKDEG = THETA(4)
TVRSS = THETA(5)
TVKINT = THETA(6)

; Covariate effects
FBWV = (BW/70)**1

; PK parameters
CL = TVCL * EXP(ETA(1))
VC = TVVC * EXP(ETA(2)) * FBWV

; Quasi-steady-state binding / target turnover
KSS = TVKSS
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(2) = RSS

$DES
L = 0.5*((A(1)/VC - A(2) - KSS) + SQRT((A(1)/VC - A(2) - KSS)**2 + 4*KSS*A(1)/VC))    ; free ligand

DADT(1) = -CL*L -KINT*(A(2)*L/(KSS+L))*VC                           ; total ligand (central), mass
DADT(2) = KSYN - KDEG*(A(2)*KSS/(KSS+L)) - KINT*(A(2)*L/(KSS+L))    ; total target, concentration

$ERROR
LTOT = A(1)/VC    ; total ligand
RTOT = A(2)    ; total target
LFREE = 0.5*((LTOT - RTOT - KSS) + SQRT((LTOT - RTOT - KSS)**2 + 4*KSS*LTOT))    ; free ligand
RFREE = RTOT*KSS/(KSS+LFREE)    ; free target

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
(0, 5) ; THETA(3) TVKSS
(0, 0.5) ; THETA(4) TVKDEG
(0, 5) ; THETA(5) TVRSS
(0, 0.5) ; THETA(6) TVKINT

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$PRIOR NWPRI

$THETAP
0.3 FIX
5 FIX
5 FIX
0.5 FIX
5 FIX
0.5 FIX

$THETAPV BLOCK(6) FIX
1000
0 1000
0 0 1000
0 0 0 1000
0 0 0 0 1000
0 0 0 0 0 1000

$ESTIMATION METHOD=BAYES INTERACTION FILE=bayes_output

; $COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output
