# c-QTc study configuration
# Derived from the actual profile of cqtc_dummy_data.csv (1008 rows, 48 subjects,
# 112 subject-cycles x 9 nominal time points) and the supplied data_spec.csv.
#
# Design observed in the table:
#   48 subjects, 12 per regimen (drug-0.5 / 1.0 / 2.0 / 3.0 mg/kg Q3W),
#   22 subjects with 3 cycles, 20 with 2 and 6 with 1 (Cycle 1/2/3 Day 1, ADY 1/22/43),
#   9 nominal time points per cycle (PREDOSE, POST15M, POST30M, POST1H, POST2H,
#   POST4H, POST6H, POST8H, POST24H) ordered by ATPTN 1-9.
#   PKCONC: 817 numeric values, 191 blank of which 146 carry PKBLQ = "Y" and 45 are
#   blank with no BLQ flag (spread over every nominal time point, including one
#   PREDOSE record).
#   QTCFAG available on all 1008 records (381.5 to 455.1 ms); BQTCF available for
#   46 of 48 subjects (missing for CQTC-001-020 and CQTC-001-037).

COVARIATE_REVIEW <- data.frame(
  variable = c(
    # prespecified base-model adjustment
    "BQTCF",
    # optional screening candidates
    "AGE", "SEX", "RACE", "AETHNIC", "ECOGBL", "TUMTP",
    # identifiers, structure and on-treatment measurements
    "STUDYID", "USUBJID", "ADY", "ATPTN", "ATPT", "TSFD", "PCTEST",
    "PKCONC", "PKBLQ", "QTCFAG", "CFBQTCF", "HRAG", "BHR", "CFBHR",
    "TRTA", "AVISIT"
  ),
  role = c(
    "prespecified",
    "continuous", "categorical", "categorical", "categorical", "categorical", "categorical",
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded"
  ),
  reason = c(
    "Subject baseline QTcF supplied in the table and used as the prespecified base-model adjustment; retained in mandatory_cov rather than screened. Missing for 2 of 48 subjects, so those subjects contribute no baseline-adjusted change",
    "Baseline age, 35 to 78 years, median 57; screened as a continuous baseline covariate on the concentration-QTcF relationship",
    "Baseline sex, 20 female and 28 male; screened as a categorical baseline covariate",
    "Baseline race, White 25, Asian 16, Black or African American 7; screened as a categorical baseline covariate",
    "Baseline ethnicity, Not Hispanic or Latino 38, Hispanic or Latino 10; screened as a categorical baseline covariate",
    "Baseline ECOG performance status, 0 in 37 and 1 in 11 subjects; screened as a categorical baseline covariate",
    "Baseline tumour type, NSCLC 12, Breast 12, Ovarian 9, Gastric 8, Colorectal 7; screened as a categorical baseline covariate",
    "Single study identifier CQTC-001; no between-study contrast is possible",
    "Subject identifier used for the within-subject random effects, not a covariate",
    "Analysis day (1, 22, 43) identifies the dosing cycle; a time/structure variable, not a baseline covariate",
    "Nominal time point ordering code; a structure variable used to order records",
    "Nominal time point label; a structure variable, and time is not a baseline characteristic",
    "Time since first dose used for time-course displays; an on-study time variable, not a baseline covariate",
    "Single analyte label drug; selects the concentration records, not a covariate",
    "Model predictor of the concentration-QTcF analysis; entering it as a covariate would duplicate the primary term",
    "Below-quantification flag used to exclude records, not a covariate",
    "Absolute QTcF is the outcome from which the change is derived; not a covariate",
    "Change from baseline QTcF is the analysis response; not a covariate",
    "Heart rate is an on-treatment measurement, not a baseline characteristic; QTcF already applies the Fridericia rate correction, so rate is reported in the heart-rate section instead of being screened",
    "Baseline heart rate is a rate-correction input rather than a baseline covariate; QTcF is already rate-corrected, so adding it would double-count the rate effect",
    "Change from baseline heart rate is an on-treatment derived measurement; not a baseline covariate",
    "Treatment regimen label defines the exposure groups and the dose range; descriptive grouping, and dose is not screened as a covariate in a concentration-QTcF model",
    "Analysis visit label identifies the cycle; a structure variable, not a baseline covariate"
  ),
  stringsAsFactors = FALSE
)

# Optional candidates plus the prespecified baseline adjustment. The intake check
# compares cov_want minus the prespecified fields against the reviewed
# continuous and categorical fields.
cov_want <- c("AGE", "SEX", "RACE", "AETHNIC", "ECOGBL", "TUMTP", "BQTCF")
cov_categorical <- c("SEX", "RACE", "AETHNIC", "ECOGBL", "TUMTP")
mandatory_cov <- c("BQTCF")

cov_label <- c(
  AGE     = "Age (years)",
  RACE    = "Race",
  SEX     = "Sex",
  AETHNIC = "Ethnicity",
  ECOGBL  = "ECOG performance status",
  TUMTP   = "Tumour type",
  BQTCF   = "Baseline QTcF (ms)"
)

# Level display uses the codes actually present in the table.
cov_levels <- list(
  SEX     = c(M = "Male", F = "Female"),
  RACE    = c(WHITE = "White", ASIAN = "Asian",
              `BLACK OR AFRICAN AMERICAN` = "Black or African American"),
  AETHNIC = c(`NOT HISPANIC OR LATINO` = "Not Hispanic or Latino",
              `HISPANIC OR LATINO` = "Hispanic or Latino"),
  ECOGBL  = c("0" = "0", "1" = "1"),
  TUMTP   = c(NSCLC = "NSCLC", Breast = "Breast", Colorectal = "Colorectal",
              Gastric = "Gastric", Ovarian = "Ovarian")
)

# Reference level = the most frequent level of each categorical covariate.
cov_ref <- "modal"

# Analyte: PCTEST carries the single generic label drug.
ANALYTE_NAME <- "drug"

# The response is taken from the paired QTCFAG and BQTCF values. The data
# dictionary notes that five supplied CFBQTCF records differ from QTCFAG minus
# BQTCF by more than 0.11 ms and that the analysis response is calculated from
# the paired values, so the derived source is declared explicitly.
QT_CHANGE_SOURCE <- "derived"

# The data dictionary states that no physical unit was supplied for PKCONC
# (status release_review_required), so no unit is asserted and no conversion is
# performed; slopes are reported per input concentration unit and this is
# disclosed in the report.
CONC_UNIT <- ""
