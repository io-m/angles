# App Review notes

Use this as the factual reviewer path. Do not provide demo credentials. The reviewer uses **Continue with Apple** and Apple's sandbox purchase flow.

## Why sign-in is required

Angles requires Sign in with Apple before the core experience because the free taste limit, private card ownership, subscription entitlement, monthly credits, community reports/blocks, and account deletion are account-scoped server features. There is no anonymous or shared test account and no email/password login.

## Exact first-run path

1. Launch Angles.
2. Tap **Continue with Apple** and complete Apple's native sign-in sheet.
3. For a new Angles account with no active subscription, the taste composer opens on "Welcome to Angles" with "Your first thought is free."
4. Type a thought into "Tell me what's on your mind..." and tap **Send** (the arrow).
5. The first Send opens **Before you start**, which names the AI providers (Mistral AI and OpenAI), says what is sent, says Angles is not therapy or a crisis service, states the community rules, and links the Terms of Use and Privacy Policy. Tap **Agree and continue**. The acceptance is stored on the server, so it appears once per account on any device.
6. If a follow-up question appears, tap any chip or type in "Say more..." and send. The server forces a result by the third turn.
7. Four angles appear, chosen from six voices (Stoic, Hopeful, Witty, Tough, Tender, and Values). A thought about real harm is not given Witty or Tough. Tap **Save to private library**. The taste is always saved privately.
8. "Saved privately" plays, then the paywall opens. Choose **Yearly** or **Monthly** (prices come from the App Store; Yearly shows the yearly price it bills), tap **Continue**, and approve the sandbox purchase. Each plan includes 600 credits a month.
9. After Apple verifies the transaction and the server syncs the entitlement, **Home** opens. The tab bar is **Home**, **Inspire me** (compose), and **Profile**. Inspire me opens the full composer, where Save is **Post** by default, with a **Save privately** option. Profile holds the private library and Settings (gear).

An existing entitled account skips the taste and paywall after Apple sign-in; if it has not accepted the Terms yet (for example, it subscribed without sending), **Before you start** opens before Home, with **Log out** as the only other choice. An account that already used its taste but is not entitled goes directly to the paywall. The taste is used as soon as its first result appears, so quitting before Save also lands on the paywall.

## Subscription restore and management

- On the paywall: **Restore purchases** under the **Continue** button, or in the (i) "What's included" sheet.
- In the app: **Profile → Settings gear → Subscription → Restore purchases**.
- **Change plan** and **Cancel** open Apple's subscription-management sheet.
- Logging out or deleting the Angles account does not cancel an Apple subscription.

## User-generated content safety

Home contains user-posted public cards. A user's own onboarding taste is private. Before submitting, the operator posts real public cards from a second account so Home shows another author.

### Report a card

1. On **Home**, tap the life-area badge with "…" (accessibility label "Card actions") on another person's card, or long-press that card.
2. Tap **Report**. It asks "Why are you reporting this card?".
3. Choose a reason: Spam, Harassment or bullying, Hate speech, Sexual content, Illegal activity, Personal information, or Something else.

The reported card leaves that reviewer's Home and library. Each new report emails the operator (ids and reason only), who reviews it as soon as possible with `pnpm reports` and can hide or delete the card or stop the author publishing. Three open reports make a card private automatically.

### Block a person

1. Open the same card menu.
2. Tap **Block [initials]**.
3. Confirm **Block**.

That person's posts disappear and the accounts can no longer follow each other. To reverse it, go to **Profile → Settings gear → Blocked people → Unblock**.

### Publication moderation

Saving privately does not publish a card. Posting a new card or changing a private card to public runs server-side public-content moderation. Disallowed content is not published; a moderation outage fails closed instead of exposing unchecked content.

## Account deletion

- **Profile → Settings gear → Delete account**, then confirm **Delete account**.
- Or, on the paywall, the (i) sheet → **Account → Delete account**, then confirm.

Apple's sheet asks to confirm with the Apple ID first, so the server can revoke the app's Sign in with Apple access; closing that sheet deletes nothing. The app then waits for server confirmation, deletes the Angles account and associated active data, and returns to Continue with Apple. Deletion does not cancel the Apple subscription; cancellation is handled through Apple. Signing in again with the same Apple ID creates a new account; its still-active sandbox purchase moves to that new account on restore.

## Reviewer environment

- No demo username or password is required or available.
- Use Apple's normal Sign in with Apple review flow.
- Use an Apple sandbox purchase for either subscription product.
- The production API, privacy policy, terms, and support URLs must be live in the submitted Release build.

## Paste-ready notes for App Store Connect

The "reviewed as soon as possible" line is only true when the report email reaches someone who acts on it promptly (`RESEND_API_KEY`, `REPORT_ALERT_FROM`, `REPORT_ALERT_TO` on Railway; the API logs `report_alerts_disabled` at startup without them). If nobody does, remove that line before pasting.

```text
Sign-in: Angles uses Sign in with Apple only. There is no email or password login, so there is no demo account. Please tap "Continue with Apple" with your own Apple ID. The account, free taste, subscription, credits, reports and blocks are tied to that Apple sign-in on our server.

First run:
1. Tap "Continue with Apple".
2. You get one free taste. Type this thought and tap Send:
   "I froze in a meeting today when my manager asked about my project, and now I keep replaying it and feel stupid."
3. The first Send shows "Before you start", which names our AI providers and links the Terms and Privacy Policy. Tap "Agree and continue".
4. If a follow-up question appears, tap any answer chip.
5. Four angles appear, chosen from six voices (Stoic, Hopeful, Witty, Tough, Tender, Values). A thought about real harm is not given Witty or Tough. Tap "Save to private library".
6. The paywall opens. Choose Yearly or Monthly, tap Continue, and approve the sandbox purchase. Each membership includes 600 credits per month; one result uses one credit.
7. Home opens. "Inspire me" in the tab bar writes a new thought; "Profile" holds your private library and Settings (gear).

If the app ever opens directly on the paywall, this Apple ID already used its taste. Purchase or restore to continue.

Restore: on the paywall, "Restore purchases" under the Continue button (also in the (i) sheet), or Profile -> Settings -> Subscription -> "Restore purchases".

Community safety (Home shows public cards from other people):
- Report: tap "..." on another person's card (or long-press it) -> Report -> choose a reason. The card disappears for you; reports are reviewed as soon as possible and repeated reports make a card private automatically.
- Block: same menu -> "Block [initials]" -> Block. Undo in Profile -> Settings -> Blocked people -> Unblock.
- Every post is screened by an automated moderation check before it becomes public; if the check is unavailable, nothing is published.
- Users agree to the Terms, which have a zero-tolerance policy for objectionable content and abusive users, on the "Before you start" screen.

Safety: Angles is a self-reflection tool, not therapy. If a thought suggests self-harm, Angles does not reframe it and shows a crisis line chosen by the device region.

AI: thoughts are processed on our server by Mistral AI or OpenAI, only after the user agrees on "Before you start". No AI runs on the device and no keys are in the app.

Account deletion: Profile -> Settings -> Delete account -> Delete account, or from the paywall (i) sheet -> Delete account. Apple's sheet confirms the Apple ID first so we can revoke Sign in with Apple access. Deleting does not cancel the Apple subscription.

Contact: info@bithavn.app
```
