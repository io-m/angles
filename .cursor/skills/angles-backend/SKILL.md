---
name: angles-backend
description: Extend or change the Angles Hono API (reframe, health, validation, LLM client, Railway). Use when editing backend TypeScript, adding routes, swapping the LLM provider, or wiring future auth/DB.
---

# Angles backend

## Layout

- `src/app.ts` — middleware, route mount, `onError`
- `src/index.ts` — Node `serve()`, signing-key and schema checks, pool shutdown
- `src/routes/reframe.ts` — `POST /reframe`; signs the cook and every result (`src/lib/cookSignature.ts`)
- `src/routes/cards.ts` — card CRUD. `POST` verifies the `/reframe` signatures and `safety: none` before storing. `PATCH` sets `isPublic`. `GET ?saved=true` is the viewer's saved cards, `?saved=false` their own; `?style=` means the card has that reframe; `?before=createdAt|id` pages. `PUT/DELETE /:id/decision` writes or clears the viewer's whole save/pass row.
- `src/db/schema.ts` / `src/db/cards.ts` — Drizzle schema and SQL seam. Saves and passes are one `card_decisions` row per viewer and card (`src/db/decisions.ts`); `isPublic` lives on `cards`. There are no pins. Saved cards stay in the library only while they are public.
- `src/db/cursor.ts` / `src/lib/cursor.ts` — one `createdAt|id` cursor for author and library pages. `cards.created_at` has millisecond precision so the cursor round-trips through a JS `Date`.
- `src/lib/feedRanking.ts` — the only place to tune Home stack order. `src/db/stack.ts` loads the signals and builds each page.
- `src/routes/stack.ts` — `GET /stack?limit&session&seen`, answering `{ cards, session, exhausted }`.
- `src/lib/decision.ts` — decision call, JSON parsing, one repair retry, metadata mapping
- `src/lib/llmClient.ts` — `generateReframe({ text, systemPrompt })`, `generateJson({ ... })`
- `src/lib/prompts.ts` — `DECISION_PROMPT`, `SYSTEM_PROMPTS`, length budgets
- `src/types/index.ts` — shared types; update Swift models in the same change

## Home order

`FEED_RANKING=resonance` ranks `GET /stack` for the signed-in viewer. Unset or `chronological` is newest-first, so the rollback is one variable. Do not add the flag to production fail-fast config.

The score is freshness, saves from distinct other people, closeness to the viewer's themes (from what they write and save, minus a little per pass), follows, a second chance for an unsaved young post, session-stable jitter, and a penalty for a card returning after a pass. Intensity is capped by pacing, never rewarded; two heavy cards are never side by side while a lighter one is left. Passes never count against a card for anyone else.

Candidates are the newest 1000 public cards by other people that the viewer has not decided, read as of the visit's `startedAt`. Paging is by exclusion, not offset: the phone echoes `session` and names the cards it was handed whose decision is not confirmed yet in `seen`. A card passed once returns after 12 hours while it has an angle the viewer never saw. House cards (`users.kind = 'house'`) come only after the community's are used up. Do not put other people's save counts on the wire. Author and library lists stay chronological. Weights and spread limits are in `BUILD.md` section 14.

## Adding a route

1. New file under `src/routes/`.
2. Mount in `createApp()`.
3. Zod at the boundary. Typed handler. `{ error, code }` on failure.
4. Cover with `app.request()` in `src/app.test.ts` (or a colocated `*.test.ts`).

## The reframe flow

One decision call (`generateJson`) then one batched style JSON call (`STYLE_BATCH_PROMPT`) for the chosen styles. Recook (`styles` length 1) uses `generateReframe`. `continue` never runs a style call. Metadata and the cleaned English thought come from the decision only — the raw user text never reaches a style prompt, and neither is ever logged. Cap concurrent provider calls at 3. A cook has a 10s wall deadline; a hung provider times out at 8s. Abort the provider fetch if the client disconnects.

## Swapping the LLM

Change only `src/lib/llmClient.ts`. Keep `generateReframe`, `generateJson`, and `LlmError`. A new provider needs a JSON mode. Honor `LLM_TIMEOUT_MS` and `AbortSignal`. Do not send `LLM_API_KEY` to the client. Do not log `text`.

## Auth / DB

`requireAuth` + `getOwnerUserId()` is the owner seam (`backend/src/lib/authStub.ts`). Better Auth (Apple ID tokens, bearer plugin) lives in `backend/src/auth.ts`. Schema is Drizzle + local Postgres using `postgres` (postgres.js), not Neon. Sign in with Apple is the only login.

## Deploy

Dockerfile in `backend/`. No `railway.json`. Health check `/health`. `PORT` from the environment.
