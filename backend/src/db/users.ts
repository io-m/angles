import { and, eq, isNull } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { cards, users, type UserRow } from "./schema.js";

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
