import { eq } from "drizzle-orm";
import { getOwnerUserId } from "../lib/authStub.js";
import { DbError, getDb, wrapDbError } from "./client.js";
import { users, type UserRow } from "./schema.js";

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
