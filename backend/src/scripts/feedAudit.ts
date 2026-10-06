/**
 * Read the ranked feed the way the app does, and grade it.
 *
 *   pnpm db:feed-audit --viewer=you@example.com [--pages=3] [--json]
 *
 * Production (no public database URL; the image ships this script):
 *
 *   railway ssh --service api --environment production \
 *     "node dist/scripts/feedAudit.js --viewer=you@example.com"
 *
 * Calls `listRankedFeed` for For you (several pages of one visit) and each style tab's
 * first page as that account, prints each page, and prints the numbers the feed is meant
 * to hold: time first, a mix of authors, at most one own card a page, followed share,
 * no repeats across pages, no old post coming back as "new" on a pull, and no fully kept
 * card coming back. Read-only. Prints no thought or answer text.
 */
import { and, eq } from "drizzle-orm";
import { runAsOwner } from "../lib/authStub.js";
import { classifyTheme, type ThemeBucket } from "../lib/feedRanking.js";
import { STYLES, type StoredCard, type Style } from "../types/index.js";
import { closePool, getDb } from "../db/client.js";
import { listFeed, listRankedFeed, loadViewerAffinity } from "../db/feed.js";
import { follows, users } from "../db/schema.js";

const PAGE = 24;

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

function keptAngles(card: StoredCard): Style[] {
  return card.results.filter((item) => item.isFavorite).map((item) => item.style);
}

function isFullyKept(card: StoredCard): boolean {
  return card.results.length > 0 && card.results.every((item) => item.isFavorite);
}

function isPartlyKept(card: StoredCard): boolean {
  const kept = keptAngles(card).length;
  return kept > 0 && kept < card.results.length;
}

/** Initials plus a short id, because two people can share initials. */
function authorLabel(card: StoredCard): string {
  return card.isOwner ? `${card.author.initials}(me)` : `${card.author.initials}#${card.author.id.slice(-4)}`;
}

function cursorOf(card: StoredCard): string {
  return `${card.createdAt}|${card.id}`;
}

type PageNumbers = {
  page: number;
  size: number;
  authors: Record<string, number>;
  topAuthorShare: number;
  own: number;
  followed: number;
  partlyKept: number;
  fullyKept: number;
  under48h: number;
  mix: Record<ThemeBucket, number>;
  longestAuthorRun: number;
};

function longestAuthorRun(page: readonly StoredCard[]): number {
  let longest = 0;
  let run = 0;
  let previous: string | null = null;
  for (const card of page) {
    run = card.author.id === previous ? run + 1 : 1;
    previous = card.author.id;
    longest = Math.max(longest, run);
  }
  return longest;
}

