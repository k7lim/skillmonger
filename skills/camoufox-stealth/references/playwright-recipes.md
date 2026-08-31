---
name: playwright-recipes
description: Copy-paste Camoufox + Playwright code recipes for interactive scraping/automation sessions
tags: camoufox, playwright, recipes, scraping, automation, python
---

# Camoufox + Playwright Recipes

Minimal, copy-pasteable snippets using the sync API (`from camoufox.sync_api import Camoufox`). Swap to `AsyncCamoufox` + `await` for async contexts — the method names are identical.

Use these for interactive/multi-step sessions where a one-shot CLI invocation isn't enough (login flows, pagination, structured extraction).

## Basic fetch + get page content

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com")
    html = page.content()
    print(html)
```

## Wait strategies

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()

    # Wait for network to go quiet (good for SPA/JS-heavy pages)
    page.goto("https://example.com", wait_until="networkidle")

    # Wait for a specific element to appear
    page.wait_for_selector("#results", timeout=10_000)

    # Wait for a specific element to be gone (e.g. a loading spinner)
    page.wait_for_selector(".spinner", state="detached", timeout=10_000)
```

## Login / form flow

```python
from camoufox.sync_api import Camoufox

with Camoufox(humanize=True) as browser:
    page = browser.new_page()
    page.goto("https://example.com/login")

    page.fill("#username", "myuser")
    page.fill("#password", "mypassword")

    with page.expect_navigation():
        page.click("button[type=submit]")

    page.wait_for_selector("#dashboard")
    print("Logged in:", page.url)
```

## Pagination / scroll to load lazy content

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com/feed")

    prev_height = 0
    for _ in range(20):  # cap iterations to avoid infinite loop
        page.mouse.wheel(0, 3000)
        page.wait_for_timeout(800)  # let lazy content load
        height = page.evaluate("document.body.scrollHeight")
        if height == prev_height:
            break
        prev_height = height

    items = page.query_selector_all(".feed-item")
    print(f"Loaded {len(items)} items")
```

Click-through pagination variant:

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com/list?page=1")

    all_rows = []
    while True:
        rows = page.query_selector_all("table tr")
        all_rows.extend(rows)

        next_btn = page.query_selector("a.next-page:not(.disabled)")
        if not next_btn:
            break
        with page.expect_navigation():
            next_btn.click()
```

## Screenshot and PDF

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com")

    page.screenshot(path="page.png", full_page=True)
```

Note: Playwright's `page.pdf()` is documented as Chromium-only upstream. Camoufox is a Firefox fork, so treat `page.pdf()` as unverified/likely unsupported here — test it directly rather than assuming it works, and prefer `page.screenshot(full_page=True)` (optionally piped into an external HTML-to-PDF tool) as the reliable path for document capture.

## Extracting structured data

```python
from camoufox.sync_api import Camoufox

with Camoufox() as browser:
    page = browser.new_page()
    page.goto("https://example.com/products")

    products = []
    for card in page.query_selector_all(".product-card"):
        products.append({
            "title": card.query_selector(".title").inner_text(),
            "price": card.query_selector(".price").inner_text(),
            "url": card.query_selector("a").get_attribute("href"),
        })

    print(products)
```

## Cookies / persistent profile reuse

Persist cookies and storage across separate script runs so a login survives — avoids re-authenticating every session.

```python
from camoufox.sync_api import Camoufox

with Camoufox(
    persistent_context=True,
    user_data_dir="./camoufox-profile",
) as browser:
    page = browser.new_page()
    page.goto("https://example.com/dashboard")
    # If a prior run logged in and saved this profile dir,
    # the session cookies are already present here.
    print(page.url)
```

First run: perform the login flow once inside this same `user_data_dir`. Subsequent runs reuse the saved cookies/localStorage automatically — no re-login needed until the session expires server-side.

## Proxy + geoip + humanize together

Keep IP, timezone, and locale consistent when proxying — mismatches (e.g. US timezone with a German exit IP) are a common detection signal.

```python
from camoufox.sync_api import Camoufox

with Camoufox(
    proxy={
        "server": "http://proxy.example.com:8000",
        "username": "user",
        "password": "pass",
    },
    geoip=True,        # derive timezone/locale from the proxy's exit IP
    humanize=True,     # human-like cursor movement
) as browser:
    page = browser.new_page()
    page.goto("https://example.com")
    print(page.content())
```

`geoip=True` requires the `[geoip]` install extra (`pip install -U "camoufox[geoip]"`). Without it, geoip resolution silently has nothing to look up against.
