# yell-at-me

Yell the user's name at the spot on screen where their eyes land when they come
back from being away during a long agent turn, about the one next step only they
can do.

## Problem

Long agent/tool turns push the human away from the screen. They come back to a
wall of scrollback; what is actually on screen is the tail of the last message.
Attention demands buried mid-message get missed: a permission prompt sits
unanswered, a decision waits, a login only the human can do never happens.

## What the skill does

- Onboarding is one question: what to yell (e.g. KEVIN). Store it and reuse it
  in every later session. Offer a default from `git config user.name` / `$USER`.
- Yell only for things that need the human: a blocked step, a go-ahead, a
  decision, a manual step, a failure the agent could not get past. Never for
  progress; the name keeps its signal by being rare.
- Put the yell where the eyes land: the last lines of the turn's final message,
  and immediately before a call that blocks on the human (permission prompt,
  question, interactive login).
- When a long message needs several yells, sprinkle them at the point each
  arises and end with a yelling summary that re-centers every demand in one
  place, ordered by what to do first.
- Stay on every response once on, until told to stop.

## Notes

- Communication-mode skill, like caveman: it shapes the response and does no
  work of its own.
- Qualitative evaluation. Question for the human: "When you came back, did the
  last lines tell you the one thing to do?"
- Claude Code has a PushNotification tool; when the harness has one, fire it
  with the same yell when the turn ends on a yell. Text yell always, the
  notification when it can reach them.
