/**
 * Walk the stack the way the app does, and grade it.
 *
 *   pnpm db:feed-audit --viewer=you@example.com [--pages=4] [--json]
 *
 * Production (no public database URL; the image ships this script):
 *
 *   railway ssh --service api --environment production \
 *     "node dist/scripts/feedAudit.js --viewer=you@example.com"
 *
 * Calls `listStack` page after page for one visit as that account, passing what earlier
 * pages handed out as the phone does, prints each page, and prints the numbers the stack is
 * meant to hold: time first, a mix of authors, no own or saved card, no repeats, never two
 * heavy cards side by side, returning cards at most one slot in five, and house cards only
 * after every community card. Read-only: it writes no decisions. Prints no thought or
 * answer text.
 */
import { and, count, eq, inArray, ne, sql } from "drizzle-orm";
import { runAsOwner } from "../lib/authStub.js";
import { classifyTheme, returningCap, type ThemeBucket } from "../lib/feedRanking.js";
import type { StoredCard } from "../types/index.js";
import { closePool, getDb } from "../db/client.js";
import { isHeavyCard, listStack, loadViewerAffinity } from "../db/stack.js";
import { cardDecisions, cards, follows, users } from "../db/schema.js";
import { STACK_PAGE_SIZE } from "../routes/stack.js";

function argument(name: string): string | undefined {
  const flag = process.argv.slice(2).find((item) => item.startsWith(`--${name}=`));
  return flag?.slice(name.length + 3).trim() || undefined;
}

function hasFlag(name: string): boolean {
  return process.argv.slice(2).includes(`--${name}`);
}

function hoursOld(card: StoredCard, now: Date): number {
  return (now.getTime() - new Date(card.createdAt).getTime()) / 3_600_000;
}

function ageLabel(hours: number): string {
  return hours < 48 ? `${hours.toFixed(1)}h` : `${(hours / 24).toFixed(1)}d`;
}

/** Initials plus a short id, because two people can share initials. */
function authorLabel(card: StoredCard): string {
  if (card.isHouse) {
    return "Angles";
  }
  return `${card.author.initials}#${card.author.id.slice(-4)}`;
}

const heavy = (card: StoredCard): boolean => isHeavyCard(card);
const returning = (card: StoredCard): boolean => card.decision?.kind === "pass";

function longestRun(page: readonly StoredCard[], key: (card: StoredCard) => string): number {
  let longest = 0;
  let run = 0;
  let previous: string | null = null;
  for (const card of page) {
    const value = key(card);
    run = value === previous ? run + 1 : 1;
    previous = value;
    longest = Math.max(longest, run);
  }
  return longest;
}

function heavyPairs(list: readonly StoredCard[]): number {
  let pairs = 0;
  for (let index = 1; index < list.length; index += 1) {
    const previous = list[index - 1];
    const current = list[index];
    if (previous && current && heavy(previous) && heavy(current)) {
      pairs += 1;
    }
  }
  return pairs;
}

type PageNumbers = {
  page: number;
  size: number;
  authors: Record<string, number>;
  topAuthorShare: number;
  longestAuthorRun: number;
  longestLifeAreaRun: number;
  followed: number;
  returning: number;
  heavy: number;
  heavyPairs: number;
  house: number;
  under48h: number;
  mix: Record<ThemeBucket, number>;
};

