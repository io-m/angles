import { and, eq, lt, or, sql } from "drizzle-orm";
import type {
  SubscriptionProductId,
  VerifiedAppStoreNotification,
  VerifiedAppStoreRenewal,
  VerifiedAppStoreTransaction,
} from "../lib/appStoreVerifier.js";
import type { SubscriptionBody } from "../types/index.js";
import { getDb, wrapDbError } from "./client.js";
import { subscriptionEntitlements, subscriptionEvents, users } from "./schema.js";

export const ENTITLED_STATUSES = ["active", "grace", "billing_retry"] as const;
export type SubscriptionStatus =
  | (typeof ENTITLED_STATUSES)[number]
  | "expired"
  | "revoked";

type EntitlementRow = typeof subscriptionEntitlements.$inferSelect;

export class SubscriptionOwnershipError extends Error {
  constructor() {
    super("This App Store subscription belongs to another Angles account");
    this.name = "SubscriptionOwnershipError";
  }
}
function isEntitled(row: EntitlementRow, now: Date): boolean {
  if (
    row.revokedAt !== null ||
    !ENTITLED_STATUSES.includes(row.status as (typeof ENTITLED_STATUSES)[number])
  ) {
    return false;
  }
  if (row.status === "active") {
    return row.paidThrough > now;
  }
  if (row.status === "grace") {
    return row.gracePeriodExpiresAt !== null && row.gracePeriodExpiresAt > now;
  }
  return row.status === "billing_retry";
}

export function subscriptionBody(
  row: EntitlementRow | undefined,
  now: Date = new Date(),
): SubscriptionBody {
  if (!row) {
    return {
      isEntitled: false,
      status: null,
      productId: null,
      environment: null,
      paidThrough: null,
      revokedAt: null,
      quotaAnchor: null,
      updatedAt: null,
    };
  }
  return {
    isEntitled: isEntitled(row, now),
    status: row.status,
    productId: row.productId as SubscriptionProductId,
    environment: row.environment,
    paidThrough: row.paidThrough.toISOString(),
    revokedAt: row.revokedAt?.toISOString() ?? null,
    quotaAnchor: row.quotaAnchor.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
  };
}

function latestTransactionDate(transaction: VerifiedAppStoreTransaction): Date {
  return new Date(
    Math.max(
      transaction.signedDate.getTime(),
      transaction.purchaseDate.getTime(),
      transaction.revocationDate?.getTime() ?? 0,
    ),
  );
}

function transactionStatus(
  transaction: VerifiedAppStoreTransaction,
  now: Date,
): SubscriptionStatus {
  if (transaction.revocationDate || transaction.isUpgraded) {
    return "revoked";
  }
  if (transaction.expiresDate <= now) {
    return "expired";
  }
  return "active";
}

function notificationStatus(
  notificationType: string,
  subtype: string | undefined,
  transaction: VerifiedAppStoreTransaction,
  renewal: VerifiedAppStoreRenewal,
  now: Date,
): SubscriptionStatus {
  const renewalAwareStatus = (): SubscriptionStatus => {
    const transactionState = transactionStatus(transaction, now);
    if (transactionState !== "expired") {
      return transactionState;
    }
    if (renewal.gracePeriodExpiresDate && renewal.gracePeriodExpiresDate > now) {
      return "grace";
    }
    return renewal.isInBillingRetryPeriod ? "billing_retry" : "expired";
  };

  switch (notificationType) {
    case "REFUND":
    case "REVOKE":
      return "revoked";
    case "EXPIRED":
      return "expired";
    case "GRACE_PERIOD_EXPIRED":
      return renewal.isInBillingRetryPeriod ? "billing_retry" : "expired";
    case "DID_FAIL_TO_RENEW":
      if (
        subtype === "GRACE_PERIOD" &&
        renewal.gracePeriodExpiresDate &&
        renewal.gracePeriodExpiresDate > now
      ) {
        return "grace";
      }
      return renewal.isInBillingRetryPeriod ? "billing_retry" : "expired";
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "REFUND_REVERSED":
      return renewalAwareStatus();
    default:
      return renewalAwareStatus();
  }
}

type AppTx = Parameters<Parameters<ReturnType<typeof getDb>["transaction"]>[0]>[0];

