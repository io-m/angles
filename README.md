# Angles

Private iOS app: type a negative thought, get it reframed in Stoic, Optimistic, Humorous, or Tough Love. Private by default; optional anonymous publish into a community Home is postponed. Paid-only after one onboarding taste.

What to build next lives in [`BUILD.md`](BUILD.md) — update that file whenever a screen or feature lands.

## Layout

```
backend/     Hono API (Node) — Railway-ready
AnglesApp/   SwiftUI iOS 17+ app (XcodeGen)
```

## Postgres (local)

From the repo root:

```bash
docker compose up -d
cd backend
pnpm db:migrate
```

Postgres listens on host port **5433** (`angles` / `angles_test`). `DATABASE_URL` and `DATABASE_URL_TEST` are in `backend/.env.example`.

Other DB scripts: `pnpm db:generate`, `pnpm db:studio`. The API does not auto-migrate; if the schema is behind it fails on boot.

## Backend (local)

Requires Node 22+ and pnpm.

```bash
cd backend
cp .env.example .env   # set MISTRAL_API_KEY (default model) and DATABASE_URL
pnpm install
pnpm dev
```

API listens on `http://localhost:8787` (bind `0.0.0.0`). A physical device must use the Mac LAN IP, not localhost.

- `GET /health` → `{ "status": "ok", "db": "ok" }` (503 when Postgres is down)
- `POST /reframe` → `{ "text": string, "followUps"?: { question, answer }[], "styles"?: Style[], "model"? }` → `{ "kind": "continue", ... }` or `{ "kind": "ready", "thought", "results", "meta" }`. Never writes a card.
- `POST /cards` → save a kept cook. `GET /cards` is the Profile library.

Other scripts: `pnpm test`, `pnpm typecheck`, `pnpm build`.

The LLM lives behind `backend/src/lib/llmClient.ts` (`generateReframe`). Default `LLM_MODEL` is `mistral-small-latest`. Also wired: `gemini-3.8-flash`, `deepseek-flash`, `deepseek-v4-pro`. The iOS app must never call an LLM with a client-side key.

Native `URLSession` does not use browser CORS. This API does not send CORS headers.

## iOS app

The overlay cooks through `ReframeService` / `POST /reframe`. Save uses `CardsService` / `POST /cards`. Profile loads the library from `GET /cards`.

Debug `AppConfig.baseURL` is the Mac LAN IP on port 8787 (devices cannot use localhost). `NSAllowsLocalNetworking` is enabled; do not turn on `NSAllowsArbitraryLoads`.

Bundle ID placeholder: `app.angles.ios`. Attach your Apple team in Xcode before device runs.

## Railway (later)

Do not add `railway.json` / `railway.toml` (Config as Code is deprecated for new services). When you create the project:

- Service root: `backend/`
- Use the `backend/Dockerfile`, or Railpack with `pnpm build` / `pnpm start`
- Health check path: `/health`
- Bind `PORT` (the server already reads `process.env.PORT`)
- Better Auth is still later
- Project-level IaC, when you need it, is `.railway/railway.ts` via the Railway CLI

## Constraints

Follow [`BUILD.md`](BUILD.md). Do not invent screens, auth, or extra product features outside that order.
