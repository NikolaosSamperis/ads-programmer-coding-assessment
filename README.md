# ADS Programmer Coding Assessment

![R](https://img.shields.io/badge/R-%3E%3D4.2.0-276DC3?logo=r)
![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?logo=python&logoColor=white)
![Pharmaverse](https://img.shields.io/badge/Pharmaverse-admiral%20%7C%20sdtm.oak-blueviolet)
![FastAPI](https://img.shields.io/badge/FastAPI-0.110-009688?logo=fastapi&logoColor=white)
![LangChain](https://img.shields.io/badge/LangChain-1.2%2B-1C3C3C?logo=chainlink&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

This repository contains my submission for the **Senior ADS Programmer Coding Assessment**. The assessment evaluates skills across R package development, the Pharmaverse ecosystem (SDTM/ADaM), regulatory clinical reporting (TLGs), and Python for backend services and Generative AI. Each of the six questions is solved in a self-contained subfolder with its own scripts, outputs, and detailed README.

The assessment dataset is the CDISC pilot trial (CDISCPILOT01) of **Xanomeline vs. Placebo** in Alzheimer's disease, accessed through the open-source `{pharmaverseraw}`, `{pharmaversesdtm}`, and `{pharmaverseadam}` packages.

---

## Repository structure

```
.
├── question_1/
│   └── descriptive_stats/        # R package: descriptiveStats
├── question_2_sdtm/              # SDTM DS domain via {sdtm.oak}
├── question_3_adam/              # ADaM ADSL via {admiral}
├── question_4_tlg/               # AE TLGs via {gtsummary}, {gt}, {ggplot2}
├── question_5_api/               # Clinical Trial Data API (FastAPI)
├── question_6_genai/             # GenAI Clinical Data Assistant (LangChain + Claude)
├── .gitignore
├── LICENSE
└── README.md                     # this file
```

| Folder | Question | Stack | Description |
|---|---|---|---|
| `question_1/descriptive_stats/` | Q1 | R Package | A `descriptiveStats` R package implementing six summary-statistics functions with full Roxygen2 docs and 50 unit tests. |
| `question_2_sdtm/` | Q2 | R / `{sdtm.oak}` | Builds the SDTM **Disposition (DS)** domain from `pharmaverseraw::ds_raw` using the `{sdtm.oak}` transformation engine. |
| `question_3_adam/` | Q3 | R / `{admiral}` | Builds the ADaM **Subject-Level Analysis (ADSL)** dataset from SDTM domains using `{admiral}` plus tidyverse derivations. |
| `question_4_tlg/` | Q4 | R / `{gtsummary}` | Produces FDA-style **Tables, Listings & Graphs** for adverse events using `{gtsummary}`, `{gt}`, and `{ggplot2}`. |
| `question_5_api/` | Q5 | Python / FastAPI | A RESTful API exposing dynamic AE cohort filtering and a per-subject **Safety Risk Score**. |
| `question_6_genai/` | Q6 | Python / LangChain | A natural-language **Clinical Data Assistant** that translates free-text questions into Pandas queries via Claude. |

Each subfolder has its own README documenting setup, dependencies, design decisions, and how to run.

---

## Question 1 — `descriptiveStats` R Package

A lightweight R package with six descriptive statistics functions for numeric vectors: `calc_mean()`, `calc_median()`, `calc_mode()`, `calc_q1()`, `calc_q3()`, and `calc_iqr()`. The package follows the standard structure (`DESCRIPTION`, `NAMESPACE`, `R/`, `man/`, `tests/`), uses Roxygen2 for documentation, and ships with 50 `testthat` unit tests covering edge cases such as empty vectors, NAs, ties in mode calculation, and non-numeric input.

```r
devtools::install("question_1/descriptive_stats")
library(descriptiveStats)
devtools::test("question_1/descriptive_stats")
devtools::check("question_1/descriptive_stats")
```

---

## Question 2 — SDTM DS Domain Creation

Builds the SDTM **Disposition (DS)** domain — required by the FDA for subject accounting — from raw EDC data using the `{sdtm.oak}` controlled-terminology pipeline. The script handles the eCRF → SDTM mapping for protocol milestones (e.g. *Randomized*) versus disposition events (*Completed*, *Adverse Event*, *Death*, etc.), assigning the correct `DSCAT` and `DSDECOD` per CDISC codelists C66727 and C66728. A study-specific `sdtm_ct.csv` provides the controlled terminology, and the output is written to `output/ds.csv` and `output/ds.rds`.

```r
source("question_2_sdtm/02_create_ds_domain.R")
```

---

## Question 3 — ADaM ADSL Dataset Creation

Creates the one-row-per-subject **ADSL** dataset that anchors every analysis dataset family. Starting from `pharmaversesdtm::dm`, the script uses the `{admiral}` family of packages plus tidyverse tools to derive six required variables on top of DM:

- `AGEGR9` / `AGEGR9N` — age group categories (`<18`, `18–50`, `>50`).
- `TRTSDTM` / `TRTSTMF` — first valid-dose exposure datetime with imputation flag.
- `ITTFL` — Intent-To-Treat flag based on `ARM`.
- `ABNSBPFL` — abnormal systolic BP flag (`<100` or `≥140 mmHg`).
- `LSTALVDT` — last known alive date (max across VS/AE/DS/EX sources, computed via `derive_vars_extreme_event()`).
- `CARPOPFL` — cardiac AE population flag.

A `stopifnot()` validation block enforces hard invariants (one row per subject, allowed factor levels, type checks). Output is written to `output/adsl.csv` and `output/adsl.rds`.

```r
source("question_3_adam/create_adsl.R")
```

---

## Question 4 — AE Tables, Listings, and Graphs

Three scripts producing regulatory-style outputs from `pharmaverseadam::adae` and `pharmaverseadam::adsl`:

| Script | Output |
|---|---|
| `01_create_ae_summary_table.R` | FDA Table 10–style hierarchical TEAE summary (AESOC › AETERM × ACTARM) → `output/ae_summary_table.html` |
| `02_create_visualizations.R` | Plot 1: AE severity by treatment (stacked bar). Plot 2: Top 10 most frequent AEs with 95 % Clopper-Pearson CIs → two PNG files |
| `03_create_listings.R` | Subject-level TEAE listing with subject, treatment, AE term, severity, causality, start/end dates → `output/ae_listings.html` |

Denominators are pulled from ADSL (not ADAE) so that columns reflect all treated subjects per arm — including those with zero AEs — per FDA Table 10 convention.

---

## Question 5 — Clinical Trial Data API (FastAPI)

A RESTful API serving the AE dataset exported from `pharmaverseadam::adae`. Three endpoints:

- `GET /` — health check returning `{"message": "Clinical Trial Data API is running"}`.
- `POST /ae-query` — dynamic cohort filtering by severity and/or treatment arm; returns matched record count and unique `USUBJID`s.
- `GET /subject-risk/{subject_id}` — computes a weighted **Safety Risk Score** (MILD = 1, MODERATE = 3, SEVERE = 5) and assigns a Low / Medium / High risk category. Returns 404 for unknown subjects.

The dataset is loaded once at startup, columns are validated, and case-insensitive comparisons are used throughout. Pytest smoke tests are included.

```bash
Rscript question_5_api/prepare_data.R       # export adae.csv
pip install -r question_5_api/requirements.txt
uvicorn main:app --reload --app-dir question_5_api
# → http://127.0.0.1:8000/docs
```

---

## Question 6 — GenAI Clinical Data Assistant

A natural-language interface to the AE DataFrame, built on **LangChain** + **Anthropic Claude**. A clinical safety reviewer can ask free-text questions (e.g. *"Give me the subjects who had adverse events of moderate severity"*) and the agent maps them to the correct column, executes a Pandas filter, and returns the matching subject cohort — without hard-coded routing rules.

The architecture follows a clean **Prompt → Parse → Execute** pipeline:

1. **Schema-first prompting** — the dataset's columns and value vocabularies live in `schema.py` and are injected into the system prompt.
2. **Native structured output** — `ChatAnthropic.with_structured_output(ParsedQuery, method="json_schema")` guarantees the LLM returns JSON matching a Pydantic schema, validated by a `@field_validator` on `target_column` for defense in depth.
3. **Case-aware execution** — handles SDTM/ADaM uppercase columns (`AETERM`, `AESOC`, `AESEV`, `AEREL`) versus mixed-case `ACTARM`.
4. **Mock fallback** — a `--mock` flag exercises the full pipeline offline without an API key, satisfying the brief's permitted alternative.

```bash
Rscript question_6_genai/prepare_data.R     # export adae.csv
pip install -r question_6_genai/requirements.txt
python question_6_genai/test_agent.py       # add --mock to run without an API key
```

---

## Author

**Nikolaos Samperis** — 2026

## License

This repository is released under the [MIT License](LICENSE).
