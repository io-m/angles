---
name: angles-llm-prompts
description: Edit Angles reframe system prompts and style tone. Use when changing prompts.ts, style copy, output length rules, or adding a new reframe style.
---

# Angles LLM prompts

All prompt copy lives in `backend/src/lib/prompts.ts`:

- `DECISION_PROMPT` (triage), plus the repair and force-ready fragments.
- `STYLE_VOICES`, one entry per style: label, voice, technique menu, banned openers, how it meets a heavy thought (`heavy`), and how it meets good news (`savor`).
- `STYLE_BATCH_PROMPT`: one JSON call that writes a hidden plan and then every chosen style.
- `SYSTEM_PROMPTS: Record<Style, string>`: single-style recook and lint rewrite.
- `GOLD_CARDS`: worked examples shared by both writer prompts.
- `recookUserPrompt`, `lintRewriteUserPrompt`, and `localLanguage`.

The pipeline that calls them is `backend/src/lib/cook.ts`; `reframeLint.ts` checks the output. Measure every prompt change with `pnpm llm:eval` (below) before shipping it.

## DECISION_PROMPT

The one call that decides `continue` vs `ready`, cleans the thought into card copy, picks which styles to write, and fills the matching metadata, including 0–2 `distortions` (thinking traps from `DISTORTIONS`). It must keep returning one JSON object matching the shape `decision.ts` validates (`DECISION_JSON_SCHEMA` and `rawDecisionSchema`) — change both together, and update the schema block inside `DECISION_REPAIR_PROMPT` too.

Load-bearing rules, do not weaken them casually:

