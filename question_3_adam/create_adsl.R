# =============================================================================
# Question 3 -- ADaM ADSL (Subject Level Analysis Dataset) Creation
# -----------------------------------------------------------------------------
# Author      : Nikolaos Samperis
# Description : Builds an ADaM ADSL dataset from SDTM source domains
#               (DM, EX, VS, DS, AE) using the {admiral} family of packages
#               and tidyverse tools. Follows the pattern from the official
#               admiral ADSL article and adds the assessment-specified
#               derivations on top of the DM-based starting point.
#
# Required derivations (per the assessment spec):
#   - AGEGR9 / AGEGR9N : age categories "<18", "18 - 50", ">50" (1 / 2 / 3)
#   - TRTSDTM / TRTSTMF: first valid-dose exposure datetime + imputation flag
#   - ITTFL            : "Y"/"N" flag, "Y" if DM.ARM is not missing
#   - ABNSBPFL         : "Y"/"N" flag for any abnormal SBP (<100 or >=140 mmHg)
#   - LSTALVDT         : last known alive date (max across VS/AE/DS/EX dates)
#   - CARPOPFL         : "Y"/NA flag for any AE with AESOC = "CARDIAC DISORDERS"
#
# Inputs      : pharmaversesdtm::dm, ::ex, ::vs, ::ds, ::ae
# Output      : An ADaM-compliant `adsl` tibble, written to output/adsl.{csv,rds}
#
# References  : - admiral ADSL article
#                 https://pharmaverse.github.io/admiral/cran-release/articles/adsl.html
#               - CDISC ADaM IG v1.3
# =============================================================================


# 0. Setup --------------------------------------------------------------------
# install.packages(c("admiral", "pharmaversesdtm", "dplyr",
#                    "stringr", "lubridate", "readr"))

suppressPackageStartupMessages({
  library(admiral)
  library(pharmaversesdtm)
  library(dplyr)
  library(stringr)
  library(lubridate)
  library(readr)
})

out_dir <- file.path("output")


# 1. Load SDTM source data ----------------------------------------------------
# All five domains come from {pharmaversesdtm}. The DS domain produced by
# Question 2 could be substituted here, but the assessment explicitly names
# pharmaversesdtm::ds as the input -- using it keeps Q3 independent of Q2.

data("dm", package = "pharmaversesdtm")
data("ex", package = "pharmaversesdtm")
data("vs", package = "pharmaversesdtm")
data("ds", package = "pharmaversesdtm")
data("ae", package = "pharmaversesdtm")

# Pre-compute Date variants of the *DTC fields used downstream by date_source()
# objects and exposure filters. admiral expects Date / POSIXct, not character.
ae <- ae %>% mutate(AESTDT = convert_dtc_to_dt(AESTDTC))
vs <- vs %>% mutate(VSDT   = convert_dtc_to_dt(VSDTC))
ds <- ds %>% mutate(DSSTDT = convert_dtc_to_dt(DSSTDTC))
ex <- ex %>%
  mutate(
    EXSTDT = convert_dtc_to_dt(EXSTDTC),
    EXENDT = convert_dtc_to_dt(EXENDTC)
  )


# 2. Initialize ADSL from DM --------------------------------------------------
# Per the admiral ADSL article, the DM domain is the base. DOMAIN is dropped
# because ADaM datasets do not carry the SDTM DOMAIN variable.

adsl <- dm %>% select(-DOMAIN)


# 3. Derive AGEGR9 and AGEGR9N ------------------------------------------------
# Categories: "<18" (1), "18 - 50" (2), ">50" (3). NA AGE -> NA AGEGR9/AGEGR9N
# via the natural NA propagation in case_when().

adsl <- adsl %>%
  mutate(
    AGEGR9 = case_when(
      AGE <  18              ~ "<18",
      AGE >= 18 & AGE <= 50  ~ "18 - 50",
      AGE >  50              ~ ">50"
    ),
    AGEGR9N = case_when(
      AGEGR9 == "<18"     ~ 1L,
      AGEGR9 == "18 - 50" ~ 2L,
      AGEGR9 == ">50"     ~ 3L
    )
  )


