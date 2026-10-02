import { describe, expect, it, vi } from "vitest";
import { DEV_USER_ID } from "../lib/authStub.js";
import type { VerifiedAppStoreTransaction } from "../lib/appStoreVerifier.js";

vi.mock("./client.js", () => ({
  getDb: vi.fn(),
  wrapDbError: vi.fn((error: unknown) => error),
}));

const { getDb } = await import("./client.js");
const { SubscriptionOwnershipError, syncSubscriptionTransaction } = await import(
  "./subscriptions.js"
);

function transaction(
  overrides: Partial<VerifiedAppStoreTransaction> = {},
): VerifiedAppStoreTransaction {
  return {
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
    ...overrides,
  };
}

describe("subscription ownership", () => {
  it("rejects a malformed appAccountToken before touching the DB", async () => {
    await expect(
      syncSubscriptionTransaction(
        DEV_USER_ID,
        transaction({ appAccountToken: "not-a-uuid" }),
      ),
    ).rejects.toBeInstanceOf(SubscriptionOwnershipError);
    expect(getDb).not.toHaveBeenCalled();
  });

  it("rejects an appAccountToken that belongs to another live account", async () => {
    const otherUserId = "00000000-0000-4000-8000-000000000099";
    const tx = {
      execute: vi.fn().mockResolvedValue(undefined),
      query: {
        users: { findFirst: vi.fn().mockResolvedValue({ id: otherUserId }) },
      },
    };
    vi.mocked(getDb).mockReturnValue({
      transaction: (run: (db: typeof tx) => Promise<unknown>) => run(tx),
    } as unknown as ReturnType<typeof getDb>);

    await expect(
      syncSubscriptionTransaction(DEV_USER_ID, transaction({ appAccountToken: otherUserId })),
    ).rejects.toBeInstanceOf(SubscriptionOwnershipError);
    expect(tx.query.users.findFirst).toHaveBeenCalledOnce();
  });
});
