# Angles

Private iOS app: type a negative thought, get it reframed in Stoic, Optimistic, Humorous, or Tough Love. No public feed in v1. Paid-only after one onboarding taste.

This repository is **scaffold only**. Networking, types, and agent docs are in place. Screens/UI, auth, database, and a real LLM provider come next.

## Layout

```
backend/     Hono API (Node) — Railway-ready
AnglesApp/   SwiftUI iOS 17+ app (XcodeGen)
```

## Backend (local)

Requires Node 22+ and pnpm.

```bash
cd backend
cp .env.example .env   # optional for the mock LLM
pnpm install
pnpm dev
```

API listens on `http://localhost:8787`.

- `GET /health` → `{ "status": "ok" }`
- `POST /reframe` → `{ "text": string, "styles": string[] }` → `{ "results": [{ "style", "reframe" }] }`

Other scripts: `pnpm test`, `pnpm typecheck`, `pnpm build`.

The LLM lives behind `backend/src/lib/llmClient.ts` (`generateReframe`). It is a mock until a provider is chosen. The iOS app must never call an LLM with a client-side key.

Native `URLSession` does not use browser CORS. This API does not send CORS headers.

## iOS app → local backend

1. Start the backend (`pnpm dev` in `backend/`).
2. Open `AnglesApp/AnglesApp.xcodeproj` (or run `xcodegen generate` in `AnglesApp/` if the project file is missing).
3. Run on the **iOS Simulator**. Debug builds use `http://localhost:8787` (`AppConfig.swift`).
4. On a **physical device**, localhost is the phone. Temporarily point `AppConfig` at your Mac's LAN IP (e.g. `http://192.168.x.x:8787`). `NSAllowsLocalNetworking` is enabled; do not turn on `NSAllowsArbitraryLoads`.

Bundle ID placeholder: `app.angles.ios`. Attach your Apple team in Xcode before device runs.

## Railway (later)

Do not add `railway.json` / `railway.toml` (Config as Code is deprecated for new services). When you create the project:

- Service root: `backend/`
- Use the `backend/Dockerfile`, or Railpack with `pnpm build` / `pnpm start`
- Health check path: `/health`
- Bind `PORT` (the server already reads `process.env.PORT`)
- Postgres + Drizzle and Better Auth are planned; not in this scaffold
- Project-level IaC, when you need it, is `.railway/railway.ts` via the Railway CLI

## Constraints

Do not invent screens, auth, a database, or extra product features in this pass.
