$PARAM TVKA = 1, TVCL = 0.5, TVVC = 2, TVW0 = 0.2, TVLAM0 = 0.1, TVLAM1 = 0.02

$PARAM TVK2 = 0.5, TVK1 = 0.2, PSI = 20

$CMT DEPOT CENTRAL W1 W2 W3 W4

$OMEGA
0.09 0.16 0.09 0.25 0.2 0.2 0.2 0.2

$SIGMA
0.1 0.1

$MAIN
double KA = TVKA * exp(ETA(1));
double CL = TVCL * exp(ETA(2));
double VC = TVVC * exp(ETA(3));
double W0 = TVW0 * exp(ETA(4));
double LAM0 = TVLAM0 * exp(ETA(5));
double LAM1 = TVLAM1 * exp(ETA(6));
double K2 = TVK2 * exp(ETA(7));
double K1 = TVK1 * exp(ETA(8));
W1_0 = W0;

$ODE
double W = W1 + W2 + W3 + W4;
double C2 = CENTRAL / VC;
double GROWTH = LAM0 * W1 / pow(1.0 + pow(LAM0 / LAM1 * W, PSI), 1.0 / PSI);
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (CL / VC) * CENTRAL;
dxdt_W1 = GROWTH - K2 * C2 * W1;
dxdt_W2 = K2 * C2 * W1 - K1 * W2;
dxdt_W3 = K1 * (W2 - W3);
dxdt_W4 = K1 * (W3 - W4);

$TABLE
double PKCONC = CENTRAL / VC;
double PDPRED = W1 + W2 + W3 + W4;

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