# 4. Derive ITTFL -------------------------------------------------------------
# Per the spec literally: "Y" if DM.ARM is not missing, else "N".
#
# Note: in pharmaversesdtm::dm, screen-failure subjects have ARM =
# "Screen Failure" (not NA), so the literal rule classifies them as ITT. The
# admiral ADSL example uses the stricter `ARM != "Screen Failure"` test; that
# alternative is shown commented out below.

adsl <- adsl %>%
  mutate(
    ITTFL = if_else(!is.na(ARM), "Y", "N")
    # Stricter alternative (matches admiral example):
    # ITTFL = if_else(!is.na(ARM) & ARM != "Screen Failure", "Y", "N")
  )


# 5. Derive TRTSDTM and TRTSTMF -----------------------------------------------
# First exposure record per subject where the dose is "valid":
#   - EXDOSE > 0, OR
#   - EXDOSE == 0 AND EXTRT contains "PLACEBO"
#
# Time imputation rules:
#   - completely missing time         -> 00:00:00
#   - partially missing components    -> 00 for missing hours / minutes
#   - if only seconds are missing     -> do NOT populate the imputation flag
#
# `highest_imputation = "h"` restricts imputation to the time portion (hours
# and below); incomplete dates remain NA. `ignore_seconds_flag = TRUE` is the
# admiral switch that matches the "do not flag seconds-only imputation" rule.

ex_dtm <- ex %>%
  derive_vars_dtm(
    dtc                 = EXSTDTC,
    new_vars_prefix     = "TRTS",
    highest_imputation  = "h",
    time_imputation     = "00:00:00",
    ignore_seconds_flag = TRUE
  )

adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_dtm,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDTM, TRTSTMF),
    filter_add  = (EXDOSE > 0 |
                   (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
                  !is.na(TRTSDTM),
    order       = exprs(TRTSDTM, EXSEQ),
    mode        = "first"
  )


# 6. Derive ABNSBPFL ----------------------------------------------------------
# "Y" if subject has any VS observation with VSTESTCD = "SYSBP", VSSTRESU =
# "mmHg", and VSSTRESN < 100 or >= 140. Else "N".
#
# Note on "supine": the assessment summary describes this as a supine SBP
# flag, but the detailed spec has no VSPOS filter. The detailed spec is
# followed below. To restrict to supine measurements only, add
# `VSPOS == "SUPINE"` to the condition.

adsl <- adsl %>%
  derive_var_merged_exist_flag(
    dataset_add   = vs,
    by_vars       = exprs(STUDYID, USUBJID),
    new_var       = ABNSBPFL,
    condition     = VSTESTCD  == "SYSBP" &
                    VSSTRESU  == "mmHg" &
                    (VSSTRESN >= 140 | VSSTRESN < 100),
    false_value   = "N",
    missing_value = "N"
  )


# 7. Derive CARPOPFL ----------------------------------------------------------
# "Y" if subject has any AE with AESOC = "CARDIAC DISORDERS"
# (case-insensitive), else NA. Note the spec is Y/NA, not Y/N -- so the
# defaults for false_value and missing_value (both NA) are kept.

adsl <- adsl %>%
  derive_var_merged_exist_flag(
    dataset_add = ae,
    by_vars     = exprs(STUDYID, USUBJID),
    new_var     = CARPOPFL,
    condition   = toupper(AESOC) == "CARDIAC DISORDERS"
    # false_value and missing_value default to NA, per spec (Y/NA flag)
  )


# 8. Derive LSTALVDT ----------------------------------------------------------
# Last known alive date: max across the four sources defined in the spec.
# Each source is wrapped in an event() so admiral can pool them and return
# the latest date per subject via derive_vars_extreme_event(mode = "last").
#
# Note: this section uses the modern event() / derive_vars_extreme_event()
# API introduced in admiral 1.2.0. The earlier date_source() /
# derive_var_extreme_dt() pair was deprecated in the same release and will
# be removed in 2027.
#
# Sources:
#   (1) VS  : VSDT, where (VSSTRESN, VSSTRESC) are not both missing
#   (2) AE  : AESTDT
#   (3) DS  : DSSTDT
#   (4) EX  : EXSTDT and EXENDT, restricted to valid-dose records
#
# EXSTDT is included alongside EXENDT so subjects whose EXENDTC is missing
# still contribute via the start date. With mode = "last", admiral picks the
# latest LSTALVDT across all events; ties between EX start and end on the
# same record naturally collapse to the same value.

ae_lstalv <- event(
  dataset_name  = "ae",
  condition     = !is.na(AESTDT),
  set_values_to = exprs(LSTALVDT = AESTDT)
)

vs_lstalv <- event(
  dataset_name  = "vs",
  condition     = !is.na(VSDT) & !(is.na(VSSTRESN) & is.na(VSSTRESC)),
  set_values_to = exprs(LSTALVDT = VSDT)
)

ds_lstalv <- event(
  dataset_name  = "ds",
  condition     = !is.na(DSSTDT),
  set_values_to = exprs(LSTALVDT = DSSTDT)
)

ex_st_lstalv <- event(
  dataset_name  = "ex",
  condition     = !is.na(EXSTDT) &
    (EXDOSE > 0 |
       (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))),
  set_values_to = exprs(LSTALVDT = EXSTDT)
)

