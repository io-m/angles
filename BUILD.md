# Angles build tracker

Living document for **what to build, in what order**. Update this file in the same change as every new screen or feature.

Assume the user is already paid. **No onboarding, paywall, or auth until the core loop is done.**

## How to update

When you add or change a screen/feature:

1. Set its **Status** (`not started` → `in progress` → `done`).
2. Fill **Files** and a one-line **Shipped** note.
3. Move **Next up** to the following item.
4. If you need a screen that is not listed, add it here *before* building it.

Do not skip ahead. Do not invent extras (social, extra styles).

Status values: `not started` · `in progress` · `done` · `skipped`

## Next up

**8. Auth** — Sign in with Apple / Better Auth, guest-card claim after subscription, `tasteCompletedAt` on the user, and Settings session Sign in/out that does not hide a StoreKit entitlement.

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
| 4c | Real LLM | feature | done | `llmClient.ts`; `HomeViewModel.swift`; `AppConfig.swift` | Overlay calls `POST /reframe`. Default Mistral Small 4; Gemini 3.8 Flash and DeepSeek via `LLM_MODEL`. |
| 4d | Model picker | feature | done | `ComposeSheetView.swift`; `LlmModel.swift`; `llmClient.ts` | Compose header picks Mistral / Gemini / DeepSeek; `POST /reframe` sends `model`. |
| 4e | Core LLM contract | feature | done | `decision.ts`; `prompts.ts`; `reframe.ts`; `ReframeModels.swift`; `HomeViewModel.swift` | Every cook runs a JSON decision call; `continue` keeps the composer; card-fit English thought plus matching metadata. |
| 5 | Card persistence | feature | done | `docker-compose.yml`; `backend/src/db/*`; `CardsService.swift`; `HomeViewModel.swift` | Profile library reads Postgres; Save writes the full cook; categories and tags are first-class. |
| 5b | Favorite angles | feature | done | `schema.ts`; `cards.ts`; `ReframeCardView.swift`; `ProfileView.swift`; `FavoritesView.swift`; `ProfileSubsetView.swift` | Per-style hearts; Profile strip (max 6) plus full Favorite angles grid; liked styles only in that carousel. |
| 5c | Pinned posts | feature | removed | `schema.ts`; `0003_drop_pins.sql`; `ProfileView.swift`; `FavoritesView.swift`; `HomeViewModel.swift` | Removed in 9c, schema included. Favorites are the only save; flip reads the thought. |
| 5d | Owner card menu | feature | done | `ReframeCardView.swift`; `cards.ts` | Long press opens the card menu (9c moved it off the ⋯ button): confirm delete, privacy flag, original-vs-English. |
| 5e | Thought type + card height | polish | done | `ReframeCardView.swift` | Thought is slightly smaller and heavier; height hugs max thought/reframe plus chrome. |
| 5f | List and in-card chrome | polish | done | `ReframeCardView.swift`; `HomeCardGrid.swift`; `ProfileView.swift` | Strip list-dots and tighter grid rows. In-card dots went away with the pager in 9c. |
| 6 | Onboarding taste | screen | done | `ComposeSheetView.swift`; `AnglesApp.swift`; `HomeViewModel.swift`; `SettingsView.swift` | Native chat welcome hero ('Break the spiral') in ComposeSheetView; zero survey, zero auth at launch; auto-presents on fresh install. A successful taste Save stamps install-local `hasCompletedOnboardingTaste`; Settings Log out replays first-run. |
| 7 | Paywall | screen | done | `Paywall/*.swift`; `Resources/celebration-checkmark.json`; `StoreKit/StoreKitManager.swift`; `AnglesApp.swift`; `HomeView.swift`; `SettingsView.swift` | Saved taste crossfades onto the Lottie celebration, then the four-angle paper and annual/monthly hard paywall. |
| 7b | StoreKit sandbox | feature | done | `StoreKitManager.swift`; `PaywallView.swift`; `project.yml` | Debug on device always uses App Store sandbox; verified entitlements unlock; empty catalog shows Retry; DEBUG product/transaction logs. |
| 7c | Taste-once routing | polish | done | `AnglesApp.swift`; `StoreKitManager.swift`; `ComposeSheetView.swift`; `PaywallView.swift`; `SettingsView.swift`; `HomeView.swift` | Launch waits for StoreKit entitlements; only live status, `currentEntitlements`, or a fresh verified purchase unlock Home; taste header link restores purchases; overlay is not dismissible until ready; paywall Restore purchases; Settings Log out is a local session and does not cancel Apple. |
| 7d | Frost handoffs | polish | done | `AnglesApp.swift`; `PaywallGlimpseView.swift`; `PaywallView.swift`; `StoreKitManager.swift` | One covering frost; checkout glass overlay over the paywall; a single applyGate destination so launch/logout never flash Home; an expired subscription stays on the paywall with Renew. |
| 7e | Membership paywall | polish | done | `PaywallView.swift`; `AnglesApp.swift` | Celebration, four-angle paper, 44pt price, and annual/monthly checkout share one screen; there is no intermediate plans step. |
| 7f | Taste header + membership | polish | done | `ComposeSheetView.swift`; `PaywallView.swift`; `StoreKitManager.swift`; `AnglesApp.swift` | Taste restore sits in the model-button row; ended membership opens the same two-plan paywall, preselects the prior plan, and purchases the selected SKU. |
| 7g | Paywall positive capture | polish | done | `PaywallView.swift`; `AnglesApp.swift` | Paper sells four angles as a 2x2 of style tiles; purchase module is spread commerce (44pt price, both plans, CTA); (i) holds library/Home, restore, legal. |
| 7h | Sandbox-only checkout | polish | done | `project.yml`; `StoreKitManager.swift`; `AnglesApp.swift`; `PaywallView.swift`; `HomeView.swift`; `ProfileView.swift`; `HomeViewModel.swift` | No local StoreKit file; prior-plan-aware renewal; neutral checkout copy; one serialized checkout/feed/frost handoff; first loads wait for entitlement readiness. |
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
| 9q | Home style tabs | polish | done | `HomeView.swift`; `HomeViewModel.swift`; `StyleTabPager.swift`; `ProfileView.swift`; `HeaderChrome.swift`; `CardsService.swift`; `feed.ts`; `db/feed.ts` | All-default tabs aligned with trailing filter; no Home Settings; one feed; tab-bar footer fade. |
| 9r | Native Home pull-to-refresh | polish | done | `HomeFeedPullRefresh.swift`; `HomeView.swift`; `HomeViewModel.swift` | SwiftUI's native refresh interaction starts below the fixed tabs while the shared feed refreshes in place. |
| 9s | Public author profile | screen | done | `AuthorProfileView.swift`; `HomeView.swift`; `StyleTabPager.swift`; `ReframeCardView.swift`; `HomeViewModel.swift`; `users.ts`; `feed.ts`; `ReframeModels.swift` | Avatar opens that author's public posts in Home's five-tab pager; your own avatar switches to Profile. |
| 9t | Following | feature | done | `follows.ts`; `schema.ts`; `0006_worthless_liz_osborn.sql`; `users.ts`; `mapCard.ts`; `feed.ts`; `ReframeCardView.swift`; `HomeViewModel.swift`; `AuthorProfileView.swift` | One-way follow badge on other people's avatars; their public posts stay in the same Home mix. |
| 9u | Following list | feature | done | `follows.ts`; `profile.ts`; `FollowingSheet.swift`; `ProfileView.swift`; `HomeViewModel.swift`; `ProfileService.swift` | A people icon beside Settings opens the people you follow; a row opens their posts, and the minus icon unfollows. |
| 9v | Model cards page | screen | done | `ModelProfileView.swift`; `HomeView.swift`; `StyleTabPager.swift`; `HomeViewModel.swift`; `models.ts`; `feed.ts`; `schema.ts`; `0008_public_model_created_idx.sql`; `ReframeModels.swift` | Tapping a model opens its public cards in Home's five-tab pager, with a logo-only header. |

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

