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
| Ready cook (every chosen style) | 1 |
| Ready single-style recook | 1 |
| Continue or clarification | 0 |
| Safety response | 0 |
| Failed operation | 0 |
| Save, publish, favorite, follow, report, or block | 0 |

The tariff is flat: 1 credit whichever model the server routed the cook to, including a fallback. Credits are reserved before provider work and charged only when the operation finishes `ready`. A discarded ready result was still generated and remains charged.

The onboarding taste uses the same server-routed models and does not debit a paid allowance. It cannot be recooked. The server consumes the one-account grant when the first ready result settles, independently of whether that result is later saved.

## Allowance behavior

- Credits reset at the end of the current monthly membership period.
- Unused credits do not roll over.
- There are no credit packs, overages, pay-as-you-go user charges, transfers, or cash value.
- The app warns at **120 credits remaining (20%)** and **60 credits remaining (10%)**. Empty is a persistent state, not a surprise Apple charge.
- Settings → Subscription shows remaining/granted credits and the reset date.
- `USAGE_PLAN_VERSION` is `monthly-600-v1`.
- `CREDIT_TARIFF_VERSION` is `flat-v1` (it was `public-models-v1`: Mistral 1, DeepSeek 2, Gemini 6 by the model the user picked).

Versioned periods preserve the rules under which they were created. Changing allowance or tariffs requires a new version and an explicit migration/product decision; do not silently reinterpret historical periods.

## Model routing and fallback

The app has no model picker and the request names no model. With 1 or more credits, cook and recook are available; at 0 they are unavailable until reset.

The server picks the model for each step of a cook:

| Step | Default | Environment variable |
| --- | --- | --- |
| Decision (continue or ready, cleaned thought, metadata) | `mistral-small-latest` | `LLM_DECISION_MODEL` |
| Writer (every style, lint rewrites, recook) | `deepseek-flash` | `LLM_WRITER_MODEL` |
| Public-card moderation | `mistral-small-latest` | `LLM_MODERATION_MODEL` |

Each step has a fallback on another provider (`LLM_DECISION_FALLBACK_MODEL` and the like; by default a Mistral step falls back to DeepSeek Flash, and a DeepSeek or Gemini step to Mistral Small). A retryable provider error (408, 429, 5xx, or a timeout) runs the same call once on the fallback. A ready cook, and the card saved from it, records the writer that answered as `model`; a recook keeps its cook's `model`. Changing a step's model is an environment change, not an app release, and it never changes the tariff.

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

`LLM_RATE_VERSION` is `2026-09-credits-v1`. Provider-reported usage is preferred. If a call fails before usable provider usage is available, the server records a conservative estimate so company spend is not hidden.

The company ledger stores no thought or reframe text. It is operational COGS accounting, not the user-visible tariff. Public-card moderation provider calls are also recorded as company COGS but do not consume user credits.

## Current company rate table

The versioned COGS calculation currently uses:

- Mistral: `$0.15/1M` input and `$0.60/1M` output
- Gemini: `$0.75/1M` input and `$3.75/1M` output, including thinking as output
- DeepSeek: `$0.03/1M` cache-hit input, `$0.30/1M` other input, and `$1.20/1M` output

These are accounting inputs, not promises to users. Verify them before production launch and create a new `LLM_RATE_VERSION` when provider pricing changes.

## Cost per cook

Measured with `pnpm llm:eval` on the 80 golden thoughts (2026-09-30), Mistral Small deciding, judged by Gemini 3.8 Flash on a 1–5 scale:

| Writer | Per ready cook | Tone | Specific | Distinct | Fresh | Kind | Latency p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `deepseek-flash` (default) | $0.00098 | 4.28 | 4.20 | 3.88 | 3.84 | 4.86 | 3.4 s |
| `gemini-3.8-flash` | $0.00338 | 4.40 | 4.24 | 3.96 | 3.82 | 4.86 | 4.0 s |
| `deepseek-v4-pro` | $0.00099 | 4.03 | 3.98 | 3.72 | 3.39 | 4.85 | 5.7 s |
| `mistral-small-latest` | $0.00107 | 3.15 | 3.43 | 3.37 | 2.83 | 4.60 | 3.5 s |

The budget is about $0.002 per ready cook, about $1.20 a month for a subscriber who uses all 600 credits. The default is about $0.001: roughly $0.59 a month at full use, 12% of the monthly price and 18% of the annual price per month before Apple's commission. Continue turns add a little on top and are bounded by the provider-call cap. Gemini writes slightly better on this judge (which may favour its own family) but costs over three times as much. `LLM_WRITER_MODEL` is the knob to raise quality later; re-run the eval before changing it.

## Provider-side controls

User credits protect per-subscriber margin. Provider controls protect the company account and are separately required:

- Mistral organization/workspace monthly spend limit
- Gemini project spend cap or bounded prepay with capped reload
- Small DeepSeek prepaid balance
- Alerts for cap/balance thresholds
- Separate production and local/CI credentials

If a provider-wide cap trips, affected requests fail with no user-credit charge. The cap does not fairly allocate usage between subscribers and is not a replacement for the 600-credit ledger.

## StoreKit and server entitlement

Apple handles purchase, renewal, refund, and cancellation. The client sends signed transaction data to the backend. The backend verifies Apple signatures, binds the original transaction to one Angles account, processes Server Notifications V2 idempotently, and determines active/grace/billing-retry/expired/revoked state. Only active and grace unlock: billing retry after Apple's Billing Grace Period is locked, so that grace period must be on in App Store Connect.

Production must run with both subscription and usage enforcement set to `required`. Local/test configurations may disable enforcement but do not define the shipped product.
