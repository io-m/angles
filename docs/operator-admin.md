# Operator admin

Private review for Angles reports. Sign in at `https://useangles.app/admin`. The home page is an overview with a sidebar (Open queue, Reviewed, sign out): open, private, suspended, and reviewed counts, then one tile per report reason. Tapping a tile filters the list. Search takes a card id, a user id, an email, or a few words from the thought. A card opens as two columns: the thought and answers with Keep, Hide, and Delete on the left, the author and their other public cards on the right. Only addresses in `ADMIN_OPERATOR_EMAILS` receive a link. Everyone else gets the same “check your inbox” page and no email.

Report mail is unchanged: ids and a reason, no card text. Open the card from that id on the site. `pnpm reports` over SSH still works when the site is down:

```bash
railway ssh --service api --environment production node dist/scripts/reports.js
railway ssh --service api --environment production node dist/scripts/reports.js keep <cardId>
```

## Auth

Magic link via Resend, not Sign in with Apple and not Cloudflare Access.

1. The operator enters an email at `/admin/login`.
2. Railway emails `https://useangles.app/admin/login/verify#t=…` only when the address is allowlisted. The token is in the URL fragment, so it is not in access logs.
3. The page posts the token to same-origin `/api/admin/login/verify`. The link works once and expires in 15 minutes.
4. The worker stores the session in an HttpOnly cookie, `angles_admin`, `Path=/api/admin`, for 12 hours.

The marketing site is a static export. It does not talk to Postgres. `web/worker.ts` proxies `/api/admin/*` to Railway `/admin/*` and adds `X-Angles-Admin-Proxy`. The browser never sees `ADMIN_PROXY_SECRET`, `ADMIN_SESSION_SECRET`, or `DATABASE_URL`.

## Routes

| Method | Path | What it does |
| --- | --- | --- |
| POST | `/admin/login/request` | `{ email }`. Always `{ ok: true }` for a valid address. |
| POST | `/admin/login/verify` | `{ token }` sets the session cookie. |
| POST | `/admin/logout` | Clears the cookie. |
| GET | `/admin/session` | `{ email }` or 401. |
| GET | `/admin/reports` | Open reports, oldest first. Thought excerpt only. |
| GET | `/admin/reports/summary` | Counts for the overview, including one number per reason. |
| GET | `/admin/reports/reviewed` | Latest keep or hide per card. |
| GET | `/admin/search?q=` | Card or user id, or a thought or email fragment. |
| GET | `/admin/reports/:cardId` | Thought, reframes, and author. Works with zero open reports. |
| POST | `/admin/reports/:cardId/keep` | Dismisses open reports. Does not republish. |
| POST | `/admin/reports/:cardId/hide` | Private, and the card cannot be published again. |
| POST | `/admin/reports/:cardId/delete` | Deletes the card. |
| GET | `/admin/users/:userId` | Email, suspended flag, public card count. |
| GET | `/admin/users/:userId/cards` | That account's public cards, as excerpts. |
| POST | `/admin/users/:userId/suspend` | Stops publishing. Cards go private. |
| POST | `/admin/users/:userId/unsuspend` | Lets the account publish again. Cards stay private. |

Hide, keep, delete, suspend, and unsuspend are the same functions as `pnpm reports` (`backend/src/db/reportReview.ts`).

Unknown session: 401 `UNAUTHORIZED`. Email no longer allowlisted: 403 `FORBIDDEN`. Missing admin env: 503 `ADMIN_DISABLED`. That 503 does not take the API down for the app.

## Railway (`api`)

| Variable | Required | Notes |
| --- | --- | --- |
| `ADMIN_OPERATOR_EMAILS` | yes | Comma-separated. `josipmiljak@proton.me,info@bithavn.app` |
| `ADMIN_SESSION_SECRET` | yes | At least 32 characters. `openssl rand -base64 32` |
| `ADMIN_PROXY_SECRET` | production | At least 32 characters. Same value as the Wrangler secret. |
| `ADMIN_APP_ORIGIN` | production | `https://useangles.app`. Local `next dev`: `http://localhost:3000` so the cookie is not `Secure`. |
| `RESEND_API_KEY` | to send links | Already used for report mail. |
| `REPORT_ALERT_FROM` | to send links | From address, unless `ADMIN_MAGIC_FROM` is set. |

Unset session secret or allowlist: startup logs `admin_disabled`. Cooks keep working.

Redeploy the `api` service after setting the variables so migration `0020_admin_login_challenges` runs.

## Cloudflare (`angles-web`)

`ANGLES_API_BASE_URL` is a Wrangler var (`https://api-production-61c9.up.railway.app` in `web/wrangler.jsonc`).

The proxy secret is not in git:

```bash
cd web
pnpm exec wrangler secret put ADMIN_PROXY_SECRET
```

Paste the same value as Railway `ADMIN_PROXY_SECRET`. Then `pnpm deploy` from `web/`. Public pages stay the static export.

## Local

From `backend/`, with the variables above in `.env` (leave `ADMIN_PROXY_SECRET` unset) and Postgres up:

```bash
pnpm dev
```

From `web/`:

```bash
pnpm dev
```

`next dev` rewrites `/api/admin` to `http://127.0.0.1:8787/admin`. Open `http://localhost:3000/admin/login`. Set `ADMIN_APP_ORIGIN=http://localhost:3000` or the browser will drop the `Secure` cookie.
