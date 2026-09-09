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

- `APIClient.post(path:body:)` — JSON encode, `URLSession`, decode `Decodable`, map failures to `APIError`.
- `ReframeService.getReframes(text:styles:)` — `POST /reframe` only.
- Auth header: TODO on the request in `APIClient`. Do not invent a token store.

## Models

Keep `Style` raw values identical to the backend: `stoic`, `optimistic`, `humorous`, `tough_love`.

## Config

`AppConfig.baseURL`: DEBUG `http://localhost:8787`; Release is a placeholder until Railway exists. Physical devices cannot use localhost.

## UI

Follow root `BUILD.md` (order + status). Update it when adding a screen. MVVM starts with the first real screen. No SwiftData until History.