async function lockSubscriptionClaim(
  tx: AppTx,
  userId: string,
  originalTransactionId: string,
): Promise<void> {
  const keys = [
    `subscription:original:${originalTransactionId}`,
    `subscription:user:${userId.toLowerCase()}`,
  ].sort();
  for (const key of keys) {
    await tx.execute(
      sql`select pg_advisory_xact_lock(hashtextextended(${key}, 0))`,
    );
  }
}

async function existingOwner(
  db: AppTx,
  originalTransactionId: string,
  currentTransactionId: string,
): Promise<EntitlementRow | undefined> {
  return db.query.subscriptionEntitlements.findFirst({
    where: or(
      eq(subscriptionEntitlements.originalTransactionId, originalTransactionId),
      eq(subscriptionEntitlements.currentTransactionId, currentTransactionId),
    ),
  });
}

export async function getSubscription(userId: string): Promise<SubscriptionBody> {
  try {
    const row = await getDb().query.subscriptionEntitlements.findFirst({
      where: eq(subscriptionEntitlements.userId, userId),
    });
    return subscriptionBody(row);
  } catch (error) {
    throw wrapDbError(error, "get_subscription");
  }
}

export async function hasActiveEntitlement(userId: string, date: Date): Promise<boolean> {
  try {
    const row = await getDb().query.subscriptionEntitlements.findFirst({
      where: eq(subscriptionEntitlements.userId, userId),
    });
    return row ? isEntitled(row, date) : false;
  } catch (error) {
    throw wrapDbError(error, "has_active_entitlement");
  }
}

export async function syncSubscriptionTransaction(
  userId: string,
  transaction: VerifiedAppStoreTransaction,
  now: Date = new Date(),
): Promise<SubscriptionBody> {
  const token = transaction.appAccountToken?.toLowerCase();
  if (token && token !== userId.toLowerCase()) {
    throw new SubscriptionOwnershipError();
  }

  try {
    return await getDb().transaction(async (db) => {
      await lockSubscriptionClaim(db, userId, transaction.originalTransactionId);

      const claimed = await existingOwner(
        db,
        transaction.originalTransactionId,
        transaction.transactionId,
      );
      if (claimed && claimed.userId !== userId) {
        throw new SubscriptionOwnershipError();
      }

      const current = await db.query.subscriptionEntitlements.findFirst({
        where: eq(subscriptionEntitlements.userId, userId),
      });
      const replacing =
        current !== undefined &&
        current.originalTransactionId !== transaction.originalTransactionId;
      if (
        replacing &&
        (isEntitled(current, now) || token !== userId.toLowerCase())
      ) {
        throw new SubscriptionOwnershipError();
      }

      const eventAt = latestTransactionDate(transaction);
      if (!replacing && current && eventAt < current.lastAppleEventAt) {
        return subscriptionBody(current, now);
      }

      const rows = await db
        .insert(subscriptionEntitlements)
        .values({
          userId,
          originalTransactionId: transaction.originalTransactionId,
          currentTransactionId: transaction.transactionId,
          productId: transaction.productId,
          environment: transaction.environment,
          status: transactionStatus(transaction, now),
          paidThrough: transaction.expiresDate,
          gracePeriodExpiresAt: null,
          renewalDate: null,
          revokedAt: transaction.revocationDate ?? null,
          quotaAnchor:
            replacing || !current
              ? transaction.originalPurchaseDate
              : current.quotaAnchor,
          lastAppleEventAt: eventAt,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: subscriptionEntitlements.userId,
          set: {
            originalTransactionId: transaction.originalTransactionId,
            currentTransactionId: transaction.transactionId,
            productId: transaction.productId,
            environment: transaction.environment,
            status: transactionStatus(transaction, now),
            paidThrough: transaction.expiresDate,
            gracePeriodExpiresAt: null,
            renewalDate: null,
            revokedAt: transaction.revocationDate ?? null,
            quotaAnchor:
              replacing
                ? transaction.originalPurchaseDate
                : (current?.quotaAnchor ?? transaction.originalPurchaseDate),
            lastAppleEventAt: eventAt,
            updatedAt: now,
          },
          ...(!replacing
            ? { setWhere: lt(subscriptionEntitlements.lastAppleEventAt, eventAt) }
            : {}),
        })
        .returning();
      if (rows[0]) {
        return subscriptionBody(rows[0], now);
      }
      const unchanged = await db.query.subscriptionEntitlements.findFirst({
        where: eq(subscriptionEntitlements.userId, userId),
      });
      return subscriptionBody(unchanged, now);
    });
  } catch (error) {
    if (error instanceof SubscriptionOwnershipError) {
      throw error;
    }
    const code =
      typeof error === "object" && error !== null && "code" in error
        ? String(error.code)
        : undefined;
    if (code === "23505") {
      throw new SubscriptionOwnershipError();
    }
    throw wrapDbError(error, "sync_subscription");
  }
}

