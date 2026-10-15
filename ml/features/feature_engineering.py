"""WealthSync - documented feature engineering.

Two trackers:

1. Monthly features (Models 1-4) built from ``data/processed/user_monthly.csv``.
2. Transaction features (Model 5) built from ``data/processed/transactions_clean.csv``.

Every derived feature is a unit-tested, pure function of *past* data only
(lags / running aggregates) so no future information leaks into a row.
"""

from __future__ import annotations

import numpy as np
import pandas as pd


def safe_div(a: pd.Series, b: pd.Series, fill: float = 0.0) -> pd.Series:
    """Division that returns ``fill`` instead of inf/NaN (divide-by-zero guard)."""
    out = a.astype(float) / b.replace(0, np.nan).astype(float)
    return out.fillna(fill).replace([np.inf, -np.inf], fill)


def spending_stability(values: pd.Series, users: pd.Series, months: list[int]) -> pd.Series:
    """Stability degrades as coefficient-of-variation of recent monthly spend grows.

    stability = 1 / (1 + cv); cv = std / mean of the given monthly expenses.
    Computed per user (group-aware) using only past months, never future ones.
    """
    def _stability(s: pd.Series) -> pd.Series:
        mat = np.column_stack([s.shift(m).values for m in months])
        mean = np.nanmean(mat, axis=1)
        std = np.nanstd(mat, axis=1)
        cv = np.where(mean > 1e-6, std / np.where(mean > 0, mean, 1.0), 0.0)
        return pd.Series(1.0 / (1.0 + cv), index=s.index)

    return values.groupby(users, sort=False).transform(_stability)


def build_monthly_features(df: pd.DataFrame) -> pd.DataFrame:
    """Build the feature table used by Models 1-4.

    df: user_monthly output of data/prepare_data.py. Must be sorted per user
        by month (ym_dt). Returns a DataFrame indexed by (user_id, ym_dt).
    """
    base = df.sort_values(["user_id", "ym_dt"]).copy()

    f = pd.DataFrame(index=base.index)
    # NOTE: these are already per user-month values; copy them as-is.
    # (A previous version used groupby().transform("sum") which wrongly turned
    # them into per-user LIFETIME totals and collapsed feature+target to a
    # constant per user.)
    f["income"] = base["income"].astype(float).to_numpy()
    f["expense"] = base["expense"].astype(float).to_numpy()
    f["txn_count"] = base["txn_count"].to_numpy()
    f["avg_txn_amount"] = base["avg_txn_amount"].astype(float).to_numpy()

    g = base.groupby("user_id", sort=False)

    f["cash_flow"] = f["income"] - f["expense"]
    f["expense_ratio"] = safe_div(f["expense"], f["income"])
    # NOTE: the source dataset has no savings field. Savings is defined as
    # month income - month expense (documented approximation).
    f["savings"] = f["cash_flow"]
    f["savings_ratio"] = safe_div(f["savings"], f["income"])
    f["rent_burden"] = safe_div(base["cat_spend_Rent"].astype(float), f["income"])

    for c in sorted(base.columns):
        if c.startswith("cat_spend_"):
            f[c.replace("cat_spend_", "cat_")] = base[c].astype(float)

    # --- lagged (past) features -------------------------------------------
    for m, name in ((1, "income_1m"), (2, "income_2m"), (1, "expense_1m"), (2, "expense_2m")):
        f[name] = g["income" if name.startswith("income") else "expense"].shift(m)
    f["cash_flow_1m"] = f["cash_flow"].groupby(base["user_id"], sort=False).shift(1)
    f["expense_ratio_1m"] = f["expense_ratio"].groupby(base["user_id"], sort=False).shift(1)
    f["savings_1m"] = f["savings"].groupby(base["user_id"], sort=False).shift(1)

    # --- rolling 3-month windows (exclude current month) ------------------
    m3 = [1, 2, 3]
    f["expense_3m_mean"] = f["expense"].groupby(base["user_id"], sort=False).transform(
        lambda s: s.shift(1).rolling(3, min_periods=1).mean()
    )
    f["income_3m_mean"] = f["income"].groupby(base["user_id"], sort=False).transform(
        lambda s: s.shift(1).rolling(3, min_periods=1).mean()
    )
    f["cash_flow_3m_mean"] = f["cash_flow"].groupby(base["user_id"], sort=False).transform(
        lambda s: s.shift(1).rolling(3, min_periods=1).mean()
    )
    f["savings_3m_mean"] = f["savings"].groupby(base["user_id"], sort=False).transform(
        lambda s: s.shift(1).rolling(3, min_periods=1).mean()
    )

    # --- trends & stability -----------------------------------------------
    f["income_trend"] = f["income_1m"] - f["income_2m"]
    f["expense_trend"] = f["expense_1m"] - f["expense_2m"]
    f["spending_stability"] = spending_stability(f["expense"], base["user_id"], [1, 2, 3])
    f["income_stability"] = spending_stability(f["income"], base["user_id"], [1, 2, 3])

    f["user_id"] = base["user_id"].values
    f["ym_dt"] = base["ym_dt"].values
    f["month"] = base["month"].values
    f["year"] = base["year"].values
    return f


