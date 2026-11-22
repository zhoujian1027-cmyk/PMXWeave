$PARAM TVCL = 5, TVV = 50

$CMT @annotated
CENTRAL : Central compartment

$OMEGA
0.09 0.16

$SIGMA
0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double VC = TVV * exp(ETA(2));

$ODE
double K = CL / VC;
dxdt_CENTRAL = -K * CENTRAL;

$TABLE
double CONC = CENTRAL / VC;
double IPRED = CONC;

double DV = IPRED + IPRED * EPS(1);

$CAPTURE IPRED DV CL VC

