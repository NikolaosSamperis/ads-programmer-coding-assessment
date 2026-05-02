# Question 3 — ADaM ADSL Dataset Creation

![R](https://img.shields.io/badge/R-%3E%3D4.2.0-276DC3?logo=r)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/NikolaosSamperis/ads-programmer-coding-assessment/blob/main/LICENSE)
![Pharmaverse](https://img.shields.io/badge/Pharmaverse-admiral-blue)

This folder builds the **ADaM ADSL (Subject Level Analysis Dataset)** from
SDTM source domains using the **{admiral}** family of packages plus
tidyverse tools.

## Files

| File | Purpose |
|---|---|
| `create_adsl.R`     | Main script — run this to produce the ADSL dataset |
| `output/adsl.csv`   | Generated ADSL dataset (created on first run) |
| `output/adsl.rds`   | Same dataset as a binary `.rds` for downstream use |

## What ADSL is

ADSL is the one-row-per-subject backbone of every analysis dataset family.
It carries demography, treatment dates, population flags, and disposition
information needed by every TLG and every analysis dataset (ADAE, ADVS,
ADLB, …). Required by the FDA in any submission package using ADaM.

## Inputs

All five SDTM domains come from `{pharmaversesdtm}`:

| Domain | Used for |
|---|---|
| `dm` | ADSL base — demography, ARM, RFSTDTC, etc. |
| `ex` | TRTSDTM derivation; one of the LSTALVDT sources |
| `vs` | ABNSBPFL flag; one of the LSTALVDT sources |
| `ds` | One of the LSTALVDT sources |
| `ae` | CARPOPFL flag; one of the LSTALVDT sources |

> The DS domain produced in Question 2 could be substituted here, but the
> assessment explicitly names `pharmaversesdtm::ds` as the input. Using the
> packaged DS keeps Q3 self-contained and independent of Q2.

## Derivations

Six variables are derived on top of the DM-based starting point.

### `AGEGR9` / `AGEGR9N`
Custom age categories: `"<18"`, `"18 - 50"`, `">50"`, mapped to numeric
`1`, `2`, `3` respectively. Implemented with `case_when()` since admiral
has no built-in helper for these specific cutoffs.

### `TRTSDTM` / `TRTSTMF`
First valid-dose exposure datetime. Built in two steps:

1. `derive_vars_dtm()` on `EX.EXSTDTC` with
   `time_imputation = "00:00:00"`, `highest_imputation = "h"`, and
   `ignore_seconds_flag = TRUE`. The combination matches the spec:
   completely missing time is imputed to midnight, partially missing
   components are imputed to `00`, and seconds-only imputation does not set
   `TRTSTMF`.
2. `derive_vars_merged()` to pull the first record per subject into ADSL,
   filtered to `EXDOSE > 0` or `EXDOSE == 0 & EXTRT contains "PLACEBO"`.

### `ITTFL`
Per the spec literally, `"Y"` if `DM.ARM` is not missing, else `"N"`.

> **Note:** in `pharmaversesdtm::dm`, screen-failure subjects have
> `ARM = "Screen Failure"` (not NA), so the literal rule classifies them as
> ITT. The script preserves the literal spec; the stricter
> `ARM != "Screen Failure"` alternative used in the admiral ADSL example is
> shown commented out for reviewers who prefer it.

### `ABNSBPFL`
`"Y"` if the subject has any VS observation with `VSTESTCD == "SYSBP"`,
`VSSTRESU == "mmHg"`, and `VSSTRESN < 100` or `>= 140`. Else `"N"`.
Implemented with `derive_var_merged_exist_flag()`.

> **Spec ambiguity — position filter:** the assessment *summary* describes
> this as a supine systolic BP flag, which would imply filtering to
> `VSPOS == "SUPINE"`. However, the *detailed derivation spec* contains no
> `VSPOS` condition at all. Where a summary and a detailed spec conflict, the
> detailed spec takes precedence. The script therefore follows the detailed
> spec and applies no position filter.
>
> **Effect on the output:** without a position filter, 233/306 subjects
> (76%) receive `ABNSBPFL = "Y"`. This rate is clinically plausible for the
> CDISCPILOT01 population — elderly patients with Alzheimer's disease, among
> whom hypertension is prevalent. Adding `VSPOS == "SUPINE"` would reduce
> this rate noticeably and can be enabled in one line if the reviewer
> prefers the supine-only interpretation.

### `CARPOPFL`
`"Y"` if the subject has any AE with `AESOC == "CARDIAC DISORDERS"`
(case-insensitive), else `NA`. Spec is Y/NA, **not** Y/N — so admiral's
default `false_value = NA` and `missing_value = NA` are kept.

### `LSTALVDT`
Last known alive date — the maximum of:

1. VS visit dates with a valid result (`VSSTRESN` and `VSSTRESC` not both NA)
2. AE start dates
3. Disposition start dates
4. Exposure start and end dates restricted to valid-dose records

Each contributing source is wrapped in an `event()` and passed to
`derive_vars_extreme_event(mode = "last")` — the modern admiral 1.2.0+
API that replaces the deprecated `date_source()` / `derive_var_extreme_dt()`
pair. EXSTDT is included alongside EXENDT so subjects whose `EXENDTC` is
missing still contribute via the start date.

> **Expected duplicate warning:** `derive_vars_extreme_event()` emits a
> warning about duplicate records with respect to `STUDYID`, `USUBJID`, and
> `LSTALVDT`. Inspecting `admiral::get_duplicates_dataset()` confirms these
> are all VS-source rows where multiple vital signs observations (e.g. systolic
> BP, diastolic BP, heart rate) share the same visit date, producing identical
> `LSTALVDT` candidates for the same subject on the same day. This is expected
> behaviour for a multi-test vital signs dataset. The warning is benign —
> `mode = "last"` correctly resolves ties and the derived `LSTALVDT` values
> are accurate.

## Validation

The script ends with a validation block that checks every derivation
programmatically rather than relying on a visual sanity check.

**Hard invariants — enforced with `stopifnot()`:**

- All required derived variables are present.
- One row per subject (`nrow == n_distinct(USUBJID)`).
- `AGEGR9` is restricted to the three allowed levels (or NA).
- `AGEGR9 ↔ AGEGR9N` mapping is consistent.
- `AGEGR9` matches `AGE` per the spec cutoffs.
- `ITTFL` and `ABNSBPFL` are `"Y"` / `"N"` only.
- `CARPOPFL` is `"Y"` or NA only (per spec, never `"N"`).
- `ITTFL` is consistent with `ARM` presence (the literal rule).
- `LSTALVDT` is `Date` and `TRTSDTM` is `POSIXct`.

**Soft summaries — printed for visual review:**

- Subject count.
- `AGEGR9 / AGEGR9N` distribution.
- `ITTFL` by `ARM`.
- `ABNSBPFL` distribution.
- `CARPOPFL` distribution (with NA bucket).
- `TRTSTMF` distribution (with NA bucket — NA means "not imputed").
- `LSTALVDT` range via `summary()`.
- First 10 records with key derived variables.

## How to run

```r
# from the repo root (or with question_3_adam/ as working dir)
source("question_3_adam/create_adsl.R")
```

The script prints the validation block, writes `output/adsl.csv` and
`output/adsl.rds`, and returns the ADSL data frame invisibly.
