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

Follow root `BUILD.md` (order + status). Update it when adding a screen. MVVM starts with the first real screen. No SwiftData. There is no tab bar. Home is the card stack. Profile and author pages are sheets. The stack has a header (filter, notifications, Settings) and an action row: Rewind, Pass, Inspire me (compose), Love, Profile. `StackDeck.swift` is the pure deck (checked angles, decision rows, multi-step rewind, `seen`); `StackModel.swift` owns visits, paging, and the serial `DecisionWriter` that `HomeViewModel` shares, so a list reload keeps pending saves. Profile has custom Yours | Loved tabs (icon, title, sliding underline), both plain lists of the old feed card. The stack's drag lives in `StackDrag` and only the views that move read it; keep it that way so a drag frame never redraws the header or the action row.

Every card is `AngleCardFace`: author or From Angles, life area, the full thought, a labelled angle bar, and the answer stage. `.stack` fills a fixed frame: the thought as large as fits, icon style pills, and the answer at one size per card from `AngleTypeFit` (accessibility sizes scroll); `.list` is the old feed card (thought, divider, answer, pills and heart). Tap halves step angles on the stack; the card drags freely but only sideways decides. The ⋯ reuses the same applicable actions. Original/English swaps inline. Card identity is `card.id`; a save must not reset the angle on screen.

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
