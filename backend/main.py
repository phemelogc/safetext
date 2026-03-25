from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import joblib
import os
import json
import traceback
from datetime import datetime

from utils import preprocess_text

app = FastAPI(title="SafeText API", description="API for Smishing Detection and Feedback Collection", version="1.0")

# Allow Flutter app access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "models", "smishing_model.pkl")
VECTORIZER_PATH = os.path.join(BASE_DIR, "models", "tfidf_vectorizer.pkl")
REPORTS_PATH = os.path.join(BASE_DIR, "data", "reports.json")

try:
    model = joblib.load(MODEL_PATH)
    vectorizer = joblib.load(VECTORIZER_PATH)
except Exception:
    traceback.print_exc()
    model = None
    vectorizer = None


class MessageRequest(BaseModel):
    message: str


class FeedbackRequest(BaseModel):
    message: str
    label: str  # 'legit' | 'report' | 'safe' | 'smishing'
    address: Optional[str] = None


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


def generate_explanation(probability: float) -> str:
    if probability >= 0.85:
        return "This message strongly resembles known scam patterns. Avoid clicking links or sharing personal information."
    if probability >= 0.65:
        return "This message contains suspicious wording commonly found in scam messages."
    return "This message appears safe, but always remain cautious."


@app.get("/health")
def health():
    return {
        "status": "ok" if model and vectorizer else "model_not_loaded"
    }


@app.post("/predict")
def predict(data: MessageRequest):

    if not model or not vectorizer:
        raise HTTPException(status_code=500, detail="Model not available")

    message = data.message

    if not message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    try:
        cleaned = preprocess_text(message)
        features = vectorizer.transform([cleaned])

        prob_val = float(model.predict_proba(features)[0][1])
        is_flagged = bool(prob_val >= 0.6)

        return {
            "flagged": is_flagged,
            "confidence": round(prob_val, 2),
            "explanation": generate_explanation(prob_val)
        }

    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Prediction failed")


@app.post("/feedback")
def feedback(data: FeedbackRequest):
    # Normalize label to 'legit' or 'report' for admin
    raw = (data.label or "").lower()
    if raw in ("safe", "legit"):
        label = "legit"
    elif raw in ("smishing", "report"):
        label = "report"
    else:
        label = raw or "unknown"
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "message": data.message,
        "label": label,
        "address": data.address,
    }
    _append_report(entry)
    return {"status": "feedback received"}


@app.get("/reports")
def get_reports():
    """For future React admin: list all stored reports."""
    _ensure_reports_file()
    try:
        with open(REPORTS_PATH, "r") as f:
            reports = json.load(f)
        return {"reports": reports}
    except Exception:
        return {"reports": []}
