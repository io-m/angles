import { describe, expect, it, vi } from "vitest";
import { reportAlertConfig, reportAlertEmail, sendReportAlert } from "./reportAlerts.js";

const CARD_ID = "00000000-0000-4000-8000-0000000000aa";
const env = {
  RESEND_API_KEY: "re_test",
  REPORT_ALERT_FROM: "Angles <alerts@useangles.app>",
  REPORT_ALERT_TO: "info@bithavn.app, ops@bithavn.app",
} as NodeJS.ProcessEnv;

describe("report alerts", () => {
  it("overrides local mail credentials in the Vitest process", () => {
    expect(process.env.RESEND_API_KEY).toBe("");
    expect(process.env.REPORT_ALERT_FROM).toBe("");
    expect(process.env.REPORT_ALERT_TO).toBe("");
  });

  it("is off until the key, sender and recipient are all set", () => {
    expect(reportAlertConfig({} as NodeJS.ProcessEnv)).toBeNull();
    expect(reportAlertConfig({ ...env, REPORT_ALERT_TO: " , " })).toBeNull();
    expect(reportAlertConfig(env)?.to).toEqual(["info@bithavn.app", "ops@bithavn.app"]);
  });

  it("skips without calling out when unconfigured", async () => {
    const fetchImpl = vi.fn<typeof fetch>();
    await expect(
      sendReportAlert({ cardId: CARD_ID, reason: "spam", madePrivate: false }, fetchImpl, {}),
    ).resolves.toBe("skipped");
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("cannot send during Vitest even when mail is configured", async () => {
    const fetchImpl = vi.fn<typeof fetch>();
    await expect(
      sendReportAlert(
        { cardId: CARD_ID, reason: "harassment", madePrivate: false },
        fetchImpl,
        { ...env, VITEST: "true" },
      ),
    ).resolves.toBe("skipped");
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("sends ids and the reason, never card text", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response("{}", { status: 200 }));
    await expect(
      sendReportAlert({ cardId: CARD_ID, reason: "hate", madePrivate: true }, fetchImpl, env),
    ).resolves.toBe("sent");
    const [url, init] = fetchImpl.mock.calls[0] ?? [];
    expect(url).toBe("https://api.resend.com/emails");
    const body = JSON.parse(String(init?.body)) as { to: string[]; subject: string; text: string };
    expect(body.to).toEqual(["info@bithavn.app", "ops@bithavn.app"]);
    expect(body.subject).toContain("made private");
    expect(body.text).toContain(CARD_ID);
    expect(Object.keys(body).sort()).toEqual(["from", "subject", "text", "to"]);
  });

  it("throws on a provider error so the caller logs it", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response("no", { status: 500 }));
    await expect(
      sendReportAlert({ cardId: CARD_ID, reason: "spam", madePrivate: false }, fetchImpl, env),
    ).rejects.toThrow("500");
  });

  it("names the review commands", () => {
    const { text } = reportAlertEmail({ cardId: CARD_ID, reason: "other", madePrivate: false });
    expect(text).toContain(`pnpm reports hide ${CARD_ID}`);
  });
});
