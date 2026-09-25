import { AsyncLocalStorage } from "node:async_hooks";
import type { MiddlewareHandler } from "hono";
import { getAuth } from "../auth.js";
import { errorBody } from "./http.js";

/**
 * Seed / community fixture id. Live requests use the Better Auth session.
 */
export const DEV_USER_ID = "00000000-0000-4000-8000-000000000001";

const ownerContext = new AsyncLocalStorage<string>();

export function getOwnerUserId(): string {
  const id = ownerContext.getStore();
  if (id) {
    return id;
  }
  if (process.env.VITEST === "true") {
    return DEV_USER_ID;
  }
  throw new Error("No authenticated user");
}

function testUserIdFromAuthorization(header: string | undefined): string | "none" | undefined {
  if (process.env.VITEST !== "true") {
    return undefined;
  }
  if (header === "Bearer none") {
    return "none";
  }
  if (header?.startsWith("Bearer test:")) {
    return header.slice("Bearer test:".length);
  }
  return DEV_USER_ID;
}

export const requireAuth: MiddlewareHandler = async (c, next) => {
  const testUser = testUserIdFromAuthorization(c.req.header("Authorization"));
  if (testUser === "none") {
    return c.json(errorBody("Sign in required", "UNAUTHENTICATED"), 401);
  }
  if (testUser) {
    await ownerContext.run(testUser, () => next());
    return;
  }

  const session = await getAuth().api.getSession({ headers: c.req.raw.headers });
  if (!session) {
    return c.json(errorBody("Sign in required", "UNAUTHENTICATED"), 401);
  }
  await ownerContext.run(session.user.id, () => next());
};

/** @deprecated Use requireAuth. Kept so older comments still grep. */
export const authStub = requireAuth;
