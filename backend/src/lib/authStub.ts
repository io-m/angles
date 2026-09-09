import type { MiddlewareHandler } from "hono";

/**
 * TODO(auth): Better Auth middleware will verify the session here and attach
 * the user to the context. Social logins (plus Sign in with Apple on iOS —
 * App Store Guideline 4.8) will live in `src/auth.ts` with Drizzle on Postgres.
 *
 * Until then, /reframe is unauthenticated. Do not expose this API publicly.
 */
export const authStub: MiddlewareHandler = async (_c, next) => {
  await next();
};
