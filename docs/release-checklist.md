# Release checklist

Current as of **2 October 2026**. Version **1.0**, build **10** is uploaded, in TestFlight, and attached to the version in App Store Connect. The App Store Connect record is `6811873869` (Angles: Reframe Thoughts).

Everything under "Left to do" needs you: a dashboard the API cannot reach, your phone, or your judgement. Everything under "Done" was checked through the App Store Connect API, Railway, or the device.

## Left to do, in order

### 1. App Privacy (about 10 minutes)

[App Store Connect → Angles → App Privacy](https://appstoreconnect.apple.com/apps/6811873869/distribution/privacy). Apple has no API for this page.

- Privacy Policy URL: `https://useangles.app/privacy` (already set on App Information; confirm it shows here).
- "Do you or your third-party partners collect data from this app?" **Yes**.
- Select exactly these data types. For each one answer: **linked to the user: Yes**, **used for tracking: No**.

| Category | Data type | Purposes |
| --- | --- | --- |
| Contact Info | Name | App Functionality |
| Contact Info | Email Address | App Functionality |
| Health & Fitness | Health | App Functionality, Product Personalization |
| User Content | Photos or Videos | App Functionality |
| User Content | Other User Content | App Functionality, Product Personalization |
| Identifiers | User ID | App Functionality |
| Purchases | Purchase History | App Functionality |
| Usage Data | Product Interaction | App Functionality, Product Personalization |

Leave everything else unchecked, including Diagnostics (there is no crash SDK) and Advertising. This matches `AnglesApp/AnglesApp/PrivacyInfo.xcprivacy`; if one changes, change the other. Then **Publish**.

### 2. Report alert email (about 10 minutes)

The Terms and the review notes promise a review of every report within 24 hours. The API sends an email for each new report once these are set; until then it logs `report_alerts_disabled`.

1. In [Resend → Domains](https://resend.com/domains), add and verify a sending domain you own (for example `useangles.app`): add the DNS records it shows.
2. In [Resend → API Keys](https://resend.com/api-keys), create a key with "Sending access".
3. Set the three variables on the Railway `api` service (production). Railway redeploys on save:
   - `RESEND_API_KEY` = the key
   - `REPORT_ALERT_FROM` = for example `Angles reports <reports@useangles.app>`
   - `REPORT_ALERT_TO` = `info@bithavn.app` (or whoever reviews reports)
4. Check: after the redeploy, the Railway log no longer shows `report_alerts_disabled`.

To review reports: `railway ssh --service api --environment production node dist/scripts/reports.js` lists open reports; add `hide <cardId>`, `keep <cardId>`, `delete <cardId>`, `suspend <userId>`, or `unsuspend <userId>`.

### 3. Walk the reviewer path on TestFlight build 10 (about 20 minutes)

Delete Angles from the phone first, then install build 10 from TestFlight (internal group "Angles team"). The production database was emptied on 2 October 2026, so this is a brand-new account.

1. Continue with Apple. The taste opens on "Welcome to Angles … Your first thought is free."
2. Type a thought and tap Send. "Before you start" appears; tap Agree and continue.
3. Answer any follow-up, see the angles, Save to private library.
4. The paywall opens. Buy Monthly or Yearly with the sandbox prompt (no charge).
5. Home opens. Post **5 to 10 public cards** with Inspire me (Save defaults to Post). App Review needs other people's cards on Home to test Report and Block; your cards count as another person to them.
6. From a second Apple ID (or ask a friend on TestFlight), report one of your cards. Check that the alert email arrives (needs step 2), then run the reports script above and `keep` it.
7. Settings → Delete account on a test account. Apple's sheet asks to confirm; afterwards Settings → Apple ID → Sign in with Apple must no longer list Angles. Railway logs must show no `apple_revoke_exchange_failed` or `apple_revoke_failed`.

### 4. Screenshots (about 20 minutes)

- **App screenshots:** App Store Connect → version 1.0 → iPhone 6.9" Display. 3 to 10 images at 1320 × 2868 or 1290 × 2796 portrait (Joe's iPhone 14 Pro Max takes 1290 × 2796). Show real use, not only login or the paywall (guideline 2.3): Home with cards, the four angles of one thought, a card opened, Profile, the widget.
- **Subscription review screenshot:** one paywall screenshot uploaded on **each** subscription ([Angles Yearly and Angles Monthly](https://appstoreconnect.apple.com/apps/6811873869/distribution/subscriptions)). Until both have one they stay "Missing Metadata" and cannot be submitted.

The agent can take these on the phone if it is unlocked and on the screen asked for.

### 5. Provider and operations safety (about 15 minutes)

- [Mistral console](https://console.mistral.ai/): set a monthly spend limit for the workspace.
- [OpenAI → Limits](https://platform.openai.com/settings/organization/limits): set a project budget and email alerts.
- [OpenAI → Data controls](https://platform.openai.com/settings/organization/data-controls/sharing): confirm sharing inputs and outputs is **off** (the privacy policy says providers do not train on what users write).
- Decide who watches Xcode Organizer crash reports, Railway alerts, and the report emails during review and launch week.
- Calendar reminder: the Sign in with Apple client secret (`APPLE_CLIENT_SECRET`, key `W4R8326VMT`) expires on **3 April 2027**. Renew it before then or sign-in and revocation stop working.

### 6. Submit

App Store Connect → Angles → version 1.0:

1. Check that the build is **10**.
2. Under "In-App Purchases and Subscriptions", select **both** Angles Yearly and Angles Monthly. First subscriptions must be submitted with the binary.
3. Re-read the review notes. Keep "reports are reviewed within 24 hours" only if step 2 is done and someone acts on the emails.
4. **Add for Review**, then **Submit for Review**.

Release is set to **manual**: after approval, press Release yourself.

## Done

### Apple account (shared with Thinline)

- Paid Apps agreement, tax, banking, and EU trader (DSA) status are account-level and already active: Thinline (same team `36U79UTZM9`) is live with approved subscriptions in 174 territories.

### App Store Connect, set through the API on 2 October 2026

- Subscription group **Angles Membership** with **Angles Yearly** (`app.angles.ios.annual`, $39.99) and **Angles Monthly** (`app.angles.ios.monthly`, $4.99). Names and descriptions say "600 credits every month" (they used to say "Unlimited", which is not true). Both have a review note and prices in all 175 territories.
- Billing Grace Period **on**: 16 days, all renewals, production and sandbox.
- App Store Server Notifications **V2**, production and sandbox: `https://api-production-61c9.up.railway.app/app-store/notifications`. Apple's sandbox test notification was delivered and the API answered 200.
- Price **Free**; available in 174 territories, all but mainland China (generative AI apps need a licence there).
- App information: subtitle "See a hard thought differently", privacy policy URL, category **Health & Fitness** with **Lifestyle** second, content rights "no third-party content".
- Age rating **13+** (matches the Terms' minimum age): user-generated content, social features, health and wellness topics, mild mature themes, mild crude humour.
- Version 1.0 listing: description (no medical claims; Terms and Privacy links; full auto-renew text), keywords, promotional text, support `https://useangles.app/support`, marketing `https://useangles.app`, copyright "2026 Bithavn", release type manual.
- App Review details: Josip Miljak, `info@bithavn.app`, +45 50 65 97 20, no demo account, notes from [app-review-notes.md](app-review-notes.md).
- TestFlight internal group **Angles team** (all builds) with `miljak.josip@outlook.com`. Builds 9 and 10 uploaded; 10 is `APP_STORE_ELIGIBLE` (not built with beta tools) and attached to 1.0.

### Code and backend (BUILD.md row 20)

- Report alerts (Resend, ids and reason only) and the operator reports script, shipped inside the API image.
- Sign in with Apple revocation on account delete.
- Terms acceptance stored on the server and required before Home.
- "Not therapy" row on Before you start, Email support in Settings, empty app icon set removed, README fixed.
- Free taste fixed in production: it used to read as 0 credits, so "You're out of credits" showed and Send was disabled. The taste screen now welcomes new accounts.
- A reinstall starts at Continue with Apple instead of resuming the old Keychain session.
- Backend: typecheck, 614 tests pass. iOS: 62 tests pass on Joe's iPhone. Release builds 9 and 10 installed and launched on the phone.
- Production deployed with migrations `0018` and `0019`; `/health` is ok. Production data was emptied on 2 October 2026 (migration history kept).
- Provider rates in `LLM_RATE_VERSION` `2026-10-providers-v1` match current prices (Mistral Small $0.15 / $0.60, gpt-4.1-mini $0.40 / $1.60 per million tokens).

## Before every later upload

- From `backend/`: `pnpm typecheck` and `pnpm test` (needs the local test Postgres).
- Bump `CURRENT_PROJECT_VERSION` for both targets in `AnglesApp/project.yml`, run `xcodegen generate`.
- Deploy the backend before a build that depends on it reaches TestFlight.
- Install and launch the Release build on Joe's iPhone with `devicectl`; a Simulator build does not count.
