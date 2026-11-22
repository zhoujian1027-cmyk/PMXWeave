# pmx_config.R - tmdd study configuration
# Covariate review from data_peek.sh on tmdd_data.csv (50 subjects, 850 records;
# 50 single IV doses CMT=1 at 10/100/1000 nmol absolute, 400 free-ligand observations
# CMT=1 and 400 total-target observations CMT=2) and the supplied data_spec.csv.
# The control stream aliases DV=LNDV (natural logarithm of the natural-scale nM value)
# and selects the residual branch by CMT; both observation columns are excluded.
# Baseline demographics/lab fields are constant within subject (changing_subjects=0).

COVARIATE_REVIEW <- data.frame(
  variable = c(
    "ID", "TIME", "DV", "LNDV", "AMT", "EVID", "CMT", "MDV", "ADDL", "II", "RATE",
    "STUDYID", "DOSE",
    "BW", "AGE", "BMI", "ALB", "CRCL",
    "SEX", "RACE", "WTBL"
  ),
  role = c(
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded",
    "continuous", "continuous", "continuous", "continuous", "continuous",
    "categorical", "categorical", "excluded"
  ),
  reason = c(
    "Subject identifier",
    "Observation time (time-varying, changes within subject)",
    "Natural-scale observed concentration in nM (free ligand for CMT=1, total target for CMT=2); dropped from the estimation input in favour of LNDV",
    "Modelled observation: natural logarithm of DV, used as DV by the control stream; must not be logged again. 26 of 400 ligand records have DV <= 0 and therefore no log value, so they carry no likelihood information",
    "Dose amount, absolute nmol (10/100/1000), not weight-normalised (regimen variable)",
    "NONMEM event identifier (event flag)",
    "Compartment/endpoint selector: CMT=1 dosing and free-ligand records, CMT=2 total-target records; not a covariate",
    "MDV flag; exact duplicate of EVID in this dataset",
    "Additional-dose count, constant zero (regimen)",
    "Interdose interval, constant zero; exact duplicate of ADDL (regimen)",
    "Infusion rate, constant zero for IV bolus; exact duplicate of ADDL (regimen)",
    "Study identifier, constant (Study 101)",
    "Text dose-level label (10/100/1000 nmol), excluded from model input by DOSE=DROP (regimen)",
    "Baseline body weight, kg, constant within subject (45-107.2)",
    "Baseline age, years, constant within subject (32-85)",
    "Baseline body mass index, kg/m2, constant within subject (16-36.4)",
    "Baseline albumin, g/dL, constant within subject (3.52-4.79)",
    "Baseline creatinine clearance, mL/min, constant within subject (30-160)",
    "Sex category, 1=Male (25 subjects, reference), 2=Female (25)",
    "Race category, 1=White (27 subjects, reference), 2=Asian (16), 3=Black or African American (6), 4=Other (1 subject, too small to support a contrast)",
    "Baseline body-weight alias; exactly duplicates BW, so it is not an independent covariate"
  ),
  stringsAsFactors = FALSE
)
