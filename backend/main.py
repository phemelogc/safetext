from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, List
import joblib
import os
import json
import traceback
import threading
from datetime import datetime

from utils import preprocess_text
from sender_reputation import get_sender_tier, has_phishing_link

app = FastAPI(
    title="SafeText API",
    description="API for Smishing Detection, Feedback Collection, and Continuous Learning",
    version="3.0",
)

# Allow Flutter app access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR        = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH      = os.path.join(BASE_DIR, "models", "smishing_model.pkl")
VECTORIZER_PATH = os.path.join(BASE_DIR, "models", "tfidf_vectorizer.pkl")
BINARIZER_PATH  = os.path.join(BASE_DIR, "models", "label_binarizer.pkl")
REPORTS_PATH    = os.path.join(BASE_DIR, "data",   "reports.json")
STATUS_PATH     = os.path.join(BASE_DIR, "data",   "retrain_status.json")

# Auto-retrain every time this many NEW feedback entries are collected
RETRAIN_EVERY = 10

# ── Model state ──────────────────────────────────────────────────────────────
model      = None
vectorizer = None
binarizer  = None
_retrain_lock = threading.Lock()


def _load_models():
    """Load (or reload) model artefacts from disk."""
    global model, vectorizer, binarizer
    try:
        model      = joblib.load(MODEL_PATH)
        vectorizer = joblib.load(VECTORIZER_PATH)
        binarizer  = joblib.load(BINARIZER_PATH)
    except Exception:
        traceback.print_exc()
        model      = None
        vectorizer = None
        binarizer  = None


_load_models()


# ── Tag explanations ──────────────────────────────────────────────────────────
TAG_EXPLANATIONS = {
    "phishing_link":     "contains a suspicious link",
    "urgency":           "uses urgent language to pressure you",
    "credential_harvest": "is asking for personal or financial details",
    "prize_bait":        "is offering a prize or reward that seems too good to be true",
    "impersonation":     "appears to be impersonating a trusted company",
    "fake_job":          "is advertising a suspicious job opportunity",
    "fake_investment":   "is promoting an investment that promises unrealistic returns",
    "setswana_bait":     "uses local language to appear more legitimate",
}


def generate_explanation(tags: list, confidence: float) -> str:
    """Build a human-readable explanation from detected tags."""
    active = [TAG_EXPLANATIONS[t] for t in tags if t in TAG_EXPLANATIONS]
    if not active:
        return "This message appears safe, but always remain cautious."

    if len(active) == 1:
        sentence = f"This message {active[0]}."
    elif len(active) == 2:
        sentence = f"This message {active[0]} and {active[1]}."
    else:
        parts = ", ".join(active[:-1])
        sentence = f"This message {parts}, and {active[-1]}."

    sentence = sentence[0].upper() + sentence[1:]
    return sentence


# ── Helpers ──────────────────────────────────────────────────────────────────
def _ensure_reports_file():
    os.makedirs(os.path.dirname(REPORTS_PATH), exist_ok=True)
    if not os.path.exists(REPORTS_PATH):
        with open(REPORTS_PATH, "w") as f:
            json.dump([], f)


def _append_report(entry: dict):
    _ensure_reports_file()
    with open(REPORTS_PATH, "r") as f:
        reports = json.load(f)
    reports.append(entry)
    with open(REPORTS_PATH, "w") as f:
        json.dump(reports, f, indent=2)
    return len(reports)


def _feedback_count() -> int:
    _ensure_reports_file()
    with open(REPORTS_PATH, "r") as f:
        return len(json.load(f))


def _read_status() -> dict:
    if os.path.exists(STATUS_PATH):
        with open(STATUS_PATH, "r") as f:
            return json.load(f)
    return {"last_retrain": None}


# ── Background retrain ────────────────────────────────────────────────────────
def _background_retrain():
    """Run retrain pipeline in a background thread, then hot-swap model files."""
    if not _retrain_lock.acquire(blocking=False):
        print("[retrain] Already in progress, skipping.")
        return
    try:
        from retrain import run_retrain
        result = run_retrain()
        print(f"[retrain] Done: {result}")
        _load_models()
    except Exception:
        traceback.print_exc()
    finally:
        _retrain_lock.release()


# ── Schemas ───────────────────────────────────────────────────────────────────
class MessageRequest(BaseModel):
    message: str
    sender: Optional[str] = None


