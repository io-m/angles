import { createHmac } from "node:crypto";

export const USAGE_PLAN_VERSION = "monthly-600-v1";
export const CREDIT_TARIFF_VERSION = "flat-v1";
export const MONTHLY_CREDITS = 600;
export const DAILY_OPERATION_LIMIT = 60;
export const DAILY_PROVIDER_CALL_LIMIT = 200;
export const TASTE_LIFETIME_TURN_LIMIT = 10;

/** Every ready cook and every recook costs the same, whichever model the server routed it to. */
export const COOK_CREDIT_COST = 1;

export type UsageWarning = "normal" | "low" | "critical" | "empty";

export type UsageSummary = {
  creditsGranted: number;
  creditsRemaining: number;
  periodStart: string | null;
  periodEnd: string | null;
  resetsAt: string | null;
  warning: UsageWarning;
  creditCost: number;
};

export function isUsageEnforcementRequired(): boolean {
  return process.env.USAGE_ENFORCEMENT?.trim().toLowerCase() === "required";
}

export function assertMeteringConfiguration(): void {
  if (isUsageEnforcementRequired() && !process.env.METERING_HMAC_KEY?.trim()) {
    throw new Error("METERING_HMAC_KEY is required when USAGE_ENFORCEMENT=required");
  }
}

export function usageWarning(remaining: number): UsageWarning {
  if (remaining <= 0) {
    return "empty";
  }
  if (remaining <= Math.floor(MONTHLY_CREDITS * 0.1)) {
    return "critical";
  }
  if (remaining <= Math.floor(MONTHLY_CREDITS * 0.2)) {
    return "low";
  }
  return "normal";
}

function daysInUtcMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
}

/** Adds months from the original UTC anchor, so clamping never accumulates drift. */
export function utcMonthBoundary(anchor: Date, monthOffset: number): Date {
  const absoluteMonth = anchor.getUTCFullYear() * 12 + anchor.getUTCMonth() + monthOffset;
  const year = Math.floor(absoluteMonth / 12);
  const month = ((absoluteMonth % 12) + 12) % 12;
  return new Date(
    Date.UTC(
      year,
      month,
      Math.min(anchor.getUTCDate(), daysInUtcMonth(year, month)),
      anchor.getUTCHours(),
      anchor.getUTCMinutes(),
      anchor.getUTCSeconds(),
      anchor.getUTCMilliseconds(),
    ),
  );
}

export function paidUsagePeriod(anchor: Date, at: Date): { startsAt: Date; endsAt: Date } {
  let offset =
    (at.getUTCFullYear() - anchor.getUTCFullYear()) * 12 +
    (at.getUTCMonth() - anchor.getUTCMonth());
  if (utcMonthBoundary(anchor, offset) > at) {
    offset -= 1;
  }
  return {
    startsAt: utcMonthBoundary(anchor, offset),
    endsAt: utcMonthBoundary(anchor, offset + 1),
  };
}

export function developmentUsagePeriod(at: Date): { startsAt: Date; endsAt: Date } {
  return {
    startsAt: new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), 1)),
    endsAt: new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth() + 1, 1)),
  };
}

function canonicalValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonicalValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, nested]) => [key, canonicalValue(nested)]),
    );
  }
  return value;
}

export function canonicalJson(value: unknown): string {
  return JSON.stringify(canonicalValue(value));
}

function meteringHmacKey(): string {
  const configured = process.env.METERING_HMAC_KEY?.trim();
  if (configured) {
    return configured;
  }
  if (!isUsageEnforcementRequired() || process.env.VITEST === "true") {
    return "local-only-metering-hmac-key";
  }
  throw new Error("METERING_HMAC_KEY is required");
}

/** The request alone: the server may route a retry to another model and it is still the same request. */
export function requestFingerprint(request: unknown): string {
  return createHmac("sha256", meteringHmacKey())
    .update(canonicalJson({ request }))
    .digest("hex");
}
