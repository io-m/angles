# Angles — agent notes

Paid-only reframe app (iOS). User submits a negative thought; the backend may ask follow-ups, then returns 1–3 sentences in all 4 styles. The server stores a card private unless the save says otherwise; compose Save defaults to **Post** (public) with a Save privately toggle, and the onboarding taste always saves privately. Publishing a card puts it on Home for everyone, including the author. Onboarding: one free taste (all 4 styles), then a hard paywall.

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
- `backend/src/index.ts` — `serve()`, `PORT` (default 8787), bind `0.0.0.0`, signing-key and schema checks, pool shutdown
- `backend/src/routes/reframe.ts` — `POST /reframe`, Zod, decision call then one batched style JSON (recook is a single style); signs every ready response
- `backend/src/routes/cards.ts` — `POST/GET/PATCH/DELETE /cards`; `POST` only stores a signed cook
- `backend/src/routes/feed.ts` — flat `GET /feed` (paged; multi-category/mood facets), viewer heart saves
- `backend/src/routes/users.ts` — `GET /users/:id/cards` (an author's public posts), `PUT/DELETE /users/:id/follow`
- `backend/src/routes/profile.ts` — `PATCH /profile` (name → initials), `GET /profile/following`, avatar upload/delete, public `GET /avatars/:userId`
- `backend/src/routes/health.ts` — `GET /health` (includes a DB probe)
- `backend/src/db/schema.ts` — Drizzle tables
- `backend/src/db/cards.ts` — SQL seam for the library (own cards plus hearted cards that are still public)
- `backend/src/db/feed.ts`, `backend/src/db/follows.ts` — Home, author lists, hearts on others' cards, follow graph
- `backend/src/db/cursor.ts`, `backend/src/lib/cursor.ts` — the shared `createdAt|id` page cursor (row comparison, index-seekable)
- `backend/src/lib/cookSignature.ts` — HMAC over a cook (`COOK_SIGNING_KEY`); `/reframe` signs, `POST /cards` verifies
- `backend/src/lib/decision.ts` — the structured decision call: continue vs ready, cleaned thought, styles, metadata
- `backend/src/lib/llmClient.ts` — **only** file to change when picking an LLM provider (`generateReframe`, `generateJson`)
- `backend/src/lib/prompts.ts` — `DECISION_PROMPT`, `STYLE_BATCH_PROMPT`, `SYSTEM_PROMPTS`, length budgets
- `backend/src/types/index.ts` — `Style`, request/response types
- `AnglesApp/project.yml` — XcodeGen source of truth; run `xcodegen generate` after structural file changes
- `AnglesApp/AnglesApp/AnglesApp.swift` — AppRoot: TabView (Home, Profile), compose overlay, shared `HomeViewModel`
- `AnglesApp/AnglesApp/Root/RootTabBar.swift` — `RootTab` (Home, Sparkle compose, Profile)
- `AnglesApp/AnglesApp/Home/HomeView.swift` — community Home: All + four style tabs aligned with trailing filter; tinted glass header; no Home Settings gear
- `AnglesApp/AnglesApp/Home/HomeFilterSheet.swift` — draft/apply Life area and Mood tabbed multi-select
- `AnglesApp/AnglesApp/Home/HeaderChrome.swift` — shared header metrics and the bottom fade stops
- `AnglesApp/AnglesApp/Home/ProfileView.swift` — private library with a fixed compact identity header (avatar, session name), Favorites-first tabs and horizontally paged style lists; Settings gear and Following sheet; opaque style wash chrome
- `AnglesApp/AnglesApp/Home/AuthorProfileView.swift` — one author's public posts, same five tabs, follow badge; edge-swipe back gate
- `AnglesApp/AnglesApp/Home/FollowingSheet.swift` — who the viewer follows; unfollow, open, its own write banner
- `AnglesApp/AnglesApp/Home/HomeCardGrid.swift` — one card per row (`LazyVStack`)
- `AnglesApp/AnglesApp/Home/ReframeCardView.swift` — stacked thought + selected answer everywhere except equal-height flipping Favorite angles; per-style chips/hearts and shared tap/long-press actions; globe on the author's public cards
- `AnglesApp/AnglesApp/Home/AvatarImage.swift` — ImageIO downsampling and the in-memory author photo cache
- `AnglesApp/AnglesApp/Networking/` — `APIClient`, `ReframeService`, `CardsService`
- `AnglesApp/AnglesApp/Models/ReframeModels.swift` — must match backend JSON exactly
- `BUILD.md` — **screen/feature order**. Update it in the same change as every new screen or feature.

## Do not invent

Follow `BUILD.md`. Do not add screens or features that are not the current item. No SwiftData, Better Auth, CORS “for browsers”, or client-side LLM keys until that row in `BUILD.md` is next. StoreKit and community Home have shipped.

## Reframe contract

Every `POST /reframe` runs the decision call first — there is no local clarify bank and no word-count gate. It answers one of two shapes:

- `{ kind: "continue", message, options, safety }` — the composer stays up; the user answers or says more.
- `{ kind: "ready", thought, thoughtOriginal?, results (1–4), meta, signature }` — `thought` is the cleaned English card copy. Each result is `{ style, reframe, signature }`.

`meta` is `{ category, proposedCategory?, proposedLabel?, tags, intensity, timeframe, emotions, safety, inputLanguage, skippedStyles, matching }`. Categories are a closed set; anything else becomes `other` plus a proposal. Never reframe a thought flagged for safety. `followUps` caps at 6 and the decision is forced to land from the third.

Save writes that cook to `POST /cards` with both signatures echoed back unchanged. The cook `signature` covers `thought`, `thoughtOriginal`, and `meta` minus `matching`; each result signature covers the thought it answers plus its style and text. A recook signs its one result against the request `text`, which must be the cook's cleaned `thought`. `POST /cards` rejects any missing or mismatched signature, and any `meta.safety` other than `none`, with 400 `VALIDATION_ERROR`. Hearts are per style on `card_reframes` (or `saved_angles` for someone else's card); `isPublic` (default false) sits on the card. A hearted card leaves the viewer's library when its author makes it private. There are no pins. `POST /reframe` never writes.

