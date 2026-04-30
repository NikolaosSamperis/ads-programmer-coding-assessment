# =============================================================================
# Question 2 -- SDTM DS (Disposition) Domain Creation using {sdtm.oak}
# -----------------------------------------------------------------------------
# Author      : Nikolaos Samperis
# Description : Transforms the raw subject-disposition dataset
#               `pharmaverseraw::ds_raw` into the SDTM Disposition (DS) domain
#               following SDTMIG v3.4 and using the {sdtm.oak} mapping engine.
#               Controlled terminology mappings are read from `sdtm_ct.csv`
#               (codelist C66727 / NCOMPLT).
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
#   patient id ............... PATNUM       -> USUBJID (with STUDY prefix)
#   study id ................. STUDY        -> STUDYID
#   visit name ............... INSTANCE     -> VISIT
#   verbatim term (free txt) . IT.DSTERM    -> DSTERM
#   reason (radio button) .... IT.DSDECOD   -> DSDECOD + DSCAT
#   event start date ......... IT.DSSTDAT   -> DSSTDTC
#   collection date .......... DSDTCOL      -> DSDTC (combined with DSTMCOL)
#   collection time .......... DSTMCOL      -> DSDTC (combined with DSDTCOL)
#   "specify other" .......... OTHERSP      -> not used
#   (no VISITNUM in raw data)               -> NA
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
#                    "pharmaversesdtm", "dplyr", "readr"))

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
# `study_ct` holds the codelist mappings used by `assign_ct()`.
# Codelist C66727 (NCOMPLT) covers completion/discontinuation reasons.
# "Randomized" is a PROTOCOL MILESTONE (not in C66727) -- hardcoded in step 7.

study_ct <- readr::read_csv(
  file.path("sdtm_ct.csv"),
  show_col_types = FALSE
)
stopifnot("C66727" %in% study_ct$codelist_code)


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
# Raw radio-button labels differ slightly from study_ct$collected_value.
# A helper column DSDECOD_COLLECTED normalises them before assign_ct().

