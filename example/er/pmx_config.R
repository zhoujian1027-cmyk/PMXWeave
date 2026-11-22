# ER study configuration
# Written from the actual er_data.csv profile (data_peek.sh --covariates: 420 subject rows,
# 46 columns, one row per subject) and the supplied data_spec.csv.

# ---------------------------------------------------------------------------
# Covariate intake: every inspected field, with role and reason.
# ---------------------------------------------------------------------------
COVARIATE_REVIEW <- data.frame(
  variable = c(
    "ID","STUDYID","USUBJID","TRT","DOSE","INDICATION","PKFL","EFFFL","SAFEFL","EXCLREAS",
    "AGE","AGEGR1","SEX","RACE","ECOGBL","WGTRL","WGTBL","BMI","ALB","CRCL","REGION","BSA",
    "LDH","HGB","NEUT","PLT","NPTRLINE","DISSTG","BRAINM",
    "Cavg24hss","Cmax24hss","Cmin24hss","AUCss","Cavg_EOT",
    "UMRD","UMRDTIME","UMRDEVT","UMRDSTATUS","BOR","ORR","DORMIN","DOREVT",
    "FATIGUE","NEUTROPENIA","HEADACHE","SAE",
    "ECOGBL0","SEXF","NPTRLINEG3","LDHHI","NEUTLOW"
  ),
  role = c(
    "excluded","categorical","excluded","excluded","excluded","excluded","excluded","excluded","excluded","excluded",
    "continuous","categorical","excluded","categorical","excluded","continuous","excluded","continuous","continuous","continuous","categorical","continuous",
    "continuous","continuous","continuous","continuous","excluded","categorical","categorical",
    "excluded","excluded","excluded","excluded","excluded",
    "excluded","excluded","excluded","excluded","excluded","excluded","excluded","excluded",
    "excluded","excluded","excluded","excluded",
    "categorical","categorical","categorical","categorical","categorical"
  ),
  reason = c(
    "Subject identifier, not an analysis covariate",
    "Dataset pools two recorded studies (ER-101, ER-102); retained so a study effect is tested rather than assumed absent",
    "Unique subject identifier (STUDYID + ID), not an analysis covariate",
    "Treatment text label duplicating DOSE; dose is used as the descriptive grouping variable",
    "Dose is the descriptive dose/regimen grouping (DOSE_VAR); the template forbids dose as a modelled covariate unless the analysis plan is explicitly revised",
    "Single level in the supplied data, no contrast available",
    "Population-kinetics flag; its role is the missingness pattern of the steady-state exposure metrics",
    "Efficacy flag; defines the evaluable efficacy rows, not a covariate",
    "Safety flag; an exact duplicate of PKFL in this dataset",
    "Exclusion reason, populated for 5 of 420 subjects only; documents analysis-set membership",
    "Baseline age, 26 to 88 years, modelled continuously",
    "Baseline age group (<65, >=65) as supplied; categorical contrast",
    "Raw sex field used solely to derive the modelled categorical covariate SEXF",
    "Baseline race (White, Asian, Black or African American, Other); 8 subjects missing race",
    "Raw baseline ECOG performance score used solely to derive the modelled covariate ECOGBL0",
    "Baseline body weight, 38 to 116.6 kg, the ER template weight field (WGTRL)",
    "Baseline weight column that is an exact duplicate of WGTRL in this dataset; retained once as WGTRL",
    "Baseline body mass index, 12.6 to 48.7 kg/m2",
    "Baseline albumin, 26.6 to 48.9 g/L (unit declared in COV_UNIT); 6 subjects missing",
    "Baseline creatinine clearance, 25 to 150 mL/min; 4 subjects missing",
    "Baseline geographic region (Europe, North America, Asia, Rest of world)",
    "Baseline body surface area, 1.29 to 2.38 m2; the data dictionary places BSA in continuous screening",
    "Baseline lactate dehydrogenase, 90 to 501 U/L; 5 subjects missing",
    "Baseline haemoglobin, 70 to 165 g/L",
    "Baseline neutrophil count, 0.4 to 8.02 x10^9/L",
    "Baseline platelet count, 40 to 441 x10^9/L",
    "Raw prior-line count used solely to derive the modelled covariate NPTRLINEG3",
    "Baseline disease stage (Stage III, Stage IV)",
    "Baseline brain metastases (No, Yes)",
    "Primary exposure metric for the exposure-response models (PK_EXPO); not a covariate",
    "Alternative steady-state exposure metric; one exposure term per model to avoid collinearity",
    "Alternative steady-state exposure metric; one exposure term per model to avoid collinearity",
    "Steady-state AUC, described in the data dictionary as approximately 24 x Cavg24hss, collinear with PK_EXPO",
    "Exposure to end of treatment, reserved by the data dictionary for the duration-of-response analysis (PK_EXPO_EOT)",
    "Binary efficacy endpoint (undetectable MRD)",
    "Time-to-event time variable for the time-to-uMRD analysis",
    "Time-to-event indicator for the time-to-uMRD analysis; an exact duplicate of UMRD",
    "Underlying uMRD status codes (0, 1, 2) behind UMRD and UMRDEVT",
    "Best overall response categories (CR, PR, SD, PD); the source of the binary ORR endpoint",
    "Binary efficacy endpoint (objective response)",
    "Duration-of-response time variable (months), responders only",
    "Duration-of-response event indicator, responders only",
    "Safety binary analysed descriptively and by exposure group; not among the prespecified modelled safety endpoints",
    "Safety binary analysed descriptively and by exposure group; not among the prespecified modelled safety endpoints",
    "Safety binary analysed descriptively and by exposure group; not among the prespecified modelled safety endpoints",
    "Safety binary selected as a prespecified modelled safety endpoint via SAFETY_MODEL_ENDPOINTS",
    "Derived baseline indicator ECOG 0 versus 1 or 2, the modelled form of ECOGBL",
    "Derived sex indicator used as the modelled categorical form of SEX",
    "Derived indicator of at least 3 prior therapy lines, the modelled categorical form of NPTRLINE",
    "Derived indicator above the assumed upper limit of normal of 250 U/L (no study-specific limit is supplied); LDH is also screened continuously",
    "Derived baseline neutropenia indicator below 1.5 x10^9/L; the neutrophil count is also screened continuously"
  ),
  stringsAsFactors = FALSE
)

