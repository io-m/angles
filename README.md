# Angles

Private iOS app: type a negative thought, get it reframed in Stoic, Optimistic, Humorous, or Tough Love. No public feed in v1. Paid-only after one onboarding taste.

This repository is **scaffold only**. Networking, types, and agent docs are in place. What to build next lives in [`BUILD.md`](BUILD.md) — update that file whenever a screen or feature lands.

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
- `POST /reframe` → `{ "text": string, "followUps"?: { question, answer }[] }` → `{ "kind": "clarify", "question", "options" }` or `{ "kind": "ready", "results": [{ "style", "reframe" }] }` (always all four styles).

Other scripts: `pnpm test`, `pnpm typecheck`, `pnpm build`.

The LLM lives behind `backend/src/lib/llmClient.ts` (`generateReframe`). It is a mock until a provider is chosen. The iOS app must never call an LLM with a client-side key.

Native `URLSession` does not use browser CORS. This API does not send CORS headers.

## iOS app

The overlay currently mocks refine on-device (`RefineMock`). `ReframeService` / `POST /reframe` stay for when a real LLM is wired.

Debug `AppConfig.baseURL` is `http://localhost:8787`. `NSAllowsLocalNetworking` is enabled; do not turn on `NSAllowsArbitraryLoads`.

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

Follow [`BUILD.md`](BUILD.md). Do not invent screens, auth, a database, or extra product features outside that order.
