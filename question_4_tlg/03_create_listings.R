# ------------------------------------------------------------------------------
# Question 4.3 - Listing of Treatment-Emergent Adverse Events
#
# Description : Subject-level listing of all TEAEs containing Subject ID,
#               Treatment, AE Term, Severity, Causality, and Start/End dates.
#               Built with {gt} (the table engine that underlies {gtsummary})
#               because {gtsummary} is purpose-built for *summary* tables, not
#               row-level listings.
# Inputs      : pharmaverseadam::adae
# Output      : ae_listings.html
# ------------------------------------------------------------------------------

# 1. Setup ---------------------------------------------------------------------
suppressPackageStartupMessages({
  library(dplyr)
  library(gt)
  library(pharmaverseadam)
})

out_dir <- file.path(dirname(rstudioapi::getSourceEditorContext()$path), "output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

adae <- pharmaverseadam::adae

# 2. Prepare listing data ------------------------------------------------------
# Treatment-emergent only, sorted by subject and event start date as required.
# AESTDTC / AEENDTC are kept as the original ISO 8601 character dates so the
# listing matches the SDTM/ADaM convention.
listing_df <- adae %>%
  filter(TRTEMFL == "Y") %>%
  arrange(USUBJID, AESTDTC) %>%
  select(
    USUBJID,
    ACTARM,
    AETERM,
    AESEV,
    AEREL,
    AESTDTC,
    AEENDTC
  ) %>%
  mutate(across(everything(), ~ tidyr::replace_na(as.character(.x), "NA")))

# 3. Build the listing with {gt} ----------------------------------------------
listing_table <- listing_df %>%
  gt(groupname_col = "USUBJID") %>%
  tab_header(
    title    = "Listing of Treatment-Emergent Adverse Events by Subject",
    subtitle = "Excluding Screen Failure Patients"
  ) %>%
  cols_label(
    ACTARM  = "Description of Actual Arm",
    AETERM  = "Reported Term for the Adverse Event",
    AESEV   = "Severity/Intensity",
    AEREL   = "Causality",
    AESTDTC = "Start Date/Time of Adverse Event",
    AEENDTC = "End Date/Time of Adverse Event"
  ) %>%
  tab_options(
    table.width       = px(1400),
    table.font.size   = px(12),
    row_group.font.weight = "bold"
  ) %>%
  cols_width(
    # Divide the total table width equally across all display columns.
    # listing_df has 7 columns but USUBJID is the row group (stub), so
    # the remaining 6 columns each get an equal share automatically.
    everything() ~ px(floor(1400 / (ncol(listing_df) - 1)))
  ) %>%
  tab_stubhead(label = "Unique Subject Identifier") %>%
  cols_align(align = "left", columns = c(AESTDTC, AEENDTC))

# 4. Export --------------------------------------------------------------------
out_path <- file.path(out_dir, "ae_listings.html")
gtsave(listing_table, filename = out_path)

message("Saved: ", normalizePath(out_path, mustWork = FALSE))
