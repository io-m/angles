/**
 * Reshape the seeded community into something that behaves like real use.
 *
 *   pnpm db:seed-realistic
 *   pnpm db:seed-realistic --viewer=you@example.com   # also give that account a taste
 *
 * The fixture posts are flat and weeks old (see `communityShape.ts`). This re-dates them
 * relative to now, skews authors, intensity and themes, and adds readers who save and
 * pass, so a stack ranked on time, saves and themes has something real to rank. Re-run it any time
 * to move everything back to "now".
 *
 * Non-destructive by design (unlike `seedCommunity`, which deletes every user but the dev
 * one, including a real phone account). It only touches:
 *  - the fixture community cards and their authors, by updating them,
 *  - its own `seed-reader-*` accounts and their decisions,
 *  - with `--viewer`, that account's decisions on community cards.
 * No users or cards are deleted, and there are no LLM calls.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { and, eq, inArray, like } from "drizzle-orm";
import { DEV_USER_ID } from "../lib/authStub.js";
import { STEP_DEFAULT_MODELS } from "../lib/llmClient.js";
import type { Category, Style } from "../types/index.js";
import { closePool, getDb } from "../db/client.js";
import { cardDecisions, cardReframes, cards, users } from "../db/schema.js";
import type { CommunityFixture } from "./communityCopy.js";
import {
  READER_EMAIL_PREFIX,
  mulberry32,
  planPosts,
  planReaders,
  planViewerDecisions,
  type DecidableCard,
  type DecisionPlan,
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
        model: STEP_DEFAULT_MODELS.writer,
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
  const decidable: DecidableCard[] = plan.map((item) => ({
    id: item.id,
    category: categoryByCard.get(item.id) ?? "other",
    createdAt: item.createdAt,
    styles: stylesByCard.get(item.id) ?? [],
  }));

  // Readers are ours: replace them, and their decisions cascade away with them.
  await db.delete(users).where(like(users.email, `${READER_EMAIL_PREFIX}%`));
  const readers = planReaders(decidable, now, rng);
  await db.insert(users).values(
    readers.map((reader) => ({
      id: reader.id,
      initials: reader.initials,
      name: reader.initials,
      email: `${READER_EMAIL_PREFIX}${reader.id}@angles.invalid`,
    })),
  );
  const readerDecisions = readers.flatMap((reader) => reader.decisions);
  for (let start = 0; start < readerDecisions.length; start += 500) {
    await db.insert(cardDecisions).values(readerDecisions.slice(start, start + 500)).onConflictDoNothing();
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
      .delete(cardDecisions)
      .where(and(eq(cardDecisions.userId, viewer.id), inArray(cardDecisions.cardId, cardIds)))
      .returning({ cardId: cardDecisions.cardId });
    const decisions: DecisionPlan[] = planViewerDecisions(viewer.id, decidable, now, rng);
    if (decisions.length > 0) {
      await db.insert(cardDecisions).values(decisions).onConflictDoNothing();
    }
    const saves = decisions.filter((decision) => decision.kind === "save");
    viewerNote = `${email}: replaced ${removed.length} decision(s) on community cards with ${saves.length} save(s) (${[
      ...new Set(saves.map((decision) => categoryByCard.get(decision.cardId))),
    ].join(", ")}; ${[...new Set(saves.map((decision) => decision.style))].join(", ")}) and ${
      decisions.length - saves.length
    } pass(es)`;
  }

  const hoursOld = plan.map((item) => (now.getTime() - item.createdAt.getTime()) / 3_600_000);
  const perCard = new Map<string, number>();
  for (const decision of readerDecisions) {
    if (decision.kind === "save") {
      perCard.set(decision.cardId, (perCard.get(decision.cardId) ?? 0) + 1);
    }
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
    `Readers ${readers.length}, decisions ${readerDecisions.length}; posts with 0 saves ${
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