Always all four styles. Style picker and per-style checkboxes are gone. Home cards store four slides; the carousel is the default face.

### 4. Hook up fetching

Not a new screen. `POST /reframe` is `{ text, followUps?, styles?, model? }` → `continue` or `ready` (was `clarify` until 4e). The overlay mocked on-device until 4c.

### 4b. Tabs + Profile shell

Three-target bar: Home (community feed, Settings gear), Sparkle (existing compose overlay, not a page), Profile (private library). Favorites strip stays unfiltered. Header picker keeps every card that **has** that style and opens the carousel on it. **All** still uses mixed `spotlightStyle` so the grid is not a stoic wall. Style is not a category; real taxonomy is `category` / tags / intensity. Home shelves use `category` (life-domain) and `emotions` (mood).

### 4c. Real LLM

Not a new screen. `generateReframe` calls a provider catalog (`mistral-small-latest` default, plus `gemini-3.8-flash`, `deepseek-flash`, `deepseek-v4-pro`). Overlay `startRefine` / recook use `ReframeService`. Follow-ups stayed the mock bank until 4e.

### 4d. Model picker

Compose overlay header: trailing 40pt logo button (always visible) opens a compact popover. Sends optional `model` on `POST /reframe`. Missing `model` still uses env `LLM_MODEL`. DeepSeek Pro stays catalog-only, not in the picker.

