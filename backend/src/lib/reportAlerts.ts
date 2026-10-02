import type { ReportReason } from "./communitySafetyTypes.js";

/**
 * Tells the operator a card was reported, so the 24-hour review the Terms promise happens.
 * The alert carries ids and the reason only, never the card's text: the operator reads the
 * card with `pnpm reports`.
 */
export type ReportAlert = {
  cardId: string;
  reason: ReportReason;
  madePrivate: boolean;
};

type ReportAlertConfig = {
  apiKey: string;
  to: string[];
  from: string;
};

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const ALERT_TIMEOUT_MS = 5_000;

export function reportAlertConfig(env: NodeJS.ProcessEnv = process.env): ReportAlertConfig | null {
  const apiKey = env.RESEND_API_KEY?.trim();
  const from = env.REPORT_ALERT_FROM?.trim();
  const to = (env.REPORT_ALERT_TO ?? "")
    .split(",")
    .map((address) => address.trim())
    .filter((address) => address.length > 0);
  if (!apiKey || !from || to.length === 0) {
    return null;
  }
  return { apiKey, to, from };
}

export function reportAlertEmail(alert: ReportAlert): { subject: string; text: string } {
  const subject = alert.madePrivate
    ? `Angles: card made private after reports (${alert.reason})`
    : `Angles: card reported (${alert.reason})`;
  const text = [
    `A card on Home was reported for "${alert.reason}".`,
    `Card: ${alert.cardId}`,
    alert.madePrivate
      ? "It reached the report threshold and is now private until reviewed."
      : "It is still public for everyone except the reporter.",
    "",
    "Review within 24 hours. From backend/, with the production DATABASE_URL:",
    "  pnpm reports",
    `  pnpm reports hide ${alert.cardId}`,
    `  pnpm reports keep ${alert.cardId}`,
  ].join("\n");
  return { subject, text };
}

/** Never throws for a missing config: an unconfigured server only logs `card_reported`. */
export async function sendReportAlert(
  alert: ReportAlert,
  fetchImpl: typeof fetch = fetch,
  env: NodeJS.ProcessEnv = process.env,
): Promise<"sent" | "skipped"> {
  const config = reportAlertConfig(env);
  if (!config) {
    return "skipped";
  }
  const { subject, text } = reportAlertEmail(alert);
  const response = await fetchImpl(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: config.from, to: config.to, subject, text }),
    signal: AbortSignal.timeout(ALERT_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`report alert failed with ${response.status}`);
  }
  return "sent";
}

/** Fire and forget from a request: the report is already stored, so an alert failure only logs. */
export function announceReport(alert: ReportAlert): void {
  console.log("card_reported", alert);
  void sendReportAlert(alert).catch((error: unknown) => {
    console.error("report_alert_failed", {
      cardId: alert.cardId,
      name: error instanceof Error ? error.name : "error",
    });
  });
}
