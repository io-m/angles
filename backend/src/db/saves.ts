import { and, eq, inArray, lte, ne, sql, type SQL } from "drizzle-orm";
import type { Style } from "../types/index.js";
import { getDb } from "./client.js";
import { cardDecisions } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

/**
 * Which saves a ranked visit counts: those made by `before` (the visit's start, so every
 * page of it scores the same), never the viewer's own (your save is not social proof).
 */
export type SaveWindow = { before?: Date; excludeUserId?: string };

function saveFilters(cardIds: string[], options: SaveWindow): SQL[] {
  const filters: SQL[] = [
    eq(cardDecisions.kind, "save"),
    inArray(cardDecisions.cardId, cardIds) as SQL,
  ];
  if (options.before) {
    filters.push(lte(cardDecisions.decidedAt, options.before));
  }
  if (options.excludeUserId) {
    filters.push(ne(cardDecisions.userId, options.excludeUserId));
  }
  return filters;
}

/**
 * People who saved each card. One decision row per viewer and card, so a plain count is a
 * people count. A card's author never has a row (`writeDecision` refuses your own card).
 */
export async function loadCardSaveTotals(
  cardIds: string[],
  db: Selectable = getDb(),
  options: SaveWindow = {},
): Promise<Map<string, number>> {
  const totals = new Map<string, number>();
  if (cardIds.length === 0) {
    return totals;
  }
  const rows = await db
    .select({ cardId: cardDecisions.cardId, saves: sql<number>`count(*)::int` })
    .from(cardDecisions)
    .where(and(...saveFilters(cardIds, options)))
    .groupBy(cardDecisions.cardId);
  for (const row of rows) {
    totals.set(row.cardId, row.saves);
  }
  return totals;
}

/** Saves per card and the angle that was on screen. Read only for the author's own posts. */
export async function loadSaveCountsByStyle(
  cardIds: string[],
  db: Selectable = getDb(),
): Promise<Map<string, Map<Style, number>>> {
  const counts = new Map<string, Map<Style, number>>();
  if (cardIds.length === 0) {
    return counts;
  }
  const rows = await db
    .select({
      cardId: cardDecisions.cardId,
      style: cardDecisions.style,
      saves: sql<number>`count(*)::int`,
    })
    .from(cardDecisions)
    .where(and(...saveFilters(cardIds, {})))
    .groupBy(cardDecisions.cardId, cardDecisions.style);
  for (const row of rows) {
    const byStyle = counts.get(row.cardId) ?? new Map<Style, number>();
    byStyle.set(row.style, row.saves);
    counts.set(row.cardId, byStyle);
  }
  return counts;
}

/**
 * The angle this viewer most often saves on. Null until they have saved anything, which
 * leaves every card on its own cover. `before` freezes it for a ranked visit.
 */
export async function loadViewerSavedStyle(
  viewerId: string,
  db: Selectable = getDb(),
  before?: Date,
): Promise<Style | null> {
  const rows = await db
    .select({ style: cardDecisions.style, saves: sql<number>`count(*)::int` })
    .from(cardDecisions)
    .where(
      and(
        eq(cardDecisions.userId, viewerId),
        eq(cardDecisions.kind, "save"),
        before ? lte(cardDecisions.decidedAt, before) : undefined,
      ),
    )
    .groupBy(cardDecisions.style);

  let best: { style: Style; saves: number } | null = null;
  for (const row of rows) {
    // Ties break on the style name so one viewer always gets one answer.
    if (!best || row.saves > best.saves || (row.saves === best.saves && row.style < best.style)) {
      best = { style: row.style, saves: row.saves };
    }
  }
  return best?.style ?? null;
}
