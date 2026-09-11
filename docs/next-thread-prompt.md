# Angles — Home scroll and list performance

New thread: do not assume prior chat context. Read the repo files listed below before coding.

Performance is the job. Vertical scroll on Home currently lags on Joe’s iPhone. Treat 60fps scrolling as a product requirement, not a later polish. Measure on device, then change the smallest thing that actually moves the needle. Do not “optimize” by undoing 9d visuals.

## READ BEFORE CODE

- AGENTS.md, BUILD.md, .cursor/rules/angles.mdc, .cursor/rules/ios-device.mdc
- .cursor/skills/angles-ios/SKILL.md
- AnglesApp/AnglesApp/Home/HomeView.swift (`HomeFeedList`, `HomeFeedShelf`)
- AnglesApp/AnglesApp/Home/HomeCardStrip.swift
- AnglesApp/AnglesApp/Home/HomeCardGrid.swift
- AnglesApp/AnglesApp/Home/ReframeCardView.swift (`FlipStack`, `StyleChipRow`)
- AnglesApp/AnglesApp/Home/HeaderChrome.swift (`ProfileScrollDistance`, `ScrollDistanceProbe`)
- AnglesApp/AnglesApp/Home/ProfileView.swift
- AnglesApp/AnglesApp/Home/HomeViewModel.swift (what publishes, what a heart invalidates)

## Context: what shipped (row 9d)

Settled, do not re-investigate or undo:

1. One card per row. `HomeCardGrid` is a `LazyVStack`. `usesSingleColumn` is gone. Grid row spacing equals `HeaderCollapse.horizontalPadding` (16).
2. Card metrics: `baseHeight` 228, `chromeInset` 16, `controlSize` 32, copy pads 8. Overlay shares `ReframeCardMetrics`.
3. Strips are landscape: `min(pageWidth * 0.84, 340)` wide, same 228 height. Peek of the next card stays.
4. Style chips: unselected are 36pt (30pt compact) circles; the selected chip is a labeled pill that morphs with a spring. Hit target 40pt. Unselected glyphs are faint. One-angle cards keep the named pill.
5. Heart top-right on the selected style. Flip chevron bottom-right. Card actions on long-press `.contextMenu`. Selection is `@State`, not a scroll offset. `ForEach` keys on `card.id` alone.
6. Pins are gone. Failed writes show a banner. Small writes time out in 6s.
7. LLM length budgets did not change. Prompt copy no longer says “two-column card”.

9b already tried to make Home cheap: `GET /feed/home` grouped payload, `LazyVStack` of shelves, strips own scroll position, `HomeFeedShelf` / `HomeCardStrip` / `ReframeCardView` are `Equatable`, no page-wide `GeometryReader` for card width. **That was not enough.** The user still feels vertical lag on Home. 9b’s isolation is incomplete — prove what still invalidates, then fix it.

## The complaint

Scrolling Home vertically hitching / lagging on Joe’s iPhone (iPhone 14 Pro Max). Horizontal strip scroll may also hitch; vertical Home is the reported pain. Profile’s vertical library and Favorite-angles / Home-subset grids are in scope if they share the same cost.

## Task 1 — measure on device first

Do not guess a rewrite. Install a Debug build on Joe’s iPhone and reproduce a long Home fling through many shelves (seeded community feed).

- Instruments on device: Core Animation (FPS, dropped frames), Time Profiler, SwiftUI (body counts / invalidations) if available.
- Count what is actually on screen vs mounted: roughly Recent + a zipper of category and emotion shelves, each a horizontal strip of up to 6 `ReframeCardView`s. Lazy must mean lazy — confirm off-screen shelves are not alive.
- State in the change (BUILD.md 9e note) what you measured and which invalidation or draw cost was the hitch. If two causes are real, fix both. If a hypothesis below is false, say so and do not “fix” it anyway.

## Task 2 — stop scroll from rebuilding the feed

Prime suspect: `HomeView` holds `@State scrolledDistance`. `ProfileScrollDistance` writes it every 0.5pt of travel (`HeaderChrome.swift`). That re-runs `HomeView.body`. `HomeFeedList` is a nested view so the header collapse would not dirty the shelves — but `HomeFeedList` is **not** `Equatable` and is **not** `.equatable()`, and it is `@ObservedObject` on the shared `HomeViewModel`. Every scroll tick can rebuild every visible shelf and every card in it.

