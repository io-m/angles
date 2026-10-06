# Angles — agent notes

Paid-only reframe app (iOS). User submits a negative thought; the backend may ask follow-ups, then returns 1–3 sentences in all 4 styles. The server stores a card private unless the save says otherwise; compose Save defaults to **Post** (public) with a Save privately toggle, and the onboarding taste always saves privately. Publishing a card puts it on Home for everyone, including the author. Onboarding: Continue with Apple, then one free taste while both `tasteConsumedAt` and `tasteCompletedAt` are empty, then a hard paywall. The first Send on an account opens the one-time AI consent sheet.

## Stack (this repo)

| Layer | Choice |
| --- | --- |
| iOS | Swift, SwiftUI, iOS 17+, MVVM when screens exist, native `URLSession` only |
| API | Hono on Node (`@hono/node-server`), pnpm, Railway |
| LLM | Server-side only, isolated in `backend/src/lib/llmClient.ts` |
| Auth | Better Auth, Apple ID tokens only. Session: `requireAuth` + `getOwnerUserId()` in `backend/src/lib/authStub.ts` |
| DB | Local Postgres in Docker (host 5433) + Drizzle, `postgres` (postgres.js) driver — not a serverless Neon adapter. Paths: `backend/src/db/`, `backend/drizzle.config.ts` |

Do not add Cloudflare Workers / Wrangler. Do not add `railway.json` (deprecated for new Railway services). SwiftData is still later.

## Layout

