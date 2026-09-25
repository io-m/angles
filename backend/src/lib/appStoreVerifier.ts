import {
  Environment,
  SignedDataVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "@apple/app-store-server-library";

export const APP_BUNDLE_ID = "app.angles.ios";
export const SUBSCRIPTION_PRODUCT_IDS = [
  "app.angles.ios.annual",
  "app.angles.ios.monthly",
] as const;

export type SubscriptionProductId = (typeof SUBSCRIPTION_PRODUCT_IDS)[number];
export type AppStoreEnvironment = "sandbox" | "production";

export type VerifiedAppStoreTransaction = {
  originalTransactionId: string;
  transactionId: string;
  productId: SubscriptionProductId;
  appAccountToken?: string;
  environment: AppStoreEnvironment;
  purchaseDate: Date;
  originalPurchaseDate: Date;
  expiresDate: Date;
  signedDate: Date;
  revocationDate?: Date;
  isUpgraded: boolean;
};

export type VerifiedAppStoreRenewal = {
  originalTransactionId: string;
  productId: SubscriptionProductId;
  autoRenewProductId?: SubscriptionProductId;
  appAccountToken?: string;
  environment: AppStoreEnvironment;
  signedDate: Date;
  gracePeriodExpiresDate?: Date;
  renewalDate?: Date;
  isInBillingRetryPeriod: boolean;
};

export type VerifiedAppStoreNotification = {
  notificationUUID: string;
  notificationType: string;
  subtype?: string;
  signedDate: Date;
  transaction?: VerifiedAppStoreTransaction;
  renewal?: VerifiedAppStoreRenewal;
};

export class AppStoreVerificationError extends Error {
  constructor(
    message: string,
    readonly kind: "invalid" | "configuration" = "invalid",
  ) {
    super(message);
    this.name = "AppStoreVerificationError";
  }
}
export interface AppStoreVerifier {
  verifyTransaction(signedTransactionInfo: string): Promise<VerifiedAppStoreTransaction>;
  verifyNotification(signedPayload: string): Promise<VerifiedAppStoreNotification>;
}

type AppleVerifier = Pick<
  SignedDataVerifier,
  | "verifyAndDecodeTransaction"
  | "verifyAndDecodeRenewalInfo"
  | "verifyAndDecodeNotification"
>;

function requiredString(value: string | undefined, field: string): string {
  if (!value) {
    throw new AppStoreVerificationError(`Apple payload is missing ${field}`);
  }
  return value;
}

function requiredDate(value: number | undefined, field: string): Date {
  if (value === undefined || !Number.isFinite(value)) {
    throw new AppStoreVerificationError(`Apple payload is missing ${field}`);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new AppStoreVerificationError(`Apple payload has invalid ${field}`);
  }
  return date;
}

function optionalDate(value: number | undefined, field: string): Date | undefined {
  return value === undefined ? undefined : requiredDate(value, field);
}

function environmentOf(value: string | undefined): AppStoreEnvironment {
  if (value === Environment.SANDBOX) {
    return "sandbox";
  }
  if (value === Environment.PRODUCTION) {
    return "production";
  }
  throw new AppStoreVerificationError("Unsupported App Store environment");
}

function normalizeTransaction(payload: JWSTransactionDecodedPayload): VerifiedAppStoreTransaction {
  if (payload.bundleId !== APP_BUNDLE_ID) {
    throw new AppStoreVerificationError("Transaction is for another app");
  }
  const productId = requiredString(payload.productId, "productId");
  if (!SUBSCRIPTION_PRODUCT_IDS.includes(productId as SubscriptionProductId)) {
    throw new AppStoreVerificationError("Transaction is for an unsupported product");
  }

  return {
    originalTransactionId: requiredString(
      payload.originalTransactionId,
      "originalTransactionId",
    ),
    transactionId: requiredString(payload.transactionId, "transactionId"),
    productId: productId as SubscriptionProductId,
    ...(payload.appAccountToken ? { appAccountToken: payload.appAccountToken.toLowerCase() } : {}),
    environment: environmentOf(payload.environment),
    purchaseDate: requiredDate(payload.purchaseDate, "purchaseDate"),
    originalPurchaseDate: requiredDate(
      payload.originalPurchaseDate ?? payload.purchaseDate,
      "originalPurchaseDate",
    ),
    expiresDate: requiredDate(payload.expiresDate, "expiresDate"),
    signedDate: requiredDate(payload.signedDate, "signedDate"),
    ...(payload.revocationDate !== undefined
      ? { revocationDate: requiredDate(payload.revocationDate, "revocationDate") }
      : {}),
    isUpgraded: payload.isUpgraded === true,
  };
}

function supportedProduct(value: string | undefined, field: string): SubscriptionProductId {
  const productId = requiredString(value, field);
  if (!SUBSCRIPTION_PRODUCT_IDS.includes(productId as SubscriptionProductId)) {
    throw new AppStoreVerificationError("Renewal is for an unsupported product");
  }
  return productId as SubscriptionProductId;
}

function normalizeRenewal(payload: JWSRenewalInfoDecodedPayload): VerifiedAppStoreRenewal {
  const autoRenewProductId = payload.autoRenewProductId
    ? supportedProduct(payload.autoRenewProductId, "autoRenewProductId")
    : undefined;
  const gracePeriodExpiresDate = optionalDate(
    payload.gracePeriodExpiresDate,
    "gracePeriodExpiresDate",
  );
  const renewalDate = optionalDate(payload.renewalDate, "renewalDate");
  return {
    originalTransactionId: requiredString(
      payload.originalTransactionId,
      "renewal originalTransactionId",
    ),
    productId: supportedProduct(payload.productId, "renewal productId"),
    ...(autoRenewProductId ? { autoRenewProductId } : {}),
    ...(payload.appAccountToken
      ? { appAccountToken: payload.appAccountToken.toLowerCase() }
      : {}),
    environment: environmentOf(payload.environment),
    signedDate: requiredDate(payload.signedDate, "renewal signedDate"),
    ...(gracePeriodExpiresDate ? { gracePeriodExpiresDate } : {}),
    ...(renewalDate ? { renewalDate } : {}),
    isInBillingRetryPeriod: payload.isInBillingRetryPeriod === true,
  };
}

function parseRootCertificates(): Buffer[] {
  const raw = process.env.APPLE_ROOT_CERTIFICATES_BASE64?.trim();
  if (!raw) {
    throw new AppStoreVerificationError(
      "APPLE_ROOT_CERTIFICATES_BASE64 is required",
      "configuration",
    );
  }
  let encoded: unknown;
  try {
    encoded = raw.startsWith("[")
      ? (JSON.parse(raw) as unknown)
      : raw.split(",").map((item) => item.trim());
  } catch {
    throw new AppStoreVerificationError(
      "APPLE_ROOT_CERTIFICATES_BASE64 must contain valid JSON or comma-separated values",
      "configuration",
    );
  }
  if (!Array.isArray(encoded) || encoded.length === 0 || encoded.some((item) => typeof item !== "string")) {
    throw new AppStoreVerificationError(
      "APPLE_ROOT_CERTIFICATES_BASE64 must contain base64 DER certificates",
      "configuration",
    );
  }
  return encoded.map((item) => Buffer.from(item as string, "base64"));
}

function productionAppId(): number | undefined {
  const raw = process.env.APPLE_APP_ID?.trim();
  if (!raw) {
    return undefined;
  }
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new AppStoreVerificationError("APPLE_APP_ID must be a positive integer", "configuration");
  }
  return value;
}

