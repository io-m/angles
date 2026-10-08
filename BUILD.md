# Angles build tracker

Living document for **what to build, in what order**. Update this file in the same change as every new screen or feature.

## How to update

When you add or change a screen/feature:

1. Set its **Status** (`not started` → `in progress` → `done`).
2. Fill **Files** and a one-line **Shipped** note.
3. Move **Next up** to the following item.
4. If you need a screen that is not listed, add it here *before* building it.

Do not skip ahead. Do not invent extras (social, extra styles).

Status values: `not started` · `in progress` · `done` · `skipped`

## Next up

**No product work is queued.** Rows 9w through 23 are done. Do not invent screens or features. Report review for the operator is `https://useangles.app/admin` (`docs/operator-admin.md`); `pnpm reports` over SSH remains the backup.

What is left is launch setup outside the app. The Railway API (`https://api-production-61c9.up.railway.app`) is up: `/health` returns `{"status":"ok","db":"ok"}`, with `APPLE_CLIENT_SECRET` and `APPLE_APP_ID` set. The client secret expires on 3 April 2027 and has to be renewed before then. Still open: App Store Connect settings and the listing. Privacy, terms, and support are live at `https://useangles.app`, including the 2 October 2026 text. The status and the remaining list are in `docs/app-store-readiness.md`. The checkbox version is `docs/release-checklist.md`.

## Core loop

Tab shell: **Home | Sparkle | Profile**. Sparkle opens the compose overlay. Profile is the private library. Home is every public card, including the viewer’s own. Private cards stay off Home.

Loading and error are **states on Results**, not their own screens.

| # | Item | Kind | Status | Files | Shipped |
| --- | --- | --- | --- | --- | --- |
| 1 | Compose (home) | screen | done | `AnglesApp.swift`; `Home/*.swift` | Favorites strip (max 6) + mixed-style grid; answer-first flip; long-press Delete. |
| 1b | Favorites | screen | done | `FavoritesView.swift`; `ProfileSubsetView.swift`; `ProfileView.swift` | Title opens a full favorites grid. Server-backed with the library. |
| 2 | Results | screen | done | `ComposeSheetView.swift`; `HomeViewModel.swift`; `ReframeCardView.swift`; `SampleCardCopy.swift` | Ready card header with JM avatar + Public/Private (Public default); Save sends `isPublic`. |
| 2a | Settings (appearance + profile + subscription) | screen | done | `Theme/*`; `Settings/*` | Warm-neutral charcoal tokens; modal Settings with local profile name/photo, appearance popover, real subscription sheet. Accent picker removed. |
| 3 | Multi-style results | same screen as 2 | done | `ComposeSheetView.swift`; `ReframeCardView.swift` | Always all 4 styles. Answer-first carousels on home and overlay. |
| 4 | Hook up fetching | feature | done | `ReframeService.swift`; `backend/src/routes/reframe.ts` | API contract exists. Overlay mocks on-device until a real LLM. |
| 4b | Tabs + Profile shell | screen | done | `AnglesApp.swift`; `Root/RootTabBar.swift`; `HomeView.swift`; `ProfileView.swift`; `HomeCardGrid.swift` | Home empty + Settings; Sparkle compose; Profile filters by style present, not cover. |
| 4c | Real LLM | feature | done | `llmClient.ts`; `HomeViewModel.swift`; `AppConfig.swift` | Overlay calls `POST /reframe`. Server-only catalog: Mistral Small primary, GPT-4.1 mini fallback. |
| 4d | Model picker | feature | removed | `ComposeSheetView.swift`; `LlmModel.swift`; `llmClient.ts` | Removed in 17: the server routes a model per step and compose has no picker. |
| 4e | Core LLM contract | feature | done | `decision.ts`; `prompts.ts`; `reframe.ts`; `ReframeModels.swift`; `HomeViewModel.swift` | Every cook runs a JSON decision call; `continue` keeps the composer; card-fit English thought plus matching metadata. |
| 5 | Card persistence | feature | done | `docker-compose.yml`; `backend/src/db/*`; `CardsService.swift`; `HomeViewModel.swift` | Profile library reads Postgres; Save writes the full cook; categories and tags are first-class. |
| 5b | Favorite angles | feature | done | `schema.ts`; `cards.ts`; `ReframeCardView.swift`; `ProfileView.swift`; `FavoritesView.swift`; `ProfileSubsetView.swift` | Per-style hearts; Profile strip (max 6) plus full Favorite angles grid; liked styles only in that carousel. |
| 5c | Pinned posts | feature | removed | `schema.ts`; `0003_drop_pins.sql`; `ProfileView.swift`; `FavoritesView.swift`; `HomeViewModel.swift` | Removed in 9c, schema included. Favorites are the only save; flip reads the thought. |
| 5d | Owner card menu | feature | done | `ReframeCardView.swift`; `cards.ts` | Long press opens the card menu (9c moved it off the ⋯ button): confirm delete, privacy flag, original-vs-English. |
| 5e | Thought type + card height | polish | done | `ReframeCardView.swift` | Thought is slightly smaller and heavier; height hugs max thought/reframe plus chrome. |
| 5f | List and in-card chrome | polish | done | `ReframeCardView.swift`; `HomeCardGrid.swift`; `ProfileView.swift` | Strip list-dots and tighter grid rows. In-card dots went away with the pager in 9c. |
| 6 | Onboarding taste | screen | done | `ComposeSheetView.swift`; `AnglesApp.swift`; `Root/AppGate.swift`; `HomeViewModel.swift`; `SettingsView.swift` | Native chat welcome hero ('Break the spiral') in ComposeSheetView; zero survey. Shown after Apple sign-in when `tasteCompletedAt` is empty and StoreKit is not entitled. Taste Save is always private and stamps server `tasteCompletedAt` in the card transaction; Settings Log out returns to Login. |
| 7 | Paywall | screen | done | `Paywall/*.swift`; `Resources/celebration-checkmark.json`; `StoreKit/StoreKitManager.swift`; `AnglesApp.swift`; `HomeView.swift`; `SettingsView.swift` | Saved taste crossfades onto the Lottie celebration, then the four-angle paper and annual/monthly hard paywall. |
| 7b | StoreKit sandbox | feature | done | `StoreKitManager.swift`; `PaywallView.swift`; `project.yml` | Debug on device always uses App Store sandbox; verified entitlements unlock; empty catalog shows Retry; DEBUG product/transaction logs. |
| 7c | Taste-once routing | polish | done | `AnglesApp.swift`; `StoreKitManager.swift`; `ComposeSheetView.swift`; `PaywallView.swift`; `SettingsView.swift`; `HomeView.swift` | Launch waits for StoreKit entitlements; only live status, `currentEntitlements`, or a fresh verified purchase unlock Home; taste header link restores purchases; overlay is not dismissible until ready; paywall Restore purchases; Settings Log out is a local session and does not cancel Apple. |
| 7d | Frost handoffs | polish | done | `AnglesApp.swift`; `Root/AppGate.swift`; `Root/LaunchSplash.swift`; `PaywallView.swift`; `StoreKitManager.swift` | One covering frost; checkout glass overlay over the paywall; one pure `AppGate` destination from a single input snapshot so launch/login/logout never flash Home, taste, or paywall; an expired subscription stays on the paywall with Renew. Cold launch is a dark aperture punch splash: the unified mark smoothly floats in from 92% to 100% scale in an ambient glow, shimmers and pulses while work runs, dips in anticipation, and punches forward through the camera to reveal Home; later Home returns keep the frost. |
| 7e | Membership paywall | polish | done | `PaywallView.swift`; `AnglesApp.swift` | Celebration, four-angle paper, 44pt price, and annual/monthly checkout share one screen; there is no intermediate plans step. |
| 7f | Taste header + membership | polish | done | `ComposeSheetView.swift`; `PaywallView.swift`; `StoreKitManager.swift`; `AnglesApp.swift` | Taste restore sits in the model-button row; ended membership opens the same two-plan paywall, preselects the prior plan, and purchases the selected SKU. |
| 7g | Paywall positive capture | polish | done | `PaywallView.swift`; `AnglesApp.swift` | Paper sells four angles as a 2x2 of style tiles; purchase module is spread commerce (44pt price, both plans, CTA); (i) holds library/Home, restore, legal. |
| 7h | Sandbox-only checkout | polish | done | `project.yml`; `StoreKitManager.swift`; `AnglesApp.swift`; `PaywallView.swift`; `HomeView.swift`; `ProfileView.swift`; `HomeViewModel.swift` | No local StoreKit file; prior-plan-aware renewal; neutral checkout copy; one serialized checkout/feed/frost handoff; first loads wait for entitlement readiness. |
| 7i | Paywall specimen marquee | polish | done | `PaywallCardMarquee.swift`; `PaywallView.swift` | Paper is a tilted 3-row marquee of specimen cards that bleeds behind the purchase sheet’s rounded corners; (i) sits on the module. |
| 7j | Launch resume | polish | done | `LaunchSplash.swift`; `AnglesApp.swift`; `SessionStore.swift`; `HomeViewModel.swift`; `HomeFeedSnapshotStore.swift`; `FeedLatestPill.swift`; `mapCard.ts`; `feed.ts` | Splash holds 0.85–1.5s with a shimmering, pulsing mark, then punches. Returning Home paints last For you from disk; a newer mix waits behind See latest so cards never vanish under a finger. Session body restores instantly and revalidates in the background. Ranked mapping reads run in parallel and reuse ranking follows. |
| 8 | Auth | feature | done | `auth.ts`; `authStub.ts`; `schema.ts`; `0009_auth_tables.sql`; `profile.ts`; `LoginView.swift`; `SessionStore.swift`; `AuthCredentials.swift`; `APIClient.swift`; `AnglesApp.swift`; `SettingsView.swift` | Continue with Apple first; `tasteCompletedAt` on the user; Keychain bearer on every API call; Settings log out and delete account. Native POSTs skip browser CSRF so a leftover cookie cannot 403 login. A sign-in is published only after StoreKit answers for that account; log out clears the session locally in one frame, then revokes it; a 401 only ends the session whose token it rejected. |
| 9 | Public opt-in / community Home | screen | done | `HomeView.swift`; `feed.ts`; `schema.ts`; `CardsService.swift` | Public-others feed by Recent, category, and emotion; viewer pin/heart saves; `pnpm db:seed-community`. |
| 9b | Home perf, header, card gestures | polish | done | `HomeView.swift`; `HeaderChrome.swift`; `ReframeCardView.swift`; `FeedSubsetView.swift`; `homeFeed.ts`; `feed.ts` | Lazy shelves + grouped `GET /feed/home`; one collapsing header; three-band cards; domain/mood zipper. |
| 9c | Style chips, flip chevron, no pins | polish | done | `ReframeCardView.swift`; `HomeCardGrid.swift`; `HomeViewModel.swift`; `AnglesApp.swift`; `APIClient.swift`; `feed.ts`; `cards.ts` | Chips replace the in-card pager; heart top-right, flip chevron bottom-right; pins gone; failed writes say so. |
| 9d | Full-width cards, hittable chips | polish | done | `ReframeCardView.swift`; `HomeCardGrid.swift`; `ProfileView.swift`; `ProfileSubsetView.swift`; `HomeCardStrip.swift`; `prompts.ts` | One card per row; selected chip is a labeled pill; 16pt grid gap; landscape strips. |
| 9e | Scroll + pagination performance | polish | done | `HomeViewModel.swift`; `HeaderChrome.swift`; `HomeView.swift`; `ProfileView.swift`; `FeedSubsetView.swift`; `ProfileSubsetView.swift`; `HomeCardGrid.swift`; `ReframeCardView.swift` | Field-level observation; header-only capped scroll state; append-only shelf paging before the edge; chips animate only on tap; heart bounce. |
| 9f | Flat filtered Home + stacked cards | feature | done | `HomeView.swift`; `HomeFilterSheet.swift`; `HomeViewModel.swift`; `ReframeCardView.swift`; `CardsService.swift`; `feed.ts`; `db/feed.ts`; `schema.ts`; `0004_feed_emotions_gin.sql` | One faceted vertical feed; scrolling title with fixed trailing actions; full-card style wash; Favorite angles keep equal-height flips. |
| 9g | Card life-area chrome | polish | done | `ReframeCardView.swift`; `HomeViewModel.swift`; `ReframeModels.swift` | Quiet icon + label left of ⋯; equal 16pt chrome inset; `other` uses `circle.grid.2x2`. |
| 9h | Home inline title | polish | done | `HomeView.swift`; `HeaderChrome.swift` | Large Home fades on scroll; compact headline title fades and slides into the bar center. |
| 9i | Profile identity + style tabs | polish | done | `ProfileView.swift`; `HomeViewModel.swift`; `HeaderChrome.swift`; `AnglesApp.swift` | JM avatar + session name; five pinned tabs (four styles + Favorites); Settings gear on Profile; strip and All popover gone. |
| 9j | Profile wash, chips, paging | polish | done | `ProfileView.swift`; `HomeViewModel.swift`; `HomePalette.swift` | Opaque -45° style chrome; Favorites-first expanding tabs; horizontal paging card lists. |
| 9k | Interactive Profile pager | polish | done | `ProfileView.swift`; `HomeViewModel.swift`; `HomePalette.swift` | Native page offset scrubs one frosted chrome tint and both expanding chips; Favorites is white glass. |
| 9l | Profile scroll coordination | polish | done | `ProfileView.swift`; `HomeViewModel.swift`; `HomePalette.swift` | Delta-coordinated vertical collapse; native-only horizontal progress; one quiet glass plane and accessible Favorites. |
| 9m | Native Profile header sync | polish | done | `ProfileView.swift` | Fixed page spacers plus real per-tab Y synchronization make every collapse/tab/expand combination native and deterministic. |
| 9n | Synchronous Profile handoff | polish | done | `ProfileView.swift` | Mounted vertical scroll views receive destination Y immediately, removing the delayed post-settle header jump. |
| 9o | Single-scroll Profile | polish | removed | `ProfileView.swift` | Removed in 9p: one maximum-height envelope caused expensive tab relayout and trailing space on shorter lists. |
| 9p | Fixed Profile header | polish | done | `ProfileView.swift` | Independent native vertical lists restore lazy performance and real per-tab extents; the shared glass header stays compact and horizontal paging remains interactive. |
| 9q | Home style tabs | polish | done | `HomeView.swift`; `HomeViewModel.swift`; `StyleTabPager.swift`; `ProfileView.swift`; `HeaderChrome.swift`; `CardsService.swift`; `feed.ts`; `db/feed.ts` | For you-default tabs aligned with trailing filter; no Home Settings; one feed; tab-bar footer fade. |
| 9r | Native Home pull-to-refresh | polish | done | `HomeFeedPullRefresh.swift`; `HomeView.swift`; `HomeViewModel.swift`; `HomeFeedShelf.swift`; `FeedRefreshPlan.swift`; `ForYouCovers.swift` | SwiftUI's native refresh interaction starts below the fixed tabs; a pull shows arrivals after the server's arrival mark, else the cards not yet reached plus the next unloaded batch, else starts the rotation over. |
| 9s | Public author profile | screen | done | `AuthorProfileView.swift`; `HomeView.swift`; `StyleTabPager.swift`; `ReframeCardView.swift`; `HomeViewModel.swift`; `users.ts`; `feed.ts`; `ReframeModels.swift` | Avatar opens that author's public posts in Home's five-tab pager; your own avatar switches to Profile. |
| 9t | Following | feature | done | `follows.ts`; `schema.ts`; `0006_worthless_liz_osborn.sql`; `users.ts`; `mapCard.ts`; `feed.ts`; `ReframeCardView.swift`; `HomeViewModel.swift`; `AuthorProfileView.swift` | One-way follow badge on other people's avatars; their public posts stay in the same Home mix. |
| 9u | Following list | feature | done | `follows.ts`; `profile.ts`; `FollowingSheet.swift`; `ProfileView.swift`; `HomeViewModel.swift`; `ProfileService.swift` | A people icon beside Settings opens the people you follow; a row opens their posts, and the minus icon unfollows. |
| 9v | Model cards page | screen | removed | `ModelProfileView.swift`; `HomeView.swift`; `StyleTabPager.swift`; `HomeViewModel.swift`; `models.ts`; `feed.ts`; `schema.ts`; `0008_public_model_created_idx.sql`; `ReframeModels.swift` | Removed in 17 with the picker (index dropped in `0017_wise_aaron_stack.sql`); every card carries the Angles mark. |
| 9w | Production community safety | feature | done | `ReframeModels.swift`; `CardsService.swift`; `ProfileService.swift`; `ReframeCardView.swift`; `BlockedPeopleSheet.swift`; `SettingsView.swift`; `HomeViewModel.swift` | Report reasons and confirmed blocks remove unsafe community content across loaded pages; Settings lists blocked people for undo. |
| 10 | Production legal/privacy hardening | feature | done | `docs/legal/*`; `PrivacyInfo.xcprivacy`; `AppConfig.swift`; `Info*.plist`; `project.yml`; `SettingsView.swift`; `PaywallView.swift` | Source privacy/terms, App Privacy declarations, Release-safe configuration, and centralized legal/support links. |
| 11 | Server subscription entitlement | feature | done | `subscriptions.ts`; `appStoreVerifier.ts`; `appStoreNotifications.ts`; `StoreKitManager.swift`; `ProfileService.swift`; `0011_workable_rage.sql` | Account-bound StoreKit purchases sync verified JWS receipts to a server-owned entitlement; account generations prevent late Apple/server results from crossing sessions. |
| 12 | Production credit metering | feature | done | `metering.ts`; `meteringPolicy.ts`; `reframe.ts`; `ReframeModels.swift`; `APIClient.swift`; `ReframeService.swift`; `HomeViewModel.swift`; `ComposeSheetView.swift`; `SubscriptionView.swift` | Monthly server-owned credits, retry-safe per-operation idempotency, account-period warnings, model tariffs/availability, and Subscription balance/reset UI. |
| 13 | Backend release hardening | feature | done | `productionConfig.ts`; `productionMigrations.ts`; `seedCommunityGuard.ts`; `Dockerfile`; `.github/workflows/backend.yml` | Runtime migrations, production configuration fail-fast checks, a production seed kill-switch, non-root container health checks, and database-backed CI. |
| 14 | Resonance feed ranking | feature | done | `feedRanking.ts`; `db/feed.ts`; `db/hearts.ts`; `mapCard.ts`; `routes/feed.ts`; `cursor.ts`; `schema.ts`; `0015_sharp_puff_adder.sql`; `types/index.ts`; `ReframeModels.swift`; `CardsService.swift`; `ReframeCardView.swift`; `HomeViewModel.swift` | Freshness, hearts, theme affinity (what the viewer writes and hearts, recency-weighted), follows, second chance, and seeded jitter behind `FEED_RANKING`; a 40/35/25 core/adjacent/explore page mix (v3: recency-first, kept angles hidden; v4: own cards scored like anyone's and 1 per page, a follow share, a fewest-placed-author fallback, a card hidden only when every angle is kept, every input frozen at `startedAt`, and `page.arrivalsAfter`); session-frozen offset paging; `after` arrivals; per-page spread; author-only heart counts; viewer-leaning opening angle. Rulebook: `docs/home-feed.md`. |
| 15 | Home style shelves | feature | done | `feedRanking.ts`; `db/feed.ts`; `db/hearts.ts`; `HomeFeedShelf.swift`; `HomeViewModel.swift`; `HomeView.swift` | Each Home style tab is its own ranked shelf for that viewer, and each card has one primary tab per viewer so the tabs mostly show different cards. For you stays the mixed feed. Hearts, follows, and removals share one card record. |
| 16 | Pre-release hardening | feature | done | `decision.ts`; `crisisResources.ts`; `prompts.ts`; `reframeReplay.ts`; `metering.ts`; `reframe.ts`; `subscriptions.ts`; `cookSignature.ts`; `cards.ts`; `profile.ts`; `schema.ts`; `0016_chilly_molecule_man.sql`; `ReframeModels.swift`; `ReframeService.swift`; `HomeViewModel.swift`; `ComposeSheetView.swift`; `StoreKitManager.swift` | Safety fails closed with region-picked crisis lines; a dropped `/reframe` response replays instead of charging again; access past a failed renewal is grace only; one card per owner-bound cook; account delete never orphans a photo. |
| 17 | Reframe engine v2 | feature | done | `prompts.ts`; `decision.ts`; `safetyScreen.ts`; `cook.ts`; `cookSchema.ts`; `reframeLint.ts`; `llmClient.ts`; `llmUsage.ts`; `meteringPolicy.ts`; `cookSignature.ts`; `reframe.ts`; `cards.ts`; `mapCard.ts`; `schema.ts`; `0017_wise_aaron_stack.sql`; `llmEval.ts`; `eval/thoughts.json`; `types/index.ts`; `ReframeModels.swift`; `ReframeService.swift`; `HomeViewModel.swift`; `ComposeSheetView.swift`; `ReframeCardView.swift`; `InspireMark.swift` | The server picks the model per step and every cook costs 1 credit; a sharper voice and technique menu per style, a hidden plan, lint with one targeted rewrite, a recook that changes technique, and answers in the writer's own language for its author. |
| 18 | Favorite Angle + Write a Thought widgets | feature | done | `project.yml`; `Shared/WidgetSnapshot.swift`; `AnglesWidgets/*`; `FavoriteAngleWidgetPublisher.swift`; `HomeViewModel.swift`; `AnglesApp.swift`; `WidgetTests.swift` | WidgetKit extension with a five-minute scheduled, length-adaptive, privacy-sensitive Favorite Angle and an Angles-mark compose shortcut with native Lock Screen material; App Group snapshots and gated deep links keep model calls and auth in the app. |
| 19 | App Review readiness | feature | done | `AIConsentSheet.swift`; `ComposeSheetView.swift`; `HomeViewModel.swift`; `ReframeCardView.swift`; `PaywallView.swift`; `AnglesApp.swift`; `AppConfig.swift`; `PrivacyInfo.xcprivacy`; `AnglesWidgets/PrivacyInfo.xcprivacy`; `project.yml`; `routes/profile.ts`; `db/subscriptions.ts`; `StoreKitManager.swift`; `docs/legal/*`; `web/app/{terms,privacy}` | One-time AI consent and Terms acceptance before an account's first send; the paywall leads with the billed price and keeps renewal terms, 600 credits, Restore, Terms, and Privacy under the CTA; Log out and Delete account in the paywall (i) sheet; a used-up taste routes to the paywall; a failed receipt check no longer signs the user out; a deleted account's purchase moves to the same Apple ID's new account (never a live account's); Terms gain zero tolerance, 24-hour report review, and the Apple EULA; Privacy gains moderation, Home ordering, legal bases, transfers, and Datatilsynet; widget privacy manifest; Release points at the Railway API. |
| 20 | Release gaps (reports, Apple revoke, Terms gate) | feature | done | `db/reportReview.ts`; `scripts/reports.ts`; `lib/reportAlerts.ts`; `lib/appleRevoke.ts`; `db/communitySafety.ts`; `db/cards.ts`; `db/users.ts`; `routes/cards.ts`; `routes/profile.ts`; `schema.ts`; `0018_report_review.sql`; `0019_terms_acceptance.sql`; `types/index.ts`; `ReframeModels.swift`; `AppleReauthorization.swift`; `SessionStore.swift`; `ProfileService.swift`; `APIClient.swift`; `AppGate.swift`; `AnglesApp.swift`; `AIConsentSheet.swift`; `ComposeSheetView.swift`; `SettingsView.swift`; `AppConfig.swift`; `project.yml` | Every new report emails the operator, and `pnpm reports` lists open reports and hides, keeps, deletes, or suspends; Delete account revokes the Sign in with Apple grant; a paid account must accept the Terms (stored on the server) before Home; support email, a "not therapy" line, and no empty app icon set. |
| 21 | Operator admin | feature | done | `routes/admin.ts`; `lib/adminSession.ts`; `lib/adminMail.ts`; `db/adminLogin.ts`; `db/reportReview.ts`; `0020_admin_login_challenges.sql`; `web/app/admin/*`; `web/worker.ts`; `docs/operator-admin.md` | Allowlisted operators sign in with a Resend magic link at `useangles.app/admin` and keep, hide, delete, or suspend from the report inbox. The site proxies to Railway `/admin`. `pnpm reports` over SSH still works. |
| 22 | Follow notifications | feature | done | `schema.ts`; `0022_follow_notifications.sql`; `follows.ts`; `followNotifications.ts`; `communitySafety.ts`; `apns.ts`; `profile.ts`; `users.ts`; `types/index.ts`; `ReframeModels.swift`; `ProfileService.swift`; `FollowNotificationsSheet.swift`; `FollowPush.swift`; `ProfileView.swift`; `SettingsView.swift`; `AnglesApp.swift`; `HomeViewModel.swift`; `project.yml` | A new follow stores one in-app row and can push with Follow back. Unread rows do not stack. A block deletes both directions. Follows and push use the actor's display name when set, else initials. One bell open clears both badges; the only automatic permission ask is iOS's dialog once Home is on screen. |
| 24 | Six voices, four angles, style menu | feature | done | `types/index.ts`; `styleSet.ts`; `decision.ts`; `prompts.ts`; `cook.ts`; `graveScreen.ts`; `mapCard.ts`; `db/feed.ts`; `routes/{reframe,cards,feed}.ts`; `0023_tender_values_styles.sql`; `llmEval.ts`; `ReframeModels.swift`; `APIClient.swift`; `HomeViewModel.swift`; `HomePalette.swift`; `StyleTabPager.swift`; `HomeFeedSnapshotStore.swift`; `AnglesWidgets.swift`; `PaywallView.swift` | Tender (rose) and Values (violet) join the four styles. A cook writes the four that fit the thought best, ranked by the decision, with no style guaranteed; a solemn thought is always Stoic, Optimistic, Tender, and Values. Builds that send `Angles-Style-Set: 2` get all six; anything older is served the original four on every route. Home, Profile, and author pages pick a style from a native menu instead of a chip row; Profile keeps Favorites as its own chip. |
| 23 | In-app App Store rating | feature | done | `StoreKit/AppStoreReviewCoordinator.swift`; `AnglesApp.swift`; `HomeViewModel.swift`; `SettingsView.swift`; `AppConfig.swift`; `project.yml`; `Info.plist`; `Info-Debug.plist` | After the third entitled Save or Post, once the celebration has left Home or Profile, the system review dialog may appear; at most twice, 90 days apart. Settings → Rate Angles opens the App Store write-review page. Taste and crisis cooks never count. |

