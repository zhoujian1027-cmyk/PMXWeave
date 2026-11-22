$PARAM TVVC = 50, TVCL = 5, TVKA1 = 1, TVKA2 = 0.8, TVALAG2 = 0.3, TVF1 = 0.5

$CMT DEPOT1 DEPOT2 CENTRAL

$OMEGA
0.09 0.09 0.09 0.09 0.09

$SIGMA
0.1

$MAIN
double VC = TVVC * exp(ETA(1));
double CL = TVCL * exp(ETA(2));
double KA1 = TVKA1 * exp(ETA(3));
double KA2 = TVKA2 * exp(ETA(4));
double LGTF1_TV = log(TVF1 / (1.0 - TVF1));
double LGTF1 = LGTF1_TV + ETA(5);
double FRAC1 = exp(LGTF1) / (1.0 + exp(LGTF1));
double FRAC2 = 1.0 - FRAC1;
F_DEPOT1 = FRAC1;
F_DEPOT2 = FRAC2;
ALAG_DEPOT2 = TVALAG2;

$ODE
double K30 = CL / VC;
dxdt_DEPOT1 = -KA1 * DEPOT1;
dxdt_DEPOT2 = -KA2 * DEPOT2;
dxdt_CENTRAL = KA1 * DEPOT1 + KA2 * DEPOT2 - K30 * CENTRAL;

$TABLE
double IPRED = CENTRAL / VC;

double DV = IPRED + IPRED * EPS(1);

$CAPTURE IPRED DV FRAC1
