"""
Schema definitions for the ADAE (Adverse Events) dataset.

Two representations of the same schema are kept here:

* ``SCHEMA_DESCRIPTION`` is a natural-language string injected into the system
  prompt so the LLM understands what the columns mean and which one to pick
  for any given user question.

* ``COLUMN_INFO`` is a programmatic dictionary used by the execution layer to
  decide things like "should I match this column case-insensitively?".

Keeping the two in one file makes it easy to keep them in sync when new
columns are added.
"""

# ---------------------------------------------------------------------------
# Natural-language schema (LLM facing)
# ---------------------------------------------------------------------------
SCHEMA_DESCRIPTION = """\
You are working with a clinical trial Adverse Events (AE) dataset called ADAE.
The relevant columns are:

- USUBJID : Unique Subject Identifier (e.g. "01-701-1015"). Never used as a
  filter target by the parser - it is the entity returned in the result set.

- AETERM : Reported term for the adverse event (the specific symptom or
  condition).
    Examples : "HEADACHE", "NAUSEA", "DIZZINESS", "PRURITUS", "ERYTHEMA",
               "DIARRHOEA", "RASH"
    Use for  : specific named conditions, symptoms, or diseases.

- AESEV  : Severity / intensity of the adverse event.
    Allowed values : "MILD", "MODERATE", "SEVERE"
    Use for        : severity, intensity, "how severe", "grade" wording.

- AESOC  : Primary System Organ Class - the body system affected.
    Examples : "CARDIAC DISORDERS",
               "GASTROINTESTINAL DISORDERS",
               "SKIN AND SUBCUTANEOUS TISSUE DISORDERS",
               "NERVOUS SYSTEM DISORDERS",
               "RESPIRATORY, THORACIC AND MEDIASTINAL DISORDERS"
    Use for  : body system / organ class wording such as "cardiac", "skin",
               "GI / gastrointestinal", "neurological", "respiratory".

- AEREL  : Causality / relationship to the study drug.
    Allowed values : "NONE", "REMOTE", "POSSIBLE", "PROBABLE"
    Use for        : "related to drug", "drug-related", "caused by", "causality".

- ACTARM : Actual treatment arm assigned to the subject.
    Examples : "Placebo", "Xanomeline High Dose", "Xanomeline Low Dose"
    Use for  : treatment groups, study arms, "patients on placebo", etc.

- AESTDTC : ISO-8601 start date of the AE (rarely a primary filter target).
- AEENDTC : ISO-8601 end date of the AE   (rarely a primary filter target).
"""

# ---------------------------------------------------------------------------
# Programmatic schema (execution facing)
# ---------------------------------------------------------------------------
# ``case`` controls how values are normalized before being compared:
#   - "upper"     : compare uppercase to uppercase   (AETERM, AESOC, AESEV, AEREL)
#   - "casefold"  : compare casefolded to casefolded (ACTARM and free-text fields)
COLUMN_INFO: dict[str, dict] = {
    "AETERM": {
        "description": "Specific adverse event term / condition",
        "case": "upper",
    },
    "AESEV": {
        "description": "Severity / intensity",
        "values": ["MILD", "MODERATE", "SEVERE"],
        "case": "upper",
    },
    "AESOC": {
        "description": "System organ class (body system)",
        "case": "upper",
    },
    "AEREL": {
        "description": "Causality / relationship to study drug",
        "values": ["NONE", "REMOTE", "POSSIBLE", "PROBABLE"],
        "case": "upper",
    },
    "ACTARM": {
        "description": "Actual treatment arm",
        "case": "casefold",
    },
}

# Columns the LLM is allowed to pick as ``target_column``.
# USUBJID is intentionally excluded - it is what we *return*, not what we filter on.
ALLOWED_TARGET_COLUMNS: tuple[str, ...] = tuple(COLUMN_INFO.keys())
