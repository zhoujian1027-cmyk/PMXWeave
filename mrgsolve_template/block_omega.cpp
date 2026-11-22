$PARAM TVCL = 5, TVV = 50

$CMT CENTRAL

$OMEGA @block
0.09
0.045 0.16

$SIGMA
0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double VC = TVV * exp(ETA(2));

$ODE
dxdt_CENTRAL = -(CL / VC) * CENTRAL;

$TABLE
double IPRED = CENTRAL / VC;

double DV = IPRED + IPRED * EPS(1);

$CAPTURE IPRED DV CL VC

