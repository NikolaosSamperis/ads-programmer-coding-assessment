# Question 4 — TLG: Adverse Events Reporting

![R](https://img.shields.io/badge/R-%3E%3D4.2.0-276DC3?logo=r)
![License](https://img.shields.io/badge/License-MIT-green)
![Pharmaverse](https://img.shields.io/badge/Pharmaverse-admiral-blue)

This folder contains the three scripts requested for Question 4: a hierarchical TEAE summary table, two ggplot2 visualisations, and a subject-level AE listing.

## Folder contents

| File | Purpose | Output |
|------|---------|--------|
| `01_create_ae_summary_table.R` | FDA Table 10–style hierarchical summary of treatment-emergent AEs (AESOC › AETERM × ACTARM) | `output/ae_summary_table.html` |
| `02_create_visualizations.R` | Plot 1 — AE severity by treatment (stacked bar). Plot 2 — Top 10 most frequent AEs with 95% Clopper-Pearson CIs | `output/ae_severity_distribution.png`, `output/top10_ae_frequency.png` |
| `03_create_listings.R` | Subject-level listing of all TEAEs (subject, treatment, term, severity, causality, start/end dates) | `output/ae_listings.html` |

## Required packages

```r
install.packages(c(
  "dplyr", "tidyr", "forcats",
  "ggplot2",
  "gt", "gtsummary",
  "pharmaverseadam"
))
```

`gtsummary` must be **>= 2.0** for `tbl_hierarchical()`.

## How to run

Open each script in RStudio and click **Source** (not Source on Save). All output files are written automatically to the `output/` subdirectory, which is created if it does not exist.

```r
source("01_create_ae_summary_table.R")
source("02_create_visualizations.R")
source("03_create_listings.R")
```

## Design notes

- **Denominators come from ADSL, not ADAE.** The summary table feeds `pharmaverseadam::adsl` into `tbl_hierarchical(denominator = ...)` so the column N reflects all treated subjects per arm — including those with zero AEs — which is the FDA Table 10 convention. Screen Failure subjects are excluded as they were never treated.
- **TEAE filter.** Only records with `TRTEMFL == "Y"` are kept for the table and listing, per the question.
- **SOC sorting.** System Organ Classes are sorted by descending subject frequency by pre-ordering the `AESOC` factor levels before passing to `tbl_hierarchical()`, as the `sort` argument is only available in gtsummary >= 2.1.
- **Severity ordering.** AESEV is coerced to a factor with levels `MILD`, `MODERATE`, `SEVERE` so the legend, stacking order, and colours are stable even if a category is empty in a given run.
- **Confidence intervals.** Plot 2 uses `stats::binom.test()` for exact Clopper-Pearson 95% CIs, applied per AETERM with the ADSL subject count as the denominator.
- **Listing engine.** The question asks for `{gtsummary}`, but `gtsummary` is purpose-built for summary tables; row-level listings are the natural job of `{gt}` (which `gtsummary` itself sits on top of). The listing therefore uses `gt::gt()` with `USUBJID` as a row group, which produces output equivalent to the sample listing in the brief.

## Assumptions

- `pharmaverseadam` is installed and the `adae` / `adsl` datasets carry the standard ADaM variables (`USUBJID`, `ACTARM`, `AESOC`, `AETERM`, `AESEV`, `AEREL`, `AESTDTC`, `AEENDTC`, `TRTEMFL`).
- Scripts are sourced from within RStudio so that `rstudioapi::getSourceEditorContext()$path` correctly resolves the output directory path.

## Session info

| Package          | Version |
|------------------|---------|
| R                | 4.5.2   |
| admiral          | 1.4.1   |
| sdtm.oak         | 0.2.0   |
| gt               | 1.3.0   |
| gtsummary        | 2.5.0   |
| ggplot2          | 4.0.2   |
| dplyr            | 1.2.1   |
| tidyr            | 1.3.2   |
| forcats          | 1.0.1   |
| pharmaverseadam  | 1.3.0   |
| pharmaversesdtm  | 1.4.1   |
| pharmaverseraw   | 0.1.1   |
