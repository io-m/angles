# Release checklist

## Repository verification

- [ ] Review `git status` and confirm the release contains only intended changes.
- [ ] From `backend/`, run `pnpm install --frozen-lockfile`.
- [ ] Run `pnpm typecheck`, `pnpm build`, and `pnpm test` with the test Postgres database available.
- [ ] Run `pnpm db:migrate` against a disposable production-shaped database and confirm a second run is idempotent.
- [ ] Build the backend container and verify it starts as the non-root user, applies packaged migrations, and reports healthy at `/health`.
- [ ] Confirm the production seed guard refuses `pnpm db:seed-community`.
- [ ] Run `git diff --check` and the documentation stale-phrase searches.

## Release app configuration

- [x] Set Release `ANGLES_API_BASE_URL` to the operator-owned production HTTPS API (`https://api-production-61c9.up.railway.app`).
- [x] Set `ANGLES_SUPPORT_EMAIL` to `info@bithavn.app`.
- [x] Set Release `ANGLES_PRIVACY_POLICY_URL` and `ANGLES_TERMS_OF_SERVICE_URL` to `https://useangles.app/privacy` and `/terms`.
- [x] Set `ANGLES_SUPPORT_URL` to `https://useangles.app/support`.
- [ ] Open all three destinations from the archived app.
- [ ] Confirm bundle ID, Apple team, signing, Sign in with Apple, In-App Purchase, version/build, export compliance, and privacy manifest.

## Production backend

- [x] Create Railway API, Postgres, private avatar bucket, and HTTPS domain.
- [x] Configure `DATABASE_URL`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `APPLE_CLIENT_ID`, and a production `APPLE_CLIENT_SECRET`. The secret expires on 3 April 2027.
- [x] Configure `COOK_SIGNING_KEY` and a separate 32+ character `METERING_HMAC_KEY`.
- [x] Configure `MISTRAL_API_KEY`.
- [x] Configure `OPENAI_API_KEY`; remove the retired provider keys.
- [x] Configure `APPLE_ROOT_CERTIFICATES_BASE64` and numeric `APPLE_APP_ID` (`6811873869`).
- [x] Configure `BUCKET`, `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`, `REGION`, `ENDPOINT`, and `S3_URL_STYLE`.
- [x] Set `SUBSCRIPTION_ENFORCEMENT=required` and `USAGE_ENFORCEMENT=required`.
- [ ] Configure `RESEND_API_KEY`, `REPORT_ALERT_FROM` (a sender on a domain verified in Resend), and `REPORT_ALERT_TO`. Without them the API logs `report_alerts_disabled` at startup and the 24-hour review promise has no trigger.
- [ ] Deploy the release-gaps backend (migrations `0018_report_review` and `0019_terms_acceptance` run at startup) before any build 9 reaches TestFlight: build 9 calls `PUT /profile/terms`, and an older API answers 404 there, which keeps a paid account on the Terms screen.
- [ ] Report a test card from a second account and confirm the alert email arrives; then run `railway ssh --service api --environment production node dist/scripts/reports.js` and `... reports.js keep <cardId>` it.
- [ ] Delete a test account and confirm no `apple_revoke_exchange_failed` or `apple_revoke_failed` in the Railway logs, and that Settings → Apple ID → Sign in with Apple no longer lists Angles.
- [ ] Deploy and verify runtime migrations, `/health`, Apple login, avatar upload, taste, purchase sync, 600-credit period creation, cook/save, report, block, and account deletion. Deployed 2 October 2026; `/health` is `{"status":"ok","db":"ok"}`. The rest still needs a device pass.

## Apple and subscriptions

- [ ] App Store Connect app record, Sign in with Apple configuration, agreements, tax, banking, and any required App Store Server API issuer/key/private-key setup are complete.
- [ ] Monthly and annual products use `app.angles.ios.monthly` and `app.angles.ios.annual`, are localized, priced at `$4.99` and `$39.99`, and are included with the submitted version.
- [ ] Configure App Store Server Notifications V2 to `https://<production-api>/app-store/notifications`.
- [ ] Send Apple's test notification and confirm a verified `200` response.
- [ ] Turn on Billing Grace Period in App Store Connect (Subscriptions → Billing Grace Period). Without it, a failed renewal locks the app at once: billing retry after grace does not unlock.
- [ ] Test new purchase, restore, renewal, expiry, billing retry/grace where available, refund/revocation, and transaction ownership conflict.

## Providers and operations

- [ ] Use production-only provider keys.
- [ ] Set Mistral organization/workspace caps and alerts.
- [ ] Set an OpenAI project budget and usage alerts.
- [ ] Confirm OpenAI API input/output sharing is off.
- [ ] Verify current provider prices against `LLM_RATE_VERSION`.
- [ ] Define who responds when a provider cap, Railway alert, failed migration, or notification failure occurs.

## Legal and App Store submission

- [x] Replace every legal operator/contact/address/governing-law placeholder. The 2 October 2026 privacy policy names the providers and countries, and says paid API terms do not allow training on inputs. Confirm that against the provider accounts before submission.
- [x] Publish privacy policy and terms at `https://useangles.app/privacy` and `/terms`. Support is at `/support`. Republished 2 October 2026.
- [ ] Complete App Privacy labels from actual app/server behavior.
- [ ] Complete the age rating for AI-generated content, mental-health themes, and public user-generated content.
- [ ] Upload final screenshots for required device sizes and any preview media.
- [ ] Complete metadata, review contact, version notes, and subscription review screenshots.
- [ ] Paste the factual path from `docs/app-review-notes.md`; provide no demo credentials.

## Physical-device release gate

- [ ] Unlock Joe's iPhone and keep it connected/trusted.
- [ ] Build Release for device `E5C20243-B9B7-571E-9EEA-14FC441C13B7`.
- [ ] Install the Release app with `devicectl`; a Simulator build does not count.
- [ ] Launch bundle `app.angles.ios` with `devicectl`.
- [ ] Complete the entire reviewer path on the installed Release build against production.
- [ ] Archive, validate, upload, process in TestFlight, and repeat the critical path from the TestFlight build before submission.
