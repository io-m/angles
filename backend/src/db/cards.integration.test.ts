import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { LEGACY_STYLES, runWithStyleSet } from "../lib/styleSet.js";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { and, eq, sql } from "drizzle-orm";
import {
  CATEGORIES,
  STYLES,
  type Category,
  type CreateCardInput,
  type Emotion,
  type StoredCard,
  type Style,
} from "../types/index.js";
import { DEV_USER_ID, runAsOwner } from "../lib/authStub.js";
import { MONTHLY_CREDITS, USAGE_PLAN_VERSION } from "../lib/meteringPolicy.js";
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
  const parsed = new URL(testUrl);
  const database = decodeURIComponent(parsed.pathname).replace(/^\/+/, "");
  if (
    !["localhost", "127.0.0.1", "[::1]"].includes(parsed.hostname) ||
    database !== "angles_test"
  ) {
    throw new Error("DATABASE_URL_TEST must point to local database angles_test");
  }
  process.env.DATABASE_URL = testUrl;
}

const { closePool, getDb, getSql } = await import("./client.js");
const { createCard, deleteCard, findOwnCardByCookSignature, getCard, listCards, patchCard } =
  await import("./cards.js");
const { acceptOwnerTerms, deleteOwnerAccount } = await import("./users.js");
const { blockUser, cardPublicationLocked, reportCard, unblockUser } =
  await import("./communitySafety.js");
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
  findReframeReplay,
  finishMeterOperation,
  getUsageSummary,
  startMeterOperation,
} = await import("./metering.js");
const { openReplay, parseReplayKey, sealReplay } = await import("../lib/reframeReplay.js");
const { clearStackCache, listPublicCardsForUser, listStack } = await import("./stack.js");
const { clearDecision, writeDecision } = await import("./decisions.js");
const { followUser, unfollowUser } = await import("./follows.js");
const { deliverLovePushes, markLoveNotificationsRead } = await import("./loveNotifications.js");
const {
  deliverFollowPush,
  listFollowNotifications,
  markFollowNotificationsRead,
  registerDeviceToken,
  setNotificationPreferences,
} = await import("./followNotifications.js");
const {
  deleteReportedCard,
  listPendingReports,
  publishHiddenCard,
  resolveCardReports,
  restorePublishing,
  suspendPublishing,
} = await import("./reportReview.js");
const { createApp } = await import("../app.js");
const {
  cardDecisions,
  cardReframes,
  cardReports,
  cards,
  dailyUsage,
  deviceTokens,
  followNotifications,
  follows,
  loveNotifications,
  meterOperations,
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
  results: LEGACY_STYLES.map((style) => ({ style, reframe: `A ${style} take on showing up.` })),
  meta: {
    category: "work",
    tags: ["job_interview", "shame"],
    intensity: 4,
    timeframe: "past",
    emotions: ["shame", "fear"],
    distortions: [],
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
    clearStackCache();
    await getSql()`
      TRUNCATE llm_call_usage, credit_adjustments, meter_operations, daily_usage, taste_usage,
        usage_periods, subscription_events, subscription_entitlements, user_blocks, card_reports,
        follow_notifications, love_notifications, device_tokens, follows, card_decisions, card_reframes, card_tags, cards,
        tags, category_proposals
        RESTART IDENTITY CASCADE
    `;
    await getDb()
      .update(users)
      .set({ tasteCompletedAt: null, tasteConsumedAt: null, publishingSuspendedAt: null })
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

  it("lets a deleted account's purchase move to the same Apple ID's new account, never a live one's", async () => {
    const liveOwnerId = "00000000-0000-4000-8000-000000000197";
    await getDb().insert(users).values({
      id: liveOwnerId,
      name: "Live",
      email: "live-owner@angles.invalid",
      initials: "LV",
    });
    await expect(
      syncSubscriptionTransaction(
        DEV_USER_ID,
        appStoreTransaction({ appAccountToken: liveOwnerId }),
      ),
    ).rejects.toBeInstanceOf(SubscriptionOwnershipError);

    await getDb().delete(users).where(eq(users.id, liveOwnerId));
    const adopted = await syncSubscriptionTransaction(
      DEV_USER_ID,
      appStoreTransaction({ appAccountToken: liveOwnerId }),
      new Date("2026-09-25T10:00:02.000Z"),
    );
    expect(adopted.isEntitled).toBe(true);
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

  it("keeps grace on the last paid quota and locks billing retry once grace ends", async () => {
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
    ).toBe(MONTHLY_CREDITS - 1);
    expect(await getDb().select().from(usagePeriods)).toHaveLength(1);

    // The phone re-syncs its lapsed receipt during grace; that must not end grace early.
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      { ...paidTransaction, signedDate: new Date("2026-10-28T10:00:00.000Z") },
      new Date("2026-10-28T10:00:01.000Z"),
    );
    expect((await getSubscription(DEV_USER_ID)).status).toBe("grace");
    expect(await hasActiveEntitlement(DEV_USER_ID, new Date("2026-10-28T10:00:02.000Z"))).toBe(true);

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
    expect((await getSubscription(DEV_USER_ID)).isEntitled).toBe(false);
    expect(await hasActiveEntitlement(DEV_USER_ID, new Date("2026-11-02T10:00:00.000Z"))).toBe(false);
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000186",
        requestFingerprint: "retry-blocked",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-11-02T10:00:00.000Z"),
      }),
    ).rejects.toMatchObject({ code: "SUBSCRIPTION_REQUIRED" });
    await syncSubscriptionTransaction(
      DEV_USER_ID,
      { ...paidTransaction, signedDate: new Date("2026-11-03T10:00:00.000Z") },
      new Date("2026-11-03T10:00:01.000Z"),
    );
    expect((await getSubscription(DEV_USER_ID)).status).toBe("billing_retry");
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
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    expect(ready.usage.creditsRemaining).toBe(MONTHLY_CREDITS - 1);
    const afterReady = await finishMeterOperation({
      operation: ready,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:01.000Z"),
    });
    expect(afterReady.creditsRemaining).toBe(MONTHLY_CREDITS - 1);

    // The routed model is recorded, not priced: an OpenAI-routed cook costs the same one credit.
    const continued = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000202",
      requestFingerprint: "continue-fingerprint",
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T12:01:01.000Z"),
    });
    expect(continued.usage.creditsRemaining).toBe(MONTHLY_CREDITS - 2);
    const afterContinue = await finishMeterOperation({
      operation: continued,
      state: "continue",
      resultKind: "continue",
      usageEvents: [],
      now: new Date("2026-09-25T12:01:02.000Z"),
    });
    expect(afterContinue.creditsRemaining).toBe(MONTHLY_CREDITS - 1);
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
    ).toBe(MONTHLY_CREDITS);
    // A failed attempt was never charged, so the same key cooks again on the same row.
    const restarted = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000211",
      requestFingerprint: "same",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:03.000Z"),
    });
    expect(restarted.operationId).toBe(first.operationId);
    expect(restarted.usage.creditsRemaining).toBe(MONTHLY_CREDITS - 1);
    // The restarted attempt is the one running operation again.
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000211",
        requestFingerprint: "same",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:04.000Z"),
      }),
    ).rejects.toMatchObject({ code: "OPERATION_RUNNING" });

    // A key whose attempt ended on a lease that ran out also restarts, without a double reserve.
    const afterRestart = await finishMeterOperation({
      operation: restarted,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      now: new Date("2026-09-25T12:00:05.000Z"),
    });
    expect(afterRestart.creditsRemaining).toBe(MONTHLY_CREDITS - 1);
    // A finished attempt without a stored replay stays a hard stop: it may have been charged.
    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000211",
        requestFingerprint: "same",
        model: "mistral-small-latest",
        kind: "full",
        now: new Date("2026-09-25T12:00:06.000Z"),
      }),
    ).rejects.toMatchObject({ code: "REQUEST_ALREADY_COMPLETED" });
  });

  it("restarts an expired attempt on the same key without reserving twice", async () => {
    const key = "00000000-0000-4000-8000-000000000231";
    const started = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: key,
      requestFingerprint: "lease",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    const restarted = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: key,
      requestFingerprint: "lease",
      model: "mistral-small-latest",
      kind: "full",
      now: new Date("2026-09-25T12:00:31.000Z"),
    });
    expect(restarted.operationId).toBe(started.operationId);
    expect(restarted.usage.creditsRemaining).toBe(MONTHLY_CREDITS - 1);
    const rows = await getSql()<{ count: number }[]>`
      select count(*)::int as count from meter_operations where client_request_id = ${key}
    `;
    expect(rows[0]?.count).toBe(1);
  });

  it("keeps a finished operation's sealed body for its own request until it expires", async () => {
    const replayKey = parseReplayKey(Buffer.alloc(32, 3).toString("base64url"))!;
    const operation = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000221",
      requestFingerprint: "replayed",
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    const body = { kind: "ready", thought: baseInput.thought, signature: "sig" };
    await finishMeterOperation({
      operation,
      state: "ready",
      resultKind: "ready",
      usageEvents: [],
      replay: sealReplay(replayKey, operation.operationId, body),
      now: new Date("2026-09-25T12:00:01.000Z"),
    });
    const [stored] = await getSql()<{ ciphertext: string }[]>`select ciphertext from reframe_replays`;
    expect(stored?.ciphertext).not.toContain("interview");

    const lookup = {
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000221",
      requestFingerprint: "replayed",
    };
    const found = await findReframeReplay({ ...lookup, now: new Date("2026-09-25T12:30:00.000Z") });
    expect(found?.chargedCredits).toBe(1);
    expect(openReplay(replayKey, found!.operationId, found!.sealed)).toEqual(body);
    expect(
      await findReframeReplay({
        ...lookup,
        requestFingerprint: "edited",
        now: new Date("2026-09-25T12:30:00.000Z"),
      }),
    ).toBeNull();
    expect(
      await findReframeReplay({ ...lookup, now: new Date("2026-09-25T13:00:01.000Z") }),
    ).toBeNull();

    const failed = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000222",
      requestFingerprint: "failed",
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T13:00:02.000Z"),
    });
    await finishMeterOperation({
      operation: failed,
      state: "failed",
      usageEvents: [],
      replay: sealReplay(replayKey, failed.operationId, body),
      now: new Date("2026-09-25T13:00:03.000Z"),
    });
    const remaining = await getSql()<{ count: number }[]>`
      select count(*)::int as count from reframe_replays
    `;
    expect(remaining[0]?.count).toBe(0);
  });

  it("applies the live 240 grant to an open period created under 600", async () => {
    const now = new Date("2026-09-25T12:00:00.000Z");
    await getUsageSummary(DEV_USER_ID, now);
    const [period] = await getDb().select().from(usagePeriods);
    expect(period).toBeDefined();
    await getSql()`
      update usage_periods
      set granted_credits = 600,
          charged_credits = 14,
          plan_version = 'monthly-600-v1'
      where id = ${period!.id}
    `;
    const summary = await getUsageSummary(DEV_USER_ID, now);
    expect(summary.creditsGranted).toBe(MONTHLY_CREDITS);
    expect(summary.creditsRemaining).toBe(MONTHLY_CREDITS - 14);
    const [updated] = await getDb().select().from(usagePeriods);
    expect(updated?.planVersion).toBe(USAGE_PLAN_VERSION);
    expect(updated?.grantedCredits).toBe(MONTHLY_CREDITS);
  });

  it("floors the grant at spent credits when spent exceeds 240 under 600", async () => {
    const now = new Date("2026-09-25T12:00:00.000Z");
    await getUsageSummary(DEV_USER_ID, now);
    const [period] = await getDb().select().from(usagePeriods);
    expect(period).toBeDefined();
    await getSql()`
      update usage_periods
      set granted_credits = 600,
          charged_credits = 250,
          plan_version = 'monthly-600-v1'
      where id = ${period!.id}
    `;
    const summary = await getUsageSummary(DEV_USER_ID, now);
    expect(summary.creditsGranted).toBe(250);
    expect(summary.creditsRemaining).toBe(0);
    const [updated] = await getDb().select().from(usagePeriods);
    expect(updated?.planVersion).toBe(USAGE_PLAN_VERSION);
    expect(updated?.grantedCredits).toBe(250);
  });

  it("expires a stale lease and releases its reservation", async () => {
    const started = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000221",
      requestFingerprint: "stale",
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T12:00:00.000Z"),
    });
    await expireStaleOperations(DEV_USER_ID, new Date("2026-09-25T12:00:31.000Z"));
    expect((await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:00:31.000Z"))).creditsRemaining).toBe(MONTHLY_CREDITS);
    const row = await getDb().query.meterOperations.findFirst({
      where: eq(meterOperations.id, started.operationId),
    });
    expect(row?.state).toBe("expired");
  });

  it("cannot overspend the final credit and stops at zero", async () => {
    const bootstrap = await getUsageSummary(
      DEV_USER_ID,
      new Date("2026-09-25T12:00:00.000Z"),
    );
    expect(bootstrap.creditsGranted).toBe(MONTHLY_CREDITS);
    const [period] = await getDb().select().from(usagePeriods);
    expect(period).toBeDefined();
    await applyCreditAdjustment({
      ownerId: DEV_USER_ID,
      periodId: period!.id,
      deltaCredits: -(MONTHLY_CREDITS - 1),
      reasonCode: "test",
      now: new Date("2026-09-25T12:00:01.000Z"),
    });

    const attempts = await Promise.allSettled([
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000231",
        requestFingerprint: "final-a",
        model: "gpt-4.1-mini",
        kind: "full",
        now: new Date("2026-09-25T12:01:01.000Z"),
      }),
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000232",
        requestFingerprint: "final-b",
        model: "gpt-4.1-mini",
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

    await expect(
      startMeterOperation({
        ownerId: DEV_USER_ID,
        clientRequestId: "00000000-0000-4000-8000-000000000233",
        requestFingerprint: "empty",
        model: "gpt-4.1-mini",
        kind: "full",
        now: new Date("2026-09-25T12:02:04.000Z"),
      }),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_CREDITS" });
    await applyCreditAdjustment({
      ownerId: DEV_USER_ID,
      periodId: period!.id,
      deltaCredits: 5,
      reasonCode: "test",
      now: new Date("2026-09-25T12:02:05.000Z"),
    });
    const refilled = await startMeterOperation({
      ownerId: DEV_USER_ID,
      clientRequestId: "00000000-0000-4000-8000-000000000234",
      requestFingerprint: "refilled",
      model: "gpt-4.1-mini",
      kind: "full",
      now: new Date("2026-09-25T12:02:06.000Z"),
    });
    expect(refilled.usage.creditsRemaining).toBe(4);
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
    expect(await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T02:59:00.000Z"))).toMatchObject({
      plan: "taste",
      creditsRemaining: 1,
      creditsGranted: 1,
      warning: "normal",
    });
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
    expect(await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T03:00:02.000Z"))).toMatchObject({
      plan: "taste",
      creditsRemaining: 0,
      warning: "empty",
    });
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
    expect((await getUsageSummary(DEV_USER_ID, new Date("2026-09-25T12:00:02.000Z"))).creditsRemaining).toBe(MONTHLY_CREDITS - 1);
    expect(await getDb().select().from(usagePeriods)).toHaveLength(1);
  });

  it("saves one card per signed cook, even when two saves race", async () => {
    const first = await createCard(baseInput, { cookSignature: "cook-signature-1" });
    const retry = await createCard(baseInput, { cookSignature: "cook-signature-1" });
    expect(retry.id).toBe(first.id);
    expect((await findOwnCardByCookSignature("cook-signature-1"))?.id).toBe(first.id);

    const raced = await Promise.all([
      createCard(baseInput, { cookSignature: "cook-signature-2" }),
      createCard(baseInput, { cookSignature: "cook-signature-2" }),
    ]);
    expect(raced[0].id).toBe(raced[1].id);

    await createCard(baseInput);
    await createCard(baseInput);
    expect(await getDb().select().from(cards)).toHaveLength(4);
    expect(await getDb().select().from(cardReframes)).toHaveLength(4 * baseInput.results.length);
    expect(await findOwnCardByCookSignature("never-saved")).toBeNull();
  });

  it("removes a user's cards with the user row", async () => {
    const otherUserId = "00000000-0000-4000-8000-000000000197";
    await getDb().insert(users).values({
      id: otherUserId,
      name: "Other",
      email: "other-cascade@angles.invalid",
      initials: "OT",
    });
    await getDb().insert(cards).values({
      userId: otherUserId,
      thoughtEn: "Another thought.",
      inputLanguage: "en",
      category: "work",
      intensity: 2,
      intensityBand: "low",
      timeframe: "past",
      safety: "none",
      emotions: ["fear"],
      skippedStyles: [],
      model: "mistral-small-latest",
      spotlightStyle: "stoic",
    });

    await getDb().delete(users).where(eq(users.id, otherUserId));

    expect(await getDb().select().from(cards).where(eq(cards.userId, otherUserId))).toEqual([]);
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
          'daily_usage', 'credit_adjustments', 'taste_usage', 'reframe_replays'
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
    expect(stored.results.map((item) => item.style)).toEqual([...LEGACY_STYLES]);
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
    expect(stored.openingStyle).toBe("stoic");
    expect(stored.isHouse).toBe(false);

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
      spotlightStyle: "hopeful",
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
        { style: "hopeful", reframe: "A hopeful take on waiting." },
      ],
      spotlightStyle: "hopeful",
      meta: {
        ...baseInput.meta,
        skippedStyles: [
          { style: "witty", reason: "A joke would land wrong on a wait this raw." },
          { style: "tough", reason: "Pushing would punch down." },
        ],
      },
    });

    const witty = await listCards({ limit: 50, style: "witty" });
    expect(witty.map((card) => card.id)).toEqual([withHumor.id]);

    const hopeful = await listCards({ limit: 50, style: "hopeful" });
    expect(hopeful).toHaveLength(2);
  });

  it("patches public on its own", async () => {
    const stored = await createCard(baseInput);
    const published = await patchCard(stored.id, { isPublic: true });
    expect(published.ok).toBe(true);
    if (!published.ok) {
      return;
    }
    expect(published.card.isPublic).toBe(true);
    const hidden = await patchCard(stored.id, { isPublic: false });
    expect(hidden.ok && hidden.card.isPublic).toBe(false);
  });

  const OTHER_USER_ID = "00000000-0000-4000-8000-000000000099";
  const HOUSE_USER_ID = "00000000-0000-4000-8000-0000000000aa";

  async function ensureUser(id: string, kind: "person" | "house" = "person"): Promise<void> {
    await getDb()
      .insert(users)
      .values({ id, initials: kind === "house" ? "A" : "AL", name: "AL", email: `seed-${id}@angles.invalid`, kind })
      .onConflictDoNothing();
  }

  async function insertOtherCard(input: {
    thought: string;
    isPublic: boolean;
    category?: Category;
    emotions?: Emotion[];
    createdAt?: Date;
    authorId?: string;
    intensity?: number;
  }): Promise<string> {
    const db = getDb();
    const authorId = input.authorId ?? OTHER_USER_ID;
    await ensureUser(authorId, authorId === HOUSE_USER_ID ? "house" : "person");
    const [inserted] = await db
      .insert(cards)
      .values({
        userId: authorId,
        thoughtEn: input.thought,
        inputLanguage: "en",
        category: input.category ?? "work",
        intensity: input.intensity ?? 3,
        intensityBand: "mid",
        timeframe: "ongoing",
        safety: "none",
        emotions: input.emotions ?? ["shame", "sadness"],
        skippedStyles: [],
        model: "mistral-small-latest",
        spotlightStyle: "witty",
        isPublic: input.isPublic,
        createdAt: input.createdAt,
      })
      .returning({ id: cards.id });
    const cardId = inserted?.id;
    if (!cardId) {
      throw new Error("insert failed");
    }
    await db.insert(cardReframes).values(
      LEGACY_STYLES.map((style, position) => ({
        cardId,
        style,
        reframe: `A ${style} take that stays with the original sting.`,
        position,
      })),
    );
    return cardId;
  }

  /** Someone else's save, written straight to the table: the fixture is not the viewer. */
  async function strangerSaves(cardId: string, userId: string, style: Style = "stoic"): Promise<void> {
    await ensureUser(userId);
    await getDb()
      .insert(cardDecisions)
      .values({ userId, cardId, kind: "save", style, checkedStyles: [style], passes: 0 })
      .onConflictDoNothing();
  }

  const save = (cardId: string, style: Style = "stoic") =>
    writeDecision(cardId, { kind: "save", style, checkedStyles: [style], passes: 0 });
  const pass = (cardId: string, checkedStyles: Style[] = ["witty"], passes = 1) =>
    writeDecision(cardId, { kind: "pass", style: checkedStyles[0] ?? "witty", checkedStyles, passes });

  it("saves a whole card on the angle on screen and lists it under Saved", async () => {
    const theirs = await insertOtherCard({
      thought: "I keep waiting for a reply that is not coming and I feel small.",
      isPublic: true,
    });
    const own = await createCard(baseInput);

    const saved = await writeDecision(theirs, {
      kind: "save",
      style: "hopeful",
      checkedStyles: ["witty"],
      passes: 0,
    });
    expect(saved.ok).toBe(true);
    if (!saved.ok) {
      return;
    }
    // The style on screen always counts as seen.
    expect(saved.decision).toMatchObject({ kind: "save", style: "hopeful", passes: 0 });
    expect(new Set(saved.decision.checkedStyles)).toEqual(new Set(["witty", "hopeful"]));

    const savedList = await listCards({ limit: 50, saved: true });
    expect(savedList.map((card) => card.id)).toEqual([theirs]);
    expect(savedList[0]?.isOwner).toBe(false);
    expect(savedList[0]?.openingStyle).toBe("hopeful");
    expect(savedList[0]?.decision?.kind).toBe("save");

    expect((await listCards({ limit: 50, saved: false })).map((card) => card.id)).toEqual([own.id]);
    expect(new Set((await listCards({ limit: 50 })).map((card) => card.id))).toEqual(new Set([own.id, theirs]));

    // Saving again is the same write, not a second row.
    expect((await save(theirs, "hopeful")).ok).toBe(true);
    expect(await getDb().select().from(cardDecisions)).toHaveLength(1);
  });

  it("refuses decisions on your own, private, unknown-style, reported, and missing cards", async () => {
    const own = await createCard({ ...baseInput, isPublic: true });
    expect(await save(own.id)).toEqual({ ok: false, reason: "own_card" });

    const priv = await insertOtherCard({ thought: "A private note stays undecidable.", isPublic: false });
    expect(await save(priv)).toEqual({ ok: false, reason: "not_public" });

    const theirs = await insertOtherCard({ thought: "A public note with four classic angles.", isPublic: true });
    expect(await save(theirs, "tender")).toEqual({ ok: false, reason: "unknown_style" });
    expect(
      await writeDecision(theirs, { kind: "pass", style: "stoic", checkedStyles: ["stoic", "values"], passes: 1 }),
    ).toEqual({ ok: false, reason: "unknown_style" });

    expect(await save("00000000-0000-4000-8000-00000000dead")).toEqual({ ok: false, reason: "not_found" });

    await reportCard(theirs, "other");
    expect(await save(theirs)).toEqual({ ok: false, reason: "not_found" });
    expect(await getDb().select().from(cardDecisions)).toHaveLength(0);
  });

  it("tells the author about a new love, and takes it back on unsave or rewind", async () => {
    const theirs = await insertOtherCard({ thought: "A card someone will love.", isPublic: true });
    const lovesFor = () => getDb().select().from(loveNotifications).where(eq(loveNotifications.cardId, theirs));

    const first = await save(theirs, "hopeful");
    expect(first.ok && first.loved).toBe(true);
    expect(await lovesFor()).toMatchObject([
      { recipientId: OTHER_USER_ID, actorId: DEV_USER_ID, style: "hopeful", readAt: null },
    ]);
    // A repeated save is the same love.
    const again = await save(theirs, "hopeful");
    expect(again.ok && again.loved).toBe(false);
    expect(await lovesFor()).toHaveLength(1);

    expect((await pass(theirs, [...LEGACY_STYLES], 2)).ok).toBe(true);
    expect(await lovesFor()).toHaveLength(0);

    expect((await save(theirs)).ok).toBe(true);
    expect(await clearDecision(theirs)).toEqual({ ok: true });
    expect(await lovesFor()).toHaveLength(0);

    // From Angles never hears about loves.
    const house = await insertOtherCard({ thought: "A house card.", isPublic: true, authorId: HOUSE_USER_ID });
    const houseSave = await save(house);
    expect(houseSave.ok && houseSave.loved).toBe(false);
  });

  it("lists loves to the author, named only when the lover allows it, and reads them", async () => {
    const theirs = await insertOtherCard({ thought: "A card someone will love.", isPublic: true });
    expect((await save(theirs, "witty")).ok).toBe(true);
    try {
      const named = await runAsOwner(OTHER_USER_ID, () => listFollowNotifications());
      expect(named.unreadCount).toBe(1);
      expect(named.loves).toMatchObject([
        { style: "witty", readAt: null, card: { id: theirs, thought: "A card someone will love." }, actor: { id: DEV_USER_ID } },
      ]);

      await setNotificationPreferences({ shareLoveName: false });
      const unnamed = await runAsOwner(OTHER_USER_ID, () => listFollowNotifications());
      expect(unnamed.loves[0]?.actor).toBeUndefined();

      const loveId = unnamed.loves[0]?.id as string;
      // Nobody else can read someone's love.
      expect(await markLoveNotificationsRead(loveId)).toBe(0);
      expect(await runAsOwner(OTHER_USER_ID, () => markLoveNotificationsRead(loveId))).toBe(0);
      expect((await runAsOwner(OTHER_USER_ID, () => listFollowNotifications())).loves[0]?.readAt).not.toBeNull();

      // A read love stays when the save is taken back; an unread one would not.
      expect((await pass(theirs, [...LEGACY_STYLES], 2)).ok).toBe(true);
      expect(await getDb().select().from(loveNotifications)).toHaveLength(1);

      await blockUser(OTHER_USER_ID);
      expect(await getDb().select().from(loveNotifications)).toHaveLength(0);
    } finally {
      await setNotificationPreferences({ shareLoveName: true });
    }
  });

  it("pushes a card's loves once, together, and waits out the quiet window", async () => {
    const theirs = await insertOtherCard({ thought: "A card someone will love.", isPublic: true });
    const THIRD_ID = "00000000-0000-4000-8000-000000000098";
    await ensureUser(THIRD_ID);
    const previous = {
      APNS_KEY: process.env.APNS_KEY,
      APNS_KEY_ID: process.env.APNS_KEY_ID,
      APNS_TEAM_ID: process.env.APNS_TEAM_ID,
      APNS_BUNDLE_ID: process.env.APNS_BUNDLE_ID,
    };
    const sent: { title: string; body: string; collapseId: string; actorId?: string; cardId?: string; style?: Style }[] = [];
    const record = async (alert: { title: string; body: string; collapseId: string; actorId?: string; cardId?: string; style?: Style }) => {
      sent.push({ title: alert.title, body: alert.body, collapseId: alert.collapseId, actorId: alert.actorId, cardId: alert.cardId, style: alert.style });
      return "sent" as const;
    };
    vi.useFakeTimers({ toFake: ["setTimeout"] });
    try {
      process.env.APNS_KEY = "test-key";
      process.env.APNS_KEY_ID = "KEYID12345";
      process.env.APNS_TEAM_ID = "TEAMID1234";
      process.env.APNS_BUNDLE_ID = "app.angles.ios";
      await runAsOwner(OTHER_USER_ID, () => registerDeviceToken("ef".repeat(32), "sandbox"));

      expect((await save(theirs)).ok).toBe(true);
      const now = new Date();
      const [viewer] = await getDb().select({ name: users.name }).from(users).where(eq(users.id, DEV_USER_ID));
      expect(await deliverLovePushes(theirs, record, now)).toBe("sent");
      expect(sent).toEqual([
        {
          title: viewer?.name.trim() || "Someone",
          body: "Loved your Stoic angle",
          collapseId: `love-${theirs}`,
          actorId: DEV_USER_ID,
          cardId: theirs,
          style: "stoic",
        },
      ]);
      expect(await deliverLovePushes(theirs, record, now)).toBe("none");

      await getDb()
        .insert(cardDecisions)
        .values({ userId: THIRD_ID, cardId: theirs, kind: "save", style: "stoic", checkedStyles: ["stoic"], passes: 0 });
      await getDb().insert(loveNotifications).values({ recipientId: OTHER_USER_ID, actorId: THIRD_ID, cardId: theirs, style: "stoic" });
      expect(await deliverLovePushes(theirs, record, new Date(now.getTime() + 60_000))).toBe("throttled");
      expect(sent).toHaveLength(1);

      const later = new Date(now.getTime() + 31 * 60_000);
      expect(await deliverLovePushes(theirs, record, later)).toBe("sent");
      expect(sent[1]).toMatchObject({ title: "AL and 1 other", body: "Loved your post", cardId: theirs, style: "stoic" });

      await runAsOwner(OTHER_USER_ID, () => setNotificationPreferences({ notifyLoves: false }));
      await getDb().delete(loveNotifications);
      await getDb().insert(loveNotifications).values({ recipientId: OTHER_USER_ID, actorId: THIRD_ID, cardId: theirs, style: "stoic" });
      expect(await deliverLovePushes(theirs, record, new Date(later.getTime() + 31 * 60_000))).toBe("skipped");
      expect(sent).toHaveLength(2);
    } finally {
      vi.clearAllTimers();
      vi.useRealTimers();
      await runAsOwner(OTHER_USER_ID, () => setNotificationPreferences({ notifyLoves: true }));
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) {
          delete process.env[key];
        } else {
          process.env[key] = value;
        }
      }
    }
  });

  it("unsaves as a final pass, and rewinds even on a card that went private", async () => {
    const theirs = await insertOtherCard({ thought: "A card saved and then let go.", isPublic: true });
    expect((await save(theirs)).ok).toBe(true);
    const unsaved = await pass(theirs, [...LEGACY_STYLES], 2);
    expect(unsaved.ok && unsaved.decision.passes).toBe(2);
    expect((await listCards({ limit: 50, saved: true })).map((card) => card.id)).toEqual([]);

    await getDb().update(cards).set({ isPublic: false }).where(eq(cards.id, theirs));
    expect(await clearDecision(theirs)).toEqual({ ok: true });
    // A retried rewind is harmless.
    expect(await clearDecision(theirs)).toEqual({ ok: true });
    expect(await getDb().select().from(cardDecisions)).toHaveLength(0);
    expect(await clearDecision("00000000-0000-4000-8000-00000000dead")).toEqual({ ok: false });
  });

  it("shows save counts to the author and to nobody else", async () => {
    const mine = await createCard({ ...baseInput, isPublic: true });
    const theirs = await insertOtherCard({
      thought: "Someone else's public card whose numbers stay their own.",
      isPublic: true,
    });
    await strangerSaves(mine.id, OTHER_USER_ID, "stoic");
    await strangerSaves(mine.id, "00000000-0000-4000-8000-000000000097", "stoic");
    await strangerSaves(mine.id, "00000000-0000-4000-8000-000000000098", "witty");
    await strangerSaves(theirs, "00000000-0000-4000-8000-000000000097", "stoic");

    const own = await getCard(mine.id);
    expect(own?.saveCount).toBe(3);
    expect(own?.results.find((item) => item.style === "stoic")?.saveCount).toBe(2);
    expect(own?.results.find((item) => item.style === "witty")?.saveCount).toBe(1);
    // Absent, not zero: a 0 on a post about your worst day is worse than no number.
    expect(own?.results.find((item) => item.style === "hopeful")?.saveCount).toBeUndefined();

    const page = await listStack({ limit: 12, session: stackSession(), seen: [] }, true);
    const other = page.cards.find((card) => card.id === theirs);
    expect(other?.saveCount).toBeUndefined();
    expect(other?.results.every((item) => item.saveCount === undefined)).toBe(true);

    // A private card has no audience, so it reports no numbers.
    const hidden = await patchCard(mine.id, { isPublic: false });
    expect(hidden.ok && hidden.card.saveCount).toBeUndefined();
  });

  it("shows the answer in their language to the author and English to everyone else", async () => {
    const mine = await createCard({
      ...baseInput,
      thoughtOriginal: "Upropastio sam intervju i vrtim svaki drhtavi odgovor.",
      meta: { ...baseInput.meta, inputLanguage: "hr" },
      results: [
        { style: "stoic", reframe: "A stoic take on showing up.", reframeOriginal: "Stoički pogled na to da si se pojavio." },
        { style: "witty", reframe: "A witty take on showing up.", reframeOriginal: "A witty take on showing up." },
      ],
      isPublic: true,
    });
    expect(mine.results.find((item) => item.style === "stoic")?.reframeOriginal).toBe(
      "Stoički pogled na to da si se pojavio.",
    );
    // A second version that is just the English is not stored.
    expect(mine.results.find((item) => item.style === "witty")).not.toHaveProperty("reframeOriginal");

    const theirs = await insertOtherCard({ thought: "Someone else's card in their own language.", isPublic: true });
    await getDb()
      .update(cardReframes)
      .set({ reframeOriginal: "Tuđi odgovor na hrvatskom." })
      .where(eq(cardReframes.cardId, theirs));

    const page = await listStack({ limit: 12, session: stackSession(), seen: [] }, true);
    const other = page.cards.find((card) => card.id === theirs);
    expect(other?.results.length).toBeGreaterThan(0);
    expect(other?.results.every((item) => item.reframeOriginal === undefined)).toBe(true);
  });

  it("drops a saved card from the library once its author makes it private", async () => {
    const kept = await insertOtherCard({
      thought: "I keep checking my phone for a message that is not coming.",
      isPublic: true,
    });
    expect((await save(kept)).ok).toBe(true);
    expect((await listCards({ limit: 50, saved: true })).some((card) => card.id === kept)).toBe(true);

    await getDb().update(cards).set({ isPublic: false }).where(eq(cards.id, kept));
    expect((await listCards({ limit: 50 })).some((card) => card.id === kept)).toBe(false);
    expect((await listCards({ limit: 50, saved: true })).some((card) => card.id === kept)).toBe(false);

    await getDb().update(cards).set({ isPublic: true }).where(eq(cards.id, kept));
    expect((await listCards({ limit: 50, saved: true })).some((card) => card.id === kept)).toBe(true);
  });

  it("pages an author's posts on equal timestamps by id without a gap or duplicate", async () => {
    const createdAt = new Date("2026-09-11T12:00:00.000Z");
    const ids = await Promise.all(
      ["One shared instant.", "Two shared instant.", "Three shared instant."].map((thought) =>
        insertOtherCard({ thought, isPublic: true, createdAt }),
      ),
    );

    const first = await listPublicCardsForUser({ userId: OTHER_USER_ID, limit: 2 });
    expect(first).toHaveLength(2);
    const last = first[1];
    if (!last) {
      throw new Error("no second card");
    }
    const second = await listPublicCardsForUser({
      userId: OTHER_USER_ID,
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

  function stackSession(overrides: { seed?: string; startedAt?: Date } = {}) {
    return {
      seed: overrides.seed ?? "seed-integration",
      // A beat ahead, so a card inserted just now is inside the visit.
      startedAt: overrides.startedAt ?? new Date(Date.now() + 1_000),
    };
  }

  async function stackIds(
    options: { limit?: number; session?: ReturnType<typeof stackSession>; seen?: string[]; ranked?: boolean } = {},
  ): Promise<string[]> {
    const page = await listStack(
      { limit: options.limit ?? 24, session: options.session ?? stackSession(), seen: options.seen ?? [] },
      options.ranked ?? true,
    );
    return page.cards.map((card) => card.id);
  }

  describe("stack", () => {
    it("projects every card onto the styles the calling app can show", async () => {
      const cardId = await insertOtherCard({ thought: "A card written with the new voices.", isPublic: true });
      const styles: Style[] = ["tender", "values", "stoic", "witty"];
      await getDb().delete(cardReframes).where(eq(cardReframes.cardId, cardId));
      await getDb()
        .insert(cardReframes)
        .values(styles.map((style, position) => ({ cardId, style, reframe: `A ${style} take.`, position })));
      await getDb().update(cards).set({ spotlightStyle: "tender" }).where(eq(cards.id, cardId));

      const lists = async () => [
        ...(await listStack({ limit: 12, session: stackSession(), seen: [] }, true)).cards,
        ...(await listStack({ limit: 12, session: stackSession(), seen: [] }, false)).cards,
      ];
      const legacy = (await runWithStyleSet(LEGACY_STYLES, lists)).filter((card) => card.id === cardId);
      expect(legacy).toHaveLength(2);
      for (const card of legacy) {
        expect(card.results.map((item) => item.style)).toEqual(["stoic", "witty"]);
        expect(["stoic", "witty"]).toContain(card.spotlightStyle);
        expect(["stoic", "witty"]).toContain(card.openingStyle);
      }
      expect(JSON.stringify(legacy)).not.toMatch(/"(tender|values)"/);

      const extended = (await runWithStyleSet(STYLES, lists)).filter((card) => card.id === cardId);
      expect(extended).toHaveLength(2);
      for (const card of extended) {
        expect(card.results.map((item) => item.style)).toEqual(styles);
      }
    });

    it("never shows the viewer's own cards, private cards, or posts newer than the visit", async () => {
      const startedAt = new Date(Date.now() - 60_000);
      const old = await insertOtherCard({
        thought: "Posted before the visit began.",
        isPublic: true,
        createdAt: new Date(Date.now() - 120_000),
      });
      const late = await insertOtherCard({
        thought: "Posted after the visit began.",
        isPublic: true,
        createdAt: new Date(),
      });
      const priv = await insertOtherCard({
        thought: "A private thought that belongs to nobody's stack.",
        isPublic: false,
        createdAt: new Date(Date.now() - 120_000),
      });
      const own = await createCard({ ...baseInput, isPublic: true });
      await getDb()
        .update(cards)
        .set({ createdAt: new Date(Date.now() - 120_000) })
        .where(eq(cards.id, own.id));

      const ids = await stackIds({ session: stackSession({ startedAt }) });
      expect(ids).toEqual([old]);
      expect(ids).not.toContain(late);
      expect(ids).not.toContain(priv);
    });

    it("ranks a card strangers saved above an equally fresh one nobody did", async () => {
      const createdAt = new Date(Date.now() - 3_600_000);
      const plain = await insertOtherCard({
        thought: "Nobody has saved this one yet and it sits in the same hour.",
        isPublic: true,
        createdAt,
        authorId: "00000000-0000-4000-8000-0000000000c1",
      });
      const loved = await insertOtherCard({
        thought: "Three people found something they needed in this one.",
        isPublic: true,
        createdAt,
        authorId: "00000000-0000-4000-8000-0000000000c2",
      });
      for (const fan of [
        "00000000-0000-4000-8000-0000000000a1",
        "00000000-0000-4000-8000-0000000000a2",
        "00000000-0000-4000-8000-0000000000a3",
      ]) {
        await strangerSaves(loved, fan, "hopeful");
      }
      // A stranger's pass is not a signal against the card.
      await getDb().insert(cardDecisions).values({
        userId: "00000000-0000-4000-8000-0000000000a1",
        cardId: plain,
        kind: "pass",
        style: "stoic",
        checkedStyles: ["stoic"],
        passes: 1,
      });

      const ids = await stackIds();
      expect(ids.indexOf(loved)).toBeLessThan(ids.indexOf(plain));
      expect(ids).toContain(plain);
    });

    it("ranks the viewer's own subject above a subject they never write about", async () => {
      for (let index = 0; index < 5; index += 1) {
        await createCard({ ...baseInput, thought: `Work keeps making me feel small, note ${index}.` });
      }
      const createdAt = new Date(Date.now() - 7_200_000);
      const stranger = await insertOtherCard({
        thought: "A money worry this viewer has never once written about.",
        isPublic: true,
        category: "money",
        emotions: ["envy"],
        createdAt,
        authorId: "00000000-0000-4000-8000-0000000000c1",
      });
      const mirror = await insertOtherCard({
        thought: "Work leaves me ashamed and afraid I am falling behind.",
        isPublic: true,
        category: "work",
        emotions: ["shame", "fear"],
        createdAt,
        authorId: "00000000-0000-4000-8000-0000000000c2",
      });

      const ids = await stackIds();
      expect(ids.indexOf(mirror)).toBeLessThan(ids.indexOf(stranger));
    });

    it("learns the viewer's themes from the cards they saved, not only what they wrote", async () => {
      const createdAt = new Date(Date.now() - 86_400_000 * 3);
      for (let index = 0; index < 3; index += 1) {
        const kept = await insertOtherCard({
          thought: `A grief thought the viewer keeps ${index}.`,
          isPublic: true,
          category: "grief_loss",
          emotions: [],
          createdAt,
        });
        expect((await save(kept)).ok).toBe(true);
      }

      const fresh = new Date(Date.now() - 3_600_000);
      const money = await insertOtherCard({
        thought: "A money worry from a subject they have never kept.",
        isPublic: true,
        category: "money",
        emotions: [],
        createdAt: fresh,
        authorId: "00000000-0000-4000-8000-0000000000c1",
      });
      const grief = await insertOtherCard({
        thought: "A new grief thought in the subject they keep saving.",
        isPublic: true,
        category: "grief_loss",
        emotions: [],
        createdAt: fresh,
        authorId: "00000000-0000-4000-8000-0000000000c2",
      });

      const ids = await stackIds();
      expect(ids.indexOf(grief)).toBeLessThan(ids.indexOf(money));
    });

    it("hands out every card exactly once across pages, however many get decided in between", async () => {
      const ids = new Set<string>();
      for (let index = 0; index < 7; index += 1) {
        ids.add(
          await insertOtherCard({
            thought: `A public thought number ${index} for the stack pager.`,
            isPublic: true,
            category: CATEGORIES[index % (CATEGORIES.length - 1)] ?? "work",
            createdAt: new Date(Date.now() - index * 60_000),
            authorId: `00000000-0000-4000-8000-0000000001${String(index).padStart(2, "0")}`,
          }),
        );
      }

      const session = stackSession({ seed: "seed-pager" });
      const whole = await stackIds({ limit: 50, session });
      const first = await listStack({ limit: 3, session, seen: [] }, true);
      expect(first.exhausted).toBe(false);
      expect(first.cards.map((card) => card.id)).toEqual(whole.slice(0, 3));

      // The phone saves one, passes one, and still holds the third when it asks for more.
      const [a, b] = first.cards;
      expect((await save(a?.id ?? "")).ok).toBe(true);
      expect((await pass(b?.id ?? "")).ok).toBe(true);
      const seen = first.cards.map((card) => card.id);
      const second = await listStack({ limit: 3, session, seen }, true);
      seen.push(...second.cards.map((card) => card.id));
      const third = await listStack({ limit: 3, session, seen }, true);
      expect(third.exhausted).toBe(true);
      seen.push(...third.cards.map((card) => card.id));

      expect(seen).toHaveLength(7);
      expect(new Set(seen)).toEqual(ids);
      // A replayed request is the same page.
      const replay = await listStack({ limit: 3, session, seen: first.cards.map((card) => card.id) }, true);
      expect(replay.cards.map((card) => card.id)).toEqual(second.cards.map((card) => card.id));
    });

    it("keeps one seed stable and gives another a different order", async () => {
      const createdAt = new Date("2026-06-01T12:00:00.000Z");
      for (let index = 0; index < 12; index += 1) {
        await insertOtherCard({
          thought: `Another public thought ${index} to shuffle between visits.`,
          isPublic: true,
          createdAt,
          authorId: `00000000-0000-4000-8000-0000000002${String(index).padStart(2, "0")}`,
        });
      }

      const startedAt = new Date("2026-06-15T18:00:00.000Z");
      const one = await stackIds({ limit: 12, session: { seed: "seed-one", startedAt } });
      const again = await stackIds({ limit: 12, session: { seed: "seed-one", startedAt } });
      const other = await stackIds({ limit: 12, session: { seed: "seed-two", startedAt } });
      expect(again).toEqual(one);
      expect(other).not.toEqual(one);
    });

    it("brings a passed card back once, after twelve hours, on an angle not yet seen", async () => {
      const passedOnce = await insertOtherCard({ thought: "Passed on Witty only.", isPublic: true });
      const recent = await insertOtherCard({ thought: "Passed an hour ago.", isPublic: true });
      const twice = await insertOtherCard({ thought: "Passed twice.", isPublic: true });
      const everyAngle = await insertOtherCard({ thought: "Passed after reading every angle.", isPublic: true });
      const saved = await insertOtherCard({ thought: "Saved, so it stays in Profile.", isPublic: true });
      const unsaved = await insertOtherCard({ thought: "Saved and then unsaved.", isPublic: true });

      expect((await pass(passedOnce, ["witty"])).ok).toBe(true);
      expect((await pass(recent, ["witty"])).ok).toBe(true);
      expect((await pass(twice, ["witty"], 2)).ok).toBe(true);
      expect((await pass(everyAngle, [...LEGACY_STYLES])).ok).toBe(true);
      expect((await save(saved)).ok).toBe(true);
      expect((await pass(unsaved, [...LEGACY_STYLES], 2)).ok).toBe(true);
      const longAgo = new Date(Date.now() - 13 * 3_600_000);
      await getDb()
        .update(cardDecisions)
        .set({ decidedAt: longAgo })
        .where(sql`${cardDecisions.cardId} <> ${recent}`);
      await getDb()
        .update(cardDecisions)
        .set({ decidedAt: new Date(Date.now() - 3_600_000) })
        .where(eq(cardDecisions.cardId, recent));

      const page = await listStack({ limit: 24, session: stackSession(), seen: [] }, true);
      expect(page.cards.map((card) => card.id)).toEqual([passedOnce]);
      const back = page.cards[0];
      // The first angle in the cook's order the viewer never saw.
      expect(back?.openingStyle).toBe("stoic");
      expect(back?.decision).toMatchObject({ kind: "pass", passes: 1, checkedStyles: ["witty"] });
    });

    it("never puts two heavy cards side by side when lighter ones are left", async () => {
      for (let index = 0; index < 10; index += 1) {
        await insertOtherCard({
          thought: `A ${index < 5 ? "heavy" : "light"} thought number ${index}.`,
          isPublic: true,
          // The heavy ones are the newest, so plain rank order would stack them.
          createdAt: new Date(Date.now() - index * 60_000),
          category: (["work", "money", "family", "health", "future"] as const)[index % 5],
          intensity: index < 5 ? 5 : 2,
          authorId: `00000000-0000-4000-8000-0000000003${String(index).padStart(2, "0")}`,
        });
      }
      const page = await listStack({ limit: 10, session: stackSession(), seen: [] }, true);
      expect(page.cards).toHaveLength(10);
      for (let index = 1; index < page.cards.length; index += 1) {
        const pair = [page.cards[index - 1], page.cards[index]];
        expect(pair.every((card) => (card?.intensity ?? 0) >= 4)).toBe(false);
      }
    });

    it("puts the house cards after every community card, then ends", async () => {
      const house = await insertOtherCard({
        thought: "A curated house thought, newest of all.",
        isPublic: true,
        authorId: HOUSE_USER_ID,
      });
      const community: string[] = [];
      for (let index = 0; index < 3; index += 1) {
        community.push(
          await insertOtherCard({
            thought: `A community thought ${index}.`,
            isPublic: true,
            createdAt: new Date(Date.now() - (index + 1) * 86_400_000),
            authorId: `00000000-0000-4000-8000-0000000004${String(index).padStart(2, "0")}`,
          }),
        );
      }

      for (const ranked of [true, false]) {
        const session = stackSession();
        const first = await listStack({ limit: 3, session, seen: [] }, ranked);
        expect(new Set(first.cards.map((card) => card.id))).toEqual(new Set(community));
        expect(first.exhausted).toBe(false);
        const second = await listStack({ limit: 3, session, seen: first.cards.map((card) => card.id) }, ranked);
        expect(second.cards.map((card) => card.id)).toEqual([house]);
        expect(second.exhausted).toBe(true);
        expect(second.cards[0]?.isHouse).toBe(true);
        expect(second.cards[0]?.author.following).toBe(false);
      }

      // No one to follow behind a house card.
      expect(await followUser(HOUSE_USER_ID)).toEqual({ result: "not_found", notificationId: null });
      // It can still be saved and passed like any other card.
      expect((await save(house)).ok).toBe(true);
    });

    it("is newest first with ranking off", async () => {
      const older = await insertOtherCard({
        thought: "Older, but saved by people.",
        isPublic: true,
        createdAt: new Date(Date.now() - 86_400_000),
      });
      const newer = await insertOtherCard({ thought: "Newer and unsaved.", isPublic: true });
      await strangerSaves(older, "00000000-0000-4000-8000-0000000000a1");
      expect(await stackIds({ ranked: false })).toEqual([newer, older]);
    });

    it("honours blocks and reports", async () => {
      const work = await insertOtherCard({ thought: "A work thought.", isPublic: true });
      const other = await insertOtherCard({ thought: "Another thought.", isPublic: true });

      await reportCard(work, "other");
      expect(await stackIds()).toEqual([other]);

      expect(await blockUser(OTHER_USER_ID)).toBe("ok");
      expect(await stackIds()).toEqual([]);
      await unblockUser(OTHER_USER_ID);
    });

    it("opens other people's cards on the angle the viewer keeps saving", async () => {
      for (let index = 0; index < 30; index += 1) {
        await insertOtherCard({
          thought: `A public thought ${index} whose cover the viewer may never have chosen.`,
          isPublic: true,
          createdAt: new Date(Date.now() - index * 60_000),
        });
      }
      const before = await listStack({ limit: 50, session: stackSession(), seen: [] }, true);
      // Every fixture card covers "witty", so a lean has to be visible to be real.
      expect(before.cards.every((card) => card.openingStyle === "witty")).toBe(true);

      const target = before.cards[0]?.id;
      if (!target) {
        throw new Error("no fixture card");
      }
      expect((await save(target, "tough")).ok).toBe(true);

      const after = await listStack({ limit: 50, session: stackSession(), seen: [] }, true);
      const leaning = after.cards.filter((card) => card.openingStyle === "tough");
      expect(leaning.length).toBeGreaterThan(0);
      // A lean, not a takeover: the mix of voices is the point.
      expect(leaning.length).toBeLessThan(after.cards.length);
    });

    it("keeps its order when the viewer follows someone mid-visit", async () => {
      const second = "00000000-0000-4000-8000-0000000000b2";
      for (let index = 0; index < 12; index += 1) {
        await insertOtherCard({
          thought: `A post ${index} for the mid-visit follow test.`,
          isPublic: true,
          category: CATEGORIES[index % (CATEGORIES.length - 1)] ?? "work",
          createdAt: new Date(Date.now() - (index + 1) * 3_600_000),
          authorId: index % 2 === 0 ? OTHER_USER_ID : second,
        });
      }
      const session = stackSession({ seed: "seed-follow-mid", startedAt: new Date(Date.now() - 1_000) });
      const before = await stackIds({ limit: 12, session });
      expect(await followUser(second)).toMatchObject({ result: "ok" });
      expect(await stackIds({ limit: 12, session })).toEqual(before);
      expect(await unfollowUser(second)).toBe("ok");
    });
  });

  it("follows and unfollows another user", async () => {
    expect(await followUser(DEV_USER_ID)).toEqual({ result: "self", notificationId: null });
    expect(await followUser("00000000-0000-4000-8000-000000000066")).toEqual({
      result: "not_found",
      notificationId: null,
    });

    const cardId = await insertOtherCard({
      thought: "I keep waiting for a reply that is not coming and I feel small.",
      isPublic: true,
    });
    expect(await followUser(OTHER_USER_ID)).toMatchObject({ result: "ok" });
    expect(await followUser(OTHER_USER_ID)).toEqual({ result: "ok", notificationId: null });

    const followed = await listStack({ limit: 12, session: stackSession(), seen: [] }, false);
    expect(followed.cards.find((card) => card.id === cardId)?.author.following).toBe(true);

    expect(await unfollowUser(OTHER_USER_ID)).toBe("ok");
    expect(await unfollowUser(OTHER_USER_ID)).toBe("ok");
    const cleared = await listStack({ limit: 12, session: stackSession(), seen: [] }, false);
    expect(cleared.cards.find((card) => card.id === cardId)?.author.following).toBe(false);
  });

  it("enforces mutual isolation and clears cross-user follows and decisions on block", async () => {
    const otherCard = await insertOtherCard({
      thought: "This public card should disappear after either side blocks.",
      isPublic: true,
    });
    const ownerCard = await createCard({ ...baseInput, isPublic: true });

    await getDb().insert(follows).values([
      { followerId: DEV_USER_ID, followeeId: OTHER_USER_ID },
      { followerId: OTHER_USER_ID, followeeId: DEV_USER_ID },
    ]);
    await getDb().insert(cardDecisions).values([
      { userId: DEV_USER_ID, cardId: otherCard, kind: "save", style: "stoic", checkedStyles: ["stoic"], passes: 0 },
      { userId: OTHER_USER_ID, cardId: ownerCard.id, kind: "pass", style: "stoic", checkedStyles: ["stoic"], passes: 1 },
    ]);

    expect(await blockUser(OTHER_USER_ID)).toBe("ok");
    expect(await blockUser(OTHER_USER_ID)).toBe("ok");
    expect(await getDb().select().from(follows)).toHaveLength(0);
    expect(await getDb().select().from(cardDecisions)).toHaveLength(0);
    expect(await stackIds()).not.toContain(otherCard);
    expect(await followUser(OTHER_USER_ID)).toEqual({ result: "blocked", notificationId: null });
    expect(await save(otherCard)).toEqual({ ok: false, reason: "not_found" });
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
    expect(await getDb().select().from(followNotifications)).toHaveLength(0);
    expect(await getDb().select().from(userBlocks)).toHaveLength(1);

    expect(await unblockUser(OTHER_USER_ID)).toBe("ok");
    await Promise.all([save(otherCard), blockUser(OTHER_USER_ID)]);
    expect(await getDb().select().from(cardDecisions)).toHaveLength(0);
    expect(await getDb().select().from(userBlocks)).toHaveLength(1);
  });

  it("notifies on a new follow, stacks nothing unread, and drops both directions on block", async () => {
    await getDb()
      .insert(users)
      .values({
        id: OTHER_USER_ID,
        initials: "AL",
        name: "Private Name",
        email: `seed-${OTHER_USER_ID}@angles.invalid`,
      })
      .onConflictDoUpdate({
        target: users.id,
        set: { name: "Private Name", initials: "AL" },
      });

    expect(await followUser(DEV_USER_ID)).toEqual({ result: "self", notificationId: null });
    expect(await getDb().select().from(followNotifications)).toHaveLength(0);

    const first = await runAsOwner(OTHER_USER_ID, () => followUser(DEV_USER_ID));
    expect(first.result).toBe("ok");
    expect(first.notificationId).toEqual(expect.any(String));
    const repeat = await runAsOwner(OTHER_USER_ID, () => followUser(DEV_USER_ID));
    expect(repeat).toEqual({ result: "ok", notificationId: null });
    expect(await getDb().select().from(followNotifications)).toHaveLength(1);

    await runAsOwner(OTHER_USER_ID, () => unfollowUser(DEV_USER_ID));
    const unreadAgain = await runAsOwner(OTHER_USER_ID, () => followUser(DEV_USER_ID));
    expect(unreadAgain.notificationId).toBeNull();
    expect(await getDb().select().from(followNotifications)).toHaveLength(1);

    const listed = await listFollowNotifications();
    expect(listed.unreadCount).toBe(1);
    expect(listed.notifications).toHaveLength(1);
    expect(listed.notifications[0]).toMatchObject({
      followedBack: false,
      readAt: null,
      actor: { id: OTHER_USER_ID, initials: "AL", following: false },
    });
    expect(listed.notifications[0]?.actor).not.toHaveProperty("name");

    // Postgres keeps microseconds; the wire stamp has milliseconds, and build 18 can lose one more.
    await getDb()
      .update(followNotifications)
      .set({ createdAt: sql`'2026-10-06 08:40:24.130267+00'::timestamptz` })
      .where(eq(followNotifications.recipientId, DEV_USER_ID));
    const stamped = await listFollowNotifications();
    expect(stamped.notifications[0]?.createdAt).toBe("2026-10-06T08:40:24.130Z");
    expect(await markFollowNotificationsRead({ before: new Date("2026-10-06T08:40:24.128Z") })).toBe(1);
    expect(await markFollowNotificationsRead({ before: new Date("2026-10-06T08:40:24.129Z") })).toBe(0);
    expect((await listFollowNotifications()).notifications[0]?.readAt).toEqual(expect.any(String));

    await runAsOwner(OTHER_USER_ID, () => unfollowUser(DEV_USER_ID));
    await followUser(OTHER_USER_ID);
    const followedBack = await runAsOwner(OTHER_USER_ID, () => followUser(DEV_USER_ID));
    expect(followedBack.notificationId).toEqual(expect.any(String));
    const rows = await getDb()
      .select()
      .from(followNotifications)
      .where(eq(followNotifications.recipientId, DEV_USER_ID));
    expect(rows).toHaveLength(2);
    expect(rows.some((row) => row.followedBack)).toBe(true);
    const perPerson = await listFollowNotifications();
    expect(perPerson.notifications).toHaveLength(1);
    expect(perPerson.notifications[0]).toMatchObject({
      id: followedBack.notificationId,
      followedBack: true,
      readAt: null,
    });
    expect(perPerson.unreadCount).toBe(1);

    const previous = {
      APNS_KEY: process.env.APNS_KEY,
      APNS_KEY_ID: process.env.APNS_KEY_ID,
      APNS_TEAM_ID: process.env.APNS_TEAM_ID,
      APNS_BUNDLE_ID: process.env.APNS_BUNDLE_ID,
    };
    const sent: { title: string; body: string; collapseId: string }[] = [];
    const notificationId = followedBack.notificationId as string;
    const record = async (alert: { title: string; body: string; collapseId: string }) => {
      sent.push({ title: alert.title, body: alert.body, collapseId: alert.collapseId });
      return "sent" as const;
    };
    try {
      await registerDeviceToken("ab".repeat(32), "sandbox");
      delete process.env.APNS_KEY;
      delete process.env.APNS_KEY_ID;
      delete process.env.APNS_TEAM_ID;
      delete process.env.APNS_BUNDLE_ID;
      await deliverFollowPush(notificationId, record);
      expect(sent).toHaveLength(0);

      process.env.APNS_KEY = "test-key";
      process.env.APNS_KEY_ID = "KEYID12345";
      process.env.APNS_TEAM_ID = "TEAMID1234";
      process.env.APNS_BUNDLE_ID = "app.angles.ios";
      await setNotificationPreferences({ notifyFollows: false });
      await deliverFollowPush(notificationId, record);
      expect(sent).toHaveLength(0);

      await setNotificationPreferences({ notifyFollows: true });
      await getDb().delete(deviceTokens);
      await deliverFollowPush(notificationId, record);
      expect(sent).toHaveLength(0);

      await registerDeviceToken("ab".repeat(32), "sandbox");
      await registerDeviceToken("cd".repeat(32), "sandbox");
      const liveTokens = await getDb().select().from(deviceTokens);
      expect(liveTokens).toHaveLength(1);
      expect(liveTokens[0]?.token).toBe("cd".repeat(32));

      await deliverFollowPush(notificationId, async (alert) => {
        sent.push({ title: alert.title, body: alert.body, collapseId: alert.collapseId });
        return "unregistered";
      });
      expect(sent).toEqual([
        {
          title: "Private Name",
          body: "Followed you back",
          collapseId: notificationId,
        },
      ]);
      expect(await getDb().select().from(deviceTokens)).toHaveLength(0);
    } finally {
      await setNotificationPreferences({ notifyFollows: true });
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) {
          delete process.env[key];
        } else {
          process.env[key] = value;
        }
      }
    }

    expect((await listFollowNotifications()).unreadCount).toBe(1);
    expect(
      await markFollowNotificationsRead({ throughId: "00000000-0000-4000-8000-0000000000ff" }),
    ).toBe(1);
    const otherUnread = (await runAsOwner(OTHER_USER_ID, () => listFollowNotifications())).unreadCount;
    expect(
      await runAsOwner(OTHER_USER_ID, () => markFollowNotificationsRead({ throughId: notificationId })),
    ).toBe(otherUnread);
    expect((await listFollowNotifications()).unreadCount).toBe(1);
    expect(await markFollowNotificationsRead({ throughId: notificationId })).toBe(0);
    expect((await listFollowNotifications()).notifications.every((row) => row.readAt !== null)).toBe(true);

    await runAsOwner(OTHER_USER_ID, () => blockUser(DEV_USER_ID));
    expect(await getDb().select().from(followNotifications)).toHaveLength(0);
    expect(await getDb().select().from(follows)).toHaveLength(0);
  });

  it("keeps one HTTP report public, auto-privates at three, and Keep unlocks without republishing", async () => {
    const owned = await createCard({ ...baseInput, isPublic: true });
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
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled"));
    try {
      for (const [index, reporterId] of reporterIds.entries()) {
        const response = await safetyApp.request(`/cards/${owned.id}/report`, {
          method: "POST",
          headers: {
            Authorization: `Bearer test:${reporterId}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ reason: "harassment" }),
        });
        expect(response.status).toBe(200);
        const row = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
        expect(row?.isPublic).toBe(index < 2);
        if (index === 0) {
          expect(await cardPublicationLocked(owned.id)).toBe(false);
        }
      }
      expect(fetchSpy).not.toHaveBeenCalled();
    } finally {
      fetchSpy.mockRestore();
    }

    const autoPrivate = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
    expect(autoPrivate?.isPublic).toBe(false);
    expect(autoPrivate?.moderationHiddenAt).toBeNull();
    expect((await getCard(owned.id))?.moderationHidden).toBeUndefined();
    expect(await cardPublicationLocked(owned.id)).toBe(true);
    expect(await getDb().select().from(cardReports)).toHaveLength(3);

    expect(await resolveCardReports(owned.id, "kept")).toBe("ok");
    expect((await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) }))?.isPublic).toBe(
      false,
    );
    expect(await cardPublicationLocked(owned.id)).toBe(false);
    expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({ ok: true });
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

  it("keeps the first Terms acceptance", async () => {
    await getDb().update(users).set({ termsAcceptedAt: null }).where(eq(users.id, DEV_USER_ID));
    const first = await acceptOwnerTerms(new Date("2026-10-02T10:00:00.000Z"));
    const again = await acceptOwnerTerms(new Date("2026-10-03T10:00:00.000Z"));
    expect(first.toISOString()).toBe("2026-10-02T10:00:00.000Z");
    expect(again.toISOString()).toBe("2026-10-02T10:00:00.000Z");
  });

  describe("operator review", () => {
    const reviewerIds = [
      "00000000-0000-4000-8000-000000000077",
      "00000000-0000-4000-8000-000000000088",
      "00000000-0000-4000-8000-0000000000c1",
    ];

    async function reportFromAll(cardId: string): Promise<void> {
      await getDb()
        .insert(users)
        .values(
          reviewerIds.map((id) => ({
            id,
            initials: "RP",
            name: "Reporter",
            email: `seed-${id}@angles.invalid`,
          })),
        )
        .onConflictDoNothing();
      await getDb().insert(cardReports).values(
        reviewerIds.map((reporterId) => ({ reporterId, cardId, reason: "spam" as const })),
      );
    }

    it("lists open reports with the card and its reasons", async () => {
      const reported = await insertOtherCard({ thought: "A card under review.", isPublic: true });
      expect(await reportCard(reported, "harassment")).toMatchObject({ ok: true, created: true });

      const [pending] = await listPendingReports();
      expect(pending).toMatchObject({
        cardId: reported,
        reportCount: 1,
        reasons: { harassment: 1 },
        thought: "A card under review.",
        isPublic: true,
        authorSuspended: false,
      });
      expect(pending?.reframes.length).toBeGreaterThan(0);
    });

    it("keep dismisses reports so they stop locking the card", async () => {
      const owned = await createCard({ ...baseInput, isPublic: false });
      await reportFromAll(owned.id);
      expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({ ok: false });

      expect(await resolveCardReports(owned.id, "kept")).toBe("ok");
      expect(await listPendingReports()).toEqual([]);
      expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({ ok: true });
    });

    it("hide stamps the card, upholds reports, blocks the author, and removes it from the stack", async () => {
      const owned = await createCard({ ...baseInput, isPublic: true });
      await reportFromAll(owned.id);

      expect(await resolveCardReports(owned.id, "hidden")).toBe("ok");
      const row = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
      expect(row?.isPublic).toBe(false);
      expect(row?.moderationHiddenAt).toBeInstanceOf(Date);
      const reports = await getDb().select().from(cardReports);
      expect(reports).toHaveLength(3);
      expect(reports.every((report) => report.resolution === "hidden")).toBe(true);
      expect(reports.every((report) => report.reviewedAt instanceof Date)).toBe(true);
      const hidden = await getCard(owned.id);
      expect(hidden?.moderationHidden).toBe(true);
      const publish = await safetyApp.request(`/cards/${owned.id}`, {
        method: "PATCH",
        headers: {
          Authorization: `Bearer test:${DEV_USER_ID}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ isPublic: true }),
      });
      expect(publish.status).toBe(400);
      await expect(publish.json()).resolves.toMatchObject({ code: "PUBLIC_CONTENT_NOT_ALLOWED" });
      const strangerFeed = await safetyApp.request("/stack?limit=50", {
        headers: { Authorization: `Bearer test:${OTHER_USER_ID}` },
      });
      expect(strangerFeed.status).toBe(200);
      const feedBody = (await strangerFeed.json()) as { cards: { id: string }[] };
      expect(feedBody.cards.map((card) => card.id)).not.toContain(owned.id);
    });

    async function feedIdsFor(viewerId: string): Promise<string[]> {
      const response = await safetyApp.request("/stack?limit=50", {
        headers: { Authorization: `Bearer test:${viewerId}` },
      });
      expect(response.status).toBe(200);
      const body = (await response.json()) as { cards: { id: string }[] };
      return body.cards.map((card) => card.id);
    }

    it("operator publish from three open reports reviews them as kept and unlocks the author", async () => {
      const owned = await createCard({ ...baseInput, isPublic: true });
      await getDb()
        .insert(users)
        .values(
          reviewerIds.map((id) => ({
            id,
            initials: "RP",
            name: "Reporter",
            email: `seed-${id}@angles.invalid`,
          })),
        )
        .onConflictDoNothing();
      const fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network disabled"));
      try {
        for (const reporterId of reviewerIds) {
          const response = await safetyApp.request(`/cards/${owned.id}/report`, {
            method: "POST",
            headers: {
              Authorization: `Bearer test:${reporterId}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ reason: "spam" }),
          });
          expect(response.status).toBe(200);
        }

        const autoPrivate = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
        expect(autoPrivate?.isPublic).toBe(false);
        expect(autoPrivate?.moderationHiddenAt).toBeNull();
        expect((await getCard(owned.id))?.moderationHidden).toBeUndefined();
        expect(await cardPublicationLocked(owned.id)).toBe(true);

        const reviewedAt = new Date("2026-10-05T17:00:00.000Z");
        expect(await publishHiddenCard(owned.id, reviewedAt)).toBe("ok");
        const row = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
        expect(row?.isPublic).toBe(true);
        expect(row?.moderationHiddenAt).toBeNull();
        const reports = await getDb().select().from(cardReports).where(eq(cardReports.cardId, owned.id));
        expect(reports).toHaveLength(3);
        expect(reports.every((report) => report.resolution === "kept")).toBe(true);
        expect(reports.every((report) => report.reviewedAt?.getTime() === reviewedAt.getTime())).toBe(true);
        expect(await listPendingReports()).toEqual([]);
        expect(await cardPublicationLocked(owned.id)).toBe(false);

        for (const reporterId of reviewerIds) {
          expect(await feedIdsFor(reporterId)).not.toContain(owned.id);
        }
        expect(await feedIdsFor(OTHER_USER_ID)).toContain(owned.id);

        expect(await patchCard(owned.id, { isPublic: false })).toMatchObject({ ok: true });
        expect(await cardPublicationLocked(owned.id)).toBe(false);
        expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({
          ok: true,
          card: { isPublic: true },
        });
        expect(fetchSpy).not.toHaveBeenCalled();
      } finally {
        fetchSpy.mockRestore();
      }
    });

    it("operator hide then publish unlocks the author and keeps the hidden history", async () => {
      const owned = await createCard({ ...baseInput, isPublic: true });
      await reportFromAll(owned.id);
      expect(await resolveCardReports(owned.id, "hidden")).toBe("ok");
      expect(await cardPublicationLocked(owned.id)).toBe(true);

      expect(await publishHiddenCard(owned.id)).toBe("ok");
      const restored = await getCard(owned.id);
      expect(restored?.isPublic).toBe(true);
      expect(restored?.moderationHidden).toBeUndefined();
      const reports = await getDb().select().from(cardReports);
      expect(reports).toHaveLength(3);
      expect(reports.every((report) => report.resolution === "hidden")).toBe(true);
      expect(await cardPublicationLocked(owned.id)).toBe(false);

      for (const reporterId of reviewerIds) {
        expect(await feedIdsFor(reporterId)).not.toContain(owned.id);
      }
      expect(await feedIdsFor(OTHER_USER_ID)).toContain(owned.id);

      expect(await patchCard(owned.id, { isPublic: false })).toMatchObject({ ok: true });
      expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({ ok: true });
    });

    it("operator publish reaches a suspended author's card, but the author stays blocked", async () => {
      const owned = await createCard({ ...baseInput, isPublic: true });
      await reportFromAll(owned.id);
      expect(await resolveCardReports(owned.id, "hidden")).toBe("ok");
      expect(await suspendPublishing(DEV_USER_ID)).toBe("ok");
      expect(await publishHiddenCard(owned.id)).toBe("ok");
      const restored = await getCard(owned.id);
      expect(restored?.isPublic).toBe(true);
      expect(restored?.moderationHidden).toBeUndefined();
      expect(await getDb().select().from(cardReports)).toHaveLength(3);
      expect(await feedIdsFor(OTHER_USER_ID)).toContain(owned.id);

      expect(await patchCard(owned.id, { isPublic: false })).toMatchObject({ ok: true });
      expect(await patchCard(owned.id, { isPublic: true })).toEqual({
        ok: false,
        reason: "publication_blocked",
      });
      expect(await restorePublishing(DEV_USER_ID)).toBe("ok");
      expect(await patchCard(owned.id, { isPublic: true })).toMatchObject({ ok: true });
    });

    it("backfills the latest legacy hidden review and keeps the card locked", async () => {
      const owned = await createCard({ ...baseInput, isPublic: false });
      await reportFromAll(owned.id);
      const reviewed = [
        new Date("2026-09-01T10:00:00.000Z"),
        new Date("2026-09-03T10:00:00.000Z"),
        new Date("2026-09-02T10:00:00.000Z"),
      ];
      for (const [index, reporterId] of reviewerIds.entries()) {
        await getDb()
          .update(cardReports)
          .set({ resolution: "hidden", reviewedAt: reviewed[index] })
          .where(
            and(eq(cardReports.cardId, owned.id), eq(cardReports.reporterId, reporterId)),
          );
      }
      await getDb()
        .update(cards)
        .set({ moderationHiddenAt: null })
        .where(eq(cards.id, owned.id));

      const migration = readFileSync(
        resolve(process.cwd(), "drizzle/0021_moderation_hidden.sql"),
        "utf8",
      );
      const backfill = migration.split("--> statement-breakpoint")[1]?.trim();
      expect(backfill).toBeTruthy();
      await getSql().unsafe(backfill as string);

      const row = await getDb().query.cards.findFirst({ where: eq(cards.id, owned.id) });
      expect(row?.moderationHiddenAt?.toISOString()).toBe("2026-09-03T10:00:00.000Z");
      expect((await getCard(owned.id))?.moderationHidden).toBe(true);
      expect(await patchCard(owned.id, { isPublic: true })).toEqual({
        ok: false,
        reason: "publication_blocked",
      });
    });

    it("suspend makes every card private and blocks publishing until restored", async () => {
      const first = await createCard({ ...baseInput, isPublic: true });
      const second = await createCard({ ...baseInput, thought: "Another public one.", isPublic: true });

      expect(await suspendPublishing(DEV_USER_ID)).toBe("ok");
      const rows = await getDb().query.cards.findMany({ where: eq(cards.userId, DEV_USER_ID) });
      expect(rows.every((row) => !row.isPublic)).toBe(true);
      expect(rows.every((row) => row.moderationHiddenAt === null)).toBe(true);
      expect(await patchCard(first.id, { isPublic: true })).toEqual({
        ok: false,
        reason: "publication_blocked",
      });

      expect(await restorePublishing(DEV_USER_ID)).toBe("ok");
      expect(
        (await getDb().query.cards.findFirst({ where: eq(cards.id, second.id) }))?.isPublic,
      ).toBe(false);
      expect(await patchCard(second.id, { isPublic: true })).toMatchObject({ ok: true });
    });

    it("delete removes the card and its reports", async () => {
      const reported = await insertOtherCard({ thought: "Delete me.", isPublic: true });
      await reportCard(reported, "spam");
      expect(await deleteReportedCard(reported)).toBe(true);
      expect(await getDb().select().from(cardReports)).toHaveLength(0);
      expect(await deleteReportedCard(reported)).toBe(false);
    });
  });
});
