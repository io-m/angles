---
name: angles-ios
description: Extend or change the Angles iOS app networking, models, and XcodeGen project. Use when editing Swift under AnglesApp, APIClient, ReframeService, AppConfig, or project.yml.
---

# Angles iOS

## Project

Source of truth is `AnglesApp/project.yml`. App icon (Icon Composer): `AnglesApp/Angles.icon` (`ASSETCATALOG_COMPILER_APPICON_NAME: Angles`). `~/Documents/Angles.icon` symlinks to that folder so edits from either path ship in the next build.

After adding or moving Swift files:

```bash
cd AnglesApp && xcodegen generate
```

Target: iOS 17+, bundle id `app.angles.ios` (placeholder). No SPM networking packages.

## Networking

- `APIClient` — JSON `URLSession` verbs (`GET`, `POST`, `PATCH`, `DELETE`), decode `Decodable`, map failures to `APIError`.
- `ReframeService.refine(text:followUps:attempt:)` and `recook(_:attempt:)` — `POST /reframe` only. Answers `.continueTurn` or `.ready`. A recook echoes the signed cook and the answer it replaces; the server picks the model.
- `CardsService` — `POST/GET/PATCH/DELETE /cards`. Profile library source of truth.
- Auth header: `Authorization: Bearer` from the Keychain session (`AuthCredentials` / `SessionStore`). Sign in with Apple only. `requireAuth` on product routes.

## Models

Keep `Style` raw values identical to the backend: `stoic`, `hopeful`, `witty`, `tough`. `ThoughtCategory`, `Timeframe`, `SafetyFlag`, and `IntensityBand` decode unknown values to a safe case on purpose — a new backend value must not fail a whole cook.

A `continue` response keeps the composer up (`ComposeSession.isComposerVisible`, held as `HomeViewModel.compose`). Never hide it on anything but a finished cook.

## Config

`AppConfig.baseURL` reads Info.plist `AnglesAPIBaseURL`, which is the `ANGLES_API_BASE_URL` build setting in `project.yml`: Debug is the Mac LAN IP (`http://192.168.0.39:8787`; physical devices cannot use localhost), Release is empty until the Railway host exists, so Release requests fail locally. Never fill it with a host we do not own.

Saves echo the `/reframe` signatures (`ReadyCook.signature`, `SignedReframeResult.signature`); a recook replaces the whole signed result, never just its text.

## UI

Follow root `BUILD.md` (order + status). Update it when adding a screen. MVVM starts with the first real screen. No SwiftData. Home matches Profile pager chrome: **For you** (default, mixed covers) plus four style tabs on one row with the filter icon, style-tinted glass header, tab-bar footer fade, Apply-only Life areas + Moods sheet. Settings lives on Profile only. For you calls `GET /feed` with no style. Each style tab calls `GET /feed?style=` the first time it opens, keeps its own page and scroll, and opens on that angle. `HomeFeedShelf.swift` holds one card record and one shelf per tab, so a heart, follow, or removal stays in sync. A filter clears every shelf and reloads the one on screen. Pull-to-refresh and load-more touch only that shelf. Profile and author pages still filter one library list in memory. Profile is identity (avatar, session name) plus five expanding tabs: Hearts first, then the four styles. Those style tabs keep owned cards that have that angle and open on it; there is no For you tab on Profile. Home and Profile share `StyleTabPager.swift` for chips and wash scrubbing.

Home, Profile library, and compose cards do not flip: avatar/date/actions, thought, divider, one selected answer, then style chips and the selected style's heart are visible together. Profile Hearts use equal-height answer/thought flips. The top ⋯ and long press reuse the same applicable actions. Original/English swaps inline. Card identity is `card.id`; a heart must not reset style selection. Chip/wash animation belongs only to a user chip tap.

## Device

Always install and launch on **Joe’s iPhone**. Never treat a Simulator `xcodebuild` as verification.

- Destination: `id=E5C20243-B9B7-571E-9EEA-14FC441C13B7`
- Bundle: `app.angles.ios`

```bash
cd AnglesApp
xcodebuild -project AnglesApp.xcodeproj -scheme AnglesApp -configuration Debug \
  -destination 'id=E5C20243-B9B7-571E-9EEA-14FC441C13B7' \
  -derivedDataPath DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device E5C20243-B9B7-571E-9EEA-14FC441C13B7 \
  DerivedData/Build/Products/Debug-iphoneos/Angles.app
xcrun devicectl device process launch --device E5C20243-B9B7-571E-9EEA-14FC441C13B7 \
  app.angles.ios
```
