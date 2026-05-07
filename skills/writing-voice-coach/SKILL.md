---
name: writing-voice-coach
description: Critique writing for AI-generated patterns — slop vocabulary, hedging, vagueness, bloat, formatting tells, structural tells, fake depth, chatbot artifacts. Provides specific rewrites.
---

# Writing Voice Coach

Analyze text for patterns that make it sound AI-generated. Provide direct critique with specific rewrites.

## Prerequisites

Run `scripts/check-prereqs.sh`.

| Missing | Action |
|---------|--------|
| python3 | `brew install python3` or `apt install python3` — offer to run |

## Workflow

### Step 1: Get text

Accept inline text or file path. If none provided, ask: "Paste or point me to the text you want critiqued."

### Step 2: Scan for issues

Check against all categories. See `references/slop-vocabulary.md` for full word lists and examples.

| Category | What to flag | Example trigger |
|----------|-------------|-----------------|
| Slop vocabulary | Words that scream AI | delve, utilize, leverage, vibrant |
| Hedging | Qualifiers hiding opinion | somewhat, arguably, perhaps |
| Vagueness | Statements true of anything | "significant growth," "various factors" |
| Over-explanation | Telling reader how to feel | remarkably, surprisingly, importantly |
| Bloat | More words than needed | "in order to" → "to" |
| Formatting tells | Em dash overuse, emoji, bold spam, curly quotes | three em dashes in one paragraph |
| Structural tells | Rule of three, staccato sentences, generic headings, title case | every list has exactly 3 items |
| Fake depth | Negative parallelism, synonym cycling, significance inflation | "not just X; it's Y" |
| Copula avoidance | Fancy verbs where "is"/"has" works | "serves as" → "is," "boasts" → "has" |
| Chatbot artifacts | Preamble, sign-off, enthusiasm, disclaimers | "I hope this helps!" "Certainly!" |
| Generic endings | Fortune cookie conclusions | "The future looks bright" |

### Step 3: Deliver critique

For each issue found:
1. Quote the offending text
2. Name the category
3. Explain why it sounds AI-generated
4. Provide a specific rewrite

Prefer conversational tone. Active voice, short words, first person where it fits.

Orwell's escape hatch: break any rule sooner than say anything outright barbarous.

### Step 4: Summarize

End with: "Found X issues across Y categories."

If clean: "This reads human. No AI tells detected."

---

## After Execution

**Script evaluation:** Run `scripts/evaluate.py` on the original text:

```bash
echo "$ORIGINAL_TEXT" | python3 scripts/evaluate.py
```

**User evaluation (alternate runs):** Ask: "Does this critique help you see where your writing sounds AI-generated?" Map: Yes=5, Mostly=4, Somewhat=3, Not really=2, No=1.

On alternate runs, self-assess instead: Does the critique quote specific text? Provide concrete rewrites? Cover the right categories? Map to 1-5.

**Log both** to `FEEDBACK.jsonl`:

```json
{"ts":"<ISO 8601>","skill":"writing-voice-coach","version":"0.1.0","prompt":"<request>","outcome":<1-5>,"note":"<summary>","source":"script|user|llm","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