### 1. Compose (home)

Home shell with a Favorites strip, the main card grid, Inspire me FAB, and header Settings.

- Front of each card is the 4-style carousel; tap flips to the original thought. Each card opens on a mixed spotlight style so the feed is not all stoic. Initials (mock JM) sit on the thought face so they flip with the card. Heart and date stay as overlay chrome.
- Four dots sit under the card while the answer face is showing.
- Long-press Delete. Heart toggles favorites (newest-favorited first). The strip shows at most 6; Favorites opens the full grid.
- Overlay starts with a focused composer. It stays up until a cook is ready, so the user can always answer or say more.

### 1b. Favorites

Tappable Favorites title on Profile. Full grid of favorite cards (same heart/delete). Library is server-backed.

### 2. Results

One statement, then AI refine (not a chat transcript).

- The API may answer with `continue`: its message plus up to 3 chips. Turns and the user's replies stay on screen as a chat, and the composer never leaves.
- The chosen styles show in one stacked card (AI sparkle avatar left of the card). The card header has the author initials top-left and a Public/Private control (Public default); Original stays trailing when the thought was not typed in English. New answer sits in the footer. Loading and error live on this overlay.
- Each style has New answer (overlay only); recook requests that style from the API.
- Start again (header) asks to confirm, then wipes the session and returns the composer (and the Public default). Overlay stays open.
- Save (icon + label) sits where the composer was and writes all 4 with the chosen privacy. X discards.

### 2a. Settings (appearance + profile + subscription)

Profile-gear Settings sheet. Gradient chrome, large title that collapses to inline. Identity header edits a display name and photo. The photo uploads to the private Railway bucket `angles-avatars` (`PUT /profile/avatar`) with a spinner and a short checkmark; a failure keeps the previous photo. The name patches initials (`PATCH /profile`). Cards show that photo, or the author's initials while it loads and when there is none. Appearance is a popover. Subscription is a sheet showing the live plan (Yearly / Monthly / Inactive), price, and renewal, with Restore plus Change/Cancel through Apple's manage-subscriptions sheet. The accent picker is gone; the chat composer glow follows the selected model color instead. Prefs in UserDefaults, not SwiftData.

### 3. Multi-style results

Four angles per card, chosen from six styles by the decision (24). Style picker and per-style checkboxes are gone. Home cards store four slides; the carousel is the default face.

### 4. Hook up fetching

Not a new screen. `POST /reframe` is `{ text, followUps?, styles?, model? }` → `continue` or `ready` (was `clarify` until 4e). The overlay mocked on-device until 4c.

### 4b. Tabs + Profile shell

Three-target bar: Home (community feed, Settings gear), Sparkle (existing compose overlay, not a page), Profile (private library). Favorites strip stays unfiltered. Header picker keeps every card that **has** that style and opens the carousel on it. **All** still uses mixed `spotlightStyle` so the grid is not a stoic wall. Style is not a category; real taxonomy is `category` / tags / intensity. Home shelves use `category` (life-domain) and `emotions` (mood).

### 4c. Real LLM

Not a new screen. `generateReframe` calls the server-only provider catalog (`mistral-small-latest` primary, `gpt-4.1-mini` fallback). Overlay `startRefine` / recook use `ReframeService`. Follow-ups stayed the mock bank until 4e.

### 4d. Model picker — removed in 17

Was a compose-header logo button that sent `model` on `POST /reframe`. The server now routes each step to a model (`modelsForStep`), so the phone never picks one and `/reframe` rejects a `model` field.

### 4e. Core LLM contract

Not a new screen. Every `POST /reframe` runs one structured decision call (`decision.ts` + `DECISION_PROMPT`), then one batched JSON style call for the styles it chose (a recook is still a single `generateReframe`). The old mock gate (`refineDecision.ts` clarify bank, 24-word threshold) is gone.

- Response is `continue` (`message`, `options`, `safety`) or `ready` (`thought`, optional `thoughtOriginal`, 1–4 `results`, `meta`).
- `meta` carries the closed category, tags, intensity, timeframe, emotions, safety, input language, skipped styles, and an anonymous `matching` key. Save writes that cook to Postgres; a discarded overlay is never stored.
- Card copy is English and card-fit (thought 8–22 words / 140 chars, reframe 12–32 words / 190 chars). A non-English input also returns its own cleaned wording behind an Original toggle.
- The composer stays up for every turn that is not a finished cook, so a `continue` is just the next message in the chat. `followUps` caps at 6; from the third the decision is told to land it, safety aside.
- A recook of a style the decision skipped comes back as `continue` with that skip reason, not a bad joke.

### 5. Card persistence

