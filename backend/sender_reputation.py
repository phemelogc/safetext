"""
sender_reputation.py
--------------------
3-tier sender reputation check for SafeText.

Tiers:
  "trusted"  — known legitimate Botswana sender IDs (skip ML, check links only)
  "flagged"  — sender found in Firestore suspicious_numbers collection
  "unknown"  — not trusted and not in Firestore (run full ML)
"""

import re

# ---------------------------------------------------------------------------
# Trusted Botswana sender IDs
# ---------------------------------------------------------------------------
TRUSTED_SENDERS = {
    "71", "Mascom", "Orange", "Made4Me", "MyZaka", "OrangeMoney",
    "YUMBI", "15278", "SMS 166326", "Maxit", "M'Booste", "71Rewards",
    "18899", "17000", "REWARDS", "12637", "Betway Ops", "FNBB",
    "THUNTSHA", "Betway", "Yango", "DigitalKYC", "MascomKYC", "156",
    "Stanbic", "Absa", "BPC", "WUC", "BTC", "DSTV",
}

# ---------------------------------------------------------------------------
# Suspicious URL patterns for phishing link detection
# ---------------------------------------------------------------------------
_SHORTENERS = re.compile(
    r"(bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly)",
    re.IGNORECASE,
)

_SUSPICIOUS_PATTERNS = re.compile(
    r"(verify[\-\.]now"           # verify-now.anything
    r"|secure[\-\.]login"         # secure-login.anything  
    r"|account[\-\.]suspended"    # account-suspended
    r"|gov[\-\.]payments"         # gov-payments (hyphenated — real .gov.bw never does this)
    r"|relief[\-\.]fund"          # relief-fund
    r"|[\w\-]+\.verify[\-\.]com"  # something.verify.com or something.verify-com
    r"|[\w\-]+-bw\.net"           # something-bw.net (hyphen before bw = fake, e.g. orange-bw.net)
    r"|[\w\-]+-verify\."          # something-verify.anything (e.g. fnbb-verify.com)
    r"|[\w\-]+-secure\."          # something-secure.anything
    r"|[\w\-]+-update\."          # something-update.anything
    r"|[\w\-]+-portal\."          # something-portal.anything
    r"|[\w\-]+-support\."         # something-support.anything
    r")",
    re.IGNORECASE,
)
_LEGITIMATE_DOMAINS = {
    "fnbb.co.bw",
    "stanbicbank.co.bw",
    "absa.co.bw",
    "mascom.bw",
    "orange.co.bw",
    "myzaka.com",
    "btc.bw",
    "bpc.bw",
    "wuc.bw",
    "gov.bw",
    "dstv.com",
    "betway.co.za",
    "yango.com",
}
 
def has_phishing_link(message: str) -> bool:
    """
    Return True only if the message contains a genuinely suspicious link.
    Whitelists known legitimate Botswana domains so trusted senders
    sending real links are not incorrectly flagged.
    """
    if not message:
        return False
 
    # If any legitimate domain appears in the message, don't flag it
    msg_lower = message.lower()
    for domain in _LEGITIMATE_DOMAINS:
        if domain in msg_lower:
            return False
 
    return bool(_SHORTENERS.search(message) or _SUSPICIOUS_PATTERNS.search(message))

def has_phishing_link(message: str) -> bool:
    """Return True if the message contains shortened URLs or suspicious domain patterns."""
    if not message:
        return False
    return bool(_SHORTENERS.search(message) or _SUSPICIOUS_PATTERNS.search(message))


# ---------------------------------------------------------------------------
# Firestore lookup (lazy-init to avoid import errors if firebase-admin missing)
# ---------------------------------------------------------------------------
_firestore_client = None
_firestore_init_attempted = False


def _get_firestore():
    global _firestore_client, _firestore_init_attempted
    if _firestore_init_attempted:
        return _firestore_client
    _firestore_init_attempted = True
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore as fs

        if not firebase_admin._apps:
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)

        _firestore_client = fs.client()
    except Exception as exc:
        print(f"[sender_reputation] Firestore unavailable: {exc}")
        _firestore_client = None
    return _firestore_client


def _is_flagged_in_firestore(sender: str) -> bool:
    """Check Firestore suspicious_numbers collection. Returns False on any error."""
    try:
        db = _get_firestore()
        if db is None:
            return False
        doc = db.collection("suspicious_numbers").document(sender).get()
        return doc.exists
    except Exception as exc:
        print(f"[sender_reputation] Firestore check failed (offline fallback): {exc}")
        return False


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def get_sender_tier(sender: str) -> str:
    """
    Return "trusted", "flagged", or "unknown" for the given sender ID.

    - "trusted"  : sender is in the known-legitimate list
    - "flagged"  : sender is in the Firestore suspicious_numbers collection
    - "unknown"  : everything else (run full ML pipeline)
    """
    if not sender:
        return "unknown"

    if sender in TRUSTED_SENDERS:
        return "trusted"

    if _is_flagged_in_firestore(sender):
        return "flagged"

    return "unknown"
