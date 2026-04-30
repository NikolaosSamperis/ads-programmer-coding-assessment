# =============================================================================
# Question 2 -- SDTM DS (Disposition) Domain Creation using {sdtm.oak}
# -----------------------------------------------------------------------------
# Author      : Nikolaos Samperis
# Description : Transforms the raw subject-disposition dataset
#               `pharmaverseraw::ds_raw` into the SDTM Disposition (DS) domain
#               following SDTMIG v3.4 and using the {sdtm.oak} mapping engine.
#               Controlled terminology mappings are read from `sdtm_ct.csv`
#               (codelists C66727 / NCOMPLT, VISIT, VISITNUM).
#
# Mapping is driven by the annotated CRF:
#   pharmaverseraw / vignettes / articles / aCRFs / Subject_Disposition_aCRF.pdf
#
# eCRF fields collected per disposition record:
#   1. Date subject completed/discontinued (MM-DD-YYYY)   -> DSSTDTC
#   2. Reason for completion/discontinuation (radio btn)  -> DSDECOD + DSCAT
#         options: Randomized | Completed | Adverse Event |
#                  Study terminated by sponsor | Screen Failure | Death |
#                  Withdrawal by Subject | Physician Decision |
#                  Protocol Violation | Lost to Follow-Up | Lack of Efficacy
#   3. "...something else, please specify"                -> not used here
#   4. Reported term for Disposition Event (free text)    -> DSTERM
#   5. Date & Time of Collection                          -> DSDTC
#
# Raw -> SDTM column mapping (verified from glimpse(ds_raw) on 30-Apr-2026):
#   patient id ............... PATNUM       -> USUBJID (aligned via DM)
#   study id ................. STUDY        -> STUDYID
#   visit name ............... INSTANCE     -> VISIT (uppercased) + VISITNUM
#   verbatim term (free txt) . IT.DSTERM    -> DSTERM
#   reason (radio button) .... IT.DSDECOD   -> DSDECOD + DSCAT
#   event start date ......... IT.DSSTDAT   -> DSSTDTC
#   collection date .......... DSDTCOL      -> DSDTC (combined with DSTMCOL)
#   collection time .......... DSTMCOL      -> DSDTC (combined with DSDTCOL)
#   "specify other" .......... OTHERSP      -> not used
#
# Output      : An SDTM-compliant `ds` data frame with the variables required
#               by the assessment:
#                 STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
#                 VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY
#
# References  : - SDTMIG v3.4 (CDISC) -- DS domain
#               - {sdtm.oak} docs ..... https://pharmaverse.github.io/sdtm.oak/
#               - {sdtm.oak} AE example (the assignment's hint pattern)
# =============================================================================


# 0. Setup --------------------------------------------------------------------
# install.packages(c("admiral", "sdtm.oak", "pharmaverseraw",
#                    "pharmaversesdtm", "dplyr", "readr", "diffdf"))

suppressPackageStartupMessages({
  library(sdtm.oak)         # SDTM transformation engine
  library(pharmaverseraw)   # provides ds_raw
  library(pharmaversesdtm)  # provides dm (needed for RFSTDTC -> DSSTDY)
  library(dplyr)
  library(readr)
})

# Output directory -- inside question_2_sdtm/
out_dir <- file.path("output")


# 1. Load the controlled-terminology spec -------------------------------------
# `study_ct` holds the codelist mappings used by `assign_ct()`. Three
# codelists are consumed in this script:
#   - C66727 (NCOMPLT) -> DSDECOD for disposition events
#   - VISIT            -> uppercase VISIT label (e.g. "Baseline" -> "BASELINE")
#   - VISITNUM         -> numeric visit number (e.g. "Baseline" -> 3)
# "Randomized" is a PROTOCOL MILESTONE (not in C66727) -- hardcoded in step 7.

