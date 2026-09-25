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

- [ ] Set Release `ANGLES_API_BASE_URL` to the operator-owned production HTTPS API.
- [ ] Set Release `ANGLES_PRIVACY_POLICY_URL` and `ANGLES_TERMS_OF_SERVICE_URL`.
- [ ] Set either `ANGLES_SUPPORT_URL` or `ANGLES_SUPPORT_EMAIL`.
- [ ] Open all three destinations from the archived app.
- [ ] Confirm bundle ID, Apple team, signing, Sign in with Apple, In-App Purchase, version/build, export compliance, and privacy manifest.

## Production backend

- [ ] Create Railway API, Postgres, private avatar bucket, and HTTPS domain.
- [ ] Configure `DATABASE_URL`, `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `APPLE_CLIENT_ID`, and a production `APPLE_CLIENT_SECRET`.
- [ ] Configure `COOK_SIGNING_KEY` and a separate 32+ character `METERING_HMAC_KEY`.
- [ ] Configure `MISTRAL_API_KEY`, `GEMINI_API_KEY`, and `DEEPSEEK_API_KEY`.
- [ ] Configure `APPLE_ROOT_CERTIFICATES_BASE64` and numeric `APPLE_APP_ID`.
- [ ] Configure `BUCKET`, `ACCESS_KEY_ID`, `SECRET_ACCESS_KEY`, `REGION`, `ENDPOINT`, and `S3_URL_STYLE`.
- [ ] Set `SUBSCRIPTION_ENFORCEMENT=required` and `USAGE_ENFORCEMENT=required`.
- [ ] Deploy and verify runtime migrations, `/health`, Apple login, avatar upload, taste, purchase sync, 600-credit period creation, cook/save, report, block, and account deletion.

## Apple and subscriptions

- [ ] App Store Connect app record, Sign in with Apple configuration, agreements, tax, banking, and any required App Store Server API issuer/key/private-key setup are complete.
- [ ] Monthly and annual products use `app.angles.ios.monthly` and `app.angles.ios.annual`, are localized, priced at `$4.99` and `$39.99`, and are included with the submitted version.
- [ ] Configure App Store Server Notifications V2 to `https://<production-api>/app-store/notifications`.
- [ ] Send Apple's test notification and confirm a verified `200` response.
- [ ] Test new purchase, restore, renewal, expiry, billing retry/grace where available, refund/revocation, and transaction ownership conflict.

## Providers and operations

- [ ] Use production-only provider keys.
- [ ] Set Mistral organization/workspace caps and alerts.
- [ ] Set a Gemini project/prepay cap and bounded reload.
- [ ] Keep the DeepSeek prepaid balance deliberately small and monitored.
- [ ] Verify current provider prices against `LLM_RATE_VERSION`.
- [ ] Define who responds when a provider cap, Railway alert, failed migration, or notification failure occurs.

## Legal and App Store submission

- [ ] Replace every legal operator/contact/address/governing-law placeholder and complete the provider-retention/training review.
- [ ] Publish privacy policy and terms at the configured URLs.
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
