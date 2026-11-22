$PARAM TVKA = 1, TVCL = 5, TVV = 50, TVR0 = 10, TVKOUT = 0.1, TVIMAX = 0.8, TVIC50 = 10

$CMT DEPOT CENTRAL RESPONSE

$OMEGA
0.09 0.16 0.09 0.2

$SIGMA
0.1 0.1

$MAIN
double KA = TVKA * exp(ETA(1));
double CL = TVCL * exp(ETA(2));
double VC = TVV * exp(ETA(3));
double R0 = TVR0 * exp(ETA(4));
double KOUT = TVKOUT;
double KIN = R0 * KOUT;
RESPONSE_0 = R0;

$ODE
double C2 = CENTRAL / VC;
double EFF = TVIMAX * C2 / (TVIC50 + C2);
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (CL / VC) * CENTRAL;
dxdt_RESPONSE = KIN - KOUT * (1.0 - EFF) * RESPONSE;

$TABLE
double PKCONC = CENTRAL / VC;
double PDPRED = RESPONSE;

double IPRED = log(0.0001);
double IPRED_PD = log(0.0001);
double DV_PK = IPRED;
double DV_PD = IPRED_PD;
if (PKCONC > 0.0) {
  IPRED = log(PKCONC);
  DV_PK = IPRED + EPS(1);
}
if (PDPRED > 0.0) {
  IPRED_PD = log(PDPRED);
  DV_PD = IPRED_PD + EPS(2);
}

double IPRED_PK = IPRED;

$CAPTURE IPRED IPRED_PK IPRED_PD DV_PK DV_PD
