$PARAM TVCL = 5, TVV = 50, TVE0 = 5, TVIMAX = 0.8, TVEC50 = 10, TVGAM = 1

$CMT CENTRAL

$OMEGA
0.09 0.16

$SIGMA
0.1 0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double VC = TVV * exp(ETA(2));

$ODE
dxdt_CENTRAL = -(CL / VC) * CENTRAL;

$TABLE
double PKCONC = CENTRAL / VC;
double PDRESP = TVE0 * (1.0 - (TVIMAX * pow(PKCONC, TVGAM)) / (pow(PKCONC, TVGAM) + pow(TVEC50, TVGAM)));

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
