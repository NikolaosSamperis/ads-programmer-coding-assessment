# Question 2 — SDTM DS Domain Creation

![R](https://img.shields.io/badge/R-%3E%3D4.2.0-276DC3?logo=r&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Pharmaverse](https://img.shields.io/badge/Pharmaverse-sdtm.oak-blue)

This folder builds the **SDTM Disposition (DS)** domain from
`pharmaverseraw::ds_raw` using the **{sdtm.oak}** transformation engine.

## Files

| File | Purpose |
|---|---|
| `02_create_ds_domain.R` | Main script — run this to produce the DS domain |
| `sdtm_ct.csv`           | Study controlled terminology spec (codelist C66727 = NCOMPLT) |
| `output/ds.csv`         | Generated SDTM DS domain (created on first run) |
| `output/ds.rds`         | Same dataset as a binary `.rds` for the ADaM step (Q3) |

## What the DS domain is

DS captures **what happened to every subject in the trial** — every protocol
milestone (Informed Consent, Randomization) and every disposition event
(Completed, Adverse Event, Death, Lost to Follow-Up, Screen Failure, …).
Required by the FDA for subject accounting; consumed by ADaM ADSL to derive
end-of-study date, discontinuation reason, death info, and population flags.

## eCRF → SDTM mapping

The Subject Disposition aCRF collects five items per record:

| eCRF field | Likely raw column | SDTM target |
|---|---|---|
| Date subject completed/discontinued (`MM-DD-YYYY`) | `DSSTDAT` | `DSSTDTC` |
| Reason for completion/discontinuation (radio) | `DSDECOD` | `DSDECOD` + `DSCAT` |
| "Something else, please specify" (free text) | `DSREASOTH` | not used here |
| Reported term for Disposition Event (free text) | `DSTERM` | `DSTERM` |
| Date & Time of Collection | `DSDTC` | `DSDTC` |

Two subtleties driven by the radio-button options:

1. **`DSTERM` and `DSDECOD` come from different fields.** The radio button
   drives `DSDECOD`; the separate free-text "Reported term" box drives
   `DSTERM`.
2. **`DSCAT` and `DSDECOD` are conditional on the value.** "Randomized" is a
   *protocol milestone* (codelist C66728 / PROTMLST), everything else is a
   *disposition event* (codelist C66727 / NCOMPLT). The script therefore:
   - hardcodes `DSDECOD = "RANDOMIZED"` and `DSCAT = "PROTOCOL MILESTONE"`
     when the radio = "Randomized";
   - uses `assign_ct()` against C66727 and `DSCAT = "DISPOSITION EVENT"`
     for everything else.

`VISITNUM` and `VISIT` are not on the eCRF itself — they come from the
form-level visit context the EDC stamps onto each row.

## Output variables (per the assessment)

`STUDYID`, `DOMAIN`, `USUBJID`, `DSSEQ`, `DSTERM`, `DSDECOD`, `DSCAT`,
`VISITNUM`, `VISIT`, `DSDTC`, `DSSTDTC`, `DSSTDY`.

## Mapping approach (in order)

1. `generate_oak_id_vars()` — adds `oak_id`/`raw_source`/`patient_number` so
   every later mapping merges back onto the same row identity.
2. **Topic** — `DSTERM` via `assign_no_ct()` from the free-text "Reported
   term" box.
3. **`DSDECOD` / `DSCAT` for disposition events** — `assign_ct()` against
   codelist C66727, conditioned on the radio value being ≠ "Randomized";
   then `hardcode_no_ct()` for `DSCAT = "DISPOSITION EVENT"`.
4. **`DSDECOD` / `DSCAT` for the Randomized milestone** — both hardcoded
   (`"RANDOMIZED"` and `"PROTOCOL MILESTONE"`) when the radio = "Randomized".

> Note: "Randomized" is not part of the provided C66727 NCOMPLT terminology,
> so `sdtm.oak` may report it as unmapped. This is expected because the script
> handles it separately as a protocol milestone with `DSDECOD = "RANDOMIZED"`
> and `DSCAT = "PROTOCOL MILESTONE"`.

5. **Dates** — `DSSTDTC` and `DSDTC` via `assign_datetime()` (CRF format
   `MM-DD-YYYY`).
6. **Visit** — `VISITNUM` / `VISIT` via `assign_no_ct()`.
7. **Identifiers** — `STUDYID` and `DOMAIN = "DS"` are assigned directly.
   `USUBJID` is aligned with `DM.USUBJID` through the raw patient number.
8. **`DSSEQ`** — row-number per subject ordered chronologically.
9. **`DSSTDY`** — derived manually from DSSTDTC and DM.RFSTDTC after aligning subjects
   through the raw patient number. The SDTM no-Day-0 rule is applied.


## Before running — verify raw column names

`pharmaverseraw::ds_raw` is intentionally EDC-/CDASH-agnostic, so its column
names may not exactly match the CDASH-style guesses above. Block 2 of the
script prints `glimpse(ds_raw)` — run it once and update the `raw_var`/`pat_var`
strings if anything differs.

## How to run

```r
# from the repo root (or with question_2_sdtm/ as working dir)
source("question_2_sdtm/02_create_ds_domain.R")
```

The script prints a summary, writes `output/ds.csv` and `output/ds.rds`,
and returns the DS data frame invisibly.
