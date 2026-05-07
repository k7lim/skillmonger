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

**Hybrid feedback approach:**

1. Run `scripts/evaluate.sh` on the feedback you generated
2. If score < 4, fix issues and re-run until score >= 4
3. On odd-numbered iterations (check `iteration_count` in CONFIG.yaml), ask: "Would you send this feedback to the student as-is?" Map: Yes=5, With minor edits=4, Needs work=3, No=2
4. On even iterations, self-assess against the rules table above

Log to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO 8601>","skill":"homework-feedback-writer","version":"<from CONFIG.yaml>","prompt":"<request>","outcome":<1-5>,"note":"...","source":"script|user|llm","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
