# Subscription tiers (planning)

Working memo for the paywall (`BUILD.md` rows 6–7). **Do not ship StoreKit from this file.** Numbers are USD list, September 2026, after the two-call cook (decision JSON + one style-batch JSON). Recook is still a decision plus one style call.

Default model: **Mistral Small 4** (`mistral-small-latest`) at about **$0.15 / 1M input** and **$0.60 / 1M output**. Gemini 3.8 Flash intro is **$0.75 / $3.75** (thinking billed as output; doubles 1 Jan 2027). DeepSeek Flash peak is **$0.30 miss / $1.20 out** (half off-peak).

Goal: prices that feel cheap to tap, while LLM + Apple still leave a wide margin on a normal user. Variable cost is tiny; the real risk is **unlimited Gemini** or **unbounded recook loops**, not 16 Mistral cooks a day.

## What a “post” is

One **ready cook**: user submits a thought, may answer a continue turn, then gets 1–4 styles (usually all four) and can save a private card.

| Extra | Counts as a post? | Why |
| --- | --- | --- |
| Continue / clarify turn | No | One cheap decision call; they have not received the card yet |
| Recook (“New stoic angle”) | Yes, 1 | Full decision + one style; easy to spam |
| Save / favorite / delete | No | Postgres only |
| Discard without save | Still a post | LLM already ran |

Onboarding taste (row 6) is **one free ready cook**, then a hard paywall. After that everyone is paid. No ads.

## Three usage scenarios

Eyeballed from a private journaling loop, not from live telemetry. 30-day month.

| | Light | Daily | Heavy |
| --- | --- | --- | --- |
| Persona | Occasional dump when something stings | Morning or evening journal | Processes a lot; recooks styles |
| Ready cooks / day | **3** | **8** | **16** |
| Ready cooks / month | 90 | 240 | 480 |
| Continues (assume ~20% of cooks) | ~18 | ~48 | ~96 |
| Recooks (assume ~0.25 per cook) | ~22 | ~60 | ~120 |
| What they feel they paid for | “A few cards when I need it” | “This is my journal” | “I live in it” |

Light is the floor we want to look generous. Daily is the **median we should price around**. Heavy is the cap we must still profit on, including Apple’s cut.

## Cost of goods (LLM only)

Token estimate: prompt characters / 4. Typical decision output ~420 tokens (not the 700 cap). Style batch ~240 tokens (not the 280 cap). **Does not include Railway, Postgres, or Apple.**

**Bare cook** (ready, four styles, no continue, no recook), Mistral:

| | Tokens in | Tokens out | $ / cook |
| --- | --- | --- | --- |
| Old (1 decision + 4 style calls) | ~2,900 | ~740 | ~$0.00088 |
| **Now (1 decision + 1 batch)** | ~2,300 | ~660 | **~$0.00075** |

**Loaded month** (bare cooks + continues + recooks as above), Mistral:

| Scenario | LLM / user / month | vs $4.99 list |
| --- | --- | --- |
| Light (3/day) | **~$0.09** | 1.8% of list |
| Daily (8/day) | **~$0.23** | 4.6% of list |
| Heavy (16/day) | **~$0.47** | 9.4% of list |

Same loaded month on **Gemini 3.8 Flash** (intro rates, thinking on): roughly **5–6×** Mistral → about **$0.50 / $1.30 / $2.60**. Still fine under a $5–8 price if Heavy is rare. It is **not** fine if Heavy users live on Gemini with no cap (see Fair use).

Infra (Railway + Postgres) is a few dollars a month at the start and pennies per user once there are hundreds of subscribers. Ignore it for tier math; it does not change the price.

## Apple’s cut

iOS IAP is the only honest path for digital subscriptions.

| | You keep of list |
| --- | --- |
| Small Business Program (≤ $1M/year) | **85%** (15% fee) |
| Standard, year 1 of a subscription | 70% (30% fee) |
| Standard, year 2+ of that subscription | 85% |

Plan **15%** as the long-run case; sanity-check **30%** so year-1 still works.

Net to Angles before LLM, on the recommended prices:

| List | After 15% | After 30% |
| --- | --- | --- |
| $2.99 | $2.54 | $2.09 |
| $4.99 | $4.24 | $3.49 |
| $7.99 | $6.79 | $5.59 |
| $39.99 / year | $33.99 | $27.99 |

Even Heavy Mistral (~$0.47) against $3.49 year-1 net is still ~**85% gross after LLM**. The product can be cheap because the cook is cheap.

## Recommended tier list

One paid product after the taste is enough for v1. Two paid SKUs if you want a visible upgrade. Three SKUs is for later, when telemetry exists.

### v1 (ship with paywall)

