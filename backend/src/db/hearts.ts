import { and, eq, inArray, lte, ne, sql, type SQL } from "drizzle-orm";
import type { Style } from "../types/index.js";
import { getDb } from "./client.js";
import { cardReframes, cards, savedAngles } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

/**
 * Which hearts a ranked visit counts: those made by `before` (the visit's start, so every
 * page of it scores the same), never the viewer's own (your heart is not social proof).
 */
export type HeartWindow = { before?: Date; excludeUserId?: string };

function heartWindowFilters(options: HeartWindow): SQL[] {
  const filters: SQL[] = [];
  if (options.before) {
    filters.push(lte(savedAngles.heartedAt, options.before));
  }
  if (options.excludeUserId) {
    filters.push(ne(savedAngles.userId, options.excludeUserId));
  }
  return filters;
}

/**
 * Hearts other people left on a card, keyed by card id.
 *
 * Both readers bound the query to one page or one candidate set, so the cost follows
 * what is being served rather than every heart ever made. `saved_angles_card_idx`
 * makes that seek cheap; the primary key leads with the user and cannot.
 *
 * A card's author never has a row here — `saveFeedAngle` refuses your own card — so
 * these are strangers' hearts by construction.
 */
export async function loadCardHeartTotals(
  cardIds: string[],
  db: Selectable = getDb(),
  options: HeartWindow = {},
): Promise<Map<string, number>> {
  const totals = new Map<string, number>();
  if (cardIds.length === 0) {
    return totals;
  }

  // Distinct people, not angles: hearting three styles on one card is one signal.
  const rows = await db
    .select({
      cardId: savedAngles.cardId,
      hearts: sql<number>`count(distinct ${savedAngles.userId})::int`,
    })
    .from(savedAngles)
    .where(and(inArray(savedAngles.cardId, cardIds), ...heartWindowFilters(options)))
    .groupBy(savedAngles.cardId);

  for (const row of rows) {
    totals.set(row.cardId, row.hearts);
  }
  return totals;
}

/**
 * The angle this viewer keeps hearting, across other people's cards and their own.
 * Null until they have hearted anything, which leaves every card on its own cover.
 */
export async function loadViewerStyleTaste(
  viewerId: string,
  db: Selectable = getDb(),
): Promise<Style | null> {
  const [saved, own] = await Promise.all([
    db
      .select({ style: savedAngles.style, hearts: sql<number>`count(*)::int` })
      .from(savedAngles)
      .where(eq(savedAngles.userId, viewerId))
      .groupBy(savedAngles.style),
    db
      .select({ style: cardReframes.style, hearts: sql<number>`count(*)::int` })
      .from(cardReframes)
      .innerJoin(cards, eq(cards.id, cardReframes.cardId))
      .where(and(eq(cards.userId, viewerId), eq(cardReframes.isHearted, true)))
      .groupBy(cardReframes.style),
  ]);

  const totals = new Map<Style, number>();
  for (const row of [...saved, ...own]) {
    totals.set(row.style, (totals.get(row.style) ?? 0) + row.hearts);
  }

  let best: { style: Style; hearts: number } | null = null;
  for (const [style, hearts] of totals) {
    // Ties break on the style name so one viewer always gets one answer.
    if (!best || hearts > best.hearts || (hearts === best.hearts && style < best.style)) {
      best = { style, hearts };
    }
  }
  return best?.style ?? null;
}

/**
 * Per-style hearts in one grouped query: what landed on an author's own posts, and
 * what decides each candidate's primary tab while ranking a style shelf.
 */
export async function loadStyleHeartCounts(
  cardIds: string[],
  db: Selectable = getDb(),
  options: HeartWindow = {},
): Promise<Map<string, Map<Style, number>>> {
  const counts = new Map<string, Map<Style, number>>();
  if (cardIds.length === 0) {
    return counts;
  }

  // One row per (user, card, style) by primary key, so a plain count is a people count.
  const rows = await db
    .select({
      cardId: savedAngles.cardId,
      style: savedAngles.style,
      hearts: sql<number>`count(*)::int`,
    })
    .from(savedAngles)
    .where(and(inArray(savedAngles.cardId, cardIds), ...heartWindowFilters(options)))
    .groupBy(savedAngles.cardId, savedAngles.style);

  for (const row of rows) {
    let byStyle = counts.get(row.cardId);
    if (!byStyle) {
      byStyle = new Map();
      counts.set(row.cardId, byStyle);
    }
    byStyle.set(row.style, row.hearts);
  }
  return counts;
}
