from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import joblib
import os
import json
import traceback
import threading
from datetime import datetime

from utils import preprocess_text

app = FastAPI(
    title="SafeText API",
    description="API for Smishing Detection, Feedback Collection, and Continuous Learning",
    version="2.0",
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
REPORTS_PATH    = os.path.join(BASE_DIR, "data", "reports.json")
STATUS_PATH     = os.path.join(BASE_DIR, "data", "retrain_status.json")

# Auto-retrain every time this many NEW feedback entries are collected
RETRAIN_EVERY = 10

# ── Model state (module-level so hot-reload works) ───────────────────────────
model      = None
vectorizer = None
_retrain_lock = threading.Lock()   # prevent concurrent retrains


def _load_models():
    """Load (or reload) model and vectorizer from disk."""
    global model, vectorizer
    try:
        model      = joblib.load(MODEL_PATH)
        vectorizer = joblib.load(VECTORIZER_PATH)
    except Exception:
        traceback.print_exc()
        model      = None
        vectorizer = None


_load_models()


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
    return len(reports)   # return total count so caller can decide to retrain


def _feedback_count() -> int:
    _ensure_reports_file()
    with open(REPORTS_PATH, "r") as f:
        return len(json.load(f))


def _read_status() -> dict:
    if os.path.exists(STATUS_PATH):
        with open(STATUS_PATH, "r") as f:
            return json.load(f)
    return {"last_retrain": None}


def generate_explanation(probability: float) -> str:
    if probability >= 0.85:
        return "This message strongly resembles known scam patterns. Avoid clicking links or sharing personal information."
    if probability >= 0.65:
        return "This message contains suspicious wording commonly found in scam messages."
    return "This message appears safe, but always remain cautious."


# ── Background retrain ───────────────────────────────────────────────────────
def _background_retrain():
    """
    Run retrain.run_retrain() in a background thread.
    Reloads model files into memory when done so predictions
    immediately benefit from the new model — no restart needed.
    """
    if not _retrain_lock.acquire(blocking=False):
        print("[retrain] Already in progress, skipping.")
        return
    try:
        from retrain import run_retrain
        result = run_retrain()
        print(f"[retrain] Done: {result}")
        _load_models()   # hot-swap the updated model
    except Exception:
        traceback.print_exc()
    finally:
        _retrain_lock.release()


# ── Schemas ──────────────────────────────────────────────────────────────────
class MessageRequest(BaseModel):
    message: str


class FeedbackRequest(BaseModel):
    message: str
    label: str          # 'legit' | 'report' | 'safe' | 'smishing'
    address: Optional[str] = None


# ── Endpoints ────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {
        "status": "ok" if model and vectorizer else "model_not_loaded",
        "feedback_collected": _feedback_count(),
        "retrain_every": RETRAIN_EVERY,
    }


@app.post("/predict")
def predict(data: MessageRequest):
    if not model or not vectorizer:
        raise HTTPException(status_code=500, detail="Model not available")

    message = data.message
    if not message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    try:
        cleaned  = preprocess_text(message)
        features = vectorizer.transform([cleaned])

        prob_val  = float(model.predict_proba(features)[0][1])
        is_flagged = bool(prob_val >= 0.6)

        return {
            "flagged":     is_flagged,
            "confidence":  round(prob_val, 2),
            "explanation": generate_explanation(prob_val),
        }

    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Prediction failed")


@app.post("/feedback")
def feedback(data: FeedbackRequest, background_tasks: BackgroundTasks):
    # Normalise label
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
    }
    total = _append_report(entry)

    # Trigger retrain when we hit a new multiple of RETRAIN_EVERY
    should_retrain = (total % RETRAIN_EVERY == 0)
    if should_retrain:
        background_tasks.add_task(_background_retrain)

    return {
        "status":          "feedback received",
        "total_feedback":  total,
        "retrain_queued":  should_retrain,
    }


@app.post("/retrain/trigger")
def manual_retrain(background_tasks: BackgroundTasks):
    """Manually kick off a retrain (useful for your future admin dashboard)."""
    if _retrain_lock.locked():
        return {"status": "retrain already in progress"}
    background_tasks.add_task(_background_retrain)
    return {"status": "retrain queued"}


@app.get("/retrain/status")
def retrain_status():
    """Returns stats about the last retrain and current feedback count."""
    status = _read_status()
    status["feedback_collected"] = _feedback_count()
    status["retrain_in_progress"] = _retrain_lock.locked()
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