study_ct <- readr::read_csv(
  file.path("sdtm_ct.csv"),
  show_col_types = FALSE
)
stopifnot(all(c("C66727", "VISIT", "VISITNUM") %in% study_ct$codelist_code))


# 2. Load and filter the raw data ---------------------------------------------
# ds_raw has 850 rows total, but many are "empty" CRF entries where both
# IT.DSDECOD and IT.DSTERM are NA (forms opened but not completed in the EDC).
# Keeping these would produce 290 spurious all-NA rows in the output.
# We retain only rows that carry actual disposition information.

ds_raw <- pharmaverseraw::ds_raw %>%
  filter(!is.na(IT.DSDECOD) | !is.na(IT.DSTERM))

cat("=== ds_raw after filtering empty rows ===\n")
cat("Rows kept:", nrow(ds_raw), "(from 850 total)\n\n")
dplyr::glimpse(ds_raw)

# Pull the single study ID for STUDYID / USUBJID construction downstream.
study_id_value <- unique(ds_raw$STUDY)
stopifnot(length(study_id_value) == 1L)


# 3. Generate oak_id_vars -----------------------------------------------------
# Adds `oak_id`, `raw_source`, and `patient_number` so every assign_*() /
# hardcode_*() call merges back onto the correct row identity.

ds_raw <- ds_raw %>%
  generate_oak_id_vars(
    pat_var = "PATNUM",
    raw_src = "ds_raw"
  )


# 4. Align collected values with the CT file ----------------------------------
# Raw radio-button labels differ slightly from study_ct$collected_value, and
# one INSTANCE value uses different capitalisation than the VISIT/VISITNUM
# codelists ("Ambul Ecg Removal" vs CT's "Ambul ECG Removal"). Normalising
# both up front keeps the downstream assign_ct() lookups exact-match clean.

ds_raw <- ds_raw %>%
  mutate(
    # Disposition reason -- align with C66727 collected_value column
    DSDECOD_COLLECTED = case_when(
      IT.DSDECOD == "Completed"                   ~ "Complete",
      IT.DSDECOD == "Screen Failure"              ~ "Trial Screen Failure",
      IT.DSDECOD == "Study Terminated by Sponsor" ~ "Study Terminated By Sponsor",
      IT.DSDECOD == "Lost to Follow-Up"           ~ "Lost To Follow-Up",
      TRUE                                        ~ IT.DSDECOD
    ),
    # Visit label -- align with VISIT/VISITNUM collected_value column
    INSTANCE_COLLECTED = case_when(
      INSTANCE == "Ambul Ecg Removal" ~ "Ambul ECG Removal",
      TRUE                            ~ INSTANCE
    )
  )


# 5. Map the topic variable DSTERM (verbatim free text) -----------------------
# DSTERM is the "Reported term for Disposition Event" free-text field.
# It is the topic variable -- all qualifiers merge onto these rows.

ds <- assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "IT.DSTERM",
  tgt_var = "DSTERM",
  id_vars = oak_id_vars()
) %>%
  
  # 6. DSDECOD for DISPOSITION EVENTS (CT lookup against C66727) --------------
# Excludes "Randomized" rows (handled separately below).
# assign_ct() maps DSDECOD_COLLECTED -> term_value
# (e.g. "Adverse Event" -> "ADVERSE EVENT").
assign_ct(
  raw_dat = condition_add(ds_raw, IT.DSDECOD != "Randomized"),
  raw_var = "DSDECOD_COLLECTED",
  tgt_var = "DSDECOD",
  ct_spec = study_ct,
  ct_clst = "C66727",
  id_vars = oak_id_vars()
) %>%
  
  # 7. DSDECOD for the PROTOCOL MILESTONE "Randomized" ------------------------
# Hardcoded: RANDOMIZED belongs to PROTMLST, not NCOMPLT.
hardcode_no_ct(
  raw_dat = condition_add(ds_raw, IT.DSDECOD == "Randomized"),
  raw_var = "IT.DSDECOD",
  tgt_var = "DSDECOD",
  tgt_val = "RANDOMIZED",
  id_vars = oak_id_vars()
) %>%
  
  # 8. DSCAT (conditional on the reason) --------------------------------------
