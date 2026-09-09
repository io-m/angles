---
name: angles-backend
description: Extend or change the Angles Hono API (reframe, health, validation, LLM client, Railway). Use when editing backend TypeScript, adding routes, swapping the LLM provider, or wiring future auth/DB.
---

# Angles backend

## Layout

- `src/app.ts` — middleware, route mount, `onError`
- `src/index.ts` — Node `serve()` only
- `src/routes/reframe.ts` — `POST /reframe`
- `src/lib/llmClient.ts` — `generateReframe({ text, systemPrompt })`
- `src/lib/prompts.ts` — `SYSTEM_PROMPTS`
- `src/types/index.ts` — shared types; update Swift models in the same change

## Adding a route

1. New file under `src/routes/`.
2. Mount in `createApp()`.
3. Zod at the boundary. Typed handler. `{ error, code }` on failure.
4. Cover with `app.request()` in `src/app.test.ts` (or a colocated `*.test.ts`).

## Swapping the LLM

Change only `src/lib/llmClient.ts`. Keep `generateReframe` and `LlmError`. Honor `LLM_TIMEOUT_MS` and `AbortSignal`. Do not send `LLM_API_KEY` to the client. Do not log `text`.

## Auth / DB (not yet)

Replace `authStub` with Better Auth. Schema via Drizzle + Railway Postgres using `postgres` (postgres.js), not Neon. Apple Sign In is required on iOS if other social providers ship.

## Deploy

Dockerfile in `backend/`. No `railway.json`. Health check `/health`. `PORT` from the environment.
