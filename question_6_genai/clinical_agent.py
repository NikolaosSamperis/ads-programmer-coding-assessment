"""
Clinical Trial Data Agent.

Translates natural-language questions about an Adverse Events DataFrame into
structured Pandas queries.

Pipeline
--------
    user question
         │
         ▼
   [LLM via LangChain]   ── ChatAnthropic + with_structured_output(ParsedQuery)
         │                  → forces Claude to return a JSON object that
         │                    validates against the Pydantic schema.
         ▼
    ParsedQuery(target_column, filter_value, reasoning)
         │
         ▼
   [Pandas execution]   ── case-aware boolean mask on the AE DataFrame.
         │
         ▼
    QueryResult(matched_count, unique_subject_count, unique_subjects)

A small rule-based ``mock`` mode is also provided so the full
Prompt → Parse → Execute flow can be exercised offline (no API key required).
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import List, Optional

import pandas as pd
from pydantic import BaseModel, Field, field_validator

from schema import (
    ALLOWED_TARGET_COLUMNS,
    COLUMN_INFO,
    SCHEMA_DESCRIPTION,
)


# ---------------------------------------------------------------------------
# Structured LLM output
# ---------------------------------------------------------------------------
class ParsedQuery(BaseModel):
    """
    Structured object the LLM is asked to produce for each question.

    Field descriptions are passed through to Anthropic's structured-output
    feature, so they double as instructions to the model.
    """

    target_column: str = Field(
        description=(
            "The single dataset column the question is asking about. "
            f"Must be one of: {', '.join(ALLOWED_TARGET_COLUMNS)}."
        )
    )
    filter_value: str = Field(
        description=(
            "The value to filter on, normalized to match how the dataset stores it. "
            "AETERM and AESOC are stored UPPERCASE. "
            "AESEV is one of MILD / MODERATE / SEVERE. "
            "AEREL is one of NONE / REMOTE / POSSIBLE / PROBABLE. "
            "ACTARM uses the exact arm label (e.g. 'Placebo', 'Xanomeline High Dose')."
        )
    )
    reasoning: str = Field(
        description="One short sentence explaining the column / value choice."
    )

    @field_validator("target_column")
    @classmethod
    def _column_must_be_allowed(cls, v: str) -> str:
        if v not in ALLOWED_TARGET_COLUMNS:
            raise ValueError(
                f"target_column '{v}' is not allowed. "
                f"Choose from {ALLOWED_TARGET_COLUMNS}."
            )
        return v


# ---------------------------------------------------------------------------
# Result of an end-to-end query
# ---------------------------------------------------------------------------
@dataclass
class QueryResult:
    """End-to-end result of a single natural-language query."""

    question: str
    parsed: ParsedQuery
    matched_count: int
    unique_subject_count: int
    unique_subjects: List[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "question": self.question,
            "target_column": self.parsed.target_column,
            "filter_value": self.parsed.filter_value,
            "reasoning": self.parsed.reasoning,
            "matched_records": self.matched_count,
            "unique_subject_count": self.unique_subject_count,
            "unique_subjects": list(self.unique_subjects),
        }


# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------
class ClinicalTrialDataAgent:
    """
    Natural-language interface to an Adverse Events DataFrame.

    Parameters
    ----------
    df :
        DataFrame containing AE records. Must include at least
        ``USUBJID``, ``AETERM``, ``AESEV`` and ``AESOC``.
    model :
        Claude model name. Defaults to ``claude-sonnet-4-5``, a strong and
        cost-efficient choice for short structured-extraction tasks.
        Anthropic also offers larger options (e.g. ``claude-opus-4-7``).
    api_key :
        Anthropic API key. If ``None``, the ``ANTHROPIC_API_KEY`` environment
        variable is used.
    mock :
        If ``True``, skip the LLM entirely and use a tiny rule-based parser.
        Intended for offline demos and CI - **not** for real use.
    temperature :
        LLM temperature. Defaults to ``0`` for deterministic parsing.
    """

    DEFAULT_MODEL = "claude-sonnet-4-5"

    # ------------------------------------------------------------------
    # construction
    # ------------------------------------------------------------------
    def __init__(
        self,
        df: pd.DataFrame,
        model: str = DEFAULT_MODEL,
        api_key: Optional[str] = None,
        mock: bool = False,
        temperature: float = 0.0,
    ) -> None:
        self.df = df.copy()
        self._validate_dataframe()
        self.model = model
        self.mock = mock

        # Build the LangChain chain only when we are actually going to use it.
        # This keeps ``mock=True`` fully usable without ``langchain-anthropic``
        # installed.
        self._chain = None
        if not mock:
            self._chain = self._build_chain(api_key=api_key, temperature=temperature)

    def _validate_dataframe(self) -> None:
        required = {"USUBJID", "AETERM", "AESEV", "AESOC"}
        missing = required - set(self.df.columns)
        if missing:
            raise ValueError(
                f"DataFrame is missing required AE columns: {sorted(missing)}"
            )

    def _build_chain(self, api_key: Optional[str], temperature: float):
        # Local imports so users running in mock mode don't need these libs.
        from langchain_anthropic import ChatAnthropic
        from langchain_core.prompts import ChatPromptTemplate

        api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise ValueError(
                "No Anthropic API key found. Either set the ANTHROPIC_API_KEY "
                "environment variable, pass api_key=..., or instantiate the "
                "agent with mock=True."
            )

        llm = ChatAnthropic(
            model=self.model,
            api_key=api_key,
            temperature=temperature,
        )
        # ``method="json_schema"`` engages Anthropic's native structured-output
        # feature, which is more reliable than plain function calling.
        structured_llm = llm.with_structured_output(ParsedQuery, method="json_schema")
        prompt = ChatPromptTemplate.from_messages(
            [
                ("system", self._system_prompt()),
                ("human", "{question}"),
            ]
        )
        return prompt | structured_llm

    @staticmethod
    def _system_prompt() -> str:
        return (
            "You are a clinical-data query parser. Given a natural-language "
            "question from a clinical safety reviewer, map it to the single "
            "most relevant column and a normalized filter value from the "
            "ADAE dataset described below.\n\n"
            f"{SCHEMA_DESCRIPTION}\n"
            "Rules:\n"
            "1. Pick exactly ONE column from "
            f"{', '.join(ALLOWED_TARGET_COLUMNS)}.\n"
            "2. Normalize filter_value to match how the value is stored:\n"
            "   - AETERM and AESOC -> UPPERCASE\n"
            "   - AESEV -> MILD / MODERATE / SEVERE\n"
            "   - AEREL -> NONE / REMOTE / POSSIBLE / PROBABLE\n"
            "   - ACTARM -> exact arm label as it appears in the data\n"
            "3. Specific named conditions (headache, rash, dizziness) -> AETERM.\n"
            "4. Body systems (cardiac, skin, GI, neurological) -> AESOC.\n"
            "5. Severity / intensity wording -> AESEV.\n"
            "6. Causality / drug-relationship wording -> AEREL.\n"
            "7. Treatment-arm wording (placebo, xanomeline ...) -> ACTARM.\n"
            "8. Keep `reasoning` to one short sentence."
        )

    # ------------------------------------------------------------------
    # LLM step
    # ------------------------------------------------------------------
    def parse_question(self, question: str) -> ParsedQuery:
        """Map a natural-language question to a ``ParsedQuery``."""
        if self.mock:
            return self._mock_parse(question)
        # The chain returns a validated ParsedQuery instance.
        return self._chain.invoke({"question": question})

    @staticmethod
    def _mock_parse(question: str) -> ParsedQuery:
        """
        Tiny rule-based fallback used when ``mock=True``.

        Just enough heuristics to make the demo runnable without an API key.
        Order matters - more specific rules are checked first.
        """
        q = question.lower()

        # 1. Severity ----------------------------------------------------
        for sev in ("mild", "moderate", "severe"):
            if re.search(rf"\b{sev}\b", q):
                return ParsedQuery(
                    target_column="AESEV",
                    filter_value=sev.upper(),
                    reasoning="Mock: matched a severity keyword.",
                )

        # 2. Causality ---------------------------------------------------
        for rel in ("probable", "possible", "remote"):
            if re.search(rf"\b{rel}\b", q):
                return ParsedQuery(
                    target_column="AEREL",
                    filter_value=rel.upper(),
                    reasoning="Mock: matched a causality keyword.",
                )

        # 3. Treatment arm ----------------------------------------------
        if "placebo" in q:
            return ParsedQuery(
                target_column="ACTARM",
                filter_value="Placebo",
                reasoning="Mock: matched 'placebo'.",
            )
        if "xanomeline" in q:
            return ParsedQuery(
                target_column="ACTARM",
                filter_value=(
                    "Xanomeline High Dose" if "high" in q else "Xanomeline Low Dose"
                ),
                reasoning="Mock: matched 'xanomeline'.",
            )

        # 4. Body systems -----------------------------------------------
        soc_map = {
            "cardiac": "CARDIAC DISORDERS",
            "heart": "CARDIAC DISORDERS",
            "skin": "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
            "gastrointestinal": "GASTROINTESTINAL DISORDERS",
            "gi": "GASTROINTESTINAL DISORDERS",
            "nervous": "NERVOUS SYSTEM DISORDERS",
            "neurological": "NERVOUS SYSTEM DISORDERS",
            "respiratory": "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS",
        }
        for kw, soc in soc_map.items():
            if re.search(rf"\b{kw}\b", q):
                return ParsedQuery(
                    target_column="AESOC",
                    filter_value=soc,
                    reasoning="Mock: matched a body-system keyword.",
                )

        # 5. Last-ditch AETERM extraction -------------------------------
        # Pull the last meaningful 4+ letter token, ignoring stop-ish words.
        stop = {
            "subjects", "patients", "with", "had", "have", "many", "much",
            "report", "reported", "experience", "experienced",
            "the", "and", "any", "show", "give", "list", "find", "which",
            "what", "where", "when", "from", "than", "more",
            "adverse", "events", "event",
        }
        tokens = re.findall(r"[A-Za-z]{4,}", question)
        meaningful = [t for t in tokens if t.lower() not in stop]
        if meaningful:
            return ParsedQuery(
                target_column="AETERM",
                filter_value=meaningful[-1].upper(),
                reasoning="Mock: defaulted to AETERM with last meaningful token.",
            )

        return ParsedQuery(
            target_column="AETERM",
            filter_value="UNKNOWN",
            reasoning="Mock: could not parse question.",
        )

    # ------------------------------------------------------------------
    # Pandas execution step
    # ------------------------------------------------------------------
    def execute(self, parsed: ParsedQuery) -> QueryResult:
        """Apply ``parsed`` to ``self.df`` and return a ``QueryResult``."""
        col = parsed.target_column
        val = parsed.filter_value

        if col not in self.df.columns:
            raise ValueError(f"Column '{col}' is not present in the DataFrame.")

        series = self.df[col].astype("string")
        case = COLUMN_INFO.get(col, {}).get("case", "upper")

        if case == "upper":
            mask = series.str.upper() == val.upper()
        else:  # casefold - case-insensitive equality
            mask = series.str.casefold() == val.casefold()

        matched = self.df.loc[mask.fillna(False)]
        subjects = sorted(matched["USUBJID"].dropna().astype(str).unique().tolist())

        return QueryResult(
            question="",  # filled in by ``query()``
            parsed=parsed,
            matched_count=int(len(matched)),
            unique_subject_count=len(subjects),
            unique_subjects=subjects,
        )

    # ------------------------------------------------------------------
    # End-to-end
    # ------------------------------------------------------------------
    def query(self, question: str) -> QueryResult:
        """Run the full Prompt → Parse → Execute pipeline."""
        parsed = self.parse_question(question)
        result = self.execute(parsed)
        result.question = question
        return result
