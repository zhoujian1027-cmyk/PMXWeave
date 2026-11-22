$PROBLEM TMDD Irreversible Binding PO 2cpt | BAYES

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW

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
TVKDEG = THETA(7)
TVRSS = THETA(8)
TVKINT = THETA(9)

; MU references
MU_1 = LOG(TVCL)
MU_2 = LOG(TVVC)
MU_3 = LOG(TVKA)
MU_4 = LOG(TVRSS)

; Covariate effects
FBWV = (BW/70)**1

; PK parameters
CL = EXP(MU_1 + ETA(1))
VC = EXP(MU_2 + ETA(2)) * FBWV
KA = EXP(MU_3 + ETA(3))
Q = TVQ
VP = TVVP
K12 = Q/VC
K21 = Q/VP

; Binding (irreversible) / target turnover
KON = TVKON
KDEG = TVKDEG
RSS = EXP(MU_4 + ETA(4))
KSYN = KDEG*RSS
KINT = TVKINT
A_0(4) = RSS

$DES
L = A(2)/VC    ; free ligand

DADT(1) = -KA*A(1)                                                  ; ligand (depot), mass
DADT(2) = KA*A(1) -CL*L -KON*A(2)*A(4) -K12*A(2) +K21*A(3)          ; free ligand (central), mass
DADT(3) = K12*A(2) - K21*A(3)                                       ; free ligand (peripheral), mass
DADT(4) = KSYN - KDEG*A(4) - KON*L*A(4)                             ; free target, concentration
DADT(5) = KON*L*A(4) - KINT*A(5)                                    ; complex, concentration

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
(0, 0.5) ; THETA(7) TVKDEG
(0, 5) ; THETA(8) TVRSS
(0, 0.5) ; THETA(9) TVKINT

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) KA
0.2         ; ETA(4) RSS

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$PRIOR NWPRI

$THETAP
0.3 FIX
5 FIX
1 FIX
0.3 FIX
5 FIX
0.05 FIX
0.5 FIX
5 FIX
0.5 FIX

$THETAPV BLOCK(9) FIX
1000
0 1000
0 0 1000
0 0 0 1000
0 0 0 0 1000
0 0 0 0 0 1000
0 0 0 0 0 0 1000
0 0 0 0 0 0 0 1000
0 0 0 0 0 0 0 0 1000

$ESTIMATION METHOD=BAYES INTERACTION FILE=bayes_output

; $COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output FORMAT=1PE12.5