- Isolate header collapse from the feed. The feed must not re-evaluate because the title faded. Same bug exists on Profile (`scrolledDistance` + `ScrollDistanceProbe`).
- A heart on one card must not rebuild other shelves. `HomeFeedShelf` is already not `@ObservedObject`; do not regress that. Check whether `HomeFeedList`’s `@ObservedObject` still fans a heart out to every strip.
- Do not reintroduce a page-wide `GeometryReader` for card width. `pageWidth` from the app root stays.

## Task 3 — cheapen what a mounted card costs

Each Home shelf is a nested `ScrollView(.horizontal)` of up to six `ReframeCardView`s. A card today is expensive even at rest:

- `FlipStack` always holds both faces, `rotation3DEffect`, and `.compositingGroup()`, even when `progress == 0`.
- Soft shadow `radius: 10` plus a diagonal `StyleWashFill` gradient on the answer face.
- `StyleChipRow` is `ViewThatFits` of two full chip rows, with a spring `.animation(..., value: selected)` attached at all times.
- `.contextMenu`, `.sensoryFeedback`, wash `.animation` on `appearance.style`.

Keep the 9d look: labeled selected pill, quiet circles, three-band flip, landscape strips. You may:

- Keep both faces but skip 3D/compositing while unflipped, if that is the cost.
- Drop or lighten shadow **only if** Instruments shows fill-rate / shadow as the hitch — not because shadows feel fancy.
- Make `ViewThatFits` / pill spring run on tap, not on every parent layout pass.
- Avoid drawing the hidden flip face’s full chrome if it is free to defer.

Do not bring back the in-card pager, page dots, or ⋯ button. Do not flatten the card into a static `Image` of the copy.

## Task 4 — lists besides Home

After Home is smooth, check:

- Profile library (`HomeCardGrid` of full-width flip cards under the same collapsing header).
- Profile Favorite angles strip (same `HomeCardStrip`).
- Home shelf subset screens (`FeedSubsetView` → `ProfileSubsetView` → paged `HomeCardGrid`).

Same bar: a fling should not hitch. Same rule: do not rebuild the list from header collapse or from a heart on a different cell.

## Constraints

- Do not start BUILD.md row 6 (onboarding), 7 (StoreKit or paywall), or 8 (Better Auth).
- No new features, styles, CORS, SwiftData, or third-party networking.
- Do not reintroduce pins, the in-card pager, in-card page dots, or the ⋯ button.
- Do not undo 9d layout (one column, 228 height, landscape strips, pill-on-selected chips) to make FPS charts green.
- Do not compose `ForEach` identity from favorite state.
- Update BUILD.md in the same change (add **9e**, leave **Next up** as 6. Onboarding).
- After adding or removing Swift files: `cd AnglesApp && xcodegen generate`.
- Backend tests/typecheck only if you touch backend (you should not need to).

## Verification — device only

Simulator is not verification. Build, install, and launch on Joe’s iPhone:
`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`.
If the phone is locked, retry the launch. Do not say the work is visible until `devicectl`
install and launch have both succeeded. Mac awake; `pnpm dev` running if you load the feed.

On device, fling Home from top through several domain/mood shelves. Fling Profile’s library. Chip-morph, flip, and heart must still feel instant and must not hitch the outer scroll. Confirm a heart still does not reset the selected style.

## Acceptance

- Home vertical scroll feels continuous on Joe’s iPhone; no hitching through the seeded feed.
- Header collapse still works and no longer dirties the shelves on every tick.
- Horizontal strips still scroll, still peek, still page-dot.
- 9d visuals remain: selected chip is a labeled pill, cards are full-width in grids and landscape in strips.
- Heart, flip, long-press menu, and write-error banner still behave as in 9c.
- BUILD.md 9e states what was slow and what changed.

## If unsure

Stop and ask. Do not add features that are not in this list. Do not ship a visual redesign dressed up as a perf fix.
