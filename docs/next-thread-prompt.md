# Angles — flat filtered Home + no-flip cards

New thread: do not assume prior chat context. Read the current repo before coding. This is a deliberate product pivot, not a small visual tweak.

The outcome:

1. Home is one newest-first, vertically paged list. There are no Recent/category/mood shelves and no horizontal strips on Home.
2. Home’s header filter opens a multi-select bottom sheet for **Life areas** and **Moods**. Home no longer filters by reframe style.
3. Cards never flip. A stored card shows identity/time, the thought, one selected AI answer, style selectors, favorite heart, and its action menu at once.
4. Delete all code and API contracts made obsolete by the old grouped Home. Do not delete metadata that the new filter still requires.

## READ BEFORE CODE

- `AGENTS.md`, `BUILD.md`, `.cursor/rules/angles.mdc`, `.cursor/rules/ios-device.mdc`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-backend/SKILL.md`
- `AnglesApp/AnglesApp/Home/HomeView.swift`
- `AnglesApp/AnglesApp/Home/HomeViewModel.swift`
- `AnglesApp/AnglesApp/Home/ReframeCardView.swift`
- `AnglesApp/AnglesApp/Home/HomeCardGrid.swift`
- `AnglesApp/AnglesApp/Home/HomeCardStrip.swift`
- `AnglesApp/AnglesApp/Home/ProfileView.swift`
- `AnglesApp/AnglesApp/Home/ProfileSubsetView.swift`
- `AnglesApp/AnglesApp/Home/FeedSubsetView.swift`
- `AnglesApp/AnglesApp/Home/HeaderChrome.swift`
- `AnglesApp/AnglesApp/Networking/CardsService.swift`
- `AnglesApp/AnglesApp/Models/ReframeModels.swift`
- `backend/src/routes/feed.ts`
- `backend/src/routes/feed.test.ts`
- `backend/src/db/feed.ts`
- `backend/src/db/schema.ts`
- `backend/src/lib/homeFeed.ts`
- `backend/src/lib/homeFeed.test.ts`
- `backend/src/types/index.ts`

## Settled decisions

### Home filter semantics

The two real taxonomy groups are:

- **Life areas** (`CATEGORIES`): Work, Money, Romantic, Family, Friends & social, Health, Self-worth, Future, Grief & loss, Identity, Other.
- **Moods** (`EMOTIONS`): Anger, Shame, Fear, Sadness, Envy, Loneliness, Overwhelm, Numbness, Hope.

Filtering is faceted:

- No selection in either group means show all public cards.
- Multiple selections inside one group are **OR**.
- If both groups have selections, the groups combine with **AND**.
- Example: Life areas = Work or Money, Moods = Fear or Overwhelm means `(Work OR Money) AND (Fear OR Overwhelm)`.
- Reframe style is no longer a Home filter. Profile’s existing style filter remains.

### Card answer semantics

- A card still stores all available styles.
- It shows exactly one selected AI answer at a time.
- Existing style chips select that answer.
- The heart favorites the selected style only.
- `ForEach` identity remains `card.id`; never include favorite or selected-style state in identity.

## Task 1 — replace grouped Home with one vertical feed

Redesign `HomeView` as a single lazy, full-width, one-card-per-row feed:

- Remove the Recent shelf.
- Remove every category and mood shelf.
- Remove shelf titles, shelf chevrons, Home horizontal card strips, strip page dots, and shelf destination navigation.
- Keep newest-first ordering and infinite cursor pagination.
- Use the existing full-width `HomeCardGrid`/`LazyVStack` pattern rather than inventing another list component.
- Preserve row spacing and root-provided page width. Do not add a page-wide `GeometryReader`.
- Empty state is one Home-level message reflecting the applied filter.
- Initial load, retry, pull/refresh behavior if already present, pagination loading, and pagination failure must be states of this one feed—not new screens.

Preserve the 9e performance work:

- `HomeViewModel` stays on iOS 17 Observation; do not return to broad `ObservableObject` invalidation.
- Header collapse progress stays in header-only capped state.
- Prefetch before the last card, append by stable id, deduplicate incrementally, keep a stable footer, and do not re-fetch/replace already displayed pages.
- Applying a filter atomically replaces the result set and resets its cursor. Do not mix pages from different filter generations if an older request finishes late.
- Do not animate insertion of an entire fetched page.

`HomeCardStrip` is **not globally obsolete**: Profile’s Favorite angles strip still uses it. Remove only Home’s use of it.

## Task 2 — multi-select filter bottom sheet

Replace Home’s style popover with a category filter sheet:

- Tapping the existing Home filter/category icon presents a native bottom sheet.
- Use a `NavigationStack` sheet with title **Filter Home**.
- Show two clearly separated sections named **Life areas** and **Moods**.
- Every row has a readable label, the existing taxonomy icon/color where appropriate, a full-row hit target, and a checkmark/selected state.
- Multi-select is draft state inside the sheet. Provide **Clear** and **Apply**. Dismissing without Apply leaves the active filter unchanged and avoids network churn for every tap.
- The header icon shows a compact badge containing the total number of applied Life area + Mood selections. Hide the badge at zero.
- Give the icon an accessibility label/value such as “Filter Home, 3 filters applied.”
- Both the expanded and collapsed Home headers must open the same sheet and show the same applied-count badge.
- Keep applied selections in `HomeViewModel` so they survive header collapse, navigation pushes, and tab switches. Do not add persistence across launches unless it already exists.
- Profile’s style filter remains unchanged.

Use one small value type for the applied filter, for example category and emotion `Set`s, with stable equality. Do not use display strings as API values.

## Task 3 — simplify the feed API and SQL

The flat Home must page `GET /feed`; retire the grouped endpoint.

### New `GET /feed` query

Support:

- `limit`
- `before`
- optional comma-separated `categories`
- optional comma-separated `emotions`

Omit empty query items. Parse and validate every raw value against `CATEGORIES`/`EMOTIONS`; an unknown value returns the normal 400 `VALIDATION_ERROR`.

SQL semantics:

- `categories`: `cards.category IN (...)`
- `emotions`: array overlap with any selected mood
- category and emotion clauses are both added to the existing `AND` filter list
- continue requiring public cards owned by someone else
- continue ordering newest first with the existing deterministic id tiebreak

Home no longer sends `style` to `/feed`. Remove that dead feed query field if no remaining caller needs it; Profile style filtering uses `/cards`, not `/feed`.

Update route, DB, and integration/unit tests for:

- no filters
- several Life areas
- several Moods
- both groups together
- invalid values
- cursor pagination with filters

If the emotion-array query needs a Postgres GIN index at realistic feed size, add a named Drizzle migration and document it. Keep the existing public/newest and category indexes unless query plans prove one is redundant.

## Task 4 — delete the grouped Home contract

After the flat feed is wired end to end, remove—not deprecate—the old shelf machinery:

### Backend

- Delete `GET /feed/home`.
- Delete `listHomeFeed`, `HOME_SCAN_LIMIT`, and the `groupHomeFeed` import.
- Delete `backend/src/lib/homeFeed.ts` and `backend/src/lib/homeFeed.test.ts`.
- Delete `FeedHomeQuery`, `FeedHomeSectionKind`, `FeedHomeSection`, and `FeedHomeResponse`.
- Remove old grouped-route mocks/assertions from feed tests.

### iOS

- Delete `CardsService.homeFeed`.
- Delete `FeedHomeSectionKind`, `FeedHomeSection`, and `FeedHomeResponse`.
- Delete `FeedShelf`, `FeedSection`, `FeedShelfIDs`, `feedShelves`, `feedSections`, the zipper, and grouped-payload application.
- Replace the per-shelf subset dictionary/tasks with one flat Home pagination state and one task generation.
- Delete `FeedSubsetView.swift`; shelf detail screens no longer exist.
- Remove `HomeFeedShelf` and all shelf navigation from `HomeView`.
- Remove Home’s `homeGridFilter` style state and replace it with the applied taxonomy filter.
- Keep `ProfileSubsetView`, `HomeCardStrip`, and Profile’s Favorite angles behavior.
- Run `cd AnglesApp && xcodegen generate` after deleting the Swift file.

### Database/data warning

“Recent” is computed output, not a database category, table, column, or enum value. There is no Recent migration and no Recent data to delete.

Do **not** drop:

- `cards.category` or the `category` enum
- `cards.emotions` or the `emotion` enum
- tags/matching metadata
- `spotlight_style`
- `thought_original`/`input_language`
- `card_reframes` or `saved_angles`

Those remain required by filtering, selected-answer display, language switching, and per-style favorites. Remove dead grouped-feed code and contracts, not useful card data.

## Task 5 — redesign stored cards without flip

Remove the flip model completely from `ReframeCardView`:

- Delete `isFlipped`, `showingThought`, `flipHaptic`, `flip()`, `FlipStack`, `rotation3DEffect`, the flip accessibility action/hint, and every flip chevron.
- The card copy is no longer a tap target.
- Remove hidden front/back faces and render one semantic hierarchy.

Use this layout:

### Top row — identity and actions

- Leading: the user’s initials avatar.
- Immediately beside it: compact time/date metadata for `card.createdAt`, visually secondary.
- Trailing: a 40–44pt ellipsis button.
- The ellipsis opens the same actions as long press. Build the menu items once and reuse them from a tap `Menu` and `.contextMenu`; do not maintain two action lists.
- Preserve owner Delete, Make public/private, saved-card Remove from board, and Original/English actions.
- Original/English now swaps the displayed thought inline; it never flips a face.
- Do not render a dead ellipsis if that card role genuinely has zero available actions.

### Content — thought, divider, selected answer

Information hierarchy matters:

- The user’s thought is context: readable, compact, slightly quieter than the answer. Do not make it look disabled or bury it in tiny caption text.
- Follow it with generous but controlled spacing and one quiet hairline divider.
- The selected AI answer is the primary value: stronger foreground and weight, with enough vertical breathing room to scan first after recognizing the thought.
- Keep the selected style’s subtle wash, but confine/compose it so the answer receives emphasis without making the thought/header noisy.
- Do not add “Question”/“Answer” labels unless on-device review proves the hierarchy is unclear without them.
- Do not truncate normal prompt-budget copy or use `minimumScaleFactor` as layout. Let the card grow vertically.

### Bottom row — selection and favorite

- Leading: the existing style selector. Selected style remains a labeled pill; other available styles remain quiet circular buttons.
- Trailing: the heart for the selected style.
- Keep 40pt minimum chip targets and a 40–44pt heart target.
- Chip/pill/wash animation occurs only inside the chip tap transaction—never on card mount, page append, filter apply, heart update, or programmatic opening-style change.
- Keep the native heart replacement/bounce and haptic. Hearting must not move the selected style.

Retune `ReframeCardMetrics` for the larger content:

- Full-width grids should use natural content height with a sensible minimum, not the old fixed 228pt flip-card frame.
- Verify the same shared card at the 340pt Profile Favorite angles strip width. Remove the strip’s hardcoded height if necessary so its `HStack` can establish one stable height from its cards.
- Keep cards lazy and avoid per-card width `GeometryReader`s.
- Test the longest allowed thought and reframe, four styles, one style, Dynamic Type, and both color schemes.

## Task 6 — remove flip from compose results too

`OverlayProposalCard` also uses `FlipStack`; remove that flip so the product has one card language:

- Show the submitted/cleaned thought, divider, and one selected answer together.
- Keep style selectors and per-style New answer/recook.
- It has no stored author/date/menu/heart, so do not fake those controls.
- Programmatic initial style remains non-animated; a user chip tap animates.
- Retune overlay sizing after shared metrics change so composer/results still fit and scroll correctly.

## Task 7 — documentation and stale contracts

- Add the next BUILD row after 9e and leave **Next up** as 6. Onboarding.
- Update `AGENTS.md` because its Home shelf, three-band flip, heart position, and owner-menu descriptions will be stale.
- Update relevant inline comments. Delete comments that describe pagers, fronts/backs, shelf zippers, or flip bands.
- Do not change LLM length budgets unless on-device testing proves the new card still cannot fit current caps.

## Constraints

- Do not start onboarding, StoreKit/paywall, or Better Auth.
- No new styles, pins, in-card pager, client-side LLM, CORS, SwiftData, or third-party networking.
- Do not remove per-style favorites.
- Do not compose card identity from favorite/filter/selection state.
- Preserve 9e field-level Observation and header/list isolation.
- Prefer failing a multi-style reframe over partial results.
- If backend wire types change, keep `backend/src/types/index.ts` and `ReframeModels.swift` aligned.

## Verification

Backend:

- Run backend typecheck and full tests.
- Run DB migration/integration tests if an index migration is added.
- Verify `/feed/home` is 404 and no grouped Home symbols remain.

iOS:

- Check edited files for diagnostics.
- Generate the Xcode project after deleting `FeedSubsetView.swift`.
- Build, install, and launch on Joe’s iPhone only:
  - destination `E5C20243-B9B7-571E-9EEA-14FC441C13B7`
  - bundle `app.angles.ios`
- Do not call Simulator verification.

On device:

- Home initially shows one newest-first vertical list.
- No Recent/category/mood shelf or Home horizontal strip remains.
- Filter sheet drafts, clears, cancels, applies, and shows the correct header badge.
- OR-within/AND-between filtering matches the API through at least two pages.
- Applying filters while a request is in flight cannot append stale results.
- Infinite paging stays smooth.
- Top avatar/date/menu, thought/divider/answer, bottom chips/heart match the hierarchy above.
- Cards never flip and no chevron remains.
- Tap ellipsis and long press expose the same applicable actions.
- Original/English swaps inline.
- Chips animate only on tap; heart bounce works; a heart never resets style selection.
- Profile library, Favorite angles strip, compose result/recook, privacy, delete, rollback banner, and navigation still work.

## Acceptance

- Home is a flat, vertically paged community feed with no Recent or shelves.
- Applied Life area/Mood filters use the settled faceted semantics and show a correct badge.
- Old grouped Home API/types/files/state are deleted.
- No useful category/emotion/card data is dropped.
- Stored and compose cards contain thought + selected answer simultaneously and have no flip state or chevrons.
- Stored card chrome is exactly: avatar + time/date + ellipsis at top; style selectors + heart at bottom.
- Existing per-style favorite, menu, language, privacy, delete, error, and performance behavior remains correct.

If a requirement conflicts with current code, stop and explain the conflict before inventing a third behavior.
