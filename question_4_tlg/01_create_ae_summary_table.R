# ------------------------------------------------------------------------------
# Question 4.1 - Summary Table of Treatment-Emergent Adverse Events (TEAEs)
#
# Description : Builds an FDA Table 10 style hierarchical summary of TEAEs using
#               {gtsummary}. Rows are AESOC with AETERM nested below; columns
#               are treatment arms (ACTARM) with N from ADSL as denominators.
# Inputs      : pharmaverseadam::adae, pharmaverseadam::adsl
# Output      : ae_summary_table.html
# ------------------------------------------------------------------------------

# 1. Setup ---------------------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(gtsummary)
  library(gt)
  library(pharmaverseadam)
})

# Output directory: created relative to this script's location so outputs land
# in question_4_tlg/output/ regardless of the working directory.
out_dir <- file.path(dirname(rstudioapi::getSourceEditorContext()$path), "output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)


# Compact display theme: tighter spacing and smaller font in the output table.
theme_gtsummary_compact()

# 2. Load and prepare data -----------------------------------------------------
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# ADSL is the denominator population: every treated subject contributes to
# the column N, even those with no AE record. Screen Failure subjects are
# excluded as they were never treated. Keeping ACTARM as a factor with
# the same levels in both datasets guarantees aligned columns.
arm_levels <- sort(unique(adsl$ACTARM[adsl$ACTARM != "Screen Failure"]))

adsl_pop <- adsl %>%
  filter(ACTARM != "Screen Failure") %>%
  mutate(ACTARM = factor(ACTARM, levels = arm_levels)) %>%
  select(USUBJID, ACTARM)

# Treatment-emergent AE records only, restricted to the columns we need.
teae <- adae %>%
  filter(TRTEMFL == "Y", ACTARM != "Screen Failure") %>%
  mutate(ACTARM = factor(ACTARM, levels = arm_levels)) %>%
  select(USUBJID, ACTARM, AESOC, AETERM)

# 3. Build the hierarchical summary table --------------------------------------
# tbl_hierarchical() (gtsummary >= 2.0) summarises subject-level event counts
# across nested categorical variables. The `denominator` argument injects the
# full ADSL population so column Ns reflect randomised subjects, not just
# subjects with AEs.
ae_table <- teae %>%
  tbl_hierarchical(
    variables   = c(AESOC, AETERM),
    by          = ACTARM,
    id          = USUBJID,
    denominator = adsl_pop,
    overall_row = TRUE
  ) %>%
  # Rename the default overall row label to match the sample output.
  # modify_table_body() is used for compatibility with older gtsummary versions
  # that do not support the overall_row_label argument.
  modify_table_body(
    ~ .x %>%
      mutate(label = ifelse(label == "Number of patients with event",
                            "Treatment Emergent AEs", label))
  ) %>%
  bold_labels() %>%
  modify_header(
    label = "**Primary System Organ Class**<br>&nbsp;&nbsp;**Reported Term for the Adverse Event**"
  ) %>%
  modify_caption("**Table 10. Treatment-Emergent Adverse Events
                 by System Organ Class and Preferred Term**") %>%
  modify_footnote(all_stat_cols() ~ "n = number of subjects with event;
                  % = percentage of treated subjects in that arm")

# 4. Export as HTML ------------------------------------------------------------
out_path <- file.path(out_dir, "ae_summary_table.html")

ae_table %>%
  as_gt() %>%
  gt::gtsave(filename = out_path)

message("Saved: ", normalizePath(out_path, mustWork = FALSE))
