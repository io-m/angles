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

**6. Onboarding taste** — Reuses Compose + Results; one thought, all four styles, then paywall.

## Core loop

Tab shell: **Home | Sparkle | Profile**. Sparkle opens the compose overlay. Profile is the private library. Home is the community feed of other people’s public cards.

Loading and error are **states on Results**, not their own screens.

| # | Item | Kind | Status | Files | Shipped |
| --- | --- | --- | --- | --- | --- |
| 1 | Compose (home) | screen | done | `AnglesApp.swift`; `Home/*.swift` | Favorites strip (max 6) + mixed-style grid; answer-first flip; long-press Delete. |
| 1b | Favorites | screen | done | `FavoritesView.swift`; `ProfileSubsetView.swift`; `ProfileView.swift` | Title opens a full favorites grid. Server-backed with the library. |
| 2 | Results | screen | done | `ComposeSheetView.swift`; `HomeViewModel.swift`; `SampleCardCopy.swift` | Statement + kept questions; AI card with per-style recook; Start again. |
| 2a | Settings (appearance + accent) | screen | done | `Theme/*`; `Settings/*`; `HomePalette.swift` | Warm-neutral charcoal tokens; modal Settings with profile, appearance, accent, subscription stub. |
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
| 9 | Public opt-in / community Home | screen | done | `HomeView.swift`; `feed.ts`; `schema.ts`; `CardsService.swift` | Public-others feed by Recent, category, and emotion; viewer pin/heart saves; `pnpm db:seed-community`. |
| 9b | Home perf, header, card gestures | polish | done | `HomeView.swift`; `HeaderChrome.swift`; `ReframeCardView.swift`; `FeedSubsetView.swift`; `homeFeed.ts`; `feed.ts` | Lazy shelves + grouped `GET /feed/home`; one collapsing header; three-band cards; domain/mood zipper. |
| 9c | Style chips, flip chevron, no pins | polish | done | `ReframeCardView.swift`; `HomeCardGrid.swift`; `HomeViewModel.swift`; `AnglesApp.swift`; `APIClient.swift`; `feed.ts`; `cards.ts` | Chips replace the in-card pager; heart top-right, flip chevron bottom-right; pins gone; failed writes say so. |

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
- The chosen styles show in one answer-first carousel (AI sparkle avatar left, flippable card right). New answer sits at the bottom center. Loading and error live on this overlay.
- Each style has New answer (overlay only); recook requests that style from the API.
- Start again (header) asks to confirm, then wipes the session and returns the composer. Overlay stays open.
- Save (icon + label) sits where the composer was and publishes all 4. X discards.

### 2a. Settings (appearance + accent)

Home-tab Settings sheet. Gradient chrome, large title that collapses to inline. Appearance is a popover. Accent and subscription stay sheets. Prefs in UserDefaults, not SwiftData.

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

Heart is per style, not per cook. Profile has a tappable **Favorite angles** title plus a landscape strip (max 6, list dots), and FavoritesView is the full 2-column grid of liked angles. Front is the liked angle; flip is the thought. One liked style has no in-card carousel; two or more liked styles on the same post share one card. Un-hearting the last liked style removes it from this list. Style chips do not filter this strip or grid.

### 5c. Pinned posts — removed in 9c

Pins are gone, app and schema. A card is saved by hearting an angle, and the thought is one flip away. Removed: `PUT` / `DELETE /feed/cards/:id/pin`, `PatchCardRequest.isPinned`, `GET /cards?pinned=`, `StoredCard.isPinned` / `pinnedAt` on the wire, and — in `drizzle/0003_drop_pins.sql` — `cards.is_pinned`, `cards.pinned_at`, `cards_user_pinned_idx`, and the `saved_pins` table. The library is now the viewer's own cards plus whatever they hearted on Home.

### 5d. Owner card menu

Long press on the owner's library cards. Menu: Delete (confirm), Make public / Make private (`isPublic`, default false), Language when a cleaned original exists (client toggle, no new translate). It lived on a top-trailing ⋯ button until 9c gave that slot to the heart. Public posts appear on other people’s Home, never the author’s.

### 5e. Thought type + card height

Thought face is slightly smaller and heavier than title3 regular, still distinct from the answer (`.callout` / `.medium`). Card height hugs max cleaned thought and max reframe plus chrome. Overlay uses the same metrics. Prompt budgets stay unless the card cannot fit them.

### 5f. List and in-card chrome

Strips have page-dots for which **card** is in view; cards in those strips have no list-dots. Grid rows are slightly tighter than the strip's horizontal gap. The in-card dots went away with the pager in 9c.

### 9. Public opt-in / community Home

Home is other people’s public cards (never the viewer’s). Style filter matches Profile (keeps cards that have that angle; All mixes covers). Sections: Recent, one strip per life-domain `category`, one strip per `emotion`. Pin/heart on someone else’s post writes viewer-scoped saves, not the author’s flags. Profile Pinned / Favorite angles union owned flags with those saves. Making a post public is so other people see it on their Home later.

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

## Postponed (do not start)

| # | Item | Kind | Status | Why later |
| --- | --- | --- | --- | --- |
| 6 | Onboarding taste | screen | not started | Reuses Compose + Results; one thought, all four styles, then paywall |
| 7 | Paywall | screen | not started | StoreKit, hard gate after the taste |
| 8 | Auth | feature | not started | Sign in with Apple / Better Auth; needed for restore, not for typing a thought |

Account / auth settings wait until auth exists. Appearance + accent already shipped in 2a.

## Out of scope (until listed)

- Extra reframe styles
- Client-side LLM keys
- Browser CORS
- Cloudflare Workers

## Shipped log

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
- 2026-09-09 — Compose (home): subtle bell-shaped accent glow around the overlay composer.
- 2026-09-09 — Compose (home): frosted overlay, inverted bubbles, cooking line, pill composer, and a header style popover.
- 2026-09-09 — Compose (home): removed Help drawer item; nudged flipped card washes closer to white.
- 2026-09-09 — Compose (home): circled drawer icons with new help/about glyphs, gradient FAB with glow, softer dock glow, and blur-crossfade title.
- 2026-09-09 — Compose (home): softened category card backs to tints, calmed card shadow for a continuous plane, and replaced boxed drawer icons with a quiet rail.
- 2026-09-09 — Compose (home): stripped glass sheen, colored glows, and double shadows; quiet white cards with one soft shadow, calm dock and FAB.
- 2026-09-09 — Compose (home): quieted the canvas to a near-white lavender linear wash and removed the radial purple glows.
- 2026-09-09 — Compose (home): glassy lavender canvas, category-matched AI card backs, borderless premium icons, elevated sparkle dock, and a rotating title.
- 2026-09-09 — Compose (home): balanced the lavender canvas, added category-coded cards and a distinct answer face, and removed the drawer’s moving plane edge.