| | Taste | Angles |
| --- | --- | --- |
| Price | $0 | **$4.99 / month** or **$39.99 / year** (~$3.33/mo) |
| Ready cooks | **1** (onboarding) | **Unlimited** on the default model |
| Styles per cook | All 4 | All 4 |
| Continues | Included | Included, do not meter |
| Recooks | n/a after paywall | Included, under fair use |
| Library | Not saved unless they pay and save | Private library, favorites, delete |
| Model | Default (Mistral) | Default (Mistral). Picker can stay visible but Gemini / DeepSeek stay off this SKU |
| Fair use | — | Soft cap **20 ready cooks / day** (covers Heavy 16 + a bad day). Recooks share that cap. Show a quiet “that’s enough for today” rather than a hard error on 21. |
| Why this price | Prove the loop | Under a coffee; impulse yes; Light users feel they stole it; Heavy still prints |

**Annual** at $39.99 is 20% off vs 12 × $4.99. That is the lever for margin and retention, not a third product.

Do not sell a $2.99 “Light” in v1. It trains people to count remaining cooks, and LLM savings vs $4.99 are cents.

### v1.5 (only if the picker or Heavy users matter)

| | Angles | Angles Plus |
| --- | --- | --- |
| Price | $4.99 / mo · $39.99 / yr | **$7.99 / mo · $59.99 / yr** |
| Model | Mistral only | Mistral + Gemini + DeepSeek |
| Fair use | 20 cooks / day | 30 cooks / day |
| Everything else | Same private loop | Same |

Plus is how you **attract with a low sticker** and still charge the people who pick the expensive model. List $7.99 after 30% is $5.59; Heavy Gemini (~$2.60) still leaves ~$3.

### Later (do not design SKUs yet)

A three-rung ladder matching the personas, if you ever want metered Light:

| SKU | List | Quota (ready + recook / month) | Fits |
| --- | --- | --- | --- |
| Light | $2.99 | 100 (~3/day + recooks) | Light |
| Angles | $4.99 | 300 (~8/day + recooks) | Daily |
| Plus | $7.99 | 600 or fair-use unlimited Mistral | Heavy |

Until you have real histograms, this ladder is optional. The two-SKU table above is enough.

## What they get (copy you can reuse)

Keep paywall copy about the **loop**, not about tokens.

- One thought in, four angles out (Stoic, Optimistic, Humorous, Tough Love).
- Private by default. Cards live in Profile. Nothing is a public feed.
- Ask a follow-up when the thought is unclear; then cook.
- Recook a single style when one angle missed.
- Save, heart, delete. Appearance and accent already in Settings.

Do not promise therapy, crisis care, or unlimited Gemini on the cheap SKU.

## Margin snapshot (v1 Angles @ $4.99)

Mistral, loaded usage, **15% Apple**:

| User | LLM | Apple | Left | LLM as % of net |
| --- | --- | --- | --- | --- |
| Light | $0.09 | $0.75 | **$4.15** | 2% |
| Daily | $0.23 | $0.75 | **$4.01** | 5% |
| Heavy | $0.47 | $0.75 | **$3.77** | 11% |

Year-1 **30% Apple** still leaves **$3.02** on a Heavy Mistral user. That is the “low price, still margin” bar.

Break-even on LLM+30% Apple at $4.99 is thousands of Gemini cooks per month. Fair use exists so a script cannot do that.

## Rules that protect the cheap price

1. **Default model is the cheap SKU.** The compose picker is a Plus feature, or Gemini/DeepSeek are capped (for example 3 Plus-model cooks/day on Angles).
2. **Meter ready + recook, not continues.** Continues are how you avoid garbage cards; charging for them feels like a tax on unclear pain.
3. **Soft daily cap, not a scary remaining-count.** 20/day is ~600/month, above Heavy. Almost nobody should hit it.
4. **Taste is one full cook, all four styles.** That is the ad. Then paywall. No three-day trial that burns Gemini.
5. **Annual is the real product.** Monthly is the trial of paying.

## Budget metering (credits)

Counting **requests** is the wrong ledger. A Mistral continue, a four-style cook, a Gemini cook, and a recook are not the same bill. Internally meter **what we pay**. On screen, use **credits**.

Prefer **credits** over **points**. Points feel like a game. Credits are “how many of these I can still do.” Never say tokens.

**1 credit = one typical Mistral ready cook** (decision + four angles, ~$0.00075). Round display to whole credits. The server still stores millicents so Gemini can cost more than one.

| Action | Credits shown | Why |
| --- | --- | --- |
| Ready cook on Mistral | **1** | The unit |
| Ready cook on DeepSeek | **~2** | Peak is a bit more than Mistral |
| Ready cook on Gemini | **~5–6** | Intro rates are ~5–6×; thinking counts |
| Recook one style | **1** | Still a full decision + a style call; easy to spam |
| Continue / clarify | **0** | Cheap, and metering it feels like a tax on unclear pain (still debited in millicents so it cannot be abused as a loop) |
| Save / discard | **0** | LLM already ran when they cooked |

