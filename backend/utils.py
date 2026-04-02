"""Text preprocessing for the SafeText smishing model."""

import re

# ---------------------------------------------------------------------------
# Setswana → English normalisation map
# ---------------------------------------------------------------------------
_SETSWANA_MAP = {
    "madi":     "money",
    "akhaonto": "account",
    "omang":    "id",
    "jaanong":  "now",
    "romela":   "send",
    "amogela":  "receive",
    "putso":    "salary",
    "mosebo":   "job",
}

# Pre-compiled regex: match whole words only (case-insensitive)
_SETSWANA_RE = re.compile(
    r"\b(" + "|".join(re.escape(k) for k in _SETSWANA_MAP) + r")\b",
    re.IGNORECASE,
)

# URL pattern (http/https/www and bare domains)
_URL_RE = re.compile(
    r"(https?://\S+|www\.\S+|\b\w+\.(com|net|org|biz|info|io|co|bw)\b(/\S*)?)",
    re.IGNORECASE,
)

# Phone numbers: +267 local format and generic international
_PHONE_RE = re.compile(
    r"(\+267[\s\-]?\d{7,8}|\b0\d{8}\b|\+\d{1,3}[\s\-]?\d{6,14})",
)

# Currency amounts: P500, P1,000, £100, $200, R350
_CURRENCY_RE = re.compile(
    r"([P£\$R]\s?\d[\d,\.]*|\d[\d,\.]*\s?(pula|bwp|usd|gbp|zar))",
    re.IGNORECASE,
)


def preprocess_text(text: str) -> str:
    """
    Clean and normalise a raw SMS/message string for the ML model.

    Steps:
      1. Lowercase
      2. Replace URLs         → SUSPICIOUSLINK
      3. Replace phone numbers → PHONENUMBER
      4. Replace currency amounts → CURRENCYAMOUNT
      5. Normalise Setswana words to English equivalents
      6. Collapse excess whitespace
    """
    if not text:
        return ""

    s = text.lower()

    # 2. URLs
    s = _URL_RE.sub(" SUSPICIOUSLINK ", s)

    # 3. Phone numbers
    s = _PHONE_RE.sub(" PHONENUMBER ", s)

    # 4. Currency amounts
    s = _CURRENCY_RE.sub(" CURRENCYAMOUNT ", s)

    # 5. Setswana normalisation
    s = _SETSWANA_RE.sub(lambda m: _SETSWANA_MAP[m.group(0).lower()], s)

    # 6. Collapse whitespace
    s = re.sub(r"\s+", " ", s).strip()

    return s
