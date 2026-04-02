"""
retrain.py
----------
Multi-label smishing pattern classifier.

Merges data/smishing_dataset.csv with locally collected feedback from
reports.json, then trains a OneVsRest LogisticRegression pipeline and
saves three model artefacts.

Called automatically by main.py every RETRAIN_EVERY feedback entries,
or manually via POST /retrain/trigger, or directly: python retrain.py
"""

import os
import json
import shutil
import joblib
import logging
import pandas as pd
from datetime import datetime
from sklearn.linear_model import LogisticRegression
from sklearn.multiclass import OneVsRestClassifier
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.preprocessing import MultiLabelBinarizer
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report

from utils import preprocess_text

logging.basicConfig(level=logging.INFO, format="%(asctime)s [retrain] %(message)s")
log = logging.getLogger(__name__)

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR        = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH    = os.path.join(BASE_DIR, "data",   "smishing_dataset.csv")
REPORTS_PATH    = os.path.join(BASE_DIR, "data",   "reports.json")
MODEL_PATH      = os.path.join(BASE_DIR, "models", "smishing_model.pkl")
VECTORIZER_PATH = os.path.join(BASE_DIR, "models", "tfidf_vectorizer.pkl")
BINARIZER_PATH  = os.path.join(BASE_DIR, "models", "label_binarizer.pkl")
STATUS_PATH     = os.path.join(BASE_DIR, "data",   "retrain_status.json")

# Each local feedback row is duplicated this many times to upweight it
LOCAL_WEIGHT = 3

ALL_TAGS = [
    "phishing_link",
    "urgency",
    "credential_harvest",
    "prize_bait",
    "impersonation",
    "fake_job",
    "fake_investment",
    "setswana_bait",
    "legit",
]


# ── Data loaders ─────────────────────────────────────────────────────────────

def _parse_tags(raw: str) -> list:
    """Split a comma-separated tag string into a list of stripped, non-empty tags."""
    return [t.strip() for t in str(raw).split(",") if t.strip()]


def _load_dataset() -> pd.DataFrame:
    """Load the primary smishing CSV dataset."""
    df = pd.read_csv(DATASET_PATH, encoding="utf-8")
    df = df.dropna(subset=["message", "tags"])
    df["tag_list"] = df["tags"].apply(_parse_tags)
    df = df[df["tag_list"].map(len) > 0]
    log.info("Primary dataset loaded: %d rows", len(df))
    return df[["message", "tag_list"]]


def _load_feedback() -> pd.DataFrame:
    """Load locally collected feedback from reports.json and map to tag lists."""
    if not os.path.exists(REPORTS_PATH):
        return pd.DataFrame(columns=["message", "tag_list"])

    with open(REPORTS_PATH, "r") as f:
        reports = json.load(f)

    rows = []
    for r in reports:
        label_raw = (r.get("label") or "").lower()
        # Use user-confirmed tags if present, otherwise derive from label
        confirmed_tags = r.get("tags") or []
        if confirmed_tags:
            tag_list = [t.strip() for t in confirmed_tags if t.strip()]
        elif label_raw in ("legit", "safe"):
            tag_list = ["legit"]
        elif label_raw in ("report", "smishing"):
            tag_list = ["urgency"]   # fallback — we don't know the pattern yet
        else:
            continue  # skip 'unknown' entries

        msg = (r.get("message") or "").strip()
        if msg and tag_list:
            rows.append({"message": msg, "tag_list": tag_list})

    df = pd.DataFrame(rows)
    log.info("Feedback entries loaded: %d usable rows", len(df))
    return df


def _backup_models():
    """Keep one timestamped backup of the current model files."""
    stamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    for src in [MODEL_PATH, VECTORIZER_PATH, BINARIZER_PATH]:
        if os.path.exists(src):
            dst = src.replace(".pkl", f"_backup_{stamp}.pkl")
            shutil.copy2(src, dst)
            log.info("Backed up %s → %s", os.path.basename(src), os.path.basename(dst))


def _save_status(info: dict):
    os.makedirs(os.path.dirname(STATUS_PATH), exist_ok=True)
    with open(STATUS_PATH, "w") as f:
        json.dump(info, f, indent=2)


# ── Main pipeline ─────────────────────────────────────────────────────────────

def run_retrain() -> dict:
    """
    Full multi-label retrain pipeline. Returns a status dict.
    Raises on critical failure so the caller can log it.
    """
    log.info("=== Retrain started ===")

    # 1. Load and merge data
    primary  = _load_dataset()
    feedback = _load_feedback()

    # Upweight feedback by repeating rows LOCAL_WEIGHT times
    if not feedback.empty:
        feedback = pd.concat([feedback] * LOCAL_WEIGHT, ignore_index=True)

    combined = pd.concat([primary, feedback], ignore_index=True)
    combined = combined.dropna(subset=["message", "tag_list"])
    combined["cleaned"] = combined["message"].apply(preprocess_text)

    log.info(
        "Combined dataset: %d rows (%d primary + %d weighted feedback)",
        len(combined), len(primary), len(feedback),
    )

    if len(combined) < 20:
        raise ValueError("Not enough data to retrain (need at least 20 rows).")

    # 2. Encode multi-labels
    mlb = MultiLabelBinarizer(classes=ALL_TAGS)
    Y = mlb.fit_transform(combined["tag_list"])

    # 3. Train/test split (no stratify — multi-label makes it complex)
    X = combined["cleaned"].values
    X_train, X_test, Y_train, Y_test = train_test_split(
        X, Y, test_size=0.15, random_state=42
    )

    # 4. Fit TF-IDF vectorizer on training text only
    vectorizer = TfidfVectorizer(
        ngram_range=(1, 2),
        max_features=10_000,
        sublinear_tf=True,
    )
    X_train_vec = vectorizer.fit_transform(X_train)
    X_test_vec  = vectorizer.transform(X_test)

    # 5. Train OneVsRest LogisticRegression
    clf = OneVsRestClassifier(LogisticRegression(max_iter=1000, C=1.0))
    clf.fit(X_train_vec, Y_train)

    # 6. Evaluate
    Y_pred = clf.predict(X_test_vec)
    tag_names = mlb.classes_.tolist()
    report = classification_report(
        Y_test, Y_pred,
        target_names=tag_names,
        output_dict=True,
        zero_division=0,
    )
    log.info("Evaluation complete:")
    for tag in tag_names:
        if tag in report:
            r = report[tag]
            log.info(
                "  %-20s precision=%.2f  recall=%.2f  f1=%.2f",
                tag, r["precision"], r["recall"], r["f1-score"],
            )

    # 7. Backup old models, save new ones
    _backup_models()
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    joblib.dump(clf,        MODEL_PATH)
    joblib.dump(vectorizer, VECTORIZER_PATH)
    joblib.dump(mlb,        BINARIZER_PATH)
    log.info("New model files saved: smishing_model.pkl, tfidf_vectorizer.pkl, label_binarizer.pkl")

    # 8. Count tag occurrences in combined dataset
    tag_counts = {}
    for tag_list in combined["tag_list"]:
        for tag in tag_list:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1

    status = {
        "last_retrain":   datetime.utcnow().isoformat() + "Z",
        "total_rows":     len(combined),
        "primary_rows":   len(primary),
        "feedback_rows":  len(feedback),
        "tag_counts":     tag_counts,
        "macro_f1":       round(report.get("macro avg", {}).get("f1-score", 0), 4),
    }
    _save_status(status)
    log.info("=== Retrain complete ===")
    return status


if __name__ == "__main__":
    result = run_retrain()
    print(json.dumps(result, indent=2))
