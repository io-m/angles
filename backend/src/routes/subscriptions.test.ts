import { beforeEach, describe, expect, it, vi } from "vitest";
import { Hono } from "hono";
import { DEV_USER_ID } from "../lib/authStub.js";
import {
  AppStoreVerificationError,
  type VerifiedAppStoreNotification,
  type VerifiedAppStoreTransaction,
} from "../lib/appStoreVerifier.js";

vi.mock("../lib/appStoreVerifier.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../lib/appStoreVerifier.js")>();
  return {
    ...actual,
    getAppStoreVerifier: vi.fn(),
  };
});
vi.mock("../db/subscriptions.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../db/subscriptions.js")>();
  return {
    ...actual,
    getSubscription: vi.fn(),
    syncSubscriptionTransaction: vi.fn(),
    processSubscriptionNotification: vi.fn(),
  };
});

const { getAppStoreVerifier } = await import("../lib/appStoreVerifier.js");
const {
  SubscriptionOwnershipError,
  getSubscription,
  processSubscriptionNotification,
  syncSubscriptionTransaction,
} = await import("../db/subscriptions.js");
const { profileRoute } = await import("./profile.js");
const { appStoreNotificationsRoute } = await import("./appStoreNotifications.js");

const app = new Hono();
app.route("/profile", profileRoute);
app.route("/app-store/notifications", appStoreNotificationsRoute);

const transaction: VerifiedAppStoreTransaction = {
  originalTransactionId: "original-1",
  transactionId: "transaction-1",
  productId: "app.angles.ios.annual",
  appAccountToken: DEV_USER_ID,
  environment: "sandbox",
  purchaseDate: new Date("2026-09-25T10:00:00.000Z"),
  originalPurchaseDate: new Date("2026-09-25T10:00:00.000Z"),
  expiresDate: new Date("2027-09-25T10:00:00.000Z"),
  signedDate: new Date("2026-09-25T10:00:01.000Z"),
  isUpgraded: false,
};

const notification: VerifiedAppStoreNotification = {
  notificationUUID: "00000000-0000-4000-8000-000000000123",
  notificationType: "DID_RENEW",
  signedDate: new Date("2026-09-25T10:00:02.000Z"),
  transaction,
};

const body = {
  isEntitled: true,
  status: "active" as const,
  productId: "app.angles.ios.annual" as const,
  environment: "sandbox" as const,
  paidThrough: "2027-09-25T10:00:00.000Z",
  revokedAt: null,
  quotaAnchor: "2026-09-25T10:00:00.000Z",
  updatedAt: "2026-09-25T10:00:02.000Z",
};

describe("subscription routes", () => {
  beforeEach(() => {
    vi.mocked(getSubscription).mockReset();
    vi.mocked(syncSubscriptionTransaction).mockReset();
    vi.mocked(processSubscriptionNotification).mockReset();
    vi.mocked(getAppStoreVerifier).mockReset();
    vi.mocked(getAppStoreVerifier).mockReturnValue({
      verifyTransaction: vi.fn().mockResolvedValue(transaction),
      verifyNotification: vi.fn().mockResolvedValue(notification),
    });
    vi.mocked(getSubscription).mockResolvedValue(body);
    vi.mocked(syncSubscriptionTransaction).mockResolvedValue(body);
    vi.mocked(processSubscriptionNotification).mockResolvedValue("processed");
  });

  it("returns server subscription diagnostics", async () => {
    const response = await app.request("/profile/subscription");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(body);
  });

  it("maps an already-owned legacy transaction to conflict", async () => {
    vi.mocked(syncSubscriptionTransaction).mockRejectedValue(new SubscriptionOwnershipError());
    const response = await app.request("/profile/subscription/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedTransactionInfo: "signed-transaction" }),
    });
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ code: "SUBSCRIPTION_OWNED_BY_ANOTHER_USER" });
  });

  it("returns 200 for a verified duplicate notification", async () => {
    vi.mocked(processSubscriptionNotification).mockResolvedValue("duplicate");
    const response = await app.request("/app-store/notifications", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedPayload: "signed-notification" }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ accepted: true, duplicate: true });
  });

  it("rejects an invalid notification signature", async () => {
    vi.mocked(getAppStoreVerifier).mockReturnValue({
      verifyTransaction: vi.fn(),
      verifyNotification: vi
        .fn()
        .mockRejectedValue(new AppStoreVerificationError("invalid signature")),
    });
    const response = await app.request("/app-store/notifications", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedPayload: "not-valid" }),
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "APP_STORE_VERIFICATION_FAILED" });
  });
});