### 4e. Core LLM contract

Not a new screen. Every `POST /reframe` runs one structured decision call (`decision.ts` + `DECISION_PROMPT`), then one batched JSON style call for the styles it chose (a recook is still a single `generateReframe`). The old mock gate (`refineDecision.ts` clarify bank, 24-word threshold) is gone.

- Response is `continue` (`message`, `options`, `safety`) or `ready` (`thought`, optional `thoughtOriginal`, 1–4 `results`, `meta`).
- `meta` carries the closed category, tags, intensity, timeframe, emotions, safety, input language, skipped styles, and an anonymous `matching` key. Save writes that cook to Postgres; a discarded overlay is never stored.
- Card copy is English and card-fit (thought 8–22 words / 140 chars, reframe 12–32 words / 190 chars). A non-English input also returns its own cleaned wording behind an Original toggle.
- The composer stays up for every turn that is not a finished cook, so a `continue` is just the next message in the chat. `followUps` caps at 6; from the third the decision is told to land it, safety aside.
- A recook of a style the decision skipped comes back as `continue` with that skip reason, not a bad joke.

### 5. Card persistence

Not a new screen. Local Postgres in Docker (host 5433) + Drizzle. Profile is the private library and reads from `GET /cards`. Save posts the kept cook to `POST /cards`; X still discards. Categories are an enum column; tags have their own table. `POST /reframe` still never writes. No SwiftData.

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

- **Tabs.** Five expanding chips: **All** (default, mixed `spotlightStyle`) plus the four styles. No Favorites. One `GET /feed` (life area / mood only); style tabs are in-memory like Profile — same cards, open on that angle. Filter sheet resets the shared feed.
- **Layout.** One overlay row: expanding tabs leading, filter trailing, same height and center as the filter icon, with a little extra space under the chips. No Home Settings gear (Profile keeps it). Quiet style-tinted paper-to-grey canvas, style-tinted glass header, tab-bar footer fade. `StyleTabPager.swift` shares pager state, chips, and wash with Profile. Each tab is its own vertical `ScrollView` + lazy `HomeCardGrid`.
- **API.** Optional `style` on `GET /feed` remains for later; Home tabs do not refetch it.

### 9r. Native Home pull-to-refresh

Not a new screen. Corrective polish on 9q.

- **Native motion.** Each tab uses SwiftUI `.refreshable`; there is no added drag recognizer, synthetic threshold, layout hold, or refresh-time scroll lock.
- **Indicator placement.** The vertical scroll viewport begins below the fixed Home chrome instead of behind the safe area. Its system spinner therefore emerges directly below the style tabs without UIKit positioning overrides.
- **Shared refresh.** The native async action awaits `HomeViewModel.refreshFeed()`. Existing cards stay visible and all tabs continue filtering the same in-memory feed.

### 9u. Following list

Not a new screen. The Profile bar has a people icon in the same round container as Settings, sitting just before the gear. It opens a large sheet, the same chrome as Settings.