v1 Angles @ $4.99 can grant **600 credits / month** (Heavy 16/day plus recooks). Light users will not notice. A Gemini-only Heavy user burns them ~5× faster, which is the point of auto-pause.

Taste = **1 credit**, Mistral only.

Do **not** sell extra credit packs in v1 (App Store virtual-currency mess). The subscription refills the balance on the billing date. Do **not** show “847,000 tokens.”

### Internal unit: millicents

After every provider call, read the provider `usage` block (do not estimate from `chars/4` once this exists):

| Provider | Fields |
| --- | --- |
| Mistral / DeepSeek | `usage.prompt_tokens`, `usage.completion_tokens` |
| Gemini | `usageMetadata.promptTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount` (thinking is output) |

`cost_millicents = round(input_tokens × in_rate + output_tokens × out_rate)` using the rate table for that model. Store one row per call: owner, model, kind (`decision` / `batch` / `reframe`), tokens in/out, millicents, period. Never store thought text.

One millicent is `$0.00001`. A typical Mistral cook is ~`$0.00075`, so **1 credit ≈ 75 millicents**. Display credits as `floor(millicents_remaining / millicents_per_credit)` using a rolling average of that user’s Mistral cooks (fallback 75). Gemini still costs ~5–6 credits because it costs ~5–6× in millicents.

### What the user sees

Copy examples:
- Compose header / picker: **“142 credits left”**
- After a Gemini cook: **“6 credits used · Gemini”** only if we want a toast; otherwise just the remaining number
- Gemini paused: **“Not enough credits for Gemini. Mistral still works.”**
- Empty: **“You’re out of credits until next month.”**

| Remaining | Picker |
| --- | --- |
| ≥ Gemini cook (~6 credits) | All allowed models on |
| ≥ 1 credit, &lt; Gemini | Gemini + DeepSeek **paused**; auto-switch to Mistral |
| 0 credits | Cook and recook disabled |

Settings → Subscription: a bar plus **“142 of 600 credits”**. Same word everywhere.

### Auto-disable, not a surprise 402

Before `POST /reframe`, the server checks remaining millicents against that model’s estimated cook:

- Below Gemini/DeepSeek → `402` / `MODEL_PAUSED`, `allowedModels: ["mistral-small-latest"]`, `creditsRemaining`. Cook on Mistral must still work.
- Below one Mistral cook → `402` / `QUOTA_EXCEEDED`. No LLM call.
- After success, return `usage`: `{ creditsRemaining, creditsGranted, allowedModels, creditCost: { mistral, gemini, deepseek } }` so the picker updates without a second round-trip.

Client: disabled rows in the model popover, not hidden. If the selected model is paused, snap to Mistral and use the paused copy above.

### What not to do

- Do not say tokens, millicents, or “API usage” in the app.
- Do not sell consumable credit packs in v1.
- Do not show continues as “−0.3 credits.”
- Do not guess tokens if the provider omitted `usage` — skip the debit rather than over-charge; log `usage_missing` without text.
- Do not ship this before auth (row 8).

### Implementation order (with paywall, not now)

1. Parse `usage` in `llmClient.ts`; return tokens alongside the string. Tests with stubbed provider JSON.
2. Rate table + millicents + `toCredits()` next to the catalog.
3. Drizzle `usage_events` + `usage_periods` (owner, period, allowance millicents, spent). Increment after each `/reframe` provider call (never on `/cards`).
4. `GET /me/usage` and `usage` on `/reframe`. Types + Swift models in the same change. JSON field names: `creditsRemaining`, not millicents.
5. Compose picker + Settings copy (“credits left”). Auto-fallback.
6. StoreKit product maps to monthly credit grant when row 7 lands. Taste = 1 credit.

Until then the published v1 SKU can stay “unlimited Mistral under a 20/day fair-use cap.” Credits **replace** that request cap once the ledger exists.

## How we pay the providers (company side)

Two different bills. **Users pay Apple** (IAP). **Angles pays Mistral / Google / DeepSeek** from one company account per provider. The iOS app never holds a provider key. Railway (and local `.env`) holds `MISTRAL_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`. Every cook from every subscriber hits those three accounts.

None of the providers sell us “600 credits per Angles user.” They only see **our** traffic as one customer. Per-user credits live in **our** Postgres. Provider dashboards are the company safety net.

Default from the providers is **not** a tidy monthly prepaid product matching our SKU. It is pay-as-you-go (or a wallet we top up). If we attach a card and set **no** cap, spend is **open-ended** until we notice. We should always set a company cap. That cap is a **kill switch for the whole app’s that model**, not a substitute for user credits.

