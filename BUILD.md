# Angles build tracker

Living document for **what to build, in what order**. Update this file in the same change as every new screen or feature.

Assume the user is already paid. **No onboarding, paywall, or auth until the core loop is done.**

## How to update

When you add or change a screen/feature:

1. Set its **Status** (`not started` → `in progress` → `done`).
2. Fill **Files** and a one-line **Shipped** note.
3. Move **Next up** to the following item.
4. If you need a screen that is not listed, add it here *before* building it.

Do not skip ahead. Do not invent extras (tabs, settings, social, extra styles).

Status values: `not started` · `in progress` · `done` · `skipped`

## Next up

**1. Compose (home)** — fake data, no API.

## Core loop

Navigation: stack only. **Compose → Results**. No tabs until History.

Loading and error are **states on Results**, not their own screens.

| # | Item | Kind | Status | Files | Shipped |
| --- | --- | --- | --- | --- | --- |
| 1 | Compose (home) | screen | not started | | |
| 2 | Results | screen | not started | | |
| 3 | Multi-style results | same screen as 2 | not started | | |
| 4 | Hook up fetching | feature | not started | | |
| 5 | History | screen | not started | | |

### 1. Compose (home)

Thought text field, four style chips (`stoic`, `optimistic`, `humorous`, `tough_love`), submit.

- Validate: empty thought, no style selected.
- Submit navigates to Results with **hardcoded** `ReframeResult`s.
- Use existing `Style` / `ReframeResult` models. Do not invent a parallel JSON shape.
- No API. No paywall. App launches here.

### 2. Results

Original thought + reframe for the chosen style.

- Actions: copy, pick another style (swap fake copy, don’t retype), “new thought” back to Compose.
- Loading and error live on this screen.
- Still fake data.

### 3. Multi-style results

Same Results screen. Stacked cards when more than one style is selected. Still fake. Matches later `Promise.all` / onboarding taste.

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

No settings/account screen until auth exists.

## Out of scope (v1)

- Public feed / social
- Extra reframe styles
- Client-side LLM keys
- Browser CORS
- Cloudflare Workers

## Shipped log

Newest first. Add a line when something moves to `done`.

_Nothing shipped yet._