export type NotificationProcessResult = "processed" | "duplicate" | "ignored";

export async function processSubscriptionNotification(
  notification: VerifiedAppStoreNotification,
  now: Date = new Date(),
): Promise<NotificationProcessResult> {
  try {
    const transaction = notification.transaction;
    const renewal = notification.renewal;
    if (!transaction || !renewal) {
      return "ignored";
    }
    let entitlement = await getDb().query.subscriptionEntitlements.findFirst({
      where: eq(
        subscriptionEntitlements.originalTransactionId,
        transaction.originalTransactionId,
      ),
    });

    const appAccountToken = transaction.appAccountToken ?? renewal.appAccountToken;
    if (!entitlement && appAccountToken) {
      const user = await getDb().query.users.findFirst({
        where: eq(users.id, appAccountToken.toLowerCase()),
        columns: { id: true },
      });
      if (user) {
        await syncSubscriptionTransaction(user.id, transaction, now);
        entitlement = await getDb().query.subscriptionEntitlements.findFirst({
          where: eq(subscriptionEntitlements.userId, user.id),
        });
      }
    }
    if (!entitlement) {
      return "ignored";
    }
    const ownerId = entitlement.userId;
    return await getDb().transaction(async (db) => {
      await lockSubscriptionClaim(db, ownerId, transaction.originalTransactionId);
      const current = await db.query.subscriptionEntitlements.findFirst({
        where: eq(subscriptionEntitlements.userId, ownerId),
      });
      if (
        !current ||
        current.originalTransactionId !== transaction.originalTransactionId
      ) {
        return "ignored";
      }
      const inserted = await db
        .insert(subscriptionEvents)
        .values({
          notificationUuid: notification.notificationUUID,
          userId: ownerId,
          notificationType: notification.notificationType,
          subtype: notification.subtype ?? null,
          originalTransactionId: transaction.originalTransactionId,
          transactionId: transaction.transactionId,
          signedAt: notification.signedDate,
        })
        .onConflictDoNothing({ target: subscriptionEvents.notificationUuid })
        .returning({ notificationUuid: subscriptionEvents.notificationUuid });
      if (inserted.length === 0) {
        return "duplicate";
      }

      const eventAt = new Date(
        Math.max(
          notification.signedDate.getTime(),
          latestTransactionDate(transaction).getTime(),
          renewal.signedDate.getTime(),
        ),
      );
      if (eventAt <= current.lastAppleEventAt) {
        return "processed";
      }

      const status = notificationStatus(
        notification.notificationType,
        notification.subtype,
        transaction,
        renewal,
        now,
      );
      await db
        .update(subscriptionEntitlements)
        .set({
          currentTransactionId: transaction.transactionId,
          productId: transaction.productId,
          environment: transaction.environment,
          status,
          paidThrough: transaction.expiresDate,
          gracePeriodExpiresAt: renewal.gracePeriodExpiresDate ?? null,
          renewalDate: renewal.renewalDate ?? null,
          revokedAt:
            status === "revoked"
              ? (transaction.revocationDate ?? notification.signedDate)
              : null,
          lastAppleEventAt: eventAt,
          updatedAt: now,
        })
        .where(
          and(
            eq(subscriptionEntitlements.userId, ownerId),
            lt(subscriptionEntitlements.lastAppleEventAt, eventAt),
          ),
        );
      return "processed";
    });
  } catch (error) {
    if (error instanceof SubscriptionOwnershipError) {
      throw error;
    }
    throw wrapDbError(error, "process_subscription_notification");
  }
}
