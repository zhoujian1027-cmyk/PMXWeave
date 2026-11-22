# pmx_config.R - pkpd study configuration
# Covariate review from data_peek.sh on pkpd_data.csv (80 subjects, 1520 records;
# 80 single IV bolus doses CMT=1, 640 PK observations CMT=1/DVID=1, 800 PD observations
# CMT=2/DVID=2) and the supplied data_spec.csv.
# The control stream aliases DV=LNDV (natural-log response) and selects the residual
# branch by DVID; both endpoint columns are therefore excluded as covariates.
# Baseline demographics/disease/lab fields are constant within subject (changing_subjects=0).

COVARIATE_REVIEW <- data.frame(
  variable = c(
    "ID", "TIME", "DV", "LNDV", "AMT", "EVID", "CMT", "MDV", "ADDL", "II", "RATE",
    "STUDYID", "DVID", "DOSE",
    "BW", "AGE", "BMI", "ALB", "CRCL",
    "SEX", "RACE", "WTBL"
  ),
  role = c(
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded",
    "continuous", "continuous", "continuous", "continuous", "continuous",
    "categorical", "categorical", "excluded"
  ),
  reason = c(
    "Subject identifier",
    "Observation time (time-varying, changes within subject)",
    "Natural-scale observed response (PK mg/L or PD arbitrary units); dropped from the estimation input in favour of LNDV",
    "Modelled observation: natural logarithm of DV, used as DV by the control stream; must not be logged again",
    "Dose amount (regimen variable; mg/kg level times BW)",
    "NONMEM event identifier (event flag)",
    "Endpoint/compartment selector: CMT=1 dosing and PK records, CMT=2 PD observation selector; not a covariate",
    "MDV flag; exact duplicate of EVID in this dataset",
    "Additional-dose count, constant zero (regimen)",
    "Interdose interval, constant zero; exact duplicate of ADDL (regimen)",
    "Infusion rate, constant zero for IV bolus; exact duplicate of ADDL (regimen)",
    "Study identifier, constant (Study 101)",
    "Endpoint selector for the log-additive residual branch; exact duplicate of CMT",
    "Text dose-level label (1/3/10 mg/kg), excluded from model input by DOSE=DROP (regimen)",
    "Baseline body weight, kg, constant within subject (45-97.4)",
    "Baseline age, years, constant within subject (28-81)",
    "Baseline body mass index, kg/m2, constant within subject (16-36.4)",
    "Baseline albumin, g/dL, constant within subject (3.39-4.75)",
    "Baseline creatinine clearance, mL/min, constant within subject (39-160)",
    "Sex category, 1=Male (46 subjects, reference), 2=Female (34)",
    "Race category, 1=White (43 subjects, reference), 2=Asian (24), 3=Black or African American (8), 4=Other (5)",
    "Baseline body-weight alias; exactly duplicates BW, so it is not an independent covariate"
  ),
  stringsAsFactors = FALSE
)