ex_en_lstalv <- event(
  dataset_name  = "ex",
  condition     = !is.na(EXENDT) &
    (EXDOSE > 0 |
       (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))),
  set_values_to = exprs(LSTALVDT = EXENDT)
)

adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars         = exprs(STUDYID, USUBJID),
    events          = list(ae_lstalv, vs_lstalv, ds_lstalv,
                           ex_st_lstalv, ex_en_lstalv),
    source_datasets = list(ae = ae, vs = vs, ds = ds, ex = ex),
    order           = exprs(LSTALVDT),
    mode            = "last",
    new_vars        = exprs(LSTALVDT)
  )



# 9. Final ordering -----------------------------------------------------------
# Keep the standard DM-derived columns first, then group the assessment-
# specified derivations. Variables not produced by this script (e.g. RFXSTDTC)
# are passed through from DM unchanged.

adsl <- adsl %>%
  relocate(
    AGEGR9, AGEGR9N,
    ITTFL,
    TRTSDTM, TRTSTMF,
    ABNSBPFL,
    CARPOPFL,
    LSTALVDT,
    .after = last_col()
  )


# 10. Validation --------------------------------------------------------------
# Hard invariants enforced via stopifnot() so the script fails loudly if any
# derivation breaks. Soft summaries are printed for visual review.

cat("\n=== Validation: hard invariants ===\n")

# 10.1 All required derived variables are present
required_derived <- c("AGEGR9", "AGEGR9N", "ITTFL",
                      "TRTSDTM", "TRTSTMF",
                      "ABNSBPFL", "CARPOPFL", "LSTALVDT")
stopifnot(all(required_derived %in% names(adsl)))

# 10.2 One row per subject
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))

# 10.3 AGEGR9 is restricted to the three allowed levels (or NA)
stopifnot(all(adsl$AGEGR9 %in% c("<18", "18 - 50", ">50") | is.na(adsl$AGEGR9)))

# 10.4 AGEGR9 <-> AGEGR9N mapping is consistent
stopifnot(all(
  is.na(adsl$AGEGR9) |
    (adsl$AGEGR9 == "<18"     & adsl$AGEGR9N == 1L) |
    (adsl$AGEGR9 == "18 - 50" & adsl$AGEGR9N == 2L) |
    (adsl$AGEGR9 == ">50"     & adsl$AGEGR9N == 3L)
))

# 10.5 AGEGR9 matches AGE
stopifnot(all(
  is.na(adsl$AGE) |
    (adsl$AGE <  18              & adsl$AGEGR9 == "<18") |
    (adsl$AGE >= 18 & adsl$AGE <= 50 & adsl$AGEGR9 == "18 - 50") |
    (adsl$AGE >  50              & adsl$AGEGR9 == ">50")
))

