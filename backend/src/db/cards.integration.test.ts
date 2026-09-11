import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { STYLES, type CreateCardInput } from "../types/index.js";
import { DbError } from "./client.js";

function loadTestDatabaseUrl(): void {
  if (process.env.DATABASE_URL_TEST) {
    return;
  }

  let raw: string;
  try {
    raw = readFileSync(resolve(process.cwd(), ".env"), "utf8");
  } catch {
    return;
  }

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("DATABASE_URL_TEST=")) {
      continue;
    }
    let value = trimmed.slice("DATABASE_URL_TEST=".length).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\"")) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env.DATABASE_URL_TEST = value;
  }
}

loadTestDatabaseUrl();
const testUrl = process.env.DATABASE_URL_TEST;
if (testUrl) {
  process.env.DATABASE_URL = testUrl;
}

const { closePool, getSql } = await import("./client.js");
const { createCard, deleteCard, getCard, listCards, patchCard } = await import("./cards.js");
const { cardReframes, cards, tags } = await import("./schema.js");

const baseInput: CreateCardInput = {
  thought: "I bombed my interview and I keep replaying every shaky answer.",
  results: STYLES.map((style) => ({ style, reframe: `A ${style} take on showing up.` })),
  meta: {
    category: "work",
    tags: ["job_interview", "shame"],
    intensity: 4,
    timeframe: "past",
    emotions: ["shame", "fear"],
    safety: "none",
    inputLanguage: "en",
    skippedStyles: [],
  },
  model: "mistral-small-latest",
  spotlightStyle: "stoic",
};

describe.skipIf(!testUrl)("cards integration", () => {
  beforeAll(async () => {
    const migrator = postgres(testUrl as string, { max: 1 });
    await migrate(drizzle(migrator), { migrationsFolder: resolve(process.cwd(), "drizzle") });
    await migrator.end();
  });

  beforeEach(async () => {
    await getSql()`
      TRUNCATE card_reframes, card_tags, cards, tags, category_proposals RESTART IDENTITY CASCADE
    `;
  });

  afterAll(async () => {
    await closePool();
  });

  it("round-trips a card with four reframes and tags", async () => {
    const stored = await createCard(baseInput);
    expect(stored.results).toHaveLength(4);
    expect(stored.results.map((item) => item.style)).toEqual([...STYLES]);
    expect(stored.tags.map((tag) => tag.slug)).toEqual(["job_interview", "shame"]);
    expect(stored.matching).toEqual({
      category: "work",
      tags: ["job_interview", "shame"],
      intensityBand: "high",
    });
    expect(stored.thoughtOriginal).toBeUndefined();
    expect(stored.isPinned).toBe(false);
    expect(stored.isPublic).toBe(false);
    expect(stored.results.every((item) => item.isFavorite === false)).toBe(true);

    const listed = await listCards({ limit: 50 });
    expect(listed).toHaveLength(1);
    expect(listed[0]?.id).toBe(stored.id);

    const fetched = await getCard(stored.id);
    expect(fetched?.thought).toBe(baseInput.thought);
  });

  it("ignores client matching and re-derives the intensity band", async () => {
    const stored = await createCard({
      ...baseInput,
      meta: {
        ...baseInput.meta,
        intensity: 5,
      },
    });
    expect(stored.intensityBand).toBe("high");
    expect(stored.matching.intensityBand).toBe("high");
  });

  it("dedupes tag slugs across two cards", async () => {
    await createCard(baseInput);
    await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      meta: {
        ...baseInput.meta,
        tags: ["job_interview", "waiting"],
      },
      spotlightStyle: "optimistic",
    });

    const db = (await import("./client.js")).getDb();
    const tagRows = await db.select().from(tags);
    expect(tagRows).toHaveLength(3);
    expect(tagRows.map((tag) => tag.slug).sort()).toEqual(["job_interview", "shame", "waiting"]);
  });

  it("cascades delete to reframes and joins", async () => {
    const stored = await createCard(baseInput);
    const gone = await deleteCard(stored.id);
    expect(gone).toBe(true);

    const db = (await import("./client.js")).getDb();
    const leftoverCards = await db.select().from(cards);
    const leftoverReframes = await db.select().from(cardReframes);
    expect(leftoverCards).toHaveLength(0);
    expect(leftoverReframes).toHaveLength(0);
    expect(await getCard(stored.id)).toBeNull();
  });

  it("rolls back a partial card when reframes fail the unique constraint", async () => {
    await expect(
      createCard({
        ...baseInput,
        results: [
          { style: "stoic", reframe: "First take." },
          { style: "stoic", reframe: "Duplicate style." },
        ],
      }),
    ).rejects.toBeInstanceOf(DbError);

    const listed = await listCards({ limit: 50 });
    expect(listed).toHaveLength(0);

    const db = (await import("./client.js")).getDb();
    const leftover = await db.select({ id: cards.id }).from(cards);
    expect(leftover).toHaveLength(0);
  });

  it("lists by whether a style exists on the card, not by spotlight", async () => {
    const withHumor = await createCard(baseInput);
    await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      results: [
        { style: "stoic", reframe: "A stoic take on waiting." },
        { style: "optimistic", reframe: "An optimistic take on waiting." },
      ],
      spotlightStyle: "optimistic",
      meta: {
        ...baseInput.meta,
        skippedStyles: [
          { style: "humorous", reason: "A joke would land wrong on a wait this raw." },
          { style: "tough_love", reason: "Pushing would punch down." },
        ],
      },
    });

    const humorous = await listCards({ limit: 50, style: "humorous" });
    expect(humorous.map((card) => card.id)).toEqual([withHumor.id]);

    const optimistic = await listCards({ limit: 50, style: "optimistic" });
    expect(optimistic).toHaveLength(2);
  });

  it("patches per-style favorite, pin, and public independently", async () => {
    const stored = await createCard(baseInput);
    const liked = await patchCard(stored.id, { isFavorite: true, style: "stoic" });
    expect(liked.ok).toBe(true);
    if (!liked.ok) {
      return;
    }
    expect(liked.card.results.find((item) => item.style === "stoic")?.isFavorite).toBe(true);
    expect(liked.card.results.find((item) => item.style === "optimistic")?.isFavorite).toBe(false);

    const pinned = await patchCard(stored.id, { isPinned: true, isPublic: true });
    expect(pinned.ok).toBe(true);
    if (!pinned.ok) {
      return;
    }
    expect(pinned.card.isPinned).toBe(true);
    expect(pinned.card.isPublic).toBe(true);
    expect(pinned.card.results.find((item) => item.style === "stoic")?.isFavorite).toBe(true);

    const favorites = await listCards({ limit: 50, favorite: true });
    expect(favorites.map((card) => card.id)).toEqual([stored.id]);

    const pins = await listCards({ limit: 50, pinned: true });
    expect(pins.map((card) => card.id)).toEqual([stored.id]);

    const slim = await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      results: [
        { style: "stoic", reframe: "A stoic take on waiting." },
        { style: "optimistic", reframe: "An optimistic take on waiting." },
      ],
      spotlightStyle: "optimistic",
    });
    const missing = await patchCard(slim.id, { isFavorite: true, style: "humorous" });
    expect(missing).toEqual({ ok: false, reason: "unknown_style" });
  });
});
