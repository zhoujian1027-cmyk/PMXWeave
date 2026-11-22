$PARAM TVCL = 0.25, TVVC = 2, TVKSS = 1, TVKDEG = 0.1, TVRSS = 3, TVKINT = 0.5

$CMT CENTRAL RECEPTOR

$OMEGA
0.09 0.16

$SIGMA
0.1 0.1

$MAIN
double CL = TVCL * exp(ETA(1));
double VC = TVVC * exp(ETA(2));
double KSS = TVKSS;
double KDEG = TVKDEG;
double RSS = TVRSS;
double KSYN = KDEG * RSS;
double KINT = TVKINT;
RECEPTOR_0 = RSS;

$ODE
double L = 0.5 * (((CENTRAL / VC) - RECEPTOR - KSS) +
  sqrt(pow((CENTRAL / VC) - RECEPTOR - KSS, 2.0) + 4.0 * KSS * (CENTRAL / VC)));
dxdt_CENTRAL = -CL * L - KINT * RECEPTOR * L / (KSS + L) * VC;
dxdt_RECEPTOR = KSYN - KDEG * RECEPTOR * KSS / (KSS + L) - KINT * RECEPTOR * L / (KSS + L);

$TABLE
double LTOT = CENTRAL / VC;
double RTOT = RECEPTOR;
double LFREE = 0.5 * ((LTOT - RTOT - KSS) +
  sqrt(pow(LTOT - RTOT - KSS, 2.0) + 4.0 * KSS * LTOT));
double IPRED_L = LFREE;
double IPRED_RT = RTOT;
double IPRED = log(0.0001);
double IPRED_TARGET = log(0.0001);
double L_O = LFREE;

double DV_L = IPRED;
double DV_R = IPRED_TARGET;
if (LTOT > 0.0) {
  if (LFREE > 0.0) IPRED = log(LFREE);
  DV_L = IPRED + EPS(1);
}
if (RTOT > 0.0) {
  IPRED_TARGET = log(RTOT);
  DV_R = IPRED_TARGET + EPS(2);
}

$CAPTURE IPRED_L IPRED_RT IPRED IPRED_TARGET L_O DV_L DV_R
