# Angles — one card per row, breathier card, real chip targets

New thread: do not assume prior chat context. Read the repo files listed below before coding.

## READ BEFORE CODE

- AGENTS.md, BUILD.md, .cursor/rules/angles.mdc, .cursor/rules/ios-device.mdc
- .cursor/skills/angles-ios/SKILL.md, .cursor/skills/angles-llm-prompts/SKILL.md
- AnglesApp/AnglesApp/Home/ReframeCardView.swift
- AnglesApp/AnglesApp/Home/HomeCardGrid.swift
- AnglesApp/AnglesApp/Home/HomeCardStrip.swift
- AnglesApp/AnglesApp/Home/ProfileView.swift, ProfileSubsetView.swift, FeedSubsetView.swift, HomeView.swift
- AnglesApp/AnglesApp/Home/HomePalette.swift (`CardStyleAppearance`)
- backend/src/lib/prompts.ts, backend/src/lib/decision.ts, backend/src/routes/reframe.ts

## Context: what shipped last thread (row 9c)

Settled, do not re-investigate or undo:

1. The in-card horizontal pager is gone. Styles switch from icon-only chips in the card's
   top-left; selection is `@State private var selectedStyle: Style?`, never a scroll offset.
2. Heart is top-right and acts on the selected chip's style. Flip chevron is bottom-right.
   Card actions (delete, make public, show original) are a long-press `.contextMenu`.
3. The favorite-reset bug is fixed: `HomeCardGrid` no longer builds a `.id()` out of favorite
   state. `ForEach` keys on `card.id` alone. Do not reintroduce a composed identity.
4. Pins are gone from the app, the API, and the schema (`drizzle/0003_drop_pins.sql`).
5. A failed write shows a banner (`HomeViewModel.writeError` → `WriteErrorBanner` in
   `AnglesApp.swift`). Small writes time out in 6s, cooks still 15s.

## Task 1 — one card per row

Today `HomeCardGrid` is a 2-column `LazyVGrid` that only collapses to one column at
accessibility Dynamic Type (`usesSingleColumn: dynamicTypeSize.isAccessibilitySize`).
Make one card per row the only layout.

- Every grid surface: Profile library, Profile subset screens (Favorite angles), and Home
  shelf subset screens. Check all of them.
- Decide and state whether `HomeCardGrid` stays a `LazyVGrid` with one `GridItem` or becomes
  a `LazyVStack`, and whether `usesSingleColumn` should be deleted rather than pinned to
  `true`. Do not leave a dead parameter behind.
- Row spacing was tuned against a 2-column grid (`Layout.gridRowSpacing = 16`). Re-tune it
  for full-width rows.

## Task 2 — redesign the card for full width

The card was sized for a ~193pt two-column cell on iPhone 14 Pro Max. At ~398pt wide the
current proportions read as a squat letterbox. `ReframeCardMetrics` today:

```
baseHeight 260 · thoughtSize 18 · chromeInset 16 · controlSize 32
chipSize 28 / chipSizeCompact 24 · chipSpacing 2
```

- Rework the metrics for a full-width card. Height should follow the copy and the new
  breathing room, not stay at 260 because that number is already there.
- **Breathier is the point.** More inset around the copy, more air between the bands and the
  text, a copy band that does not feel shrink-wrapped. Do not just scale everything up.
- The three-band contract stays: top chrome (chips / initials, heart), middle (copy, tap
  flips), bottom chrome (date, flip chevron). Only the middle flips. The date never flips.
  No `onTapGesture` on a card `Text`.
- `minimumScaleFactor(0.72)` on the copy is a safety net, not a layout tool. At full width
  the copy should sit at its real size in the normal case.
- The horizontal strips (Home shelves, Profile Favorite angles) still show narrower cards:
  `HomeCardStrip.cardWidth = min(pageWidth * 0.78, 300)`. State how the redesigned card
  behaves at that width — whether strips widen to match, or the card simply has to work at
  both. Do not let the strip card break.
