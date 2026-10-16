"""Pydantic schemas for WealthSync ML API."""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict, Any, List
import json
from pathlib import Path

ML_MODELS_DIR = Path(__file__).resolve().parents[1] / "ml" / "models"


def _load_feature_columns(model_dir: str) -> List[str]:
    """Load raw input columns from feature_columns.json."""
    path = ML_MODELS_DIR / model_dir / "feature_columns.json"
    if path.exists():
        data = json.loads(path.read_text())
        return data.get("raw_input_columns", [])
    return []


SPENDING_FEATURES = _load_feature_columns("spending/random forest")
RISK_FEATURES = _load_feature_columns("risk/gradient boosting")


class SpendingPredictRequest(BaseModel):
    """Request schema for spending prediction."""
    
    age_ref: float = Field(..., description="Age of reference person")
    age2: float = Field(..., description="Age squared")
    fam_size: float = Field(..., description="Family size")
    educ_ref: float = Field(..., description="Education of reference person")
    seq: float = Field(..., description="Interview sequence number")
    totexppq: float = Field(..., description="Total expenditure previous quarter")
    foodpq: float = Field(..., description="Food expenditure previous quarter")
    houspq: float = Field(..., description="Housing expenditure previous quarter")
    transpq: float = Field(..., description="Transportation expenditure previous quarter")
    utilpq: float = Field(..., description="Utilities expenditure previous quarter")
    sheltpq: float = Field(..., description="Shelter expenditure previous quarter (exact spelling: sheltpq)")
    itbi_q_income: float = Field(..., description="Income before taxes quarterly")
    cuincome_class: float = Field(..., description="Consumer unit income class")
    total_spend_lag1: float = Field(..., description="Total spending lag 1")
    total_spend_pastmean: float = Field(..., description="Total spending past mean")
    total_spend_paststd: float = Field(..., description="Total spending past std (must be present, imputer handles NaN)")
    food_lag1: float = Field(..., description="Food spending lag 1")
    housing_lag1: float = Field(..., description="Housing spending lag 1")
    income_lag1: float = Field(..., description="Income lag 1")
    fam_type: float = Field(..., description="Family type (categorical)")
    cutenure: float = Field(..., description="Consumer unit tenure (categorical)")
    bls_urbn: float = Field(..., description="BLS urban/rural classification (categorical)")

    model_config = {"extra": "forbid"}

    @classmethod
    def required_fields(cls) -> List[str]:
        return SPENDING_FEATURES


class SpendingPredictResponse(BaseModel):
    """Response schema for spending prediction."""
    
    success: bool = True
    data: Dict[str, Any]
    error: Optional[Dict[str, str]] = None


class RiskPredictRequest(BaseModel):
    """Request schema for risk prediction."""
    
    LIMIT_BAL: float = Field(..., description="Limit balance")
    AGE: float = Field(..., description="Age")
    PAY_0: float = Field(..., description="Repayment status September")
    PAY_2: float = Field(..., description="Repayment status August")
    PAY_3: float = Field(..., description="Repayment status July")
    PAY_4: float = Field(..., description="Repayment status June")
    PAY_5: float = Field(..., description="Repayment status May")
    PAY_6: float = Field(..., description="Repayment status April")
    BILL_AMT1: float = Field(..., description="Bill amount September")
    BILL_AMT2: float = Field(..., description="Bill amount August")
    BILL_AMT3: float = Field(..., description="Bill amount July")
    BILL_AMT4: float = Field(..., description="Bill amount June")
    BILL_AMT5: float = Field(..., description="Bill amount May")
    BILL_AMT6: float = Field(..., description="Bill amount April")
    PAY_AMT1: float = Field(..., description="Payment amount September")
    PAY_AMT2: float = Field(..., description="Payment amount August")
    PAY_AMT3: float = Field(..., description="Payment amount July")
    PAY_AMT4: float = Field(..., description="Payment amount June")
    PAY_AMT5: float = Field(..., description="Payment amount May")
    PAY_AMT6: float = Field(..., description="Payment amount April")
    util_mean6: float = Field(..., description="Mean utilization ratio 6 months")
    repay_ratio_mean6: Optional[float] = Field(None, description="Mean repayment ratio 6 months (can be NaN)")
    max_delinq_6m: float = Field(..., description="Max delinquency 6 months")
    SEX: float = Field(..., description="Sex (categorical: 1=male, 2=female)")
    EDUCATION: float = Field(..., description="Education (categorical)")
    MARRIAGE: float = Field(..., description="Marriage (categorical)")

    model_config = {"extra": "forbid"}

    @classmethod
    def required_fields(cls) -> List[str]:
        return [f for f in RISK_FEATURES if f != "repay_ratio_mean6"]


class RiskPredictResponse(BaseModel):
    """Response schema for risk prediction."""
    
    success: bool = True
    data: Dict[str, Any]
    error: Optional[Dict[str, str]] = None


class ModelHealthResponse(BaseModel):
    """Response schema for model health check."""
    
    success: bool = True
    models: Dict[str, Dict[str, Any]]
    error: Optional[Dict[str, str]] = None


class ErrorResponse(BaseModel):
    """Standard error response."""
    
    success: bool = False
    error: Dict[str, str]
    data: Optional[Dict[str, Any]] = None


# ---------------------------------------------------------------------------
# SMS transaction classifier (two-stage text pipeline)
# ---------------------------------------------------------------------------


class SmsClassifyRequest(BaseModel):
    """Request schema for a single SMS classification."""

    text: str = Field(..., description="Raw SMS message text")

    model_config = {"extra": "forbid"}

    @field_validator("text")
    @classmethod
    def _non_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("SMS text must not be empty")
        return value


class SmsBatchClassifyRequest(BaseModel):
    """Request schema for batch SMS classification."""

    messages: List[str] = Field(..., min_length=1, description="Raw SMS messages")

    model_config = {"extra": "forbid"}

    @field_validator("messages")
    @classmethod
    def _non_empty_items(cls, values: List[str]) -> List[str]:
        if not values:
            raise ValueError("messages must contain at least one SMS")
        cleaned = [v.strip() for v in values]
        if any(not v for v in cleaned):
            raise ValueError("SMS messages must not be empty")
        return cleaned


class SmsClassifyResponse(BaseModel):
    """Response schema for SMS classification (single or batch)."""

    success: bool = True
    data: Dict[str, Any]
    error: Optional[Dict[str, str]] = None