# "Randomized"  -> PROTOCOL MILESTONE
# anything else -> DISPOSITION EVENT
hardcode_no_ct(
  raw_dat = condition_add(ds_raw, IT.DSDECOD == "Randomized"),
  raw_var = "IT.DSDECOD",
  tgt_var = "DSCAT",
  tgt_val = "PROTOCOL MILESTONE",
  id_vars = oak_id_vars()
) %>%
  hardcode_no_ct(
    raw_dat = condition_add(ds_raw, IT.DSDECOD != "Randomized"),
    raw_var = "IT.DSDECOD",
    tgt_var = "DSCAT",
    tgt_val = "DISPOSITION EVENT",
    id_vars = oak_id_vars()
  ) %>%
  
  # 9. Disposition-event start date (DSSTDTC) ---------------------------------
# CRF format MM-DD-YYYY -> ISO 8601 date.
assign_datetime(
  raw_dat = ds_raw,
  raw_var = "IT.DSSTDAT",
  tgt_var = "DSSTDTC",
  raw_fmt = "m-d-y",
  id_vars = oak_id_vars()
) %>%
  
  # 10. Collection date/time (DSDTC) ------------------------------------------
# Date (DSDTCOL, MM-DD-YYYY) and time (DSTMCOL, HH:MM) are separate columns.
# assign_datetime() handles missing time gracefully, producing a date-only
# ISO 8601 string when DSTMCOL is NA.
assign_datetime(
  raw_dat = ds_raw,
  raw_var = c("DSDTCOL", "DSTMCOL"),
  tgt_var = "DSDTC",
  raw_fmt = c("m-d-y", "H:M"),
  id_vars = oak_id_vars()
) %>%
  
  # 11. Visit number (VISITNUM) -- CT lookup against VISITNUM codelist --------
# Maps the visit label ("Baseline", "Week 26", ...) to its sponsor-defined
# numeric value via the VISITNUM codelist in sdtm_ct.csv. The CT returns
# term_value as character, so VISITNUM is coerced to numeric in step 13.
assign_ct(
  raw_dat = ds_raw,
  raw_var = "INSTANCE_COLLECTED",
  tgt_var = "VISITNUM",
  ct_spec = study_ct,
  ct_clst = "VISITNUM",
  id_vars = oak_id_vars()
) %>%
  
  # 12. Visit name (VISIT) ----------------------------------------------------
# VISIT comes from the form-level visit context (INSTANCE column) that the
# EDC stamps onto every row. Uppercased in step 13 to follow SDTM convention.
assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "INSTANCE",
  tgt_var = "VISIT",
  id_vars = oak_id_vars()
)


# 13. Add identifier variables and finalise VISIT/VISITNUM types --------------
# A temporary USUBJID is built here to keep the row identity intact; it is
# overwritten with DM.USUBJID in step 15 once the patient_number join lands.

ds <- ds %>%
  mutate(
    STUDYID  = study_id_value,
    DOMAIN   = "DS",
    USUBJID  = paste(study_id_value, patient_number, sep = "-"),
    VISIT    = toupper(VISIT),         # SDTM convention: uppercase
    VISITNUM = as.numeric(VISITNUM)    # CT returns character; coerce to numeric
  )


# 14. Derive DSSEQ ------------------------------------------------------------
# Sequence number per subject, ordered chronologically.

ds <- ds %>%
  arrange(USUBJID, DSSTDTC, DSDTC) %>%
  group_by(USUBJID) %>%
  mutate(DSSEQ = row_number()) %>%
  ungroup()


