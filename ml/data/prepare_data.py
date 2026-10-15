"""WealthSync - Data preparation for the 5 core ML models.

Source dataset: Dataset/budgetwise_finance_dataset.csv
  - Transaction-level records: user_id, date, transaction_type, category,
    amount, payment_mode, location, notes
  - 150 users x 48 months (2021-01 .. 2024-12), ~15,900 rows

Outputs (ml/data/processed/):
  transactions_clean.csv   -> transaction-level work table (Model 5)
  user_monthly.csv         -> user-month aggregates (Models 1-4)

Design notes
------------
* Raw data is noisy / synthetic with typos (e.g. "Bank Transfr", "Fod",
  "3-1-23" style dates). Values are normalised here.
* Amount column contains mixed types -> coerced to numeric.
* Amount outliers: the synthetic source injects exact-round anomalies
  (999,999,999 x66 and 1,000,000 x78). Amounts are winsorized at 500,000 to
  neutralise them while preserving the real distribution (99.5% of values lie
  below 500,000). This is a documented, defensible winsorisation.
* Inconsistent case/spelling of payment_mode and category are mapped to a
  small set of canonical values. Anything unmapped falls back to 'Other'.
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

RAW_CSV = Path(__file__).resolve().parents[2] / "Dataset" / "budgetwise_finance_dataset.csv"
PROCESSED_DIR = Path(__file__).resolve().parent / "processed"

# Winsorisation cap for transaction amounts (see header docstring).
AMOUNT_CAP = 500_000.0

# NOTE: the source dataset only distinguishes generic "card" (CARD/Card/CRD/
# Crd). It does NOT separate credit vs debit, and contains no wallet entries.
# Bare card variants are therefore mapped to "Debit Card" (documented
# adaptation). Final target classes: UPI, Debit Card, Cash, Bank Transfer.
PAYMENT_MODE_ALIASES = {
    "UPI": ["upi", "upis", "paytm", "phonepe", "gpay", "gpayp"],
    "Debit Card": ["card", "crd", "debit card", "debitcard"],
    "Cash": ["cash", "csh"],
    "Bank Transfer": ["bank transfer", "banktransfer", "bank transfr", "bank_transfer", "neft", "imps", "rtgs"],
}

CATEGORY_ALIASES = {
    "Food": ["food", "foods", "foodd", "fod", "grocery", "groceries", "restaurant", "dining", "dining out", "swiggy", "zomato"],
    "Rent": ["rent", "rentt", "rnt", "housing", "accomodation", "accommodation"],
    "Shopping": ["shopping", "shop", "clothing", "apparel", "electronics"],
    "Transport": ["transport", "transportation", "fuel", "petrol", "diesel", "uber", "ola", "metro", "bus"],
    "Entertainment": ["entertainment", "entertain", "entrtnmnt", "movies", "ott", "netflix", "spotify", "gaming"],
    "Bills": ["bills", "bill"],
    "Utilities": ["utilities", "utility", "utlities", "utilties", "electricity", "water", "gas", "wifi", "internet"],
    "Healthcare": ["health", "healthcare", "helth", "doctor", "hospital", "pharmacy", "medical"],
    "Education": ["education", "educaton", "edu", "course", "books", "tuition"],
    "Travel": ["travel", "traval", "flight", "hotel", "trips"],
    "Salary": ["salary", "sal"],
    "Freelance": ["freelance", "freelancing", "contract"],
    "Bonus": ["bonus", "incentive"],
    "Investment": ["investment", "invest", "stock", "mutual fund", "sip"],
    "Savings": ["savings", "saving", "deposit", "fd"],
    "Other": ["other", "others", "misc", "miscellaneous", "others", "personal"],
}

TRANSACTION_TYPE_ALIASES = {"income": ["income", "credit", "in"], "expense": ["expense", "debit", "out", "ex"]}


def _map_aliases(value: object, table: dict[str, list[str]], default: str) -> str:
    if pd.isna(value):
        return default
    v = str(value).strip().lower()
    for canonical, aliases in table.items():
        if v in aliases or v == canonical.lower():
            return canonical
    return default


def _parse_amount(value: object) -> float:
    if pd.isna(value):
        return float("nan")
    s = str(value).strip().upper()
    s = s.replace(",", "").replace("₹", "").replace("RS ", "").replace("$", "").replace("USD ", "")
    if re.search(r"[A-Z]", s):
        return float("nan")
    try:
        return float(s)
    except ValueError:
        return float("nan")


def _parse_date(value: object) -> pd.Timestamp | pd.NaT:
    if pd.isna(value):
        return pd.NaT
    s = str(value).strip()
    return pd.to_datetime(s, format="mixed", dayfirst=False, errors="coerce")


def load_raw() -> pd.DataFrame:
    df = pd.read_csv(RAW_CSV)
    df["amount"] = df["amount"].map(_parse_amount)
    df["date"] = df["date"].map(_parse_date)
    df = df.dropna(subset=["date", "amount", "payment_mode"])
    df = df[df["amount"] > 0]
    df["amount"] = df["amount"].clip(upper=AMOUNT_CAP)
    df = df.drop_duplicates(subset=["transaction_id", "user_id", "date", "amount"], keep="first")
    df["transaction_type"] = df["transaction_type"].map(
        lambda v: _map_aliases(v, TRANSACTION_TYPE_ALIASES, "expense")
    )
    df["category"] = df["category"].map(lambda v: _map_aliases(v, CATEGORY_ALIASES, "Other"))
    df["payment_mode"] = df["payment_mode"].map(lambda v: _map_aliases(v, PAYMENT_MODE_ALIASES, "Other"))
    df["year"] = df["date"].dt.year
    df["month"] = df["date"].dt.month
    df["ym"] = df["date"].dt.to_period("M").astype(str)
    df = df[df["payment_mode"] != "Other"]
    return df.sort_values(["user_id", "date"]).reset_index(drop=True)


def build_user_monthly(txn: pd.DataFrame) -> pd.DataFrame:
    """Aggregate transactions to user-month totals (Models 1-4)."""
    rows = []
    for (uid, ym), g in txn.groupby(["user_id", "ym"], observed=True):
        income = float(g.loc[g["transaction_type"] == "income", "amount"].sum())
        expense = float(g.loc[g["transaction_type"] == "expense", "amount"].sum())
        cat_spend = {
            f"cat_spend_{cat}": float(g.loc[(g["transaction_type"] == "expense") & (g["category"] == cat), "amount"].sum())
            for cat in sorted(txn["category"].unique())
        }
        pay_counts = g["payment_mode"].value_counts().to_dict()
        row = {
            "user_id": uid,
            "ym": ym,
            "year": g["year"].iloc[0],
            "month": g["month"].iloc[0],
            "income": income,
            "expense": expense,
            "txn_count": int(len(g)),
            "avg_txn_amount": float(g["amount"].mean()),
            "payment_preference": pay_counts,
            **cat_spend,
        }
        rows.append(row)
    df = pd.DataFrame(rows).sort_values(["user_id", "ym"]).reset_index(drop=True)
    # keep only months that exist in alphabetical/chronological order per user
    df["ym_dt"] = pd.to_datetime(df["ym"].astype(str) + "-01")
    return df


def main() -> None:
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    txn = load_raw()
    txn.to_csv(PROCESSED_DIR / "transactions_clean.csv", index=False)

    monthly = build_user_monthly(txn)
    monthly.to_csv(PROCESSED_DIR / "user_monthly.csv", index=False)

    print("transactions_clean rows:", len(txn), "| users:", txn["user_id"].nunique())
    print("user_monthly rows:", len(monthly), "| users:", monthly["user_id"].nunique())
    print("monthly date range:", monthly["ym_dt"].min().date(), "->", monthly["ym_dt"].max().date())
    pay = txn["payment_mode"].value_counts()
    cat = txn["transaction_type"].value_counts()
    print("payment modes:", pay.to_dict())
    print("transaction types:", cat.to_dict())


if __name__ == "__main__":
    main()