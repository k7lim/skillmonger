# Skill Design Template

> Fill this out before writing SKILL.md. The goal: separate what can be **known deterministically** from what requires **reasoning**.

## Skill Overview

**Name:** [skill-name]
**One-liner:** [What does this skill do?]

---

## State Detection

What needs to be true before this skill can work? List each prerequisite and whether it can be checked programmatically.

| Prerequisite | Can script detect it? | How? |
|--------------|----------------------|------|
| Example: Node.js installed | ✅ Yes | `command -v node` |
| Example: User has API key | ❌ No | Must ask user |
| | | |

**Action:** For each "Yes", add a check to `scripts/status-check.sh`. For each "No", add a question to SKILL.md's workflow.

---

## Decision Points

Where does the agent need to make choices? Identify what informs each decision.

| Decision | Data needed | Source |
|----------|-------------|--------|
| Example: Which template to use | User's video concept | Ask user |
| Example: Install missing deps? | What's missing | Script output |
| | | |

**Action:** Script outputs should provide the data. SKILL.md should explain how to interpret it.

---

## Actions

What does this skill actually do? Separate mechanical actions from creative ones.

### Deterministic Actions (script candidates)
- [ ] Example: Create project directory structure
- [ ] Example: Install dependencies
- [ ]

### Flexible Actions (prompt guidance)
- [ ] Example: Design component architecture based on user needs
- [ ] Example: Choose animation style
- [ ]

---

## Error Scenarios

What can go wrong? How should each be handled?

| Error | Detection | Response |
|-------|-----------|----------|
| Example: npm install fails | Exit code ≠ 0 | Show error, suggest fixes |
| Example: Unsupported OS | Script detects OS | Explain limitation |
| | | |

---

## Status Check Script Design

Based on the above, your `scripts/status-check.sh` should output JSON like:

```json
{
  "ready": true|false,
  "checks": [
    {"name": "node", "status": "ok|missing|outdated", "version": "...", "required": "..."},
    {"name": "...", "status": "...", ...}
  ],
  "context": {
    // Any other useful data for the agent
  }
}
```

The agent reads `ready` to know if it can proceed, and uses `checks` to know what to fix.

---

## SKILL.md Structure

Once you understand the above, your SKILL.md should:

1. **Prerequisites section** → "Run `scripts/status-check.sh` and interpret results"
2. **Interpretation table** → Map status values to actions
3. **Workflow** → Guide the agent through decision points
4. **Examples** → Show expected inputs/outputs

---

## Checklist Before Promoting

- [ ] `scripts/status-check.sh` covers all detectable prerequisites
- [ ] Script outputs valid JSON
- [ ] SKILL.md explains how to interpret every status
- [ ] Decision points have clear guidance
- [ ] Error scenarios are documented
- [ ] Tested in sandbox with edge cases
