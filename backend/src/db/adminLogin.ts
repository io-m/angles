import { eq, lt } from "drizzle-orm";
import { getDb } from "./client.js";
import { adminLoginChallenges } from "./schema.js";

type Db = ReturnType<typeof getDb>;

/** Drops expired rows, then stores a new one-time sign-in challenge. */
export async function insertLoginChallenge(
  jti: string,
  email: string,
  expiresAt: Date,
  db: Db = getDb(),
): Promise<void> {
  await db.delete(adminLoginChallenges).where(lt(adminLoginChallenges.expiresAt, new Date()));
  await db.insert(adminLoginChallenges).values({ jti, email, expiresAt });
}

/** Marks the challenge used. A second call, a mismatch, or an expiry is `invalid`. */
export async function consumeLoginChallenge(
  jti: string,
  email: string,
  now: Date = new Date(),
  db: Db = getDb(),
): Promise<"ok" | "invalid"> {
  return db.transaction(async (tx) => {
    const [row] = await tx
      .select({
        email: adminLoginChallenges.email,
        expiresAt: adminLoginChallenges.expiresAt,
        usedAt: adminLoginChallenges.usedAt,
      })
      .from(adminLoginChallenges)
      .where(eq(adminLoginChallenges.jti, jti))
      .for("update");
    if (!row || row.email !== email || row.usedAt !== null || row.expiresAt.getTime() <= now.getTime()) {
      return "invalid";
    }
    await tx
      .update(adminLoginChallenges)
      .set({ usedAt: now })
      .where(eq(adminLoginChallenges.jti, jti));
    return "ok";
  });
}
