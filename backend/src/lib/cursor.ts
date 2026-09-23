import { z } from "zod";
import type { FeedCursor } from "../types/index.js";

/** `createdAt|id` from the last card of the previous page. */
export function cardCursorSchema() {
  return z.string().transform((raw, context): FeedCursor => {
    const parts = raw.split("|");
    const createdAt = parts[0] ? new Date(parts[0]) : new Date(Number.NaN);
    const id = parts[1];
    if (
      parts.length !== 2 ||
      Number.isNaN(createdAt.getTime()) ||
      !id ||
      !z.uuid().safeParse(id).success
    ) {
      context.addIssue({
        code: "custom",
        message: "before must be an ISO-8601 timestamp and UUID separated by |",
      });
      return z.NEVER;
    }
    return { createdAt, id };
  });
}
