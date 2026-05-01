"""Smoke tests for the Clinical Trial Data API.

Run with:  pytest -v
"""
from fastapi.testclient import TestClient

from main import app, ae_df

client = TestClient(app)


def test_root() -> None:
    r = client.get("/")
    assert r.status_code == 200
    assert r.json() == {"message": "Clinical Trial Data API is running"}


def test_ae_query_no_filters_returns_all() -> None:
    r = client.post("/ae-query", json={})
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == len(ae_df)
    assert len(body["subjects"]) == ae_df["USUBJID"].nunique()


def test_ae_query_severity_and_arm() -> None:
    r = client.post(
        "/ae-query",
        json={"severity": ["MILD", "MODERATE"], "treatment_arm": "Placebo"},
    )
    assert r.status_code == 200
    body = r.json()
    expected = ae_df[
        ae_df["AESEV"].str.upper().isin({"MILD", "MODERATE"})
        & (ae_df["ACTARM"].str.casefold() == "placebo")
    ]
    assert body["count"] == len(expected)


def test_ae_query_severity_is_case_insensitive() -> None:
    r1 = client.post("/ae-query", json={"severity": ["mild"]})
    r2 = client.post("/ae-query", json={"severity": ["MILD"]})
    assert r1.json() == r2.json()


def test_subject_risk_known_subject() -> None:
    sample_id = ae_df["USUBJID"].dropna().iloc[0]
    r = client.get(f"/subject-risk/{sample_id}")
    assert r.status_code == 200
    body = r.json()
    assert body["subject_id"] == sample_id
    assert isinstance(body["risk_score"], int)
    assert body["risk_category"] in {"Low", "Medium", "High"}


def test_subject_risk_404() -> None:
    r = client.get("/subject-risk/NOT-A-REAL-SUBJECT")
    assert r.status_code == 404
    assert "not found" in r.json()["detail"].lower()
