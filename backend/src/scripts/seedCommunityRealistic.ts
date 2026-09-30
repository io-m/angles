/**
 * Reshape the seeded community into something that behaves like real use.
 *
 *   pnpm db:seed-realistic
 *   pnpm db:seed-realistic --viewer=you@example.com   # also give that account a taste
 *
 * The fixture posts are flat and weeks old (see `communityShape.ts`). This re-dates them
 * relative to now, skews authors, intensity and themes, and adds readers with hearts, so
 * a feed ranked on time, hearts and themes has something real to rank. Re-run it any time
 * to move everything back to "now".
 *
 * Non-destructive by design (unlike `seedCommunity`, which deletes every user but the dev
 * one, including a real phone account). It only touches:
 *  - the fixture community cards and their authors, by updating them,
 *  - its own `seed-reader-*` accounts and their hearts,
 *  - with `--viewer`, that account's hearts on community cards.
 * No users or cards are deleted, and there are no LLM calls.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { and, eq, inArray, like } from "drizzle-orm";
import { DEV_USER_ID } from "../lib/authStub.js";
import type { Category, Style } from "../types/index.js";
import { closePool, getDb } from "../db/client.js";
import { cardReframes, cards, savedAngles, users } from "../db/schema.js";
import type { CommunityFixture } from "./communityCopy.js";
import {
  READER_EMAIL_PREFIX,
  mulberry32,
  planPosts,
  planReaders,
  planViewerHearts,
  type HeartableCard,
  type HeartPlan,
} from "./communityShape.js";
import { assertCommunitySeedAllowed } from "./seedCommunityGuard.js";

const SEED = 20260930;

function loadFixture(): CommunityFixture {
  const path = resolve(process.cwd(), "fixtures/community.json");
  return JSON.parse(readFileSync(path, "utf8")) as CommunityFixture;
}

function viewerEmail(argv: readonly string[]): string | undefined {
  const flag = argv.find((argument) => argument.startsWith("--viewer="));
  const value = flag?.slice("--viewer=".length).trim();
  return value ? value : undefined;
}

function histogram(values: readonly number[], edges: readonly number[]): string {
  const counts = new Array<number>(edges.length + 1).fill(0);
  for (const value of values) {
    const index = edges.findIndex((edge) => value < edge);
    counts[index === -1 ? edges.length : index] = (counts[index === -1 ? edges.length : index] ?? 0) + 1;
  }
  return counts.join(" / ");
}

async function main(): Promise<void> {
  assertCommunitySeedAllowed();
  const fixture = loadFixture();
  if (fixture.users.some((user) => user.id === DEV_USER_ID)) {
    throw new Error("fixture includes DEV_USER_ID");
  }
  const db = getDb();
  const now = new Date();
  const rng = mulberry32(SEED);

  const cardIds = fixture.posts.map((post) => post.id);
  const present = await db.select({ id: cards.id }).from(cards).where(inArray(cards.id, cardIds));
  if (present.length !== cardIds.length) {
    throw new Error(
      `expected ${cardIds.length} community cards, found ${present.length} — run pnpm db:seed-community first`,
    );
  }

  const plan = planPosts(
    fixture.posts.map((post) => ({ id: post.id, category: post.category })),
    fixture.users.map((user) => user.id),
    now,
    rng,
  );
  for (const item of plan) {
    await db
      .update(cards)
      .set({
        userId: item.userId,
        createdAt: item.createdAt,
        intensity: item.intensity,
        intensityBand: item.intensityBand,
        isPublic: true,
      })
      .where(eq(cards.id, item.id));
  }

  const stylesByCard = new Map<string, Style[]>();
  const angleRows = await db
    .select({ cardId: cardReframes.cardId, style: cardReframes.style })
    .from(cardReframes)
    .where(inArray(cardReframes.cardId, cardIds));
  for (const row of angleRows) {
    stylesByCard.set(row.cardId, [...(stylesByCard.get(row.cardId) ?? []), row.style]);
  }
  const categoryByCard = new Map(fixture.posts.map((post) => [post.id, post.category as Category]));
  const heartable: HeartableCard[] = plan.map((item) => ({
    id: item.id,
    category: categoryByCard.get(item.id) ?? "other",
    createdAt: item.createdAt,
    styles: stylesByCard.get(item.id) ?? [],
  }));

  // Readers are ours: replace them, and their hearts cascade away with them.
  await db.delete(users).where(like(users.email, `${READER_EMAIL_PREFIX}%`));
  const readers = planReaders(heartable, now, rng);
  await db.insert(users).values(
    readers.map((reader) => ({
      id: reader.id,
      initials: reader.initials,
      name: reader.initials,
      email: `${READER_EMAIL_PREFIX}${reader.id}@angles.invalid`,
    })),
  );
  const readerHearts = readers.flatMap((reader) => reader.hearts);
  for (let start = 0; start < readerHearts.length; start += 500) {
    await db.insert(savedAngles).values(readerHearts.slice(start, start + 500)).onConflictDoNothing();
  }

  let viewerNote = "no --viewer given";
  const email = viewerEmail(process.argv.slice(2));
  if (email) {
    const [viewer] = await db.select({ id: users.id }).from(users).where(eq(users.email, email));
    if (!viewer) {
      throw new Error(`no account with email ${email}`);
    }
    if (viewer.id === DEV_USER_ID || viewer.id.startsWith("00000000-0000-4000-8")) {
      throw new Error("--viewer must be a real account, not a seeded one");
    }
    const removed = await db
      .delete(savedAngles)
      .where(and(eq(savedAngles.userId, viewer.id), inArray(savedAngles.cardId, cardIds)))
      .returning({ cardId: savedAngles.cardId });
    const hearts: HeartPlan[] = planViewerHearts(viewer.id, heartable, now, rng);
    if (hearts.length > 0) {
      await db.insert(savedAngles).values(hearts).onConflictDoNothing();
    }
    viewerNote = `${email}: replaced ${removed.length} heart(s) on community cards with ${hearts.length} (${[
      ...new Set(hearts.map((heart) => categoryByCard.get(heart.cardId))),
    ].join(", ")}; ${[...new Set(hearts.map((heart) => heart.style))].join(", ")})`;
  }

  const hoursOld = plan.map((item) => (now.getTime() - item.createdAt.getTime()) / 3_600_000);
  const perCard = new Map<string, number>();
  for (const heart of readerHearts) {
    perCard.set(heart.cardId, (perCard.get(heart.cardId) ?? 0) + 1);
  }
  const perAuthor = new Map<string, number>();
  for (const item of plan) {
    perAuthor.set(item.userId, (perAuthor.get(item.userId) ?? 0) + 1);
  }
  const perCategory = new Map<string, number>();
  for (const item of plan) {
    const category = categoryByCard.get(item.id) ?? "other";
    perCategory.set(category, (perCategory.get(category) ?? 0) + 1);
  }

  console.log(`Re-dated ${plan.length} community posts relative to ${now.toISOString()}.`);
  console.log(`Age (<2h / <24h / <48h / <7d / <30d / older): ${histogram(hoursOld, [2, 24, 48, 168, 720])}`);
  console.log(
    `Posts per author: max ${Math.max(...perAuthor.values())}, median ${
      [...perAuthor.values()].sort((left, right) => left - right)[Math.floor(perAuthor.size / 2)]
    }, authors ${perAuthor.size}`,
  );
  console.log(
    `Readers ${readers.length}, hearts ${readerHearts.length}; posts with 0 hearts ${
      plan.filter((item) => !perCard.has(item.id)).length
    }, max on one post ${Math.max(0, ...perCard.values())}`,
  );
  console.log(`Viewer: ${viewerNote}`);
  console.log(`Posts per life area: ${[...perCategory.entries()].map(([key, count]) => `${key} ${count}`).join(", ")}`);
}

main()
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.message : "seed_failed";
    console.error(message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
