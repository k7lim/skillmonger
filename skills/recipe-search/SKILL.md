---
name: recipe-search
description: Search and retrieve structured recipes from curated high-quality sources
---

# Recipe Search & Inspiration

## When to use

- Recipe search for specific dish, cuisine, or ingredient
- Meal planning, cooking inspiration
- Comparing recipes across trusted sources
- Dietary-specific search (vegetarian, vegan, healthy, budget)

## Prerequisites

Run `scripts/check-prereqs.sh` in this skill directory.

- `"ready": true` → proceed
- `"ready": false` → resolve via table, offer to run install commands

| Check | If missing |
|-------|-----------|
| python3 | `brew install python3` or `apt install python3` |
| recipe-scrapers | Offer to run: `pip install recipe-scrapers` |
| scrape-schema-recipe | Offer to run: `pip install scrape-schema-recipe` |

## Workflow

### Step 1: Parse intent

Extract from request:
- **Cuisine/dish** — "Korean fried chicken", "pasta carbonara"
- **Dietary needs** — vegetarian, vegan, gluten-free
- **Constraints** — quick/under 30 min, budget, beginner
- **Goal** — single recipe, comparison, meal planning

### Step 2: Search

1. Read `references/sources.md`, pick 3-5 domains from **Cuisine Quick-Reference** matching intent
2. WebSearch with `site:` scoping:
   ```
   chicken tikka masala recipe site:seriouseats.com OR site:recipetineats.com OR site:indianhealthyrecipes.com
   ```
3. No good results → broaden: drop `site:` or widen cuisine tags
4. Collect 2-3 promising URLs

### Step 3: Retrieve

```bash
python3 scripts/fetch-recipe.py "<url1>" "<url2>"
```

Structured JSON output: title, ingredients, instructions, timing, servings. If result has `"error"` key, skip it, try another URL.

### Step 4: Present

- Best-matching recipe with title, source, time, servings, ingredients, instructions
- Offer alternatives if multiple retrieved
- Note substitutions for dietary needs

## Examples

**"Find me a good chicken tikka masala recipe"**
→ Search `site:indianhealthyrecipes.com OR site:recipetineats.com OR site:seriouseats.com`, retrieve top 2, present best match.

**"Something Korean for dinner, under 45 minutes"**
→ Search `site:maangchi.com OR site:thewoksoflife.com OR site:recipetineats.com` + "quick korean dinner", present with timing highlighted.

**"Vegan dessert ideas"**
→ Search `site:minimalistbaker.com OR site:cookieandkate.com` + "vegan dessert", retrieve 2-3, present as list.

---

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate.py <file>
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

Save the recipe JSON first; the evaluator reads it as a file.

Script scores 4-5 → self-assess: did recipe match cuisine/dietary/time needs? Score it lower if not.

Score it on the standard scale: 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"recipe-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"recipe-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
