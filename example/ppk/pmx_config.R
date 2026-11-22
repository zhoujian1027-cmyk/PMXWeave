# pmx_config.R - ppk study configuration
# Covariate review from data_peek.sh on ppk_data.csv (100 subjects, 2999 records;
# 300 depot doses CMT=1 at 100/200 mg, 2699 central observations CMT=2) and data_spec.csv.
# Baseline demographics/disease/lab fields are constant within subject (changing_subjects=0).

COVARIATE_REVIEW <- data.frame(
  variable = c(
    "ID", "TIME", "DV", "AMT", "EVID", "CMT", "MDV", "ADDL", "II", "RATE",
    "STUDYID", "DOSE", "ADY",
    "BW", "AGE", "BMI", "ALB", "CRCL",
    "SEX", "RACE"
  ),
  role = c(
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "excluded", "excluded", "excluded", "excluded", "excluded", "excluded", "excluded",
    "continuous", "continuous", "continuous", "continuous", "continuous",
    "categorical", "categorical"
  ),
  reason = c(
    "Subject identifier",
    "Observation time (time-varying, changes within subject)",
    "Observed response (drug concentration, mg/L)",
    "Dose amount (regimen variable)",
    "NONMEM event identifier (event flag)",
    "NONMEM compartment identifier (event flag)",
    "MDV flag; exact duplicate of EVID in this dataset",
    "Additional-dose count, constant zero (regimen)",
    "Interdose interval, constant zero; exact duplicate of ADDL (regimen)",
    "Infusion rate, constant zero; exact duplicate of ADDL (regimen)",
    "Study identifier, constant (Study 101)",
    "Text dose-group label, excluded from model input by DOSE=DROP (regimen)",
    "Analysis day derived from TIME (time-varying)",
    "Baseline body weight, kg, constant within subject (45-96.2)",
    "Baseline age, years, constant within subject (40-85)",
    "Baseline body mass index, kg/m2, constant within subject (16-36.2)",
    "Baseline albumin, g/dL, constant within subject (3.07-4.84)",
    "Baseline creatinine clearance, mL/min, constant within subject (30-156)",
    "Sex category, 1=Male (58 subjects, reference), 2=Female (42)",
    "Race category, 1=White (55 subjects, reference), 2=Asian (26), 3=Black or African American (15), 4=Other (4)"
  ),
  stringsAsFactors = FALSE
)
