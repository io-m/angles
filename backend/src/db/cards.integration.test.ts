import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { eq } from "drizzle-orm";
import {
  STYLES,
  type Category,
  type CreateCardInput,
  type Emotion,
} from "../types/index.js";
import { DEV_USER_ID } from "../lib/authStub.js";
import type {
  VerifiedAppStoreNotification,
  VerifiedAppStoreRenewal,
  VerifiedAppStoreTransaction,
} from "../lib/appStoreVerifier.js";
import { DbError } from "./client.js";
import { logPostgresNotice } from "./productionMigrations.js";

function loadTestDatabaseUrl(): void {
  if (process.env.DATABASE_URL_TEST) {
    return;
  }

  let raw: string;
  try {
    raw = readFileSync(resolve(process.cwd(), ".env"), "utf8");
  } catch {
    return;
  }

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("DATABASE_URL_TEST=")) {
      continue;
    }
    let value = trimmed.slice("DATABASE_URL_TEST=".length).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\"")) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env.DATABASE_URL_TEST = value;
  }
}

loadTestDatabaseUrl();
const testUrl = process.env.DATABASE_URL_TEST;
if (testUrl) {
  process.env.DATABASE_URL = testUrl;
}

const { closePool, getDb, getSql } = await import("./client.js");
const { createCard, deleteCard, getCard, listCards, patchCard } = await import("./cards.js");
const { deleteOwnerAccount } = await import("./users.js");
const { blockUser, reportCard, unblockUser } = await import("./communitySafety.js");
const {
  SubscriptionOwnershipError,
  getSubscription,
  hasActiveEntitlement,
  processSubscriptionNotification,
  syncSubscriptionTransaction,
} = await import("./subscriptions.js");
const {
  MeteringError,
  applyCreditAdjustment,
  beginProviderCall,
  expireStaleOperations,
  finishMeterOperation,
  getUsageSummary,
  startMeterOperation,
} = await import("./metering.js");
const { clearFeedSaves, listFeed, saveFeedAngle } = await import("./feed.js");
const { followUser, unfollowUser } = await import("./follows.js");
const { createApp } = await import("../app.js");
const {
  cardReframes,
  cardReports,
  cards,
  dailyUsage,
  follows,
  meterOperations,
  savedAngles,
  subscriptionEntitlements,
  subscriptionEvents,
  tags,
  tasteUsage,
  usagePeriods,
  userBlocks,
  users,
} = await import("./schema.js");
const safetyApp = createApp();

const baseInput: CreateCardInput = {
  thought: "I bombed my interview and I keep replaying every shaky answer.",
  results: STYLES.map((style) => ({ style, reframe: `A ${style} take on showing up.` })),
  meta: {
    category: "work",
    tags: ["job_interview", "shame"],
    intensity: 4,
    timeframe: "past",
    emotions: ["shame", "fear"],
    safety: "none",
    inputLanguage: "en",
    skippedStyles: [],
  },
  model: "mistral-small-latest",
  spotlightStyle: "stoic",
};

function appStoreTransaction(
  overrides: Partial<VerifiedAppStoreTransaction> = {},
): VerifiedAppStoreTransaction {
  return {
    originalTransactionId: "original-subscription-1",
    transactionId: "transaction-1",
    productId: "app.angles.ios.annual",
    environment: "sandbox",
    purchaseDate: new Date("2026-09-25T10:00:00.000Z"),
    originalPurchaseDate: new Date("2026-09-25T10:00:00.000Z"),
    expiresDate: new Date("2027-09-25T10:00:00.000Z"),
    signedDate: new Date("2026-09-25T10:00:01.000Z"),
    isUpgraded: false,
    ...overrides,
  };
}

function appStoreNotification(
  overrides: Partial<VerifiedAppStoreNotification> = {},
): VerifiedAppStoreNotification {
  const signedDate = overrides.signedDate ?? new Date("2026-09-25T12:00:00.000Z");
  const transaction =
    overrides.transaction ??
    appStoreTransaction({
      transactionId: "transaction-2",
      purchaseDate: new Date("2026-09-25T11:59:00.000Z"),
      signedDate,
      expiresDate: new Date("2027-09-25T12:00:00.000Z"),
    });
  const renewal: VerifiedAppStoreRenewal =
    overrides.renewal ?? {
      originalTransactionId: transaction.originalTransactionId,
      productId: transaction.productId,
      ...(transaction.appAccountToken
        ? { appAccountToken: transaction.appAccountToken }
        : {}),
      environment: transaction.environment,
      signedDate,
      renewalDate: transaction.expiresDate,
      isInBillingRetryPeriod: false,
    };
  return {
    notificationUUID: "00000000-0000-4000-8000-000000000101",
    notificationType: "DID_RENEW",
    signedDate,
    transaction,
    renewal,
    ...overrides,
  };
}

