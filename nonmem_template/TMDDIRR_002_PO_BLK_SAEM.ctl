$PROBLEM TMDD Irreversible Binding PO 1cpt | SAEM

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID SEX

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(DEPOT) COMP=(CENTRAL) COMP=(RECEPTOR) COMP=(COMPLEX)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVKA = THETA(3)
TVKON = THETA(4)
TVKDEG = THETA(5)
TVRSS = THETA(6)
TVKINT = THETA(7)

; MU references
MU_1 = LOG(TVCL)
MU_2 = LOG(TVVC)
MU_3 = LOG(TVKA)

; Covariate effects
IF (SEX.EQ.2) THEN
  FSEX = THETA(8)
ELSE
  FSEX = 1
ENDIF

; PK parameters
CL = EXP(MU_1 + ETA(1)) * FSEX
VC = EXP(MU_2 + ETA(2))
KA = EXP(MU_3 + ETA(3))

; Binding (irreversible) / target turnover
KON = TVKON
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(3) = RSS

$DES
L = A(2)/VC    ; free ligand

DADT(1) = -KA*A(1)                                                  ; ligand (depot), mass
DADT(2) = KA*A(1) -CL*L -KON*A(2)*A(3)                              ; free ligand (central), mass
DADT(3) = KSYN - KDEG*A(3) - KON*L*A(3)                             ; free target, concentration
DADT(4) = KON*L*A(3) - KINT*A(4)                                    ; complex, concentration

$ERROR
LFREE = A(2)/VC    ; free ligand
RFREE = A(3)    ; free target
RTOT = RFREE + A(4)    ; total target

IPRED = LOG(0.0001)
Y     = IPRED

IF (CMT.EQ.2.AND.F.GT.0) THEN
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
(0, 1) ; THETA(3) TVKA
(0, 0.05) ; THETA(4) TVKON
(0, 0.5) ; THETA(5) TVKDEG
(0, 5) ; THETA(6) TVRSS
(0, 0.5) ; THETA(7) TVKINT
1 ; THETA(8) SEXEFF

$OMEGA
BLOCK(2)
0.2         ; ETA(1) CL
0.01 0.2    ; ETA(2) VC

$OMEGA
0.2         ; ETA(3) KA

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=SAEM INTERACTION NBURN=2000 NITER=1000

$ESTIMATION METHOD=IMP EONLY=1 ISAMPLE=1000 NITER=5
; $COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output FORMAT=1PE12.5
