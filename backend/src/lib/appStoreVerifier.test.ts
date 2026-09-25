import { beforeEach, describe, expect, it, vi } from "vitest";

const apple = vi.hoisted(() => ({
  verifyAndDecodeNotification: vi.fn(),
  verifyAndDecodeTransaction: vi.fn(),
  verifyAndDecodeRenewalInfo: vi.fn(),
}));

vi.mock("@apple/app-store-server-library", async (importOriginal) => {
  const actual = await importOriginal<
    typeof import("@apple/app-store-server-library")
  >();
  return {
    ...actual,
    SignedDataVerifier: vi.fn(function SignedDataVerifier() {
      return apple;
    }),
  };
});

const { getAppStoreVerifier } = await import("./appStoreVerifier.js");

const signedDate = Date.parse("2026-09-25T10:00:02.000Z");
const expiresDate = Date.parse("2026-10-25T10:00:00.000Z");

describe("App Store notification verification", () => {
  beforeEach(() => {
    process.env.APPLE_ROOT_CERTIFICATES_BASE64 = "Y2VydA==";
    delete process.env.APPLE_APP_ID;
    apple.verifyAndDecodeNotification.mockReset();
    apple.verifyAndDecodeTransaction.mockReset();
    apple.verifyAndDecodeRenewalInfo.mockReset();
    apple.verifyAndDecodeNotification.mockResolvedValue({
      notificationUUID: "00000000-0000-4000-8000-000000000123",
      notificationType: "DID_FAIL_TO_RENEW",
      subtype: "GRACE_PERIOD",
      signedDate,
      data: {
        bundleId: "app.angles.ios",
        environment: "Sandbox",
        signedTransactionInfo: "signed-transaction",
        signedRenewalInfo: "signed-renewal",
      },
    });
    apple.verifyAndDecodeTransaction.mockResolvedValue({
      originalTransactionId: "original-1",
      transactionId: "transaction-1",
      bundleId: "app.angles.ios",
      productId: "app.angles.ios.monthly",
      environment: "Sandbox",
      purchaseDate: Date.parse("2026-09-25T10:00:00.000Z"),
      originalPurchaseDate: Date.parse("2026-09-25T10:00:00.000Z"),
      expiresDate,
      signedDate,
    });
    apple.verifyAndDecodeRenewalInfo.mockResolvedValue({
      originalTransactionId: "original-1",
      productId: "app.angles.ios.monthly",
      autoRenewProductId: "app.angles.ios.monthly",
      environment: "Sandbox",
      signedDate,
      renewalDate: expiresDate,
      gracePeriodExpiresDate: Date.parse("2026-11-01T10:00:00.000Z"),
      isInBillingRetryPeriod: true,
    });
  });

  it("verifies and exposes matching signed renewal coverage", async () => {
    const notification = await getAppStoreVerifier().verifyNotification("outer-jws");

    expect(apple.verifyAndDecodeTransaction).toHaveBeenCalledWith("signed-transaction");
    expect(apple.verifyAndDecodeRenewalInfo).toHaveBeenCalledWith("signed-renewal");
    expect(notification.renewal).toMatchObject({
      originalTransactionId: "original-1",
      productId: "app.angles.ios.monthly",
      environment: "sandbox",
      isInBillingRetryPeriod: true,
    });
    expect(notification.renewal?.gracePeriodExpiresDate?.toISOString()).toBe(
      "2026-11-01T10:00:00.000Z",
    );
    expect(notification.renewal?.renewalDate?.toISOString()).toBe(
      "2026-10-25T10:00:00.000Z",
    );
  });

  it("rejects mismatched signed renewal metadata instead of trusting the outer payload", async () => {
    apple.verifyAndDecodeRenewalInfo.mockResolvedValue({
      originalTransactionId: "another-original",
      productId: "app.angles.ios.monthly",
      environment: "Sandbox",
      signedDate,
      isInBillingRetryPeriod: true,
    });

    await expect(
      getAppStoreVerifier().verifyNotification("outer-jws"),
    ).rejects.toThrow("App Store signature verification failed");
  });
});
