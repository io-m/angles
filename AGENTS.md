# Angles — agent notes

Paid-only private reframe app (iOS). User submits a negative thought; the backend may ask follow-ups, then always returns 1–3 sentences in all 4 styles. Private by default; anonymous opt-in to publish individual cards is postponed. The current shell has no public feed. Onboarding: one free taste (all 4 styles), then a hard paywall.

## Stack (this repo)

| Layer | Choice |
| --- | --- |
| iOS | Swift, SwiftUI, iOS 17+, MVVM when screens exist, native `URLSession` only |
| API | Hono on Node (`@hono/node-server`), pnpm, Railway |
| LLM | Server-side only, isolated in `backend/src/lib/llmClient.ts` |
| Auth (later) | Better Auth, social logins. iOS must also offer Sign in with Apple (Guideline 4.8) if any other social login ships. Hook: `backend/src/lib/authStub.ts` (`getOwnerUserId`) |
| DB | Local Postgres in Docker (host 5433) + Drizzle, `postgres` (postgres.js) driver — not a serverless Neon adapter. Paths: `backend/src/db/`, `backend/drizzle.config.ts` |

Do not add Cloudflare Workers / Wrangler. Do not add `railway.json` (deprecated for new Railway services).

## Layout

- `backend/src/app.ts` — Hono app, middleware, error handler
- `backend/src/index.ts` — `serve()`, `PORT` (default 8787), bind `0.0.0.0`, schema check, pool shutdown
- `backend/src/routes/reframe.ts` — `POST /reframe`, Zod, decision call then one batched style JSON (recook is a single style)
- `backend/src/routes/cards.ts` — `POST/GET/PATCH/DELETE /cards`
- `backend/src/routes/health.ts` — `GET /health` (includes a DB probe)
- `backend/src/db/schema.ts` — Drizzle tables
- `backend/src/db/cards.ts` — SQL seam for the library
- `backend/src/lib/decision.ts` — the structured decision call: continue vs ready, cleaned thought, styles, metadata
- `backend/src/lib/llmClient.ts` — **only** file to change when picking an LLM provider (`generateReframe`, `generateJson`)
- `backend/src/lib/prompts.ts` — `DECISION_PROMPT`, `STYLE_BATCH_PROMPT`, `SYSTEM_PROMPTS`, length budgets
- `backend/src/types/index.ts` — `Style`, request/response types
- `AnglesApp/project.yml` — XcodeGen source of truth; run `xcodegen generate` after structural file changes
- `AnglesApp/AnglesApp/AnglesApp.swift` — AppRoot: TabView (Home, Profile), compose overlay, shared `HomeViewModel`
- `AnglesApp/AnglesApp/Root/RootTabBar.swift` — `RootTab` (Home, Sparkle compose, Profile)
- `AnglesApp/AnglesApp/Home/HomeView.swift` — empty Home tab + Settings
- `AnglesApp/AnglesApp/Home/ProfileView.swift` — private library (favorites + grid). Style chips keep cards that have that angle and open on it; All mixes covers.
- `AnglesApp/AnglesApp/Home/HomeCardGrid.swift` — 2-column card grid
- `AnglesApp/AnglesApp/Networking/` — `APIClient`, `ReframeService`, `CardsService`
- `AnglesApp/AnglesApp/Models/ReframeModels.swift` — must match backend JSON exactly
- `BUILD.md` — **screen/feature order**. Update it in the same change as every new screen or feature.

## Do not invent

Follow `BUILD.md`. Do not add screens or features that are not the current item. No StoreKit, SwiftData, Better Auth, CORS “for browsers”, client-side LLM keys, or community Home until that row in `BUILD.md` is next.

## Reframe contract

Every `POST /reframe` runs the decision call first — there is no local clarify bank and no word-count gate. It answers one of two shapes:

- `{ kind: "continue", message, options, safety }` — the composer stays up; the user answers or says more.
- `{ kind: "ready", thought, thoughtOriginal?, results (1–4), meta }` — `thought` is the cleaned English card copy.

`meta` is `{ category, proposedCategory?, proposedLabel?, tags, intensity, timeframe, emotions, safety, inputLanguage, skippedStyles, matching }`. Categories are a closed set; anything else becomes `other` plus a proposal. Never reframe a thought flagged for safety. `followUps` caps at 6 and the decision is forced to land from the third.

Save writes that cook to `POST /cards`. `POST /reframe` never writes.

## Type sync

`Style` JSON values: `stoic`, `optimistic`, `humorous`, `tough_love`.

If you change `backend/src/types/index.ts`, update `ReframeModels.swift` in the same change. Prefer failing the request over returning partial `results`.

## API errors

JSON body `{ "error": string, "code": string }`. Validation → 400 `VALIDATION_ERROR`. Bad JSON → 400 `INVALID_JSON`. Oversize body → 413 `PAYLOAD_TOO_LARGE`. LLM failure → 500 `LLM_ERROR`. Missing card → 404 `NOT_FOUND`. Database failure → 500 `DB_ERROR`. Do not log the user's thought text.

## CORS

Not used. Native iOS `URLSession` is not a browser. Do not add wildcard CORS.

## iOS

- `#if DEBUG` API URL is `http://localhost:8787`. Simulator only; devices need the Mac LAN IP.
- ATS: `NSAllowsLocalNetworking` only. Never `NSAllowsArbitraryLoads`.
- No third-party networking libraries.
- ViewModels arrive with screens. Keep networking free of UIKit/SwiftUI.
- **Always install and launch on Joe’s iPhone** (`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`). A Simulator compile is not done. See `.cursor/rules/ios-device.mdc`.

## Skills

- `.cursor/skills/angles-backend/SKILL.md`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-llm-prompts/SKILL.md`
