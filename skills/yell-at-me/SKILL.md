---
name: yell-at-me
description: >
  Yell the human's name where their eyes land when they come back from a long
  agent turn, about the one next step only they can do. Use when the user asks
  to be yelled at or pinged when something needs them, says they are stepping
  away, or invokes /yell-at-me; stays on every response until "stop yelling".
argument-hint: "[name to yell]"
---

Yell the human's name where their eyes land when they come back, and only about a step that needs them.

## Onboarding

Run `scripts/check-prereqs.sh` in this skill directory. It prints the stored name, or candidates from `git config user.name` and `$USER` when none is stored.

| Result | Do |
|---|---|
| A name was given (argument, or in the request) | That is the name. Save it: `scripts/set-name.sh "<name>"`. |
| `ready: true` | Yell `context.yell`. Say nothing about setup. |
| `ready: false` | Ask one question: "What should I yell?", offering `context.candidates[0]`. Save the answer with `scripts/set-name.sh "<name>"`. |

The name is stored per home directory, so a sandbox home asks once too. If the save fails, use the name for this session and suggest `YELL_AT_ME_NAME` in the environment.

## The landing zone

While a long turn runs, the human is elsewhere. When they return they see the **landing zone**: the last lines of the turn's final message. Text written between tool calls has scrolled away. Yell in the landing zone; write everything else for a reader who is present.

## What earns a yell

A yell is a **demand** on the human. Reserve the name for demands so it keeps its signal.

| Situation | Yell |
|---|---|
| The turn stops because only the human can act: approve, answer, log in, pay, choose | Yes |
| A go-ahead is needed before something hard to reverse | Yes |
| Something failed and could not be got past | Yes, with what they should do |
| Only their eyes can check it (a UI, a dashboard, a rendered page) | Yes |
| Done, nothing needed | No. End with "Nothing needed from you." |
| Progress, findings, caveats, FYI | No |

## How to yell

One yell is one line: the name in caps with an exclamation mark, bold, then one imperative sentence that names the step and, when it fits, why.

> **KEVIN!** Approve the permission prompt below; it lets me push to origin.

- One yell per demand. The same demand yelled twice is noise.
- The sentence names something the human can do now. "Something is wrong" is not a yell; "Run `gcloud auth login`, then say go" is.
- The yell form (caps, exclamation mark) appears on yell lines and nowhere else.

## Where to yell

| Moment | Placement |
|---|---|
| The turn ends with one demand | The final message ends on the yell. |
| The turn ends with two or more demands | Yell at the point each arises, then end on a yelling summary. |
| A call is about to block on the human (permission prompt, question, interactive login) | Yell in the text immediately before the call; that text is on screen while it waits. |
| Text between tool calls | Plain text. Nobody is there. |

## Yelling summary

The summary re-centers every demand in one place, so a distracted reader acts from the last lines alone:

> **KEVIN!** 3 things, in order:
> 1. Approve the permission prompt below (push to origin).
> 2. Decide: keep `useMemo` or revert; both versions are in the diff.
> 3. Check the staging page renders; only you have the login.

Order: blocked first, then decisions, then checks. Each line stands alone; acting on it needs no scrolling up.

## Escalation

When the harness has a push-notification tool and the turn ends on a yell, send the first yell line once (plain text, under 200 characters). The text yell stays; the notification is the version that reaches them away from the screen.

## Persistence

ACTIVE EVERY RESPONSE once on. Off only when the user says "stop yelling" or "quiet mode". If unsure whether it is on, it is on.

---

## After Execution

Score every turn that yelled, or that blocked on the human and should have.

Self-assess, or ask the human once they are back:

> When you came back, did the last lines tell you the one thing to do?

Map: 5=every demand yelled once, in the landing zone, and nothing else yelled; 4=every demand landed, with one yell misplaced or one extra; 3=they had to scroll up to find what to do; 2=yells on progress, or a demand with no yell; 1=the turn blocked on the human with no yell at all.

Append one JSON line to `FEEDBACK.jsonl` in this skill directory — the copy you
are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"yell-at-me","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"llm","session":"<this session's id>","schema_version":1}
```

Drop `session` if you do not know this session's id. That line is the whole
record: nothing in `CONFIG.yaml` is edited by a run.

Use `"source":"user"` when the score came from the user rather than from your
own assessment.