class OfficialAppStoreVerifier implements AppStoreVerifier {
  private readonly sandbox: AppleVerifier;
  private readonly production?: AppleVerifier;

  constructor() {
    const roots = parseRootCertificates();
    this.sandbox = new SignedDataVerifier(
      roots,
      true,
      Environment.SANDBOX,
      APP_BUNDLE_ID,
    );
    const appId = productionAppId();
    if (appId !== undefined) {
      this.production = new SignedDataVerifier(
        roots,
        true,
        Environment.PRODUCTION,
        APP_BUNDLE_ID,
        appId,
      );
    }
  }

  async verifyTransaction(signedTransactionInfo: string): Promise<VerifiedAppStoreTransaction> {
    const payload = await this.verifyInEitherEnvironment((verifier) =>
      verifier.verifyAndDecodeTransaction(signedTransactionInfo),
    );
    return normalizeTransaction(payload);
  }

  async verifyNotification(signedPayload: string): Promise<VerifiedAppStoreNotification> {
    return this.verifyInEitherEnvironment(async (verifier) => {
      const payload = await verifier.verifyAndDecodeNotification(signedPayload);
      return this.normalizeNotification(payload, verifier);
    });
  }

  private async verifyInEitherEnvironment<T>(
    operation: (verifier: AppleVerifier) => Promise<T>,
  ): Promise<T> {
    const verifiers = this.production ? [this.production, this.sandbox] : [this.sandbox];
    for (const verifier of verifiers) {
      try {
        return await operation(verifier);
      } catch {
        // A JWS is bound to one environment. Try the other configured Apple verifier.
      }
    }
    throw new AppStoreVerificationError("App Store signature verification failed");
  }

  private async normalizeNotification(
    payload: ResponseBodyV2DecodedPayload,
    verifier: AppleVerifier,
  ): Promise<VerifiedAppStoreNotification> {
    const notificationUUID = requiredString(payload.notificationUUID, "notificationUUID");
    const notificationType = requiredString(payload.notificationType, "notificationType");
    const signedTransactionInfo = payload.data?.signedTransactionInfo;
    const signedRenewalInfo = payload.data?.signedRenewalInfo;
    if (!signedTransactionInfo || !signedRenewalInfo) {
      if (notificationType === "TEST") {
        return {
          notificationUUID,
          notificationType,
          signedDate: requiredDate(payload.signedDate, "signedDate"),
        };
      }
      throw new AppStoreVerificationError(
        "Subscription notification is missing signed transaction or renewal information",
      );
    }
    const transaction = normalizeTransaction(
      await verifier.verifyAndDecodeTransaction(signedTransactionInfo),
    );
    const renewal = normalizeRenewal(
      await verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo),
    );
    const outerEnvironment = environmentOf(payload.data?.environment);
    if (
      payload.data?.bundleId !== APP_BUNDLE_ID ||
      outerEnvironment !== transaction.environment ||
      outerEnvironment !== renewal.environment ||
      transaction.originalTransactionId !== renewal.originalTransactionId ||
      transaction.productId !== renewal.productId ||
      (transaction.appAccountToken !== undefined &&
        renewal.appAccountToken !== undefined &&
        transaction.appAccountToken !== renewal.appAccountToken)
    ) {
      throw new AppStoreVerificationError(
        "Notification transaction and renewal metadata do not match",
      );
    }
    return {
      notificationUUID,
      notificationType,
      ...(payload.subtype ? { subtype: payload.subtype } : {}),
      signedDate: requiredDate(payload.signedDate, "signedDate"),
      transaction,
      renewal,
    };
  }
}

let verifier: AppStoreVerifier | undefined;

export function getAppStoreVerifier(): AppStoreVerifier {
  verifier ??= new OfficialAppStoreVerifier();
  return verifier;
}
