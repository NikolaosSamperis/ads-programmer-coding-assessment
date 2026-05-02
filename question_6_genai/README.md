# Question 6 — GenAI Clinical Data Assistant

![Python](https://img.shields.io/badge/Python-3.11%2B-blue?logo=python&logoColor=white)
![LangChain](https://img.shields.io/badge/LangChain-1.2%2B-brightgreen?logo=chainlink&logoColor=white)
![Anthropic](https://img.shields.io/badge/Anthropic-Claude-orange?logo=anthropic&logoColor=white)
![Pharmaverse](https://img.shields.io/badge/Data-Pharmaverse-blueviolet)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/NikolaosSamperis/ads-programmer-coding-assessment/blob/main/LICENSE)

A natural-language interface to an Adverse Events (AE) DataFrame, powered by
Anthropic's Claude via LangChain. A clinical safety reviewer can ask free-text
questions about the ADAE dataset and the agent maps them to the correct column,
executes the filter, and returns the matching subject cohort — no SQL or column
names required.

> **Live example**
> Q: *"Give me the subjects who had adverse events of Moderate severity."*
> → `AESEV == "MODERATE"` → **378 matched records, 136 unique subjects.**

---

## Project structure

```
question_6_genai/
├── README.md                  # this file
├── requirements.txt           # Python dependencies
├── .env.example               # template for ANTHROPIC_API_KEY (safe to commit)
├── .env                       # your real API key — never committed (in .gitignore)
├── schema.py                  # ADAE schema (LLM- and code-facing)
├── clinical_agent.py          # ClinicalTrialDataAgent class
├── test_agent.py              # demo script — runs 3 example queries
├── prepare_data.R             # export pharmaverseadam::adae → data/adae.csv
└── data/
    └── adae.csv               # AE dataset — produced by prepare_data.R
```

---

## Architecture

The agent follows a clean **Prompt → Parse → Execute** pipeline:

```
   user question (free text)
            │
            ▼
   ┌──────────────────────────────────────────────┐
   │  Prompt                                       │
   │  schema.SCHEMA_DESCRIPTION + routing rules    │
   │  injected as the LLM system message           │
   └──────────────────────────────────────────────┘
            │
            ▼
   ┌──────────────────────────────────────────────┐
   │  Parse  (LangChain + Anthropic)               │
   │  ChatAnthropic.with_structured_output(        │
   │      ParsedQuery, method="json_schema")       │
   │  → Claude returns a JSON object that          │
   │    validates against the Pydantic schema      │
   └──────────────────────────────────────────────┘
            │  ParsedQuery(target_column, filter_value, reasoning)
            ▼
   ┌──────────────────────────────────────────────┐
   │  Execute  (pandas)                            │
   │  Case-aware boolean mask on the AE DataFrame  │
   └──────────────────────────────────────────────┘
            │
            ▼
   QueryResult(matched_count, unique_subject_count, unique_subjects)
```

### Why this shape?

1. **Schema-first.** The dataset's columns and value vocabularies live in
   `schema.py` and are injected into the system prompt. Adding a new column
   means editing one file — no prompt surgery, no rule changes.
2. **Native structured output.** `with_structured_output(..., method="json_schema")`
   uses Anthropic's native structured-output feature, which guarantees the
   model returns JSON validating against the `ParsedQuery` Pydantic schema. No
   regex, no fragile string parsing.
3. **No hard-coded routing rules.** The LLM does the semantic mapping.
   *"intensity"* → `AESEV`, *"cardiac"* → `AESOC`, *"headache"* → `AETERM` are
   inferred from the schema description, not from `if/elif` ladders.
4. **Mock fallback.** A small rule-based `mock=True` path lets the complete
   pipeline run offline without an API key — useful for reviewers and CI.

---

## Setup

### Step 1 — Clone / open the project

Open the `question_6_genai/` folder in VS Code, then open a terminal
(**Terminal → New Terminal**).

> **Windows PowerShell only:** run this once if script execution is blocked:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

### Step 2 — Create and activate a virtual environment

```powershell
# Windows (PowerShell)
python -m venv .venv
.venv\Scripts\Activate.ps1
```

```bash
# Mac / Linux
python -m venv .venv
source .venv/bin/activate
```

Your prompt will show `(.venv)` once active.

> **Python version note:** Python 3.10 or newer is required. pandas 2.x will
> fail to build from source on Python 3.9. Check your version with
> `python --version` and upgrade at https://www.python.org/downloads/ if needed.

### Step 3 — Install dependencies

```powershell
pip install -r requirements.txt
```

This installs pandas, pydantic, langchain, langchain-anthropic, and
python-dotenv into the virtual environment.

### Step 4 — Set up your Anthropic API key *(optional)*

```powershell
# Windows
Copy-Item .env.example .env
```

```bash
# Mac / Linux
cp .env.example .env
```

Open `.env` and replace the placeholder with your real key:

```
ANTHROPIC_API_KEY=sk-ant-your-real-key-here
```

Get a key at https://console.anthropic.com/.

> **No API key?** Skip this step entirely and use `--mock` (see
> [Running the demo](#running-the-demo)). The full Prompt → Parse → Execute
> pipeline still runs — the only difference is that a rule-based parser
> substitutes for the live LLM call. This is the approach explicitly permitted
> by the assessment brief.

### Step 5 — Export the data

Run the included R script to export `pharmaverseadam::adae`:

```powershell
Rscript prepare_data.R
```

This writes `data/adae.csv` with the following columns: `USUBJID`, `AETERM`,
`AESEV`, `AESOC`, `AEREL`, `ACTARM`, `AESTDTC`, `AEENDTC`. The script
installs `pharmaverseadam` from CRAN automatically if it is not already
available.

---

## Running the demo

### With Claude (API key required)

```powershell
python test_agent.py
```

### Without an API key — mock mode

```powershell
python test_agent.py --mock
```

Both commands run the same three example queries through the complete pipeline:

1. *"Give me the subjects who had adverse events of Moderate severity."*
2. *"Which patients experienced cardiac adverse events?"*
3. *"How many subjects reported pruritus?"*

---

## Mock vs LLM — side-by-side output

The pandas execution (records returned, subject IDs) is **identical** in both
modes. The only difference is the `reasoning` field — which reveals exactly
what separates keyword matching from semantic understanding.

### Query 1 — Severity

**Question:** *"Give me the subjects who had adverse events of Moderate severity."*

| Field | Mock output | Claude output |
|---|---|---|
| `target_column` | `AESEV` | `AESEV` |
| `filter_value` | `MODERATE` | `MODERATE` |
| `reasoning` | *"Mock: matched a severity keyword."* | *"The question asks about severity level, which maps to AESEV with the normalized value MODERATE."* |
| `matched_records` | 378 | 378 |
| `unique_subject_count` | 136 | 136 |

---

### Query 2 — Body system

**Question:** *"Which patients experienced cardiac adverse events?"*

| Field | Mock output | Claude output |
|---|---|---|
| `target_column` | `AESOC` | `AESOC` |
| `filter_value` | `CARDIAC DISORDERS` | `CARDIAC DISORDERS` |
| `reasoning` | *"Mock: matched a body-system keyword."* | *"The question asks about cardiac adverse events, which maps to the System Organ Class for heart-related conditions."* |
| `matched_records` | 91 | 91 |
| `unique_subject_count` | 44 | 44 |

---

### Query 3 — Specific AE term

**Question:** *"How many subjects reported pruritus?"*

| Field | Mock output | Claude output |
|---|---|---|
| `target_column` | `AETERM` | `AETERM` |
| `filter_value` | `PRURITUS` | `PRURITUS` |
| `reasoning` | *"Mock: defaulted to AETERM with last meaningful token."* | *"Pruritus is a specific named adverse event condition, so we filter on AETERM with the uppercase normalized value."* |
| `matched_records` | 84 | 84 |
| `unique_subject_count` | 57 | 57 |

---

### Where Claude goes further — semantic queries

The mock parser only matches keywords it was explicitly programmed for. Claude
understands **meaning**, so it handles synonyms and paraphrasing the mock
cannot:

| Question | Mock result | Claude result |
|---|---|---|
| *"Show me high intensity adverse events"* | Falls to AETERM fallback ❌ | `AESEV = SEVERE` ✅ |
| *"Which subjects had drug-related events?"* | Falls to AETERM fallback ❌ | `AEREL = PROBABLE` ✅ |
| *"Patients with skin issues"* | `AESOC = SKIN AND SUBCUTANEOUS...` ✅ | `AESOC = SKIN AND SUBCUTANEOUS...` ✅ |

---

## Programmatic usage

```python
import pandas as pd
from dotenv import load_dotenv
from clinical_agent import ClinicalTrialDataAgent

load_dotenv()                            # loads ANTHROPIC_API_KEY from .env
df = pd.read_csv("data/adae.csv")
agent = ClinicalTrialDataAgent(df)

result = agent.query("Which subjects had probable drug-related AEs?")

print(result.parsed.target_column)      # AEREL
print(result.parsed.filter_value)       # PROBABLE
print(result.parsed.reasoning)          # Claude's explanation
print(result.unique_subject_count)      # e.g. 79
print(result.unique_subjects[:5])       # first 5 subject IDs
```

### ClinicalTrialDataAgent options

| Argument | Default | What it does |
|---|---|---|
| `df` | — | The AE DataFrame |
| `model` | `"claude-sonnet-4-5"` | Any Claude model supported by `langchain-anthropic` |
| `api_key` | `None` | Falls back to `ANTHROPIC_API_KEY` env var |
| `mock` | `False` | Skip the LLM and use a rule-based parser instead |
| `temperature` | `0.0` | Deterministic — same question always returns same parse |

---

## Schema covered

| Column | Meaning | Example values |
|---|---|---|
| `USUBJID` | Unique subject identifier | `"01-701-1015"` |
| `AETERM` | Specific AE term / condition | `"HEADACHE"`, `"PRURITUS"`, `"DIARRHOEA"` |
| `AESEV` | Severity / intensity | `"MILD"`, `"MODERATE"`, `"SEVERE"` |
| `AESOC` | System organ class (body system) | `"CARDIAC DISORDERS"`, `"GASTROINTESTINAL DISORDERS"` |
| `AEREL` | Causality / relationship to drug | `"NONE"`, `"REMOTE"`, `"POSSIBLE"`, `"PROBABLE"` |
| `ACTARM` | Actual treatment arm | `"Placebo"`, `"Xanomeline High Dose"` |

`USUBJID` is intentionally **not** an allowed `target_column` — it is what the
agent *returns*, not what it filters on.

---

## Design decisions

- **`json_schema` over `function_calling`.** Anthropic's native structured-output
  mode guarantees schema-valid JSON and is available in `langchain-anthropic >= 1.1.0`.
- **`temperature=0`.** Parsing is deterministic — the same question should
  always map to the same column and value.
- **Pydantic validator on `target_column`.** Even with structured output, a
  `@field_validator` rejects anything outside the allow-list. Defense in depth
  is cheap.
- **Case-aware execution.** SDTM/ADaM stores `AETERM`, `AESOC`, `AESEV` and
  `AEREL` uppercase but `ACTARM` mixed-case. The executor applies `.str.upper()`
  or `.str.casefold()` per column to prevent silent zero-match bugs.
- **Deferred LLM imports.** `langchain_anthropic` is imported only when
  `mock=False`, so the mock path works without the heavy dependency installed.

---

## Extending

- **Add a new column.** Add a row to `COLUMN_INFO` in `schema.py` and a bullet
  to `SCHEMA_DESCRIPTION`. No changes needed in `clinical_agent.py`.
- **Multi-condition queries.** Change `ParsedQuery` from a single
  `(column, value)` pair to a list of filters and AND them in `execute()`.
- **Range queries.** Add a `comparator` field (`==`, `>=`, `<=`, `between`)
  to `ParsedQuery` for date / numeric columns.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No API key | Run `python test_agent.py --mock` — full pipeline, no key needed |
| `python` not recognised on Windows | Install Python 3.11+ from python.org and tick **Add to PATH** |
| `(.venv)` not showing after activation | Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` first |
| `ModuleNotFoundError: langchain_anthropic` | `pip install -r requirements.txt` inside the activated venv |
| `ValueError: No Anthropic API key found` | Check `.env` exists (not just `.env.example`) with no spaces around `=` |
| `ValueError: DataFrame is missing required AE columns` | Re-run `Rscript prepare_data.R` to regenerate `data/adae.csv` |
| Always returns 0 subjects | Casing mismatch — confirm `AETERM`/`AESOC` are uppercase in the CSV |

---

## References

- LangChain × Anthropic: https://docs.langchain.com/oss/python/integrations/chat/anthropic
- Anthropic structured outputs: https://docs.claude.com/en/docs/build-with-claude/structured-outputs
- Claude API overview: https://docs.claude.com/en/api/overview
- ADaM IG (CDISC): https://www.cdisc.org/standards/foundational/adam
- Pharmaverse ADAE: https://pharmaverse.github.io/pharmaverseadam/
