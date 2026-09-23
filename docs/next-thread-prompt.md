# Angles — post lands on Home

New thread: do not assume prior chat context. Read the current repo before coding.

The outcome: after a successful public save, the person sees a short success, the compose overlay leaves, and Home is already showing that new tall card at the top. The card is really on their feed. Refresh does not remove it. There is no moment of “where did my post go?”

Private saves never join Home. They use the same success, then land on Profile with that card in view.

The first-run taste save is unchanged. It still goes to the membership paywall.

## Read before code

- `AGENTS.md`, `BUILD.md`, `.cursor/rules/angles.mdc`, `.cursor/rules/ios-device.mdc`
- `.cursor/skills/angles-ios/SKILL.md`
- `.cursor/skills/angles-backend/SKILL.md`
- `AnglesApp/AnglesApp/AnglesApp.swift` — `handleSavedCard` sends a normal save to Profile
- `AnglesApp/AnglesApp/Home/ComposeSheetView.swift` — `publishAndLeave`, save bar (“Save to public library” / “Save to private library”)
- `AnglesApp/AnglesApp/Home/HomeViewModel.swift` — `saveCook` inserts into the library `cards` array only, not `feedCards`
- `AnglesApp/AnglesApp/Home/HomeView.swift` — tall feed, All + style tabs, unused `glimpseCard`
- `AnglesApp/AnglesApp/Paywall/PaywallView.swift` — existing Lottie `celebration-checkmark`
- `AnglesApp/Resources/celebration-checkmark.json`
- `backend/src/db/feed.ts` — `listFeed` requires `isPublic` and `userId !== viewerId`
- `backend/src/db/cards.integration.test.ts` — “excludes the viewer’s cards and private cards from the feed”

## Settled decisions

### Whose posts are on Home

Lift the rule that the author’s public posts never appear on their own Home.

Today that rule is written in three places:

- `BUILD.md` tab shell: “Home is the community feed of other people’s public cards.”
- `BUILD.md` 5d: “Public posts appear on other people’s Home, never the author’s.”
- `BUILD.md` section 9: “Home is other people’s public cards (never the viewer’s).”
- `AGENTS.md` opening line: published cards go to the “public-others” feed.
- `listFeed` in `backend/src/db/feed.ts`: `ne(cards.userId, viewerId)`.

Home is every public card, including the viewer’s own, newest first. Private cards stay off Home. Other people’s private cards stay off Home.

`isFeedSaveTarget` stays `isPublic && userId !== viewerId`. Hearting someone else’s card still writes `saved_angles`. The viewer’s own card on Home is an owner card: heart, delete, and public/private go through the existing owner card APIs. `HomeView` already branches on `isOwner`. Do not write a feed-save for the author’s own card.

### Where Save goes

Compose still defaults public.

- **Public, not taste.** Success, then Home, **All** tab, list at the top, this card first. It is a tall Home card, the same `TallHomeCardGrid` path. It also shows on any Home style tab that has that angle, because those tabs filter the same feed in memory. The landing tab is All.
- **Private, not taste.** Success, then Profile, on the style tab for the card’s spotlight style, with that card in view. It is not inserted into `feedCards`. The library insert in `saveCook` already puts it at the front of `cards`.
- **Taste.** Leave `handleSavedCard`’s onboarding branch alone. Do not run this Home arrival. Do not stack this celebration on the paywall celebration.

If Home’s Life area / Mood filter would hide the new public card, clear that filter before revealing Home. If the card matches, keep the filter. Either way the new card is on screen.

### The card has to stay

Do not use `glimpseCard`. That hook prepends a card only in the view and scrolls All to the top. `BUILD.md` already killed the half-second feed glimpse. A refresh would drop a glimpse, which is the doubt this work removes.

On public save success:

1. Insert the saved card at the front of `feedCards` (deduped by id) and into the library, which `saveCook` already does.
2. `GET /feed` includes the viewer’s public cards, so pull-to-refresh and the next page still contain it. Newest-first cursor paging stays as it is. Do not re-fetch the whole feed just to show this one card.
3. Making that card private, or deleting it, removes it from `feedCards` as well as the library. `setPublic` today updates only the library array. Fix that so the feed copy cannot keep a card Home should no longer show.
4. A later “Make public” on an existing library card makes it eligible for Home. Insert it into the loaded feed if Home is already loaded. No second celebration for the menu toggle.

Do not animate insertion of a whole fetched page. Only this one new card may animate in.

### Motion

Reuse the Lottie asset `celebration-checkmark`. Do not add another animation file. Do not present the paywall, its copy, or its Continue button.

Public or private, not taste:

1. The save button stays up while `POST /cards` runs. Do not dismiss the overlay on the tap.
2. On success: a success haptic, then the checkmark plays once, centered, over the compose overlay. Cap the beat at about one second. Reduce Motion skips the Lottie, keeps the haptic, and holds a short beat (about 0.4s).
3. Under the overlay, the destination is already in place: Home All at the top for a public post, or the Profile spotlight style tab with the new card in view for a private post.
4. Dismiss the overlay with the existing compose fade (`ComposeMotion`). The first thing they see is that card. No empty gap, no jump to a different tab after the fade, no second layout pass that scrolls it away.

Failure still shows the existing save error and leaves the overlay up. Do not play the checkmark.

### Copy

The save control must name the destination.

- Public: **Post**
- Private: **Save privately**
- The accessibility hint matches that destination. Delete the hint that says the card is added to Profile and the overlay closes. That is the private path only.

The Public / Private toggle on the card stays.

## Leave alone

- Tall card layout, Favorites flip cards, Profile chrome, Home chrome, paging, filters sheet, recook, prompts, seed data, and schema. No new column. `isPublic` already exists.
- Taste, paywall, StoreKit, and the frost handoff.
- Owner vs feed menus. A public own card on Home keeps the owner menu (delete, public/private).
- No `BUILD.md` feature row. Rewrite the sentences that say the author’s public posts are absent from their Home. Add one shipped-log line: a public post now appears on the author’s Home, and Save lands on that card. Do not describe the animation in that line.

## Tests and device

Update `cards.integration.test.ts`: the viewer’s public card is in `listFeed` with `isOwner: true`; their private card and other people’s private cards are not. Keep newest-first order.

Backend tests for the feed query. Then build, install, and launch on Joe’s iPhone (`E5C20243-B9B7-571E-9EEA-14FC441C13B7`, `app.angles.ios`). No Simulator. Do not say it is ready until that launch succeeds.

On device, confirm three paths: public Post opens onto that card at the top of Home All and survives pull-to-refresh; private Save privately opens onto that card on Profile and it is absent from Home; a taste save still opens the paywall.
