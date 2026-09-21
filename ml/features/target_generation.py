"""WealthSync - documented target / label generation (Models 1-5).

IMPORTANT (Requirements sections 7, 8, 9):
No real-world risk labels, wellness ground-truth or independently-verified
"best payment method" exists in the source dataset. Every target produced here
is either

  * a **forecasting target** (Models 1 & 2): future observed amount/savings --
    NOT rule-derived, uses the actual next-month value; or
  * a **RULE-DERIVED LABEL** (Models 3, 4, 5): generated from deterministic,
    documented scoring rules. These must never be presented as ground truth.

Each rule is written below next to the function that uses it.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def add_future_targets(features: pd.DataFrame) -> pd.DataFrame:
    """Attach Models 1 & 2 targets (future values), per user.

    * future_expense  = expense of month t+1   (Model 1 - spending prediction)
    * future_savings  = savings of month t+1   (Model 2 - savings prediction)

    savings is the documented approximation income-expense (see
    feature_engineering.build_monthly_features).
    Rows whose user has no month t+1 get NaN and are dropped by callers.
    """
    df = features.sort_values(["user_id", "ym_dt"]).copy()
    g = df.groupby("user_id", sort=False)
    df["future_expense"] = g["expense"].shift(-1)
    df["future_savings"] = g["savings"].shift(-1)
    return df


# ---------------------------------------------------------------------------
# Model 3 - Financial Wellness Score (rule-derived, documented)
# ---------------------------------------------------------------------------

def wellness_score(df: pd.DataFrame) -> pd.Series:
    """Financial Wellness Score in [0, 100] - RULE-DERIVED LABEL.

    The model cannot know what "wellness" means, so it is DEFINED here:
    a household is healthier when it spends a smaller share of income, saves
    more, keeps committed (rent) burden low and has stable monthly income and
    spending. Start = 50, then add/subtract per rule, clipped to [0, 100]:

    +20 expense ratio < 0.50             |  -15 expense ratio > 0.90
    +12 expense ratio 0.50-0.70          |   (0.70-0.90 -> +5)
    +15 savings ratio > 0.20             |  -15 savings ratio < 0
    + 8 savings ratio 0.10-0.20          |   (0.00-0.10 -> 0)
    +10 positive monthly cash flow       |  -10 negative cash flow
    + 5 rent burden < 0.30               |   -5 rent burden > 0.50
    + 5 spending stability >= 0.70       |   -5 spending stability <= 0.35
    + 5 income stability  >= 0.70        |   -5 income stability  <= 0.35
    """
    def rng_bonus(series, lo, hi, amount):
        return np.where(series.eq(0) | series.isna(), 0.0,
                        np.where((series >= lo) & (series < hi), amount, 0.0))

    score = np.full(len(df), 50.0)

    er = df["expense_ratio"].replace(0, np.nan)
    score += rng_bonus(er, 0.0, 0.50, 20.0)
    score += rng_bonus(er, 0.50, 0.70, 12.0)
    score += rng_bonus(er, 0.70, 0.90, 5.0)
    score += np.where(er > 0.90, -15.0, 0.0)

    sr = df["savings_ratio"].replace(0, np.nan)
    score += rng_bonus(sr, 0.20, np.inf, 15.0)
    score += rng_bonus(sr, 0.10, 0.20, 8.0)
    score += np.where(sr < 0, -15.0, 0.0)

    cf = df["cash_flow"].fillna(0)
    score += np.where(cf > 0, 10.0, -10.0)

    rb = df["rent_burden"].replace(0, np.nan)
    score += np.where((rb > 0) & (rb < 0.30), 5.0, 0.0)
    score += np.where(rb > 0.50, -5.0, 0.0)

    st = df["spending_stability"].fillna(0.5)
    sti = df["income_stability"].fillna(0.5)
    score += np.where(st >= 0.70, 5.0, np.where(st <= 0.35, -5.0, 0.0))
    score += np.where(sti >= 0.70, 5.0, np.where(sti <= 0.35, -5.0, 0.0))

    return pd.Series(np.clip(score, 0, 100).round(0).astype(int), index=df.index)


# ---------------------------------------------------------------------------
# Model 4 - Financial Risk (rule-derived, documented)
# ---------------------------------------------------------------------------

def risk_flag(df: pd.DataFrame) -> pd.Series:
    """Financial Risk binary label - RULE-DERIVED LABEL.

    1 = HIGH RISK if any of the following hold in the trailing 6 months
        (current month included):

       R1  negative cash flow in >= 3 of the last 6 months
       R2  expense_ratio > 1.0 AND savings_ratio < 0  (spending beyond means)
       R3  income volatility (std/mean over 6 months) > 0.60 AND cash flow < 0
       R4  spending volatility (std/mean over 6 months) > 1.0 AND cash flow < 0

    0 = LOW RISK otherwise. Documented; not ground truth.
    """
    uid = df["user_id"]
    val = pd.DataFrame(index=df.index)

    cash_flow = df["cash_flow"]
    expense = df["expense"]
    income = df["income"]

    for lag in range(6):
        val[f"cf_{lag}"] = cash_flow.groupby(uid, sort=False).shift(lag)
        val[f"exp_{lag}"] = expense.groupby(uid, sort=False).shift(lag)
        val[f"inc_{lag}"] = income.groupby(uid, sort=False).shift(lag)

    cf6 = val[[f"cf_{i}" for i in range(6)]].fillna(0)
    exp6 = val[[f"exp_{i}" for i in range(6)]]
    inc6 = val[[f"inc_{i}" for i in range(6)]]

    r1 = (cf6 < 0).sum(axis=1) >= 3
    er = df["expense_ratio"]
    sr = df["savings_ratio"]
    r2 = (er > 1.0) & (sr < 0)
    inc_mean = inc6.mean(axis=1).replace(0, np.nan)
    inc_cv = inc6.std(axis=1) / inc_mean
    r3 = (inc_cv.fillna(0) > 0.60) & (df["cash_flow"] < 0)
    exp_mean = exp6.mean(axis=1).replace(0, np.nan)
    exp_cv = exp6.std(axis=1) / exp_mean
    r4 = (exp_cv.fillna(0) > 1.0) & (df["cash_flow"] < 0)

    return pd.Series((r1 | r2 | r3 | r4).astype(int), index=df.index)


# ---------------------------------------------------------------------------
# Model 5 - Best Payment Method (observed-behaviour target)
# ---------------------------------------------------------------------------

PAYMENT_METHODS = ["UPI", "Debit Card", "Cash", "Bank Transfer"]


def payment_method_target(txn_features: pd.DataFrame) -> pd.Series:
    """Best-payment-method target for Model 5.

    The dataset has no independent ground truth for "best". The target is the
    payment mode *actually used* on each transaction. Interpretation
    (documented): a rational user picks a method based on transaction size,
    category, and available cash flow; the model learns that suitability
    function. This is an observed-behaviour label, not verified ground truth.
    """
    return txn_features["payment_mode"].astype(str)