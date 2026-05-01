# prepare_data.R --------------------------------------------------------------
# Export pharmaverseadam::adae to data/adae.csv so the GenAI agent can
# consume it. Run this once from the question_6_genai/ directory:
#
#     Rscript prepare_data.R
#
# Requires: pharmaverseadam (>= 0.1.0)
# -----------------------------------------------------------------------------

if (!requireNamespace("pharmaverseadam", quietly = TRUE)) {
  install.packages("pharmaverseadam")
}

if (!dir.exists("data")) {
  dir.create("data")
  message("Created data/ directory")
}

adae <- pharmaverseadam::adae

# All columns the ClinicalTrialDataAgent reads from. See schema.py for the
# matching Python-side schema used to prompt the LLM.
keep <- c(
  "USUBJID",   # subject identifier (returned by the agent)
  "AETERM",    # specific AE term / condition
  "AESEV",     # severity / intensity
  "AESOC",     # system organ class (body system)
  "AEREL",     # causality / relationship to study drug
  "ACTARM",    # actual treatment arm
  "AESTDTC",   # AE start date (ISO 8601)
  "AEENDTC"    # AE end date   (ISO 8601)
)

write.csv(adae[, keep], "data/adae.csv", row.names = FALSE, na = "")
message("Wrote ", nrow(adae), " rows to data/adae.csv")
