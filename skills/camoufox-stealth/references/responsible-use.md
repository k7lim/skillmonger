---
name: responsible-use
description: Firm responsible-use boundaries for Camoufox — what this skill is for, what it must never be used for
tags: camoufox, responsible-use, ethics, policy, boundaries
---

# Responsible Use

Camoufox is a legitimate tool for authorized web automation and scraping. It stays legitimate only if it's used that way. This is not optional guidance — treat it as a hard boundary on this skill's use.

## Always

- **Respect `robots.txt` and the target site's Terms of Service.** Check both before automating against a new target.
- **Rate-limit politely.** Keep request volume low enough that it doesn't degrade the target site for other users; identify the impact of a scraping run before running it at scale (expected request count, frequency, duration).
- **Prefer official APIs or data exports when they exist**, over scraping, especially for high-volume or recurring needs.

## Never

- Do not use this skill for **credential stuffing** or any attempt to test/use credentials the user does not already legitimately possess.
- Do not use it for **mass or automated account creation** (sign-up abuse, fake-account generation).
- Do not use it for **spam** (automated posting, messaging, or content submission at scale).
- Do not use it to **scrape personal data at scale** — bulk collection of names, contact info, or other personal data about individuals, beyond what a specific authorized, narrow task requires.

## Authorization boundary

Treat the following as requiring the user's **explicit, per-target authorization** before proceeding — do not assume consent from the mere existence of a login form or a request to "get data from this site":

- Any **login-walled data** (content behind an account the user must authenticate into).
- Any target the user does not clearly **own or control**, or hasn't clearly stated they're authorized to access this way (e.g., via a ToS carve-out, a data-sharing agreement, or the site owner's direct permission).

If authorization is unclear, ask before proceeding rather than assuming it.

## Off-limits regardless of authorization

- **CAPTCHA-solving** (automated bypass of image/interactive challenges, or integrating third-party CAPTCHA-solving services) is out of scope for this skill.
- **Defeating access controls for prohibited purposes** — using Camoufox's fingerprint evasion specifically to get around a block that exists to enforce a policy against automation (rather than to reduce false-positive blocking of otherwise-legitimate, authorized automation) is off-limits.

## Framing

This is a legitimate stealth-browsing tool for cases like: authorized scraping of a site that blocks all automation indiscriminately, QA/testing of a site's own bot defenses, or automating a service on the user's own behalf where fingerprinting causes false-positive blocks. Keep every use inside that frame.