# ---------------------------------------------------------------------------
# Declared covariate sets (must match the review roles exactly).
# ---------------------------------------------------------------------------
CON_COV <- c("AGE", "WGTRL", "BMI", "BSA", "ALB", "CRCL", "LDH", "HGB", "NEUT", "PLT")

CAT_COV <- c("STUDYID", "ECOGBL0", "AGEGR1", "SEXF", "RACE", "REGION", "DISSTG",
             "BRAINM", "NPTRLINEG3", "LDHHI", "NEUTLOW")

COV_LABEL <- c(
  STUDYID    = "Study",
  AGE        = "Age",
  WGTRL      = "Body weight",
  BMI        = "BMI",
  BSA        = "Body surface area",
  ALB        = "Albumin",
  CRCL       = "Creatinine clearance",
  LDH        = "Lactate dehydrogenase",
  HGB        = "Haemoglobin",
  NEUT       = "Neutrophils",
  PLT        = "Platelets",
  LDHHI      = "LDH above the assumed upper limit of normal",
  NEUTLOW    = "Baseline neutropenia",
  NPTRLINEG3 = "At least 3 prior lines",
  AGEGR1     = "Age group",
  ECOGBL0    = "ECOG 0",
  SEXF       = "Sex",
  RACE       = "Race",
  REGION     = "Region",
  DISSTG     = "Disease stage",
  BRAINM     = "Brain metastases",
  DOSE       = "Dose",
  DOSEF      = "Dose group"
)

# Albumin is reported in g/L in this dataset (range 26.6 to 48.9); the low-albumin
# summary therefore uses the 35 g/L threshold, and no study LLN override is supplied.
ALBUMIN_LLN <- NULL

COV_UNIT <- c(
  AGE      = "years",
  WGTRL    = "kg",
  BMI      = "kg/m2",
  BSA      = "m2",
  ALB      = "g/L",
  CRCL     = "mL/min",
  LDH      = "U/L",
  HGB      = "g/L",
  NEUT     = "10^9/L",
  PLT      = "10^9/L",
  DOSE     = "mg"
)

COV_LEVELS <- list(
  SEXF       = c(M = "Male", F = "Female"),
  AGEGR1     = c("<65" = "< 65 years", ">=65" = ">= 65 years"),
  DISSTG     = c("Stage III" = "Stage III", "Stage IV" = "Stage IV"),
  BRAINM     = c(No = "No", Yes = "Yes"),
  LDHHI      = c(No = "No", Yes = "Yes"),
  NEUTLOW    = c(No = "No", Yes = "Yes"),
  NPTRLINEG3 = c(No = "No", Yes = "Yes")
)

COV_REF <- "modal"

# ---------------------------------------------------------------------------
# Switches and endpoints for this dataset.
# ---------------------------------------------------------------------------
# Primary steady-state exposure; log-transformed in the models.
PK_EXPO     <- "Cavg24hss"
PK_EXPO_EOT <- "Cavg_EOT"
LOGPK       <- TRUE
N_QUANTILE  <- 4
SCREEN_P    <- NA            # BIC-only selection

# Formal logistic modelling of the prespecified safety endpoint present in this
# table. The template safety catalogue (er_analysis.Rmd SAFETY_DEF) covers SAE and
# grade 3 haematologic/organ events; FATIGUE, HEADACHE and NEUTROPENIA fall outside
# that catalogue and are therefore not modelled here (disclosed in Section 4.3).
SAFETY_MODEL_ENDPOINTS <- "SAE"

# The supplied table carries no progression-free-survival or overall-survival fields.
RUN_PFS <- FALSE

DOSE_VAR  <- "DOSE"
REG_LABEL <- "Dose (mg QD)"