ds_raw <- ds_raw %>%
  mutate(
    DSDECOD_COLLECTED = case_when(
      IT.DSDECOD == "Completed"                   ~ "Complete",
      IT.DSDECOD == "Screen Failure"              ~ "Trial Screen Failure",
      IT.DSDECOD == "Study Terminated by Sponsor" ~ "Study Terminated By Sponsor",
      IT.DSDECOD == "Lost to Follow-Up"           ~ "Lost To Follow-Up",
      TRUE                                        ~ IT.DSDECOD
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
  
# 6. DSDECOD for DISPOSITION EVENTS (CT lookup against C66727) ----------------
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
  
# 7. DSDECOD for the PROTOCOL MILESTONE "Randomized" --------------------------
# Hardcoded: RANDOMIZED belongs to PROTMLST, not NCOMPLT.
hardcode_no_ct(
  raw_dat = condition_add(ds_raw, IT.DSDECOD == "Randomized"),
  raw_var = "IT.DSDECOD",
  tgt_var = "DSDECOD",
  tgt_val = "RANDOMIZED",
  id_vars = oak_id_vars()
) %>%
  
# 8. DSCAT (conditional on the reason) ----------------------------------------
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
  
# 9. Disposition-event start date (DSSTDTC) -----------------------------------
# CRF format MM-DD-YYYY -> ISO 8601 date.
assign_datetime(
  raw_dat = ds_raw,
  raw_var = "IT.DSSTDAT",
  tgt_var = "DSSTDTC",
  raw_fmt = "m-d-y",
  id_vars = oak_id_vars()
) %>%
  
# 10. Collection date/time (DSDTC) --------------------------------------------
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
  
# 11. Visit name (VISIT) ------------------------------------------------------
# VISIT comes from the form-level visit context (INSTANCE column) that the
# EDC stamps onto every row. VISITNUM is not present in ds_raw.
assign_no_ct(
  raw_dat = ds_raw,
  raw_var = "INSTANCE",
  tgt_var = "VISIT",
  id_vars = oak_id_vars()
)


# 12. Add identifier variables ------------------------------------------------
# USUBJID follows the pharmaversesdtm convention (STUDY-PATNUM) so the join
# to DM in step 14 resolves correctly.

ds <- ds %>%
  mutate(
    STUDYID  = study_id_value,
    DOMAIN   = "DS",
    USUBJID  = paste(study_id_value, patient_number, sep = "-"),
    VISITNUM = NA_real_          # not collected in ds_raw
  )


# 13. Derive DSSEQ ------------------------------------------------------------
# Sequence number per subject, ordered chronologically.

ds <- ds %>%
  arrange(USUBJID, DSSTDTC, DSDTC) %>%
  group_by(USUBJID) %>%
  mutate(DSSEQ = row_number()) %>%
  ungroup()


# 14. Derive DSSTDY (study day) -----------------------------------------------
# DSSTDY is derived by comparing the disposition start date (DSSTDTC)
# with the subject-level reference start date (RFSTDTC) from the DM domain.
#
# The raw DS data identifies subjects by patient number. Therefore,
# patient_number is used to join DS with DM, and the official DM.USUBJID
# is retained in the final SDTM DS domain.
#
# SDTM study day rule -- no Day 0:
#   DSSTDTC >= RFSTDTC  ->  DSSTDY = (DSSTDTC - RFSTDTC) + 1
#   DSSTDTC <  RFSTDTC  ->  DSSTDY = (DSSTDTC - RFSTDTC)
#
# The calculation is implemented manually with dplyr rather than
# derive_study_day() to avoid naming-convention warnings when the date and 
# study-day variable stems do not follow the expected pattern.

dm_ref <- pharmaversesdtm::dm %>%
  select(STUDYID, USUBJID, RFSTDTC) %>%
  mutate(
    patient_number = sub("^01-", "", USUBJID),
    RFSTDTC_DATE = as.Date(substr(as.character(RFSTDTC), 1, 10))
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
      DSSTDTC_DATE >= RFSTDTC_DATE ~ as.integer(DSSTDTC_DATE - RFSTDTC_DATE)
      + 1L, TRUE ~ as.integer(DSSTDTC_DATE - RFSTDTC_DATE)
    )
  ) %>%
  select(-DSSTDTC_DATE, -RFSTDTC_DATE, -DM_USUBJID)


# 15. Final ordering ----------------------------------------------------------
# Keep exactly the variables required by the assessment, in SDTM order.

ds <- ds %>%
  select(
    STUDYID, DOMAIN, USUBJID, DSSEQ,
    DSTERM, DSDECOD, DSCAT,
    VISITNUM, VISIT,
    DSDTC, DSSTDTC, DSSTDY
  ) %>%
  arrange

# 16. Remove inherited variable labels ----------------------------------------
# USUBJID inherits a variable label from the DM domain after the join.
# The remaining DS variables are created manually and do not have labels.
# Labels are removed before export to keep the output dataset consistent.

ds <- ds %>%
  mutate(across(everything(), ~ {
    attr(.x, "label") <- NULL
    .x
  }))



# 17. Quick QC ----------------------------------------------------------------
cat("\n=== DS domain summary ===\n")
cat("Rows           :", nrow(ds), "\n")
cat("Unique subjects:", dplyr::n_distinct(ds$USUBJID), "\n\n")

cat("DSCAT x DSDECOD distribution:\n")
print(dplyr::count(ds, DSCAT, DSDECOD, sort = TRUE))

cat("\nNA counts per required variable:\n")
print(colSums(is.na(ds)))

cat("\nFirst 10 records:\n")
print(utils::head(ds, 10))


# 18. Persist the result ------------------------------------------------------
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
readr::write_csv(ds, file.path(out_dir, "ds.csv"))
saveRDS(ds, file.path(out_dir, "ds.rds"))
cat("\nOutput written to:", out_dir, "\n")

invisible(ds)