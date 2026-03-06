# SafeText Backend

FastAPI app for prediction and feedback storage. Matches the Flutter app (predict, feedback with `address`, reports persisted).

## Setup

1. Copy your trained model files into `backend/models/`:
   - `smishing_model.pkl`
   - `tfidf_vectorizer.pkl`
2. From the `backend` directory:
   ```bash
   pip install -r requirements.txt
   uvicorn app:app --reload
   ```
3. Reports are stored in `data/reports.json`. Use `GET /reports` from your React admin to list them.

## Endpoints

- `GET /health` — model status
- `POST /predict` — body `{ "message": "..." }` → `flagged`, `confidence` (0–1), `explanation`
- `POST /feedback` — body `{ "message", "label": "legit"|"report", "address"?: "..." }` → persisted to `data/reports.json`
- `GET /reports` — returns all stored reports for admin
