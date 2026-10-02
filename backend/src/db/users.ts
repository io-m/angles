import { and, eq, isNull, sql } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { accounts, cards, users, type UserRow } from "./schema.js";

export async function getUserById(id: string): Promise<UserRow | undefined> {
  try {
    return await getDb().query.users.findFirst({ where: eq(users.id, id) });
  } catch (error) {
    throw wrapDbError(error, "getUserById");
  }
}

export async function setOwnerAvatar(key: string | null): Promise<UserRow> {
  try {
    const [row] = await getDb()
      .update(users)
      .set({ avatarKey: key })
      .where(eq(users.id, getOwnerUserId()))
      .returning();
    if (!row) {
      throw new DbError("Database error");
    }
    return row;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "setOwnerAvatar");
  }
}

export async function updateOwnerInitials(initials: string): Promise<UserRow> {
  try {
    const [row] = await getDb()
      .update(users)
      .set({ initials })
      .where(eq(users.id, getOwnerUserId()))
      .returning();
    if (!row) {
      throw new DbError("Database error");
    }
    return row;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "updateOwnerInitials");
  }
}

export async function markOwnerTasteCompleted(): Promise<void> {
  try {
    await getDb()
      .update(users)
      .set({ tasteCompletedAt: new Date(), updatedAt: new Date() })
      .where(and(eq(users.id, getOwnerUserId()), isNull(users.tasteCompletedAt)));
  } catch (error) {
    throw wrapDbError(error, "markOwnerTasteCompleted");
  }
}

/** Keeps the first acceptance: a retry or a second phone never moves the date. */
export async function acceptOwnerTerms(now: Date = new Date()): Promise<Date> {
  try {
    const [row] = await getDb()
      .update(users)
      .set({
        termsAcceptedAt: sql`coalesce(${users.termsAcceptedAt}, ${now.toISOString()}::timestamptz)`,
        updatedAt: now,
      })
      .where(eq(users.id, getOwnerUserId()))
      .returning({ termsAcceptedAt: users.termsAcceptedAt });
    if (!row?.termsAcceptedAt) {
      throw new DbError("Database error");
    }
    return row.termsAcceptedAt;
  } catch (error) {
    if (error instanceof DbError) {
      throw error;
    }
    throw wrapDbError(error, "acceptOwnerTerms");
  }
}

/** The Apple `sub` the owner signed in with, or null for an account without one (fixtures). */
export async function getOwnerAppleSubject(): Promise<string | null> {
  try {
    const row = await getDb().query.accounts.findFirst({
      where: and(eq(accounts.userId, getOwnerUserId()), eq(accounts.providerId, "apple")),
      columns: { accountId: true },
    });
    return row?.accountId ?? null;
  } catch (error) {
    throw wrapDbError(error, "getOwnerAppleSubject");
  }
}

export async function deleteOwnerAccount(): Promise<void> {
  try {
    await getDb().transaction(async (tx) => {
      const ownerId = getOwnerUserId();
      await tx.delete(cards).where(eq(cards.userId, ownerId));
      await tx.delete(users).where(eq(users.id, ownerId));
    });
  } catch (error) {
    throw wrapDbError(error, "deleteOwnerAccount");
  }
}
