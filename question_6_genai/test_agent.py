"""
Demo script for ``ClinicalTrialDataAgent``.

Loads ``data/adae.csv``, instantiates the agent, and runs three example
natural-language queries through the full Prompt → Parse → Execute pipeline.

Modes
-----
* If ``ANTHROPIC_API_KEY`` is set in the environment (or in a ``.env`` file)
  the script uses Claude via LangChain.
* Otherwise - or if ``--mock`` is passed - the script falls back to the
  rule-based mock parser so the pipeline can still be exercised offline.

Usage
-----
    python test_agent.py              # uses Claude if API key is set
    python test_agent.py --mock       # forces mock mode
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import List

import pandas as pd

# ---------------------------------------------------------------------------
# API key loading
# ---------------------------------------------------------------------------
# python-dotenv reads the ANTHROPIC_API_KEY from a local .env file and injects
# it into os.environ before anything else runs. This means the rest of the
# script (and the ClinicalTrialDataAgent constructor) can simply call
# os.getenv("ANTHROPIC_API_KEY") without knowing where the key came from.
# The try/except makes python-dotenv optional — if it is not installed the
# script still works, it just won't auto-load from a .env file.
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:  # python-dotenv is optional
    pass

# ClinicalTrialDataAgent is the main class that owns the full pipeline:
# Prompt → Parse (LLM or mock) → Execute (pandas filter) → QueryResult
from clinical_agent import ClinicalTrialDataAgent


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Path to the AE dataset exported by prepare_data.R.
# Path(__file__).parent resolves relative to this script's location rather
# than the working directory, so the script works regardless of where it is
# called from.
DATA_PATH = Path(__file__).parent / "data" / "adae.csv"

# The three demo questions cover the three most common column types the agent
# is expected to handle:
#   1. AESEV  — severity enum  ("Moderate" → "MODERATE")
#   2. AESOC  — system organ class / body system ("cardiac" → "CARDIAC DISORDERS")
#   3. AETERM — specific named AE term ("pruritus" → "PRURITUS")
# Adding more questions here is the easiest way to extend the demo.
EXAMPLE_QUESTIONS: List[str] = [
    # 1. Severity → AESEV
    "Give me the subjects who had adverse events of Moderate severity.",
    # 2. Body system → AESOC
    "Which patients experienced cardiac adverse events?",
    # 3. Specific term → AETERM
    "How many subjects reported pruritus?",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _truncate(items: list, n: int = 5) -> list:
    """
    Limit a list of subject IDs so the demo output stays readable.

    If there are more than ``n`` subjects, the list is cut off and a summary
    string ("... (+X more)") is appended so the reader knows the full count.
    The full list is always available on ``QueryResult.unique_subjects``.
    """
    if len(items) <= n:
        return items
    return items[:n] + [f"... (+{len(items) - n} more)"]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    # --- 1. Guard: make sure the data file exists before doing anything else.
    #    Failing fast with a clear message is better than a cryptic pandas error
    #    several lines later.
    if not DATA_PATH.exists():
        print(f"adae.csv not found at {DATA_PATH}", file=sys.stderr)
        print(
            "Run the R export script first:\n"
            "    Rscript prepare_data.R",
            file=sys.stderr,
        )
        sys.exit(1)

    # --- 2. Load the AE dataset into a pandas DataFrame.
    #    The agent works with any DataFrame that has the required columns
    #    (USUBJID, AETERM, AESEV, AESOC). The full column list expected by the
    #    schema is defined in schema.py → COLUMN_INFO.
    df = pd.read_csv(DATA_PATH)
    print(
        f"Loaded {len(df):,} AE records "
        f"for {df['USUBJID'].nunique()} unique subjects from {DATA_PATH.name}.\n"
    )

    # --- 3. Decide which parsing mode to use.
    #    Priority order:
    #      a) --mock flag passed on the command line → always use mock
    #      b) ANTHROPIC_API_KEY not set             → fall back to mock
    #      c) API key is set                         → use Claude via LangChain
    #
    #    This design means the script is always runnable — even in environments
    #    without an API key — while defaulting to the real LLM when one is
    #    available.
    use_mock = "--mock" in sys.argv or not os.getenv("ANTHROPIC_API_KEY")
    if use_mock:
        print("[MODE] Mock parser (no LLM call).")
        # Only print the hint when the fallback was triggered automatically
        # (i.e. the user did not explicitly ask for mock mode).
        if "--mock" not in sys.argv:
            print("       Set ANTHROPIC_API_KEY to use Claude via LangChain.")
        print()
    else:
        print("[MODE] Anthropic Claude via LangChain.\n")

    # --- 4. Instantiate the agent.
    #    When mock=False the constructor imports langchain_anthropic and builds
    #    the LangChain chain (ChatAnthropic → with_structured_output).
    #    When mock=True those imports are skipped entirely, keeping the
    #    dependency footprint minimal for offline use.
    agent = ClinicalTrialDataAgent(df, mock=use_mock)

    # --- 5. Run each demo question through the full pipeline and print results.
    for i, question in enumerate(EXAMPLE_QUESTIONS, start=1):
        print(f"=== Query {i} ===")
        print(f"Q: {question}")

        try:
            # agent.query() runs the complete pipeline:
            #   parse_question() → LLM or mock → ParsedQuery
            #   execute()        → pandas mask  → QueryResult
            result = agent.query(question)
        except Exception as exc:
            # Catch-all so one failing query doesn't abort the entire demo.
            # The repr includes the exception type, which helps with diagnosis.
            print(f"  ✗ failed: {exc!r}\n")
            continue

        # Serialise to a plain dict so json.dumps can handle it, then truncate
        # the subject list to keep the terminal output readable. The full list
        # is still accessible on result.unique_subjects if needed.
        out = result.to_dict()
        out["unique_subjects"] = _truncate(out["unique_subjects"], n=5)
        print(json.dumps(out, indent=2))
        print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
# The if __name__ == "__main__" guard ensures main() is only called when this
# file is run directly (python test_agent.py), not when it is imported as a
# module — which would be the case in a unit-testing context.
if __name__ == "__main__":
    main()