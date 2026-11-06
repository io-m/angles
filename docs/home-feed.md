# Home stack: how the cards behave

This is the plain-language rulebook for Home. If the app does something this page does not describe, that is a bug. The tuning numbers live in `backend/src/lib/feedRanking.ts`; the full engineering notes are `BUILD.md` sections 14 and 27.

Home is a stack of cards, one on top. Swipe right or tap the heart to love a card (it goes to Profile → Loved), swipe left or tap Pass to move on. Only sideways decides; a card dragged up or down springs back. Everything here applies when the server runs with `FEED_RANKING=resonance` (production). With `FEED_RANKING` unset or `chronological`, the stack is newest first, the house cards still last, and the ranking rules below are off. That switch stays as the rollback.

## A visit

A **visit** starts on a cold launch, when you come back to the app after 30 minutes away, or when you tap Check again on the end card. At that moment the server fixes everything the order depends on: who you follow, every save (yours and other people's), your themes, which passed cards may come back, and the clock. A save or a follow during the visit takes effect on the next one.

The phone asks for 12 cards at a time and asks for more when 5 are left. Each request names the cards this visit already handed out, so a card never comes twice in one visit. A card you decide on is gone from the next request on its own; the order of the cards that are left does not change.

## Filters

The filter at the top left narrows the stack to some life areas, some moods, or both: a card shows when its life area is one of those picked and it shares at least one picked mood. Applying a filter starts a new visit with everything below still in force inside it, house cards included. When nothing is left under the filter, the end card offers Clear filters instead of Check again. The filter lasts until it is cleared or the account signs out.

## What you see first

- **What is new.** A post from today beats one from last week unless saves, follows, and your themes together make up the difference.
- **New posts get read.** About 1 card in 5 is one that fewer than 8 people have decided on yet, so a fresh post is seen before anyone can say whether it is good.
- **A mix of people.** At most 2 cards per author in 12, about a tenth of a whole visit for any one author (at least 2), and never the same author twice in a row when someone else is available. In a community of two or three people the stack alternates between them.
- **A mix of themes.** About 40% close to what you write and save, 35% next to it, and 25% something else. The 25% is held for you, not just allowed, as long as such cards are left. A new account with little history gets the plain ranked order.
- **Pacing.** Two heavy cards never sit back to back while a lighter one is left. A card is heavy when it is about real harm (the cook skipped Witty and Tough for it), about grief and loss, or has intensity 4 or more. At most two cards from one life area in a row, and at most 6 of the most intense posts in 12.

## Your own cards

Never in the stack. Saving your own card means nothing. Everything you wrote is in Profile under Yours, and a new post does not jump into the stack: compose closes back to the card you were on and a short "Posted" or "Saved privately" note appears.

## Save, pass, and coming back

A save keeps the **whole card**, all of its angles, in Profile under Saved, opening on the angle you saved it on. It never comes back to the stack.

An angle counts as seen once it has been on screen: the one the card opened on and every one you tapped to.

A pass takes the card off the stack. It may come back **once**, and only when:

- the pass is at least 12 hours old,
- it was your first pass on that card, and
- the card still has an angle you have not seen.

It then opens on the first angle you have not seen, in the order the cook ranked them. It sits lower than a new card of the same age, and at most 2 cards in 12 are ones coming back. A second pass, or a pass after reading every angle, keeps it away for good. Unsaving a card in Profile counts as reading every angle, so it does not bounce back.

Rewind walks back through this visit's decisions one at a time and puts each card back exactly as it was before.

## Telling the author

A save tells the author, unless the card is From Angles. They see it in the bell list ("Loved your Witty angle", with two lines of their own thought) and, ten seconds later, as a push: "Ana" ("Loved your Witty angle") or "Ana and 2 others" ("Loved your post"), never the words of the card. Tapping the push or the row in the bell opens that post on the angle they loved, with an X in the top left to return to Home. The wait means a swipe you Rewind straight away tells nobody, and loves that arrive together become one push. While earlier loves on a card are unread, it pushes at most once every 2 minutes; loves in between go out together at the end of the wait. Unsaving or Rewind takes the love back while the author has not read it yet.

Your name is on your loves unless you turn off Settings → Show my name on loves; then the author sees "Someone". The first time you love a card the app says so once. Settings → Loves on my posts turns off the push for loves on your own posts; the bell list keeps them. Blocking someone removes their loves and yours between you.

## Follow vs discovery

Following someone is a strong nudge, never a filter:

- A followed author's post scores higher, worth about half a day of freshness on a new post.
- When you follow **3 or more people who posted in the last 7 days**, about a quarter of the stack (3 in 12) comes from them, spread through it rather than stacked at the top.
- Followed authors never take more than half. The rest is always discovery.

## From Angles

When the community cards for this visit run out, curated cards from Angles follow, marked From Angles with the Angles mark instead of a person. They use the same theme mix, never count as followed, and can be saved and passed like any other card. After them comes the end card: you're caught up, with Inspire me and Check again.

## What never appears

- Your own cards.
- Private cards.
- Cards from people you blocked or who blocked you.
- Cards you reported.
- Cards you saved.
- Cards you passed, except the one return above.

## Which angle a card opens on

The cook's best angle is the card's cover. Once you have saved a few cards, about half of the cards you meet open on the angle you save on most instead; the other half keep their cover, so the stack still reads in several voices. A returning card always opens on an angle you have not seen. Tap the right half of a card for the next angle and the left half for the one before, or tap an angle's name.

## The score

Each card gets one number. These are the weights:

| Term | Weight | What it measures |
| --- | --- | --- |
| Freshness | 2.0 | How new the post is: about half its worth after a day, a third after two, then a small tail that lasts about two weeks |
| Kept | 0.6 | Of the people who decided on it, how many saved it, compared with cards of the same weight. A heavy card is only compared with heavy cards, so a grief post is never marked down because people pass grief more often than a joke. A card with few decisions sits in the middle until there are enough to say. |
| Reach | 0.2 | How many other people saved it; grows slowly and stops at 10, so one popular card cannot take over |
| Your themes | 0.7 | How close its life area, mood, and topics are to what you write (weight 1) and save (1.5), scaled by how much history you have. A pass takes a little (0.3) from that card's themes, for you only, never below zero. |
| Followed | 0.6 | You follow the author |
| Variety | 0.15 | A small, stable shuffle per visit, so two visits do not look identical |
| Coming back | −0.75 | You passed it once and it is back on an angle you have not seen |

## Checking it

`pnpm db:feed-audit --viewer=<email>` walks one visit as that account, page after page, and prints each card's age, life area, theme bucket, author, and flags (followed, heavy, returning), with no thought text. It ends with the numbers that must hold: no repeats, no own or saved cards, no heavy cards side by side, no page over the returning cap, no community card after the first house card, and the newest post near the top. It also prints how many authors the visit reached, the top author's share, the share of cards from outside your themes, and how long each page took. It is in the production image and runs read-only over `railway ssh`. `pnpm db:seed-realistic --viewer=<email>` gives the fixture community readers who save and pass, and that account a small history.
