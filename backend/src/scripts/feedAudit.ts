/**
 * Read the ranked feed the way the app does, and grade it.
 *
 *   pnpm db:feed-audit --viewer=you@example.com
 *
 * Calls `listRankedFeed` for All and each style tab as that account (one visit, one
 * session), prints the first page of each, and prints the numbers the feed is meant to
 * hold: time first, tabs that differ, no kept angle coming back. Read-only.
 */
import { and, eq } from "drizzle-orm";
import { runAsOwner } from "../lib/authStub.js";
import { classifyTheme, type ThemeBucket } from "../lib/feedRanking.js";
import { STYLES, type StoredCard, type Style } from "../types/index.js";
import { closePool, getDb } from "../db/client.js";
import { listFeed, listRankedFeed, loadViewerAffinity } from "../db/feed.js";
import { users } from "../db/schema.js";

const PAGE = 24;

function argument(name: string): string | undefined {
  const flag = process.argv.slice(2).find((item) => item.startsWith(`--${name}=`));
  return flag?.slice(name.length + 3).trim() || undefined;
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

async function main(): Promise<void> {
  const email = argument("viewer");
  if (!email) {
    throw new Error("usage: pnpm db:feed-audit --viewer=<email>");
  }
  const db = getDb();
  const [viewer] = await db
    .select({ id: users.id })
    .from(users)
    .where(and(eq(users.email, email)));
  if (!viewer) {
    throw new Error(`no account with email ${email}`);
  }

  const startedAt = new Date();
  const session = { seed: "audit-session-0001", startedAt, offset: 0 };
  const now = new Date(startedAt.getTime() + 1);

  await runAsOwner(viewer.id, async () => {
    const affinity = await loadViewerAffinity(viewer.id, now, db);
    const themes = [...affinity.categories.keys()].join(", ") || "none";
    const moods = [...affinity.emotions.keys()].join(", ") || "none";
    console.log(`Viewer ${email}: confidence ${affinity.confidence.toFixed(2)}, themes ${themes}; moods ${moods}\n`);

    const all = await listRankedFeed({ limit: PAGE, session });
    const tabs = new Map<Style, StoredCard[]>();
    for (const style of STYLES) {
      tabs.set(style, await listRankedFeed({ limit: PAGE, style, session }));
    }

    const bucketOf = (card: StoredCard): ThemeBucket =>
      classifyTheme({ category: card.matching.category, emotions: card.emotions }, affinity);

    const show = (title: string, page: StoredCard[]): void => {
      console.log(`== ${title} (${page.length})`);
      for (const [index, card] of page.entries()) {
        const kept = keptAngles(card);
        console.log(
          `${String(index + 1).padStart(2)}. ${ageLabel(hoursOld(card, now)).padStart(6)}  ${card.category.padEnd(15)} ${bucketOf(card).padEnd(9)} ${card.author.initials.padEnd(2)} hearts:${kept.join(",") || "-"}`,
        );
      }
      console.log("");
    };
    show("All", all);
    for (const style of STYLES) {
      show(style, tabs.get(style) ?? []);
    }

    // Time first: what share of the page is recent, and is the newest post near the top?
    const recent = all.filter((card) => hoursOld(card, now) < 48).length;
    const inLast48h = (await listFeed({ limit: 200 })).filter((card) => hoursOld(card, now) < 48);
    const newest = (await listFeed({ limit: 60 })).find((card) => keptAngles(card).length === 0);
    const newestRank = newest ? all.findIndex((card) => card.id === newest.id) : -1;

    console.log("== Numbers");
    console.log(
      `Under 48h on All: ${recent}/${all.length} (${Math.round((100 * recent) / Math.max(1, all.length))}%), ${inLast48h.length} such posts exist`,
    );
    console.log(
      `Newest visible post is slot ${newestRank === -1 ? "not on page 1" : newestRank + 1} (want 1 to 6)`,
    );

    const overlaps: string[] = [];
    let worst = 0;
    for (const [left, right] of STYLES.flatMap((a, i) => STYLES.slice(i + 1).map((b) => [a, b] as const))) {
      const rightIds = new Set((tabs.get(right) ?? []).map((card) => card.id));
      const shared = (tabs.get(left) ?? []).filter((card) => rightIds.has(card.id)).length;
      worst = Math.max(worst, shared);
      overlaps.push(`${left}/${right} ${shared}`);
    }
    // Posts under 6h old are not held back from any tab, and a thin explore pool can only
    // fill a page's explore share with the same few cards, so read the worst figure with
    // those two numbers beside it.
    const everyone = await listFeed({ limit: 400 });
    const pool: Record<ThemeBucket, number> = { core: 0, adjacent: 0, explore: 0 };
    for (const card of everyone) {
      pool[bucketOf(card)] += 1;
    }
    const fresh = all.filter((card) => hoursOld(card, now) < 6).length;
    console.log(
      `Tab overlap of ${PAGE}: ${overlaps.join(", ")} (worst ${worst}; ${fresh} posts under 6h are shared by design, explore pool is ${pool.explore} of ${everyone.length})`,
    );

    const counts: Record<ThemeBucket, number> = { core: 0, adjacent: 0, explore: 0 };
    for (const card of all) {
      counts[bucketOf(card)] += 1;
    }
    console.log(`Mix on All: core ${counts.core}, adjacent ${counts.adjacent}, explore ${counts.explore}`);

    const leaked =
      all.filter((card) => keptAngles(card).length > 0).length +
      STYLES.reduce(
        (sum, style) =>
          sum + (tabs.get(style) ?? []).filter((card) => keptAngles(card).includes(style)).length,
        0,
      );
    console.log(`Kept angles that came back: ${leaked} (want 0)`);
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
