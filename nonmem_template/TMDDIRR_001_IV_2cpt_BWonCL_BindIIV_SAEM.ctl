$PROBLEM TMDD Irreversible Binding IV 2cpt | SAEM

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW SEX AGE

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

; MU references
MU_1 = LOG(TVCL)
MU_2 = LOG(TVVC)
MU_3 = LOG(TVKON)

; Covariate effects
FBWCL = (BW/70)**0.75
FBWV = (BW/70)**1
IF (SEX.EQ.2) THEN
  FSEX = THETA(9)
ELSE
  FSEX = 1
ENDIF
FAGE = (AGE/40)**THETA(10)

; PK parameters
CL = EXP(MU_1 + ETA(1)) * FBWCL * FSEX * FAGE
VC = EXP(MU_2 + ETA(2)) * FBWV
Q = TVQ
VP = TVVP
K12 = Q/VC
K21 = Q/VP

; Binding (irreversible) / target turnover
KON = EXP(MU_3 + ETA(3))
KDEG = TVKDEG
RSS = TVRSS
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
1 ; THETA(9) SEXEFF
(0, 1) ; THETA(10) AGEPWR

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) KON

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=SAEM INTERACTION NBURN=2000 NITER=1000

$ESTIMATION METHOD=IMP EONLY=1 ISAMPLE=1000 NITER=5
; $COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output