def build_transaction_features(txn: pd.DataFrame) -> pd.DataFrame:
    """Feature table for Model 5 (one row = one expense transaction).

    Only past/current-time information is used:
      - transaction amount, category, timing (month, day, weekend)
      - user running monthly income/expense *before* this transaction
      - user historical payment-method counts *before* this transaction
    """
    txn = txn.sort_values(["user_id", "date"]).copy()
    txn = txn[txn["transaction_type"] == "expense"].copy()
    txn = txn.reset_index(drop=True)

    f = pd.DataFrame(index=txn.index)
    f["amount"] = txn["amount"].astype(float)
    f["month"] = txn["date"].dt.month
    f["day_of_month"] = txn["date"].dt.day
    f["is_weekend"] = txn["date"].dt.weekday.isin([5, 6]).astype(int)

    # running monthly income / expense *before* this txn (per user)
    amt = (txn["amount"].astype(float) * (txn["transaction_type"] == "income")) - (
        txn["amount"].astype(float) * (txn["transaction_type"] == "expense")
    )
    f["month_cash_flow_so_far"] = (
        amt.groupby([txn["user_id"], txn["ym"]]).cumsum() - amt
    )

    income_amt = txn["amount"].astype(float) * (txn["transaction_type"] == "income")
    f["month_income_so_far"] = (
        income_amt.groupby([txn["user_id"], txn["ym"]]).cumsum() - income_amt
    )

    # historical payment-method counts before this transaction
    for method in ["UPI", "Debit Card", "Cash", "Bank Transfer"]:
        ind = (txn["payment_mode"] == method).astype(int)
        f[f"hist_{method.replace(' ', '_')}"] = (
            ind.groupby(txn["user_id"]).cumsum() - ind
        )
    f["hist_total"] = txn.groupby("user_id").cumcount()

    # user's cumulative spending on this category BEFORE the transaction
    # (vectorised; a DataFrame.apply version misaligned on non-contiguous
    # indexes and produced all-NaN in this pandas build)
    cat_labels = txn["category"].astype(str).str.replace(" ", "_")
    wide = (txn[["user_id", "amount"]]
            .assign(_cat=cat_labels)
            .pivot_table(index=txn.index, columns="_cat", values="amount",
                         aggfunc="sum", fill_value=0.0))
    wide = wide.reindex(columns=sorted(cat_labels.unique()), fill_value=0.0)
    cat_prev = wide.groupby(txn["user_id"], sort=False).cumsum() - wide
    for c in sorted(cat_labels.unique()):
        f[f"cat_cum_{c}"] = cat_prev[c].to_numpy()

    f["user_id"] = txn["user_id"].values
    f["date"] = txn["date"].values
    f["ym"] = txn["ym"].values
    f["category"] = txn["category"].values
    f["payment_mode"] = txn["payment_mode"].values  # target
    return f