- `backend/src/app.ts` — Hono app, middleware, error handler
- `backend/src/index.ts` — `serve()`, `PORT` (default 8787), bind `0.0.0.0`, signing-key and schema checks, pool shutdown
- `backend/src/routes/reframe.ts` — `POST /reframe`, Zod, metering, and signing around `cook.ts`: a compose turn runs the decision call then the batch; a recook verifies the signed cook and writes one style
- `backend/src/routes/cards.ts` — `POST/GET/PATCH/DELETE /cards`; `POST` only stores a signed cook
- `backend/src/routes/feed.ts` — flat `GET /feed` (paged; life-area/mood facets; optional `style` for a Home shelf), viewer heart saves
- `backend/src/routes/users.ts` — `GET /users/:id/cards` (an author's public posts), `PUT/DELETE /users/:id/follow`
- `backend/src/routes/appStoreNotifications.ts` — verified, idempotent App Store Server Notifications V2 receiver
- `backend/src/auth.ts` — Better Auth (Sign in with Apple, bearer plugin)
- `backend/src/lib/authStub.ts` — `requireAuth` + `getOwnerUserId()`
- `backend/src/routes/profile.ts` — profile/session/delete/following/blocked/avatar plus subscription sync/diagnostics and usage summary
- `backend/src/routes/health.ts` — `GET /health` (includes a DB probe)
- `backend/src/db/schema.ts` — Drizzle tables
- `backend/src/db/cards.ts` — SQL seam for the library (own cards plus hearted cards that are still public)
- `backend/src/db/feed.ts`, `backend/src/db/follows.ts` — Home, author lists, hearts on others' cards, follow graph
- `backend/src/lib/feedRanking.ts` — Home order when `FEED_RANKING=resonance`. For you is the mixed score. A `style` request adds that shelf's taste, angle hearts, a weak cover nudge, and an off-primary-tab penalty. Also the theme learning and the core/adjacent/explore page mix. Unset or `chronological` is newest-first. Tune only here.
- `backend/src/scripts/seedCommunityRealistic.ts`, `feedAudit.ts` — `pnpm db:seed-realistic` reshapes the fixture community (dates, authors, hearts); `pnpm db:feed-audit --viewer=<email>` grades the ranked feed
- `backend/src/db/communitySafety.ts` — reports, bidirectional block filtering, unblock list, automatic private threshold
- `backend/src/db/subscriptions.ts` — account-bound StoreKit entitlement and notification state
- `backend/src/db/metering.ts` — credit periods, operation leases/idempotency, abuse counters, provider-attempt ledger
- `backend/src/db/productionMigrations.ts` — packaged startup migrations
- `backend/src/db/cursor.ts`, `backend/src/lib/cursor.ts` — the shared `createdAt|id` page cursor (row comparison, index-seekable)
- `backend/src/lib/cookSignature.ts` — HMAC over a cook and its owner (`COOK_SIGNING_KEY`); `/reframe` signs, `POST /cards` and a recook verify
- `backend/src/lib/cookSchema.ts` — the signed-meta Zod schema shared by `POST /cards` and the recook request
- `backend/src/lib/cook.ts` — the cook pipeline without HTTP: decision, batch writer, lint rewrite, recook, bilingual answers. The route and `pnpm llm:eval` both run it
- `backend/src/lib/reframeLint.ts` — deterministic checks on written answers (length, questions, foreign digits, markdown, clichés, banned openers, overlap)
- `backend/src/lib/safetyScreen.ts` — self-harm phrase screen for English and 15 other languages written with spaces between words; runs over the user's words and, on a ready turn, the model's cleaned copy (so the English `thought` covers any other language); overrides a model's `none`
- `backend/src/lib/crisisResources.ts` — region → crisis line table; the model never writes numbers
- `backend/src/lib/reframeReplay.ts` — seals a finished `/reframe` response under the client's `Replay-Key`
- `backend/src/lib/decision.ts` — the structured decision call: continue vs ready, cleaned thought, styles, metadata
- `backend/src/lib/llmClient.ts` — **only** file to change when picking an LLM provider (`generateReframe`, `generateJson`). `modelsForStep` routes each step (`decision`, `writer`, `moderation`) from env (`LLM_<STEP>_MODEL`, `LLM_<STEP>_FALLBACK_MODEL`); the phone never picks a model
- `backend/src/lib/llmUsage.ts`, `backend/src/lib/meteringPolicy.ts` — provider-token COGS and fixed 600-credit user tariff; every cook and recook costs 1 credit
- `backend/src/scripts/llmEval.ts`, `backend/eval/thoughts.json` — `pnpm llm:eval`: the golden thoughts through the real pipeline, lint and judge scores, cost; reports in `backend/eval/out/`
- `backend/src/lib/appStoreVerifier.ts`, `backend/src/lib/subscriptionGate.ts` — Apple JWS verification and paid/taste gate
- `backend/src/lib/publicModeration.ts`, `backend/src/lib/communitySafetyTypes.ts` — fail-closed publishing classifier and report contract
- `backend/src/lib/productionConfig.ts` — production environment fail-fast validation
- `backend/src/lib/prompts.ts` — `DECISION_PROMPT`, `STYLE_BATCH_PROMPT`, `SYSTEM_PROMPTS`, `STYLE_VOICES` (voice, technique menu, banned openers per style), `GOLD_CARDS`, length budgets
- `backend/src/types/index.ts` — `Style`, request/response types
- `AnglesApp/project.yml` — XcodeGen source of truth; run `xcodegen generate` after structural file changes
- `AnglesApp/AnglesApp/AnglesApp.swift` — AppRoot: TabView (Home, Profile), compose overlay, shared `HomeViewModel`
- `AnglesApp/AnglesApp/Root/AppGate.swift` — the pure funnel resolver (launching / login / taste / paywall / home); AppRoot renders only from it
- `AnglesApp/AnglesApp/Root/RootTabBar.swift` — `RootTab` (Home, Sparkle compose, Profile)
- `AnglesApp/AnglesApp/Home/HomeView.swift` — community Home: For you + four style tabs aligned with trailing filter; tinted glass header; no Home Settings gear
- `AnglesApp/AnglesApp/Home/HomeFeedShelf.swift` — one Home card record, one page per tab. A heart, follow, or removal updates every shelf that is showing that post. Profile and author pages do not use this ranking.
- `AnglesApp/AnglesApp/Home/HomeFilterSheet.swift` — draft/apply Life area and Mood tabbed multi-select
- `AnglesApp/AnglesApp/Home/HeaderChrome.swift` — shared header metrics and the bottom fade stops
- `AnglesApp/AnglesApp/Home/ProfileView.swift` — private library with a fixed compact identity header (avatar, session name), Favorites-first tabs and horizontally paged style lists; Settings gear and Following sheet; opaque style wash chrome
- `AnglesApp/AnglesApp/Home/AuthorProfileView.swift` — one author's public posts, same five tabs, follow badge; edge-swipe back gate
- `AnglesApp/AnglesApp/Home/FollowingSheet.swift` — who the viewer follows; unfollow, open, its own write banner
- `AnglesApp/AnglesApp/Home/AIConsentSheet.swift` — the one-time per-account "Before you start" sheet before the first Send: AI providers, what is sent, community rules, Terms and Privacy acceptance
- `AnglesApp/AnglesApp/Home/HomeCardGrid.swift` — one card per row (`LazyVStack`)
- `AnglesApp/AnglesApp/Home/ReframeCardView.swift` — stacked thought + selected answer everywhere except equal-height flipping Favorite angles; per-style chips/hearts and shared tap/long-press actions; globe on the author's public cards
- `AnglesApp/AnglesApp/Home/BlockedPeopleSheet.swift` — Settings block list and unblock actions
- `AnglesApp/AnglesApp/Home/AvatarImage.swift` — ImageIO downsampling and the in-memory author photo cache
- `AnglesApp/AnglesApp/Networking/` — `APIClient`, `ReframeService`, `CardsService`
- `AnglesApp/AnglesApp/Auth/` — login, Keychain session, Sign in with Apple
- `AnglesApp/AnglesApp/StoreKit/StoreKitManager.swift` — purchases, restore, account-token transaction sync, entitlement routing
- `AnglesApp/AnglesApp/Settings/SubscriptionView.swift` — plan/manage/restore plus server credit balance and reset
- `AnglesApp/AnglesApp/Config/AppConfig.swift` — optional Release API, legal, and support destinations
- `AnglesApp/AnglesApp/Models/ReframeModels.swift` — must match backend JSON exactly
- `BUILD.md` — **screen/feature order**. Update it in the same change as every new screen or feature.
- `demo/` — showcase TikToks. **Cut contract** is at the top of `demo/README.md`: hook, type, short cook, **exactly four** style chapters (yellow title on the cut), extra hold + small zoom on Tough love, then the end card. Do not add a fifth “best” chapter, Post, bike cover, or Home. `demo/make_video.sh` records a real cook on the "Angles Demo iPhone 17 Pro" Simulator; `demo/edit.mjs` writes the HyperFrames composition (`demo/lib/composition.template.html`) and `demo/output/final_9x16.mp4`. Sign-in is `pnpm demo:session` (local DB) + `DemoLaunch` (Debug Simulator only). Raw takes in `demo/raw/` are never overwritten.

## Do not invent

Follow `BUILD.md`. Do not add screens or features that are not the current item. No SwiftData, CORS “for browsers”, or client-side LLM keys until that row in `BUILD.md` is next. StoreKit, community Home, and Auth have shipped.

## Reframe contract

A request is either a compose turn `{ text, followUps?, region? }` or a recook `{ recook, region? }`, never both. The phone never sends a model or a list of styles: the server routes each step (`modelsForStep`) and the decision picks the styles. Every compose turn runs the decision call first — there is no local clarify bank and no word-count gate. It answers one of two shapes:

- `{ kind: "continue", message, options, safety, crisisResource? }` — the composer stays up; the user answers or says more. `crisisResource` is present exactly when `safety` is not `none`.
- `{ kind: "ready", thought, thoughtOriginal?, results (1–4), meta, model, signature }` — `thought` is the cleaned English card copy. Each result is `{ style, reframe, reframeOriginal?, signature }`. `model` is the writer the server routed to; Save echoes it and the phone never shows it (cards carry the Angles mark).

`meta` is `{ category, proposedCategory?, proposedLabel?, tags, intensity, timeframe, emotions, distortions, safety, inputLanguage, skippedStyles, matching }`. Categories are a closed set; anything else becomes `other` plus a proposal. `distortions` is 0–2 thinking traps (`DISTORTIONS` in `types/index.ts`); the writer pushes against them, the cook signature covers them, and the card does not store them. The decision adapts a style to a heavy thought rather than skipping it, except for a real mismatch (for example tough love on a loss the person blames themselves for, which `chooseStyles` removes); `chooseStyles` always writes stoic and optimistic. A happy moment with no complaint is a thought too: it cooks on the first turn with angles that keep the feeling, never a "what are you stuck on" question. Never reframe a thought flagged for safety. `followUps` caps at 6 and the decision is forced to land from the third.

**The writer.** A ready decision gets one batch JSON call that writes a hidden `plan` (one technique per style, all different) and then each style from its own voice, technique menu, and banned openers in `STYLE_VOICES`, steered by timeframe, intensity, and distortions. `reframeLint.ts` then checks every answer, and any style that fails gets one targeted rewrite (call kind `rewrite`) while the deadline allows; a rewrite ships only if it has fewer problems.

**Their language.** When `meta.inputLanguage` is not English, every answer comes back twice: `reframe` in English and `reframeOriginal` in their language, written the way a native speaker would say it rather than translated word for word. The public card stays English; only the author gets `reframeOriginal` back from `/cards` and `/feed`, and sees it through the Original toggle. A `reframeOriginal` that still has a foreign number after the rewrite is dropped and the English ships alone.

**Recook.** "New answer" sends `{ recook: { style, cook: { thought, thoughtOriginal?, meta, model, signature }, previous?: { reframe, reframeOriginal?, signature } } }`, all echoed unchanged from the ready response. The server verifies the cook and the previous answer (400 `VALIDATION_ERROR` before metering if either fails or `meta.safety` is not `none`), skips the decision call, and writes one style at temperature 0.95 with the previous answer in view and a different technique. A style the cook skipped answers as a continue with its reason, no model call, and no charge. The response keeps the cook's own `thought`, `meta`, `model`, and `signature`; only the new result is new.

**Safety fails closed.** Any safety label the model returns that is not `none` or a clear synonym of it is treated as `self_harm`, on the server (`normalizeSafety` in `decision.ts`) and in `SafetyFlag` on the phone. `safetyScreen.ts` also screens the text and every follow-up answer for explicit and passive self-harm phrasing in several languages; a screen hit overrides the model's `none`, and still answers with the crisis continue if the model call fails. A flagged turn is a continue with no chips, even on a forced turn. The model never writes a phone number or hotline: the request carries the phone's `region` (ISO 3166-1 alpha-2, never sent to the model), and `crisisResources.ts` picks the line — 988 in the US and Canada, 112 across Europe, a short table of others, and a generic "call your local emergency number" line for anything unknown or malformed. A malformed `region` never fails the request. A crisis message that contains a digit is replaced with the fixed fallback.

**Retries replay.** Every refine turn and recook sends an `Idempotency-Key` UUID and a `Replay-Key` (32 random bytes, unpadded base64url) that the phone keeps with it. The server seals the finished response under that key (AES-256-GCM, `reframeReplay.ts`) in the same transaction that charges it, and keeps the ciphertext for an hour. A retry with the same key and request gets the same signed response back and is not charged again; the taste is not spent twice. The server never stores the replay key, so it cannot read what it stored.

## Home ranking

`GET /feed` with `FEED_RANKING=resonance` ranks for the signed-in viewer. The score in `feedRanking.ts` is recency first, like a social feed: a post from today beats last week's unless hearts, follows, and themes together make up the difference. After that it prefers one people have hearted, one close to the viewer's themes, one from someone they follow, and an unhearted post that is still young enough to be found. A little stable variety keeps one session from looking identical to the next. Distress is capped, never rewarded. There is no dwell-time signal. Every input (hearts, follows, themes, the clock) is read as of the visit's `startedAt`, so a heart or follow mid-visit applies on the next visit. The plain-language rulebook is `docs/home-feed.md`; change it with the behaviour.

**Own cards** are on Home, scored like anyone else's (no own-theme boost, the viewer's own hearts never count as resonance), at most 1 per page; the ranked list ends once only own cards are left. **Follows** add a 0.6 boost; on For you, following 3+ authors with posts in the last 7 days also reserves about 25% of each page for them, capped at 50%. In a small community the spread falls back to the author with the fewest cards on the page, never plain rank order, and avoids the same author twice in a row.

