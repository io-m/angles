/**
 * Append a few public cards timestamped now, so pull-to-refresh has something
 * newer to find. Home is strictly newest-first, and `seedCommunity` re-inserts
 * the same fixture rows with the same historical timestamps, so a refresh after
 * it can only ever return the identical page.
 *
 *   pnpm db:seed-recent        # 3 cards
 *   pnpm db:seed-recent 8      # 8 cards
 *
 * Appends only: nothing is deleted, and JM's library is untouched. Copy is
 * reused from the fixture, but every card gets a fresh id and `createdAt`.
 */
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { ne } from "drizzle-orm";
import { DEV_USER_ID } from "../lib/authStub.js";
import { intensityBand, type Category, type Emotion, type Style, type Timeframe } from "../types/index.js";
import { getDb, closePool } from "../db/client.js";
import { cardReframes, cardTags, cards, tags, users } from "../db/schema.js";
import { titleCase } from "../lib/slugs.js";
import type { CommunityFixture, CommunityPost } from "./communityCopy.js";
import { assertCommunitySeedAllowed } from "./seedCommunityGuard.js";

const DEFAULT_COUNT = 3;
const MAX_COUNT = 50;
const SEED_MODELS = ["mistral-small-latest", "gemini-3.8-flash", "deepseek-flash"] as const;

function loadFixture(): CommunityFixture {
  const path = resolve(process.cwd(), "fixtures/community.json");
  return JSON.parse(readFileSync(path, "utf8")) as CommunityFixture;
}

function requestedCount(argument: string | undefined): number {
  if (argument === undefined) {
    return DEFAULT_COUNT;
  }
  const parsed = Number.parseInt(argument, 10);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > MAX_COUNT) {
    throw new Error(`count must be an integer between 1 and ${MAX_COUNT}`);
  }
  return parsed;
}

function pick<T>(items: readonly T[], index: number): T {
  return items[index % items.length]!;
}

async function main(): Promise<void> {
  assertCommunitySeedAllowed();
  const count = requestedCount(process.argv[2]);
  const fixture = loadFixture();
  const db = getDb();

  // Authors must already exist, so this cannot create orphan rows.
  const authors = await db
    .select({ id: users.id })
    .from(users)
    .where(ne(users.id, DEV_USER_ID));
  if (authors.length === 0) {
    throw new Error("no community users found — run pnpm db:seed-community first");
  }

  const chosen: CommunityPost[] = [];
  const offset = Math.floor(Math.random() * fixture.posts.length);
  for (let index = 0; index < count; index += 1) {
    chosen.push(pick(fixture.posts, offset + index));
  }

  const slugs = [...new Set(chosen.flatMap((post) => post.tags))];
  if (slugs.length > 0) {
    await db
      .insert(tags)
      .values(slugs.map((slug) => ({ slug, label: titleCase(slug) })))
      .onConflictDoNothing({ target: tags.slug });
  }
  const tagRows = slugs.length > 0 ? await db.select().from(tags) : [];
  const tagBySlug = new Map(tagRows.map((row) => [row.slug, row.id]));

  const now = Date.now();
  for (const [index, post] of chosen.entries()) {
    const id = randomUUID();
    // Newest first, one second apart, so ordering is deterministic.
    const createdAt = new Date(now - index * 1000);
    await db.insert(cards).values({
      id,
      userId: pick(authors, offset + index).id,
      thoughtEn: post.thought,
      thoughtOriginal: post.thoughtOriginal ?? null,
      inputLanguage: post.inputLanguage,
      category: post.category as Category,
      intensity: post.intensity,
      intensityBand: intensityBand(post.intensity),
      timeframe: post.timeframe as Timeframe,
      safety: "none",
      emotions: post.emotions as Emotion[],
      skippedStyles: [],
      model: pick(SEED_MODELS, index),
      spotlightStyle: post.spotlightStyle as Style,
      isPublic: true,
      createdAt,
    });
    await db.insert(cardReframes).values(
      post.results.map((result, position) => ({
        cardId: id,
        style: result.style as Style,
        reframe: result.reframe,
        position,
      })),
    );
    const joins = post.tags.flatMap((slug) => {
      const tagId = tagBySlug.get(slug);
      return tagId ? [{ cardId: id, tagId }] : [];
    });
    if (joins.length > 0) {
      await db.insert(cardTags).values(joins);
    }
  }

  console.log(`Appended ${count} public card(s) dated now. Pull to refresh on Home.`);
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
