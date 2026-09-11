---
name: angles-ios
description: Extend or change the Angles iOS app networking, models, and XcodeGen project. Use when editing Swift under AnglesApp, APIClient, ReframeService, AppConfig, or project.yml.
---

# Angles iOS

## Project

Source of truth is `AnglesApp/project.yml`. After adding or moving Swift files:

```bash
cd AnglesApp && xcodegen generate
```

Target: iOS 17+, bundle id `app.angles.ios` (placeholder). No SPM networking packages.

## Networking

- `APIClient` — JSON `URLSession` verbs (`GET`, `POST`, `PATCH`, `DELETE`), decode `Decodable`, map failures to `APIError`.
- `ReframeService.refine(text:followUps:styles:model:)` — `POST /reframe` only. Answers `.continueTurn` or `.ready`.
- `CardsService` — `POST/GET/PATCH/DELETE /cards`. Profile library source of truth.
- Auth header: TODO on the request in `APIClient`. Do not invent a token store.

## Models

Keep `Style` raw values identical to the backend: `stoic`, `optimistic`, `humorous`, `tough_love`. `ThoughtCategory`, `Timeframe`, `SafetyFlag`, and `IntensityBand` decode unknown values to a safe case on purpose — a new backend value must not fail a whole cook.

A `continue` response keeps the composer up (`HomeViewModel.isComposerVisible`). Never hide it on anything but a finished cook.

## Config

`AppConfig.baseURL`: DEBUG `http://localhost:8787`; Release is a placeholder until Railway exists. Physical devices cannot use localhost.

## UI

Follow root `BUILD.md` (order + status). Update it when adding a screen. MVVM starts with the first real screen. No SwiftData. Home is one newest-first paged feed: its title scrolls under the gradient while filter and Settings stay fixed trailing. Its Apply-only filter uses Life areas + Moods tabs. Profile style chips keep cards that have that style and open on it; All still uses mixed `spotlightStyle`. The Favorite angles strip stays unfiltered (max 6).

Home, Profile library, and compose cards do not flip: avatar/date/actions, thought, divider, one selected answer, then style chips and the selected style's heart are visible together. Profile Favorite angles alone use equal-height answer/thought flips so the horizontal strip remains level. The top ⋯ and long press reuse the same applicable actions. Original/English swaps inline. Card identity is `card.id`; a heart must not reset style selection. Chip/wash animation belongs only to a user chip tap.

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
