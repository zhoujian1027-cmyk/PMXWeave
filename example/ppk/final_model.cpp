$PROB PPK sim (mrgsolve translation of the frozen control stream by stage 2)
$PARAM TVVC = 32.054556222000, TVCL = 4.832272394710, TVKA = 0.766967402892, TVVP = 29.272230994300, TVQ = 5.844677723290, TVVMAX = 0.146588520072, TVKM = 0.130651621989
$PARAM BW = 70
$CMT DEPOT CENTRAL PERIPH
$OMEGA @block
0.243246304492
0.000000000000 0.151039155918
0.000000000000 0.000000000000 0.397339547405
0.00000000000 0.00000000000 0.00000000000 3.24000364959
$SIGMA
0.106079801004
$MAIN
double TVCL_SCM = (TVCL * pow(((BW / 70.0)),0.75));
double VC = (TVVC * exp(ETA(1)));
double CL = (TVCL_SCM * exp(ETA(2)));
double KA = (TVKA * exp(ETA(3)));
double VP = TVVP;
double Q = TVQ;
double K23 = (Q / VC);
double K32 = (Q / VP);
double VMAX = (TVVMAX * exp(ETA(4)));
double KM = TVKM;
$ODE
double K12 = KA;
double K20 = (CL / VC);
double C2 = (CENTRAL / VC);
dxdt_DEPOT = ((-K12) * DEPOT);
dxdt_CENTRAL = (((((K12 * DEPOT) + (K32 * PERIPH)) - (K23 * CENTRAL)) - (K20 * CENTRAL)) - (((VMAX * C2)) / ((KM + C2))));
dxdt_PERIPH = ((K23 * CENTRAL) - (K32 * PERIPH));
$TABLE
double F = (CENTRAL / VC);
double Y = (F + (F * EPS(1)));
double IPRED = F;
double PRED = IPRED;
double DV = Y;
$CAPTURE IPRED PRED DV
