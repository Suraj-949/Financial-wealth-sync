# SMS Transaction Classifier (`sms/`)

Two-stage text pipeline that turns raw bank / transaction SMS into structured
categories, supporting automated expense tracking.

```
raw SMS
   ↓  preprocess_text()  (lowercase, [url]/[phone] tokens, strip digits & punctuation)
   ↓  Stage 1: spam/noise filter   →  DISCARDED (SPAM/NOISE)  when predicted spam
   ↓  Stage 2: categoriser         →  credit | debit | other
```

Both stages are `TfidfVectorizer(ngram_range=(1, 2))` + `MultinomialNB(alpha=0.1)`,
trained on the small labelled dataset embedded in `sms_classifier.py`. The data,
preprocessing rules and hyper-parameters are preserved verbatim from the training
notebook, so the served model **is** the trained model.

## Files

| File | Purpose |
|---|---|
| `sms_classifier.py` | Dataset, preprocessing, `SmsClassifier` (train / save / load / classify) |
| `artifacts/` | Persisted pipeline the backend serves (generated) |

## Artifacts (`sms/artifacts/`)

- `spam_vectorizer.joblib`, `spam_model.joblib` — stage 1 (binary: `0` legitimate, `1` spam)
- `category_vectorizer.joblib`, `category_model.joblib` — stage 2 (`credit` / `debit` / `other`)
- `metadata.json` — algorithm, classes, sample counts, train accuracy, trained_at

## Train once (already committed artifacts)

```powershell
# From repo root
$env:KMP_DUPLICATE_LIB_OK="TRUE"
C:\Users\SURAJ\anaconda3\python.exe -c "from sms import sms_classifier as sc; sc.SmsClassifier.train().save()"
```

`SmsClassifier.load_or_train()` loads the artifacts if present, otherwise trains
and persists them once. The backend uses this — it never retrains per request.

## API

Served by the FastAPI backend (`backend/sms_service.py`):

| Method | Path | Body |
|---|---|---|
| GET | `/api/sms/health` | — |
| POST | `/api/sms/classify` | `{ "text": "..." }` |
| POST | `/api/sms/classify/batch` | `{ "messages": ["...", ...] }` |

A legitimate SMS returns `status = "APPROVED (TRANSACTION)"` with a
`category`; spam/noise returns `status = "DISCARDED (SPAM/NOISE)"` with
`category = "N/A"`. See `backend/ML_API_DOCUMENTATION.md` for the full schema.

## Notes

- The training set is small and synthetic; train accuracy is 1.0 and real-world
  accuracy will be lower. Treat outputs as assistive, not authoritative.
- `untitled7.py` is the original source notebook; `sms_classifier.py` is the
  productionised extraction.
