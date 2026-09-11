import { and, asc, desc, eq, inArray, lt, not, or, sql } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { normalizeTagSlugs, titleCase } from "../lib/slugs.js";
import {
  intensityBand,
  type CreateCardInput,
  type CardListQuery,
  type PatchCardInput,
  type StoredCard,
} from "../types/index.js";
import { getDb, wrapDbError, DbError } from "./client.js";
import { loadViewerSaves, toStoredCard } from "./mapCard.js";
import { cardReframes, cardTags, cards, categoryProposals, savedAngles, tags } from "./schema.js";

type Queryable = { query: ReturnType<typeof getDb>["query"] };

async function loadCard(db: Queryable, id: string): Promise<StoredCard | null> {
  const row = await db.query.cards.findFirst({
    where: and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())),
    with: {
      user: true,
      reframes: { orderBy: [asc(cardReframes.position)] },
      cardTags: { with: { tag: true } },
    },
  });
  if (!row) {
    return null;
  }
  return toStoredCard(row, { angles: new Map() });
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
    const viewerId = getOwnerUserId();
    const db = getDb();
    const savedAngleIds = db
      .select({ id: savedAngles.cardId })
      .from(savedAngles)
      .where(eq(savedAngles.userId, viewerId));
    const ownedFavoriteIds = db
      .select({ id: cardReframes.cardId })
      .from(cardReframes)
      .innerJoin(cards, eq(cards.id, cardReframes.cardId))
      .where(and(eq(cardReframes.isFavorite, true), eq(cards.userId, viewerId)));

    // The library is the viewer's own cards plus anything they hearted on Home.
    const filters = [or(eq(cards.userId, viewerId), inArray(cards.id, savedAngleIds))!];
    if (query.category) {
      filters.push(eq(cards.category, query.category));
    }
    if (query.style) {
      filters.push(
        inArray(
          cards.id,
          db.select({ id: cardReframes.cardId }).from(cardReframes).where(eq(cardReframes.style, query.style)),
        ),
      );
    }
    if (query.favorite === true) {
      filters.push(or(inArray(cards.id, ownedFavoriteIds), inArray(cards.id, savedAngleIds))!);
    } else if (query.favorite === false) {
      filters.push(not(or(inArray(cards.id, ownedFavoriteIds), inArray(cards.id, savedAngleIds))!));
    }
    if (query.before) {
      filters.push(lt(cards.createdAt, query.before));
    }

    const rows = await db.query.cards.findMany({
      where: and(...filters),
      orderBy: [desc(cards.createdAt), desc(cards.id)],
      limit: query.limit,
      with: {
        user: true,
        reframes: { orderBy: [asc(cardReframes.position)] },
        cardTags: { with: { tag: true } },
      },
    });

    const saves = await loadViewerSaves(viewerId);
    return rows.map((row) => toStoredCard(row, saves, viewerId));
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

export type PatchCardResult =
  | { ok: true; card: StoredCard }
  | { ok: false; reason: "not_found" | "unknown_style" };

export async function patchCard(id: string, patch: PatchCardInput): Promise<PatchCardResult> {
  try {
    return await getDb().transaction(async (tx) => {
      const existing = await tx.query.cards.findFirst({
        where: and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())),
        columns: { id: true },
        with: {
          reframes: { columns: { style: true } },
        },
      });
      if (!existing) {
        return { ok: false, reason: "not_found" };
      }

      if (patch.isFavorite !== undefined) {
        const style = patch.style;
        if (!style || !existing.reframes.some((item) => item.style === style)) {
          return { ok: false, reason: "unknown_style" };
        }
        await tx
          .update(cardReframes)
          .set({
            isFavorite: patch.isFavorite,
            favoritedAt: patch.isFavorite ? new Date() : null,
          })
          .where(and(eq(cardReframes.cardId, id), eq(cardReframes.style, style)));
      }

      const cardSet: {
        isPublic?: boolean;
      } = {};
      if (patch.isPublic !== undefined) {
        cardSet.isPublic = patch.isPublic;
      }
      if (Object.keys(cardSet).length > 0) {
        await tx
          .update(cards)
          .set(cardSet)
          .where(and(eq(cards.id, id), eq(cards.userId, getOwnerUserId())));
      }

      const loaded = await loadCard(tx, id);
      if (!loaded) {
        return { ok: false, reason: "not_found" };
      }
      return { ok: true, card: loaded };
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "patchCard");
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
