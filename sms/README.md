# SMS Transaction Classifier (`sms/`)

The `sms/` package provides a two-stage NLP text classification pipeline that automatically parses raw bank and payment SMS messages into structured ledger transactions.

---

## Two-Stage Pipeline Architecture

```
                       Raw SMS Message
                              │
                              ▼
                      preprocess_text()
         * Lowercase conversion
         * Mask URLs -> '[url]'
         * Mask phone numbers -> '[phone]'
         * Strip extraneous digits and symbols
                              │
                              ▼
            ┌───────────────────────────────────┐
            │   Stage 1: Spam / Noise Filter    │
            │   TF-IDF + MultinomialNB (a=0.1)  │
            └─────────────────┬─────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
      Is Spam? = YES                      Is Spam? = NO
            │                                   │
            ▼                                   ▼
     DISCARDED (SPAM/NOISE)     ┌───────────────────────────────────┐
     Category: N/A              │   Stage 2: Transaction Category   │
                                │   TF-IDF + MultinomialNB (a=0.1)  │
                                └─────────────────┬─────────────────┘
                                                  │
                                                  ▼
                                       credit | debit | other
                                       APPROVED (TRANSACTION)
```

Both stages use `TfidfVectorizer(ngram_range=(1, 2))` paired with `MultinomialNB(alpha=0.1)`. The artifacts are fitted once and persisted to disk. The backend loads them lazily and never retrains per request.

---

## Directory Structure

```
sms/
|-- sms_classifier.py            # Dataset, text preprocessing, and SmsClassifier class
|-- untitled7.py                 # Source training notebook
|-- __init__.py                  # Package initialization
|-- artifacts/                   # Serialized pipeline components
|   |-- spam_vectorizer.joblib   # Stage 1 TF-IDF vectorizer
|   |-- spam_model.joblib        # Stage 1 MultinomialNB model (0: Legitimate, 1: Spam)
|   |-- category_vectorizer.joblib# Stage 2 TF-IDF vectorizer
|   |-- category_model.joblib    # Stage 2 MultinomialNB model (credit, debit, other)
|   `-- metadata.json            # Model parameters, training counts, and accuracy
`-- README.md                    # SMS classification guide (this file)
```

---

## API Endpoints (`backend/sms_service.py`)

The pipeline is served by the FastAPI backend:

### 1. GET `/api/sms/health`
Check availability and class metadata:
```json
{
  "success": true,
  "sms": {
    "status": "available",
    "classes": ["credit", "debit", "other"],
    "train_samples": 42,
    "train_accuracy": 1.0
  }
}
```

### 2. POST `/api/sms/classify`
Classify a single SMS message.

**Request:**
```json
{
  "text": "ALERT: Acct *112 has been credited with USD 450.00."
}
```

**Response (Legitimate Transaction):**
```json
{
  "success": true,
  "data": {
    "text": "ALERT: Acct *112 has been credited with USD 450.00.",
    "is_spam": false,
    "is_transaction": true,
    "status": "APPROVED (TRANSACTION)",
    "category": "credit",
    "display_category": "Credit",
    "confidence": 94.56,
    "spam_probability": 0.95,
    "category_probabilities": {
      "credit": 94.56,
      "debit": 3.4,
      "other": 2.04
    }
  }
}
```

**Response (Discarded Spam / Promotion):**
```json
{
  "success": true,
  "data": {
    "text": "Congratulations! You won a $1,000,000 lottery! Call now.",
    "is_spam": true,
    "is_transaction": false,
    "status": "DISCARDED (SPAM/NOISE)",
    "category": "N/A",
    "display_category": "N/A",
    "confidence": 98.7,
    "spam_probability": 98.7,
    "category_probabilities": {}
  }
}
```

### 3. POST `/api/sms/classify/batch`
Classify an array of messages while preserving input order.
```json
{
  "messages": [
    "You spent INR 450 at Starbucks on 12-Oct.",
    "Exclusive sale! 50% discount on shoes today only."
  ]
}
```

---

## Mobile App Integration (`app/`)

The mobile client leverages this pipeline for automated bank SMS import:

1. **`SmsInboxService`**:
   - Accesses device SMS inbox on Android via `flutter_sms_inbox` and `permission_handler`.
   - Filters candidate banking messages using regex keywords (`credited`, `debited`, `transfer`, `UPI`, `ATM`) while excluding spam keywords.
   - Paginates inbox records up to 1,000 messages.
2. **`SmsTransactionImporter`**:
   - Parses the transaction amount (`₹`, `Rs.`, `INR`, `$`) and merchant/counterparty from the text.
   - Converts the approved SMS into a typed `Transaction` entity.
   - Injects the transaction directly into the user's active ledger.
3. **`SmsClassifierScreen`**:
   - **Manual Tab**: Live try-me playground for pasting text and checking classification confidence.
   - **SMS Timeline Tab**: Monthly archive of scanned bank messages with month-by-month picker, confidence badges, and 1-click **Import to Ledger** button.

---

## Retraining

To retrain the model and regenerate `artifacts/`:
```bash
# From repository root
python -c "from sms import sms_classifier as sc; sc.SmsClassifier.train().save()"
```
