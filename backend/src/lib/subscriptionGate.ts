import type { MiddlewareHandler } from "hono";
import { hasActiveEntitlement } from "../db/subscriptions.js";
import { getUserById } from "../db/users.js";
import { getOwnerUserId } from "./authStub.js";
import { errorBody } from "./http.js";

export function isSubscriptionEnforcementRequired(): boolean {
  return process.env.SUBSCRIPTION_ENFORCEMENT?.trim().toLowerCase() === "required";
}

export async function canUseSubscriptionOrTaste(
  ownerId: string,
  date: Date = new Date(),
): Promise<boolean> {
  if (!isSubscriptionEnforcementRequired()) {
    return true;
  }
  const user = await getUserById(ownerId);
  if (!user) {
    return false;
  }
  if (user.tasteCompletedAt === null && user.tasteConsumedAt === null) {
    return true;
  }
  return hasActiveEntitlement(ownerId, date);
}

export const requireSubscriptionOrTaste: MiddlewareHandler = async (c, next) => {
  if (await canUseSubscriptionOrTaste(getOwnerUserId())) {
    await next();
    return;
  }
  return c.json(
    errorBody("An active subscription is required", "SUBSCRIPTION_REQUIRED"),
    402,
  );
};