describe.skipIf(!testUrl)("cards integration", () => {
  beforeAll(async () => {
    const migrator = postgres(testUrl as string, {
      max: 1,
      onnotice: logPostgresNotice,
    });
    await migrate(drizzle(migrator), { migrationsFolder: resolve(process.cwd(), "drizzle") });
    await migrator.end();
  });

  beforeEach(async () => {
    process.env.USAGE_ENFORCEMENT = "off";
    await getSql()`
      TRUNCATE llm_call_usage, credit_adjustments, meter_operations, daily_usage, taste_usage,
        usage_periods, subscription_events, subscription_entitlements, user_blocks, card_reports,
        follows, saved_angles, card_reframes, card_tags, cards, tags, category_proposals
        RESTART IDENTITY CASCADE
    `;
    await getDb()
      .update(users)
      .set({ tasteCompletedAt: null, tasteConsumedAt: null })
      .where(eq(users.id, DEV_USER_ID));
  });

  afterAll(async () => {
    await closePool();
  });

  it("allows one legacy claim and prevents the original transaction unlocking another user", async () => {
    const first = await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction(),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    expect(first.isEntitled).toBe(true);

    const otherUserId = "00000000-0000-4000-8000-000000000199";
    await getDb().insert(users).values({
      id: otherUserId,
      name: "Other",
      email: "other-subscription@angles.invalid",
      initials: "OT",
    });
    await expect(
      syncSubscriptionTransaction(otherUserId, appStoreTransaction()),
    ).rejects.toBeInstanceOf(SubscriptionOwnershipError);
    expect((await getSubscription(otherUserId)).status).toBeNull();
    await getDb().delete(users).where(eq(users.id, otherUserId));
  });

  it("serializes concurrent claims by user and original transaction", async () => {
    const otherUserId = "00000000-0000-4000-8000-000000000198";
    await getDb().insert(users).values({
      id: otherUserId,
      name: "Other",
      email: "other-concurrent@angles.invalid",
      initials: "OT",
    });

    const originalRace = await Promise.allSettled([
      syncSubscriptionTransaction(DEV_USER_ID, appStoreTransaction()),
      syncSubscriptionTransaction(otherUserId, appStoreTransaction()),
    ]);
    expect(originalRace.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(await getDb().select().from(subscriptionEntitlements)).toHaveLength(1);

    await getSql()`truncate subscription_entitlements cascade`;
    const userRace = await Promise.allSettled([
      syncSubscriptionTransaction(
        DEV_USER_ID,
        appStoreTransaction({
          originalTransactionId: "original-race-a",
          transactionId: "transaction-race-a",
          appAccountToken: DEV_USER_ID,
        }),
      ),
      syncSubscriptionTransaction(
        DEV_USER_ID,
        appStoreTransaction({
          originalTransactionId: "original-race-b",
          transactionId: "transaction-race-b",
          appAccountToken: DEV_USER_ID,
        }),
      ),
    ]);
    expect(userRace.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(await getDb().select().from(subscriptionEntitlements)).toHaveLength(1);
    await getDb().delete(users).where(eq(users.id, otherUserId));
  });

  it("replaces a non-entitled chain for the same account token and resets its quota anchor", async () => {
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({
        originalTransactionId: "original-expired",
        transactionId: "transaction-expired",
        appAccountToken: DEV_USER_ID,
        expiresDate: new Date("2026-08-01T00:00:00.000Z"),
      }),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    const replacementPurchase = new Date("2026-09-26T08:00:00.000Z");
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({
        originalTransactionId: "original-replacement",
        transactionId: "transaction-replacement",
        appAccountToken: DEV_USER_ID,
        purchaseDate: replacementPurchase,
        originalPurchaseDate: replacementPurchase,
        signedDate: new Date("2026-09-26T08:00:01.000Z"),
      }),
      new Date("2026-09-26T08:00:02.000Z"),
    );

    const [row] = await getDb().select().from(subscriptionEntitlements);
    expect(row).toMatchObject({
      userId: DEV_USER_ID,
      originalTransactionId: "original-replacement",
      currentTransactionId: "transaction-replacement",
      quotaAnchor: replacementPurchase,
    });
  });

  it("rejects replacing an entitled chain with a different original transaction", async () => {
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({ appAccountToken: DEV_USER_ID }),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    await expect(
      syncSubscriptionTransaction(
        DEV_USER_ID,
        appStoreTransaction({
          originalTransactionId: "other-active-chain",
          transactionId: "other-active-transaction",
          appAccountToken: DEV_USER_ID,
        }),
        new Date("2026-09-25T10:00:03.000Z"),
      ),
    ).rejects.toBeInstanceOf(SubscriptionOwnershipError);
  });

  it("deduplicates notifications and ignores older state transitions", async () => {
    await syncSubscriptionTransaction(DEV_USER_ID, appStoreTransaction());
    const renewal = appStoreNotification();
    await expect(processSubscriptionNotification(renewal)).resolves.toBe("processed");
    await expect(processSubscriptionNotification(renewal)).resolves.toBe("duplicate");

    const oldExpiry = appStoreNotification({
      notificationUUID: "00000000-0000-4000-8000-000000000102",
      notificationType: "EXPIRED",
      signedDate: new Date("2026-09-25T11:00:00.000Z"),
      transaction: appStoreTransaction({
        transactionId: "transaction-old",
        purchaseDate: new Date("2026-09-25T10:30:00.000Z"),
        signedDate: new Date("2026-09-25T11:00:00.000Z"),
        expiresDate: new Date("2026-09-25T10:59:00.000Z"),
      }),
    });
    await expect(processSubscriptionNotification(oldExpiry)).resolves.toBe("processed");
    expect((await getSubscription(DEV_USER_ID)).status).toBe("active");
    expect(await getDb().select().from(subscriptionEvents)).toHaveLength(2);

    const equalTimestampExpiry = appStoreNotification({
      notificationUUID: "00000000-0000-4000-8000-000000000105",
      notificationType: "EXPIRED",
      signedDate: renewal.signedDate,
      transaction: renewal.transaction!,
      renewal: renewal.renewal!,
    });
    await expect(processSubscriptionNotification(equalTimestampExpiry)).resolves.toBe("processed");
    expect((await getSubscription(DEV_USER_ID)).status).toBe("active");
    expect(await getDb().select().from(subscriptionEvents)).toHaveLength(3);
  });

  it("applies newer expiry and revoke notifications", async () => {
    await syncSubscriptionTransaction(DEV_USER_ID, appStoreTransaction());
    const expiry = appStoreNotification({
      notificationUUID: "00000000-0000-4000-8000-000000000103",
      notificationType: "EXPIRED",
      signedDate: new Date("2027-09-25T10:01:00.000Z"),
      transaction: appStoreTransaction({
        transactionId: "transaction-expired",
        purchaseDate: new Date("2026-09-25T10:00:00.000Z"),
        signedDate: new Date("2027-09-25T10:01:00.000Z"),
        expiresDate: new Date("2027-09-25T10:00:00.000Z"),
      }),
    });
    await processSubscriptionNotification(expiry, new Date("2027-09-25T10:02:00.000Z"));
    expect((await getSubscription(DEV_USER_ID)).status).toBe("expired");

    const revokedAt = new Date("2027-09-25T11:00:00.000Z");
    await processSubscriptionNotification(
      appStoreNotification({
        notificationUUID: "00000000-0000-4000-8000-000000000104",
        notificationType: "REVOKE",
        signedDate: revokedAt,
        transaction: appStoreTransaction({
          transactionId: "transaction-revoked",
          signedDate: revokedAt,
          revocationDate: revokedAt,
        }),
      }),
      revokedAt,
    );
    const body = await getSubscription(DEV_USER_ID);
    expect(body.status).toBe("revoked");
    expect(body.isEntitled).toBe(false);
    expect(await getDb().select().from(subscriptionEntitlements)).toHaveLength(1);
  });

  it("keeps grace and billing retry on the last paid quota without minting another period", async () => {
    process.env.USAGE_ENFORCEMENT = "required";
    const paidThrough = new Date("2026-10-25T10:00:00.000Z");
    const paidTransaction = appStoreTransaction({
      productId: "app.angles.ios.monthly",
      expiresDate: paidThrough,
    });
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      paidTransaction,
      new Date("2026-09-25T10:00:02.000Z"),
    );
    await getDb()
      .update(users)
      .set({ tasteCompletedAt: new Date("2026-09-25T10:00:03.000Z") })
      .where(eq(users.id, DEV_USER_ID));

    const paidOperation = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000181",
      requestFingerprint: "paid-before-retry",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-26T10:00:00.000Z"),
    });
    await finishMeterOperation({
      operation: paidOperation,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-26T10:00:01.000Z"),
    });

    const graceSignedAt = new Date("2026-10-25T10:01:00.000Z");
    const graceExpiresAt = new Date("2026-11-01T10:00:00.000Z");
    await processSubscriptionNotification(
      appStoreNotification({
        notificationUUID: "00000000-0000-4000-8000-000000000182",
        notificationType: "DID_FAIL_TO_RENEW",
        subtype: "GRACE_PERIOD",
        signedDate: graceSignedAt,
        transaction: paidTransaction,
        renewal: {
          originalTransactionId: paidTransaction.originalTransactionId,
          productId: paidTransaction.productId,
          environment: paidTransaction.environment,
          signedDate: graceSignedAt,
          gracePeriodExpiresDate: graceExpiresAt,
          renewalDate: paidThrough,
          isInBillingRetryPeriod: true,
        },
      }),
      graceSignedAt,
    );
    expect((await getSubscription(DEV_USER_ID)).status).toBe("grace");
    expect(await hasActiveEntitlement(DEV_USER_ID, new Date("2026-10-27T10:00:00.000Z"))).toBe(true);
    expect(
      (await getUsageSummary(DEV_USER_ID, new Date("2026-10-27T10:00:00.000Z")))
        .creditsRemaining,
    ).toBe(599);
    expect(await getDb().select().from(usagePeriods)).toHaveLength(1);

    const retrySignedAt = new Date("2026-11-01T10:01:00.000Z");
    await processSubscriptionNotification(
      appStoreNotification({
        notificationUUID: "00000000-0000-4000-8000-000000000183",
        notificationType: "GRACE_PERIOD_EXPIRED",
        signedDate: retrySignedAt,
        transaction: paidTransaction,
        renewal: {
          originalTransactionId: paidTransaction.originalTransactionId,
          productId: paidTransaction.productId,
          environment: paidTransaction.environment,
          signedDate: retrySignedAt,
          renewalDate: paidThrough,
          isInBillingRetryPeriod: true,
        },
      }),
      retrySignedAt,
    );
    expect((await getSubscription(DEV_USER_ID)).status).toBe("billing_retry");
    expect(await hasActiveEntitlement(DEV_USER_ID, new Date("2026-11-02T10:00:00.000Z"))).toBe(true);
    expect(
      (await getUsageSummary(DEV_USER_ID, new Date("2026-11-02T10:00:00.000Z")))
        .creditsRemaining,
    ).toBe(599);
    expect(await getDb().select().from(usagePeriods)).toHaveLength(1);

    const expiredSignedAt = new Date("2026-11-10T10:01:00.000Z");
    await processSubscriptionNotification(
      appStoreNotification({
        notificationUUID: "00000000-0000-4000-8000-000000000184",
        notificationType: "EXPIRED",
        signedDate: expiredSignedAt,
        transaction: paidTransaction,
        renewal: {
          originalTransactionId: paidTransaction.originalTransactionId,
          productId: paidTransaction.productId,
          environment: paidTransaction.environment,
          signedDate: expiredSignedAt,
          renewalDate: paidThrough,
          isInBillingRetryPeriod: false,
        },
      }),
      expiredSignedAt,
    );
    expect(await hasActiveEntitlement(DEV_USER_ID, expiredSignedAt)).toBe(false);
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000185",
        requestFingerprint: "expired-blocked",
        model: "mistral-small-latest",
        kind: "full",
        now: expiredSignedAt,
      }),
    ).rejects.toMatchObject({ code: "SUBSCRIPTION_REQUIRED" });
  });

  it("reserves atomically, charges only ready, and releases continue", async () => {
    const ready = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000201",
      requestFingerprint: "ready-fingerprint",
      model: "deepseek-flash",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    expect(ready.usage.creditsRemaining).toBe(598);
    const afterReady = await finishMeterOperation({
      operation: ready,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:01.000Z"),
    });
    expect(afterReady.creditsRemaining).toBe(598);

    const continued = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000202",
      requestFingerprint: "continue-fingerprint",
      model: "gemini-3.8-flash",
      kind: "full",
      now: new Date("2026-09-25T12:01:01.000Z"),
    });
    expect(continued.usage.creditsRemaining).toBe(592);
    const afterContinue = await finishMeterOperation({
      operation: continued,
      state: "continue",
      resultKind: "continue",
      usageEvents: [],
      now: new Date("2026-09-25T12:01:02.000Z"),
    });
    expect(afterContinue.creditsRemaining).toBe(598);
  });

  it("enforces one running operation and all idempotency outcomes", async () => {
    const first = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000211",
      requestFingerprint: "same",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000211",
        requestFingerprint: "different",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:01.000Z"),
      }),
    ).rejects.toMatchObject({ code: "IDEMPOTENCY_CONFLICT" });
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000211",
        requestFingerprint: "same",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:01.000Z"),
      }),
    ).rejects.toMatchObject({ code: "OPERATION_RUNNING" });
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000212",
        requestFingerprint: "other",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:01.000Z"),
      }),
    ).rejects.toMatchObject({ code: "OPERATION_RUNNING" });
    await finishMeterOperation({
      operation: first,
      state: "failed",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:02.000Z"),
    });
    expect(
      (await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:00:02.500Z")))
        .creditsRemaining,
    ).toBe(600);
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000211",
        requestFingerprint: "same",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:03.000Z"),
      }),
    ).rejects.toMatchObject({ code: "REQUEST_ALREADY_COMPLETED" });
  });

  it("expires a stale lease and releases its reservation", async () => {
    const started = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000221",
      requestFingerprint: "stale",
      model: "gemini-3.8-flash",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    await expireStaleOperations(DEV_USER_ID, new Date("2026-09-25T12:00:31.000Z"));
    expect((await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:00:31.000Z"))).creditsRemaining).toBe(600);
    const row = await getDb().query.meterOperations.findFirst({
      where: eq(meterOperations.id, started.operationId),
    });
    expect(row?.state).toBe("expired");
  });

  it("cannot overspend the final credits and pauses Gemini below six", async () => {
    const bootstrap = await getUsageSummary(
      DEV_USER_ID,
      new Date("2026-09-25T12:00:00.000Z"),
    );
    expect(bootstrap.creditsGranted).toBe(600);
    const [period] = await getDb().select().from(usagePeriods);
    expect(period).toBeDefined();
    await applyCreditAdjustment({
      ownerId: DEV_USER_ID,
      periodId: period!.id,
      deltaCredits: -594,
      reasonCode: "test",
      now: new Date("2026-09-25T12:00:01.000Z"),
    });

    const attempts = await Promise.allSettled([
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000231",
        requestFingerprint: "final-a",
        model: "gemini-3.8-flash",
        kind: "full",
        now: new Date("2026-09-25T12:01:01.000Z"),
      }),
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000232",
        requestFingerprint: "final-b",
        model: "gemini-3.8-flash",
        kind: "full",
        now: new Date("2026-09-25T12:01:01.000Z"),
      }),
    ]);
    expect(attempts.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const winner = attempts.find(
      (result): result is PromiseFulfilledResult<Awaited<ReturnType<typeof startMeterOperation>>> =>
        result.status === "fulfilled",
    );
    expect(winner).toBeDefined();
    await finishMeterOperation({
      operation: winner!.value,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-25T12:01:02.000Z"),
    });
    expect((await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:01:03.000Z"))).creditsRemaining).toBe(0);

    await applyCreditAdjustment({
      ownerId: DEV_USER_ID,
      periodId: period!.id,
      deltaCredits: 5,
      reasonCode: "test",
      now: new Date("2026-09-25T12:01:04.000Z"),
    });
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000233",
        requestFingerprint: "gemini-paused",
        model: "gemini-3.8-flash",
        kind: "full",
        now: new Date("2026-09-25T12:02:04.000Z"),
      }),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_CREDITS" });
    const mistral = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000234",
      requestFingerprint: "mistral-works",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:02:05.000Z"),
    });
    expect(mistral.usage.creditsRemaining).toBe(4);
  });

  it("limits taste turns, disallows recook, and enforces the UTC daily count", async () => {
    process.env.USAGE_ENFORCEMENT = "required";
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000241",
        requestFingerprint: "taste-recook",
        model: "mistral-small-latest",
        kind: "recook",
        now: new Date("2026-09-25T00:00:00.000Z"),
      }),
    ).rejects.toMatchObject({ code: "TASTE_RECOOK_UNAVAILABLE" });

    for (let index = 0; index < 10; index += 1) {
      const operation = await startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: `00000000-0000-4000-8000-${String(250 + index).padStart(12, "0")}`,
        requestFingerprint: `taste-${index}`,
        model: "mistral-small-latest",
        kind: "full",
        now: new Date(Date.parse("2026-09-25T01:00:00.000Z") + index * 61_000),
      });
      await finishMeterOperation({
        operation,
        state: "continue",
        resultKind: "continue",
        usageEvents: [],
        now: new Date(Date.parse("2026-09-25T01:00:01.000Z") + index * 61_000),
      });
    }
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000299",
        requestFingerprint: "taste-eleven",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T02:00:00.000Z"),
      }),
    ).rejects.toMatchObject({ code: "TASTE_LIMIT_REACHED" });
    expect((await getDb().select().from(tasteUsage))[0]?.clientTurnCount).toBe(10);

    process.env.USAGE_ENFORCEMENT = "off";
    await getDb()
      .insert(dailyUsage)
      .values({
        ownerId: DEV_USER_ID,
        usageDate: "2026-09-26",
        operationCount: 60,
      })
      .onConflictDoUpdate({
        target: [dailyUsage.ownerId, dailyUsage.usageDate],
        set: { operationCount: 60 },
      });
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000300",
        requestFingerprint: "daily",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-26T12:00:00.000Z"),
      }),
    ).rejects.toMatchObject({ code: "DAILY_OPERATION_LIMIT" });
  });

  it("consumes one taste exactly once at ready settlement and blocks another request", async () => {
    process.env.USAGE_ENFORCEMENT = "required";
    const operation = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000271",
      requestFingerprint: "taste-ready",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T03:00:00.000Z"),
    });

    const settlements = await Promise.allSettled([
      finishMeterOperation({
        operation,
        state: "ready",
        resultKind: "ready",
        usageEvents: [],
        now: new Date("2026-09-25T03:00:01.000Z"),
      }),
      finishMeterOperation({
        operation,
        state: "ready",
        resultKind: "ready",
        usageEvents: [],
        now: new Date("2026-09-25T03:00:01.000Z"),
      }),
    ]);
    expect(settlements.every((result) => result.status === "fulfilled")).toBe(true);

    const tasted = await getDb().query.users.findFirst({
      where: eq(users.id, DEV_USER_ID),
    });
    expect(tasted?.tasteConsumedAt).toEqual(new Date("2026-09-25T03:00:01.000Z"));
    expect((await getDb().select().from(tasteUsage))[0]?.readyCount).toBe(1);
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000272",
        requestFingerprint: "second-taste",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T03:01:02.000Z"),
      }),
    ).rejects.toMatchObject({ code: "TASTE_ALREADY_CONSUMED" });

    await createCard(baseInput);
    const saved = await getDb().query.users.findFirst({
      where: eq(users.id, DEV_USER_ID),
    });
    expect(saved?.tasteCompletedAt).toBeInstanceOf(Date);
    expect(saved?.tasteConsumedAt).toEqual(new Date("2026-09-25T03:00:01.000Z"));
  });

  it("opens the 200-call daily provider circuit before another provider request", async () => {
    const operation = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000301",
      requestFingerprint: "provider-limit",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    await getDb()
      .update(dailyUsage)
      .set({ providerCallCount: 200 })
      .where(eq(dailyUsage.ownerId, DEV_USER_ID));
    await expect(
      beginProviderCall(operation, new Date("2026-09-25T12:00:01.000Z")),
    ).rejects.toMatchObject({ code: "PROVIDER_CALL_LIMIT", status: 429 });
    await finishMeterOperation({
      operation,
      state: "failed",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:02.000Z"),
    });
  });

  it("starts a fresh UTC provider-call counter when an operation crosses midnight", async () => {
    const operation = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000302",
      requestFingerprint: "midnight-provider",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T23:59:50.000Z"),
    });

    await expect(
      beginProviderCall(operation, new Date("2026-09-26T00:00:01.000Z")),
    ).resolves.toBeUndefined();
    const rows = await getDb().select().from(dailyUsage);
    expect(rows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          usageDate: "2026-09-25",
          operationCount: 1,
          providerCallCount: 0,
        }),
        expect.objectContaining({
          usageDate: "2026-09-26",
          operationCount: 0,
          providerCallCount: 1,
        }),
      ]),
    );
    await finishMeterOperation({
      operation,
      state: "failed",
      usageEvents: [],
      now: new Date("2026-09-26T00:00:02.000Z"),
    });
  });

  it("keeps the existing period allowance across entitlement restore changes", async () => {
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({
        originalPurchaseDate: new Date("2026-01-31T10:00:00.000Z"),
        purchaseDate: new Date("2026-01-31T10:00:00.000Z"),
      }),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    const first = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000311",
      requestFingerprint: "before-restore",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    await finishMeterOperation({
      operation: first,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:01.000Z"),
    });
    await getDb()
      .update(subscriptionEntitlements)
      .set({ currentTransactionId: "restored-transaction" })
      .where(eq(subscriptionEntitlements.userId, DEV_USER_ID));
    expect((await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:00:02.000Z"))).creditsRemaining).toBe(599);
    expect(await getDb().select().from(usagePeriods)).toHaveLength(1);
  });

  it("stores no prompt, response, or user-text columns in metering tables", async () => {
    const columns = await getSql()<
      { table_name: string; column_name: string }[]
    >`
      select table_name, column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name in (
          'usage_periods', 'meter_operations', 'llm_call_usage',
          'daily_usage', 'credit_adjustments', 'taste_usage'
        )
    `;
    expect(
      columns.filter(({ column_name }) =>
        ["prompt", "response", "body", "thought", "reframe", "output", "raw_text", "user_text"]
          .includes(column_name),
      ),
    ).toEqual([]);
    expect(MeteringError).toBeDefined();
  });

  it("cascades account deletion through taste, subscription, and metering rows", async () => {
    await getDb().insert(tasteUsage).values({ ownerId: DEV_USER_ID, clientTurnCount: 1 });
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({ appAccountToken: DEV_USER_ID }),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000351",
      requestFingerprint: "delete-cascade",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });

    try {
      await deleteOwnerAccount();
      expect(await getDb().select().from(tasteUsage)).toHaveLength(0);
      expect(await getDb().select().from(subscriptionEntitlements)).toHaveLength(0);
      expect(await getDb().select().from(usagePeriods)).toHaveLength(0);
      expect(await getDb().select().from(meterOperations)).toHaveLength(0);
      expect(await getDb().select().from(dailyUsage)).toHaveLength(0);
    } finally {
      await getDb()
        .insert(users)
        .values({
          id: DEV_USER_ID,
          name: "Josip Miljak",
          email: "dev@angles.invalid",
          initials: "JM",
        })
        .onConflictDoNothing();
    }
  });

  it("round-trips a card with four reframes and tags", async () => {
    const stored = await createCard(baseInput);
    expect(stored.results).toHaveLength(4);
    expect(stored.results.map((item) => item.style)).toEqual([...STYLES]);
    expect(stored.tags.map((tag) => tag.slug)).toEqual(["job_interview", "shame"]);
    expect(stored.matching).toEqual({
      category: "work",
      tags: ["job_interview", "shame"],
      intensityBand: "high",
    });
    expect(stored.thoughtOriginal).toBeUndefined();
    expect(stored.isPublic).toBe(false);
    expect(stored.isOwner).toBe(true);
    expect(stored.author).toEqual({ id: DEV_USER_ID, initials: "JM", following: false });
    expect(stored.results.every((item) => item.isFavorite === false)).toBe(true);

    const listed = await listCards({ limit: 50 });
    expect(listed).toHaveLength(1);
    expect(listed[0]?.id).toBe(stored.id);

    const fetched = await getCard(stored.id);
    expect(fetched?.thought).toBe(baseInput.thought);
  });

  it("stamps tasteCompletedAt on the first save and leaves it on the next", async () => {
    const first = await createCard(baseInput);
    const afterFirst = await getDb().query.users.findFirst({
      where: eq(users.id, DEV_USER_ID),
    });
    expect(afterFirst?.tasteCompletedAt).toBeInstanceOf(Date);
    const stamped = afterFirst?.tasteCompletedAt?.getTime();

    await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
    });
    const afterSecond = await getDb().query.users.findFirst({
      where: eq(users.id, DEV_USER_ID),
    });
    expect(afterSecond?.tasteCompletedAt?.getTime()).toBe(stamped);
    expect(first.id).toBeTruthy();
  });

  it("persists isPublic when create sets it", async () => {
    const stored = await createCard({ ...baseInput, isPublic: true });
    expect(stored.isPublic).toBe(true);

    const fetched = await getCard(stored.id);
    expect(fetched?.isPublic).toBe(true);
  });

  it("ignores client matching and re-derives the intensity band", async () => {
    const stored = await createCard({
      ...baseInput,
      meta: {
        ...baseInput.meta,
        intensity: 5,
      },
    });
    expect(stored.intensityBand).toBe("high");
    expect(stored.matching.intensityBand).toBe("high");
  });

  it("dedupes tag slugs across two cards", async () => {
    await createCard(baseInput);
    await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      meta: {
        ...baseInput.meta,
        tags: ["job_interview", "waiting"],
      },
      spotlightStyle: "optimistic",
    });

    const db = (await import("./client.js")).getDb();
    const tagRows = await db.select().from(tags);
    expect(tagRows).toHaveLength(3);
    expect(tagRows.map((tag) => tag.slug).sort()).toEqual(["job_interview", "shame", "waiting"]);
  });

  it("cascades delete to reframes and joins", async () => {
    const stored = await createCard(baseInput);
    const gone = await deleteCard(stored.id);
    expect(gone).toBe(true);

    const db = (await import("./client.js")).getDb();
    const leftoverCards = await db.select().from(cards);
    const leftoverReframes = await db.select().from(cardReframes);
    expect(leftoverCards).toHaveLength(0);
    expect(leftoverReframes).toHaveLength(0);
    expect(await getCard(stored.id)).toBeNull();
  });

  it("rolls back a partial card when reframes fail the unique constraint", async () => {
    await expect(
      createCard({
        ...baseInput,
        results: [
          { style: "stoic", reframe: "First take." },
          { style: "stoic", reframe: "Duplicate style." },
        ],
      }),
    ).rejects.toBeInstanceOf(DbError);

    const listed = await listCards({ limit: 50 });
    expect(listed).toHaveLength(0);

    const db = (await import("./client.js")).getDb();
    const leftover = await db.select({ id: cards.id }).from(cards);
    expect(leftover).toHaveLength(0);
  });

  it("lists by whether a style exists on the card, not by spotlight", async () => {
    const withHumor = await createCard(baseInput);
    await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      results: [
        { style: "stoic", reframe: "A stoic take on waiting." },
        { style: "optimistic", reframe: "An optimistic take on waiting." },
      ],
      spotlightStyle: "optimistic",
      meta: {
        ...baseInput.meta,
        skippedStyles: [
          { style: "humorous", reason: "A joke would land wrong on a wait this raw." },
          { style: "tough_love", reason: "Pushing would punch down." },
        ],
      },
    });

    const humorous = await listCards({ limit: 50, style: "humorous" });
    expect(humorous.map((card) => card.id)).toEqual([withHumor.id]);

    const optimistic = await listCards({ limit: 50, style: "optimistic" });
    expect(optimistic).toHaveLength(2);
  });

  it("patches per-style favorite and public independently", async () => {
    const stored = await createCard(baseInput);
    const liked = await patchCard(stored.id, { isFavorite: true, style: "stoic" });
    expect(liked.ok).toBe(true);
    if (!liked.ok) {
      return;
    }
    expect(liked.card.results.find((item) => item.style === "stoic")?.isFavorite).toBe(true);
    expect(liked.card.results.find((item) => item.style === "optimistic")?.isFavorite).toBe(false);

    const published = await patchCard(stored.id, { isPublic: true });
    expect(published.ok).toBe(true);
    if (!published.ok) {
      return;
    }
    expect(published.card.isPublic).toBe(true);
    expect(published.card.results.find((item) => item.style === "stoic")?.isFavorite).toBe(true);

    const favorites = await listCards({ limit: 50, favorite: true });
    expect(favorites.map((card) => card.id)).toEqual([stored.id]);

    const slim = await createCard({
      ...baseInput,
      thought: "I keep waiting for the offer that is not coming.",
      results: [
        { style: "stoic", reframe: "A stoic take on waiting." },
        { style: "optimistic", reframe: "An optimistic take on waiting." },
      ],
      spotlightStyle: "optimistic",
    });
    const missing = await patchCard(slim.id, { isFavorite: true, style: "humorous" });
    expect(missing).toEqual({ ok: false, reason: "unknown_style" });
  });

  const OTHER_USER_ID = "00000000-0000-4000-8000-000000000099";

  async function insertOtherCard(input: {
    thought: string;
    isPublic: boolean;
    category?: Category;
    emotions?: Emotion[];
    createdAt?: Date;
  }): Promise<string> {
    const db = getDb();
    await db
      .insert(users)
      .values({
        id: OTHER_USER_ID,
        initials: "AL",
        name: "AL",
        email: `seed-${OTHER_USER_ID}@angles.invalid`,
      })
      .onConflictDoNothing();
    const [inserted] = await db
      .insert(cards)
      .values({
        userId: OTHER_USER_ID,
        thoughtEn: input.thought,
        inputLanguage: "en",
        category: input.category ?? "work",
        intensity: 3,
        intensityBand: "mid",
        timeframe: "ongoing",
        safety: "none",
        emotions: input.emotions ?? ["shame", "sadness"],
        skippedStyles: [],
        model: "mistral-small-latest",
        spotlightStyle: "humorous",
        isPublic: input.isPublic,
        createdAt: input.createdAt,
      })
      .returning({ id: cards.id });
    const cardId = inserted?.id;
    if (!cardId) {
      throw new Error("insert failed");
    }
    await db.insert(cardReframes).values(
      STYLES.map((style, position) => ({
        cardId,
        style,
        reframe: `A ${style} take that stays with the original sting.`,
        position,
        isFavorite: style === "stoic",
      })),
    );
    return cardId;
  }

  it("includes the viewer's public card and excludes private cards", async () => {
    const minePublic = await createCard({
      ...baseInput,
      thought: "I posted this and I want it on my own Home.",
      isPublic: true,
    });
    const minePrivate = await createCard({
      ...baseInput,
      thought: "I keep this one private because it is still too raw to share.",
      isPublic: false,
    });
    await getDb()
      .update(cards)
      .set({ createdAt: new Date("2026-09-11T12:00:00.000Z") })
      .where(eq(cards.id, minePublic.id));
    await getDb()
      .update(cards)
      .set({ createdAt: new Date("2026-09-14T12:00:00.000Z") })
      .where(eq(cards.id, minePrivate.id));

    const publicOther = await insertOtherCard({
      thought: "I keep waiting for a reply that is not coming and I feel small.",
      isPublic: true,
      createdAt: new Date("2026-09-13T12:00:00.000Z"),
    });
    const privateOther = await insertOtherCard({
      thought: "Someone else's private note stays off the feed.",
      isPublic: false,
      createdAt: new Date("2026-09-12T12:00:00.000Z"),
    });

    const feed = await listFeed({ limit: 50 });
    expect(feed.map((card) => card.id)).toEqual([publicOther, minePublic.id]);
    expect(feed.map((card) => card.isOwner)).toEqual([false, true]);
    expect(feed[0]?.author).toEqual({ id: OTHER_USER_ID, initials: "AL", following: false });
    expect(feed[1]?.author).toEqual({ id: DEV_USER_ID, initials: "JM", following: false });
    expect(feed.every((card) => card.isPublic)).toBe(true);
    expect(feed.map((card) => card.id)).not.toContain(minePrivate.id);
    expect(feed.map((card) => card.id)).not.toContain(privateOther);
    expect(feed[0]?.results.every((item) => item.isFavorite === false)).toBe(true);
  });

  it("uses OR within each feed facet and AND between facets", async () => {
    const workFear = await insertOtherCard({
      thought: "Work keeps making me afraid I am falling behind.",
      isPublic: true,
      category: "work",
      emotions: ["fear"],
    });
    const moneyOverwhelm = await insertOtherCard({
      thought: "Every bill makes the month feel impossible to hold.",
      isPublic: true,
      category: "money",
      emotions: ["overwhelm"],
    });
    await insertOtherCard({
      thought: "I feel lonely even when my family is in the room.",
      isPublic: true,
      category: "family",
      emotions: ["loneliness"],
    });
    const workShame = await insertOtherCard({
      thought: "Work is going well but I still feel ashamed.",
      isPublic: true,
      category: "work",
      emotions: ["shame"],
    });

    const categories = await listFeed({ limit: 50, categories: ["work", "money"] });
    expect(new Set(categories.map((card) => card.id))).toEqual(
      new Set([workFear, moneyOverwhelm, workShame]),
    );

    const emotions = await listFeed({ limit: 50, emotions: ["fear", "overwhelm"] });
    expect(new Set(emotions.map((card) => card.id))).toEqual(new Set([workFear, moneyOverwhelm]));

    const combined = await listFeed({
      limit: 50,
      categories: ["money"],
      emotions: ["fear", "overwhelm"],
    });
    expect(combined.map((card) => card.id)).toEqual([moneyOverwhelm]);
  });

  it("pages equal timestamps by id without a gap or duplicate", async () => {
    const createdAt = new Date("2026-09-11T12:00:00.000Z");
    const ids = await Promise.all(
      ["One shared instant.", "Two shared instant.", "Three shared instant."].map((thought) =>
        insertOtherCard({ thought, isPublic: true, createdAt }),
      ),
    );

    const first = await listFeed({ limit: 2 });
    expect(first).toHaveLength(2);
    const last = first[1];
    expect(last).toBeDefined();
    if (!last) {
      return;
    }

    const second = await listFeed({
      limit: 2,
      before: { createdAt: new Date(last.createdAt), id: last.id },
    });
    expect(second).toHaveLength(1);
    expect(new Set([...first, ...second].map((card) => card.id))).toEqual(new Set(ids));
  });

  it("pages the library one card at a time with the server's own timestamps", async () => {
    const created = await Promise.all(
      ["First.", "Second.", "Third."].map((suffix) =>
        createCard({ ...baseInput, thought: `${baseInput.thought} ${suffix}` }),
      ),
    );

    const seen: string[] = [];
    let before: { createdAt: Date; id: string } | undefined;
    for (let page = 0; page < 4; page += 1) {
      const [card] = await listCards({ limit: 1, before });
      if (!card) {
        break;
      }
      seen.push(card.id);
      before = { createdAt: new Date(card.createdAt), id: card.id };
    }
    expect(seen).toHaveLength(3);
    expect(new Set(seen)).toEqual(new Set(created.map((card) => card.id)));
  });

  it("saves a heart without mutating the author's flags", async () => {
    const publicOther = await insertOtherCard({
      thought: "I keep waiting for a reply that is not coming and I feel small.",
      isPublic: true,
    });

    const liked = await saveFeedAngle(publicOther, "optimistic");
    expect(liked.ok).toBe(true);
    if (!liked.ok) {
      return;
    }
    expect(liked.card.results.find((item) => item.style === "optimistic")?.isFavorite).toBe(true);
    expect(liked.card.results.find((item) => item.style === "stoic")?.isFavorite).toBe(false);

    const authorRow = await getDb().query.cards.findFirst({
      where: eq(cards.id, publicOther),
      with: { reframes: true },
    });
    expect(authorRow?.reframes.find((item) => item.style === "stoic")?.isFavorite).toBe(true);
    expect(authorRow?.reframes.find((item) => item.style === "optimistic")?.isFavorite).toBe(false);

    const library = await listCards({ limit: 50 });
    const saved = library.find((card) => card.id === publicOther);
    expect(saved?.isOwner).toBe(false);
    expect(saved?.results.find((item) => item.style === "optimistic")?.isFavorite).toBe(true);
    expect(library.some((card) => card.isOwner)).toBe(false);

    const own = await createCard(baseInput);
    const listed = await listCards({ limit: 50 });
    expect(listed.some((card) => card.id === own.id && card.isOwner)).toBe(true);

    const ownSave = await saveFeedAngle(own.id, "stoic");
    expect(ownSave).toEqual({ ok: false, reason: "not_found" });

    const cleared = await clearFeedSaves(publicOther);
    expect(cleared.ok).toBe(true);
    const after = await listCards({ limit: 50 });
    expect(after.some((card) => card.id === publicOther)).toBe(false);
  });

  it("drops a hearted card from the library once its author makes it private", async () => {
    const hearted = await insertOtherCard({
      thought: "I keep checking my phone for a message that is not coming.",
      isPublic: true,
    });
    expect((await saveFeedAngle(hearted, "stoic")).ok).toBe(true);
    expect((await listCards({ limit: 50 })).some((card) => card.id === hearted)).toBe(true);

    await getDb().update(cards).set({ isPublic: false }).where(eq(cards.id, hearted));

    expect((await listCards({ limit: 50 })).some((card) => card.id === hearted)).toBe(false);
    expect((await listCards({ limit: 50, favorite: true })).some((card) => card.id === hearted)).toBe(
      false,
    );
    expect(await clearFeedSaves(hearted)).toEqual({ ok: true });
    expect(await clearFeedSaves(hearted)).toEqual({ ok: false });

    await getDb().update(cards).set({ isPublic: true }).where(eq(cards.id, hearted));
    expect((await listCards({ limit: 50 })).some((card) => card.id === hearted)).toBe(false);
  });

  it("follows and unfollows another user without changing feed order", async () => {
    expect(await followUser(DEV_USER_ID)).toBe("self");
    expect(await followUser("00000000-0000-4000-8000-000000000066")).toBe("not_found");

    const cardId = await insertOtherCard({
      thought: "I keep waiting for a reply that is not coming and I feel small.",
      isPublic: true,
    });
    expect(await followUser(OTHER_USER_ID)).toBe("ok");
    expect(await followUser(OTHER_USER_ID)).toBe("ok");

    const followed = await listFeed({ limit: 50 });
    expect(followed.find((card) => card.id === cardId)?.author.following).toBe(true);

    expect(await unfollowUser(OTHER_USER_ID)).toBe("ok");
    expect(await unfollowUser(OTHER_USER_ID)).toBe("ok");
    const cleared = await listFeed({ limit: 50 });
    expect(cleared.map((card) => card.id)).toEqual(followed.map((card) => card.id));
    expect(cleared.find((card) => card.id === cardId)?.author.following).toBe(false);
  });

  it("enforces mutual isolation and clears cross-user follows and saves on block", async () => {
    const otherCard = await insertOtherCard({
      thought: "This public card should disappear after either side blocks.",
      isPublic: true,
    });
    const ownerCard = await createCard({ ...baseInput, isPublic: true });

    await getDb().insert(follows).values([
      { followerId: DEV_USER_ID, followeeId: OTHER_USER_ID },
      { followerId: OTHER_USER_ID, followeeId: DEV_USER_ID },
    ]);
    await getDb().insert(savedAngles).values([
      { userId: DEV_USER_ID, cardId: otherCard, style: "stoic" },
      { userId: OTHER_USER_ID, cardId: ownerCard.id, style: "stoic" },
    ]);

    expect(await blockUser(OTHER_USER_ID)).toBe("ok");
    expect(await blockUser(OTHER_USER_ID)).toBe("ok");
    expect(await getDb().select().from(follows)).toHaveLength(0);
    expect(await getDb().select().from(savedAngles)).toHaveLength(0);
    expect((await listFeed({ limit: 50 })).map((card) => card.id)).not.toContain(otherCard);
    expect(await followUser(OTHER_USER_ID)).toBe("blocked");
    expect(await saveFeedAngle(otherCard, "stoic")).toEqual({ ok: false, reason: "not_found" });
    expect(await getDb().select().from(userBlocks)).toHaveLength(1);

    expect(await unblockUser(OTHER_USER_ID)).toBe("ok");
    expect(await unblockUser(OTHER_USER_ID)).toBe("ok");
    expect(await getDb().select().from(userBlocks)).toHaveLength(0);
  });

  it("serializes block against concurrent follow and save writes", async () => {
    const otherCard = await insertOtherCard({
      thought: "Concurrent social writes must not survive a block.",
      isPublic: true,
    });

    await Promise.all([followUser(OTHER_USER_ID), blockUser(OTHER_USER_ID)]);
    expect(await getDb().select().from(follows)).toHaveLength(0);
    expect(await getDb().select().from(userBlocks)).toHaveLength(1);

    expect(await unblockUser(OTHER_USER_ID)).toBe("ok");
    await Promise.all([saveFeedAngle(otherCard, "stoic"), blockUser(OTHER_USER_ID)]);
    expect(await getDb().select().from(savedAngles)).toHaveLength(0);
    expect(await getDb().select().from(userBlocks)).toHaveLength(1);
  });

  it("hides a report immediately and locks publication at three unique reporters", async () => {
    const reported = await insertOtherCard({
      thought: "A public card that receives community reports.",
      isPublic: true,
    });

    expect(await saveFeedAngle(reported, "stoic")).toMatchObject({ ok: true });
    expect(await reportCard(reported, "spam")).toEqual({ ok: true, created: true });
    expect(await reportCard(reported, "hate")).toEqual({ ok: true, created: false });
    expect((await listFeed({ limit: 50 })).map((card) => card.id)).not.toContain(reported);
    expect((await listCards({ limit: 50 })).map((card) => card.id)).not.toContain(reported);

    const reporterIds = [
      "00000000-0000-4000-8000-000000000077",
      "00000000-0000-4000-8000-000000000088",
    ];
    await getDb()
      .insert(users)
      .values(
        reporterIds.map((id) => ({
          id,
          initials: "RP",
          name: "Reporter",
          email: `seed-${id}@angles.invalid`,
        })),
      )
      .onConflictDoNothing();
    for (const reporterId of reporterIds) {
      const response = await safetyApp.request(`/cards/${reported}/report`, {
        method: "POST",
        headers: {
          Authorization: `Bearer test:${reporterId}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ reason: "harassment" }),
      });
      expect(response.status).toBe(200);
    }

    const row = await getDb().query.cards.findFirst({ where: eq(cards.id, reported) });
    expect(row?.isPublic).toBe(false);
    expect(await getDb().select().from(cardReports)).toHaveLength(3);
  });

  it("prevents republishing an owned card with three reports", async () => {
    const owned = await createCard({ ...baseInput, isPublic: false });
    const reporterIds = [
      "00000000-0000-4000-8000-000000000077",
      "00000000-0000-4000-8000-000000000088",
      "00000000-0000-4000-8000-000000000099",
    ];
    await getDb()
      .insert(users)
      .values(
        reporterIds.map((id) => ({
          id,
          initials: "RP",
          name: "Reporter",
          email: `seed-${id}@angles.invalid`,
        })),
      )
      .onConflictDoNothing();
    await getDb().insert(cardReports).values(
      reporterIds.map((reporterId) => ({ reporterId, cardId: owned.id, reason: "other" as const })),
    );

    expect(await patchCard(owned.id, { isPublic: true })).toEqual({
      ok: false,
      reason: "publication_blocked",
    });
  });
});