# 15. Align USUBJID with DM and derive DSSTDY (study day) ---------------------
# DSSTDY is derived by comparing the disposition start date (DSSTDTC)
# with the subject-level reference start date (RFSTDTC) from the DM domain.
#
# The raw DS data identifies subjects by patient number. patient_number is
# therefore used to join DS with DM, and the official DM.USUBJID is retained
# in the final SDTM DS domain. The site-prefix strip below uses a generic
# pattern (^[^-]+-) rather than a hardcoded "01-" so the join works for any
# study, not just CDISCPILOT01.
#
# SDTM study day rule -- no Day 0:
#   DSSTDTC >= RFSTDTC  ->  DSSTDY = (DSSTDTC - RFSTDTC) + 1
#   DSSTDTC <  RFSTDTC  ->  DSSTDY = (DSSTDTC - RFSTDTC)
#
# DSSTDY remains NA for subjects with no RFSTDTC in DM (e.g. screen failures
# who were never randomized and therefore have no reference start date).
#
# The calculation is implemented manually with dplyr rather than
# admiral::derive_vars_dy() to avoid an unnecessary cross-package dependency
# and to handle date-type coercion explicitly inline.

dm_ref <- pharmaversesdtm::dm %>%
  select(STUDYID, USUBJID, RFSTDTC) %>%
  mutate(
    patient_number = sub("^[^-]+-", "", USUBJID),
    RFSTDTC_DATE   = as.Date(substr(as.character(RFSTDTC), 1, 10))
  )

ds <- ds %>%
  mutate(
    DSSTDTC_DATE = as.Date(substr(as.character(DSSTDTC), 1, 10))
  ) %>%
  left_join(
    dm_ref %>% select(patient_number, DM_USUBJID = USUBJID, RFSTDTC_DATE),
    by = "patient_number"
  ) %>%
  mutate(
    USUBJID = DM_USUBJID,
    DSSTDY = case_when(
      is.na(DSSTDTC_DATE) | is.na(RFSTDTC_DATE) ~ NA_integer_,
      DSSTDTC_DATE >= RFSTDTC_DATE ~ as.integer(DSSTDTC_DATE - RFSTDTC_DATE) + 1L,
      TRUE                         ~ as.integer(DSSTDTC_DATE - RFSTDTC_DATE)
    )
  ) %>%
  select(-DSSTDTC_DATE, -RFSTDTC_DATE, -DM_USUBJID)


# 16. Final ordering ----------------------------------------------------------
# Keep exactly the variables required by the assessment, in SDTM order.

ds <- ds %>%
  select(
    STUDYID, DOMAIN, USUBJID, DSSEQ,
    DSTERM, DSDECOD, DSCAT,
    VISITNUM, VISIT,
    DSDTC, DSSTDTC, DSSTDY
  ) %>%
  arrange(USUBJID, DSSEQ)


# 17. Remove inherited variable labels ----------------------------------------
# USUBJID inherits a variable label from the DM domain after the join.
# The remaining DS variables are created manually and do not have labels.
# Labels are removed before export to keep the output dataset consistent.

ds <- ds %>%
  mutate(across(everything(), ~ {
    attr(.x, "label") <- NULL
    .x
  }))


# 18. Validation --------------------------------------------------------------
# Programmatic checks for the invariants this script must satisfy. Hard
# invariants are enforced with stopifnot() so the script fails loudly if any
# assumption breaks; soft summaries (distributions, NA counts) are printed
# for visual review. Where {pharmaversesdtm} ships a reference DS dataset,
# {diffdf} is used to surface any row-level differences against it.

cat("\n=== Validation: hard invariants ===\n")

# 18.1 Required variables present, in the assessment-mandated order
required_vars <- c("STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM",
                   "DSDECOD", "DSCAT", "VISITNUM", "VISIT", "DSDTC",
                   "DSSTDTC", "DSSTDY")
stopifnot(identical(names(ds), required_vars))

# 18.2 DOMAIN is always "DS"
stopifnot(all(ds$DOMAIN == "DS"))

