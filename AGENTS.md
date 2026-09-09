# Angles — agent notes

Paid-only private reframe app (iOS). User submits a negative thought; the backend LLM returns 1–3 sentences in a chosen style. No public feed in v1. Onboarding: one free taste (all 4 styles in parallel), then a hard paywall.

## Stack (this repo)

| Layer | Choice |
| --- | --- |
| iOS | Swift, SwiftUI, iOS 17+, MVVM when screens exist, native `URLSession` only |
| API | Hono on Node (`@hono/node-server`), pnpm, Railway |
| LLM | Server-side only, isolated in `backend/src/lib/llmClient.ts` (mock today) |
| Auth (later) | Better Auth, social logins. iOS must also offer Sign in with Apple (Guideline 4.8) if any other social login ships. Hook: `backend/src/lib/authStub.ts` |
| DB (later) | Postgres on Railway, Drizzle. Use the `postgres` (postgres.js) driver — not a serverless Neon adapter. Planned paths: `backend/src/db/`, `backend/drizzle.config.ts` |

Do not add Cloudflare Workers / Wrangler. Do not add `railway.json` (deprecated for new Railway services).

## Layout

- `backend/src/app.ts` — Hono app, middleware, error handler
- `backend/src/index.ts` — `serve()`, `PORT` (default 8787), bind `0.0.0.0`
- `backend/src/routes/reframe.ts` — `POST /reframe`, Zod, `Promise.all` per style
- `backend/src/routes/health.ts` — `GET /health`
- `backend/src/lib/llmClient.ts` — **only** file to change when picking an LLM provider
- `backend/src/lib/prompts.ts` — `SYSTEM_PROMPTS`
- `backend/src/types/index.ts` — `Style`, request/response types
- `AnglesApp/project.yml` — XcodeGen source of truth; run `xcodegen generate` after structural file changes
- `AnglesApp/AnglesApp/Networking/` — `APIClient`, `ReframeService`
- `AnglesApp/AnglesApp/Models/ReframeModels.swift` — must match backend JSON exactly

## Do not invent

No SwiftUI screens, StoreKit, SwiftData, Drizzle schema, Better Auth implementation, CORS “for browsers”, client-side LLM keys, or v2 social feed.

## Type sync

`Style` JSON values: `stoic`, `optimistic`, `humorous`, `tough_love`.

If you change `backend/src/types/index.ts`, update `ReframeModels.swift` in the same change. Prefer failing the request over returning partial `results`.

## API errors

JSON body `{ "error": string, "code": string }`. Validation → 400 `VALIDATION_ERROR`. Bad JSON → 400 `INVALID_JSON`. Oversize body → 413 `PAYLOAD_TOO_LARGE`. LLM failure → 500 `LLM_ERROR`. Do not log the user's thought text.

## CORS

Not used. Native iOS `URLSession` is not a browser. Do not add wildcard CORS.

## iOS

- `#if DEBUG` API URL is `http://localhost:8787`. Simulator only; devices need the Mac LAN IP.
- ATS: `NSAllowsLocalNetworking` only. Never `NSAllowsArbitraryLoads`.
- No third-party networking libraries.
- ViewModels arrive with screens. Keep networking free of UIKit/SwiftUI.

## Skills

- `.cursor/skills/angles-backend/SKILL.md`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-llm-prompts/SKILL.md`
