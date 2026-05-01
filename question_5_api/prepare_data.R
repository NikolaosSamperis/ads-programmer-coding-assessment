# prepare_data.R --------------------------------------------------------------
# Export pharmaverseadam::adae to data/adae.csv so the FastAPI service can
# consume it. Run this once from the question_5_api/ directory:
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

# Only the columns the API endpoints actually use
keep <- c("USUBJID", "AESEV", "ACTARM")

write.csv(adae[, keep], "data/adae.csv", row.names = FALSE, na = "")
message("Wrote ", nrow(adae), " rows to data/adae.csv")