- `ready` is the default. Heavy is not the same as unclear: grief, loss, self-hatred and hopelessness get cooked. Styles adapt to a heavy thought (each voice's `heavy` line) rather than being skipped; skip only a real mismatch. `chooseStyles` always writes stoic and optimistic, and removes tough love from a loss the person blames themselves for, whatever the model says.
- If you can name the situation in one clause, cook it. Broken English, typos, rudeness, and irritation at family are thoughts. Never bounce with "I didn't catch a thought" / "try again".
- Good news is a thought too. A happy moment with no complaint cooks on the first turn as a savor cook (`SAVOR_RULES` plus each voice's `savor` line): keep the gladness, never hunt for a hidden problem. A glad-and-worried thought cooks the worry and keeps the good fact. On a first turn that already looks like a thought, a "what are you stuck on" continue is rejected as a bounce and repaired.
- The first turn is framed in English (`They typed: …`) so a short non-English input still gets an English decision.
- Safety is only suicide, self-harm (including passive wishes not to wake up or to disappear), harm to others, or abuse. They never get a reframe. `safetyScreen.ts` catches explicit and passive self-harm phrasing and overrides a model's `none`. It has lists for English, Croatian/Bosnian/Serbian, German, Spanish, French, Portuguese, Italian, Dutch, Polish, Russian, Ukrainian, Turkish, Indonesian, Swedish, Danish, and Norwegian, and on a ready turn it also reads the model's English `thought`, which covers every other language. Every new phrase needs an idiom test that must not match ("mourir de rire"). Keep the prompt's passive examples and the screen in step. The model never writes a phone number, hotline, or country; `crisisResources.ts` adds the line for the phone's region, and a crisis message containing a digit is replaced with `SAFETY_FALLBACK_MESSAGE`. An unknown safety label is read as `self_harm`.
- Skip reasons are written as user-facing sentences: a recook of a skipped style returns that reason verbatim.
- Worked examples at the bottom of the decide section carry a lot of weight on small models. Test any edit against them.

## Length budgets

Exported as constants so the pipeline can enforce them:

- Thought: 8–30 words, 40–200 characters. A decision past 40 words or 240 characters is repaired once with the counts in the hint, and the repair pass may land at up to 50 words or 300 characters (the card grows vertically). `thought_original_cleaned` shares the budget.
- Reframe: 12–45 words, 80–280 characters. Past 340 characters it is trimmed at a sentence boundary; past 280 the lint flags `too_long` and asks for one rewrite.

The batch output cap is computed from these (`writerMaxOutputTokens`), doubled for a bilingual cook. Change a budget and the cap follows.

## The writer

`STYLE_BATCH_PROMPT` writes every chosen style in one JSON call (temperature 0.8). Load-bearing parts:

- **"Each JSON field is that style only."** Tests use this exact line to tell the batch from the decision call. Humorous must not sound like tough love.
- **Plan first.** A hidden `plan` field names one technique id per style from `STYLE_VOICES` plus a 3–8 word insight, all different. It is never returned to the phone; a rewrite uses it to steer away from the same technique.
- **Context rules.** Timeframe (past → acceptance, ongoing → control or the next step, future → likelihood or preparation), intensity (4–5 gentler and shorter, humor lighter but still a joke), and traps (push against the named distortion in plain words, never the label).
- **Their language.** When they did not write English, each style field is `{ "en", "local" }`. `local` is how a native speaker would say the same answer to a friend, not a translation. The public card is English; the author sees `local` as `reframeOriginal`.

Each voice has banned openers; `reframeLint.ts` reads `SHARED_BANNED_OPENERS` and `STYLE_VOICES[style].bannedOpeners` directly, so add an opener in one place.

## Lint and rewrite

`reframeLint.ts` flags `too_short`, `too_long`, `question`, `digits` (a phone number, long figure, or percentage the thought did not have), `markdown`, `cliche`, `opener`, and `overlap` (two styles, or a recook and the answer it replaces, saying the same thing). Everything except `too_short` earns one targeted rewrite through `lintRewriteUserPrompt` (call kind `rewrite`), which names the problems from `LINT_REWRITE_NOTES`. A rewrite ships only if it has fewer problems. The answer in their language gets the language-blind checks (`lintLocal`); one that still has a foreign number is dropped.

## Recook

`recookUserPrompt` sends the signed cook's thought and context, plus the answer being replaced with the instruction to use a different technique and a different insight. It runs at temperature 0.95 with that style's `SYSTEM_PROMPTS`, and no decision call.

## Shared rules (keep in every style)

- 1–3 sentences, inside the length budget
- No bullets, headings, labels, or markdown
- No therapy-speak clichés, no technique or trap names, no diagnosis
- No phone numbers, hotlines, statistics, or percentages
- Never mock, belittle, or punch down at the user
- Do not invent facts, people, amounts, or outcomes they did not state
- No questions

## Current styles

| Key | Voice | Techniques |
| --- | --- | --- |
| `stoic` | Austere, calm, short declaratives; steadies, does not cheer | dichotomy of control, judgment vs event, view from above, impermanence, obstacle is the way, amor fati |
| `optimistic` | Bright and warm; every hope rests on something already true; no "at least" | what it proves, already working, it won't last, door it opens, what you'll know |
| `humorous` | A real joke on the situation or the brain, never the person | dramatic narrator, absurd escalation, deadpan understatement, mock official, comic specificity |
| `tough_love` | A coach on their side; short imperatives, no softeners, no jokes | name the excuse, call the pattern, cost of waiting, next 24 hours |

## Measuring a change

```bash
cd backend
pnpm llm:eval --label=my-change --decision=mistral-small-latest --writer=gpt-4.1-mini
pnpm llm:eval --compare=eval/out/<before>.json,eval/out/<after>.json
```

The golden thoughts are `backend/eval/thoughts.json`. The report gives kind, category, and safety accuracy, styles per cook, answers in their language, lint and rewrite rates, overlap, cost per cook, and judge scores per style (judge `gpt-4.1-mini` by default). Run one eval at a time: parallel runs share the provider rate limits, and the eval has no fallbacks, so a 429 becomes an error case.

## Adding a style

1. Add the key to `STYLES` in `backend/src/types/index.ts`.
2. Add its `STYLE_VOICES` entry (voice, techniques, banned openers, heavy, savor) and a gold answer in every `GOLD_CARDS` card.
3. Add the Swift `Style` case with the same raw value.
4. Teach `DECISION_PROMPT` when it fits.
5. Extend tests and run the eval. Do not special-case the LLM client per style.

Do not put prompt text in the iOS app or in `llmClient.ts`.
