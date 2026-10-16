"""WealthSync backend - SMS transaction classification service.

Thin adapter over the `sms` package: a two-stage TfidfVectorizer +
MultinomialNB pipeline (spam/noise filter -> credit/debit/other categoriser).
Artifacts live in `sms/artifacts/`; the pipeline is trained once and cached.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sms import sms_classifier


def classify_sms(text: str) -> Dict[str, Any]:
    """Classify one raw SMS message."""
    return sms_classifier.classify(text)


def classify_sms_batch(messages: List[str]) -> List[Dict[str, Any]]:
    """Classify a batch of raw SMS messages (order preserved)."""
    return sms_classifier.classify_batch(messages)


def sms_health() -> Dict[str, Any]:
    """Availability + metadata for the SMS pipeline."""
    return sms_classifier.health()
