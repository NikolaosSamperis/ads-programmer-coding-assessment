"""
Clinical Trial Data API
=======================

A small FastAPI service that serves Adverse Event (AE) data from an exported
ADaM `adae.csv` file. Provides:

* `GET  /`                       – health-check / welcome
* `POST /ae-query`               – dynamic cohort filtering by severity / arm
* `GET  /subject-risk/{id}`      – weighted Safety Risk Score per subject

Run locally with:
    uvicorn main:app --reload
"""

from pathlib import Path
from typing import List, Optional

import pandas as pd
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Resolve the path to adae.csv relative to this file so the API works
# regardless of which directory uvicorn is launched from.
DATA_PATH = Path(__file__).parent / "data" / "adae.csv"

# Risk weights per AESEV value (compared in upper case).
# These are defined once here so they can be reused across endpoints
# and updated easily if new severity levels are introduced.
SEVERITY_WEIGHTS = {
    "MILD": 1,
    "MODERATE": 3,
    "SEVERE": 5,
}

# Risk-category cut-offs – matches the spec exactly.
def _categorize_risk(score: int) -> str:
    # Boundaries: <5 = Low, 5-14 = Medium, >=15 = High
    if score < 5:
        return "Low"
    if score < 15:
        return "Medium"
    return "High"


# ---------------------------------------------------------------------------
# Data loading (executed once at import-time / app start-up)
# ---------------------------------------------------------------------------

def load_ae_data(path: Path = DATA_PATH) -> pd.DataFrame:
    """Load the ADAE dataset and normalise the columns we rely on.

    The file is expected to be the CSV export of ``pharmaverseadam::adae``
    and to contain at least: USUBJID, AESEV, ACTARM. Other columns are kept
    untouched so the same DataFrame can be reused by other endpoints later.
    """
    # Fail fast at startup rather than returning a 500 on the first request
    if not path.exists():
        raise FileNotFoundError(
            f"ADAE dataset not found at {path}. "
            "Export pharmaverseadam::adae to data/adae.csv "
            "(see prepare_data.R) before starting the API."
        )

    df = pd.read_csv(path)

    # Validate that all columns the endpoints depend on are present
    required = {"USUBJID", "AESEV", "ACTARM"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(
            f"adae.csv is missing required columns: {sorted(missing)}"
        )

    # Strip whitespace; keep original case for display, do case-insensitive
    # comparison in the endpoints.
    for col in ("USUBJID", "AESEV", "ACTARM"):
        df[col] = df[col].astype("string").str.strip()

    return df

# Load the dataset once at startup — the API is read-only so a single
# process-wide DataFrame is safe and keeps every request O(rows).
ae_df: pd.DataFrame = load_ae_data()


# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------

class AEQueryRequest(BaseModel):
    """Body for ``POST /ae-query``. All fields are optional filters."""

    severity: Optional[List[str]] = Field(
        default=None,
        description="Severities to keep, e.g. ['MILD', 'MODERATE']",
        examples=[["MILD", "MODERATE"]],
    )
    treatment_arm: Optional[str] = Field(
        default=None,
        description="ACTARM value, e.g. 'Placebo'",
        examples=["Placebo"],
    )


class AEQueryResponse(BaseModel):
    # Total number of AE records matching the filters
    count: int
    # Unique subject IDs in the filtered cohort, sorted alphabetically
    subjects: List[str]


class SubjectRiskResponse(BaseModel):
    subject_id: str
    risk_score: int     # Sum of severity weights across all AEs
    risk_category: str  # Low / Medium / High based on risk_score


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Clinical Trial Data API",
    description=(
        "Serves AE data exported from pharmaverseadam::adae. "
        "Supports dynamic cohort filtering and per-subject risk scoring."
    ),
    version="1.0.0",
)


@app.get("/", summary="Health check")
def root() -> dict[str, str]:
    """Welcome / liveness probe."""
    return {"message": "Clinical Trial Data API is running"}


@app.post(
    "/ae-query",
    response_model=AEQueryResponse,
    summary="Dynamic cohort filtering",
)
def ae_query(filters: AEQueryRequest) -> AEQueryResponse:
    """Filter the AE dataset on any combination of severity / treatment arm.

    Filters that are ``null`` or omitted are ignored, so an empty body
    returns every record.
    """

    # Start with the full dataset and narrow down based on provided filters
    df = ae_df

    if filters.severity:
        # Normalise to upper case so "mild", "Mild", "MILD" all match
        wanted = {s.strip().upper() for s in filters.severity if s}
        if wanted:
            df = df[df["AESEV"].str.upper().isin(wanted)]

    if filters.treatment_arm:
        # casefold() is a more aggressive lowercase for unicode safety
        target = filters.treatment_arm.strip().casefold()
        df = df[df["ACTARM"].str.casefold() == target]

    # Return unique subject IDs sorted alphabetically for consistent output
    subjects = sorted(df["USUBJID"].dropna().unique().tolist())
    return AEQueryResponse(count=int(len(df)), subjects=subjects)


@app.get(
    "/subject-risk/{subject_id}",
    response_model=SubjectRiskResponse,
    summary="Weighted Safety Risk Score for a subject",
    responses={404: {"description": "Subject not found"}},
)
def subject_risk(subject_id: str) -> SubjectRiskResponse:
    """Compute the weighted risk score for ``subject_id``.

    * MILD = 1, MODERATE = 3, SEVERE = 5
    * Other / missing severities contribute 0
    * Categories: <5 Low, 5–14 Medium, ≥15 High
    """

    # Filter the dataset to only this subject's AE records
    subj_df = ae_df[ae_df["USUBJID"] == subject_id]

    # Return 404 if the subject ID is not found in the dataset
    if subj_df.empty:
        raise HTTPException(
            status_code=404,
            detail=f"Subject '{subject_id}' not found in AE dataset.",
        )

    score = int(
        subj_df["AESEV"]
        .str.upper()
        .map(SEVERITY_WEIGHTS)    # Map each severity to its point value
        .fillna(0)                # Unknown or missing severities contribute 0
        .sum()                    # Total risk score across all AEs
    )

    return SubjectRiskResponse(
        subject_id=subject_id,
        risk_score=score,
        risk_category=_categorize_risk(score),
    )
