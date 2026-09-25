# App Review notes

Use this as the factual reviewer path. Do not provide demo credentials. The reviewer uses **Continue with Apple** and Apple's sandbox purchase flow.

## Why sign-in is required

Angles requires Sign in with Apple before the core experience because the free taste limit, private card ownership, subscription entitlement, monthly credits, community reports/blocks, and account deletion are account-scoped server features. There is no anonymous or shared test account and no email/password login.

## Exact first-run path

1. Launch Angles.
2. Tap **Continue with Apple** and complete Apple's native sign-in sheet.
3. For a new Angles account with no active subscription, the app opens one free onboarding taste.
4. Enter a thought and tap Send. If Angles asks a follow-up, choose an answer or type a response.
5. When the four-angle result appears, tap **Save**. The onboarding taste is always saved privately.
6. The membership paywall appears. Select **Yearly — $39.99/year** or **Monthly — $4.99/month** and complete the Apple sandbox purchase.
7. After Apple verifies the transaction and the server syncs the entitlement, the app opens **Home**. The center sparkle button opens Compose; **Profile** contains the private library and Settings.

An existing entitled review account skips the taste and paywall after Apple sign-in. An account that already used its taste but is not entitled goes directly to the paywall.

## Subscription restore and management

- From the paywall, use **Restore purchases** in the information sheet.
- From the full app: **Profile → Settings gear → Subscription → Restore purchases**.
- **Change plan** and **Cancel** open Apple's subscription-management sheet.
- Logging out or deleting the Angles account does not cancel an Apple subscription.

## User-generated content safety

Home contains user-posted public cards. A user's own onboarding taste is private.

### Report a card

1. On **Home**, open the **⋯** menu on another person's public card, or long-press that card.
2. Tap **Report**.
3. Choose a reason: Spam, Harassment or bullying, Hate speech, Sexual content, Illegal activity, Personal information, or Something else.

The reported card is removed from that reviewer's in-app surfaces. Reports are stored for moderation, and repeated reports can automatically make a card private.

### Block a person

1. Open the same card menu.
2. Tap **Block [initials]**.
3. Confirm **Block**.

That person's posts disappear and the accounts can no longer follow each other. To reverse it, go to **Profile → Settings gear → Blocked people → Unblock**.

### Publication moderation

Saving privately does not publish a card. Posting a new card or changing a private card to public runs server-side public-content moderation. Disallowed content is not published; a moderation outage fails closed instead of exposing unchecked content.

## Account deletion

1. Open **Profile**.
2. Tap the **Settings gear**.
3. Tap **Delete account**.
4. Confirm **Delete account**.

The app waits for server confirmation, deletes the Angles account and associated active data, and returns to Continue with Apple. Deletion does not cancel the Apple subscription; cancellation is handled through Apple.

## Reviewer environment

- No demo username or password is required or available.
- Use Apple's normal Sign in with Apple review flow.
- Use an Apple sandbox purchase for either subscription product.
- The production API, privacy policy, terms, and support URLs must be live in the submitted Release build.
