"""WealthSync - shared data loading helpers."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

PROCESSED_DIR = Path(__file__).resolve().parent


def load_transactions() -> pd.DataFrame:
    return pd.read_csv(PROCESSED_DIR / "processed" / "transactions_clean.csv", parse_dates=["date"])


def load_user_monthly() -> pd.DataFrame:
    return pd.read_csv(PROCESSED_DIR / "processed" / "user_monthly.csv", parse_dates=["ym_dt"])