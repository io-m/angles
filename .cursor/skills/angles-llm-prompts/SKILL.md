---
name: angles-llm-prompts
description: Edit Angles reframe system prompts and style tone. Use when changing prompts.ts, style copy, output length rules, or adding a new reframe style.
---

# Angles LLM prompts

Prompts live in `backend/src/lib/prompts.ts` as `SYSTEM_PROMPTS: Record<Style, string>`.

## Shared rules (keep in every style)

- 1–3 sentences max
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
4. Extend tests. Do not special-case the LLM client per style.

Do not put prompt text in the iOS app or in `llmClient.ts`.
