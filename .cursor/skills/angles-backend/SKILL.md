---
name: angles-backend
description: Extend or change the Angles Hono API (reframe, health, validation, LLM client, Railway). Use when editing backend TypeScript, adding routes, swapping the LLM provider, or wiring future auth/DB.
---

# Angles backend

## Layout

- `src/app.ts` — middleware, route mount, `onError`
- `src/index.ts` — Node `serve()`, signing-key and schema checks, pool shutdown
- `src/routes/reframe.ts` — `POST /reframe`; signs the cook and every result (`src/lib/cookSignature.ts`)
- `src/routes/cards.ts` — card CRUD. `POST` verifies the `/reframe` signatures and `safety: none` before storing. `PATCH` sets per-style `isFavorite` (requires `style`) and/or `isPublic`. `GET ?style=` means the card has that reframe; `?favorite=` means any liked style; `?before=createdAt|id` pages.
- `src/db/schema.ts` / `src/db/cards.ts` — Drizzle schema and SQL seam. Favorites live on `card_reframes`; `isPublic` lives on `cards`. There are no pins. The library includes hearted cards only while they are public.
- `src/db/cursor.ts` / `src/lib/cursor.ts` — one `createdAt|id` cursor for author and library pages, and for Home when ranking is off. `cards.created_at` has millisecond precision so the cursor round-trips through a JS `Date`.
- `src/lib/feedRanking.ts` — the only place to tune Home order. `src/db/feed.ts` loads the signals and pages the result.
- `src/routes/feed.ts` — `GET /feed`. Optional `style` selects a Home shelf. Life area and mood are the facets.
- `src/lib/decision.ts` — decision call, JSON parsing, one repair retry, metadata mapping
- `src/lib/llmClient.ts` — `generateReframe({ text, systemPrompt })`, `generateJson({ ... })`
- `src/lib/prompts.ts` — `DECISION_PROMPT`, `SYSTEM_PROMPTS`, length budgets
- `src/types/index.ts` — shared types; update Swift models in the same change

## Home order

`FEED_RANKING=resonance` ranks `GET /feed` for the signed-in viewer. Unset or `chronological` is newest-first, including a style filter, so the rollback is one variable. Do not add the flag to production fail-fast config.

All (no `style`) scores freshness, hearts from distinct people, overlap with the viewer's own recent life areas and moods, follows, a second chance for an unhearted young post, and session-stable jitter. Intensity is capped by the page spread, never rewarded. A style shelf keeps that score, then blends general taste toward hearts on that style (full confidence at five), adds capped hearts on that exact angle, and a small cover tie-break. Jitter is salted by style. One heart cannot take over a shelf. With no `style`, the All score and the mixed opening angle stay as they are.

Candidates are the newest 1000 matching public cards, frozen for the session. The response cursor is an opaque `seed|startedAt|offset`. `after` stays newest-first even while ranking is on. Do not put other people's per-style heart counts on the wire. Author and model lists stay chronological. Weights and spread limits are documented in `BUILD.md` sections 14 and 15.

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
