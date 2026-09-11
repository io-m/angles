# Angles — fix the favorite-reset bug, then replace card gestures with chips + flip

New thread: do not assume prior chat context. Read the repo files listed below before coding.

## READ BEFORE CODE

- AGENTS.md, BUILD.md, .cursor/rules/angles.mdc, .cursor/rules/ios-device.mdc
- .cursor/skills/angles-ios/SKILL.md, .cursor/skills/angles-backend/SKILL.md
- AnglesApp/AnglesApp/Home/ReframeCardView.swift
- AnglesApp/AnglesApp/Home/HomeCardGrid.swift
- AnglesApp/AnglesApp/Home/HomeCardStrip.swift
- AnglesApp/AnglesApp/Home/HomeViewModel.swift
- AnglesApp/AnglesApp/Home/HomeView.swift
- AnglesApp/AnglesApp/Home/ProfileView.swift
- AnglesApp/AnglesApp/Home/ProfileSubsetView.swift
- AnglesApp/AnglesApp/Home/FeedSubsetView.swift
- AnglesApp/AnglesApp/Networking/APIClient.swift, CardsService.swift
- backend/src/routes/feed.ts, backend/src/db/feed.ts, backend/src/db/cards.ts

## Context: what the previous thread already established

Do not re-investigate these; they are settled.

1. "Inspire me returns nothing" was not an LLM or backend fault. `POST /reframe` works
   end to end in about 3 seconds with real Mistral output. The dev server log contained
   no `/reframe` request from the device at all, because the Mac hosting the dev server
   was asleep. Swapping providers changed nothing because no provider was ever reached.
2. The server persists favorites correctly. After `PUT /feed/cards/:id/angles/:style`,
   the write response, `GET /feed/home`, and `GET /cards` all report the angle
   favorited. The reset the user sees is client-side.
3. Half of the favorite-reset symptom was the same sleeping Mac: `toggleFavorite`
   applies the heart optimistically and its `catch` branch silently restores the old
   value, so a write that times out un-fills the heart about 15 seconds later with no
   error shown. `APIClient` uses `timeoutIntervalForRequest = 15`.
4. The other half is a real view-layer bug. `HomeCardGrid.cardIdentity` includes the
   card's favorited-style list, so every heart changes the SwiftUI identity, rebuilds
   the card, resets its `@State`, and `syncPager()` snaps the in-card carousel back to
   the opening slide. The bottom-chrome heart is bound to
   `visibleSlides[safe: activeSlideIndex]`, so it then renders a different style's
   unfavorited state, and tapping again either toggles the wrong style or removes the
   real favorite.

## Task 1 — stop silent write failures

- Make a failed write legible instead of invisible. Today `toggleFavorite` and
  `togglePinned` roll back in `catch` with no message. Surface an error to the user.
  Reuse the existing error presentation language; do not invent a new toast system if
  one already exists.
- Consider whether the 15s request timeout should be shorter for small writes
  (heart, pin) than for a cook, so an unreachable server fails fast. Propose, do not
  guess.
- Do not log user thought text.

## Task 2 — fix the favorite-reset bug in the view layer

- `HomeCardGrid.cardIdentity` must not depend on favorite state. Identity should be
  the card id, plus presentation and openingStyle only if genuinely required. Handle
  slide-visibility changes inside the card view, not by changing identity.
- After the fix, hearting a card must not flip its face, must not move its selected
  style, and must not affect sibling cards.
- Check every surface: Home strips, Home shelf subset screens, Profile All and
  per-style grids, and Profile subset screens.

## Task 3 — replace the in-card carousel with style chips

The inner horizontal pager collides with the outer list scrolling. Remove it.

- Delete the in-card horizontal `ScrollView`, its `scrollTargetBehavior(.paging)` and
  `scrollPosition(id:)`, and the page dots.
- In its place, put tappable style chips (icons) in the card's top-left, where the
  style pill currently sits. Tapping a chip switches the visible answer copy.
- Only render chips for styles the card actually has; cards carry 1 to 4.
- Selection becomes explicit `@State` (the selected style), not a value inferred from
  scroll offset. The heart must act on the selected chip's style.
- Keep the existing style wash and appearance animation driven by the selected style.
- No new styles. The four are stoic, optimistic, humorous, tough_love.

## Task 4 — card chrome: flip affordance, heart top-right, no pin

- Add a flip control (right arrow or chevron) at the card's bottom-right, in the slot
  the pin or heart occupies today.
- Move the heart to the card's top-right corner.
- Remove the pin control from cards entirely.
- Decide and state whether tap-to-flip on the middle copy band stays in addition to
  the explicit chevron. Recommendation: keep both, since the middle band already owns
  the flip gesture and the chevron is the discoverable affordance.
- Preserve the three-band hit-testing contract from row 9b: top and bottom chrome must
  not flip the card, and the date must not flip it. Do not put `onTapGesture` on a
  card `Text`.

## Task 5 — remove the pinned list

- Remove the pinned strip and section from Profile and any pinned-only screen. Users
  can only favorite answers, and they can flip a card to read the original thought.
- Remove the iOS pin surface end to end: `pinnedCards`, `stripPinnedCards`,
  `togglePinned`, `pinTasks`, `pinnedSection`, `pinnedAndFavorites`, the `.pinned`
  card presentation, and `pinFeed` / `unpinFeed` in `CardsService`.
- Backend surface to consider: `PUT` and `DELETE /feed/cards/:id/pin`, `pinFeedCard`,
  `unpinFeedCard`, `savedPins`, `cards.isPinned`, `PatchCardRequest.isPinned`.
  Recommendation: leave the DB columns and the `savedPins` table in place, since
  dropping them needs a migration nobody asked for, but remove the routes and the app
  surface and note the dormant columns in BUILD.md. Confirm before deleting routes.
- If any type changes, keep `backend/src/types/index.ts` and `ReframeModels.swift`
  JSON-identical in the same change.

## Constraints

- Do not start BUILD.md row 6 (onboarding), 7 (StoreKit or paywall), or 8 (Better Auth).
- No CORS. No For-you ranking. No visible like or pin counts. No comments or nicknames.
- No extra reframe styles. No third-party networking. No SwiftData.
- Update BUILD.md in the same change as the feature work.
- After adding or removing Swift files: `cd AnglesApp && xcodegen generate`.
- Run the backend test suite and the typecheck before calling anything done.

## Verification — device only

Simulator is not verification. Build, install, and launch on Joe's iPhone:
`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`.
If the phone is locked, retry the launch. Do not say the work is visible until
`devicectl` install and launch have both succeeded. Make sure the Mac is awake and
`pnpm dev` is running before testing anything that talks to the server.

## Acceptance

- Hearting an answer sticks: it survives the server round-trip, a style-filter change,
  leaving and re-entering the tab, and an app relaunch.
- A failed write shows an error instead of silently reverting.
- Cards have no inner horizontal pager; styles switch by tapping the top-left chips.
- Heart is top-right, flip chevron is bottom-right, pin is gone from cards.
- No pinned list anywhere in the app.
- Outer vertical scrolling and shelf horizontal scrolling are unobstructed by card
  gestures.

## If unsure

Stop and ask. Do not add features that are not in this list.