**Themes** are the top life areas and moods from what the viewer writes and every angle they heart on any tab, recency-weighted (14-day half-life) and confidence-gated (five cards or hearts is a full profile; `other` is never a theme). Every page then follows a **theme mix**: about 40% core (their own life areas), 35% adjacent (neighbouring life areas or moods), 25% explore, scaled down with confidence and off entirely for a new viewer. Ranking orders cards inside a bucket; each bucket is capped at its share of the page, so the mix never pushes old cards ahead of new ones.

**Kept angles.** A heart is on one answer, not the card. For you hides a card only once every angle is hearted; a partly kept card stays, a little lower, and opens on an unhearted angle (server `openingStyle` and phone `ForYouCovers`). A style tab hides only that tab's own angle. Frozen to the visit's start, so paging is exact.

**Arrivals.** A ranked page answers `page.arrivalsAfter` (newest candidate at `startedAt`). The phone's pull asks `GET /feed?after=` that mark, never the newest card on screen, and `after` applies the same kept and own-card rules. With nothing new, a pull moves up the loaded cards the reader never reached, then the next unloaded page.

**For you** omits `style` and stays that mixed feed. **Stoic**, **Optimistic**, **Humorous**, and **Tough love** each send `style` and get their own shelf: the same base score, plus taste learned from hearts on that style (one heart cannot take over; five matching hearts is full confidence), hearts on that exact angle, and a weak nudge when the author's cover matches the tab. Each card also has one **primary tab** for that viewer (the style it fits best, ties broken by a stable viewer+card hash), and a card on another style's primary tab is penalised, so the tabs mostly show different cards. The penalty fades out for posts under a few hours old, so the newest posts are on every tab. It is a penalty, not a filter: a thin tab still fills. With the flag off, every tab is newest-first among cards that have that angle, so they look alike.

