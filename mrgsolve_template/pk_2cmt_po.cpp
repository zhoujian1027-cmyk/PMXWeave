$PARAM TVCL = 5, TVV2 = 50, TVQ = 10, TVV3 = 50, TVKA = 1, TVLAG = 0.5

$PARAM SEXEFF = 1, AGEPWR = 0.5

$PARAM BW = 70, SEX = 1, AGE = 40

$CMT DEPOT CENTRAL PERIPH

$OMEGA
0.09 0.16 0.09 0.16 0.25 0.1

$SIGMA
0.1

$MAIN
double FSEX = (SEX == 2) ? SEXEFF : 1.0;
double FAGE = pow(AGE / 40.0, AGEPWR);
double FBWCL = pow(BW / 70.0, 0.75);
double CL = TVCL * exp(ETA(1)) * FBWCL * FSEX * FAGE;
double V2 = TVV2 * exp(ETA(2));
double Q = TVQ * exp(ETA(3));
double V3 = TVV3 * exp(ETA(4));
double KA = TVKA * exp(ETA(5));
double ALAG = TVLAG * exp(ETA(6));
ALAG_DEPOT = ALAG;

$ODE
dxdt_DEPOT = -KA * DEPOT;
dxdt_CENTRAL = KA * DEPOT - (CL / V2) * CENTRAL - (Q / V2) * CENTRAL + (Q / V3) * PERIPH;
dxdt_PERIPH = (Q / V2) * CENTRAL - (Q / V3) * PERIPH;

$TABLE
double IPRED = CENTRAL / V2;

double DV = IPRED + IPRED * EPS(1);

$CAPTURE IPRED DV CL

