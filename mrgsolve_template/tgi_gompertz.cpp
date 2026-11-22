$PARAM TVKA = 1, TVCL = 0.5, TVVC = 2, TVW0 = 0.2, TVALPHA0 = 0.1, TVBETA = 0.02

$PARAM TVEMAX = 0.5, TVEC50 = 1

$CMT DEPOT CENTRAL TUMOR

$OMEGA
0.09 0.16 0.09 0.25 0.2 0.2

$SIGMA
0.1 0.1

$MAIN
double KA = TVKA * exp(ETA(1));
double CL = TVCL * exp(ETA(2));
double VC = TVVC * exp(ETA(3));
double W0 = TVW0 * exp(ETA(4));
double ALPHA0 = TVALPHA0 * exp(ETA(5));
double EMAX = TVEMAX * exp(ETA(6));
TUMOR_0 = W0;

$ODE
double C2 = CENTRAL / VC;
double GROWTH = ALPHA0 * exp(-TVBETA * SOLVERTIME);
double INHIB = EMAX * C2 / (TVEC50 + C2);
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (CL / VC) * CENTRAL;
dxdt_TUMOR = (GROWTH - INHIB) * TUMOR;

$TABLE
double PKCONC = CENTRAL / VC;
double PDPRED = TUMOR;

double IPRED_PK = log(0.0001);
double IPRED_W = log(0.0001);
double DV_PK = IPRED_PK;
double DV_W = IPRED_W;
if (PKCONC > 0.0) {
  IPRED_PK = log(PKCONC);
  DV_PK = IPRED_PK + EPS(1);
}
if (PDPRED > 0.0) {
  IPRED_W = log(PDPRED);
  DV_W = IPRED_W + EPS(2);
}

$CAPTURE IPRED_PK IPRED_W DV_PK DV_W