- **List.** `GET /profile/following` is the people you follow, newest follow first. Each row is a 40pt photo or initials and those initials. There is no display name and no count. Empty copy says you aren't following anyone yet. The system search field under the title filters those initials; no matches uses the system search empty state.
- **Open.** A tap on the person closes the sheet and pushes their public posts.
- **Unfollow.** The trailing person-minus icon unfollows them and drops the row. If the write fails, the row comes back with the existing write banner.

### 9t. Following

Not a new screen. A one-way follow on someone else's avatar. Home stays the public newest-first mix; a later algorithm can read the graph. No Following tab, counts, or messages. The people you follow are a sheet on Profile (9u).

- **Badge.** A bordered plus on another person's avatar, bottom-trailing. Tap follows; it scales up, ticks, and fills from paper to ink as the plus becomes a checkmark. Tap again unfollows. The rest of the avatar still opens their posts. Your own avatars stay plain, including Profile, compose, and the ready card.
- **Graph.** `follows` is `(follower_id, followee_id)` with cascade deletes and a check against following yourself. `PUT /users/:id/follow` and `DELETE /users/:id/follow` are idempotent. Missing users are 404. `author.following` is on every card and on `GET /users/:id/cards`. Private posts stay off Home.
- **Writes.** The badge flips immediately on every card and the author header for that person, then rolls back with the existing write-failure banner if the request fails.

### 9s. Public author profile

Tapping someone else's card avatar pushes this page over Home or Profile, covering the tab bar. Your own avatar switches to the Profile tab. The compose avatar does not navigate. The private Profile tab stays the library.

- **Who.** Every card author includes `id`. Initials-only authors open the same way as authors with a photo. The header is a back button, the style tabs, and that avatar on the right (photo or initials). There is no display name.
- **Posts.** `GET /users/:id/cards` returns that person's public cards, newest first, with the same cursor as Home. Private cards stay off the page, including the author's own. An empty public list is still that person. Unknown ids are an error on the page.
- **Tabs.** All is the default mixed cover. A style tab keeps posts that have that angle and opens on it, from the one loaded list. No Favorites, no Life area or Mood sheet, no Settings.
- **Hearts and owner actions.** Same as Home, written through the existing card and feed endpoints. The author list, Home, and the library update in place. Opening this page does not refetch either.
- **Back.** Only the header chevron pops the page. Each pushed public destination hides the native back control, disabling the system edge-pop so horizontal drags belong exclusively to the style pager. The tab bar returns with the card that opened the page. A tap on this page for the author already showing does nothing.

### 9i. Profile identity + style tabs

Not a new screen. Profile is a private identity page, not a greeting plus two card lists.

- **Header.** Local profile photo plus the typed display name (falls back to initials, then a person glyph; empty still reads **On this iPhone**). `displayName` is a nil seam for Auth (row 8). No mock full name.
- **Tabs.** Five pinned icon tabs replace the style popover: Stoic, Optimistic, Humorous, Tough love, Favorite angles. Default is Stoic. There is no All tab. Style tabs show owned cards that have that angle and open on it; Favorites is the full liked-angle grid. Empty library still uses the Inspire me hero under the tabs.
- **Removed.** Favorite angles strip, `HomeCardStrip`, `FavoritesView`, `ProfileSubsetView`, and the header filter popover. Home has no Settings gear; Profile keeps the trailing gear.

### 9j. Profile wash, chips, paging

Not a new screen. Polish on 9i.

- **Chrome.** Opaque paper plus a stronger style wash, lit from -45° (top-leading to bottom-trailing). Favorites uses a quiet ink tint. Cards cannot show through the identity or tab row. Wash crossfades when the settled tab changes.
- **Tabs.** Favorites is first and the default. The selected tab is a labeled pill (glyph + name) like card chips; the rest stay icon circles. Spring only on selection change.
- **Paging.** Identity, tabs, and Settings stay put. Card lists page horizontally (`scrollTargetBehavior(.paging)`), not an inner TabView. Each page is its own vertical `ScrollView` + `HomeCardGrid`.

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
- Zero auth at launch: no email, no password, no login gate. Complies with Apple Guideline 2.1 (no reviewer demo credentials required) and 5.1.1(v).
- Native welcome hero in `ComposeSheetView`: "Break the spiral." with subtitle capturing the mental loop/overthinking problem. Starter prompt chips are not in the compose hero.
- Auto-presents the native compose sheet on first install after StoreKit entitlements are known. An active subscription skips taste.
- Sending a thought runs the cook with cycling progress lines, arriving at the ready card.
- The overlay cannot be dismissed during the taste. Only a successful Save stamps `hasCompletedOnboardingTaste = true` and crossfades onto the celebration frost, so killing the app on an unsaved result cannot skip to the paywall.
- Settings **Log out** starts over on this iPhone (taste again). It does not cancel Apple. Taste **Already have an account?** and paywall Restore purchases sign the session back in.