async function main(): Promise<void> {
  const email = argument("viewer");
  if (!email) {
    throw new Error("usage: pnpm db:feed-audit --viewer=<email> [--pages=3] [--json]");
  }
  const pageCount = Math.max(1, Math.min(10, Number(argument("pages") ?? 3) || 3));
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
  const seed = argument("seed") ?? "audit-session-0001";
  const now = new Date(startedAt.getTime() + 1);
  const log = (line = ""): void => {
    if (!asJson) {
      console.log(line);
    }
  };

  await runAsOwner(viewer.id, async () => {
    const affinity = await loadViewerAffinity(viewer.id, now, db);
    const following = await db
      .select({ id: follows.followeeId })
      .from(follows)
      .where(eq(follows.followerId, viewer.id));
    const themes = [...affinity.categories.keys()].join(", ") || "none";
    const moods = [...affinity.emotions.keys()].join(", ") || "none";
    log(
      `Viewer ${viewer.name || "(no name)"} [${viewer.initials}] ${email}: confidence ${affinity.confidence.toFixed(2)}, themes ${themes}; moods ${moods}; follows ${following.length}`,
    );

    // The catalog as a chronological reader would see it, before any ranking or hiding.
    const catalog = await listFeed({ limit: 500 });
    const byAuthor = new Map<string, number>();
    for (const card of catalog) {
      byAuthor.set(authorLabel(card), (byAuthor.get(authorLabel(card)) ?? 0) + 1);
    }
    const authorIds = [...new Set(catalog.map((card) => card.author.id))];
    const followedIds = new Set(
      following.map((row) => row.id).filter((id) => authorIds.includes(id)),
    );
    log(
      `Catalog: ${catalog.length} public cards by ${authorIds.length} authors (${[...byAuthor.entries()]
        .sort((left, right) => right[1] - left[1])
        .map(([label, count]) => `${label} ${count}`)
        .join(", ")}); ${catalog.filter(isFullyKept).length} fully kept, ${catalog.filter(isPartlyKept).length} partly kept by the viewer\n`,
    );

    const bucketOf = (card: StoredCard): ThemeBucket =>
      classifyTheme({ category: card.matching.category, emotions: card.emotions }, affinity);

    const show = (title: string, page: StoredCard[]): void => {
      log(`== ${title} (${page.length})`);
      for (const [index, card] of page.entries()) {
        const kept = keptAngles(card);
        log(
          `${String(index + 1).padStart(2)}. ${ageLabel(hoursOld(card, now)).padStart(6)}  ${card.category.padEnd(15)} ${bucketOf(card).padEnd(9)} ${authorLabel(card).padEnd(10)} ${card.author.following ? "F" : "-"} cover:${card.spotlightStyle.padEnd(10)} kept:${kept.join(",") || "-"}`,
        );
      }
      log();
    };

    // For you, page after page, the way load more walks one visit.
    const pages: StoredCard[][] = [];
    let arrivalsAfter: string | undefined;
    for (let index = 0; index < pageCount; index += 1) {
      const ranked = await listRankedFeed({
        limit: PAGE,
        session: { seed, startedAt, offset: index * PAGE },
      });
      const page = ranked.cards;
      arrivalsAfter ??= ranked.arrivalsAfter;
      pages.push(page);
      show(`For you page ${index + 1}`, page);
      if (page.length < PAGE) {
        break;
      }
    }
    const first = pages[0] ?? [];

    const tabs = new Map<Style, StoredCard[]>();
    for (const style of STYLES) {
      const { cards: page } = await listRankedFeed({
        limit: PAGE,
        style,
        session: { seed, startedAt, offset: 0 },
      });
      tabs.set(style, page);
      show(style, page);
    }

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
        own: page.filter((card) => card.isOwner).length,
        followed: page.filter((card) => !card.isOwner && followedIds.has(card.author.id)).length,
        partlyKept: page.filter(isPartlyKept).length,
        fullyKept: page.filter(isFullyKept).length,
        under48h: page.filter((card) => hoursOld(card, now) < 48).length,
        mix,
        longestAuthorRun: longestAuthorRun(page),
      };
    });

    // Paging: the same visit must neither repeat a card nor skip one.
    const seen = new Set<string>();
    let duplicates = 0;
    for (const page of pages) {
      for (const card of page) {
        if (seen.has(card.id)) {
          duplicates += 1;
        }
        seen.add(card.id);
      }
    }

    // A pull right after page 1. The phone asks for posts newer than its arrival mark.
    // Through build 25 that mark was the newest card on screen; anything the server already
    // had at `startedAt` that comes back is an old post announced as new.
    const phoneMark = first.reduce<StoredCard | null>(
      (newest, card) =>
        !newest ||
        card.createdAt > newest.createdAt ||
        (card.createdAt === newest.createdAt && card.id > newest.id)
          ? card
          : newest,
      null,
    );
    const fakeArrivalsFromScreen = phoneMark
      ? (await listFeed({ limit: 200, after: { createdAt: new Date(phoneMark.createdAt), id: phoneMark.id } }))
          .filter((card) => new Date(card.createdAt) <= startedAt).length
      : 0;
    // The same pull from build 26 on: after the server's mark, with ranked visibility.
    const [markAt, markId] = arrivalsAfter?.split("|") ?? [];
    const fakeArrivalsFromServerMark =
      markAt && markId
        ? (
            await listFeed(
              { limit: 200, after: { createdAt: new Date(markAt), id: markId } },
              { rankedArrivals: true },
            )
          ).filter((card) => new Date(card.createdAt) <= startedAt).length
        : null;

    const newestVisible = catalog.find((card) => !isFullyKept(card) && !card.isOwner);
    const newestRank = newestVisible ? first.findIndex((card) => card.id === newestVisible.id) : -1;

    const overlaps: Record<string, number> = {};
    for (const [left, right] of STYLES.flatMap((a, i) => STYLES.slice(i + 1).map((b) => [a, b] as const))) {
      const rightIds = new Set((tabs.get(right) ?? []).map((card) => card.id));
      overlaps[`${left}/${right}`] = (tabs.get(left) ?? []).filter((card) => rightIds.has(card.id)).length;
    }

    const leakedForYou = pages.flat().filter(isFullyKept).length;
    const leakedTabs = STYLES.reduce(
      (sum, style) =>
        sum + (tabs.get(style) ?? []).filter((card) => keptAngles(card).includes(style)).length,
      0,
    );

    const summary = {
      viewer: { email, name: viewer.name, initials: viewer.initials },
      startedAt: startedAt.toISOString(),
      seed,
      affinity: { confidence: affinity.confidence, themes, moods },
      follows: following.length,
      followedAuthorsWithPosts: followedIds.size,
      catalog: {
        cards: catalog.length,
        authors: authorIds.length,
        byAuthor: Object.fromEntries(byAuthor),
        fullyKept: catalog.filter(isFullyKept).length,
        partlyKept: catalog.filter(isPartlyKept).length,
      },
      pages: pageNumbers,
      duplicatesAcrossPages: duplicates,
      distinctCardsReached: seen.size,
      fakeArrivalsFromScreen,
      fakeArrivalsFromServerMark,
      newestVisibleOtherSlot: newestRank === -1 ? null : newestRank + 1,
      tabOverlap: overlaps,
      keptLeaks: { forYouFullyKept: leakedForYou, tabsOwnAngle: leakedTabs },
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
          .join(", ")}; top author ${numbers.topAuthorShare}%; longest same-author run ${numbers.longestAuthorRun}; own ${numbers.own}; followed ${numbers.followed}; partly kept ${numbers.partlyKept}; under 48h ${numbers.under48h}; mix core ${numbers.mix.core}/adjacent ${numbers.mix.adjacent}/explore ${numbers.mix.explore}`,
      );
    }
    log(`Repeats across ${pages.length} pages: ${duplicates} (want 0); distinct cards reached ${seen.size}`);
    log(`Old posts a pull right after page 1 would call new, build 25 and earlier (screen mark): ${fakeArrivalsFromScreen}`);
    log(
      `Old posts a pull right after page 1 would call new, build 26 on (server mark): ${fakeArrivalsFromServerMark ?? "n/a"} (want 0)`,
    );
    log(
      `Newest post by someone else is slot ${newestRank === -1 ? "not on page 1" : newestRank + 1} (want 1 to 6)`,
    );
    log(
      `Tab overlap of ${PAGE}: ${Object.entries(overlaps)
        .map(([pair, count]) => `${pair} ${count}`)
        .join(", ")}`,
    );
    log(`Fully kept cards on For you: ${leakedForYou}; kept tab angles on their tab: ${leakedTabs} (want 0 and 0)`);
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