- `OverlayProposalCard` (compose results) shares `ReframeCardMetrics` and is already full
  width. Keep it visually consistent with the new card.

## Task 3 — style chips you can actually hit

Today: 28pt (24pt compact) icon-only chips, 2pt apart, selected gets a tinted circle. Too
small for a thumb, and the row reads as one blob.

- Every chip sits in its own circular container — unselected ones too, so the row reads as a
  real segmented control instead of four loose glyphs.
- Only the selected chip is colored (its `CardStyleAppearance.ink`) and lifted: a subtle
  elevation, not a drop shadow competing with the card's own. Unselected chips stay quiet and
  neutral.
- Spend the new full-width space on the tap target. Aim for a comfortable thumb target and
  say what size you landed on and why. The card is ~398pt wide now, not 193 — four chips plus
  the heart no longer have to fight for the band.
- Gap between chips should be clearly visible but not sprawling. Tune it, do not default to
  "bigger is better".
- `ViewThatFits` currently degrades 28pt → 24pt for narrow cards. Decide whether that fallback
  is still needed once cards are full width, given the strip cards are still ~300pt.
- Keep the behavior: tapping a chip switches the copy, the heart follows the selection, the
  wash and the appearance animation follow the selected style, and a card with one angle
  keeps the named pill instead of a single chip.

## Task 4 — revisit the LLM length budgets

The prompts are written against a two-column card and say so in the copy. Constants in
`backend/src/lib/prompts.ts`:

```
THOUGHT   8–22 words · 40–140 chars   (hard: 32 words / 180 chars)
REFRAME  12–32 words · 80–190 chars   (hard: 250 chars)
```

- Only change these if the redesigned card genuinely fits more. Measure against the real card
  at the real width first, then propose numbers. Do not guess upward because there is space.
- If you do change them, `STYLE_LENGTH_BUDGET` and the decision prompt still say "fit a
  two-column card" in two places. Fix the wording in the same change.
- The retry and trim paths (`REFRAME_TOO_LONG_RETRY`, `REFRAME_HARD_MAX_CHARS`,
  `THOUGHT_HARD_MAX_*` in `decision.ts` and `reframe.ts`) have to stay consistent with any
  new budget.
- `backend/src/scripts/communityCopy.ts` and `communityFixture.test.ts` assert against these
  budgets. The seeded community copy was written to the old caps — say whether it needs a
  reseed, and do not leave the fixture test failing.
- Longer is not better. The card is a glance, not a paragraph. If the budgets stay, say so.

## Constraints

- Do not start BUILD.md row 6 (onboarding), 7 (StoreKit or paywall), or 8 (Better Auth).
- No new reframe styles. No CORS. No third-party networking. No SwiftData.
- Do not reintroduce pins, the in-card pager, page dots, or the ⋯ button.
- Update BUILD.md in the same change as the feature work.
- After adding or removing Swift files: `cd AnglesApp && xcodegen generate`.
- Run the backend test suite and the typecheck before calling anything done.

## Verification — device only

Simulator is not verification. Build, install, and launch on Joe's iPhone:
`id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`, bundle `app.angles.ios`.
If the phone is locked, retry the launch. Do not say the work is visible until `devicectl`
install and launch have both succeeded. Make sure the Mac is awake and `pnpm dev` is running
before testing anything that talks to the server.

## Acceptance

- One card per row everywhere a grid appears; no two-column layout left in the app.
- The card reads as full width and unhurried: copy has room, bands have air, height follows
  the content instead of a leftover constant.
- Chips are circular containers, only the selected one is colored and lifted, and a thumb
  hits them without aiming.
- Cards in the horizontal strips still look right and still scroll.
- Hearting still sticks, still does not move the selected style, and still does not flip the
  card. Outer scrolling is unobstructed.
- If the LLM budgets changed, prompt copy, retry, trim, fixtures, and tests all agree.

## If unsure

Stop and ask. Do not add features that are not in this list.