async function main(): Promise<void> {
  const email = argument("viewer");
  if (!email) {
    throw new Error("usage: pnpm db:feed-audit --viewer=<email> [--pages=4] [--json]");
  }
  const pageCount = Math.max(1, Math.min(20, Number(argument("pages") ?? 4) || 4));
  const asJson = hasFlag("json");
  const db = getDb();
  const [viewer] = await db
    .select({ id: users.id, name: users.name, initials: users.initials })
    .from(users)
    .where(and(eq(users.email, email)));
  if (!viewer) {
    throw new Error(`no account with email ${email}`);
  }

  const startedAt = new Date();
  const session = { seed: argument("seed") ?? "audit-session-0001", startedAt };
  const log = (line = ""): void => {
    if (!asJson) {
      console.log(line);
    }
  };

  await runAsOwner(viewer.id, async () => {
    const affinity = await loadViewerAffinity(viewer.id, startedAt, db);
    const following = await db
      .select({ id: follows.followeeId })
      .from(follows)
      .where(eq(follows.followerId, viewer.id));
    const followedIds = new Set(following.map((row) => row.id));
    const [decided] = await db
      .select({
        saves: sql<number>`count(*) filter (where ${cardDecisions.kind} = 'save')`.mapWith(Number),
        passes: sql<number>`count(*) filter (where ${cardDecisions.kind} = 'pass')`.mapWith(Number),
      })
      .from(cardDecisions)
      .where(eq(cardDecisions.userId, viewer.id));
    const [catalog] = await db
      .select({ cards: count() })
      .from(cards)
      .where(and(eq(cards.isPublic, true), ne(cards.userId, viewer.id)));
    const themes = [...affinity.categories.keys()].join(", ") || "none";
    const moods = [...affinity.emotions.keys()].join(", ") || "none";
    log(
      `Viewer ${viewer.name || "(no name)"} [${viewer.initials}] ${email}: confidence ${affinity.confidence.toFixed(2)}, themes ${themes}; moods ${moods}; follows ${following.length}; saved ${decided?.saves ?? 0}, passed ${decided?.passes ?? 0}`,
    );
    log(`Catalog: ${catalog?.cards ?? 0} public cards by other people and Angles\n`);

    const bucketOf = (card: StoredCard): ThemeBucket =>
      classifyTheme({ category: card.matching.category, emotions: card.emotions }, affinity);

    const show = (title: string, page: StoredCard[]): void => {
      log(`== ${title} (${page.length})`);
      for (const [index, card] of page.entries()) {
        const flags = [
          card.author.following ? "F" : "-",
          heavy(card) ? "H" : "-",
          returning(card) ? "R" : "-",
        ].join("");
        log(
          `${String(index + 1).padStart(2)}. ${ageLabel(hoursOld(card, startedAt)).padStart(6)}  ${card.category.padEnd(15)} ${bucketOf(card).padEnd(9)} ${authorLabel(card).padEnd(10)} ${flags} opens:${card.openingStyle}`,
        );
      }
      log();
    };

    // One visit, page after page, the way the phone asks when five cards are left.
    const pages: StoredCard[][] = [];
    const pageMs: number[] = [];
    const seen: string[] = [];
    let exhausted = false;
    for (let index = 0; index < pageCount && !exhausted; index += 1) {
      const began = performance.now();
      const page = await listStack({ limit: STACK_PAGE_SIZE, session, seen: [...seen] }, true);
      pageMs.push(Math.round(performance.now() - began));
      pages.push(page.cards);
      seen.push(...page.cards.map((card) => card.id));
      exhausted = page.exhausted;
      show(`Stack page ${index + 1}${page.exhausted ? " (last)" : ""}`, page.cards);
    }
    const walked = pages.flat();

    const pageNumbers: PageNumbers[] = pages.map((page, index) => {
      const authors: Record<string, number> = {};
      const mix: Record<ThemeBucket, number> = { core: 0, adjacent: 0, explore: 0 };
      for (const card of page) {
        authors[authorLabel(card)] = (authors[authorLabel(card)] ?? 0) + 1;
        mix[bucketOf(card)] += 1;
      }
      const top = Math.max(0, ...Object.values(authors));
      return {
        page: index + 1,
        size: page.length,
        authors,
        topAuthorShare: page.length ? Math.round((100 * top) / page.length) : 0,
        longestAuthorRun: longestRun(page, (card) => card.author.id),
        longestLifeAreaRun: longestRun(page, (card) => card.category),
        followed: page.filter((card) => followedIds.has(card.author.id)).length,
        returning: page.filter(returning).length,
        heavy: page.filter(heavy).length,
        heavyPairs: heavyPairs(page),
        house: page.filter((card) => card.isHouse).length,
        under48h: page.filter((card) => hoursOld(card, startedAt) < 48).length,
        mix,
      };
    });

    const duplicates = walked.length - new Set(walked.map((card) => card.id)).size;
    const ownShown = walked.filter((card) => card.isOwner).length;
    const savedShown = walked.filter((card) => card.decision?.kind === "save").length;
    const firstHouse = walked.findIndex((card) => card.isHouse);
    const communityAfterHouse =
      firstHouse === -1 ? 0 : walked.slice(firstHouse).filter((card) => !card.isHouse).length;
    const returningOverCap = pageNumbers.filter((numbers) => numbers.returning > returningCap(STACK_PAGE_SIZE)).length;
    const newestOther = [...walked]
      .filter((card) => !card.isHouse && !returning(card))
      .sort((left, right) => right.createdAt.localeCompare(left.createdAt))[0];
    const newestSlot = newestOther ? walked.findIndex((card) => card.id === newestOther.id) + 1 : null;

    const community = walked.filter((card) => !card.isHouse);
    const visitAuthors = new Map<string, number>();
    for (const card of community) {
      visitAuthors.set(card.author.id, (visitAuthors.get(card.author.id) ?? 0) + 1);
    }
    const visitTopAuthorShare = community.length
      ? Math.round((100 * Math.max(0, ...visitAuthors.values())) / community.length)
      : 0;
    const exploreShare = community.length
      ? Math.round((100 * community.filter((card) => bucketOf(card) === "explore").length) / community.length)
      : 0;
    const walkedIds = walked.map((card) => card.id);
    const decisionCounts = walkedIds.length
      ? await db
          .select({ cardId: cardDecisions.cardId, decisions: count() })
          .from(cardDecisions)
          .where(and(inArray(cardDecisions.cardId, walkedIds), ne(cardDecisions.userId, viewer.id)))
          .groupBy(cardDecisions.cardId)
      : [];
    const decisionsById = new Map(decisionCounts.map((row) => [row.cardId, row.decisions]));
    const barelyDecided = community.filter((card) => (decisionsById.get(card.id) ?? 0) < 8).length;

    const summary = {
      viewer: { email, name: viewer.name, initials: viewer.initials },
      startedAt: startedAt.toISOString(),
      seed: session.seed,
      affinity: { confidence: affinity.confidence, themes, moods },
      follows: following.length,
      decided: decided ?? { saves: 0, passes: 0 },
      catalog: catalog?.cards ?? 0,
      pages: pageNumbers,
      walked: walked.length,
      exhausted,
      duplicates,
      ownShown,
      savedShown,
      heavyPairsAcrossVisit: heavyPairs(walked),
      returningOverCapPages: returningOverCap,
      communityAfterHouse,
      newestOtherSlot: newestSlot,
      visitAuthors: visitAuthors.size,
      visitTopAuthorShare,
      exploreShare,
      barelyDecided,
      pageMs,
    };

    if (asJson) {
      console.log(JSON.stringify(summary, null, 2));
      return;
    }

    log("== Numbers");
    for (const numbers of pageNumbers) {
      log(
        `Page ${numbers.page}: ${numbers.size} cards; authors ${Object.entries(numbers.authors)
          .map(([label, count]) => `${label} ${count}`)
          .join(", ")}; top author ${numbers.topAuthorShare}%; longest same-author run ${numbers.longestAuthorRun}; longest life-area run ${numbers.longestLifeAreaRun}; followed ${numbers.followed}; returning ${numbers.returning}; heavy ${numbers.heavy} (pairs ${numbers.heavyPairs}); house ${numbers.house}; under 48h ${numbers.under48h}; mix core ${numbers.mix.core}/adjacent ${numbers.mix.adjacent}/explore ${numbers.mix.explore}`,
      );
    }
    log(`Walked ${walked.length} cards over ${pages.length} pages${exhausted ? ", to the end card" : ""}`);
    log(`Repeats ${duplicates}, own cards ${ownShown}, saved cards ${savedShown} (want 0, 0, 0)`);
    log(`Heavy cards side by side across the visit: ${heavyPairs(walked)} (want 0 unless only heavy cards are left)`);
    log(`Pages over the returning cap of ${returningCap(STACK_PAGE_SIZE)}: ${returningOverCap} (want 0)`);
    log(`Community cards after the first house card: ${communityAfterHouse} (want 0)`);
    log(`Newest community post is card ${newestSlot ?? "not reached"} (want 1 to 6)`);
    log(
      `Across the visit: ${visitAuthors.size} authors, top author ${visitTopAuthorShare}% of community cards (want about 10% or less)`,
    );
    log(`Explore cards ${exploreShare}% of community cards (want about 25% once themes are known)`);
    log(`Cards fewer than 8 people have decided on: ${barelyDecided} of ${community.length}`);
    log(`Page times: ${pageMs.map((ms) => `${ms} ms`).join(", ")} (the first page builds the visit)`);
  });
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : "audit_failed");
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
