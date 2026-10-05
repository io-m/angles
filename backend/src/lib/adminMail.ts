const RESEND_ENDPOINT = "https://api.resend.com/emails";
const MAIL_TIMEOUT_MS = 5_000;

/** Sends the operator sign-in link. Never throws for a missing Resend config. */
export async function sendAdminMagicLink(
  email: string,
  link: string,
  fetchImpl: typeof fetch = fetch,
  env: NodeJS.ProcessEnv = process.env,
): Promise<"sent" | "skipped"> {
  const apiKey = env.RESEND_API_KEY?.trim();
  const from = env.ADMIN_MAGIC_FROM?.trim() || env.REPORT_ALERT_FROM?.trim();
  if (!apiKey || !from) {
    return "skipped";
  }
  const response = await fetchImpl(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: "Angles operator sign-in",
      text: [
        "Sign in to review Angles reports:",
        link,
        "",
        "This link works once and expires in 15 minutes.",
        "If you did not ask for it, ignore this email.",
      ].join("\n"),
    }),
    signal: AbortSignal.timeout(MAIL_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`admin magic link failed with ${response.status}`);
  }
  return "sent";
}
