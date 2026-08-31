---
name: anti-bot-troubleshooting
description: Cheapest-first playbook for when a target site still blocks or challenges Camoufox — what to try, in order, and what Camoufox cannot do
tags: camoufox, anti-bot, troubleshooting, detection, blocking, playbook
---

# Anti-Bot Troubleshooting Playbook

Ordered cheapest-first: try each step, re-test, escalate only if still blocked. Don't jump straight to proxies/persistent profiles if a one-line flag flip fixes it.

## Escalation order

| # | Symptom | Try | Why it helps |
|---|---|---|---|
| 1 | Blocked/challenged even on a simple `goto` | Switch `headless=False` (or `headless="virtual"` on Linux) | Headless mode has residual fingerprint signals in most stacks; running headed (or virtual-display headless) removes the most common ones |
| 2 | Blocked despite headed mode | Add `humanize=True` | Sites that fingerprint mouse/cursor behavior see non-human, instant pointer jumps without it |
| 3 | Still challenged, or rate-limited after a few requests | Slow down — add explicit delays between actions, randomize timing (`page.wait_for_timeout(random.uniform(...))`) instead of fixed intervals | Uniform, superhuman request cadence is a strong behavioral signal independent of any fingerprint |
| 4 | IP-based blocking, geofencing, or datacenter-IP flags | Use a residential `proxy`, **with** `geoip=True` and a matching `locale` | Consistency matters: IP, timezone, and locale must agree. A US proxy with a German locale/timezone is a mismatch signal on its own |
| 5 | Blocked repeatedly from the same apparent fingerprint | Vary the `os` fingerprint (pass a list, e.g. `os=["windows", "macos"]`) across sessions/launches | Avoids a single static fingerprint accumulating a bad reputation over many requests |
| 6 | Site fingerprints via WebRTC-leaked local/real IP behind a proxy | `block_webrtc=True` | Prevents WebRTC STUN requests from exposing the real IP even when a proxy is otherwise correctly configured |
| 7 | Login-gated content re-triggers challenge every run | Use `persistent_context=True` + `user_data_dir=` with a profile that has already been "warmed" (aged cookies, prior normal browsing history in that profile) | A profile with history and existing session cookies looks like a returning real user, not a fresh bot |
| 8 | Blocked under moderate load / multiple concurrent sessions | Reduce request rate and concurrency; stagger session starts | Aggregate request-volume anomalies (many parallel sessions from one operator) are detected independently of any single session's fingerprint |

## Diagnostic tips

- Isolate the cause: strip back to a single `goto()` with default options first. Add one countermeasure at a time so you know what actually mattered.
- Check whether the block happens at load (network/IP-level, e.g. a WAF challenge page) vs. after some interaction (behavioral/JS-level). That tells you whether to focus on proxy/geoip (step 4) or humanize/timing (steps 2–3).
- A 403/999-style immediate block on first request usually points to IP reputation (step 4) before anything else.
- A challenge that appears only after several page interactions usually points to behavioral analysis (steps 2–3, 8).

## Limits & honesty

Camoufox reduces *fingerprint-based* detection — it does not defeat every anti-bot system. Be direct with the user about what's out of reach:

- **Behavioral analysis** (mouse/scroll/typing patterns over a full session, not just cursor movement) can still flag automation even with `humanize=True`; it reduces but does not eliminate this signal.
- **Account-level signals** (account age, prior activity, velocity of actions tied to a logged-in identity) are outside what any browser fingerprint change can fix.
- **Hard CAPTCHAs** (image challenges, hCaptcha/reCAPTCHA enterprise tiers, etc.) are not solved by Camoufox. CAPTCHA-solving is out of scope for this skill — do not attempt to bypass, automate past, or integrate third-party CAPTCHA-solving services.
- If a target keeps blocking after working through this list, that is a signal to stop and reconsider the approach (different data source, official API, direct outreach to the site owner) rather than escalating countermeasures indefinitely.
