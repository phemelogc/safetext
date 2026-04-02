# Replace your _SUSPICIOUS_PATTERNS regex with this tighter version.
# The old one matched too broadly — ".bw.net" caught legitimate .bw domains,
# and "customerportal" caught real banking sites.

# ── OLD (too aggressive) ─────────────────────────────────────────────────────
# _SUSPICIOUS_PATTERNS = re.compile(
#     r"(verify[\-\.]now|secure[\-\.]login|account[\-\.]suspended|"
#     r"customerportal|[\-\.]bw\.net|[\-\.]verify\.com|"
#     r"gov[\-\.]payments|relief[\-\.]fund)",
#     re.IGNORECASE,
# )
import re
# ── NEW (tighter) ────────────────────────────────────────────────────────────
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

# ── ALSO ADD: known legitimate Botswana domains to whitelist ─────────────────
# If a URL contains one of these, don't flag it even if a shortener is present
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