### 7. Paywall

The first saved taste keeps a covering frost and plays the ThinLine checkmark/confetti Lottie; the Home feed is not shown in between. It then reveals **“One thought. Four ways out.”**, the 2×2 angle tiles, and the annual/monthly purchase module on the same screen. Annual (`app.angles.ios.annual`) bills $39.99/year immediately; monthly (`app.angles.ios.monthly`) bills $4.99/month. There is no free trial. Verified purchases and restores persist the unlock cache, but Apple overwrites it before routing and Settings. Paywall restore is labeled Restore purchases. Taste shows a top **Already have an account?** link that runs the same restore path. Successful purchase or restore dissolves the covering frost to reveal Home.

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

- Launch holds chrome until `StoreKitManager.prepare()` finishes. Active entitlements skip taste, stamp `hasCompletedOnboardingTaste`, and open Home. Entitlement is `Product.SubscriptionInfo.Status` (subscribed / grace / billing retry), an unexpired verified `currentEntitlements` transaction, or a just-completed verified purchase — which unlocks immediately and is not overwritten if that refresh is still empty. `Transaction.latest(for:)` is ended-subscription detection only and never opens Home, so Restore on an expired subscription offers Renew instead of Home.
- Taste overlay hides Close and Start again, blocks canvas dismiss and recook, and stamps taste only after a successful Save. Save raises the celebration frost before compose dismisses so the Home feed never flashes.
- Taste: optional top-leading **Already have an account?** unless an ended subscription is found — then the overlay shows **We found your previous subscription** and **Renew membership**, which opens the normal two-plan paywall. The probe runs at the end of `prepare()` and again when the paywall appears, and only records ended history when no Annual or Monthly is live. Restore remains available and uses `AppStore.sync()` for receipts not on this phone; the probe never syncs or raises a password sheet.
- Settings **Log out** is a local session: start over on this iPhone, ignore StoreKit until the next taste restore, paywall Subscribe, or Restore. It does not cancel Apple. Sign in with Apple waits for row 8.
- One local flag (`hasCompletedOnboardingTaste`). The old `hasEnteredPaywallFlow` value is migrated once and removed. No Keychain device fingerprint. Auth / `tasteCompletedAt` wait for row 8.

### 7d. Frost handoffs

Not a new screen. Taste, paywall, purchase, and restore share one AppRoot covering frost. Checkout uses an ultra-thin glass overlay above the still-visible paywall. A single `applyGate()` picks Home, paywall, or taste only after StoreKit is ready. A successful entitlement structurally removes Taste/paywall under the cover, waits for the StoreKit operation and first Home result, then runs one frost-to-Home crossfade. Failed checks remove the checkout glass and leave an actionable paywall/taste state.

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

**Logout race regression:** Apple status/history calls already in flight when Log out is tapped must re-check `hasSignedOutSession` after every await. They may finish and clean up transactions, but only an explicit purchase or Restore can sign the local session back in; passive refresh/probe work cannot leave Home visible while Settings reports Inactive.

## Postponed (do not start)

| # | Item | Kind | Status | Why later |
| --- | --- | --- | --- | --- |
| 8 | Auth | feature | not started | Sign in with Apple / Better Auth; guest-card claim; `users.tasteCompletedAt`; Settings session Sign in/out does not void StoreKit |

Account / auth settings wait until auth exists. Appearance already shipped in 2a; the accent picker is removed.

## Out of scope (until listed)

- Extra reframe styles
- Client-side LLM keys
- Browser CORS
- Cloudflare Workers

## Shipped log

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
- 2026-09-10 — Compose model picker: Mistral / Gemini / DeepSeek logos; optional `model` on `POST /reframe`.
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
