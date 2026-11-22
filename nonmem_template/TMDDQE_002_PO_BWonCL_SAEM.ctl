$PROBLEM TMDD QE Model PO 1cpt | SAEM

$INPUT ID TIME DV AMT EVID CMT MDV ADDL II RATE STUDYID BW

$DATA pk_data.csv IGNORE=@

$SUBROUTINES ADVAN13 TOL=9

$MODEL COMP=(DEPOT) COMP=(CENTRAL) COMP=(RECEPTOR)

$PK
; Typical values
TVCL = THETA(1)
TVVC = THETA(2)
TVKA = THETA(3)
TVKD = THETA(4)
TVKDEG = THETA(5)
TVRSS = THETA(6)
TVKINT = THETA(7)

; MU references
MU_1 = LOG(TVCL)
MU_2 = LOG(TVVC)
MU_3 = LOG(TVKA)

; Covariate effects
FBWCL = (BW/70)**0.75

; PK parameters
CL = EXP(MU_1 + ETA(1)) * FBWCL
VC = EXP(MU_2 + ETA(2))
KA = EXP(MU_3 + ETA(3))

; Quasi-equilibrium binding / target turnover
KD = TVKD
KDEG = TVKDEG
RSS = TVRSS
KSYN = KDEG*RSS
KINT = TVKINT
A_0(3) = RSS

$DES
L = 0.5*((A(2)/VC - A(3) - KD) + SQRT((A(2)/VC - A(3) - KD)**2 + 4*KD*A(2)/VC))    ; free ligand

DADT(1) = -KA*A(1)                                                   ; ligand (depot), mass
DADT(2) = KA*A(1) -CL*L -KINT*(A(3)*L/(KD+L))*VC                    ; total ligand (central), mass
DADT(3) = KSYN - KDEG*(A(3)*KD/(KD+L)) - KINT*(A(3)*L/(KD+L))     ; total target, concentration

$ERROR
LTOT = A(2)/VC    ; total ligand
RTOT = A(3)    ; total target
LFREE = 0.5*((LTOT - RTOT - KD) + SQRT((LTOT - RTOT - KD)**2 + 4*KD*LTOT))    ; free ligand
RFREE = RTOT*KD/(KD+LFREE)    ; free target

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
(0, 5) ; THETA(4) TVKD
(0, 0.5) ; THETA(5) TVKDEG
(0, 5) ; THETA(6) TVRSS
(0, 0.5) ; THETA(7) TVKINT

$OMEGA
0.2         ; ETA(1) CL
0.2         ; ETA(2) VC
0.2         ; ETA(3) KA

$SIGMA
0.1 ; PK (free drug) log-additive error
0.1 ; PD (total target) log-additive error

$ESTIMATION METHOD=SAEM INTERACTION NBURN=2000 NITER=1000

$ESTIMATION METHOD=IMP EONLY=1 ISAMPLE=1000 NITER=5

; $COVARIANCE UNCONDITIONAL PRINT=E

$TABLE ID TIME DV PRED IPRED CMT CWRES NOPRINT ONEHEADER FILE=output FORMAT=1F12.5
