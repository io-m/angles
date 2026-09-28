import { sql } from "drizzle-orm";
import type { FeedCursor } from "../types/index.js";
import { cards } from "./schema.js";

/** Row comparison so Postgres can seek the `(created_at desc, id desc)` indexes. */
export function olderThanCursor(before: FeedCursor) {
  return sql`(${cards.createdAt}, ${cards.id}) < (${before.createdAt.toISOString()}::timestamptz, ${before.id}::uuid)`;
}

/** The same seek in the other direction: what has arrived since the client last looked. */
export function newerThanCursor(after: FeedCursor) {
  return sql`(${cards.createdAt}, ${cards.id}) > (${after.createdAt.toISOString()}::timestamptz, ${after.id}::uuid)`;
}
