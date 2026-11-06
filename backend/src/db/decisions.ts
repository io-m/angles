import { and, eq, inArray } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { isStyleShown } from "../lib/styleSet.js";
import type { CardDecision, DecisionBody, Style } from "../types/index.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { lockUserPair, usersAreBlocked } from "./communitySafety.js";
import { recordLove, retractLove } from "./loveNotifications.js";
import { cardDecisions, cardReframes, cardReports, cards, users, type CardDecisionRow } from "./schema.js";

type Selectable = Pick<ReturnType<typeof getDb>, "select">;

export function toCardDecision(row: CardDecisionRow): CardDecision {
  return {
    kind: row.kind,
    style: row.style,
    checkedStyles: [...row.checkedStyles],
    passes: row.passes,
    decidedAt: row.decidedAt.toISOString(),
  };
}

/** The viewer's decisions on `cardIds` only, so the cost follows the page. */
export async function loadViewerDecisions(
  cardIds: string[],
  viewerId: string = getOwnerUserId(),
  db: Selectable = getDb(),
): Promise<Map<string, CardDecisionRow>> {
  const decisions = new Map<string, CardDecisionRow>();
  if (cardIds.length === 0) {
    return decisions;
  }
  const rows = await db
    .select()
    .from(cardDecisions)
    .where(and(eq(cardDecisions.userId, viewerId), inArray(cardDecisions.cardId, cardIds)));
  for (const row of rows) {
    decisions.set(row.cardId, row);
  }
  return decisions;
}

export type DecisionWriteResult =
  /** `loved`: this write turned the row into a save and stored a love for the author. */
  | { ok: true; decision: CardDecision; loved: boolean }
  | { ok: false; reason: "not_found" | "own_card" | "not_public" | "unknown_style" };

/**
 * Writes the viewer's whole decision row as sent, so a retry or a rewind lands on the same
 * state. Only someone else's public card the viewer can still see: not blocked either
 * way, and not one they reported.
 *
 * A row that becomes a save tells the author (a love notification); a save that stops
 * being one takes that notification back while it is unread. A repeated save says nothing.
 */
export async function writeDecision(cardId: string, body: DecisionBody): Promise<DecisionWriteResult> {
  try {
    return await getDb().transaction(async (tx) => {
      const viewerId = getOwnerUserId();
      const [target] = await tx
        .select({ authorId: cards.userId, authorKind: users.kind })
        .from(cards)
        .innerJoin(users, eq(users.id, cards.userId))
        .where(eq(cards.id, cardId))
        .limit(1);
      if (!target) {
        return { ok: false, reason: "not_found" };
      }
      if (target.authorId === viewerId) {
        return { ok: false, reason: "own_card" };
      }
      await lockUserPair(tx, viewerId, target.authorId);
      const [locked] = await tx
        .select({ authorId: cards.userId, isPublic: cards.isPublic })
        .from(cards)
        .where(eq(cards.id, cardId))
        .for("update");
      if (
        !locked ||
        locked.authorId !== target.authorId ||
        (await usersAreBlocked(viewerId, locked.authorId, tx))
      ) {
        return { ok: false, reason: "not_found" };
      }
      const [reported] = await tx
        .select({ cardId: cardReports.cardId })
        .from(cardReports)
        .where(and(eq(cardReports.reporterId, viewerId), eq(cardReports.cardId, cardId)))
        .limit(1);
      if (reported) {
        return { ok: false, reason: "not_found" };
      }
      if (!locked.isPublic) {
        return { ok: false, reason: "not_public" };
      }

      const angles = await tx
        .select({ style: cardReframes.style })
        .from(cardReframes)
        .where(eq(cardReframes.cardId, cardId));
      const shown = new Set<Style>(angles.map((row) => row.style).filter(isStyleShown));
      if (!shown.has(body.style) || body.checkedStyles.some((style) => !shown.has(style))) {
        return { ok: false, reason: "unknown_style" };
      }
      const checked = [...new Set<Style>([...body.checkedStyles, body.style])];
      const [prior] = await tx
        .select({ kind: cardDecisions.kind })
        .from(cardDecisions)
        .where(and(eq(cardDecisions.userId, viewerId), eq(cardDecisions.cardId, cardId)))
        .limit(1);
      const decidedAt = new Date();
      const values = {
        kind: body.kind,
        style: body.style,
        checkedStyles: checked,
        passes: body.passes,
        decidedAt,
      };
      const [row] = await tx
        .insert(cardDecisions)
        .values({ userId: viewerId, cardId, ...values })
        .onConflictDoUpdate({ target: [cardDecisions.userId, cardDecisions.cardId], set: values })
        .returning();
      if (!row) {
        throw new DbError("Database error");
      }
      let loved = false;
      const wasSave = prior?.kind === "save";
      if (body.kind === "save" && !wasSave && target.authorKind !== "house") {
        loved = await recordLove(tx, {
          recipientId: target.authorId,
          actorId: viewerId,
          cardId,
          style: body.style,
        });
      } else if (body.kind !== "save" && wasSave) {
        await retractLove(tx, viewerId, cardId);
      }
      return { ok: true, decision: toCardDecision(row), loved };
    });
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "writeDecision");
  }
}

/**
 * Removes the viewer's decision: a rewind past the first save or pass. Works on a card
 * that went private since, and answers the same when there was nothing to remove, so a
 * retried rewind is harmless. Only a card that does not exist is not found.
 */
export async function clearDecision(cardId: string): Promise<{ ok: boolean }> {
  try {
    const viewerId = getOwnerUserId();
    const db = getDb();
    const removed = await db
      .delete(cardDecisions)
      .where(and(eq(cardDecisions.userId, viewerId), eq(cardDecisions.cardId, cardId)))
      .returning({ cardId: cardDecisions.cardId, kind: cardDecisions.kind });
    if (removed.length > 0) {
      if (removed.some((row) => row.kind === "save")) {
        await retractLove(db, viewerId, cardId);
      }
      return { ok: true };
    }
    const [exists] = await db.select({ id: cards.id }).from(cards).where(eq(cards.id, cardId)).limit(1);
    return { ok: exists !== undefined };
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "clearDecision");
  }
}
