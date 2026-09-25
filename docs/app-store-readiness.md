# App Store readiness

Current as of **September 25, 2026**.

## Release status

The production feature work is implemented in the repository. The app is not ready to submit or operate publicly until the external configuration and App Store assets below are completed.

### Implemented

- Sign in with Apple through Better Auth, Keychain bearer sessions, server-owned users, log out, and in-app account deletion.
- Account-scoped onboarding: Apple sign-in first, one server-tracked taste while both taste timestamps are empty, a private taste save, then the hard paywall.
- StoreKit 2 annual and monthly purchase, restore, renewal/expiry handling, Settings subscription status, plan management, and cancellation handoff to Apple.
- Server-side verification of signed App Store transactions and Server Notifications V2, account-bound entitlements, idempotent notification processing, and subscription enforcement after the taste.
- A server-owned allowance of 600 credits per monthly membership period for both products. Mistral costs 1 credit, DeepSeek 2, and Gemini 6 for a ready result; continue, safety, and failed operations cost 0 user credits.
- All three public models in the picker with credit-aware availability, fallback to an affordable model, 20% and 10% warnings, reset information, request idempotency, and daily/burst abuse limits.
- Provider token usage and estimated/reported company cost recorded for every real provider attempt without storing thought text in the metering ledger.
- Public/private cards, community Home, follows, per-angle favorites, reporting, blocking/unblocking, and pre-publication moderation.
- Production hardening: runtime migrations before schema checks, production configuration fail-fast validation, a production seed guard, a non-root container with a health check, and Postgres-backed backend CI.
- Source privacy/terms documents, privacy manifest, Release-safe plist split, and centralized API/legal/support configuration.

`POST /reframe` does not store cards or thought text. It does write text-free operation, idempotency, usage, token, and company-cost metadata. A card is stored only when the signed cook is sent to `POST /cards`.

## Remaining external blockers

These are deployment, operator, Apple, provider, and submission tasks; they are not missing product implementations.

### Release app configuration

- Set the Release `ANGLES_API_BASE_URL` to the production HTTPS API.
- Set `ANGLES_PRIVACY_POLICY_URL`, `ANGLES_TERMS_OF_SERVICE_URL`, and either `ANGLES_SUPPORT_URL` or `ANGLES_SUPPORT_EMAIL`.
- Verify those destinations load from the archived build. They are intentionally empty today.
- Confirm the final Apple team, signing, bundle record, capabilities, and Release archive/export configuration.

### Hosted legal and support

- Replace all operator placeholders in `docs/legal/privacy.md` and `docs/legal/terms.md`, including legal operator, privacy/support contact, mailing address, and governing law.
- Complete the provider-retention/training review noted in the privacy policy.
- Publish both documents at operator-controlled HTTPS URLs and provide a working support destination.

### Apple production configuration

- Download and configure the required Apple root certificates in `APPLE_ROOT_CERTIFICATES_BASE64`.
- Set the numeric App Store Connect `APPLE_APP_ID`.
- Create the production Sign in with Apple and App Store configuration, including a valid `APPLE_CLIENT_SECRET`, product/subscription-group availability, agreements, tax, banking, and any App Store Server API issuer/key/private-key setup used by release operations.
- Configure App Store Server Notifications V2 for the production API endpoint `POST /app-store/notifications` and send/verify Apple's test notification.
- Confirm the production bundle ID and product IDs are exactly `app.angles.ios`, `app.angles.ios.monthly`, and `app.angles.ios.annual`.

### Railway and infrastructure

- Create the Railway project, API service, production Postgres database, and private `angles-avatars` bucket.
- Assign the final HTTPS domain and set `BETTER_AUTH_URL` to that origin.
- Configure every required production secret from `backend/.env.example`: database, Better Auth/Apple, cook signing, metering HMAC, all three model providers, Apple verification, and bucket credentials.
- Set both `SUBSCRIPTION_ENFORCEMENT=required` and `USAGE_ENFORCEMENT=required`.
- Deploy, confirm packaged migrations complete, and verify `/health`, authentication, purchase sync, notification delivery, avatar storage, and a full cook/save cycle.
- Never run the destructive community seed against production; the production guard must remain enabled.

### Provider operations

- Configure production keys separately from local/CI keys.
- Set Mistral organization/workspace spend limits, a Gemini project/prepay cap, and a deliberately small DeepSeek prepaid balance.
- Configure spend/balance alerts and operational handling for a provider pause or outage.
- Recheck current provider prices against `LLM_RATE_VERSION` before launch and bump the version when rates change.

### App Store Connect submission

- Complete app name/subtitle/description, keywords, category, copyright, review contact, and version notes.
- Upload final device screenshots and any required preview media.
- Complete App Privacy answers from the shipped privacy manifest and actual backend behavior.
- Complete the age-rating questionnaire with the AI-generated content, mental-health themes, and user-generated public content represented accurately.
- Add the reviewer notes from `docs/app-review-notes.md`; do not provide demo credentials.
- Verify both subscription products, localization, pricing, review screenshots, and the subscription group are submitted with the app version.

## Release gate

Do not submit until all of the following are true:

1. The production API and Postgres are live behind HTTPS with required enforcement enabled.
2. Apple production verification and Server Notifications V2 pass end to end.
3. Release API, legal, and support destinations are non-empty and reachable.
4. Legal placeholders and provider-review notes are resolved on the hosted pages.
5. Provider caps and alerts are active.
6. A signed Release build installs and launches on Joe's unlocked iPhone and completes the reviewer path against production.
7. App Store metadata, screenshots, privacy answers, age rating, and subscription review assets are complete.

Use `docs/release-checklist.md` for the executable checklist and `docs/app-review-notes.md` for App Review.