class FeedbackRequest(BaseModel):
    message: str
    label: str                      # 'legit' | 'report' | 'safe' | 'smishing'
    address: Optional[str] = None
    tags: Optional[List[str]] = []  # tags the user confirmed e.g. ["phishing_link"]


# ── Endpoints ─────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {
        "status": "ok" if (model and vectorizer and binarizer) else "model_not_loaded",
        "feedback_collected": _feedback_count(),
        "retrain_every": RETRAIN_EVERY,
    }


@app.post("/predict")
def predict(data: MessageRequest):
    message = data.message
    sender  = (data.sender or "").strip()

    if not message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    # ── Tier 1: trusted sender ────────────────────────────────────────────────
    tier = get_sender_tier(sender) if sender else "unknown"

    if tier == "trusted":
        if has_phishing_link(message):
            return {
                "flagged":     True,
                "confidence":  0.95,
                "tags":        ["phishing_link", "impersonation"],
                "sender_tier": "trusted",
                "explanation": (
                    "This message appears to come from a known sender "
                    "but contains a suspicious link — it may be spoofed."
                ),
            }
        return {
            "flagged":     False,
            "confidence":  0.99,
            "tags":        ["legit"],
            "sender_tier": "trusted",
            "explanation": "Trusted sender. This message appears legitimate.",
        }

    # ── Model required ─────────────────────────────────────────────────────────
    if not model or not vectorizer or not binarizer:
        raise HTTPException(status_code=500, detail="Model not available")

    try:
        cleaned  = preprocess_text(message)
        features = vectorizer.transform([cleaned])

        # predict_proba returns shape (n_samples, n_classes) per estimator
        # For OvR, model.estimators_[i].predict_proba gives [[p_neg, p_pos]]
        tag_names = binarizer.classes_.tolist()
        probs = []
        for estimator in model.estimators_:
            prob_positive = float(estimator.predict_proba(features)[0][1])
            probs.append(prob_positive)

        # Apply confidence floor for flagged senders
        confidence_floor = 0.75 if tier == "flagged" else 0.0

        THRESHOLD = 0.45
        detected_tags = [
            tag for tag, prob in zip(tag_names, probs)
            if prob >= THRESHOLD and tag != "legit"
        ]

        max_confidence = max(probs) if probs else 0.0
        # Apply floor: if sender is flagged, confidence is at least 0.75
        max_confidence = max(max_confidence, confidence_floor)

        flagged = bool(detected_tags) or max_confidence >= 0.6

        if not flagged:
            detected_tags = ["legit"]

        return {
            "flagged":     flagged,
            "confidence":  round(max_confidence, 2),
            "tags":        detected_tags,
            "sender_tier": tier,
            "explanation": generate_explanation(detected_tags, max_confidence),
        }

    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Prediction failed")


@app.post("/feedback")
def feedback(data: FeedbackRequest, background_tasks: BackgroundTasks):
    raw = (data.label or "").lower()
    if raw in ("safe", "legit"):
        label = "legit"
    elif raw in ("smishing", "report"):
        label = "report"
    else:
        label = raw or "unknown"

    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "message":   data.message,
        "label":     label,
        "address":   data.address,
        "tags":      data.tags or [],
    }
    total = _append_report(entry)

    should_retrain = (total % RETRAIN_EVERY == 0)
    if should_retrain:
        background_tasks.add_task(_background_retrain)

    return {
        "status":         "feedback received",
        "total_feedback": total,
        "retrain_queued": should_retrain,
    }


@app.post("/retrain/trigger")
def manual_retrain(background_tasks: BackgroundTasks):
    """Manually kick off a retrain."""
    if _retrain_lock.locked():
        return {"status": "retrain already in progress"}
    background_tasks.add_task(_background_retrain)
    return {"status": "retrain queued"}


@app.get("/retrain/status")
def retrain_status():
    """Returns stats about the last retrain and current feedback count."""
    status = _read_status()
    status["feedback_collected"]       = _feedback_count()
    status["retrain_in_progress"]      = _retrain_lock.locked()
    status["next_retrain_at_feedback"] = (
        ((_feedback_count() // RETRAIN_EVERY) + 1) * RETRAIN_EVERY
    )
    return status


@app.get("/reports")
def get_reports():
    """List all stored feedback reports."""
    _ensure_reports_file()
    try:
        with open(REPORTS_PATH, "r") as f:
            reports = json.load(f)
        return {"reports": reports}
    except Exception:
        return {"reports": []}