# 10.6 ITTFL and ABNSBPFL are restricted to "Y"/"N"
stopifnot(all(adsl$ITTFL    %in% c("Y", "N")))
stopifnot(all(adsl$ABNSBPFL %in% c("Y", "N")))

# 10.7 CARPOPFL is "Y" or NA only (per spec, NOT "N")
stopifnot(all(is.na(adsl$CARPOPFL) | adsl$CARPOPFL == "Y"))

# 10.8 ITTFL is consistent with ARM presence (the literal rule)
stopifnot(all(
  (is.na(adsl$ARM)  & adsl$ITTFL == "N") |
    (!is.na(adsl$ARM) & adsl$ITTFL == "Y")
))

# 10.9 Date / datetime types are correct
stopifnot(inherits(adsl$LSTALVDT, "Date"))
# TRTSDTM should be POSIXct; if admiral returned a Date (version-dependent
# behaviour when all times are imputed to midnight), coerce it here and warn.
if (!inherits(adsl$TRTSDTM, "POSIXct")) {
  warning("TRTSDTM is not POSIXct (class: ",
          paste(class(adsl$TRTSDTM), collapse = "/"),
          ") -- coercing to POSIXct UTC.")
  adsl$TRTSDTM <- as.POSIXct(as.character(adsl$TRTSDTM), tz = "UTC")
}
stopifnot(inherits(adsl$TRTSDTM,  "POSIXct"))

cat("All hard invariants passed.\n")


cat("\n=== Validation: soft summaries ===\n")
cat("Number of subjects:", nrow(adsl), "\n\n")

cat("AGEGR9 / AGEGR9N distribution:\n")
print(count(adsl, AGEGR9, AGEGR9N))

cat("\nITTFL by ARM:\n")
print(count(adsl, ARM, ITTFL))

cat("\nABNSBPFL distribution:\n")
print(count(adsl, ABNSBPFL))

cat("\nCARPOPFL distribution:\n")
print(count(adsl, CARPOPFL, useNA = "ifany"))

cat("\nTRTSTMF distribution (NA = not imputed):\n")
print(count(adsl, TRTSTMF, useNA = "ifany"))

cat("\nLSTALVDT range:\n")
print(summary(adsl$LSTALVDT))

cat("\nFirst 10 ADSL records (key derived variables):\n")
print(adsl %>%
        select(USUBJID, AGE, AGEGR9, AGEGR9N, ARM, ITTFL,
               TRTSDTM, TRTSTMF, ABNSBPFL, CARPOPFL, LSTALVDT) %>%
        head(10))


# 11. Apply variable labels ---------------------------------------------------
# Variables inherited from pharmaversesdtm::dm already carry SAS-style column
# labels as R attributes. The derived variables created by this script have
# none by default. Adding labels here makes the dataset consistent and
# mirrors what a production ADSL submission dataset would look like.

label_map <- list(
  AGEGR9   = "Age Group 9",
  AGEGR9N  = "Age Group 9 (N)",
  ITTFL    = "Intent-to-Treat Population Flag",
  TRTSDTM  = "Datetime of First Exposure to Treatment",
  TRTSTMF  = "Start Date/Time of Treatment Imputation Flag",
  ABNSBPFL = "Abnormal Supine Systolic BP Flag",
  CARPOPFL = "Cardiac Adverse Event Population Flag",
  LSTALVDT = "Last Known Alive Date"
)

for (var in names(label_map)) {
  if (var %in% names(adsl)) {
    attr(adsl[[var]], "label") <- label_map[[var]]
  }
}

cat("Variable labels applied to all derived variables.\n")

# 12. Persist the result ------------------------------------------------------
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
readr::write_csv(adsl, file.path(out_dir, "adsl.csv"))
saveRDS(adsl, file.path(out_dir, "adsl.rds"))
cat("\nOutput written to:", out_dir, "\n")

invisible(adsl)
