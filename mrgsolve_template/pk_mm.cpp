$PARAM TVKA = 1, TVVC = 50, TVVMAX = 10, TVKM = 1

$CMT DEPOT CENTRAL

$OMEGA
0.09 0.09 0.1

$SIGMA
0.1

$MAIN
double KA = TVKA * exp(ETA(1));
double VC = TVVC * exp(ETA(2));
double VMAX = TVVMAX * exp(ETA(3));
double KM = TVKM;

$ODE
double C = CENTRAL / VC;
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (VMAX * C) / (KM + C);

$TABLE
double IPRED = CENTRAL / VC;

double DV = IPRED + IPRED * EPS(1);

$CAPTURE IPRED DV

