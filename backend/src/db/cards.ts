import { and, asc, desc, eq, inArray, lt, sql } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { normalizeTagSlugs, titleCase } from "../lib/slugs.js";
import {
  intensityBand,
  type CreateCardInput,
  type CardListQuery,
  type StoredCard,
} from "../types/index.js";
import { getDb, wrapDbError, DbError } from "./client.js";
import {
  cardReframes,
  cardTags,
  cards,
  categoryProposals,
  tags,
  type CardReframeRow,
  type CardRow,
  type TagRow,
} from "./schema.js";

type CardLoaded = CardRow & {
  reframes: CardReframeRow[];
  cardTags: { tag: TagRow }[];
};

function toStoredCard(row: CardLoaded): StoredCard {
  const tagList = row.cardTags.map((join) => ({
    slug: join.tag.slug,
    label: join.tag.label,
  }));
  const results = [...row.reframes]
    .sort((left, right) => left.position - right.position)
    .map((item) => ({ style: item.style, reframe: item.reframe }));

  const stored: StoredCard = {
    id: row.id,
    thought: row.thoughtEn,
    inputLanguage: row.inputLanguage,
    category: row.category,
    tags: tagList,
    intensity: row.intensity,
    intensityBand: intensityBand(row.intensity),
    timeframe: row.timeframe,
    emotions: row.emotions,
    safety: row.safety,
    skippedStyles: row.skippedStyles,
    matching: {
      category: row.category,
      tags: tagList.map((tag) => tag.slug),
      intensityBand: intensityBand(row.intensity),
    },
    results,
    model: row.model,
    spotlightStyle: row.spotlightStyle,
    isFavorite: row.isFavorite,
    createdAt: row.createdAt.toISOString(),
  };

  if (row.thoughtOriginal) {
    stored.thoughtOriginal = row.thoughtOriginal;
  }
  if (row.proposedCategory) {
    stored.proposedCategory = row.proposedCategory;
  }
  if (row.proposedLabel) {
    stored.proposedLabel = row.proposedLabel;
  }
  if (row.favoritedAt) {
    stored.favoritedAt = row.favoritedAt.toISOString();
  }

  return stored;
}

type Queryable = { query: ReturnType<typeof getDb>["query"] };

async function loadCard(db: Queryable, id: string): Promise<StoredCard | null> {
  const row = await db.query.cards.findFirst({
    where: and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())),
    with: {
      reframes: { orderBy: [asc(cardReframes.position)] },
      cardTags: { with: { tag: true } },
    },
  });
  if (!row) {
    return null;
  }
  return toStoredCard(row);
}

export async function createCard(input: CreateCardInput): Promise<StoredCard> {
  try {
    return await getDb().transaction(async (tx) => {
      const thoughtOriginal =
        input.thoughtOriginal && input.thoughtOriginal !== input.thought
          ? input.thoughtOriginal
          : null;
      const slugs = normalizeTagSlugs(input.meta.tags);
      const band = intensityBand(input.meta.intensity);

      const [inserted] = await tx
        .insert(cards)
        .values({
          userId: getOwnerUserId(),
          thoughtEn: input.thought,
          thoughtOriginal,
          inputLanguage: input.meta.inputLanguage,
          category: input.meta.category,
          proposedCategory:
            input.meta.category === "other" ? (input.meta.proposedCategory ?? null) : null,
          proposedLabel: input.meta.category === "other" ? (input.meta.proposedLabel ?? null) : null,
          intensity: input.meta.intensity,
          intensityBand: band,
          timeframe: input.meta.timeframe,
          safety: input.meta.safety,
          emotions: input.meta.emotions,
          skippedStyles: input.meta.skippedStyles,
          model: input.model,
          spotlightStyle: input.spotlightStyle,
        })
        .returning({ id: cards.id });

      const cardId = inserted?.id;
      if (!cardId) {
        throw new DbError("Database error");
      }

      await tx.insert(cardReframes).values(
        input.results.map((result, position) => ({
          cardId,
          style: result.style,
          reframe: result.reframe,
          position,
        })),
      );

      if (slugs.length > 0) {
        await tx
          .insert(tags)
          .values(slugs.map((slug) => ({ slug, label: titleCase(slug) })))
          .onConflictDoNothing({ target: tags.slug });

        const storedTags = await tx.select().from(tags).where(inArray(tags.slug, slugs));
        const bySlug = new Map(storedTags.map((tag) => [tag.slug, tag]));
        const joins = slugs.flatMap((slug) => {
          const tag = bySlug.get(slug);
          return tag ? [{ cardId, tagId: tag.id }] : [];
        });
        if (joins.length > 0) {
          await tx.insert(cardTags).values(joins);
        }
      }

      if (input.meta.category === "other" && input.meta.proposedCategory) {
        const slug = input.meta.proposedCategory;
        const label = input.meta.proposedLabel?.trim() || titleCase(slug);
        const now = new Date();
        await tx
          .insert(categoryProposals)
          .values({
            slug,
            label,
            seenCount: 1,
            firstSeenAt: now,
            lastSeenAt: now,
          })
          .onConflictDoUpdate({
            target: categoryProposals.slug,
            set: {
              seenCount: sql`${categoryProposals.seenCount} + 1`,
              lastSeenAt: now,
            },
          });
      }

      const loaded = await loadCard(tx, cardId);
      if (!loaded) {
        throw new DbError("Database error");
      }
      return loaded;
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "createCard");
  }
}

export async function listCards(query: CardListQuery): Promise<StoredCard[]> {
  try {
    const filters = [eq(cards.userId, getOwnerUserId())];
    if (query.category) {
      filters.push(eq(cards.category, query.category));
    }
    if (query.style) {
      filters.push(eq(cards.spotlightStyle, query.style));
    }
    if (query.favorite === true) {
      filters.push(eq(cards.isFavorite, true));
    } else if (query.favorite === false) {
      filters.push(eq(cards.isFavorite, false));
    }
    if (query.before) {
      filters.push(lt(cards.createdAt, query.before));
    }

    const rows = await getDb().query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      limit: query.limit,
      with: {
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    return rows.map((row) => toStoredCard(row));
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "listCards");
  }
}

export async function getCard(id: string): Promise<StoredCard | null> {
  try {
    return await loadCard(getDb(), id);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "getCard");
  }
}

export async function setFavorite(id: string, isFavorite: boolean): Promise<StoredCard | null> {
  try {
    const updated = await getDb()
      .update(cards)
      .set({
        isFavorite,
        favoritedAt: isFavorite ? new Date() : null,
      })
      .where(and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())))
      .returning({ id: cards.id });

    if (!updated[0]) {
      return null;
    }
    return await loadCard(getDb(), id);
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "setFavorite");
  }
}

export async function deleteCard(id: string): Promise<boolean> {
  try {
    const deleted = await getDb()
      .delete(cards)
      .where(and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())))
      .returning({ id: cards.id });
    return deleted.length > 0;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "deleteCard");
  }
}
