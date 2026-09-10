import type { MiddlewareHandler } from "hono";

/**
 * TODO(auth): Better Auth middleware will verify the session here and attach
 * the user to the context. Social logins (plus Sign in with Apple on iOS —
 * App Store Guideline 4.8) will live in `src/auth.ts` with Drizzle on Postgres.
 *
 * Until then, every card belongs to the seeded local dev user. Do not expose
 * this API publicly.
 */
export const DEV_USER_ID = "00000000-0000-4000-8000-000000000001";

export function getOwnerUserId(): string {
  return DEV_USER_ID;
}

export const authStub: MiddlewareHandler = async (_c, next) => {
  await next();
};