## Type sync

`Style` JSON values: `stoic`, `optimistic`, `humorous`, `tough_love`.

If you change `backend/src/types/index.ts`, update `ReframeModels.swift` in the same change. Prefer failing the request over returning partial `results`.

## API errors

JSON body `{ "error": string, "code": string }`. Validation → 400 `VALIDATION_ERROR`. Bad JSON → 400 `INVALID_JSON`. Oversize body → 413 `PAYLOAD_TOO_LARGE`. LLM failure → 500 `LLM_ERROR`. Missing card → 404 `NOT_FOUND`. Database failure → 500 `DB_ERROR`. Do not log the user's thought text.

## CORS

Not used. Native iOS `URLSession` is not a browser. Do not add wildcard CORS.

## iOS

- API URL is the `ANGLES_API_BASE_URL` build setting in `project.yml` (Info.plist `AnglesAPIBaseURL`). Debug is the Mac's LAN IP (`http://192.168.0.39:8787`); Release is empty until the production host exists, so a Release build fails its requests locally. Never point it at a host we do not own.
- The dev API binds `0.0.0.0` so the iPhone can reach it. Until auth exists, anyone on the same network can use it as the dev user, including reading the private library and spending LLM credit. Run it only on networks you trust.
- ATS: `NSAllowsLocalNetworking` only. Never `NSAllowsArbitraryLoads`.
- No third-party networking libraries.
- ViewModels arrive with screens. Keep networking free of UIKit/SwiftUI.
- **Always install and launch on Joe’s iPhone** (`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`). A Simulator compile is not done. See `.cursor/rules/ios-device.mdc`.

## Skills

- `.cursor/skills/angles-backend/SKILL.md`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-llm-prompts/SKILL.md`
