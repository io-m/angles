# Subscription contract

This is the shipped V1 contract. It is not a pricing proposal.

## Products

- Monthly: **$3.99/month** (`app.angles.ios.monthly`)
- Annual: **$24.99/year** (`app.angles.ios.annual`)
- No free trial
- One private onboarding taste before the paywall
- Both paid products grant **600 credits per monthly membership period**

The annual product does not grant 7,200 credits at once. Its allowance is divided into monthly periods anchored to the original subscription purchase date.

## User credit tariff

| Result | User credits |
| --- | ---: |
| Ready cook (every chosen style) | 1 |
| Ready single-style recook | 1 |
| Continue or clarification | 0 |
| Safety response | 0 |
| Failed operation | 0 |
| Save, publish, heart, follow, report, or block | 0 |

The tariff is flat: 1 credit whichever model the server routed the cook to, including a fallback. Credits are reserved before provider work and charged only when the operation finishes `ready`. A discarded ready result was still generated and remains charged.

The onboarding taste uses the same server-routed models and does not debit a paid allowance. It cannot be recooked. The server consumes the one-account grant when the first ready result settles, independently of whether that result is later saved.

## Allowance behavior

- Credits reset at the end of the current monthly membership period.
- Unused credits do not roll over.
- There are no credit packs, overages, pay-as-you-go user charges, transfers, or cash value.
- The app warns at **120 credits remaining (20%)** and **60 credits remaining (10%)**. Empty is a persistent state, not a surprise Apple charge.
- Settings → Subscription shows remaining/granted credits and the reset date.
- `USAGE_PLAN_VERSION` is `monthly-600-v1`.
- `CREDIT_TARIFF_VERSION` is `flat-v1`; the earlier model-weighted tariff is retired.

Versioned periods preserve the rules under which they were created. Changing allowance or tariffs requires a new version and an explicit migration/product decision; do not silently reinterpret historical periods.

## Model routing and fallback

The app has no model picker and the request names no model. With 1 or more credits, cook and recook are available; at 0 they are unavailable until reset.

The server picks the model for each step of a cook:

| Step | Default | Environment variable |
| --- | --- | --- |
| Decision (continue or ready, cleaned thought, metadata) | `mistral-small-latest` | `LLM_DECISION_MODEL` |
| Writer (every style, lint rewrites, recook) | `mistral-small-latest` | `LLM_WRITER_MODEL` |
| Public-card moderation | `mistral-small-latest` | `LLM_MODERATION_MODEL` |

Each step defaults to one fallback on `gpt-4.1-mini` (`LLM_DECISION_FALLBACK_MODEL` and the like). Any failure of that provider call, including an auth error, a 4xx or 5xx, a timeout, a network error, or an empty reply, runs the same call once on the fallback. `none` disables the fallback. A ready cook, and the card saved from it, records the writer that answered as `model`; a recook keeps its cook's `model`. Changing a step's model is an environment change, not an app release, and it never changes the tariff.

A failed operation, including one where the fallback also failed, costs 0 user credits and returns an error.

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

The user ledger is intentionally simple and predictable: 1 credit per ready cook or recook. It controls the 600-credit allowance and is independent of the model and the exact token count of one request.

It does not represent tokens, provider currency, or a resale of provider credits.

### Actual provider token and COGS ledger

The company ledger records each real provider attempt, including failed attempts:

- operation/account association, call kind, attempt number, requested and returned model, and provider request ID when supplied;
- prompt, cached, cache-hit/cache-miss, completion, thinking, and tool tokens as applicable;
- whether usage was provider-reported or estimated;
- success/failure status;
- versioned company cost in nano-USD.

`LLM_RATE_VERSION` is `2026-10-providers-v2`. Provider-reported usage is preferred. If a call fails before usable provider usage is available, the server records a conservative estimate so company spend is not hidden.

The company ledger stores no thought or reframe text. It is operational COGS accounting, not the user-visible tariff. Public-card moderation provider calls are also recorded as company COGS but do not consume user credits.

## Current company rate table

The versioned COGS calculation currently uses:

- Mistral: `$0.15/1M` input, `$0.015/1M` cached input, and `$0.60/1M` output
- OpenAI GPT-4.1 mini: `$0.40/1M` input, `$0.10/1M` cached input, and `$1.60/1M` output

These are accounting inputs, not promises to users. Verify them before production launch and create a new `LLM_RATE_VERSION` when provider pricing changes.

## Cost per cook

A ready cook on the current Mistral prompts is about $0.0015 (the decision call plus four styles), about $0.90 a month for a subscriber who uses all 600 credits. The budget remains about $0.002 per ready cook, about $1.20 a month once a lint rewrite is included. Free continue turns are uncharged and dominate the abuse ceiling: 600 cooks plus the rest of the daily operation cap filled with continues is about $1.90. The $0.0015 figure is arithmetic on today's prompt sizes. An earlier 80-thought run measured about $0.00107 per ready cook, and there is no measured GPT-4.1 mini quality or per-cook claim yet. Re-run `pnpm llm:eval` before making the fallback primary or treating either figure as a current benchmark.

## Provider-side controls

User credits protect per-subscriber margin. Provider controls protect the company account and are separately required:

- Mistral organization/workspace monthly spend limit
- OpenAI project budget and usage alerts
- OpenAI API input/output sharing confirmed off
- Alerts for cap/balance thresholds
- Separate production and local/CI credentials

If a provider-wide cap trips, affected requests fail with no user-credit charge. The cap does not fairly allocate usage between subscribers and is not a replacement for the 600-credit ledger.

## StoreKit and server entitlement

Apple handles purchase, renewal, refund, and cancellation. The client sends signed transaction data to the backend. The backend verifies Apple signatures, binds the original transaction to one Angles account, processes Server Notifications V2 idempotently, and determines active/grace/billing-retry/expired/revoked state. Only active and grace unlock: billing retry after Apple's Billing Grace Period is locked, so that grace period must be on in App Store Connect.

Production must run with both subscription and usage enforcement set to `required`. Local/test configurations may disable enforcement but do not define the shipped product.
