---
name: homework-feedback-writer
description: Write clear, specific, actionable feedback for student work. Avoids AI slop, hedging, and passive voice.
---

# Homework Feedback Writer

Write feedback that students will actually read and act on.

## Prerequisites

Run `scripts/check-prereqs.sh`. No external dependencies required.

## Workflow

### Step 1: Get the student work

If not provided, ask for it. Accept pasted text or file path.

### Step 2: Write feedback

Follow these rules strictly:

| Rule | Do | Don't |
|------|-----|-------|
| Be specific | "Paragraph 2 needs a topic sentence" | "Some organizational issues" |
| Assert | "This fails because you cite no evidence" | "This might perhaps be less effective" |
| Be brief | "Weak thesis. What's your claim?" | Long explanations |
| Use active voice | "Strengthen your thesis" | "The thesis could be strengthened" |

**Banned words** (delete on sight): delve, crucial, pivotal, showcase, foster, landscape, tapestry, groundbreaking, utilize, facilitate, leverage, underscore

**Banned hedges**: somewhat, arguably, perhaps, a bit, tends to, might, could potentially

**Replace**: "serves as" -> "is", "in order to" -> "to", "a wide variety of" -> "many"

### Step 3: Validate output

Run `scripts/evaluate.sh` on your feedback. Fix any flagged issues before presenting to user.

```bash
echo "<your feedback>" | scripts/evaluate.sh
```

Score meanings:
- 5: No issues detected
- 4: Minor issues (1-2 hedge words)
- 3: Several issues need fixing
- 1-2: Rewrite required

## Example

**Student excerpt**: "The Civil War was a very important event that happened in America..."

**Bad feedback**: "The introduction could perhaps benefit from a more specific thesis statement that delves deeper into the crucial aspects of your argument."

**Good feedback**: "Your thesis is vague. 'Important event' says nothing. What specifically about the Civil War are you arguing? State your claim in one sentence."

---

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate.sh   # takes the output on stdin, or as its first argument
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

**Hybrid feedback approach:**

1. Run `scripts/evaluate.sh` on the feedback you generated
2. If score < 4, fix issues and re-run until score >= 4
3. "Would you send this feedback to the student as-is?" Map: Yes=5, With minor edits=4, Needs work=3, No=2
4. On even iterations, self-assess against the rules table above

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"homework-feedback-writer","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"homework-feedback-writer","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
