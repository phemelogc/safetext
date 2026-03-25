"""
retrain.py
----------
Merges the universal SMS spam dataset with locally collected feedback from
reports.json, then retrains the Naive Bayes + TF-IDF pipeline and saves
the new model files (backing up the old ones first).

Called automatically by main.py every RETRAIN_EVERY feedback entries,
or manually via POST /retrain/trigger.
"""

import os
import json
import shutil
import joblib
import logging
import pandas as pd
from datetime import datetime
from sklearn.naive_bayes import MultinomialNB
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.pipeline import Pipeline
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report

from utils import preprocess_text

logging.basicConfig(level=logging.INFO, format="%(asctime)s [retrain] %(message)s")
log = logging.getLogger(__name__)

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR        = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH    = os.path.join(BASE_DIR, "data", "spam_dataset.tsv")   # universal TSV
REPORTS_PATH    = os.path.join(BASE_DIR, "data", "reports.json")
MODEL_PATH      = os.path.join(BASE_DIR, "models", "smishing_model.pkl")
VECTORIZER_PATH = os.path.join(BASE_DIR, "models", "tfidf_vectorizer.pkl")
STATUS_PATH     = os.path.join(BASE_DIR, "data", "retrain_status.json")

# How much to weight each local feedback entry vs one universal row.
# 3 means one local SMS counts as 3 universal rows during training.
LOCAL_WEIGHT = 3


def _load_universal() -> pd.DataFrame:
    """Load the original tab-separated dataset (no header, label | message)."""
    df = pd.read_csv(
        DATASET_PATH,
        sep="\t",
        header=None,
        names=["label", "message"],
        encoding="latin-1",
    )
    # Normalise: ham → 0, spam → 1
    df["binary_label"] = df["label"].map({"ham": 0, "spam": 1})
    df = df.dropna(subset=["binary_label"])
    df["binary_label"] = df["binary_label"].astype(int)
    df["weight"] = 1.0
    log.info("Universal dataset loaded: %d rows", len(df))
    return df[["message", "binary_label", "weight"]]


def _load_feedback() -> pd.DataFrame:
    """Load locally collected feedback from reports.json."""
    if not os.path.exists(REPORTS_PATH):
        return pd.DataFrame(columns=["message", "binary_label", "weight"])

    with open(REPORTS_PATH, "r") as f:
        reports = json.load(f)

    rows = []
    for r in reports:
        label_raw = (r.get("label") or "").lower()
        if label_raw in ("legit", "safe", "ham"):
            binary = 0
        elif label_raw in ("report", "smishing", "spam"):
            binary = 1
        else:
            continue  # skip 'unknown' entries
        msg = (r.get("message") or "").strip()
        if msg:
            rows.append({"message": msg, "binary_label": binary, "weight": float(LOCAL_WEIGHT)})

    df = pd.DataFrame(rows)
    log.info("Feedback entries loaded: %d usable rows", len(df))
    return df


def _backup_models():
    """Keep one timestamped backup of the current model files."""
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    for src in [MODEL_PATH, VECTORIZER_PATH]:
        if os.path.exists(src):
            dst = src.replace(".pkl", f"_backup_{stamp}.pkl")
            shutil.copy2(src, dst)
            log.info("Backed up %s → %s", os.path.basename(src), os.path.basename(dst))


def _save_status(info: dict):
    os.makedirs(os.path.dirname(STATUS_PATH), exist_ok=True)
    with open(STATUS_PATH, "w") as f:
        json.dump(info, f, indent=2)


def run_retrain() -> dict:
    """
    Full retrain pipeline. Returns a status dict.
    Raises on critical failure so the caller can log it.
    """
    log.info("=== Retrain started ===")

    # 1. Load data
    universal = _load_universal()
    feedback  = _load_feedback()
    combined  = pd.concat([universal, feedback], ignore_index=True)
    combined  = combined.dropna(subset=["message", "binary_label"])
    combined["cleaned"] = combined["message"].apply(preprocess_text)

    log.info(
        "Combined dataset: %d rows (%d universal + %d local feedback)",
        len(combined), len(universal), len(feedback),
    )

    if len(combined) < 50:
        raise ValueError("Not enough data to retrain (need at least 50 rows).")

    X = combined["cleaned"]
    y = combined["binary_label"]
    w = combined["weight"]

    # 2. Train/test split (stratified, reproducible)
    X_train, X_test, y_train, y_test, w_train, _ = train_test_split(
        X, y, w, test_size=0.15, random_state=42, stratify=y
    )

    # 3. Fit vectorizer on training set only
    vectorizer = TfidfVectorizer(
        ngram_range=(1, 2),
        max_features=10_000,
        sublinear_tf=True,
    )
    X_train_vec = vectorizer.fit_transform(X_train)
    X_test_vec  = vectorizer.transform(X_test)

    # 4. Train Naive Bayes with sample weights
    nb_model = MultinomialNB(alpha=0.1)
    nb_model.fit(X_train_vec, y_train, sample_weight=w_train)

    # 5. Evaluate
    y_pred = nb_model.predict(X_test_vec)
    report = classification_report(y_test, y_pred, target_names=["ham", "spam"], output_dict=True)
    log.info(
        "Eval → spam precision: %.2f  recall: %.2f  f1: %.2f",
        report["spam"]["precision"],
        report["spam"]["recall"],
        report["spam"]["f1-score"],
    )

    # 6. Backup old models, save new ones
    _backup_models()
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    joblib.dump(nb_model,   MODEL_PATH)
    joblib.dump(vectorizer, VECTORIZER_PATH)
    log.info("New model files saved.")

    status = {
        "last_retrain": datetime.utcnow().isoformat() + "Z",
        "total_rows": len(combined),
        "universal_rows": len(universal),
        "feedback_rows": len(feedback),
        "spam_f1": round(report["spam"]["f1-score"], 4),
        "spam_precision": round(report["spam"]["precision"], 4),
        "spam_recall": round(report["spam"]["recall"], 4),
    }
    _save_status(status)
    log.info("=== Retrain complete ===")
    return status


if __name__ == "__main__":
    # Allow manual run: `python retrain.py`
    result = run_retrain()
    print(json.dumps(result, indent=2))