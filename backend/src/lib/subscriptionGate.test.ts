import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Hono } from "hono";
import { DEV_USER_ID } from "./authStub.js";

vi.mock("../db/subscriptions.js", () => ({
  hasActiveEntitlement: vi.fn(),
}));

vi.mock("../db/users.js", () => ({
  getUserById: vi.fn(),
}));

const { hasActiveEntitlement } = await import("../db/subscriptions.js");
const { getUserById } = await import("../db/users.js");
const { canUseSubscriptionOrTaste, requireSubscriptionOrTaste } = await import(
  "./subscriptionGate.js"
);
const { requireAuth } = await import("./authStub.js");

const app = new Hono();
app.post("/", requireAuth, requireSubscriptionOrTaste, (c) => c.json({ ok: true }));

describe("subscription or taste gate", () => {
  beforeEach(() => {
    process.env.SUBSCRIPTION_ENFORCEMENT = "required";
    vi.mocked(getUserById).mockReset();
    vi.mocked(hasActiveEntitlement).mockReset();
  });

  afterEach(() => {
    delete process.env.SUBSCRIPTION_ENFORCEMENT;
  });

  it("allows the one taste while neither taste timestamp is set", async () => {
    vi.mocked(getUserById).mockResolvedValue({
      tasteCompletedAt: null,
      tasteConsumedAt: null,
    } as never);
    await expect(canUseSubscriptionOrTaste(DEV_USER_ID)).resolves.toBe(true);
    expect(hasActiveEntitlement).not.toHaveBeenCalled();
  });

  it("requires a paid-through entitlement after taste", async () => {
    vi.mocked(getUserById).mockResolvedValue({
      tasteCompletedAt: new Date(),
      tasteConsumedAt: null,
    } as never);
    vi.mocked(hasActiveEntitlement).mockResolvedValue(false);
    await expect(canUseSubscriptionOrTaste(DEV_USER_ID)).resolves.toBe(false);
  });

  it("returns 402 after taste when enforcement is required and entitlement ended", async () => {
    vi.mocked(getUserById).mockResolvedValue({
      tasteCompletedAt: new Date(),
      tasteConsumedAt: null,
    } as never);
    vi.mocked(hasActiveEntitlement).mockResolvedValue(false);
    const response = await app.request("/", { method: "POST" });
    expect(response.status).toBe(402);
    expect(await response.json()).toMatchObject({ code: "SUBSCRIPTION_REQUIRED" });
  });

  it("blocks a later taste route after ready was issued but before save", async () => {
    vi.mocked(getUserById).mockResolvedValue({
      tasteCompletedAt: null,
      tasteConsumedAt: new Date(),
    } as never);
    vi.mocked(hasActiveEntitlement).mockResolvedValue(false);
    const response = await app.request("/", { method: "POST" });
    expect(response.status).toBe(402);
  });

  it("keeps existing local and test flows open unless enforcement is required", async () => {
    process.env.SUBSCRIPTION_ENFORCEMENT = "off";
    await expect(canUseSubscriptionOrTaste(DEV_USER_ID)).resolves.toBe(true);
    expect(getUserById).not.toHaveBeenCalled();
  });
});