Not a new screen. Local Postgres in Docker (host 5433) + Drizzle. Profile is the private library and reads from `GET /cards`. Save posts the kept cook to `POST /cards`; X still discards. Categories are an enum column; tags have their own table. `POST /reframe` never stores cards or thought text; production metering later added text-free operation and provider-cost writes. No SwiftData.

### 5b. Favorite angles

Heart is per style, not per cook. Profile has a tappable **Favorite angles** title plus a landscape strip (max 6, list dots), and FavoritesView is the full one-card-per-row grid of liked angles. Front is the liked angle; flip is the thought. One liked style has no in-card carousel; two or more liked styles on the same post share one card. Un-hearting the last liked style removes it from this list. Style chips do not filter this strip or grid.

### 5c. Pinned posts — removed in 9c

Pins are gone, app and schema. A card is saved by hearting an angle, and the thought is one flip away. Removed: `PUT` / `DELETE /feed/cards/:id/pin`, `PatchCardRequest.isPinned`, `GET /cards?pinned=`, `StoredCard.isPinned` / `pinnedAt` on the wire, and — in `drizzle/0003_drop_pins.sql` — `cards.is_pinned`, `cards.pinned_at`, `cards_user_pinned_idx`, and the `saved_pins` table. The library is now the viewer's own cards plus whatever they hearted on Home.

### 5d. Owner card menu

Long press on the owner's library cards. Menu: Delete (confirm), Make public / Make private (`isPublic`; omit on `POST /cards` still stores private). Compose Save defaults public with a toggle. Language when a cleaned original exists (client toggle, no new translate). It lived on a top-trailing ⋯ button until 9c gave that slot to the heart. Public posts appear on Home, including the author’s.

### 5e. Thought type + card height

Thought face is slightly smaller and heavier than title3 regular, still distinct from the answer (`.callout` / `.medium`). Card height hugs max cleaned thought and max reframe plus chrome. Overlay uses the same metrics. Prompt budgets stay unless the card cannot fit them.

### 5f. List and in-card chrome

Strips have page-dots for which **card** is in view; cards in those strips have no list-dots. Grid rows are slightly tighter than the strip's horizontal gap. The in-card dots went away with the pager in 9c.

### 9. Public opt-in / community Home

Home is every public card, including the viewer’s own, newest first. Private cards stay off Home. Style filter matches Profile (keeps cards that have that angle; All mixes covers). Sections: Recent, one strip per life-domain `category`, one strip per `emotion`. Pin/heart on someone else’s post writes viewer-scoped saves, not the author’s flags. Profile Pinned / Favorite angles union owned flags with those saves. Making a post public puts it on Home for everyone, including the author.

### 9b. Home perf, header, card gestures

Not a new screen. Polish on 9.

- **Payload.** `GET /feed/home?style=&perSection=6` returns `{ cards, recent, sections }` — shelf ids into one de-duplicated card list, so Home downloads ~140 KB instead of ~500 KB. Shelves cap at 6, so the style filter runs in SQL; changing it refetches without blanking the shelves. Chevron screens page `GET /feed?category=|emotion=&limit=24&before=` as the grid scrolls.
- **Shelf order.** Recent, then a deterministic zipper of life domain and mood in catalog order (Work, Anger, Money, Shame, …). Empty shelves never ship.
- **Scroll cost.** `LazyVStack` mounts shelves near the viewport instead of ~20 strips of flip cards at once. Strips own their scroll position, strips and cards are `Equatable`, and a heart no longer animates or re-renders the page. No page-wide `GeometryReader`: card width comes from `containerRelativeFrame`.
- **Header.** One 44pt row — “Home” leading, style filter then Settings trailing — collapsing into Profile’s centered filter chip (`HeaderChrome.swift` is now shared by both tabs). Settings stays trailing when collapsed.
- **Card bands.** Top chrome (pill / initials, ⋯), middle (copy), bottom chrome (date, heart / pin, dots). Only the middle flips and only the middle holds the in-card pager, so a drag on the date moves to the next card while a drag on the copy pages styles. The date no longer flips; the wash and pill follow the active angle from outside the pager. 9c replaced the pager with chips and re-cut the bands.
- **Cache.** Home and Profile load once; popping a shelf keeps the cards and the scroll position instead of a cold refetch.

### 9c. Style chips, flip chevron, no pins

Not a new screen. Polish on 9b.

- **Chips, not a pager.** The in-card horizontal `ScrollView` and its dots are gone; the collision with the outer list is gone with them. Icon-only chips in the top-left switch the visible answer, one per angle the card carries (1–4). A single-angle card keeps the named pill. Selection is explicit `@State`, not a scroll offset, and four 28pt chips drop to 24pt on a narrower card.
- **Bands.** Top: chips / initials leading, heart trailing. Middle: the copy, which still flips on tap. Bottom: date leading (never flips), flip chevron trailing. Card actions moved to a long press; the pin is gone from cards entirely.
- **Favorite reset.** `HomeCardGrid` keyed card identity on the favorited-style list, so every heart rebuilt the card, reset its state, and snapped the carousel back to slide one — the heart then acted on a different style. Identity is `card.id` from `ForEach` alone.
- **Failed writes.** A heart, privacy flag, or delete that never reaches the server rolls back visibly: a banner at the top of the app says so instead of the heart quietly un-filling ~15s later. Small writes time out in 6s; cooks keep 15s.
- **No pinned list.** Profile is the favorites strip plus the library. `drizzle/0003_drop_pins.sql` drops `is_pinned`, `pinned_at`, and `saved_pins` so the schema and the seed have no pin left in them.

### 9d. Full-width cards, hittable chips

Not a new screen. Polish on 9c.

- **One card per row.** `HomeCardGrid` is a `LazyVStack`. Profile library, Favorite angles, and Home shelf subsets are full width. `usesSingleColumn` is gone. Strips are a landscape peek (`min(pageWidth * 0.84, 340)`).
- **Card.** Inset 16, copy pads 8, height 228 so chrome hugs the copy. Overlay shares the metrics.
- **Chips.** Selected is a labeled pill; the rest stay 36pt circles and morph on tap. Unselected glyphs stay faint. Single-angle cards keep the named pill.
- **Row gap.** Grid spacing matches the 16pt side padding.
- **Budgets.** Thought and reframe caps stay; prompt copy no longer says two-column.

### 9e. Scroll + pagination performance

Not a new screen. Polish on 9d.

- **Measured cause/result.** An Animation Hitches recording on Joe’s iPhone showed baseline main-thread interaction delays up to 131.66ms. Steady Home scrolling was already smooth; reproduction isolated the visible jitter to a shelf page arriving while the user was at the list edge. In the final 20s pagination capture, over-budget rendered hitches fell from 21 to 13 and the worst rendered hitch fell from 125.03ms to 25.01ms. One offscreen-render event was not correlated, so card shadows, gradients, and flip visuals stayed unchanged.
- **Observation boundary.** `HomeViewModel` uses iOS 17 Observation instead of one broad Combine publisher, so subset paging does not invalidate Home, Profile, compose, and unrelated shelves. Subset content receives explicit load state instead of observing the whole model.
- **Header.** Collapse distance lives in header-only state and caps at 80pt. Long flings stop publishing after the header is fully collapsed; feed and library content never read that progress.
- **Pagination.** Shelf pushes retain their six seeded cards and exact server cursor. The next page appends directly instead of re-fetching/replacing page one, deduplicates incrementally, prefetches six rows early on long lists, and keeps a fixed-height loading footer so arrival does not move the scroll edge.
- **Interaction animation.** Programmatic style selection is transactionally non-animated. The selected pill and wash spring only from a chip tap; hearts use a native symbol replacement and bounce without changing card identity or selection.

### 9f. Flat filtered Home + stacked cards

Not a new screen. This replaces the grouped Home and flip-card language from 9b–9e.

- **One feed.** Home is one newest-first `HomeCardGrid`, paged 24 at a time with a composite created-at/id cursor. It prefetches six rows early, incrementally deduplicates, keeps a stable footer, and rejects stale pages after a filter generation changes.
- **Faceted filter.** Home's title scrolls under the existing gradient while filter and Settings stay fixed at the right with no centering or movement. Its Apply-only sheet uses Life areas and Moods tabs. Multiple values are OR within a group and the two groups are ANDed. Profile's style filter is unchanged.
- **API.** `GET /feed` accepts comma-separated `categories` and `emotions`; the old style/singular feed filters and `GET /feed/home` are gone. Category uses `IN`; moods use array overlap backed by `cards_emotions_gin_idx`.
- **Cards.** Home, library, and compose cards show a slightly quieter thought, divider, and dominant selected answer together over the selected style wash. Stored cards put avatar/date/⋯ at the top and style chips/heart at the bottom; ⋯ and long press share actions. Profile Favorite angles alone retain equal-height answer/thought flips so their strip stays level.
- **Removed.** Grouped response types, shelf zipper/state, `homeFeed.ts`, and `FeedSubsetView.swift`. Category, emotion, matching, language, style results, and per-style favorite data remain.

### 9q. Home style tabs

Not a new screen. Replaces the scrolling **Home** title from 9f/9h with Profile-like chrome.

- **Tabs.** A native single-select style menu (24): **For you** (default, mixed `spotlightStyle`) plus the six styles. It replaced five expanding chips, which did not fit six styles on a narrow phone; swiping still pages between them. No Favorites. For you is one ranked `GET /feed`. Each style tab is its own ranked shelf (`GET /feed?style=`), opened on that angle. Profile and author pages still filter one library list in memory. The filter sheet resets every Home shelf.
- **Layout.** One overlay row: expanding tabs leading, filter trailing, same height and center as the filter icon, with a little extra space under the chips. No Home Settings gear (Profile keeps it). Quiet style-tinted paper-to-grey canvas, style-tinted glass header, tab-bar footer fade. `StyleTabPager.swift` shares pager state, chips, and wash with Profile. Each tab is its own vertical `ScrollView` + lazy `HomeCardGrid`.
- **API.** Each style tab calls `GET /feed?style=` and keeps its own page. For you omits `style`. Profile and author pages do not.

### 9r. Native Home pull-to-refresh

Not a new screen. Corrective polish on 9q.

