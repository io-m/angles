# Release checklist

Current as of **5 October 2026**. Version **1.0**. Latest iOS uploads: build **12** (refresh pill; check App Store Connect for **13+** if persistence shipped after). App Store Connect app `6811873869` (Angles: Reframe Thoughts).

Everything under "Left to do" needs you: a dashboard the API cannot reach, your phone, or your judgement.

## Left to do, in order

### 1. App Privacy — done

Published in App Store Connect with the eight data types from this doc (Oct 2026).

### 2. Report alert email — done (production)

Resend domain verified; Railway `api` has `RESEND_API_KEY`, `REPORT_ALERT_FROM`, `REPORT_ALERT_TO`. Redeploy if you change report email copy in `reportAlerts.ts`.

Wording is now **as soon as possible** (not 24 hours) in Terms, consent sheet, review notes, and alert emails. Redeploy **api** for new email body text; redeploy **web** (or publish `useangles.app`) so live Terms match.

To review reports: `railway ssh --service api --environment production node dist/scripts/reports.js` — then `keep`, `hide`, etc.

### 3. TestFlight on production — partly done

**Done:** Fresh install, onboarding, Home/feed on TestFlight against production; Home seeded with real public posts (`josipmiljak@proton.me`).

**Still to do:**

1. **Report + email (wife’s phone):** She installs TestFlight (same internal group or external tester), signs in with **her** Apple ID, opens Home, reports **one of your** public cards (⋯ or long-press → Report). You check `info@bithavn.app`, then SSH `pnpm reports` and `keep <cardId>`.
2. **Delete account (optional throwaway):** On a test account you do not need, Settings → Delete account → confirm Apple sheet. Confirm Sign in with Apple no longer lists Angles; Railway logs show no `apple_revoke_failed`.
3. **Latest build:** Use the newest TestFlight build (persistence + pill fixes). Attach that build to version 1.0 before submit.

Apple Review does not need you to have two Apple IDs; they test Report on your public posts with their account.

### 4. Screenshots — done (4 October 2026)

Uploaded to version 1.0, English, iPhone 6.9". Not submitted yet.

### 5. Provider and operations safety (~15 minutes)

- [Mistral console](https://console.mistral.ai/): monthly spend limit.
- [OpenAI → Limits](https://platform.openai.com/settings/organization/limits): budget + email alerts.
- [OpenAI → Data controls](https://platform.openai.com/settings/organization/data-controls/sharing): training/sharing **off**.
- Decide who watches Organizer crashes, Railway, and report mail during review week.
- Calendar: Apple client secret expires **3 April 2027**.

### 6. Submit

App Store Connect → Angles → version 1.0:

1. Select the **latest** TestFlight build (not 11 if 12/13 is ready).
2. Under subscriptions, attach **both** Angles Yearly and Angles Monthly.
3. Paste review notes from [app-review-notes.md](app-review-notes.md) (as soon as possible report wording).
4. **Add for Review** → **Submit for Review**. Release stays **manual**.

## Done (unchanged summary)

Apple account, subscriptions, grace period, server notifications, listing copy, age rating, review contact details, backend migrations, Resend on Railway, production `/health`, BUILD.md row 20 features, builds 9–12 uploaded, onboarding path verified on device.

## Before every later upload

- `backend/`: `pnpm typecheck` && `pnpm test`
- Bump `CURRENT_PROJECT_VERSION` in `AnglesApp/project.yml`, `xcodegen generate`
- Deploy backend before a build that depends on API changes
- TestFlight on Joe’s iPhone for release verification (not Debug replacing TestFlight unless intentional)
