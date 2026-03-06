"""Text preprocessing for the smishing model. Replace with your full pipeline if needed."""

import re


def preprocess_text(text: str) -> str:
    if not text:
        return ""
    s = text.lower().strip()
    s = re.sub(r"\s+", " ", s)
    return s
