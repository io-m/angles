# Subscription contract

This is the shipped V1 contract. It is not a pricing proposal.

## Products

- Monthly: **$4.99/month** (`app.angles.ios.monthly`)
- Annual: **$39.99/year** (`app.angles.ios.annual`)
- No free trial
- One private onboarding taste before the paywall
- Both paid products grant **600 credits per monthly membership period**

The annual product does not grant 7,200 credits at once. Its allowance is divided into monthly periods anchored to the original subscription purchase date.

## User credit tariff

| Result | User credits |
| --- | ---: |
| Ready Mistral result | 1 |
| Ready DeepSeek result | 2 |
| Ready Gemini result | 6 |
| Continue or clarification | 0 |
| Safety response | 0 |
| Failed operation | 0 |
| Save, publish, favorite, follow, report, or block | 0 |

The same selected-model tariff applies to a full ready cook and a ready single-style recook. Credits are reserved before provider work and charged only when the operation finishes `ready`. A discarded ready result was still generated and remains charged.

The onboarding taste uses Mistral and does not debit a paid allowance. It cannot be recooked. The server consumes the one-account grant when the first ready result settles, independently of whether that result is later saved.

## Allowance behavior

- Credits reset at the end of the current monthly membership period.
- Unused credits do not roll over.
- There are no credit packs, overages, pay-as-you-go user charges, transfers, or cash value.
- The app warns at **120 credits remaining (20%)** and **60 credits remaining (10%)**. Empty is a persistent state, not a surprise Apple charge.
- Settings → Subscription shows remaining/granted credits and the reset date.
- `USAGE_PLAN_VERSION` is `monthly-600-v1`.
- `CREDIT_TARIFF_VERSION` is `public-models-v1`.

Versioned periods preserve the rules under which they were created. Changing allowance or tariffs requires a new version and an explicit migration/product decision; do not silently reinterpret historical periods.

## Model availability and fallback

All three public models are part of the same paid membership:

- 6 or more credits: Mistral, DeepSeek, and Gemini are available.
- 2–5 credits: Mistral and DeepSeek are available.
- 1 credit: only Mistral is available.
- 0 credits: cook and recook are unavailable until reset.

The picker keeps models visible with their costs. If the selected model becomes unaffordable after an authoritative server summary, the client visibly falls back in cheapest-first order, normally to Mistral. The server remains authoritative and rejects an unavailable selection before making a provider call. It never silently runs an expensive model and bills a different tariff.

Provider outages are not credit fallback. A failed provider operation costs 0 user credits and returns an error; it is not automatically retried as a different model.

## Abuse limits

Credits are the subscription allowance, not the only abuse control. The server also enforces:

- 10 operations in a rolling 60-second burst window
- 60 operations per account per UTC day
- 200 provider calls per account per UTC day
- one running metered operation per account
- a 30-second operation lease
- 10 lifetime client turns during the free taste
- a required UUID `Idempotency-Key` in production, bound to a text-free HMAC request fingerprint

Decision follow-ups can use multiple provider calls without charging user credits unless the operation eventually returns a ready result. Provider-call caps still bound those free turns.

## Two different ledgers

### Fixed user tariff

The user ledger is intentionally simple and predictable: Mistral 1, DeepSeek 2, Gemini 6. It controls the 600-credit allowance and is independent of the exact token count of one request.

It does not represent tokens, provider currency, or a resale of provider credits.

### Actual provider token and COGS ledger

The company ledger records each real provider attempt, including failed attempts:

- operation/account association, call kind, attempt number, requested and returned model, and provider request ID when supplied;
- prompt, cached, cache-hit/cache-miss, completion, thinking, and tool tokens as applicable;
- whether usage was provider-reported or estimated;
- success/failure status;
- versioned company cost in nano-USD.

`LLM_RATE_VERSION` is `2026-09-credits-v1`. Provider-reported usage is preferred. If a call fails before usable provider usage is available, the server records a conservative estimate so company spend is not hidden.

The company ledger stores no thought or reframe text. It is operational COGS accounting, not the user-visible tariff. Public-card moderation provider calls are also recorded as company COGS but do not consume user credits.

## Current company rate table

The versioned COGS calculation currently uses:

- Mistral: `$0.15/1M` input and `$0.60/1M` output
- Gemini: `$0.75/1M` input and `$3.75/1M` output, including thinking as output
- DeepSeek: `$0.03/1M` cache-hit input, `$0.30/1M` other input, and `$1.20/1M` output

These are accounting inputs, not promises to users. Verify them before production launch and create a new `LLM_RATE_VERSION` when provider pricing changes.

## Provider-side controls

User credits protect per-subscriber margin. Provider controls protect the company account and are separately required:

- Mistral organization/workspace monthly spend limit
- Gemini project spend cap or bounded prepay with capped reload
- Small DeepSeek prepaid balance
- Alerts for cap/balance thresholds
- Separate production and local/CI credentials

If a provider-wide cap trips, affected requests fail with no user-credit charge. The cap does not fairly allocate usage between subscribers and is not a replacement for the 600-credit ledger.

## StoreKit and server entitlement

Apple handles purchase, renewal, refund, and cancellation. The client sends signed transaction data to the backend. The backend verifies Apple signatures, binds the original transaction to one Angles account, processes Server Notifications V2 idempotently, and determines active/grace/billing-retry/expired/revoked state.

Production must run with both subscription and usage enforcement set to `required`. Local/test configurations may disable enforcement but do not define the shipped product.
