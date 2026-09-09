# Angles build tracker

Living document for **what to build, in what order**. Update this file in the same change as every new screen or feature.

Assume the user is already paid. **No onboarding, paywall, or auth until the core loop is done.**

## How to update

When you add or change a screen/feature:

1. Set its **Status** (`not started` → `in progress` → `done`).
2. Fill **Files** and a one-line **Shipped** note.
3. Move **Next up** to the following item.
4. If you need a screen that is not listed, add it here *before* building it.

Do not skip ahead. Do not invent extras (tabs, social, extra styles).

Status values: `not started` · `in progress` · `done` · `skipped`

## Next up

**4. Hook up fetching** — Compose → `ReframeService.getReframes` → Results.

## Core loop

Navigation: stack only. **Compose → Results**. No tabs until History.

Loading and error are **states on Results**, not their own screens.

| # | Item | Kind | Status | Files | Shipped |
| --- | --- | --- | --- | --- | --- |
| 1 | Compose (home) | screen | done | `AnglesApp.swift`; `Home/*.swift` | Frosted overlay, inverted bubbles, pill composer, and header style popover. |
| 2 | Results | screen | done | `ComposeSheetView.swift`; `HomeViewModel.swift` | Overlay session of thought + style-wash card; Send appends; header style applies to the next send only. |
| 2a | Settings (appearance + accent) | screen | done | `Theme/*`; `Settings/*`; `HomePalette.swift` | Warm-neutral charcoal tokens; modal Settings with profile, appearance, accent, subscription stub. |
| 3 | Multi-style results | same screen as 2 | skipped | | Per-send single style. Checkbox to select; floating Save above composer publishes. Carousel when 2+ saved. In-memory only. |
| 4 | Hook up fetching | feature | not started | | |
| 5 | History | screen | not started | | |

### 1. Compose (home)

Home shell with a scrollable fake-history card grid, composer dock, and header Settings.

- Cards flip between the original thought and a hardcoded `ReframeResult`.
- Composer overlay validates empty thought and no style selected, then cooks a hardcoded response in place.
- Settings is a dismissible sheet from a circular header control; header scrolls with the feed; appearance is a popover.
- Use existing `Style` / `ReframeResult` models. Do not invent a parallel JSON shape.
- No API or persistence. No paywall. App launches here.

### 2. Results

Original thought + reframe for the chosen style.

- Pick another style in the header; it applies to the next send, not a recook of the latest thought.
- Send another thought from the composer to append a new cook; earlier pairs stay.
- Loading and error live on this screen.
- Still fake data.

### 2a. Settings (appearance + accent)

Header Settings sheet. Gradient chrome, large title that collapses to inline. Appearance is a popover. Accent and subscription stay sheets. Prefs in UserDefaults, not SwiftData.

### 3. Multi-style results

Skipped. Stacked multi-style on one send was rejected. Header style is single-select and binds at Send. Checkbox selects replies; a floating Save chip above the composer publishes them to home (carousel when 2+). X closes without saving.

### 4. Hook up fetching

Not a new screen. Compose → `ReframeService.getReframes` → Results.

- Simulator + local API (`pnpm dev`, `http://localhost:8787`).
- Loading/error become real.
- Physical device: Mac LAN IP in `AppConfig` (localhost is the phone).

### 5. History

List of past thoughts/reframes. **After fetching.** Needs SwiftData (or similar). Do not add persistence before this task.

Tabs are allowed only once this screen exists (Compose + History).

## Postponed (do not start)

| # | Item | Kind | Status | Why later |
| --- | --- | --- | --- | --- |
| 6 | Onboarding taste | screen | not started | Reuses Compose + Results; one thought, all four styles, then paywall |
| 7 | Paywall | screen | not started | StoreKit, hard gate after the taste |
| 8 | Auth | feature | not started | Sign in with Apple / Better Auth; needed for restore, not for typing a thought |

Account / auth settings wait until auth exists. Appearance + accent already shipped in 2a.

## Out of scope (v1)

- Public feed / social
- Extra reframe styles
- Client-side LLM keys
- Browser CORS
- Cloudflare Workers

## Shipped log

Newest first. Add a line when something moves to `done`.

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
