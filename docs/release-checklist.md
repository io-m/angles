# Release checklist

Current as of **6 October 2026**. Version **1.0**. Latest iOS upload: build **25** (Follows row opens iOS Settings; no in-app switch). App Store Connect app `6811873869` (Angles: Reframe Thoughts).

Everything under "Left to do" needs you: a dashboard the API cannot reach, your phone, or your judgement.

## Left to do, in order

### 1. App Privacy — done

Published in App Store Connect with the eight data types from this doc (Oct 2026).

### 2. Report alert email — done (production)

Resend domain verified; Railway `api` has `RESEND_API_KEY`, `REPORT_ALERT_FROM`, `REPORT_ALERT_TO`. Redeploy if you change report email copy in `reportAlerts.ts`.

Wording is now **as soon as possible** (not 24 hours) in Terms, consent sheet, review notes, and alert emails. Redeploy **api** for new email body text; redeploy **web** (or publish `useangles.app`) so live Terms match.

To review reports: [https://useangles.app/admin](https://useangles.app/admin) after the operator env in [operator-admin.md](operator-admin.md) is set. SSH still works: `railway ssh --service api --environment production node dist/scripts/reports.js` — then `keep`, `hide`, etc.

### 3. TestFlight on production — partly done

**Done:** Fresh install, onboarding, Home/feed on TestFlight against production; Home seeded with real public posts (`josipmiljak@proton.me`).

**Still to do:**

1. **Report + email (wife’s phone):** She installs TestFlight (same internal group or external tester), signs in with **her** Apple ID, opens Home, reports **one of your** public cards (⋯ or long-press → Report). You check `info@bithavn.app`, then `keep` that card at [https://useangles.app/admin](https://useangles.app/admin) (or SSH `pnpm reports` and `keep <cardId>`).
2. **Delete account (optional throwaway):** On a test account you do not need, Settings → Delete account → confirm Apple sheet. Confirm Sign in with Apple no longer lists Angles; Railway logs show no `apple_revoke_failed`.
3. **Latest build:** Use TestFlight build **25**. Attach that build to version 1.0 before submit.
4. **Follow push (two TestFlight phones):** see "Follow push" below.

### 3a. Follow push — APNs key (done 6 October 2026)

Key `54XP579X5K` (Sandbox & Production) is on Railway `api`; the logs show `apns_config { configured: true, keyValid: true }` and Apple accepted test pushes with `200`. Keep `AuthKey_54XP579X5K.p8` backed up privately. Test push only on TestFlight builds: a Debug install from Xcode replaces the TestFlight app and cannot receive production pushes.

Before the banner proof: install **TestFlight build 23** (do not replace it with a Debug install). Sign in. If Follows is on, iOS should ask for notifications on first launch of that install — Allow. iOS Settings → Angles then shows Notifications. You should not need Settings → Follows → Turn on notifications after every reinstall.

1. [Apple Developer → Keys](https://developer.apple.com/account/resources/authkeys/list) → **+** → name "Angles APNs", tick **Apple Push Notifications service (APNs)** → Configure: environment **Sandbox & Production**, key restriction **Team Scoped (All Topics)** → Save → Continue → Register → **Download** the `AuthKey_XXXXXXXXXX.p8` (one download only) and note the **Key ID**.
2. Railway `angles` → `api` → Variables, add: `APNS_KEY` (paste the whole `.p8` file, including the BEGIN/END lines), `APNS_KEY_ID` (the Key ID), `APNS_TEAM_ID` = `36U79UTZM9`, `APNS_BUNDLE_ID` = `app.angles.ios`. Saving redeploys.
3. Railway logs for the new deploy must show `apns_config { configured: true, keyValid: true }`. `keyValid: false` means the pasted key is incomplete.
4. Banner proof: on phone A open the bell (so nothing from B is unread), on phone B unfollow A if needed, lock phone A, on phone B follow A. Phone A shows "Angles — XY followed you"; Railway logs show `apns_result { status: 200 }`. A `403 InvalidProviderToken` is the key or Key ID; `400 BadDeviceToken` is a sandbox token on a production build (reinstall from TestFlight); `follow_push_skipped no_token` means that phone never allowed notifications.

### 3b. Follow notifications retest on build 25 (both TestFlight phones)

- Empty bell on a fresh account: "Nothing yet.", no badge.
- One row per person in Follows, even after they unfollow and follow again.
- Follow back from the bell: no dialog, the row turns "Following", the other phone gets "followed you back".
- One open of the bell clears the tab badge and the app icon badge, and they stay clear after background/foreground and a cold relaunch.
- First follow from Home or an author page: only iOS's own dialog, once, unless this install already asked on sign-in. Later follows never ask.
- Reinstall TestFlight, sign in: iOS asks for notifications without opening Settings. After Allow, a follow from the other phone banners.
- After "Don't Allow": Settings → Follows says "Allow in iOS Settings" and opens iOS Settings. No switch.
- When banners are on: Settings → Follows says "On · iOS Settings". Tap opens iOS Settings so they can turn them off. Return: subtitle updates.
- Banners and the list show the display name when set, else initials, else Someone — never thought text or a follower count.
- Lock-screen tap and **View profile** open that person's posts. **Follow back** opens the bell and follows.

Apple Review does not need you to have two Apple IDs; they test Report on your public posts with their account.

### 4. Screenshots — done (4 October 2026)

Uploaded to version 1.0, English, iPhone 6.9". Not submitted yet.

### 5. Provider and operations safety — done (5 October 2026)

- **Mistral:** €20 prepaid credits, auto-recharge **off** (Billing has no monthly limit on this account; API stops at €0).
- **OpenAI:** $50 hard monthly cap, alerts at $15 and $40, API training/sharing **off**.
- **You** watch crash Organizer / Railway / report mail during review week.
- Reminder: Apple client secret expires **3 April 2027**.

### 6. Submit

App Store Connect → Angles → version 1.0:

1. Select TestFlight build **25**.
2. Under subscriptions, attach **both** Angles Yearly and Angles Monthly.
3. Paste review notes from [app-review-notes.md](app-review-notes.md) (as soon as possible report wording).
4. **Add for Review** → **Submit for Review**. Release stays **manual**.

## Done (unchanged summary)

Apple account, subscriptions, grace period, server notifications, listing copy, age rating, review contact details, backend migrations, Resend on Railway, production `/health`, BUILD.md row 20 features, builds 9–15 uploaded, onboarding path verified on device.

## Before every later upload

- `backend/`: `pnpm typecheck` && `pnpm test`
- Bump `CURRENT_PROJECT_VERSION` in `AnglesApp/project.yml`, `xcodegen generate`
- Deploy backend before a build that depends on API changes
- TestFlight on Joe’s iPhone for release verification (not Debug replacing TestFlight unless intentional)
