"""WealthSync SMS financial-transaction classifier (two-stage pipeline).

Stage 1 - spam / noise filter: binary target, ``0`` = legitimate, ``1`` = spam.
Stage 2 - category classifier: ``credit`` / ``debit`` / ``other``.

Both stages are ``TfidfVectorizer(ngram_range=(1, 2))`` +
``MultinomialNB(alpha=0.1)``, trained once on the labelled dataset below and
persisted to ``sms/artifacts/`` so the API never retrains on boot.

The preprocessing rules, dataset and hyper-parameters are preserved verbatim
from the training notebook so the served model is the trained model.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics import accuracy_score
from sklearn.naive_bayes import MultinomialNB

ARTIFACTS_DIR = Path(__file__).resolve().parent / "artifacts"

# Stage labels surfaced to clients.
SPAM_STATUS = "DISCARDED (SPAM/NOISE)"
TRANSACTION_STATUS = "APPROVED (TRANSACTION)"
CATEGORY_DISPLAY = {"credit": "Credit", "debit": "Debit", "other": "Other"}

# ---------------------------------------------------------------------------
# Labelled dataset (verbatim from the training notebook)
# ---------------------------------------------------------------------------

CATEGORY_SMS: List[str] = [
    "Dear Customer, your Acct XX123 has been Debited by USD 45.00 on 12-Oct. Info: WALMART.",
    "Your VIsa Card ending in 4321 was charged USD 12.50 at STARBUCKS.",
    "Acct XX987 Credited with USD 1500.00 on 01-Nov for SALARY.",
    "Txn of USD 250.00 completed on your Credit Card. Available limit: USD 5000.",
    "Hey, are we still meeting for lunch today at 1 PM?",
    "Your OTP for logging into WealthSync is 584930. Do not share this with anyone.",
    "Congratulations! You have won a free gift card. Click here to claim.",
    "Alert: Your utility bill payment of USD 85.00 is due by tomorrow.",
    "USD 500.00 transfer to John Doe successful from Account XX772.",
    "Refund of USD 19.99 processed to your card on Amazon Prime.",
    "Don't forget to bring the documents for the project tomorrow.",
    "Your bank account XX445 has been credited with USD 120.00.",
    "You have received a credit of USD 250.00 from John.",
    "Salary of USD 3000.00 credited to your account.",
    "You sent USD 15.00 to Coffee Shop using Apple Pay.",
    "Your monthly paycheck was deposited successfully into checking.",
    "You made a purchase of USD 45.00 on your card.",
    "Money received! USD 50.00 has been deposited to your wallet.",
]
CATEGORY_LABELS: List[str] = [
    "debit", "debit", "credit", "debit", "other", "other", "other", "debit",
    "debit", "credit", "other", "credit", "credit", "credit", "debit", "credit",
    "debit", "credit",
]

SPAM_SMS: List[str] = [
    # Legitimate transactions
    "Dear Customer, your Acct XX123 has been Debited by USD 45.00 on 12-Oct.",
    "Your Visa Card was charged USD 12.50 at STARBUCKS.",
    "Acct XX987 Credited with USD 1500.00 on 01-Nov for SALARY.",
    "Your bank account XX445 has been credited with USD 120.00.",
    "Refund of USD 19.99 processed to your card on Amazon.",
    "You sent USD 15.00 to Coffee Shop using Apple Pay.",
    "Salary of USD 3000.00 credited to your account.",
    # Pure spam, promos & personal chats (noise)
    "Congratulations! You have won a free $1000 gift card. Claim now at https://prize.wealthsync.com/win.",
    "Get 50% off on all pizzas tonight! Call +1-555-0199 to order.",
    "Are we still meeting for lunch today at 1 PM?",
    "Your OTP for logging into WealthSync is 584930.",
    "ALERT: Suspicious login attempt detected on your social media account. Verify at http://scamlink.com.",
    "Hey buddy, don't forget to bring the documents tomorrow.",
]
SPAM_LABELS: List[int] = [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]

# ---------------------------------------------------------------------------
# Preprocessing (verbatim from the training notebook)
# ---------------------------------------------------------------------------

_URL_RE = re.compile(
    r"https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}"
    r"\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)"
)
_PHONE_RE = re.compile(r"\b\+?\d{1,3}[-.\s]?\d{3,4}[-.\s]?\d{4,9}\b")
_ISOLATED_NUM_RE = re.compile(r"\b\d+\b")
_PUNCT_RE = re.compile(r"[^\w\s\[\]]")


def preprocess_text(text: str) -> str:
    """Lowercase, normalise URLs/phones to tokens, strip numbers & punctuation."""
    text = text.lower()
    text = _URL_RE.sub(" [url] ", text)
    text = _PHONE_RE.sub(" [phone] ", text)
    text = _ISOLATED_NUM_RE.sub("", text)
    text = _PUNCT_RE.sub("", text)
    return " ".join(text.split())


# ---------------------------------------------------------------------------
# Two-stage classifier
# ---------------------------------------------------------------------------


class SmsClassifier:
    """Two-stage SMS pipeline: spam filter, then credit/debit/other categoriser."""

    def __init__(
        self,
        spam_vectorizer: TfidfVectorizer,
        spam_model: MultinomialNB,
        category_vectorizer: TfidfVectorizer,
        category_model: MultinomialNB,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.spam_vectorizer = spam_vectorizer
        self.spam_model = spam_model
        self.category_vectorizer = category_vectorizer
        self.category_model = category_model
        self.metadata = metadata or {}

    # -- training / persistence --------------------------------------------

    @classmethod
    def train(cls) -> "SmsClassifier":
        """Fit both stages on the labelled dataset (deterministic, no RNG)."""
        spam_vectorizer = TfidfVectorizer(ngram_range=(1, 2))
        spam_matrix = spam_vectorizer.fit_transform(
            [preprocess_text(s) for s in SPAM_SMS]
        )
        spam_model = MultinomialNB(alpha=0.1)
        spam_model.fit(spam_matrix, SPAM_LABELS)

        category_vectorizer = TfidfVectorizer(ngram_range=(1, 2))
        category_matrix = category_vectorizer.fit_transform(
            [preprocess_text(s) for s in CATEGORY_SMS]
        )
        category_model = MultinomialNB(alpha=0.1)
        category_model.fit(category_matrix, CATEGORY_LABELS)

        metadata: Dict[str, Any] = {
            "algorithm": "MultinomialNB(alpha=0.1) + TfidfVectorizer(ngram_range=(1, 2))",
            "stages": ["spam_filter", "categorizer"],
            "spam_classes": [int(c) for c in spam_model.classes_],
            "category_classes": [str(c) for c in category_model.classes_],
            "spam_train_samples": len(SPAM_SMS),
            "category_train_samples": len(CATEGORY_SMS),
            "spam_train_accuracy": round(
                float(accuracy_score(SPAM_LABELS, spam_model.predict(spam_matrix))), 4
            ),
            "category_train_accuracy": round(
                float(
                    accuracy_score(
                        CATEGORY_LABELS, category_model.predict(category_matrix)
                    )
                ),
                4,
            ),
            "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        return cls(spam_vectorizer, spam_model, category_vectorizer, category_model, metadata)

    def save(self, directory: Path = ARTIFACTS_DIR) -> Path:
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        joblib.dump(self.spam_vectorizer, directory / "spam_vectorizer.joblib")
        joblib.dump(self.spam_model, directory / "spam_model.joblib")
        joblib.dump(self.category_vectorizer, directory / "category_vectorizer.joblib")
        joblib.dump(self.category_model, directory / "category_model.joblib")
        (directory / "metadata.json").write_text(
            json.dumps(self.metadata, indent=2), encoding="utf-8"
        )
        return directory

    @classmethod
    def load(cls, directory: Path = ARTIFACTS_DIR) -> "SmsClassifier":
        directory = Path(directory)
        meta_path = directory / "metadata.json"
        metadata = json.loads(meta_path.read_text("utf-8")) if meta_path.exists() else {}
        return cls(
            joblib.load(directory / "spam_vectorizer.joblib"),
            joblib.load(directory / "spam_model.joblib"),
            joblib.load(directory / "category_vectorizer.joblib"),
            joblib.load(directory / "category_model.joblib"),
            metadata,
        )

    @classmethod
    def artifacts_exist(cls, directory: Path = ARTIFACTS_DIR) -> bool:
        directory = Path(directory)
        return all(
            (directory / name).exists()
            for name in (
                "spam_vectorizer.joblib",
                "spam_model.joblib",
                "category_vectorizer.joblib",
                "category_model.joblib",
            )
        )

    @classmethod
    def load_or_train(cls, directory: Path = ARTIFACTS_DIR) -> "SmsClassifier":
        """Load persisted artifacts, training (and persisting) once if absent."""
        if cls.artifacts_exist(directory):
            return cls.load(directory)
        classifier = cls.train()
        classifier.save(directory)
        return classifier

    # -- inference ----------------------------------------------------------

    @staticmethod
    def _percentages(model: MultinomialNB, matrix) -> Dict[str, float]:
        proba = model.predict_proba(matrix)[0]
        return {
            str(label): round(float(p) * 100, 2)
            for label, p in zip(model.classes_, proba)
        }

    def classify(self, raw_sms: str) -> Dict[str, Any]:
        """Classify one raw SMS. Returns a JSON-friendly dict."""
        text = (raw_sms or "").strip()
        if not text:
            raise ValueError("SMS text is empty")

        cleaned = preprocess_text(text)
        spam_matrix = self.spam_vectorizer.transform([cleaned])
        spam_pred = int(self.spam_model.predict(spam_matrix)[0])
        spam_proba = self.spam_model.predict_proba(spam_matrix)[0]
        # P(spam) is the probability of class 1, regardless of the prediction.
        spam_probability = round(
            float(spam_proba[list(self.spam_model.classes_).index(1)]) * 100, 2
        )
        is_spam = spam_pred == 1

        if is_spam:
            return {
                "text": text,
                "is_spam": True,
                "is_transaction": False,
                "status": SPAM_STATUS,
                "category": "N/A",
                "display_category": "Spam / Noise",
                "confidence": spam_probability,
                "spam_probability": spam_probability,
                "category_probabilities": {},
            }

        category_matrix = self.category_vectorizer.transform([cleaned])
        category = str(self.category_model.predict(category_matrix)[0])
        category_proba = self.category_model.predict_proba(category_matrix)[0]
        cat_idx = list(self.category_model.classes_).index(category)
        confidence = round(float(category_proba[cat_idx]) * 100, 2)

        return {
            "text": text,
            "is_spam": False,
            "is_transaction": True,
            "status": TRANSACTION_STATUS,
            "category": category,
            "display_category": CATEGORY_DISPLAY.get(category, category.title()),
            "confidence": confidence,
            "spam_probability": spam_probability,
            "category_probabilities": self._percentages(
                self.category_model, category_matrix
            ),
        }

    def classify_batch(self, messages: List[str]) -> List[Dict[str, Any]]:
        return [self.classify(message) for message in messages]


# ---------------------------------------------------------------------------
# Process-wide singleton
# ---------------------------------------------------------------------------

_classifier: Optional[SmsClassifier] = None


def get_classifier() -> SmsClassifier:
    """Return the cached pipeline, loading (or training once) on first use."""
    global _classifier
    if _classifier is None:
        _classifier = SmsClassifier.load_or_train()
    return _classifier


def classify(raw_sms: str) -> Dict[str, Any]:
    return get_classifier().classify(raw_sms)


def classify_batch(messages: List[str]) -> List[Dict[str, Any]]:
    return get_classifier().classify_batch(messages)


def health() -> Dict[str, Any]:
    classifier = get_classifier()
    return {
        "status": "available",
        "kind": "text_classification",
        "stages": classifier.metadata.get("stages", ["spam_filter", "categorizer"]),
        "categories": classifier.metadata.get("category_classes", []),
        "algorithm": classifier.metadata.get("algorithm"),
        "artifacts": str(ARTIFACTS_DIR),
    }
