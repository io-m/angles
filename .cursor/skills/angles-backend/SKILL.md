---
name: angles-backend
description: Extend or change the Angles Hono API (reframe, health, validation, LLM client, Railway). Use when editing backend TypeScript, adding routes, swapping the LLM provider, or wiring future auth/DB.
---

# Angles backend

## Layout

- `src/app.ts` — middleware, route mount, `onError`
- `src/index.ts` — Node `serve()`, schema check, pool shutdown
- `src/routes/reframe.ts` — `POST /reframe`
- `src/routes/cards.ts` — card CRUD
- `src/db/schema.ts` / `src/db/cards.ts` — Drizzle schema and SQL seam
- `src/lib/decision.ts` — decision call, JSON parsing, one repair retry, metadata mapping
- `src/lib/llmClient.ts` — `generateReframe({ text, systemPrompt })`, `generateJson({ ... })`
- `src/lib/prompts.ts` — `DECISION_PROMPT`, `SYSTEM_PROMPTS`, length budgets
- `src/types/index.ts` — shared types; update Swift models in the same change

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

`authStub.getOwnerUserId()` is the owner seam (seeded local user today). Replace `authStub` with Better Auth later. Schema is Drizzle + local Postgres using `postgres` (postgres.js), not Neon. Apple Sign In is required on iOS if other social providers ship.

## Deploy

Dockerfile in `backend/`. No `railway.json`. Health check `/health`. `PORT` from the environment.