- **Native motion.** Each tab uses SwiftUI `.refreshable`; there is no added drag recognizer, synthetic threshold, layout hold, or refresh-time scroll lock. The closure reads a reference updated on every body pass, not a Bool captured on first layout: Home is in the tree before it is revealed, SwiftUI keeps that first closure, and a captured `false` drops the request. The fetch is detached from the refreshable task, so a shelf update cannot cancel it before it is sent. A pull's end always clears its own refreshing flag, even after a retry or filter moved the shelf on, so the next pull is never refused. If one half of a pull is cut off, the half that landed still applies; only both missing stays silent.
- **Indicator placement.** The scroll view carries a top `safeAreaInset` of the chrome height rather than a clear spacer inside its content. Cards still scroll up behind the frosted header, and because the inset is real, the system spinner emerges directly below the style tabs instead of behind them — no UIKit positioning overrides. Do not replace that inset with in-content padding: that is what hid the indicator between 2026-09-23 and 2026-09-28.
- **Shared refresh.** The native async action awaits `HomeViewModel.refreshFeed(tab)` for the shelf that was pulled. Existing cards stay visible. A pull on Stoic does not rotate For you.
- **Rotating pull.** Home is no longer strictly newest-first across a visit. One pull fetches a small head (8, arrivals only) and the next tail page (24) in parallel, then [`FeedRefreshPlan.swift`](AnglesApp/AnglesApp/Home/FeedRefreshPlan.swift) picks one outcome. Arrivals never share a page with a rotated batch: a page starting today and jumping to last week would hide everything in between and make the banner count a lie. `prepend` keeps the loaded page and its cursor; `rotate` moves up the loaded cards the reader never reached (in rank order), then the tail minus everything this visit loaded, and moves the cursor to the last tail card it *consumed*, never past one the page cap left behind (a tail that failed keeps the shelf's cursor and `hasMore`); `catchUp` (a head that is nothing but arrivals) and `restart` (nothing unread or unloaded left) reload the newest page as a new visit; `unchanged` covers a catalog that fits on what is already on screen. "Reached" is a card's `onAppear` in `TallHomeCardGrid`, kept per tab in `HomeViewModel.feedDisplayedIDs` outside observation so scrolling never redraws Home. The arrival mark (`highWater`) is composite (`createdAt` plus id) because cards share a millisecond. Under ranking it is the server's `page.arrivalsAfter` (14), not the newest card on screen, and arrivals advance it; on chronological pages it is the newest server card. Local inserts (your new post, a republished card) never move it, and the planner ignores an arrival already in `seenIDs`, so your own post is not announced again. `seenIDs` is wider than the shelf's `ids`, which a rotation resets to the page on screen.
- **Stated outcome.** The library is still strictly newest-first, so a refresh with nothing newer returns the identical page and reads as a dead gesture. `FeedRefreshBanner` announces the result under the chrome for about 1s, with the same traveling border spark a new card gets: `N new posts`, `Fresh angles`, `Full circle`, `You're all caught up`, or `Couldn't refresh`. The failure case matters because a failed refresh with cards already on screen otherwise showed nothing at all. Only Home uses the middle two. A cancelled or superseded fetch stays silent (`PageFetchResult.discarded`), one half failing still reports the other's outcome, and both failing leaves that shelf's cards and cursor untouched. Switching tabs does not replay another shelf's banner.
- **Testing new arrivals.** `pnpm db:seed-recent [count]` appends public cards dated now without deleting anything, so a pull while the app is open genuinely finds newer posts. `pnpm db:seed-community` cannot show this: it re-inserts the same fixture rows with the same historical timestamps.

### 9u. Following list

Not a new screen. The Profile bar has a people icon in the same round container as Settings, sitting just before the gear. It opens a large sheet, the same chrome as Settings.

- **List.** `GET /profile/following` is the people you follow, newest follow first. Each row is a 40pt photo or initials and those initials. There is no display name and no count. Empty copy says you aren't following anyone yet. The system search field under the title filters those initials; no matches uses the system search empty state.
- **Open.** A tap on the person closes the sheet and pushes their public posts.
- **Unfollow.** The trailing person-minus icon unfollows them and drops the row. If the write fails, the row comes back with the existing write banner.

### 9w. Production community safety

Every non-owner community card offers Report and Block. Reporting chooses a compact reason; blocking requires confirmation and removes the author's cards, saves, and follow state across Home, Profile, and author pages. The author profile chrome exposes the same block action. Settings → Blocked people lists blocked accounts and restores a row if unblock fails. Public save/publish moderation errors explain whether the content is disallowed or moderation is temporarily unavailable.

### 10. Production legal/privacy hardening

Source privacy and terms documents describe account, AI-provider, card, profile, community, subscription, retention, deletion, moderation, and mental-health handling. The app declares no tracking and its collected data/UserDefaults use, centralizes optional legal/support destinations, keeps development LAN permission out of Release, and reports unavailable links only in Debug until operator-owned hosting and support details are configured.

### 9t. Following

Not a new screen. A one-way follow on someone else's avatar. Their public posts stay in the same Home mix, with a modest lift once ranking is on (`BUILD.md` section 14). No Following tab, counts, or messages. The people you follow are a sheet on Profile (9u).

- **Badge.** A bordered plus on another person's avatar, bottom-trailing. Tap follows; it scales up, ticks, and fills from paper to ink as the plus becomes a checkmark. Tap again unfollows. The rest of the avatar still opens their posts. Your own avatars stay plain, including Profile, compose, and the ready card.
- **Graph.** `follows` is `(follower_id, followee_id)` with cascade deletes and a check against following yourself. `PUT /users/:id/follow` and `DELETE /users/:id/follow` are idempotent. Missing users are 404. `author.following` is on every card and on `GET /users/:id/cards`. Private posts stay off Home.
- **Writes.** The badge flips immediately on every card and the author header for that person, then rolls back with the existing write-failure banner if the request fails.

### 9s. Public author profile

Tapping someone else's card avatar pushes this page over Home or Profile, covering the tab bar. Your own avatar switches to the Profile tab. The compose avatar does not navigate. The private Profile tab stays the library.

- **Who.** Every card author includes `id`. Initials-only authors open the same way as authors with a photo. The header is a back button, the style tabs, and that avatar on the right (photo or initials). There is no display name.
- **Posts.** `GET /users/:id/cards` returns that person's public cards, newest first, with the same cursor as Home. Private cards stay off the page, including the author's own. An empty public list is still that person. Unknown ids are an error on the page.
- **Tabs.** For you is the default mixed cover. A style tab keeps posts that have that angle and opens on it, from the one loaded list. No Favorites, no Life area or Mood sheet, no Settings.
- **Hearts and owner actions.** Same as Home, written through the existing card and feed endpoints. The author list, Home, and the library update in place. Opening this page does not refetch either.
- **Back.** The header chevron pops the page, and so does a swipe from the left 40% of the screen on iOS 26 and later (`wideBackSwipe` in `InteractivePop.swift` opens UIKit's own content-swipe pop for this page only and hands it back when the page goes away); earlier systems keep the system edge strip. The pager no longer scrolls sideways, so nothing competes for the drag. The tab bar returns with the card that opened the page. A tap on this page for the author already showing does nothing.

### 9i. Profile identity + style tabs

Not a new screen. Profile is a private identity page, not a greeting plus two card lists.

- **Header.** Local profile photo plus the typed display name (falls back to initials, then a person glyph; empty still reads **On this iPhone**). `displayName` is a nil seam for Auth (row 8). No mock full name.
- **Tabs.** Five pinned icon tabs replace the style popover: Stoic, Optimistic, Humorous, Tough love, Favorite angles. Default is Stoic. There is no For you tab. Style tabs show owned cards that have that angle and open on it; Favorites is the full liked-angle grid. Empty library still uses the Inspire me hero under the tabs.
- **Removed.** Favorite angles strip, `HomeCardStrip`, `FavoritesView`, `ProfileSubsetView`, and the header filter popover. Home has no Settings gear; Profile keeps the trailing gear.

### 9j. Profile wash, chips, paging

Not a new screen. Polish on 9i.

- **Chrome.** Opaque paper plus a stronger style wash, lit from -45° (top-leading to bottom-trailing). Favorites uses a quiet ink tint. Cards cannot show through the identity or tab row. Wash crossfades when the settled tab changes.
- **Tabs.** Favorites is first and the default, as its own chip. The six styles are one native single-select menu beside it (24), which reads "Styles" while Favorites is on screen. Spring only on selection change.
- **Paging.** Identity, tabs, and Settings stay put. Card lists sit in a horizontal paging strip (`scrollTargetBehavior(.paging)`), not an inner TabView, that the menu or Favorites chip scrolls; since 24 a finger cannot drag it. Each page is its own vertical `ScrollView` + `HomeCardGrid`.

### 9k. Interactive Profile pager

Not a new screen. Polish on 9j.

- **Finger-tracked paging.** A capped header-only pager state reads native horizontal content offset every frame (scroll geometry on iOS 18, named-space probe on iOS 17). The card lists, glass tint, and tabs share the same continuous page position; the settled id remains data state only.
- **Continuous chrome.** One ultra-thin material plane covers the status bar, compact title, Settings, identity, and tabs. Adjacent -45° tint gradients crossfade by page progress; Favorites uses white highlights instead of grey ink, and card contours blur beneath the collapsing glass.
- **Continuous chips.** The leaving label stays mounted while its pill contracts and fades; the entering circle expands as its label fades/scales in. Live offset updates disable animation, while taps and final settling retain the short chip spring (no spring with Reduce Motion).

### 9l. Profile scroll coordination

Not a new screen. Corrective polish on 9k.

- **Vertical physics.** The active page sends raw offset deltas into one capped Profile header state. Page insets are stable during a gesture and rebased before horizontal arrival, so cards and chrome move 1:1 and switching tabs preserves the current collapse. Negative overscroll rebound cannot re-collapse an extended header, and deep cards return to the collapse boundary before the header grows.
- **Horizontal physics.** Native page geometry is the only live visual source. The midpoint-changing `scrollPosition` binding is gone; settled data/header state commits only at a physical page endpoint, while chip taps use `ScrollViewReader`. Idle normalization is non-animated, observation is limited to tint/chips, and chip layout caches intrinsic sizes.
- **One accessible glass.** A quiet uniform style tint and diagonal sheen share one thin-material plane across status, identity, Settings, and tabs. Favorites uses adaptive theme ink on a surfaced hairline chip instead of white-on-white.

### 9m. Native Profile header sync

Not a new screen. Replaces 9l's synthetic inset coordinator.

- **One vertical truth.** Every tab has the same fixed expanded-header spacer. Active collapse is the clamped native vertical content offset, so scrolling down traverses real content distance before elastic overscroll and bounce cannot move the header.
- **Prepared destinations.** An adjacent shallower tab is moved to at least the current collapse before arrival (`ScrollPosition` on iOS 18, a fixed-marker `ScrollViewReader` fallback on iOS 17). Tab changes never expand the header; deeper destinations may collapse it further with horizontal progress.
- **Transition matrix.** Tap, swipe, cancel, reverse, partial collapse, full collapse, deep lists, and short/empty pages share the same prepare → native scroll → endpoint commit flow. Only the active vertical page and small chrome views publish per frame.

### 9n. Synchronous Profile handoff

Not a new screen. Corrective polish on 9m.

- **No deferred restore.** Each mounted page registers its native vertical scroll view with the Profile coordinator. The destination offset is set synchronously and without animation while that page is still offscreen, rather than waiting for a SwiftUI scroll-position request after landing.
- **One visual timeline.** Header height continues to interpolate from horizontal geometry, then endpoint commit only changes data ownership. There is no delayed second transition to the destination's expanded/collapsed state.

### 6. Onboarding taste

Frictionless first-run experience directly in the real app compose canvas:

- Zero profiling survey (no questions about personal demographics or body metrics).
- No email or password: Continue with Apple (row 8) is the only sign-in. Complies with Apple Guideline 2.1 (no reviewer demo credentials required) and 5.1.1(v).
- Native welcome hero in `ComposeSheetView`: "Break the spiral." with subtitle capturing the mental loop/overthinking problem. Starter prompt chips are not in the compose hero.
- Taste is the `AppGate` destination for a signed-in account with an empty `tasteCompletedAt` and no StoreKit entitlement. An active subscription skips taste. There is no install-local taste flag; the old `hasCompletedOnboardingTaste` / `hasEnteredPaywallFlow` keys are removed at launch.
- Sending a thought runs the cook with cycling progress lines, arriving at the ready card.
- The overlay cannot be dismissed during the taste. Taste Save is always private (`saveCook(forcePrivate:)`) and the card hides the Public/Private control. The first ready taste stamps `tasteConsumedAt` on the server; a Save stamps `tasteCompletedAt` (same transaction as the card) and moves the destination to the celebrating paywall. Either stamp ends the taste, so killing the app on an unsaved result relaunches on the paywall.
- A taste the server says is used up (`TASTE_LIMIT_REACHED`, `TASTE_ALREADY_CONSUMED`) routes to the paywall instead of stranding the composer.
- Before the first send, each account agrees once on this phone to the AI disclosure and the Terms (`AIConsentSheet`).
- Settings **Log out** returns to Login. It does not cancel Apple. The paywall (i) sheet also has Log out and Delete account, so an account can be deleted without paying.

### 7. Paywall

The first saved taste keeps a covering frost and plays the ThinLine checkmark/confetti Lottie; the Home feed is not shown in between. It then reveals **“One thought. Four ways out.”**, the 2×2 angle tiles, and the annual/monthly purchase module on the same screen. Annual (`app.angles.ios.annual`) and monthly (`app.angles.ios.monthly`) prices come from StoreKit `displayPrice`; the hero price is always the billed amount, with the yearly plan's monthly equivalent only in the caption. There is no free trial. Under the CTA the purchase module always shows the renewal price and period, 600 credits a month, the auto-renew terms, **Restore purchases**, **Terms of Use**, and **Privacy Policy**. Verified purchases and restores persist the unlock cache, but Apple overwrites it before routing and Settings. Successful purchase or restore dissolves the covering frost to reveal Home.

### 7b. StoreKit sandbox

Not a new screen. Hardens row 7 for App Store sandbox:

- Native StoreKit 2 only: `Product.products(for:)`, `product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()`. Unfinished transactions are finished on the same verify path so interrupted purchases recover.
- Unlock after a verified, unrevoked Angles purchase transaction, or a live subscription status / `currentEntitlements`. `Transaction.latest(for:)` never unlocks. `hasUnlockedFullApp` is a launch cache, then StoreKit overwrites it when Apple reports expired or revoked — not when `currentEntitlements` is briefly empty after `finish()`.
- Paywall never disables Subscribe because the catalog is empty: it shows Loading, Retry, or a clear error, and prices come from StoreKit `displayPrice`.
- Debug on device always uses App Store sandbox. The `AnglesApp` scheme has no StoreKit configuration file, so Xcode Run and `devicectl` install hit the same store. Products come from App Store Connect.
- A subscription group is ended only when nothing in it is live. An expired Annual must not override an active Monthly.
- DEBUG logs requested/returned product IDs, verified transaction product ID, and transaction environment. Thought text is never logged.

### 7c. Taste-once routing

Not a new screen. Hardens rows 6–7 so a returning subscriber is not sent through the free chat:

- Launch holds chrome until the Keychain session restore and `StoreKitManager.prepare(hasAccountSession:)` finish. Active entitlements skip taste and open Home. Entitlement is `Product.SubscriptionInfo.Status` (subscribed / grace; billing retry after grace does not unlock), an unexpired verified `currentEntitlements` transaction, or a just-completed verified purchase — which unlocks immediately and is not overwritten if that refresh is still empty. `Transaction.latest(for:)` is ended-subscription detection only and never opens Home, so Restore on an expired subscription offers Renew instead of Home.
- Taste overlay hides Close and Start again and blocks canvas dismiss and recook. The server stamps the taste on its first ready result. Save raises the celebration frost before compose dismisses so the Home feed never flashes.
- Taste: when an ended subscription is found, the overlay shows **We found your previous subscription** and **Renew membership**, which opens the normal two-plan paywall. Otherwise restore lives in the paywall and Settings → Subscription. The probe runs at the end of `prepare()` and again when the paywall appears, and only records ended history when no Annual or Monthly is live. Restore remains available and uses `AppStore.sync()` for receipts not on this phone; the probe never syncs or raises a password sheet.
- Settings **Log out** is a local session: back to Login, ignore StoreKit until the next Apple sign-in, paywall Subscribe, or Restore. It does not cancel Apple.
- Taste is decided by server `tasteCompletedAt` only (row 8). No Keychain device fingerprint.

### 7d. Frost handoffs

Not a new screen. Taste, paywall, purchase, and restore share one AppRoot covering frost. Checkout uses an ultra-thin glass overlay above the still-visible paywall. `Root/AppGate.swift` resolves one destination (launching, login, taste, paywall, home) from a single snapshot of session restored, StoreKit ready, signed in, entitled, server taste, and taste Renew; AppRoot renders only from it, and the first frame of a Home destination is always covered. A successful entitlement structurally removes Taste/paywall under the cover, waits for the StoreKit operation and first Home result, then runs one frost-to-Home crossfade. Failed checks remove the checkout glass and leave an actionable paywall/taste state.

A cold launch paints the system launch screen and a SwiftUI splash the same dark paper. The unified Angles mark smoothly floats in from 92% to 100% scale in a warm ambient glow, then shimmers and scales while session, StoreKit, and Home resume; then executes an anticipation dip and an explosive 36x aperture punch forward as the dark background dissolves into the resolved screen. The cover never waits more than 1.5s on live data: last For you is on disk, and a newer mix is parked behind See latest. Later returns to Home keep the frost crossfade.

### 7e. Membership paywall

Not a new screen. Folds the post-taste celebration and checkout into one `PaywallView`. First save plays the Lottie, then the four-angle paper and purchase module arrive — there is no intermediate plans step. Yearly and Monthly are always full selectable rows; price and billing cadence come from StoreKit.

### 7f. Taste header + membership

Not a new screen. Taste restore copy shares the 40pt header row with the model button. Taste never shows Close; Save is the normal way forward. When Apple reports ended membership, Taste offers **Renew membership** and opens the same full Yearly/Monthly paywall without marking the taste complete. The most recently ended App Store-backed SKU is preselected: that row says **Renew membership**; choosing the other says **Switch to Yearly/Monthly**. Both call StoreKit `Product.purchase`; `Transaction.latest` supplies only this UI hint and never unlocks.

### 7g. Paywall positive capture

Not a new screen. Polish on 7f. Earlier revisions scattered furniture (value lines, library deck, legal) onto the paper and forced a scroll. Current shape is one locked screen:

- **No scroll.** Paper sells the product as a 2x2 of style tiles (wash, glyph, name, one-line benefit) under **"One thought. Four ways out."** plus one miss line. No membership card.
- **Purchase module.** Commerce only, spread: 44pt morphing price, both plan rows (64pt), ink CTA. Spacing uses leftover sheet height.
- **(i) sheet.** Keep cooking, Home, Restore, Apple legal. Opens on the large detent so membership legal is on screen.
- **Motion.** Celebration fades while the membership group rises 12pt as one unit; Reduce Motion unchanged. Checkout text rotates with stable opacity content transitions and only describes Apple checking/confirmation, never promises an unlock.

### 7h. Sandbox-only checkout

Not a new screen. Debug on device talks only to App Store sandbox — no `.storekit` file, no extra Sandbox scheme. Ended-subscription detection is group-wide (expired Annual does not win over live Monthly). Leftover Xcode StoreKit Testing receipts (`.xcode`) never unlock Home or report Subscribed; only App Store sandbox or production does. Home does not fetch from a cached unlock: its first task waits for `entitlementsReady && hasUnlockedFullApp`; Profile waits until its tab is selected. Intermediate transient retries stay in Loading and only the final failure exposes Retry.

**Checkout race regression:** `holdCheckoutUntilHome()` is armed before purchase/restore can change entitlement. A transaction update may arrive while that async call is suspended, so no continuation may arm the hold again. StoreKit owns `isPurchasing`/`isRestoring` until their `defer` runs; AppRoot can release only the visual confirmation hold. `AppRoot.applyGate()` moves an Apple-backed unlock through hidden → waiting for checkout → waiting for the first Home result → one animated visible state. The full native TabView pre-renders behind an opaque curtain so cards, bottom gradient, and tab bar arrive as one frame. Home never animates underneath checkout glass, and Taste Save never runs a second close transaction. Cancel, pending, no-active-subscription, and verification failure release the glass with clear feedback.

**Logout race regression:** Apple status/history calls already in flight when Log out is tapped must re-check `hasSignedOutSession` after every await. They may finish and clean up transactions, but only an explicit purchase, Restore, or Apple account sign-in can sign the local session back in; passive refresh/probe work cannot leave Home visible while Settings reports Inactive. Logout clears the session in the same synchronous step as StoreKit, so no frame reads signed in + locked + untasted.

**Entitlement hardening:** `Transaction.latest` is never `.active`, even when unexpired; only live status or `currentEntitlements` unlock, and Restore/probe unlock only through the same refresh. Status is read once per subscription group. Upgraded-away receipts are skipped. A fresh purchase names its plan in Settings immediately. An expiry watchdog refreshes shortly after `activeExpiresAt`, so a lapse while Home is open lands on the paywall (or taste) without backgrounding; foreground still refreshes. The Home arrival is bounded at 10s, after which Home shows its own loading/Retry.

**Sandbox re-purchase (Joe’s iPhone, App Store sandbox, no `.storekit`):**

1. Cancel: Profile → Settings → Subscription → **Cancel** (Apple's manage sheet), or iOS Settings → **Developer → Sandbox Apple Account → Manage** (older iOS: **App Store → Sandbox Account → Manage**). Renewal Rate lives there too; **Clear Purchase History** resets to a never-subscribed tester (no Renew hint).
2. Wait for the period to end (Monthly ≈5 min, Yearly ≈1 h at the default rate). Foreground the app: Settings → Subscription reads Inactive and Home becomes the paywall.
3. Apple login with `tasteCompletedAt` set → paywall with the prior plan as **Renew membership**, the other as **Switch**. With the Angles account deleted → taste (with **We found your previous subscription**) → Save privately → celebration → paywall.
4. Purchase: Apple's sandbox sheet → checkout glass → frost → Loading Home → Home; feed loads with the bearer; Settings shows Yearly/Monthly.
5. Live sub + Apple login → Home, no paywall/taste frame. Log out from Home → Login only. Restore on a live sub → Home; on an expired sub → Renew/Switch stays up. Cancel the sheet, Ask to Buy pending, and an offline catalog (Retry) leave an actionable paywall. Killing the app mid-checkout recovers through `Transaction.unfinished` on relaunch.

DEBUG console: `[Angles Gate] old -> new` with every gate input and the StoreKit snapshot (product, expiry, environment, signed-out flag), plus `[Angles StoreKit]` transaction lines. No thought text.

### 7i. Paywall specimen marquee

Not a new screen. Polish on 7g. Replaces the 2×2 style-benefit tiles with a full-bleed tilted 3-row marquee of thought/reframe specimens (canned community copy, plus the saved taste card when present). Cards bleed under the status bar and behind the Yearly/Monthly sheet’s rounded corners. There is no headline or miss line. The (i) sits on the trailing edge of the purchase module. Celebration and StoreKit are unchanged. Reduce Motion shows a static clipped collage. Compact height and large Dynamic Type scroll the purchase module over the marquee.

### 7j. Launch resume

Not a new screen. The splash is a 0.85–1.5s branded loading cover: the mark shimmers and scales while session, StoreKit, and Home resume, then punches. Returning Home paints last For you from disk. A live first page that differs is parked behind a tappable See latest pill so hearts and follows are not yanked. Session restore commits the last body immediately and revalidates in the background. Ranked card mapping reads run in parallel and reuse the ranking follow set.

### 8. Auth

Sign in first, then one taste if this account still needs it.

- Launch is **Continue with Apple**. First tap creates the account; the next tap is log-in. Session token lives in Keychain and goes out as `Authorization: Bearer` on every API call.
- After a session: StoreKit subscribed → Home. `users.tasteCompletedAt` set → paywall. Empty taste flag and unpaid → one free taste, then the paywall if they still have no subscription.
- Taste Save writes the card as this user and stamps `tasteCompletedAt`. There is no anonymous stub user and no guest-card claim.
- Settings **Log out** returns to the login screen and does not cancel Apple. **Delete account** is Apple 5.1.1(v); Settings stays up with a progress row until the server confirms, then returns to Login.
- Sign-in is atomic: token → Keychain → `GET /profile/session` → StoreKit refresh for this account → publish the session. The first destination is already Home, taste, or paywall; Login keeps its spinner meanwhile.
- Log out clears session, Keychain, bearer, and StoreKit in one frame, then revokes the server session in the background with the captured token. A 401 ends only the session whose token it rejected, so a late 401 from an old token cannot sign out a new one.

### 12. Production credit metering

The server owns a 600-credit membership period and returns remaining/granted credits, reset time, warning level, and `creditCost`. Since 17 every cook and recook costs 1 credit whichever model the server routed it to; the earlier model-weighted tariff is retired. Every intentional refine turn and recook sends a fresh UUID `Idempotency-Key` and a fresh `Replay-Key`. There is no automatic client retry; if the user retries after an ambiguous transport failure, the client reuses that logical operation's pair so the retry cannot spend twice, and if the first attempt had finished, the server returns its sealed response instead of a 409. An explicit server failure or a new turn gets a new pair.

Low credit warnings appear once per period, the critical/empty state stays in the compose header, and each paid ready response quietly reports the credits used. Metering, rate-limit, taste, duplicate-operation, and subscription errors have specific recovery copy; an already-completed result is never automatically retried.

Settings → Subscription loads `GET /profile/usage` independently and shows remaining of granted credits, period reset date, a progress bar, and retryable load failure. There are no credit packs, push/email warnings, modal warnings, or separate usage screen.

### 14. Resonance feed ranking

Home stops being chronological. `FEED_RANKING=resonance` turns it on; unset or `chronological` is the default and behaves exactly as before, so a bad feed is one environment variable away from gone. The order lives in [`backend/src/lib/feedRanking.ts`](backend/src/lib/feedRanking.ts) — pure, unit-tested, and the only file to touch when tuning. The plain-language rulebook (cold open, each refresh outcome, follow vs discovery, what never appears) is [`docs/home-feed.md`](docs/home-feed.md); keep it in step with this section.

- **Score.** Seven weighted terms per card, all read as of the visit's `startedAt`: `freshness` (`exp(-ageHours/24)` at weight 2.0, a one-day scale: Home reads like a social feed, so a post from this morning beats one from last week unless hearts, follows, and the viewer's themes together make up the difference), `resonance` 0.8 (distinct other people who hearted it, log-damped, saturating at 10 so one card cannot own the feed; the viewer's own hearts never count), `affinity` 0.7 (closeness to the viewer's themes, the recognition term, and the reason their feed should not read like a stranger's; 0 on the viewer's own cards), `followed` 0.6, `secondChance` 0.25 (unhearted and 1–14 days old, fading to 30, so no author's post dies unseen), `jitter` 0.15 (a deterministic hash of card id and session seed), and on For you `partlyKept` −0.5 (the viewer hearted some but not all of its angles). Intensity is capped, never rewarded. There is no dwell-time signal and no `ORDER BY random()`.
- **Own cards.** The viewer's own public cards are on Home, scored like a stranger's (no own-theme affinity, no follow, no self-hearts), at most 1 per page (`SPREAD_LIMITS.own`, a limit no fallback breaks) on every shelf and on the arrivals path. Once only own cards remain, the ranked list ends instead of paging through them. The phone still places a post at the top of For you the moment it is published.
- **Follow mix.** On For you, when the viewer follows 3 or more authors with posts from the last 7 days (`FOLLOW_MIX`), each page reserves about 25% for them, paced by slot (`followed so far < floor(0.25 × (slot + 1))`), and caps them at 50%. Fewer active follows get only the `followed` term. Style tabs never use the floor.
- **Themes.** A viewer's themes are the top three life areas above a 15% share and the top five moods above 10%, learned from what they wrote (weight 1) and every angle they hearted on any tab, on other people's cards or their own favorites (weight 1.5; three angles of one card count once). Each signal decays with a 14-day half-life, floored at 10% so old taste fades without vanishing. `other` is never a theme. The themes carry a `confidence` of decayed signal weight over 5, capped at 1: one card is a hint (0.2), five are a profile. The affinity term grades each theme by its strength relative to the viewer's strongest, a life area is worth more than a mood, and the whole term is scaled by confidence.
- **Theme mix.** Every candidate is `core` (its life area is one of the viewer's themes), `adjacent` (a neighbouring life area from `CATEGORY_ADJACENCY`, a shared mood, or a mood next to their strongest in `EMOTION_ADJACENCY`), or `explore`. A page of 24 follows `THEME_MIX` (40 core, 35 adjacent, 25 explore) scaled by confidence: core and adjacent shrink and explore takes the slack, and below 0.2 confidence there is no quota at all, so a new viewer keeps the plain ranked order. Each bucket is capped at its share of the page rounded up (`bucketCaps`: 10/9/6 at full confidence), and within those caps the page reads in plain rank order, so the mix pushes a few newer cards of an over-full bucket down instead of interleaving old explore cards into the top slots; an empty bucket falls back to the next best card, so a page is never short. A thin bucket (a small explore pool) fills its share with the same few cards on every tab, which is data and not a bug. The buckets come from the viewer's general themes on every tab.
- **Exact paging.** The app mints nothing; the server owns the pointer because a ranked order cannot be derived from the cards. `GET /feed` answers `page.nextCursor`, an opaque base64url `seed|startedAt|offset`, and the candidate set is frozen at `startedAt` so offset paging can neither repeat nor skip a card. Every input is frozen with it: hearts (`favoritedAt <= startedAt`), follows (`follows.createdAt <= startedAt`), the viewer's themes, and the freshness clock, so a heart or follow made mid-visit cannot reorder later offsets. Candidates are the newest 1000 matching cards; add a sampled tail before the public catalog passes that. A chronological `before` keyset still works, so a client mid-scroll is never yanked into another order.
- **Arrival mark.** A ranked page also answers `page.arrivalsAfter`, the `createdAt|id` of the newest candidate at `startedAt` (`startedAt|` nil UUID when there is none). The phone asks for arrivals after that, not after the newest card on screen: a ranked page need not hold the newest posts, and the old screen mark announced lower-ranked existing posts as new. Chronological pages omit it.
- **Already kept stays out.** Hiding is by angle, frozen to the visit's `startedAt` so offset paging cannot shift. A heart is on one answer, not the card, so For you hides a card only once every angle it has is hearted; a partly kept card stays, lower (`partlyKept`), and opens on an angle the viewer has not hearted (server `openingStyle` and the phone's `ForYouCovers`). A style tab hides only that tab's own angle, so a thought kept in Stoic can still show its Humorous angle under Humorous. A heart made during a visit leaves the current order alone and applies on the next visit. Chronological Home (flag off) is unchanged.
- **Seed and audit.** `pnpm db:seed-realistic [--viewer=<email>]` reshapes the existing fixture posts without adding or duplicating any: dated over about 45 days and denser toward now (20 posts in the last 24h), a few authors posting far more than the rest, skewed themes and intensity, about 40 seeded readers with skewed hearts, and with `--viewer` a realistic week of the account's own hearts. It refuses seeded and dev accounts for `--viewer`. `pnpm db:feed-audit --viewer=<email> [--pages=3] [--seed=…] [--json]` reads the ranked feed as that account and prints For you pages 1–N and each tab's first page with the numbers the feed is meant to hold: author share and longest same-author run, own and followed cards, partly kept cards, share under 48h, repeats across pages, fake arrivals (by the old screen mark and by `arrivalsAfter`; the second must be 0), the newest other person's slot, tab overlap, the theme mix, and kept angles that came back (must be 0). It prints no thought text and ships in the production image: `railway ssh -s api -e production "node dist/scripts/feedAudit.js --viewer=<email>"` (read-only).
- **Arrivals.** `GET /feed?after=<createdAt|id>` returns only cards strictly newer than that cursor, newest first, and stays chronological even under ranking — otherwise a new post could rank out of sight. Under ranking it applies the visit's visibility rules too: fully kept cards (or the tab's own kept angle) are dropped and at most 1 own card comes back, and it reads past the limit so hidden cards cannot make a full head look short. This is the head half of 9r's pull-to-refresh; the tail half carries the ranked cursor.
- **Spread.** Each page of 24 is greedily re-picked: at most 2 cards per author (own cards 1), no two from one author back to back when another author is available, 6 at intensity 5, and never 3 in a row sharing a life area, dominant mood, or cover angle. A card on the viewer's own theme may run 3 in a row by life area or mood (`SPREAD_LIMITS.coreRun`), so someone mostly in Work is not chopped up; the cover-angle run stays 2. The author and intensity caps are real limits; a run is reading rhythm, so breaking a run beats breaking a cap. When every remaining card breaks a cap (a community of two or three people), the pick is the card whose author has the fewest cards on the page, ties to rank, never plain rank order, so a small community alternates instead of walling its most active author. The whole ranked list is spread one window at a time so the global order stays stable across offsets.
- **Author-visible hearts.** `StoredReframeResult.heartCount` is per style and present only on the author's own public cards, omitted at zero: a `0` on a post about your worst day is worse than no number. Nobody sees anyone else's counts, there are no follower counts and no streaks — a public tally would change what people are willing to post. Counts come from a bounded aggregate over `saved_angles` (`saved_angles_card_idx`, `0015_sharp_puff_adder.sql`) rather than a denormalized counter, so the block and report paths that delete saves stay correct for free.
- **Opening angle.** Someone else's card can open on the angle the viewer keeps hearting, on a stable per-card coin flip (`PREFERRED_COVER_SHARE`). A lean, not a takeover: For you is meant to show mixed covers. Your own cards keep the cover you saved them with. A style shelf opens on the style you asked for; it does not use this coin flip.
- **No repeated angle on For you.** The server's spread keeps a cover run to two and the coin flip can still stack the favourite angle, so the phone has the last word on faces: `ForYouCovers.swift` walks each page entering For you and, when a card would open on the same angle as the card above (or a fixed card below), opens it on another angle it has. An angle the viewer hearted is never the face while the card has an unhearted one, even at the cost of a repeat. Order is untouched. Cards already on the shelf keep their face; your own cards keep their saved cover, and a card with one angle keeps it, so a repeat is possible only there. Style shelves stay one voice.

### 15. Home style shelves

For you stays the mixed ranked feed. Stoic, Optimistic, Humorous, and Tough love are separate shelves for the same viewer. A strong card can appear on more than one tab. Profile and author pages stay libraries that filter one list to "has this angle."

- **Style score.** A style request keeps the For you score, then blends the viewer's general theme affinity toward the taste implied by hearts on that style. Confidence reaches full weight at five matching hearts, so one heart cannot take over a shelf. Hearts on that exact angle add a capped style-resonance term. The saved cover is only a weak tie-break. Jitter is salted by style, so two shelves with the same scores do not share one order, and one shelf stays stable while you page it. With no `style`, the For you score is unchanged. `FEED_RANKING` still has to be `resonance`; unset stays chronological.
- **Primary tab.** Each card has one primary tab per viewer: the style it fits best among the angles it has. Fit is that tab's hearted taste relative to the viewer's general taste (hearts on any tab feed the general taste, so one tab cannot claim every card that matches the viewer) plus strangers' hearts on that angle. The author's cover is left out, since it is one style for every viewer and would skew a cold catalog. Ties, which is every card for a new viewer, break on a hash of viewer, card, and style with no session seed, so each tab's request reaches the same answer without coordinating and a new viewer gets a roughly even, personal split. On a style shelf a card whose primary is another style loses `STYLE_RANKING_WEIGHTS.offTab`: a penalty and not a filter, so a thin tab still fills from other tabs' cards once its own run out. The penalty is 2.75, more than the 2.5 an old card can score on the terms every tab shares, and it fades in with age (`OFF_TAB_FADE_HOURS`: none under 1h, full from 6h), so a brand-new post is on every tab like a normal feed and only older cards stay on their own tab. Two tabs share the last few hours of posts and any thin explore pool; the audit below prints both. A style request loads all four tabs' hearts, each angle's hearts, and each card's angles in single grouped queries.
- **One card, many orders.** Home keeps one record per loaded card and one session per tab: order, cursor, footer, visit history, and refresh. Heart, follow, delete, report, block, and privacy updates write the record once and every shelf that shows it follows. A new public post lands on For you and on any style shelf that has already loaded and includes that angle.
- **Loading.** A style shelf fetches the first time you open it and keeps its page when you swipe away. The life-area and mood filter clears every shelf, then reloads the one you are on. Pull-to-refresh and load-more touch only that shelf.

### 17. Reframe engine v2

The reframe pipeline, rebuilt around quality per style and a measured cost. Prompt copy is in `prompts.ts`, the pipeline in `cook.ts`, and every change is measured with `pnpm llm:eval`.

- **Server routing.** The request names no model and compose has no picker; the model cards page and the provider logos are gone, and every card carries the Angles mark. `modelsForStep` picks decision, writer, and moderation models from `LLM_*_MODEL`; every step defaults to Mistral Small and retries once on GPT-4.1 mini when that provider call fails. Every ready cook or recook costs 1 credit (`flat-v1`).
- **Robustness.** The batch output cap is computed from the length budget and the style count; JSON calls use strict schema mode; decision runs at temperature 0.2 and the writer at 0.8; each call gets up to 8 s and the whole cook fits a 13 s deadline inside the phone's timeout.
- **Decision.** `meta.distortions` names up to two thinking traps. Heavy thoughts adapt each style instead of skipping it. Passive suicidal phrasing is in the examples, and `safetyScreen.ts` overrides a model's `none` on explicit or passive self-harm wording. It has phrase lists for English and 15 other languages written with spaces, each with idiom exclusions, and on a ready turn it also reads the model's English copy, so a language with no list (Hindi, Japanese, Arabic) still gets the English one. The golden set has crisis thoughts in 8 languages besides English.
- **Writer.** Each style has a sharper voice, a technique menu, banned openers, and a line for heavy thoughts (`STYLE_VOICES`), plus shared gold examples (`GOLD_CARDS`). A hidden plan names one technique and insight per style, all different, before the answers. Timeframe, intensity, and the named traps shape the answer.
- **Lint.** `reframeLint.ts` checks length, questions, stray numbers, markdown, clichés, banned openers, and overlap between styles; a flagged style gets one targeted rewrite (call kind `rewrite`) that ships only if it has fewer problems.
- **Recook.** The phone echoes the signed cook and the answer it replaces. The server verifies the signature, skips the decision call, and asks for a different technique at temperature 0.95.
- **Their language.** When the thought was not in English, each answer comes back in English and in that language (`reframeOriginal`). Both are signed. The public card is English; only the author sees and toggles their own-language version. Stored in `card_reframes.reframe_original` (`0017_wise_aaron_stack.sql`).
- **Result.** The 80-thought golden set remains the quality gate for prompt and routing changes. No evaluation score is claimed for the GPT fallback; run `pnpm llm:eval` before making it primary.

### 20. Release gaps

The pre-submission audit (2 October 2026) found three promises the app made without a way to keep them.

- **Report review.** The Terms and the review notes promise review as soon as possible. A new report logs `card_reported` (ids and reason only) and emails `REPORT_ALERT_TO` through Resend when `RESEND_API_KEY`, `REPORT_ALERT_FROM`, and `REPORT_ALERT_TO` are set; the email carries no card text. Production starts without them but logs `report_alerts_disabled`. `pnpm reports` lists cards with open reports, oldest first, with the thought and answers. `hide <cardId>` makes it private, stamps `moderation_hidden_at`, and locks it until an operator uses `publish <cardId>`; publish clears that stamp and returns it to Home without discarding report history. `keep <cardId>` dismisses open reports so they stop counting toward the three-report threshold but does not republish; `delete <cardId>` removes it; `suspend <userId>` makes every card of that account private and stops it publishing while it keeps its private library and subscription; `unsuspend` reverses the account lock but does not republish cards. `card_reports` gains `reviewed_at` and `resolution` (`kept` or `hidden`); `users` gains `publishing_suspended_at` (`0018_report_review.sql`), and cards gain `moderation_hidden_at` with the legacy hidden-resolution backfill (`0021_moderation_hidden.sql`). A publish attempt from a suspended account, a stamped card, or a card with three open reports answers 400 `PUBLIC_CONTENT_NOT_ALLOWED` before moderation runs. Row 21 is the usual way to do that review. Production Postgres has no public URL, so the image still ships this script (`tsconfig.build.json` `files`) and the operator can run it inside the API container when the site is down: `railway ssh --service api --environment production node dist/scripts/reports.js [action] [id]`.
- **Apple revocation on delete.** Apple requires an app that uses Sign in with Apple to revoke the user's grant when they delete their account. Sign-in sends only the identity token, so Delete account first opens one Apple sheet for a fresh authorization code (`AppleReauthorization.swift`); closing it deletes nothing and shows no error. `DELETE /profile` takes an optional `{ appleAuthorizationCode }` (older builds send no body). The server trades the code at `appleid.apple.com/auth/token` before deleting anything, refuses with 400 if it belongs to a different Apple ID than the account's `accounts.account_id`, deletes the photo and the account, then calls `auth/revoke` (`lib/appleRevoke.ts`). An Apple outage on either call is logged (`apple_revoke_exchange_failed`, `apple_revoke_failed`) and never blocks the deletion. Production needs `APPLE_CLIENT_SECRET` (the Sign in with Apple client secret JWT, the same one Better Auth uses) for revocation to run.
- **Terms gate.** Acceptance used to live in the phone's `UserDefaults`, so a paid account on a new phone, or one that never sent, reached Home without accepting the Terms. `users.terms_accepted_at` (`0019_terms_acceptance.sql`) is now the record: `PUT /profile/terms` sets it once (a repeat keeps the first time) and `GET /profile/session` returns `termsAcceptedAt`. `AppGate` sends an entitled account without it to `.terms`, which shows the same "Before you start" sheet with Log out instead of Not now; Agree waits for the server and shows an error if it cannot reach it. The taste and paywall are not gated; the first Send there opens the sheet and records the same server field. The sheet gains a "Not therapy" row (not medical care or a crisis service). Settings gains Email support (`ANGLES_SUPPORT_EMAIL`, `info@bithavn.app`) when a separate support page is configured.
- **Taste welcome (build 10).** In production a new account has no credit period, so `/profile/usage` and every taste `/reframe` answered 0 credits and `empty`, the composer said "You're out of credits", and Send stayed disabled: the taste could not start. Local development never showed it because `ensurePeriod` gives every account a development period. `UsageSummary` and `ReframeUsage` gain `plan` (`taste` or `membership`); the taste reads as 1 credit while both taste timestamps are empty and 0 after (`tasteSummary` in `metering.ts`). The phone shows no balance for `plan: taste`; the taste composer opens on "Welcome to Angles", what happens next, and "Your first thought is free." Subscription shows "Credits start with your membership" for a taste account.
- **Reinstall starts at login.** iOS keeps Keychain items when the app is deleted, so a reinstall resumed the old session and skipped Continue with Apple. The first launch of an install (no `angles.installMarker` in UserDefaults) deletes the stored token (`KeychainStore.discardTokenFromEarlierInstall`). Builds 9 and earlier never wrote the marker, so updating to build 10 signs out once.
- **Display name is account data.** `PATCH /profile` stores the trimmed name on `users.name` with the initials. Profile and Settings fill from `GET /profile/session` after a reinstall, and a name that still exists only on this iPhone is uploaded once. An empty name does not clear the stored one. The profile photo there uses `avatarUrl` when the local JPEG is gone.
- **Checkout to Terms.** A purchase or restore keeps the checkout lock up until Home. An entitled account that never accepted the Terms stops at Before you start instead, so the root also releases the lock on `.terms` (`AnglesApp.swift`); before this, the spinner stayed over the Terms screen forever.
- **Sign-in survives a missed request.** The Apple sign-in POST and the session read retry a request that got no answer (`APIError.network`) three times over about six seconds before the login shows an error (`SessionStore.retryingNetworkFailures`). The first request after iOS grants local network access to a Debug build fails this way, and so does a dropped connection. HTTP answers are not retried.
- **Before you start keeps Agree visible.** Agree and continue (and its error line) is pinned under the scrolling consent text (`AIConsentSheet.agreeBar`), so a small screen or large text never hides it. Build 11.

### 21. Operator admin

Not an iOS screen. The operator reviews the report email at `https://useangles.app/admin` instead of an SSH session.

- **Auth.** A magic link from Resend, only for addresses in `ADMIN_OPERATOR_EMAILS`. The link's token sits in the URL hash, is single-use (`admin_login_challenges`, `0020_admin_login_challenges.sql`), and expires in 15 minutes. The session cookie is HttpOnly on `useangles.app` for 12 hours. Sign in with Apple is not used. Missing config answers 503 `ADMIN_DISABLED` and does not stop cooks.
- **API.** Railway `/admin` calls `reportReview.ts` for keep, hide, publish, delete, suspend, and unsuspend. Hide stamps `cards.moderation_hidden_at` (`0021`). The author's private library says the post broke the rules, and they cannot publish it until an operator does. Publish clears that stamp, puts the card back on Home, and reviews any reports still open as `kept`, so three reports that made it private no longer lock it and the author can make it private and public again (a suspended account still cannot). The list omits thought text; the card detail includes it. Production also requires `ADMIN_PROXY_SECRET`, which only the site worker sends.
- **Site.** Static pages under `web/app/admin`. The browser calls same-origin `/api/admin`, and `web/worker.ts` proxies that to the Railway API. No browser CORS and no database credential in the browser. `pnpm reports` remains the backup.
- **Overview.** `/admin` opens on counts (open, already private, suspended authors, reviewed) and a tile per report reason. The list under that is the thought, not the card id. Search matches an id, an email, or words from the thought. Keep or Hide moves to the next report in that filtered queue. Make public confirms that the card returns to Home and the author can change it afterward, then reloads the same card.
- **Chrome.** The admin has its own neutral shell (`web/app/admin/admin.css`): dark sidebar with Open, Reviewed, and sign out, stat cards, reason tiles, a filter bar, queue rows with reason pills, and a two-column review with a sticky Keep/Hide/Make public/Delete bar. The marketing paper theme is untouched. A private card offers Make public.

### 22. Follow notifications

Someone followed you. The follow graph is unchanged: one-way, no counts, and their posts stay in the same Home mix.

- **Row.** `followUser` inserts `follow_notifications` in the same transaction only when the follow row is new (`0022_follow_notifications.sql`). If you already follow them, `followedBack` is true. An unread pair cannot stack (partial unique index); a later follow after you have read the last one inserts another. Unfollow leaves the row. A failed insert does not roll back the follow. A block deletes both directions. Account delete cascades.
- **List.** Profile's bell opens Follows. One row per person, their newest follow; older rows stay stored for read state. Each row shows their photo or initials, their **display name** when the account has one, otherwise their initials, otherwise **Someone**. Subtitle is "Followed you" or "Followed you back", with Follow back or Following. Following does not unfollow. Tapping the row opens their posts. The Profile tab shows the unread count. `GET /profile/notifications`.
- **Read.** One open of the bell reads it. `POST /profile/notifications/read` takes `{ throughId }` (the newest row on screen) and answers `{ read, unreadCount }`; the server compares `created_at` in SQL, because the column has microseconds and the wire stamp only milliseconds. Build 18's `{ before }` still works with a millisecond-truncated compare and 1 ms of slack. The view model owns the read, so closing the sheet or a dialog over it cannot cancel it, and a list that left before a read is discarded. The unread count leaves out blocked people, like the list.
- **Badges.** The tab badge and the app icon both show the server's unread count, and the icon is rewritten after every load and read.
- **Permission.** Banners are an iOS permission. Settings has no Follows switch: the row opens iOS's dialog if this install has never asked, and iOS Settings otherwise (the only place that can turn banners off). The only automatic ask is iOS's dialog once Home is on screen (splash gone), never during login, taste, paywall, Terms, a follow, the bell, Follow back, or a push. Whatever they answer, the app does not auto-ask again (`angles.pushOsPromptedThisInstall`, plus `angles.followPushPromptSeen`).
- **Tokens.** At session start and every foreground the app registers its token when iOS allows notifications, including a token already in memory so a same-token callback cannot skip the API. It asks the server to forget its stored token when iOS does not allow banners. Registering a token drops other tokens for that account and APNs environment. Push testing happens on TestFlight only: a Debug install from Xcode replaces the TestFlight app, talks to the LAN API, and has a sandbox token.
- **Push.** `users.notify_follows` (default true) stays on the session. The app does not expose an in-app off; iOS Settings is the control. A leftover false from the old switch is healed when this iPhone is allowed. The banner title uses the same label as the list: trimmed display name (`users.name`), else initials, else **Someone**. The body is "Followed you" or "Followed you back". Never thought text or a follower count. `GET /profile/notifications` includes `displayName` on the actor when set. The notification category is `follow` with **View profile** and **Follow back** (long-press or expanded notification on the lock screen; iOS does not put buttons on the collapsed banner). A plain tap or View profile opens their posts on the author page; it must not switch the Home tab (that pops the author stack). Follow back opens the bell and follows. With no session, the tap waits until after sign-in and Home is revealed. Logout deletes this device's token first. Missing `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, or `APNS_BUNDLE_ID` skips the push and does not fail the follow. A `410` or `BadDeviceToken` drops the token. Debug uses the sandbox push environment; TestFlight and Release use production (`api.push.apple.com`).
- **Push logs.** Startup logs `apns_config { configured, keyValid }`. A push that does not go out logs `follow_push_skipped` with `switch_off`, `blocked`, `no_token`, or `no_config`; a send logs `apns_result` with the status, Apple's `reason`, and the environment. No token, name, or initials is logged.

## Postponed (do not start)

Nothing queued. Do not invent extras.

## Out of scope (until listed)

- Extra reframe styles
- Client-side LLM keys
- Browser CORS
- Moving the API onto Cloudflare Workers

## Shipped log

- 2026-10-08 — Robustness pass. Home and Profile build a style's list the first time it is chosen instead of all six up front; author pages keep at most 16 loaded feeds; the tinted menu icons are cached; a failed avatar thumbnail shows initials instead of a full-size decode; the swipe-back is scoped to the author page and covers the left 40% of the screen on iOS 26+.
- 2026-10-08 — Six-style polish. The dev community fixture now carries four of the six styles per card (Tender and Values on about two thirds, a grave scene never Humorous or Tough love, the spotlight always one of the card's own angles), and `pnpm db:seed-community` removes only seeded users, so a real local account keeps its cards. Values is a compass (`safari.fill`). Style menu rows keep each style's colour. Home, Profile, and author pages no longer swipe sideways between styles (the menu is the only way), and the author page's edge swipe goes back again.
- 2026-10-08 — Six voices (24). Tender and Values join the catalog; each cook writes the four that fit best, ranked, and a solemn thought is Stoic, Optimistic, Tender, and Values. Only builds that send `Angles-Style-Set: 2` see the new styles; every route projects cards onto the original four for older builds, so build 30 decodes everything it gets. The writer prompt carries only the voices a cook writes, so cost per cook is flat. The style chip row is a native menu on Home, Profile, and author pages.
- 2026-10-08 — Solemn, backend only. A thought about real harm to people (a death, serious illness, sexual violence, a child hurt, abuse, war and attacks on civilians, genocide, persecution, self-hatred), theirs or strangers', never gets humorous or tough love. The decision's required `solemn` fails closed, `graveScreen.ts` forces it, a written joke that names the harm is dropped before signing, and a recook of either on a grave signed thought is refused at no charge. Works on every installed build. `pnpm db:grave-humor --dry-run` lists older public cards that still carry one.
- 2026-10-08 — Follow notifications ask only on Home. Sign-in, taste, and paywall no longer show iOS's dialog; the one automatic ask waits until Home is visible and splash is gone. Settings → Follows stays the manual path.
- 2026-10-08 — Launch resume (7j). Cold launch shimmers and pulses the mark for at most 1.5s, punches into last For you from disk, and parks a newer mix behind a tappable See latest pill so in-flight hearts are not yanked. Session restore uses the last body immediately; mapping queries on a ranked page run in parallel.
- 2026-10-06 — Build 30. Cold launch smooth float-in + aperture punch: the unified Angles mark smoothly floats in from 92% to 100% scale in an ambient glow, rests calmly while Home loads underneath, dips in anticipation, and punches 36x through the camera as the dark background dissolves into the resolved screen. Later returns to Home still use the frost crossfade.
- 2026-10-06 — Build 29. Cold launch petal assembly + aperture punch: the Angles mark petals start separated and spring together with a bounce and glow bloom, breathe upright while Home loads underneath, dip in anticipation, and punch 36x through the camera as the dark background dissolves into the resolved screen. Later returns to Home still use the frost crossfade.
- 2026-10-06 — Build 28. Cold launch is an X-style aperture punch splash: the system launch screen and the SwiftUI cover share the dark paper, the Angles mark breathes upright while Home loads underneath, dips in anticipation, and punches 36x through the camera as the dark background dissolves into the resolved screen. Later returns to Home still use the frost crossfade.
- 2026-10-06 — Build 26. Predictable Home feed (`docs/home-feed.md`). Your own posts are on For you scored like anyone else's, at most one per page. A small community alternates authors instead of filling page 1 with whoever posts most. Following 3 or more active people gives them about a quarter of each For you page, never more than half. Hearting one answer no longer hides the card: it shows a little lower and opens on an answer you have not hearted, and leaves For you only when every answer is hearted. Hearts, follows, and themes are frozen for the visit, so pages cannot shift. A pull asks for posts after the server's `page.arrivalsAfter`, so an older post further down is never announced as new; with nothing new it moves up the cards you have not reached before the next page. `feedAudit.ts` ships in the production image.
- 2026-10-06 — Build 25. Follows in Settings is no longer a switch. The row opens iOS's dialog or iOS Settings; that is the only way to turn banners off.
- 2026-10-06 — Build 24. The Follows switch is on only when this iPhone is allowed to show banners. A Don't Allow leaves the account flag on; the switch looks off and the row points at iOS Settings.
- 2026-10-06 — Build 23. After reinstall, Follows already on asks iOS for banners on the first signed-in session so the switch cannot sit on with no token. A lock-screen tap or View profile opens their posts instead of Home. Registering a device token drops stale tokens for that account and environment.
- 2026-10-05 — Build 17. Operator Make public also reviews the reports still open as kept, so a card three reports made private is unlocked for its author afterward (a suspended account stays blocked; the reporters still never see it). On Home, a For you pull reads which of your cards are public alongside the feed and applies the page, any card that went private, and the banner in one no-animation commit. A card remembered as private that comes back public returns once, in place, without a restart. The library no longer rewrites your public cards on Home (their For you cover stays), nor reassigns the library or the widget when nothing changed.
- 2026-10-05 — Operator can publish a hidden card again. Hide stamps the card; the author's private library says Angles hid it for breaking the rules, and Make public is gone until an operator publishes it. A pull-to-refresh drops that card from the author's Home, which had been keeping the copy from when they posted it.
- 2026-10-05 — Operator redesign. `/admin` has a dark-sidebar admin shell with stat cards, reason tiles, queue rows, and a two-column review with a sticky action bar. Same endpoints and review functions, new look only.
- 2026-10-05 — Operator overview. `/admin` opens on counts and a tile per report reason, then a filterable list whose title is the thought. Search finds a card or an email. Keep or Hide continues to the next report. The same report-review functions still hide, keep, delete, and suspend.
- 2026-10-05 — Operator admin. Allowlisted addresses sign in at `useangles.app/admin` with a one-time Resend link and review open reports there: keep, hide, delete, or suspend. The site proxies to Railway `/admin`, which uses the same report review functions as `pnpm reports`. The SSH script remains the backup. Report emails are still ids and a reason only.
- 2026-10-02 — The save ride has a dark-mode copy (`Go to school dark.lottie`, from `scripts/lottie-dark-variant.mjs`): light outlines and light grey tires on the dark paper, dark grey where the light file is white, the same orange. Light mode is unchanged.
- 2026-10-02 — Tooling, not a product row: `demo/make_video.sh` records a real cook on a Simulator and edits it into the 9:16 showcase video (`demo/README.md`). It uses test IDs on compose and the chips, `DemoLaunch` launch arguments that exist only in Debug Simulator builds, and the local-only `pnpm demo:session`.
- 2026-10-02 — For you never opens two cards in a row on the same angle when a card has another one. Order, ranking, and style shelves are unchanged.
- 2026-10-02 — Pull-to-refresh calls the server again. The refresh action reads a live callback instead of a Bool captured before Home is revealed, the fetch is detached so a shelf update cannot cancel it, a pull always clears its own refreshing flag, and the half of a pull that landed still applies.
- 2026-10-02 — Two-provider LLM routing. Mistral Small is the primary for decision, writer, and moderation; GPT-4.1 mini is the only one-hop fallback on provider failure. The server catalog, metering, production configuration, consent, and privacy copy no longer route to or name the removed providers.
- 2026-10-02 — Home's empty board is a card: the tab's icon, a title, one line of explanation, and an **Inspire me** button that opens compose. A filtered tab that matches nothing keeps the filter icon and no button. An author's empty page uses the same card without the button.
- 2026-10-02 — App Review readiness. Before an account's first send, a one-time sheet names Mistral and OpenAI, says what is sent, and takes the Terms (zero tolerance for abuse) with **Agree and continue**. The paywall's big price is now what Apple bills, and under Continue it always shows renewal terms, 600 credits a month, Restore purchases, Terms of Use, and Privacy Policy; its (i) sheet adds Log out and Delete account. A used-up taste opens the paywall instead of a dead end, and a receipt the server cannot verify answers 422 so it no longer signs the user out. After an account is deleted, its still-active purchase moves to the next account the same Apple ID signs in with; a purchase owned by a live account is still refused. The Terms now promise zero tolerance and a 24-hour report review and name Apple's EULA; the Privacy Policy now covers moderation, Home ordering, legal bases, transfers to the US, and Datatilsynet. The widget ships its own privacy manifest. Release builds call the Railway API.
- 2026-10-01 — Good news cooks. A clearly happy thought is ready on the first turn, with angles that keep the feeling instead of asking what they are stuck on; a glad-and-worried thought still cooks the worry and keeps the good fact. A "what are you stuck on" reply to a first turn that already names a situation is repaired into a cook. Stoic and optimistic are now always written, even when the model tries to skip them; other skips are unchanged.
- 2026-09-30 — Reframe engine v2. The server picks the model for each step with a one-hop provider fallback and every cook or recook costs 1 credit; the compose picker, model page, and provider logos are gone and cards carry the Angles mark. Each style has a sharper voice, a technique menu, and banned openers; the writer plans a distinct technique per style, a lint pass rewrites any flagged style once, and a recook reuses the signed cook with a different technique and no decision call. A thought in another language gets each answer in that language too, shown only to its author. Safety adds distortions to meta and a phrase screen for passive self-harm.
- 2026-09-30 — Pre-release hardening. An unknown safety label is read as `self_harm` on the server and the phone, so a crisis can never be reframed; crisis numbers come from `crisisResources.ts` by the phone's region (988 US/Canada, 112 Europe, a short table, a generic local-emergency line otherwise), and the model never writes one. Every cook sends a `Replay-Key` beside its `Idempotency-Key`; the server seals the finished response under it for an hour, so a retry after a lost response gets the same cook back without a second charge or a second taste. `billing_retry` after grace is locked on the server and phone, a lapsed-receipt sync no longer ends grace early, and a failed status read keeps an existing unlock over a lapsed receipt. Cook signatures (v3) bind the owner; one cook makes one card per account; `cards.user_id` cascades; account delete retries the photo and fails with 503 rather than orphaning it.
- 2026-09-30 — Feed ranking v3: recency first (one-day freshness at weight 2.0, off-tab penalty only for posts older than an hour and full from six), angles the viewer already kept stay out of All and the matching tab for the visit, the theme mix now caps each bucket instead of interleaving slots, and `pnpm db:seed-realistic` and `pnpm db:feed-audit` build and grade a realistic community. Backend only; no API or iOS change.
- 2026-09-30 — Feed ranking v2, backend only: themes learned from what the viewer writes and hearts on any tab (recency-weighted, confidence-gated, `other` ignored), a 40/35/25 core/adjacent/explore mix on every page, a soft run limit for the viewer's own theme, and a primary tab per card so the four style tabs mostly show different cards. No API or iOS change.
- 2026-09-29 — Home style shelves: each style tab is its own ranked page for that viewer, while All stays the mixed feed. Hearts on a style teach that shelf, hearts on that angle lift it, and one shared card record keeps hearts, follows, and removals in sync.
- 2026-09-28 — Resonance feed ranking behind `FEED_RANKING`: freshness on a four-day scale, hearts as relief, affinity with what the viewer writes about, a second chance for unfound posts, and seeded jitter for variety; offset paging over a candidate set frozen per session; `GET /feed?after=` for arrivals; a per-page spread that caps one author and a wall of crisis; heart counts only on your own public cards; and an opening angle that leans to the style you heart without flattening the mix.
- 2026-09-28 — Home pull-to-refresh rotates: one pull prepends real arrivals, otherwise swaps in the next batch this visit has not shown, and starts over once the catalog runs out. `FeedRefreshPlan.swift` is pure and unit-tested; the banner names which of the five outcomes happened.
- 2026-09-25 — Final iOS audit fixes: StoreKit work is account-generation scoped; card writes and block loads reject stale completions; ambiguous reframe retries reuse their operation UUID; low-credit warnings are account-period scoped; subscription dates use neutral active-until copy and failed server sync has an explicit retry.
- 2026-09-25 — Backend release hardening: packaged runtime migrations before schema checks, strict production configuration assertions, production seed refusal, non-root Docker health checks, and Postgres-backed backend CI.
- 2026-09-25 — Production credit metering UI: authoritative model costs/availability and automatic visible fallback, per-period low/critical/empty warnings, per-cook usage feedback, idempotent refine headers, structured metering errors, and Subscription credit balance/reset.
- 2026-09-25 — StoreKit-to-backend entitlement: account-token purchases, verified transaction sync, idempotent App Store Server Notifications V2, one-time legacy claims, server diagnostics, and optional post-taste cooking enforcement.
- 2026-09-25 — Production legal/privacy hardening: source terms and privacy policy, no-tracking privacy manifest, explicit export declaration, Release-safe plist split, centralized legal/support destinations, and version 1.0.0 (8).
- 2026-09-25 — Production community safety: report with a reason, confirmed user blocking, synchronized local removal and rollback, blocked-people management in Settings, and clear public-moderation save/publish errors.
- 2026-09-25 — One pure `AppGate` destination: logout goes straight to Login with no taste/paywall frame; Apple login publishes the session only after StoreKit answers, so subscribers land on Home and tasted users on the paywall directly; server `tasteCompletedAt` is the only taste flag; `Transaction.latest` can no longer unlock; Settings names the freshly bought plan; an expiry watchdog and a 10s arrival cap keep Home from outliving the subscription or spinning forever; delete account waits for the server; sandbox re-purchase recipe under 7h.
- 2026-09-25 — Native Apple sign-in no longer 403s on a leftover session cookie without a browser Origin.
- 2026-09-25 — Home waits for a signed-in session before fetching the feed, so Apple login does not stall on Loading Home.
- 2026-09-25 — Login cards start fully off-screen; dark blooms match the first dissipated look, light a notch stronger.
- 2026-09-25 — Login cards fall from the top, spring onto the dock, then float in the pile.
- 2026-09-25 — Login sits a real Home card deck on the dock; dark blooms are a whisper.
- 2026-09-25 — Login marquee tilts through the four angles; light blooms stay quiet; dark blooms unchanged.
- 2026-09-25 — Login breathes with compositor animation, stains light paper with the four style hues, and says Reframe your mind / Four angles on the same situation.
- 2026-09-25 — Login is Apple-only: four-angle paper, specimen fan, native Continue with Apple. Google OAuth is gone.
- 2026-09-25 — Sign in first (Continue with Apple), then one taste if `tasteCompletedAt` is empty; tasted unpaid users see the paywall; subscribers go Home. Session in Keychain, `Authorization` on API calls, Settings log out and delete account.
- 2026-09-25 — Paywall’s two main marquee rows always show Stoic, Optimistic, Humorous, and Tough Love together.
- 2026-09-25 — Paywall marquee uses four rows so the collage fills from the top fade down behind the sheet.
- 2026-09-25 — Paywall marquee lifts a third card row into the top fade.
- 2026-09-25 — Paywall marquee runs behind the purchase sheet so rounded corners sit on cards, not a hard paper cut.
- 2026-09-25 — Paywall (i) sits on the trailing edge of the purchase module; marquee has no headline and matching top/bottom fades.
- 2026-09-25 — Paywall marquee has no headline; top and bottom paper fades match so cards dissolve softly into checkout.
- 2026-09-25 — Paywall marquee bleeds under the headline and fades into checkout; specimen tiles are larger and the miss line is gone.
- 2026-09-25 — Paywall paper is a tilted 3-row marquee of specimen cards; Yearly/Monthly checkout, headline, and (i) sheet are unchanged.
- 2026-09-24 — The model page globe opens the same privacy menu as Home; Make private removes the card with one smooth list transaction.
- 2026-09-24 — Owner globes open the same privacy menu on both Profile card layouts.
- 2026-09-24 — Profile privacy actions now apply directly without a second confirmation dialog.
- 2026-09-24 — Tapping the globe on the author’s own Home post opens the native card-action menu; Make private removes it with one smooth list transaction.
- 2026-09-24 — Narrow-layout hardening: shared pager tabs choose a stable 36pt or 30pt density from available width, card style rows gain a final icon-only fallback, compose/proposal chrome can grow or reflow, Profile/Following labels stay bounded, and paywall plan/legal content reflows while compact-height or large-type membership content scrolls.
- 2026-09-24 — Home, public author, and model pages now instantiate one `HomeFeedPager` for horizontal paging, chip scrub, wash, tab pages, refresh, footer, and bottom fade; trailing author/model identity overlays no longer compress the wide Humorous and Tough Love chips, model chrome is logo-only, and back is chevron-only.
- 2026-09-23 — Audit fixes, server: `POST /cards` only stores a cook `/reframe` signed (HMAC, `COOK_SIGNING_KEY`) and rejects any safety flag; a hearted card leaves the viewer's library once its author makes it private, and can still be removed from the board; feed, author, and library pages share one index-seekable `createdAt|id` cursor on millisecond timestamps; per-page save lookups.
- 2026-09-23 — Audit fixes, iOS: pull-to-refresh keeps the page cursor, so a failed refresh can still load more; publishing under a filter refetches the unfiltered page; thin style tabs keep paging; the library pages past 200; a card that went away says so; Make public asks first and public cards show a globe to their author; recook failures and Following-sheet unfollow failures show; the name saves on blur; leaving waits for a save; Log out clears loaded cards; author photos are cached and downsampled; the author page's edge swipe no longer disables the root's pop gate; Release has no API host until one exists.
- 2026-09-23 — Following sheet search filters initials with the system search field.
- 2026-09-23 — Profile's people icon, beside Settings, opens who you follow; the row's minus icon unfollows them.
- 2026-09-23 — Follow badge tap scales up, ticks, and fills from paper to ink as the plus becomes a checkmark.
- 2026-09-23 — Following: a bordered badge on other people's avatars follows them; their public posts stay in the same Home mix.
- 2026-09-23 — Public author profile: a card avatar opens that person's published posts; the private Profile tab stays the library.
- 2026-09-23 — Profile photos upload to the private Railway bucket and every card shows that photo or the author's initials.
- 2026-09-23 — Chat glow follows the selected model color; accent picker is out of Settings; Settings edits a local name/photo and the subscription sheet shows the live plan with Restore and Apple change/cancel.
- 2026-09-23 — The save cover slides off the new card with a premium traveling border spark and deepened ambient shadow (currently previewed on Home open and tab return); compose lines stay at the top.
- 2026-09-23 — A public post now appears on the author’s Home, and Save lands on that card.
- 2026-09-23 — Profile style tabs now use the Home tall card.
- 2026-09-15 — Native Home pull-to-refresh: SwiftUI's system refresh interaction starts below the fixed style tabs and refreshes the shared feed without blanking cards.
- 2026-09-15 — Profile dropped the shared maximum-height envelope; independent lazy tab lists remove Stoic’s paging hitch and shorter-tab trailing space, with a fixed compact header.
- 2026-09-15 — Profile destination Y now applies synchronously to mounted native scroll views, eliminating the delayed expanded/collapsed jump after a tab lands.
- 2026-09-15 — Profile now synchronizes real per-tab vertical offsets behind fixed spacers; collapsed-tab handoffs expand smoothly without overscroll fighting.
- 2026-09-15 — Profile ignores pull-down rebound as an upward gesture and delays header expansion until deep cards return to the collapse boundary.
- 2026-09-15 — Profile’s midpoint hitch is gone: horizontal drag has no `scrollPosition` binding mutation, and tab data/header activation waits for the physical page endpoint.
- 2026-09-15 — Profile scroll coordination removes inset feedback and settle fighting; collapse survives tab changes; one quiet glass plane and adaptive Favorites restore contrast.
- 2026-09-15 — Profile paging now tracks the finger 1:1: one frosted header blends adjacent tints, both chips morph continuously, and Favorites uses white glass.
- 2026-09-15 — Profile chrome is an opaque -45° style wash; Favorites is the first expanding tab; card lists page horizontally like Instagram.
- 2026-09-15 — Profile is identity plus five pinned tabs (four styles and Favorites); session label until Auth; Settings gear on Profile; favorites strip and style popover removed.
- 2026-09-14 — Ended membership uses the normal two-plan StoreKit paywall: prior SKU preselected with Renew membership, alternate SKU labeled Switch; Taste no longer opens Manage Subscriptions.
- 2026-09-14 — Checkout, first Home result, and frost removal are one serialized reveal; operation flags stay owned by StoreKit and Home cannot bleed under checkout glass.
- 2026-09-14 — Home and the native bottom bar now pre-render behind an opaque reveal curtain; Log out also rejects entitlement/history results that complete after the local session was cleared.
- 2026-09-14 — Intermediate Home/Profile retries stay in Loading, Profile defers its 200-card load until selected, and rotating checkout text no longer promises an unlock.
- 2026-09-14 — Paid handoff crossfades Home in while the frost and checkout glass fade away; the gate remains non-interactive until Home is the destination.
- 2026-09-14 — The first unlocked Home/Profile load retries transient local-network startup failures automatically; successful payment no longer lands on a one-shot Retry state.
- 2026-09-14 — Checkout is armed before StoreKit can unlock, never re-armed after Home, and always ends at Home or visible failure; both fresh and already-entitled Continue use the same gate.
- 2026-09-14 — Home/Profile wait for an Apple-confirmed, ready StoreKit unlock before fetching, so the launch cache cannot leave a stale Retry after paywall.
- 2026-09-14 — Sandbox-only checkout: deleted `Angles.storekit` and the extra Sandbox scheme; ended-sub looks at the whole group; checkout overlay holds until Home and rotates copy; (i) opens large.
- 2026-09-14 — Paywall light wash pulled to a midpoint; Confirm with Apple sits under the CTA; (i) sheet is titled rows with icons, restore, and membership legal.
- 2026-09-14 — Paywall light mode: stronger style washes, style-ink tile edges, deeper canvas and sheet shadow so surfaces separate like dark.
- 2026-09-14 — Paywall paper is a 2x2 of style tiles (why four angles exist); purchase module is spread commerce; (i) holds library/Home/legal.
- 2026-09-14 — Paywall purchase module sells the miss and three opportunities; slogans off the paper; (i) is legal/restore only.
- 2026-09-14 — Paywall is one unscrollable screen: compact first-save card, one headline, purchase module; (i) sheet holds value/legal/restore. Guest library no longer leaks onto the paywall.
- 2026-09-14 — Paywall sells ownership and opportunity: library deck hero behind the lock, three value lines (four angles, private library, others' feed), both plan rows in an elevated module.
- 2026-09-14 — Paywall hierarchy rebuild: paper content over an elevated purchase module, both plan rows always visible, morphing price hero, concrete three-state copy.
- 2026-09-14 — Paywall positive capture: full-height membership composition, kept-card hero or style motif, price type in every state, winback primary Renew membership.
- 2026-09-14 — Taste restore aligns with the model button; Close is gone on taste; paywall hero is the saved card with type-led yearly price, or Renew-only when the subscription ended.
- 2026-09-14 — Membership paywall: celebration, three benefit rows, and annual-first checkout share one screen; monthly is a quiet row; no Continue-to-plans.
- 2026-09-14 — Decision no longer ships "didn't catch a thought" continues on a named situation; family irritation and broken English cook, and a continue must name the missing fact.
- 2026-09-14 — Only Apple’s live status, `currentEntitlements`, or a fresh verified purchase unlock Home; a leftover `Transaction.latest` receipt no longer sends Restore to Home or reports Subscribed in Settings.
- 2026-09-14 — Home feed is hidden until the gate is Home; late StoreKit unlocks cannot yank paywall off without a user checkout.
- 2026-09-14 — Launch/logout routing uses one gate and never flashes Home; checkout glass sits over the paywall and dissolves only after Home is ready.
- 2026-09-14 — Paywall Restore always reports a result and checks local entitlements before `AppStore.sync()`.
- 2026-09-14 — Frost handoffs: one covering frost across taste/paywall/unlock; Home is revealed through glass; the half-second feed glimpse is gone.
- 2026-09-14 — Settings Log out starts over on this iPhone without canceling Apple; taste **Already have an account?** restores the session.
- 2026-09-14 — StoreKit unlocks from the verified purchase and subscription status; an empty `currentEntitlements` after `finish()` no longer keeps the paywall up.
- 2026-09-14 — Paywall Subscribe unlocks when StoreKit already has an active Angles entitlement instead of starting a new purchase.
- 2026-09-14 — Taste-once routing: wait for StoreKit entitlements before compose; skip taste when subscribed; stamp taste after a successful Save; non-dismissible onboarding overlay; taste restore link; paywall Restore purchases.
- 2026-09-14 — StoreKit sandbox foundation: verified-entitlement unlock, Retry on empty catalog, and DEBUG product/transaction logs.
- 2026-09-14 — Paywall: half-second saved-card glimpse; green Lottie success-to-benefits choreography with anonymous-community value and Continue CTA; StoreKit 2 annual/monthly hard gate, restore, entitlement persistence, and Settings status/reset.

- 2026-09-14 — Onboarding taste: native chat welcome hero ('Break the spiral' + tactile prompt chips) inside ComposeSheetView; auto-launches on first install; zero survey, zero auth; reset in Settings.
- 2026-09-11 — Home and Profile pull-to-refresh re-fetch feed and library without clearing on-screen cards.
- 2026-09-11 — Flat Home + stacked cards: one faceted vertical feed with composite paging and a mood GIN index; grouped Home removed; Home/library/compose show thought + answer while Favorite angles keep equal-height flips.
- 2026-09-11 — Shelf pagination no longer jitters at page arrival: field-level Observation, capped header-only scroll state, exact-cursor append paging with early prefetch and stable footer; chips animate only on tap and hearts bounce.
- 2026-09-11 — Full-width cards: one per row, height 228, selected style is a labeled pill, 16pt grid gap, landscape strips (340×228); LLM length budgets unchanged.
- 2026-09-11 — Card chips replace the in-card pager, heart top-right, flip chevron bottom-right, card actions on long press; pins removed app, API, and schema (`0003_drop_pins.sql`); hearting no longer rebuilds the card; failed writes show a banner and small writes time out in 6s.
- 2026-09-11 — Home polish: lazy shelves and a grouped `GET /feed/home` (140 KB, not 500 KB), one collapsing header like Profile, three-band cards (middle flips and pages, chrome swipes the strip), domain/mood zipper, paged shelf screens, no cold refetch on pop.
- 2026-09-11 — Community Home: public-others feed (Recent, life-domain, mood), viewer-scoped pin/heart, seed via `pnpm db:seed-community` (docker compose up, migrate, seed).
- 2026-09-10 — Profile style filter keeps every card that has that angle and opens the carousel on it; All still mixes covers.
- 2026-09-10 — Cook latency polish: one batched style JSON after the decision; 10s cook budget; cycling cooking copy; icon-only Original; leave confirms while a cook or unsaved session is open.
- 2026-09-10 — Empty Profile hero opens compose; Original sits on card chrome; thought and reframe budgets match the two-column card.
- 2026-09-10 — Card persistence: local Postgres + Drizzle; Profile library loads from the API; Save writes the full cook; categories and tags are first-class.
- 2026-09-10 — Core LLM contract: every cook runs a structured decision call; `continue` keeps the composer; card-fit English thought, optional original, 1–4 styles, matching metadata.
- 2026-09-10 — Compose formerly had provider logos and an optional `model` on `POST /reframe`; both were later removed.
- 2026-09-10 — Real LLM: overlay cooks via `POST /reframe`; default Mistral Small 4; optional `styles` for recook.
- 2026-09-10 — Native glass tab bar; Profile header fade, stable filter chip, space under the header.
- 2026-09-10 — Tab shell: empty Home (Settings), Sparkle compose overlay, Profile library with spotlight-style filter.
- 2026-09-10 — Favorites strip caps at 6 with a spring insert; Favorites title opens a grid; home cards mix starting styles; four dots; overlay New answer at the bottom.
- 2026-09-10 — Answer-first flip (home + overlay); initials on the thought face; Start again; per-style New answer with mock variants.
- 2026-09-10 — Overlay mocks on-device; questions stay with a chosen row; one 4-style carousel; heart + long-press Delete.
- 2026-09-10 — Refine: statement + up to 3 follow-ups, then all 4 styles; Save CTA; Favorites row; dots under the card.
- 2026-09-09 — Home: chat composer sits on the keyboard again; home layer still ignores it so the FAB does not slide.
- 2026-09-09 — Home: FAB stays put when chat closes; card flip no longer hitches or double-taps haptics.
- 2026-09-09 — Home: shorter bottom fade so it stays around the FAB.
- 2026-09-09 — Home: FAB is near-black/near-white with a flipped sparkle; dark cards sit a notch deeper.
- 2026-09-09 — Home: Inspire me is a trailing frosted FAB with an accent-gradient sparkle.
- 2026-09-09 — Home: quieter Inspire me type; dark chat composer matches the keyboard.
- 2026-09-09 — Home: Inspire me pill is larger, with a contrasting sparkle circle inside.
- 2026-09-09 — Home: compact centered Inspire me pill replaces the full-width composer dock.
- 2026-09-09 — Home: AI answer wash is stronger in dark mode so the diagonal tint actually reads.
- 2026-09-09 — Home: date, dots, and ⋮ flip with the card; answer pill uses the sparkle icon.
- 2026-09-09 — Home: flipped card pill uses the sparkle answer icon instead of the style glyph.
- 2026-09-09 — Home: style icon+name share a pill; ⋮ opens Edit (reopen thread) or Delete.
- 2026-09-09 — Home: thinner style chip; stoic slate, optimistic gold, humorous orchid, tough love ember.
- 2026-09-09 — Home: quieter AI wash at the bottom; top icon and style badge share one 40pt line.
- 2026-09-09 — Home: AI card wash is a top-left to bottom-right fade, clear at the top and tinted at the bottom.
- 2026-09-09 — Home: AI card backs a touch more tinted, still a soft gradient.
- 2026-09-09 — Results: checkboxes on AI cards; floating Save chip above the composer; carousel dots sit on the card.
- 2026-09-09 — Results: checkmark publishes bookmarked replies to home; 2+ become a carousel with Bandaid-style dots. X discards.
- 2026-09-09 — Results: single style per send, circular bookmark-to-memory, avatars beside bubbles. Multi-style stacked cook skipped.
- 2026-09-09 — Home: shorter, denser status-bar fade; title and Settings scroll under it.
- 2026-09-09 — Home: dropped the sidebar and FAB; Settings lives in the header, dock is full width.
- 2026-09-09 — Settings: modal sheet from a thumb-reach drawer icon; profile avatar and subscription live inside Settings.
- 2026-09-09 — Settings: appearance (System/Light/Dark) and accent picker; charcoal neutrals so dark cards are no longer purple.
- 2026-09-09 — Compose (home): Bandaid-matched keyboard insets; overlay sibling layout, constant 8pt bottom pad, and focus-bound dismiss chevron.
- 2026-09-09 — Compose (home): fixed overlay composer to the same bottom inset as the home dock; no keyboard padding animation.
- 2026-09-09 — Compose (home): rest the overlay composer above the home indicator when the keyboard is down.
- 2026-09-09 — Results: sending another thought appends a new cook; previous overlay pairs stay.
- 2026-09-09 — Compose (home): restored 3D card flip on the feed; overlay freeze no longer zeros grid animation.
- 2026-09-09 — Results: avatar beside a compact style-wash card; next thought from the composer; dropped Copy/Again tiles.
- 2026-09-09 — Results: one-shot overlay cook with a style-wash result bubble, in-bubble Copy/Again, header style recook, and in-place error/retry.
- 2026-09-09 — Compose (home): fade overlay chrome with the frost, slightly faster on close so nothing lingers.
- 2026-09-09 — Compose (home): keep the home grid still while the frost overlay fades.
- 2026-09-09 — Compose (home): fixed composer to 8pt bottom padding so it no longer jumps with the keyboard.
- 2026-09-09 — Compose (home): Bandaid-matched composer (newline Return, Send on text, Optimistic default), smoother frost close, wider dock–FAB gap.
- 2026-09-09 — Compose (home): bell-shaped glow around the overlay composer in the selected model's brand color.
- 2026-09-09 — Compose (home): frosted overlay, inverted bubbles, cooking line, pill composer, and a header style popover.
- 2026-09-09 — Compose (home): removed Help drawer item; nudged flipped card washes closer to white.
- 2026-09-09 — Compose (home): circled drawer icons with new help/about glyphs, gradient FAB with glow, softer dock glow, and blur-crossfade title.
- 2026-09-09 — Compose (home): softened category card backs to tints, calmed card shadow for a continuous plane, and replaced boxed drawer icons with a quiet rail.
- 2026-09-09 — Compose (home): stripped glass sheen, colored glows, and double shadows; quiet white cards with one soft shadow, calm dock and FAB.
- 2026-09-09 — Compose (home): quieted the canvas to a near-white lavender linear wash and removed the radial purple glows.
- 2026-09-09 — Compose (home): glassy lavender canvas, category-matched AI card backs, borderless premium icons, elevated sparkle dock, and a rotating title.
- 2026-09-09 — Compose (home): balanced the lavender canvas, added category-coded cards and a distinct answer face, and removed the drawer’s moving plane edge.
