# App Store readiness

Current as of **October 2, 2026**.

## Release status

The production feature work is implemented in the repository. The app is not ready to submit or operate publicly until the external configuration and App Store assets below are completed.

### Implemented

- Sign in with Apple through Better Auth, Keychain bearer sessions, server-owned users, log out, and in-app account deletion.
- Account-scoped onboarding: Apple sign-in first, one server-tracked taste while both taste timestamps are empty, a private taste save, then the hard paywall.
- StoreKit 2 annual and monthly purchase, restore, renewal/expiry handling, Settings subscription status, plan management, and cancellation handoff to Apple.
- Server-side verification of signed App Store transactions and Server Notifications V2, account-bound entitlements, idempotent notification processing, and subscription enforcement after the taste.
- A server-owned allowance of 600 credits per monthly membership period for both products. A ready cook or recook costs 1 credit; continue, safety, and failed operations cost 0 user credits.
- Server-side model routing per step with a fallback provider, 20% and 10% warnings, reset information, request idempotency, and daily/burst abuse limits. The app has no model picker.
- Provider token usage and estimated/reported company cost recorded for every real provider attempt without storing thought text in the metering ledger.
- Public/private cards, community Home, follows, per-angle hearts, reporting, blocking/unblocking, and pre-publication moderation.
- Production hardening: runtime migrations before schema checks, production configuration fail-fast validation, a production seed guard, a non-root container with a health check, and Postgres-backed backend CI.
- Source privacy/terms documents, privacy manifest, Release-safe plist split, and centralized API/legal/support configuration.
- App Review readiness (`BUILD.md` row 19, October 2, 2026):
  - The Release API URL points at the Railway production API.
  - Both privacy manifests declare UserDefaults (CA92.1 app, 1C8F.1 app group) and the collected Health and Product Interaction types.
  - The paywall leads with the billed price, shows the renewal terms, Restore, Terms of Use, and Privacy under Continue, and links Apple's EULA in the (i) sheet.
  - A one-time **Before you start** sheet names the AI providers and carries the Terms acceptance before the first Send.
  - Log out and Delete account are in the paywall's (i) sheet.
  - A used-up taste routes to the paywall.
  - The subscription sync never answers 401, and a deleted account's purchase moves to the same Apple ID's new account.
  - The Terms have the zero-tolerance and as-soon-as-possible report text plus the Apple EULA clause. The privacy policy has the providers, moderation, Home ordering, legal bases, transfers, and the Datatilsynet line.
- Release gaps (`BUILD.md` row 20, October 2, 2026; build 9):
  - Each new report emails the operator through Resend (ids and reason only). `pnpm reports` lists open reports and hides, keeps, or deletes a card, or suspends an author's publishing.
  - Delete account confirms with Apple first and the server revokes the Sign in with Apple grant (guideline 5.1.1(v)).
  - Terms acceptance is stored on the server (`users.terms_accepted_at`). A paid account that has not accepted it sees **Before you start** before Home, on any device.
  - **Before you start** says Angles is not therapy or a crisis service. Settings has Email support. The empty `AppIcon.appiconset` is gone (the icon is `Angles.icon`).

`POST /reframe` does not store cards or plaintext thought text. It does write text-free operation, idempotency, usage, token, and company-cost metadata, plus an hour-long replay of the finished response encrypted under a key only the device holds. A card is stored only when the signed cook is sent to `POST /cards`.

## Remaining external blockers

**The current, ordered list of what is left is [release-checklist.md](release-checklist.md) ("Left to do").** On 2 October 2026 the subscriptions, Grace Period, server notifications, pricing and availability, listing, age rating, review details, and TestFlight were set through the App Store Connect API; the notes below are background.

### Release app configuration

- The Release `ANGLES_API_BASE_URL` is `https://api-production-61c9.up.railway.app` (the `api` service in the Railway `angles` project).
- `ANGLES_PRIVACY_POLICY_URL`, `ANGLES_TERMS_OF_SERVICE_URL`, and `ANGLES_SUPPORT_URL` are set to `https://useangles.app/privacy`, `/terms`, and `/support` in Debug and Release.
- Verify those destinations load from the archived build once `useangles.app` is serving them.
- Confirm the final Apple team, signing, bundle record, capabilities, and Release archive/export configuration.

### Hosted legal and support

- Operator details in `docs/legal/privacy.md` and `docs/legal/terms.md` name Bithavn, CVR 46705130, `info@bithavn.app`, the Copenhagen postal address, and Danish law.
- The privacy policy names Mistral AI (France) and OpenAI (US), and says each is used through a paid API whose terms forbid training on inputs. Confirm both provider accounts before submission; in OpenAI, keep API input/output sharing off.
- The site is published at `https://useangles.app` (`/privacy`, `/terms`, `/support`). `www` and plain HTTP redirect to that host. The 2 October 2026 Terms and Privacy text is live.
- Set `RESEND_API_KEY`, `REPORT_ALERT_FROM`, and `REPORT_ALERT_TO` on Railway, and name who acts on a report email as soon as possible during review and launch (`railway ssh --service api --environment production node dist/scripts/reports.js`); the Terms and the review notes promise review as soon as possible.
- Deploy the backend with migrations `0018` and `0019` before build 9 goes to TestFlight.

### Apple production configuration

- Production `APPLE_ROOT_CERTIFICATES_BASE64` is set. The local `backend/.env` has the same certificates, so sandbox receipt sync works on this machine. That file is not in git.
- Production `APPLE_APP_ID` is `6811873869` (Angles: Reframe Thoughts).
- Production `APPLE_CLIENT_SECRET` is a Sign in with Apple JWT for key `W4R8326VMT`, team `36U79UTZM9`, client `app.angles.ios`. It expires on 3 April 2027. Renew it from `~/Downloads/AuthKey_W4R8326VMT.p8` before then. Still open: product and subscription-group availability, agreements, tax, banking, and any App Store Server API issuer/key/private-key setup used by release operations.
- Configure App Store Server Notifications V2 for the production API endpoint `POST /app-store/notifications` and send/verify Apple's test notification.
- Confirm the production bundle ID and product IDs are exactly `app.angles.ios`, `app.angles.ios.monthly`, and `app.angles.ios.annual`.

### Railway and infrastructure

- The Railway `angles` project, `api` service, production Postgres, and private `angles-avatars` bucket exist. The API is deployed at `https://api-production-61c9.up.railway.app` and `/health` returns `{"status":"ok","db":"ok"}`.
- Production has the database URL, Better Auth secret and URL, cook signing key, metering HMAC, both model provider keys, Apple verification material, bucket credentials, and both `SUBSCRIPTION_ENFORCEMENT=required` and `USAGE_ENFORCEMENT=required`.
- Still to confirm on a real device: authentication, purchase sync, notification delivery, avatar storage, and a full cook/save cycle.
- Never run the destructive community seed against production; the production guard must remain enabled.

### Provider operations

- Configure production keys separately from local/CI keys.
- Set Mistral organization/workspace spend limits and OpenAI project budget and usage alerts.
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
