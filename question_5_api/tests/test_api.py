"""Smoke tests for the Clinical Trial Data API.

Run with:  pytest -v

Each test uses FastAPI's TestClient which runs the app in-process,
so no live uvicorn server is needed.
"""
from fastapi.testclient import TestClient

from main import app, ae_df

# Single client instance shared across all tests
client = TestClient(app)


def test_root() -> None:
    # Confirm the health check endpoint returns the expected welcome message
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"message": "Clinical Trial Data API is running"}


def test_ae_query_no_filters_returns_all() -> None:
    # An empty body should apply no filters and return the full dataset
    r = client.post("/ae-query", json={})
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == len(ae_df)
    # Subject count should match the number of unique USUBJIDs in the dataset
    assert len(body["subjects"]) == ae_df["USUBJID"].nunique()


def test_ae_query_severity_and_arm() -> None:
    # Filtering by both severity and treatment arm should combine both conditions
    r = client.post(
        "/ae-query",
        json={"severity": ["MILD", "MODERATE"], "treatment_arm": "Placebo"},
    )
    assert r.status_code == 200
    body = r.json()
    # Replicate the filter logic in pandas to get the expected count
    expected = ae_df[
        ae_df["AESEV"].str.upper().isin({"MILD", "MODERATE"})
        & (ae_df["ACTARM"].str.casefold() == "placebo")
    ]
    assert body["count"] == len(expected)


def test_ae_query_severity_is_case_insensitive() -> None:
    # "mild" and "MILD" should return identical results
    r1 = client.post("/ae-query", json={"severity": ["mild"]})
    r2 = client.post("/ae-query", json={"severity": ["MILD"]})
    assert r1.json() == r2.json()


def test_subject_risk_known_subject() -> None:
    # Pick the first subject in the dataset to use as a known valid ID
    sample_id = ae_df["USUBJID"].dropna().iloc[0]
    r = client.get(f"/subject-risk/{sample_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["subject_id"] == sample_id
    # Risk score must be a non-negative integer
    assert isinstance(body["risk_score"], int)
    # Risk category must be one of the three valid values
    assert body["risk_category"] in {"Low", "Medium", "High"}


def test_subject_risk_404() -> None:
    # A subject ID that doesn't exist should return a 404 with a clear message
    r = client.get("/subject-risk/NOT-A-REAL-SUBJECT")
    assert r.status_code == 404
    assert "not found" in r.json()["detail"].lower()