The app keeps one copy of each loaded card and a separate order per tab. Life area and mood filters apply to every shelf. Author and Profile pages stay ordinary lists. Per-style heart totals stay on the server. The full weights, paging, and spread rules are `BUILD.md` sections 14 and 15.

Save writes that cook to `POST /cards` with both signatures echoed back unchanged. Both signatures are bound to the account that cooked it, so a cook signed for one account does not save under another. The cook `signature` covers `thought`, `thoughtOriginal`, `model`, and `meta` minus `matching` (including `distortions`); each result signature covers the thought it answers plus its style, `reframe`, and `reframeOriginal`, and names no model. A recook signs its one result against the cook's cleaned `thought`. `POST /cards` rejects any missing or mismatched signature, and any `meta.safety` other than `none`, with 400 `VALIDATION_ERROR`. One cook makes at most one card per account (`cards.cook_signature`): a repeated save returns the first card with 200, before moderation. Hearts are per style on `card_reframes` (or `saved_angles` for someone else's card); `isPublic` (default false) sits on the card. A hearted card leaves the viewer's library when its author makes it private. There are no pins. `POST /reframe` never stores cards or plaintext thought text; it writes only text-free metering/idempotency state, provider token/cost records, and the hour-long replay sealed under a key the server does not keep.

## Subscription access

