# Home feed: how For you behaves

This is the plain-language rulebook for Home. If the app does something this page does not describe, that is a bug. The tuning numbers live in `backend/src/lib/feedRanking.ts`; the full engineering notes are `BUILD.md` sections 9r, 14, and 15.

Everything here applies when the server runs with `FEED_RANKING=resonance` (production). With `FEED_RANKING` unset or `chronological`, every tab is simply newest first and the ranking rules below are off. That switch stays as the rollback.

## A visit

A **visit** starts when Home loads its first page: a cold open, a filter change, or a pull that starts over. At that moment the server fixes the list of cards the visit can show and the order they come in. It also fixes everything the order depends on: who you follow, every heart (yours and other people's), your themes, and the clock. Nothing you do during the visit reorders it. A heart or a follow takes effect on the next visit.

Each Home tab (For you, Stoic, Optimistic, Humorous, Tough love, Tender, Values) has its own visit and its own order. An app build that does not send `Angles-Style-Set: 2` only has the first five: its cards, kept angles, covers, and primary tabs are all worked out over the original four styles.

## Cold open

The first page is the top 24 cards of the visit's order. That order:

- **Starts with what is new.** A post from today beats one from last week unless hearts, follows, and your themes together make up the difference.
- **Mixes people.** At most 2 cards per author on a page, and never two from the same author in a row when someone else is available. In a community of two or three people, the page alternates between them instead of filling up with whoever posts most.
- **Shows at most one of your own cards per page.** Your own posts are scored like anyone else's. Your own themes do not boost them, and your hearts on them do not count. Once nobody else's cards are left, the feed ends rather than filling up with yours, so in a very small community For you can be short. Everything you wrote is always in Profile.
- **Mixes themes.** About 40% of a page is close to what you write and heart about, 35% is next to it, and 25% is something else. A new account with little history skips this and gets the plain ranked order.
- **Keeps distress in check.** At most 6 of the heaviest posts on a page.

## Follow vs discovery

Following someone is a strong nudge, never a filter:

- A followed author's post scores higher, worth about 7 hours of freshness on a new post.
- When you follow **3 or more people who posted in the last 7 days**, about a quarter of each For you page (6 of 24) comes from them, spread through the page rather than stacked at the top.
- Followed authors never take more than half a page. The rest is always discovery.
- Following fewer than 3 active people gives only the nudge.

The guaranteed share is For you only. Style tabs use the nudge.

## Angles you already hearted

You heart an **answer**, not the whole card. So:

- **For you** still shows a card when you have hearted some of its answers. It sits a little lower, and it opens on an answer you have not hearted yet.
- A card disappears from For you only once you have hearted **every** answer it has.
- A **style tab** hides a card once you heart that tab's answer. The Stoic tab drops a card whose stoic answer you hearted; the Humorous tab can still show it.

## Load more

Scrolling near the end asks the server for the next 24 cards of the same visit. Pages never repeat a card and never skip one, even if you heart or follow someone mid-visit.

## Pull to refresh

A pull asks two things at once: are there posts newer than anything this visit could show, and what is the next page of the visit. Then exactly one of these happens:

| What you see | When |
| --- | --- |
| **N new posts** | People posted since the visit started. Only those posts are added at the top; nothing else moves. |
| A reload with **N new posts** | So many new posts arrived that the app starts a fresh visit instead of guessing. |
| **Fresh angles** | Nothing is new. The cards you have not scrolled to yet move to the top, followed by the next page you have not loaded. |
| **Full circle** | Nothing is new and you have seen everything. A fresh visit starts from the top. |
| **You're all caught up** | Nothing is new and everything fits on the screen you already have. |
| **Couldn't refresh** | Both requests failed. Your cards and your place stay as they were. |

"New posts" only ever means posts that did not exist when the visit started. An older post that was simply further down the order is never announced as new. Your own post appears at the top as soon as you publish it, and a pull does not count it again.

## What never appears

- Private cards, including your own.
- Cards from people you blocked or who blocked you.
- Cards you reported.
- On For you, a card whose every answer you hearted. On a style tab, a card whose answer for that tab you hearted.
- More than one of your own cards on a page.

## The score

Each card gets one number. These are the weights:

| Term | Weight | What it measures |
| --- | --- | --- |
| Freshness | 2.0 | How new the post is; halves roughly every 17 hours |
| Hearts | 0.8 | How many other people hearted it; grows slowly and stops at 10 hearts, so one popular card cannot take over. Your own hearts do not count. |
| Your themes | 0.7 | How close its life area and mood are to yours, scaled by how much history you have. Zero on your own cards. |
| Followed | 0.6 | You follow the author |
| Second chance | 0.25 | Nobody has hearted it yet and it is 1 to 14 days old (fading out by 30), so no post dies unseen |
| Variety | 0.15 | A small, stable shuffle per visit, so two visits do not look identical |
| Partly kept | −0.5 | For you only: you hearted some of its answers |

Style tabs add taste learned from the hearts you gave that style, hearts on that exact answer, and a penalty (2.75) for a card that fits another tab better. That penalty fades in over a post's first six hours, so the newest posts appear on every tab.

## Before and after (production)

`pnpm db:feed-audit --viewer=<email>` prints the feed as one account sees it, with no thought text. It is in the production image and runs read-only over `railway ssh`. The before reports were taken on 6 October 2026 with 8 public cards by 2 people (Josip 6, Martina 2).

**Josip, before:** For you page 1 had 5 cards, all his own. Both of Martina's posts were hidden because he had hearted one answer on each. A pull right after page 1 would have announced 2 old posts as new.

**Martina, before:** page 1 had 6 cards, 3 of them her own and the top two slots hers. A pull reported no fake arrivals, because her newest post happened to lead her page.

**After** (same day, same catalog, `backend/eval/out/feed-audit-after-*.txt`):

| | Josip before | Josip after | Martina before | Martina after |
| --- | --- | --- | --- | --- |
| Cards on For you | 5 | 3 | 6 | 5 |
| Own cards on page 1 | 5 | 1 | 3 | 1 |
| The other person's cards | 0 | 2 (both partly kept, opening on an unhearted answer) | 3 | 4 |
| Old posts a pull would call new | 2 | 0 | 0 | 0 |
| Kept angles that came back | 0 | 0 | 0 | 0 |

Josip now opens on one of his posts and both of Martina's, on answers he has not hearted. His other five posts stay in Profile. Martina opens on Josip's posts with one of her own in second place. With only two people posting, a page cannot avoid one author twice in a row; the spread still alternates where it can. The style tabs share fewer cards than before (for Josip, 0 to 2 per pair instead of 5 to 7) because his own cards no longer fill every tab.
