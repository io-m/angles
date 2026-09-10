---
name: angles-llm-prompts
description: Edit Angles reframe system prompts and style tone. Use when changing prompts.ts, style copy, output length rules, or adding a new reframe style.
---

# Angles LLM prompts

All prompt copy lives in `backend/src/lib/prompts.ts`: `DECISION_PROMPT` (triage), `SYSTEM_PROMPTS: Record<Style, string>` (the four reframes), plus the repair and force-ready fragments.

## DECISION_PROMPT

The one call that decides `continue` vs `ready`, cleans the thought into card copy, picks which styles to write, and fills the matching metadata. It must keep returning one JSON object matching the shape `decision.ts` validates — change both together, and update the schema block inside `DECISION_REPAIR_PROMPT` too.

Load-bearing rules, do not weaken them casually:

- `ready` is the default. Heavy is not the same as unclear: grief, loss, self-hatred and hopelessness get cooked, with the wrong styles skipped.
- Safety is only suicide, self-harm, harm to others, or abuse. Only those mention a crisis line, and they never get a reframe.
- Skip reasons are written as user-facing sentences: a recook of a skipped style returns that reason verbatim.
- Worked examples at the bottom of the decide section carry a lot of weight on small models. Test any edit against them.

## Length budgets

Exported as constants so the route can enforce them: thought 8–22 words / 40–140 chars (hard reject past 32 words or 180 chars), reframe 12–32 words / 80–190 chars (retry once past 250 chars, then trim). `thought_original_cleaned` shares the thought budget and must fit the same card.

## Shared rules (keep in every style)

- 1–3 sentences max, inside the length budget
- No bullets, headings, or markdown
- No therapy-speak clichés
- Never mock or diagnose the user
- Do not invent facts they did not state

## Current styles

| Key | Tone |
| --- | --- |
| `stoic` | Control vs not; no sugarcoating |
| `optimistic` | Genuine silver lining; warm; forward-looking |
| `humorous` | Gentle humor; never punch down |
| `tough_love` | Challenge/lesson; direct; no coddling |

## Adding a style

1. Add the key to `STYLES` in `backend/src/types/index.ts`.
2. Add `SYSTEM_PROMPTS` copy (include shared constraints).
3. Add the Swift `Style` case with the same raw value.
4. Teach `DECISION_PROMPT` when to skip it.
5. Extend tests. Do not special-case the LLM client per style.

Do not put prompt text in the iOS app or in `llmClient.ts`.