Access is `active`, or `grace` while Apple's Billing Grace Period lasts. `billing_retry` after grace is stored but locked, on the server and on the phone. A client sync of a lapsed receipt never overwrites a grace or billing-retry state from Apple's notifications. On the phone, a status read that fails or times out does not clear an unlock the phone already had when the only receipt for this account is a lapsed one; the server still gates every cook. Billing Grace Period must be on in App Store Connect. Account delete removes the avatar first, retries it, and fails with 503 `STORAGE_UNAVAILABLE` without deleting anything if storage will not confirm.

## Type sync

`Style` JSON values: `stoic`, `optimistic`, `humorous`, `tough_love`.

If you change `backend/src/types/index.ts`, update `ReframeModels.swift` in the same change. Prefer failing the request over returning partial `results`.

## API errors

JSON body `{ "error": string, "code": string }`. Validation → 400 `VALIDATION_ERROR`. Bad JSON → 400 `INVALID_JSON`. Oversize body → 413 `PAYLOAD_TOO_LARGE`. LLM failure → 500 `LLM_ERROR`. Missing card → 404 `NOT_FOUND`. Database failure → 500 `DB_ERROR`. Do not log the user's thought text.

## CORS

Not used. Native iOS `URLSession` is not a browser. Do not add wildcard CORS.

## iOS

- API URL is the `ANGLES_API_BASE_URL` build setting in `project.yml` (Info.plist `AnglesAPIBaseURL`). Debug is the Mac's LAN IP (`http://192.168.0.39:8787`); Release is the Railway production API (`https://api-production-61c9.up.railway.app`, the `api` service in the `angles` project). Never point it at a host we do not own.
- The dev API binds `0.0.0.0` so the iPhone can reach it. Product routes need a Better Auth session. Run it only on networks you trust.
- ATS: `NSAllowsLocalNetworking` only. Never `NSAllowsArbitraryLoads`.
- No third-party networking libraries.
- ViewModels arrive with screens. Keep networking free of UIKit/SwiftUI.
- **Always install and launch on Joe’s iPhone** (`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`). A Simulator compile is not done. See `.cursor/rules/ios-device.mdc`.

## Skills

- `.cursor/skills/angles-backend/SKILL.md`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-llm-prompts/SKILL.md`
