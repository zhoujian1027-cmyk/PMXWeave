$PARAM TVKA = 1, TVCL = 0.5, TVVC = 2, TVQ = 1, TVVP = 2, TVBASE = 5

$PARAM TVKG = 0.005, TVKD = 0.02, TVLAMBDA = 0.01

$CMT DEPOT CENTRAL PERIPH TUMOR

$OMEGA
0.09 0.16 0.09 0.16 0.09 0.25 0.2 0.2

$SIGMA
0.1 0.1

$MAIN
double KA = TVKA * exp(ETA(1));
double CL = TVCL * exp(ETA(2));
double VC = TVVC * exp(ETA(3));
double Q = TVQ * exp(ETA(4));
double VP = TVVP * exp(ETA(5));
double BASE = TVBASE * exp(ETA(6));
double KG = TVKG * exp(ETA(7));
double KD = TVKD * exp(ETA(8));
TUMOR_0 = BASE;

$ODE
double C2 = CENTRAL / VC;
double KILL = KD * C2 * exp(-TVLAMBDA * SOLVERTIME);
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (CL / VC) * CENTRAL - (Q / VC) * CENTRAL + (Q / VP) * PERIPH;
dxdt_PERIPH = (Q / VC) * CENTRAL - (Q / VP) * PERIPH;
dxdt_TUMOR = (KG - KILL) * TUMOR;

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