# 18.3 DSDECOD values are restricted to NCOMPLT terms + RANDOMIZED milestone
allowed_dsdecod <- c(
  study_ct$term_value[study_ct$codelist_code == "C66727"],
  "RANDOMIZED"
)
stopifnot(all(ds$DSDECOD %in% allowed_dsdecod))

# 18.4 DSCAT vs DSDECOD is consistent
#      "RANDOMIZED" <=> "PROTOCOL MILESTONE", everything else <=> "DISPOSITION EVENT"
stopifnot(all(
  (ds$DSDECOD == "RANDOMIZED" & ds$DSCAT == "PROTOCOL MILESTONE") |
    (ds$DSDECOD != "RANDOMIZED" & ds$DSCAT == "DISPOSITION EVENT")
))

# 18.5 SDTM no-Day-0 rule for DSSTDY
stopifnot(!any(ds$DSSTDY == 0L, na.rm = TRUE))

# 18.6 DSSEQ is unique within USUBJID and starts at 1
seq_check <- ds %>%
  group_by(USUBJID) %>%
  summarise(
    n_dups = sum(duplicated(DSSEQ)),
    starts_at_one = min(DSSEQ) == 1L,
    .groups = "drop"
  )
stopifnot(all(seq_check$n_dups == 0L))
stopifnot(all(seq_check$starts_at_one))

# 18.7 Every USUBJID in DS exists in DM
stopifnot(all(ds$USUBJID %in% pharmaversesdtm::dm$USUBJID))

cat("All hard invariants passed.\n")


cat("\n=== Validation: soft summaries ===\n")
cat("Rows           :", nrow(ds), "\n")
cat("Unique subjects:", dplyr::n_distinct(ds$USUBJID), "\n\n")

cat("DSCAT x DSDECOD distribution:\n")
print(dplyr::count(ds, DSCAT, DSDECOD, sort = TRUE))

cat("\nVISIT x VISITNUM distribution:\n")
print(dplyr::count(ds, VISITNUM, VISIT, sort = TRUE))

cat("\nNA counts per required variable:\n")
print(colSums(is.na(ds)))

cat("\nDSSTDY range (excluding NA):\n")
print(summary(ds$DSSTDY))


# 18.8 Optional reference comparison against pharmaversesdtm::ds --------------
# {pharmaversesdtm} ships a reference SDTM DS dataset built from the same
# study source. Comparing against it surfaces any unexpected differences.
# Variables not in the assessment scope are excluded from the comparison.

if (requireNamespace("diffdf", quietly = TRUE)) {
  ref_ds <- pharmaversesdtm::ds %>%
    select(any_of(required_vars)) %>%
    arrange(USUBJID, DSSEQ)
  
  compare_ds <- ds %>%
    select(any_of(intersect(required_vars, names(ref_ds)))) %>%
    arrange(USUBJID, DSSEQ)
  
  cat("\n=== Validation: diffdf vs pharmaversesdtm::ds ===\n")
  cat("Variables compared:", paste(names(compare_ds), collapse = ", "), "\n")
  diff_result <- try(
    diffdf::diffdf(
      base    = ref_ds %>% select(all_of(names(compare_ds))),
      compare = compare_ds,
      keys    = c("USUBJID", "DSSEQ"),
      suppress_warnings = TRUE
    ),
    silent = TRUE
  )
  if (inherits(diff_result, "try-error")) {
    cat("diffdf comparison could not be completed -- skipping.\n")
  } else {
    print(diff_result)
  }
} else {
  cat("\n{diffdf} not installed -- skipping reference comparison.\n")
  cat("Install with: install.packages(\"diffdf\")\n")
}


cat("\nFirst 10 records:\n")
print(utils::head(ds, 10))


# 19. Persist the result ------------------------------------------------------
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
readr::write_csv(ds, file.path(out_dir, "ds.csv"))
saveRDS(ds, file.path(out_dir, "ds.rds"))
cat("\nOutput written to:", out_dir, "\n")

invisible(ds)