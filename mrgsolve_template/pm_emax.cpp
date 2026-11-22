$PARAM TVCL = 5, TVV1 = 50, TVVMAX = 10, TVKM = 1, TVCLM = 5, TVVM = 50

$CMT PARENT METAB

$OMEGA
0.09 0.16 0.25 0.25 0.09 0.16

$SIGMA
0.1 0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double V1 = TVV1 * exp(ETA(2));
double VMAX = TVVMAX * exp(ETA(3));
double KM = TVKM * exp(ETA(4));
double CLM = TVCLM * exp(ETA(5));
double VM = TVVM * exp(ETA(6));

$ODE
double CP = PARENT / V1;
double RATE_FORM = VMAX * CP / (KM + CP);
dxdt_PARENT = -RATE_FORM - (CL / V1) * PARENT;
dxdt_METAB = RATE_FORM - (CLM / VM) * METAB;

$TABLE
double PKCONC = PARENT / V1;
double PDPRED = METAB / VM;

double IPRED_P = log(0.0001);
double IPRED_M = log(0.0001);
double DV_P = IPRED_P;
double DV_M = IPRED_M;
if (PKCONC > 0.0) {
  IPRED_P = log(PKCONC);
  DV_P = IPRED_P + EPS(1);
}
if (PDPRED > 0.0) {
  IPRED_M = log(PDPRED);
  DV_M = IPRED_M + EPS(2);
}

$CAPTURE IPRED_P IPRED_M DV_P DV_M
