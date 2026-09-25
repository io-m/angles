# Angles

iOS app: type a negative thought, get it reframed in Stoic, Optimistic, Humorous, or Tough Love. Every card lives in your private library; posting one also puts it on the community Home. Compose Save defaults to Post, with Save privately one tap away. Paid-only after one onboarding taste.

What to build next lives in [`BUILD.md`](BUILD.md) — update that file whenever a screen or feature lands.

## Layout

```text
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

Other DB scripts: `pnpm db:generate`, `pnpm db:studio`. API startup applies the packaged Drizzle migrations, then verifies that the schema is current.

## Backend (local)

Requires Node 22+ and pnpm.

```bash
cd backend
cp .env.example .env   # set MISTRAL_API_KEY, COOK_SIGNING_KEY, and DATABASE_URL
pnpm install
pnpm dev
```

API listens on `http://localhost:8787` (bind `0.0.0.0`). A physical device must use the Mac LAN IP, not localhost. Product routes require a Better Auth session (`Authorization: Bearer`).

- `GET /health` → `{ "status": "ok", "db": "ok" }` (503 when Postgres is down)
- `POST /reframe` → `{ "text": string, "followUps"?: { question, answer }[], "styles"?: Style[], "model"? }` → `{ "kind": "continue", ... }` or `{ "kind": "ready", "thought", "results", "meta", "signature" }`. It never stores a card or thought text, but it does write text-free metering, idempotency, provider-usage, and company-cost metadata.
- `POST /cards` → save a kept cook, echoing the `/reframe` signatures; anything the server did not sign is rejected. `GET /cards` is the Profile library.
- `GET /profile/usage` → the server-owned 600-credit membership period. Ready results cost Mistral 1, DeepSeek 2, or Gemini 6 credits; continues and failed operations cost 0.
- `POST /profile/subscription/sync` verifies a signed StoreKit transaction. `POST /app-store/notifications` receives App Store Server Notifications V2.

Other scripts: `pnpm test`, `pnpm typecheck`, `pnpm build`.

The LLM lives behind `backend/src/lib/llmClient.ts` (`generateReframe` / `generateJson`). The three public metered models are `mistral-small-latest`, `gemini-3.8-flash`, and `deepseek-flash`; `deepseek-v4-pro` remains catalog-only. The iOS app must never call an LLM with a client-side key.

Native `URLSession` does not use browser CORS. This API does not send CORS headers.

## iOS app

The overlay cooks through `ReframeService` / `POST /reframe`. Save uses `CardsService` / `POST /cards`. Profile loads the library from `GET /cards`.

`AppConfig.baseURL` comes from the `ANGLES_API_BASE_URL` build setting in `AnglesApp/project.yml`: the Mac LAN IP on port 8787 for Debug (devices cannot use localhost), empty for Release until a production host exists. `NSAllowsLocalNetworking` is enabled; do not turn on `NSAllowsArbitraryLoads`.

Bundle ID: `app.angles.ios`. Attach the correct Apple team in Xcode before device runs.

## Production deployment

Do not add `railway.json` / `railway.toml` (Config as Code is deprecated for new services). When you create the project:

- Service root: `backend/`
- Use the `backend/Dockerfile`, or Railpack with `pnpm build` / `pnpm start`
- Health check path: `/health`
- Bind `PORT` (the server already reads `process.env.PORT`)
- Startup applies packaged migrations before serving and fails fast on incomplete production configuration.
- Better Auth is Sign in with Apple. Set every production variable documented in `backend/.env.example`, including Apple verification, subscription/usage enforcement, all three provider keys, and avatar-bucket credentials.
- Project-level IaC, when you need it, is `.railway/railway.ts` via the Railway CLI

Release status and external submission work are tracked in [`docs/app-store-readiness.md`](docs/app-store-readiness.md) and [`docs/release-checklist.md`](docs/release-checklist.md).

## Constraints

Follow [`BUILD.md`](BUILD.md). Do not invent screens or extra product features outside that order.
