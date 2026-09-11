/**
 * Seed fake community users and public cards for Home.
 *
 *   docker compose up -d
 *   pnpm db:migrate
 *   pnpm db:seed-community
 *
 * Re-running deletes non-JM users and their cards, then inserts the fixture.
 * Does not call the live LLM. JM's library is left in place.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { ne } from "drizzle-orm";
import { DEV_USER_ID } from "../lib/authStub.js";
import { intensityBand, type Category, type Emotion, type Style, type Timeframe } from "../types/index.js";
import { getDb, closePool } from "../db/client.js";
import { cardReframes, cardTags, cards, tags, users } from "../db/schema.js";
import { titleCase } from "../lib/slugs.js";
import type { CommunityFixture } from "./communityCopy.js";

function loadFixture(): CommunityFixture {
  const path = resolve(process.cwd(), "fixtures/community.json");
  return JSON.parse(readFileSync(path, "utf8")) as CommunityFixture;
}

async function main(): Promise<void> {
  const fixture = loadFixture();
  if (fixture.users.some((user) => user.id === DEV_USER_ID)) {
    throw new Error("fixture includes DEV_USER_ID");
  }
  if (fixture.posts.some((post) => post.userId === DEV_USER_ID)) {
    throw new Error("fixture post authored by DEV_USER_ID");
  }

  const db = getDb();
  await db.delete(cards).where(ne(cards.userId, DEV_USER_ID));
  await db.delete(users).where(ne(users.id, DEV_USER_ID));

  await db.insert(users).values(fixture.users.map((user) => ({ id: user.id, initials: user.initials })));

  const allSlugs = [...new Set(fixture.posts.flatMap((post) => post.tags))];
  if (allSlugs.length > 0) {
    await db
      .insert(tags)
      .values(allSlugs.map((slug) => ({ slug, label: titleCase(slug) })))
      .onConflictDoNothing({ target: tags.slug });
  }
  const tagRows = allSlugs.length > 0 ? await db.select().from(tags) : [];
  const tagBySlug = new Map(tagRows.map((row) => [row.slug, row.id]));

  for (const post of fixture.posts) {
    await db.insert(cards).values({
      id: post.id,
      userId: post.userId,
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
      model: "mistral-small-latest",
      spotlightStyle: post.spotlightStyle as Style,
      isPublic: true,
      createdAt: new Date(post.createdAt),
    });
    await db.insert(cardReframes).values(
      post.results.map((result, position) => ({
        cardId: post.id,
        style: result.style as Style,
        reframe: result.reframe,
        position,
      })),
    );
    const joins = post.tags.flatMap((slug) => {
      const tagId = tagBySlug.get(slug);
      return tagId ? [{ cardId: post.id, tagId }] : [];
    });
    if (joins.length > 0) {
      await db.insert(cardTags).values(joins);
    }
  }

  console.log(`Seeded ${fixture.users.length} users and ${fixture.posts.length} public cards.`);
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