| | How they charge Angles | Open-ended? | Cap we can set | If the cap / balance hits |
| --- | --- | --- | --- | --- |
| **Mistral** | Card on file. Plan includes a bit of monthly usage, then **pay-as-you-go per token** if PAYG is on. Optional prepaid credits offset the invoice. | **Yes, unless we set a limit.** Workspaces default to **no** monthly cap. PAYG off = stop when included usage is gone (too tight for production). | Admin → Billing → **Organization monthly spending limit**. Optional extra cap per Workspace (prod vs dev). | API **suspended** for that org/workspace until next month or we raise the limit. Failed invoices also suspend. |
| **Gemini** | Google Cloud Billing. **Prepay** (buy credits, deduct in near-real-time; unused credits expire in 12 months) or **Postpay** (invoice / auto-charge at month end, or when a tier cap hits). New AI Studio accounts often land on Prepay (min ~$5). | **Mostly no.** Google also enforces a **tier ceiling** on the billing account (Tier 1 **$250**/mo, Tier 2 **$2,000**, Tier 3 **$20k–$100k**). We can set a tighter **project spend cap** in AI Studio. Prepay stops at $0. Auto-reload can quietly refill unless we set a **monthly auto-charge limit**. | AI Studio → Spend → **project monthly spend cap**. Prepay: modest balance + auto-reload **with** a monthly auto-charge ceiling. Do not treat Google’s $250 tier cap as our budget. | Keys on that project **pause** until the next cycle, we raise the cap, or we add Prepay credits. Caps lag ~**10 minutes** — a burst can overshoot. |
| **DeepSeek** | **Prepaid wallet** only. Top up; they deduct per token (granted promo balance first). No monthly invoice. | **Only as far as the wallet.** There is no “monthly spend limit” product. If we keep topping up, spend continues. | The balance **is** the cap. Keep it small. No huge auto-top-up. `GET /user/balance` to watch it. | **`402 Insufficient Balance`**. That model dies for every user until we add funds. |

Rate limits (requests/sec, tokens/min) are a separate throttle. They protect their cluster, not our bank account.

### What to configure for Angles

1. **One production key per provider**, on Railway, rotated if leaked. A second Workspace / Google project / DeepSeek key for local + CI so a runaway test cannot drain prod.
2. **Turn PAYG on for Mistral**, then set an **org monthly spend limit**. Add a **prod workspace cap** at the same number (or slightly under) so Studio/Vibe experiments cannot steal the budget.
3. **Gemini: Prepay + project spend cap**, not unbounded Postpay. Auto-reload only with a monthly auto-charge limit. Paid Gemini (not the free tier) so prompts are not used to train.
4. **DeepSeek: keep a small prepaid float** (enough for a few weeks of Plus traffic). When it runs low, top up by hand until we have alerts.
5. **Size the company cap as 2–3× expected LLM COGS** for that month’s paid headcount, not as “unlimited.” Example: 1,000 Daily Mistral users ≈ **$230**/mo LLM → set Mistral ~**$500–700**. Gemini envelope only if the picker is on (Plus); start tight (tens of dollars) and raise with Tier upgrades when we actually need them. Recheck the number when subscriber count jumps.
6. **Email alerts at 50% / 80% / 100%** of each company cap (Mistral usage page, Google budget emails, DeepSeek balance check). Hitting 100% is an incident: every user loses that model.
7. **Do not map Apple revenue 1:1 onto a provider prepaid pack.** Apple pays us on their cycle; we pay providers on theirs. Float a few hundred dollars of LLM budget so a spike in cooks does not wait on App Store proceeds.

### Two layers, both required

| Layer | Who it protects | Granularity | If it trips |
| --- | --- | --- | --- |
| **User credits** (our DB) | Margin per subscriber | One person | That person pauses Gemini, then cooks, until their period resets |
| **Company spend cap** (provider console) | The bank account | Whole product | **All** users get `LLM_ERROR` / that model gone until we act |

The provider cap is the last line of defense against a leaked key, a retry bug, or a scraped cook endpoint. It will not fairly share budget across users. That is what credits are for.

Do not wait for a provider invoice to “feel” expensive. At $0.00075/cook, abuse is a volume problem, not a sticker-shock problem, until Gemini is on.

## Open questions (paywall task, not now)

- Small Business Program vs standard 30%.
- Family Sharing (Guideline 3.1.2) if you ever share a library — skip for a private journal.
- Restore purchases needs auth (row 8) or at least Apple ID restore; do not invent accounts here.
- EU alternative billing does not change the “keep prices low” story; still plan IAP first.

When telemetry exists, replace the 3 / 8 / 16 eyeball with p50 / p90 cooks per active day and revisit Plus. Until then, **$4.99 monthly / $39.99 yearly, Mistral unlimited under a 20/day fair-use cap, one free taste** is the tier list.
