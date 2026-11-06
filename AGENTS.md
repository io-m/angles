# Angles — agent notes

Paid-only reframe app (iOS). User submits a negative thought; the backend may ask follow-ups, then returns 2–3 sentences in the four of six styles that fit the thought best. The server stores a card private unless the save says otherwise; compose Save defaults to **Post** (public) with a Save privately toggle, and the onboarding taste always saves privately. Publishing a card puts it in other people's Home stacks; the author's own cards never appear in their stack. Home is a stack of whole cards under a header (filter, notifications, Settings): swipe right or the heart loves the card (all its angles) into Profile → Loved, swipe left or Pass moves on, and Rewind undoes. Love is the on-screen name for a save; the wire says `save`. Onboarding: Continue with Apple, then one free taste while both `tasteConsumedAt` and `tasteCompletedAt` are empty, then a hard paywall. The first Send on an account opens the one-time AI consent sheet.

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
- `backend/src/routes/cards.ts` — `POST/GET/PATCH/DELETE /cards` (`GET ?saved=true|false` for Profile's two lists); `POST` only stores a signed cook; `PUT/DELETE /cards/:id/decision` writes or clears the viewer's save or pass
- `backend/src/routes/stack.ts` — `GET /stack?limit&session&seen&categories&emotions` (12 cards per page, `{ cards, session, exhausted }`) for Home; the two filters are comma-separated enum lists
- `backend/src/routes/users.ts` — `GET /users/:id/cards` (an author's public posts), `PUT/DELETE /users/:id/follow`
- `backend/src/routes/appStoreNotifications.ts` — verified, idempotent App Store Server Notifications V2 receiver
- `backend/src/auth.ts` — Better Auth (Sign in with Apple, bearer plugin)
- `backend/src/lib/authStub.ts` — `requireAuth` + `getOwnerUserId()`
- `backend/src/routes/profile.ts` — profile/session/delete/following/blocked/avatar plus subscription sync/diagnostics and usage summary
- `backend/src/routes/health.ts` — `GET /health` (includes a DB probe)
- `backend/src/db/schema.ts` — Drizzle tables
- `backend/src/db/cards.ts` — SQL seam for the library (own cards, and saved cards that are still public)
- `backend/src/db/stack.ts`, `backend/src/db/decisions.ts`, `backend/src/db/saves.ts`, `backend/src/db/follows.ts` — the Home stack, one decision row per viewer and card (`card_decisions`), save counts, author lists, follow graph
- `backend/src/lib/feedRanking.ts` — the stack order when `FEED_RANKING=resonance`: the score (freshness with a tail, save rate within heavy or light cards, reach, themes and tags, follows), themes from writes, saves, and passes, the core/adjacent/explore mix and its explore floor, the exploration floor for barely-decided cards, follow share, spread and pacing with a visit-wide author cap, returning cards. Unset or `chronological` is newest-first. Tune only here.
- `backend/src/scripts/seedCommunityRealistic.ts`, `feedAudit.ts`, `houseCards.ts` — `pnpm db:seed-realistic` reshapes the fixture community (dates, authors, saves, passes); `pnpm db:feed-audit --viewer=<email>` walks one ranked visit; `pnpm db:house-cards` cooks `backend/house/thoughts.json` and posts it as the From Angles house account
- `backend/src/db/loveNotifications.ts`, `backend/src/db/notificationCounts.ts` — a save tells the author (`love_notifications`, retracted while unread on unsave or Rewind, never for house cards), the bell list's loves, and the delayed push (10 seconds, grouped per card across unread loves, at most every 2 minutes, `notify_loves` and `share_love_name`); the unread count is follows plus loves
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
- `backend/src/lib/styleSet.ts` — the request's style catalog from `Angles-Style-Set` (absent: the original four), `shownStyleSchema()` for every style at the HTTP boundary. Header `2` serves the frozen `STYLE_SET_2` (six literals); `STYLES` only appends, so a new style needs a new header value and a new frozen set, never an edit to `STYLE_SET_2`
- `backend/src/lib/graveScreen.ts` — English phrase screen for real harm to people (death, serious illness, violence, war, atrocity, persecution, self-hatred); runs over the user's words and the model's English `thought`, forces `solemn`, and guards a written joke. Idioms ("I bombed my interview") stay out
- `backend/src/lib/crisisResources.ts` — region → crisis line table; the model never writes numbers
- `backend/src/lib/reframeReplay.ts` — seals a finished `/reframe` response under the client's `Replay-Key`
- `backend/src/lib/decision.ts` — the structured decision call: continue vs ready, cleaned thought, styles, metadata
- `backend/src/lib/llmClient.ts` — **only** file to change when picking an LLM provider (`generateReframe`, `generateJson`). `modelsForStep` routes each step (`decision`, `writer`, `moderation`) from env (`LLM_<STEP>_MODEL`, `LLM_<STEP>_FALLBACK_MODEL`); the phone never picks a model
- `backend/src/lib/llmUsage.ts`, `backend/src/lib/meteringPolicy.ts` — provider-token COGS and fixed 240-credit user tariff; every cook and recook costs 1 credit
- `backend/src/scripts/llmEval.ts`, `backend/eval/thoughts.json` — `pnpm llm:eval`: the golden thoughts through the real pipeline, lint and judge scores, cost; reports in `backend/eval/out/`
- `backend/src/lib/appStoreVerifier.ts`, `backend/src/lib/subscriptionGate.ts` — Apple JWS verification and paid/taste gate
- `backend/src/lib/publicModeration.ts`, `backend/src/lib/communitySafetyTypes.ts` — fail-closed publishing classifier and report contract
- `backend/src/lib/productionConfig.ts` — production environment fail-fast validation
- `backend/src/lib/prompts.ts` — `DECISION_PROMPT`, `STYLE_BATCH_PROMPT`, `SYSTEM_PROMPTS`, `STYLE_VOICES` (voice, technique menu, banned openers per style), `GOLD_CARDS`, length budgets
- `backend/src/types/index.ts` — `Style`, request/response types
- `AnglesApp/project.yml` — XcodeGen source of truth; run `xcodegen generate` after structural file changes
- `AnglesApp/AnglesApp/AnglesApp.swift` — AppRoot: Home stack, Profile and author sheets, compose overlay, shared `HomeViewModel`
- `AnglesApp/AnglesApp/Root/AppGate.swift` — the pure funnel resolver (launching / login / taste / paywall / home); AppRoot renders only from it
- `AnglesApp/AnglesApp/Home/Stack/` — `StackDeck.swift` (pure deck: checked angles, decision rows, multi-step rewind, `seen`; tests in `StackDeckTests.swift`), `StackModel.swift` (visits, paging, the serial `DecisionWriter`), `StackView.swift` (the header with `CircleIcon` buttons and the six style dots, three rendered cards with the same chrome, the middle one shaded and the back one see-through, the next one scaling up into that place as the top card leaves, free drag in one `StackDrag` observable read only by the views that move, corner stamps, fling, the end card, the Posted toast, the five-button action row in 44/56/76 sizes with the ringed Inspire; `StackLayout.frame` caps the card at 1.52× a 6.1-inch card's width, splits the spare height above and below it, then lifts the card and the action row 16 points toward the header when there is spare, keeping another 0.3% of the screen height under the header), `StackFilterSheet.swift` (Life areas and Moods). `Home/AccountSheets.swift` is Settings and People for the header and Profile; `Theme/ActionColors.swift` is the Love pink-red, Pass slate blue, and Inspire orange
- `AnglesApp/AnglesApp/Theme/RenderCounter.swift`, `FrameMonitor.swift` — DEBUG-only `RENDER <view> n` and `HITCH <ms>` console lines (read with `devicectl ... launch --console`); compiled out of Release
- `AnglesApp/AnglesApp/Home/HeaderChrome.swift` — shared header metrics and the bottom fade stops
- `AnglesApp/AnglesApp/Home/ProfileView.swift` — a sheet over the stack: centered name and the Yours | Loved tabs, same grey as the sheet. A downward pan closes it. A follow push still opens People on top
- `AnglesApp/AnglesApp/Home/AuthorProfileView.swift` — a sheet of one author's public posts, name centered, Follow or Unfollow as text. A downward pan closes it
- `AnglesApp/AnglesApp/Home/PostDetailView.swift` — a sheet for one specific post (opened from a love push or a love row in the bell), with a top-left X button that closes straight to Home, the card opened on the loved angle, and the people who loved it underneath
- `AnglesApp/AnglesApp/Home/FollowingSheet.swift` — who the viewer follows and who followed them, on Profile's icon tabs; the search field lifts when focused; unfollow, open, its own write banner
- `AnglesApp/AnglesApp/Home/AIConsentSheet.swift` — the one-time per-account "Before you start" sheet before the first Send: AI providers, what is sent, community rules, Terms and Privacy acceptance
- `AnglesApp/AnglesApp/Home/Compose/` — the compose screen, one small view per file:
  - `ComposeSession.swift` — the `@Observable` compose state (thought, turns, phase, input, cook, save) and its `/reframe` and `/cards` calls. `HomeViewModel.compose` holds it; it reaches the shared credit balance and library through `ComposeSessionHost`
  - `ComposeThreadModel.swift` — pure logic with tests in `ComposeLogicTests.swift`: thread rows and their stable ids, the bottom bar mode (input, Post, held), the scroll follow, the leave prompt
  - `ComposeSheetView.swift` — the thin composition plus leave, consent, and save routing. AppRoot hands it one `ComposeSheetContext` (handlers, shared references, flags, tasks), so an AppRoot redraw skips it. Keep its inputs free of closures and `@State`, and keep word-sized fields before one-byte flags: padding inside the value makes SwiftUI redraw it every time
  - `ComposeThreadView.swift`, `ComposeRowViews.swift` — the top-down thread and its rows (bubbles, cooking, error, the card with Start new, the only restart)
  - `ComposeBottomBar.swift`, `ComposeInputBar.swift`, `ComposePostBar.swift` — the bar and its focus, the input, Post with its note chip
  - `ComposeHeader.swift`, `ComposeWelcome.swift`, `ComposeSessionEffects.swift`, `ComposeThreadMask.swift`, `ComposeLayout.swift`, `SaveCelebrationCover.swift` — close and credits, the empty-state hero, haptic and keyboard rules, the fade under header and bar, shared metrics, the save cover
- `AnglesApp/AnglesApp/Home/AngleCardFace.swift` — the one card face. `.stack` fills a fixed frame with an 18-point inset: author or From Angles, life area, the thought in 75% ink under 30% of the card, a hairline divider, the tabs row (icon style pills and an "n / 4" count), and the answer top-aligned 12 points under the tabs over a faded style mark (tap halves step angles). `AngleTypeFit` sizes each angle to its own length, 30 down to 15 points filling at most 92% of the space under the tabs, cached per card; accessibility sizes scroll. `.list` is the old feed card: thought, divider, answer, pills and the Love heart, whole-card wash; the same tap halves step angles on the thought and the answer. ⋯ for original, privacy, delete, follow, report, block. `AngleCardList.swift` is the shared list for Profile and author pages
- `AnglesApp/AnglesApp/Home/CardParts.swift`, `HomeCard.swift` — shared card pieces (author mark, follow badge, life-area badge, compose proposal card) and the phone's card record (`decision`, `isHouse`, `openingStyle`)
- `AnglesApp/AnglesApp/Home/BlockedPeopleSheet.swift` — Settings block list and unblock actions
- `AnglesApp/AnglesApp/Home/AvatarImage.swift` — ImageIO downsampling and the in-memory author photo cache
- `AnglesApp/AnglesApp/Networking/` — `APIClient`, `ReframeService`, `CardsService`
- `AnglesApp/AnglesApp/Auth/` — login, Keychain session, Sign in with Apple
- `AnglesApp/AnglesApp/StoreKit/StoreKitManager.swift` — purchases, restore, account-token transaction sync, entitlement routing
- `AnglesApp/AnglesApp/Settings/SubscriptionView.swift` — plan/manage/restore plus server credit balance and reset
- `AnglesApp/AnglesApp/Config/AppConfig.swift` — optional Release API, legal, and support destinations
- `AnglesApp/AnglesApp/Models/ReframeModels.swift` — must match backend JSON exactly
- `BUILD.md` — **screen/feature order**. Update it in the same change as every new screen or feature.
- `demo/` — showcase TikToks. **Cut contract** is at the top of `demo/README.md`: hook, type, short cook, **exactly four** style chapters (yellow title on the cut), extra hold + small zoom on the last one (the four are whichever styles the cook wrote, including Tender and Values), then the end card. Do not add a fifth “best” chapter, Post, bike cover, or Home. `demo/make_video.sh` records a real cook on the "Angles Demo iPhone 17 Pro" Simulator; `demo/edit.mjs` writes the HyperFrames composition (`demo/lib/composition.template.html`) and `demo/output/final_9x16.mp4`. Each run also writes `demo/output/cover.png` and `demo/output/<theme>_cover.png` from the first hook frame (`frames/01-hook-1.png`) for TikTok — no custom cover art. Sign-in is `pnpm demo:session` (local DB) + `DemoLaunch` (Debug Simulator only). Raw takes in `demo/raw/` are never overwritten.

## Do not invent

Follow `BUILD.md`. Do not add screens or features that are not the current item. No SwiftData, CORS “for browsers”, or client-side LLM keys until that row in `BUILD.md` is next. StoreKit, community Home, and Auth have shipped.

## Reframe contract

A request is either a compose turn `{ text, followUps?, region? }` or a recook `{ recook, region? }`, never both. The phone never sends a model or a list of styles: the server routes each step (`modelsForStep`) and the decision picks the styles. Every compose turn runs the decision call first — there is no local clarify bank and no word-count gate. It answers one of two shapes:

- `{ kind: "continue", message, options, safety, crisisResource? }` — the composer stays up; the user answers or says more. `crisisResource` is present exactly when `safety` is not `none`.
- `{ kind: "ready", thought, thoughtOriginal?, results (1–4; always 4 for a build that sends `Angles-Style-Set: 2`), meta, model, signature }` — `thought` is the cleaned English card copy. Each result is `{ style, reframe, reframeOriginal?, signature }`. `model` is the writer the server routed to; Save echoes it and the phone never shows it (cards carry the Angles mark).

`meta` is `{ category, proposedCategory?, proposedLabel?, tags, intensity, timeframe, emotions, distortions, safety, inputLanguage, skippedStyles, matching }`. Categories are a closed set; anything else becomes `other` plus a proposal. `distortions` is 0–2 thinking traps (`DISTORTIONS` in `types/index.ts`); the writer pushes against them, the cook signature covers them, and the card does not store them. **Solemn fails closed.** The decision JSON carries a required `solemn` boolean: true when the thought is about real harm to people, theirs or strangers' (a death, serious illness, sexual violence, a child hurt, abuse, torture or trafficking, war and attacks on civilians, genocide, terrorism, persecution, self-hatred). Only an explicit `false` allows Witty or Tough; anything else, and every `grief_loss` card, is solemn. `graveScreen.ts` screens the user's words and the cleaned English `thought` and forces solemn on a hit. A solemn cook never writes Witty or Tough and stores our fixed reasons in `meta.skippedStyles`; `solemn` itself is never on the wire. A written witty line that names real harm makes the cook solemn before signing (`withoutGraveJokes` in `cook.ts`), and a recook of Witty or Tough on a grave signed thought answers with the reason, no model call and no charge. **Four of six.** The decision ranks the six styles best first and `chooseStyles` keeps that order: no style is guaranteed, a solemn thought is exactly stoic, hopeful, tender, and values, and a card always has four. A build that does not send `Angles-Style-Set: 2` gets the original four only (`styleSet.ts`); for it `chooseStyles` still always writes stoic and hopeful and a solemn card has two. A happy moment with no complaint is a thought too: it cooks on the first turn with angles that keep the feeling, never a "what are you stuck on" question. A first message that asks to be asked ("ask me some options", `asksForQuestions` in `decision.ts`) or is only a bare mood ("my day started meh") gets one specific question with 2–3 options; if the model writes the card anyway on such a request, one repair asks instead, and a request to the AI is stripped from the card thought (`withoutMetaRequests`). Never reframe a thought flagged for safety. `followUps` caps at 6, but the product asks at most two clarifying questions: the decision is forced to land from the second answer (`FORCE_READY_AFTER` in `cook.ts`). The phone shows compose as a top-down thread: the user's thought, the AI's answered questions with their answers, and one tailed reply (the open question with its quick replies, or the angles). Rows fade in with a short slide from their own side. Only a new row animates; rows already on screen stay still. Once angles are on screen there is exactly one card, with a quiet Start new link beneath it (outside the card), its Post button anchored in the bottom bar where the input was, and no more writing except an edit. The pencil left of a live bubble puts its text back in the input; committing an edit after the AI has answered folds the whole old exchange into a collapsed "Edited · Previous version" accordion (an archived card keeps Post this version) and the live thread starts a new generation of row ids with the edited message and its new cook. Avatars sit at each bubble's tail (the AI's bottom left, yours bottom right). The phone sends `text` and the answers to its questions as `followUps`, never anything the AI wrote (the client keeps the text under 2000 characters).

**The writer.** A ready decision gets one batch JSON call that writes a hidden `plan` (one technique per style, all different) and then each style from its own voice, technique menu, and banned openers in `STYLE_VOICES`, steered by timeframe, intensity, and distortions. `reframeLint.ts` then checks every answer, and any style that fails gets one targeted rewrite (call kind `rewrite`) while the deadline allows; a rewrite ships only if it has fewer problems.

**Their language.** When `meta.inputLanguage` is not English, every answer comes back twice: `reframe` in English and `reframeOriginal` in their language, written the way a native speaker would say it rather than translated word for word. The public card stays English; only the author gets `reframeOriginal` back from `/cards` and `/feed`, and sees it through the Original toggle. A `reframeOriginal` that still has a foreign number after the rewrite is dropped and the English ships alone.

**Recook.** "New answer" sends `{ recook: { style, cook: { thought, thoughtOriginal?, meta, model, signature }, previous?: { reframe, reframeOriginal?, signature } } }`, all echoed unchanged from the ready response. The server verifies the cook and the previous answer (400 `VALIDATION_ERROR` before metering if either fails or `meta.safety` is not `none`), skips the decision call, and writes one style at temperature 0.95 with the previous answer in view and a different technique. A style the cook skipped answers as a continue with its reason, no model call, and no charge. The response keeps the cook's own `thought`, `meta`, `model`, and `signature`; only the new result is new.

**Safety fails closed.** Any safety label the model returns that is not `none` or a clear synonym of it is treated as `self_harm`, on the server (`normalizeSafety` in `decision.ts`) and in `SafetyFlag` on the phone. `safetyScreen.ts` also screens the text and every follow-up answer for explicit and passive self-harm phrasing in several languages; a screen hit overrides the model's `none`, and still answers with the crisis continue if the model call fails. A flagged turn is a continue with no chips, even on a forced turn. The model never writes a phone number or hotline: the request carries the phone's `region` (ISO 3166-1 alpha-2, never sent to the model), and `crisisResources.ts` picks the line — 988 in the US and Canada, 112 across Europe, a short table of others, and a generic "call your local emergency number" line for anything unknown or malformed. A malformed `region` never fails the request. A crisis message that contains a digit is replaced with the fixed fallback.

**Retries replay.** Every refine turn and recook sends an `Idempotency-Key` UUID and a `Replay-Key` (32 random bytes, unpadded base64url) that the phone keeps with it. The server seals the finished response under that key (AES-256-GCM, `reframeReplay.ts`) in the same transaction that charges it, and keeps the ciphertext for an hour. A retry with the same key and request gets the same signed response back and is not charged again; the taste is not spent twice. The server never stores the replay key, so it cannot read what it stored. Once the free decision call is done, the paid writer is detached from the phone's connection: it always finishes and seals a replay, so a phone that went away gets the angles on retry. A `failed` or `expired` attempt with the same key and request restarts on the same row (never charged before); a `ready` or `continue` attempt with no replay is still 409 `REQUEST_ALREADY_COMPLETED`, and a live one is 409 `OPERATION_RUNNING`. The phone waits 25 s per request, finishes under a background task, and `ReframeRetry` retries the same attempt on a lost connection or a running cook, so every error ends in a Try again.

## Home stack

Home is a stack (`GET /stack`), ranked for the signed-in viewer when `FEED_RANKING=resonance`. The score in `feedRanking.ts` is recency first: a post from today beats last week's unless saves, follows, and themes together make up the difference. Quality is a card's save rate among the people who decided on it, compared only with cards of the same weight (heavy or light), so passing grief never marks grief down; about 20% of each page is held for cards fewer than 8 people have decided on. One author is at most about 10% of a visit. `db/stack.ts` draws candidates from six slices (`CANDIDATE_STRATA`) and ranks each visit once, kept in memory (`STACK_CACHE=off` disables it); a miss rebuilds the same order. Distress is capped, never rewarded. There is no dwell-time signal. Every input is read as of the visit's `startedAt`. The plain-language rulebook is `docs/home-feed.md`; change it with the behaviour. Full weights are `BUILD.md` sections 14 and 27.

**Never in the stack:** the viewer's own cards, private cards, blocked authors either way, reported cards, saved cards, and passed cards except the one return below.

**Loves tell the author.** A decision that turns into a save stores a `love_notifications` row (never for a house card); a save that stops being one deletes it while unread. The push waits 10 seconds and only goes if the save still stands, groups unread loves per card, and never carries thought text; tapping the push or the bell row opens `PostDetailView` on the loved angle. `share_love_name` off makes the author see "Someone" with no actor id. Never expose other people's save counts. **Follows** add a 0.6 boost; following 3+ authors with posts in the last 7 days reserves about 25% of each page for them, capped at 50%. **Themes** come from what the viewer writes and saves, minus a little for each pass (never below zero); every page follows the 40/35/25 core/adjacent/explore mix scaled by confidence. **Pacing** never puts two heavy cards (solemn, grief, intensity 4+) side by side while a lighter one is left.

**Decisions.** A save (Love on screen) keeps the whole card, opening in Loved on the angle it was loved on. Only a sideways drag decides; the card follows the finger everywhere and springs back otherwise. A pass may return the card **once**: at least 12 hours later, only after a first pass, only while it has an angle the viewer never saw, opening on the first such angle, at most 20% of a page. An angle counts as seen once it is on screen. Each card has one `card_decisions` row per viewer (`kind`, `style`, `checkedStyles`, `passes`), written whole by `PUT /cards/:id/decision` and cleared by `DELETE`, so Rewind restores the exact prior row any number of steps back within a visit. Unsave from a list is a pass with every angle seen and `passes` 2. The phone writes optimistically through one serial queue.

**Visits and paging.** A visit starts on cold launch, after 30 minutes away, on Check again, or when the filter (life areas, moods) changes. The phone sends the visit's `session` back with `seen` (handed-out cards whose decision the server has not confirmed, at most 200), renders three cards, and asks for more when 5 are left. **House cards** (From Angles, `users.kind = 'house'`) come only after the visit's community cards are used up, then the end card (Inspire me, Check again). A post never enters the stack: compose closes back to the same card with a Posted or Saved privately toast and a Profile pulse.

Save writes that cook to `POST /cards` with both signatures echoed back unchanged. Both signatures are bound to the account that cooked it, so a cook signed for one account does not save under another. The cook `signature` covers `thought`, `thoughtOriginal`, `model`, and `meta` minus `matching` (including `distortions`); each result signature covers the thought it answers plus its style, `reframe`, and `reframeOriginal`, and names no model. A recook signs its one result against the cook's cleaned `thought`. `POST /cards` rejects any missing or mismatched signature, and any `meta.safety` other than `none`, with 400 `VALIDATION_ERROR`. One cook makes at most one card per account (`cards.cook_signature`): a repeated save returns the first card with 200, before moderation. Saves and passes are one `card_decisions` row per viewer and card; `isPublic` (default false) sits on the card. A saved card leaves the viewer's Saved list when its author makes it private. There are no pins. `POST /reframe` never stores cards or plaintext thought text; it writes only text-free metering/idempotency state, provider token/cost records, and the hour-long replay sealed under a key the server does not keep.

## Subscription access

Access is `active`, or `grace` while Apple's Billing Grace Period lasts. `billing_retry` after grace is stored but locked, on the server and on the phone. A client sync of a lapsed receipt never overwrites a grace or billing-retry state from Apple's notifications. On the phone, a status read that fails or times out does not clear an unlock the phone already had when the only receipt for this account is a lapsed one; the server still gates every cook. Billing Grace Period must be on in App Store Connect. Account delete removes the avatar first, retries it, and fails with 503 `STORAGE_UNAVAILABLE` without deleting anything if storage will not confirm.

## Type sync

`Style` JSON values: `stoic`, `hopeful`, `witty`, `tough`, `tender`, `values`: the same word is the stored key, the label on screen, and the name the model reads. Append only. Migration `0024_one_style_label.sql` renamed the old keys (`optimistic`, `humorous`, `tough_love`) in the enum and in `cards.skipped_styles`; a build that predates it sends and expects the old keys and no longer works against this backend.

**Older builds.** Build 30 and earlier fail a whole cook on a style they do not know and send no version header. Every request without `Angles-Style-Set: 2` is served the original four: the cook chooses among them, `mapCard.ts` drops other angles and keeps `spotlightStyle` on a returned one, ranking reads only those angles, and a decision naming a style outside them is 400. Never send a new style to a request without the header, and never roll the backend back past this once a card has one.

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
