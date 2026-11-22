$PROB TMDD sim (mrgsolve translation of the frozen control stream by stage 2)
$PARAM TVCL = 0.21229622527200, TVVC = 5.46315959679000, TVKSS = 4.93491208102000, TVKDEG = 0.02329549711080, TVRSS = 9.93155436708000, TVKINT = 0.01398356430030, theta_VC_age = 0.00119308494394
$PARAM AGE = 40
$CMT CENTRAL RECEPTOR
$OMEGA @block
0.403608334559
0.000000000000 0.153126646102
0.000000000000 0.000000000000 0.259498010938
$SIGMA
0.263751301613
0.00101699526709
$MAIN
double TVVC_SCM = (TVVC * pow(((AGE / 40.0)),theta_VC_age));
double CL = (TVCL * exp(ETA(1)));
double VC = (TVVC_SCM * exp(ETA(2)));
double KSS = (TVKSS * exp(ETA(3)));
double KDEG = TVKDEG;
double RSS = TVRSS;
double KSYN = (KDEG * RSS);
double KINT = TVKINT;
RECEPTOR_0 = RSS;
$ODE
double LTOT = (CENTRAL / VC);
double RTOT = RECEPTOR;
double DISCR = ((LTOT - RTOT) - KSS);
double L = (0.5 * ((DISCR + sqrt(fmax(0.0,(pow(DISCR,2.0) + ((4.0 * KSS) * LTOT)))))));
double P = ((RTOT * L) / ((KSS + L)));
double R = ((RTOT * KSS) / ((KSS + L)));
dxdt_CENTRAL = (((-CL) * L) - ((KINT * P) * VC));
dxdt_RECEPTOR = ((KSYN - (KDEG * R)) - (KINT * P));
$TABLE
LTOT = (CENTRAL / VC);
RTOT = RECEPTOR;
double LFREE = (0.5 * (((((LTOT - RTOT) - KSS)) + sqrt((pow((((LTOT - RTOT) - KSS)),2.0) + ((4.0 * KSS) * LTOT))))));
double IPRED = log(((LFREE > 0.0) ? LFREE : 0.0001));
double IPRED_TARGET = log(((RTOT > 0.0) ? RTOT : 0.0001));
double DV_L = IPRED + (CENTRAL > 0.0 ? EPS(1) : 0.0);
double DV_R = IPRED_TARGET + (RTOT > 0.0 ? EPS(2) : 0.0);
$CAPTURE IPRED IPRED_TARGET DV_L DV_R
