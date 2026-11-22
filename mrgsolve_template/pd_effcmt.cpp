$PARAM TVCL = 5, TVV = 50, TVKE0 = 0.5, TVE0 = 5, TVIMAX = 0.8, TVEC50 = 10

$CMT CENTRAL BIOPHASE

$OMEGA
0.09 0.16 0.25

$SIGMA
0.1 0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double VC = TVV * exp(ETA(2));
double KE0 = TVKE0 * exp(ETA(3));

$ODE
double C2 = CENTRAL / VC;
dxdt_CENTRAL = -(CL / VC) * CENTRAL;
dxdt_BIOPHASE = KE0 * (C2 - BIOPHASE);

$TABLE
double PKCONC = CENTRAL / VC;
double PDRESP = TVE0 * (1.0 - (TVIMAX * BIOPHASE) / (BIOPHASE + TVEC50));

double IPRED = log(0.0001);
double IPRED_PD = log(0.0001);
double DV_PK = IPRED;
double DV_PD = IPRED_PD;
if (PKCONC > 0.0) {
  IPRED = log(PKCONC);
  DV_PK = IPRED + EPS(1);
}
if (PDRESP > 0.0) {
  IPRED_PD = log(PDRESP);
  DV_PD = IPRED_PD + EPS(2);
}

$CAPTURE IPRED IPRED_PD DV_PK DV_PD
