import { generateKeyPairSync } from "node:crypto";
import http2 from "node:http2";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import {
  apnsConfigFromEnv,
  apnsOutcome,
  apnsReason,
  describeApnsConfig,
  followActorPublicName,
  followAlertCopy,
  followPushAlertText,
  sendApnsAlert,
  type ApnsConfig,
  type FollowPushAlert,
} from "./apns.js";

describe("follow alert copy", () => {
  it("prefers display name, then initials, then Someone", () => {
    expect(followActorPublicName("Alex Lee", "AL")).toBe("Alex Lee");
    expect(followActorPublicName("  ", "AL")).toBe("AL");
    expect(followActorPublicName("", "  ")).toBe("Someone");
    expect(followAlertCopy("Alex Lee", "AL", false)).toBe("Alex Lee followed you");
    expect(followAlertCopy("", "AL", true)).toBe("AL followed you back");
    expect(followPushAlertText("Alex Lee", "AL", false)).toEqual({
      title: "Alex Lee",
      body: "Followed you",
    });
  });
});

describe("APNs config", () => {
  const keys = ["APNS_KEY", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_BUNDLE_ID"] as const;
  const previous = Object.fromEntries(keys.map((key) => [key, process.env[key]]));

  afterEach(() => {
    for (const key of keys) {
      const value = previous[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it("skips when any value is missing", () => {
    delete process.env.APNS_KEY;
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_TEAM_ID;
    delete process.env.APNS_BUNDLE_ID;
    expect(apnsConfigFromEnv()).toBeNull();
    expect(describeApnsConfig()).toEqual({ configured: false, keyValid: false });
    expect(apnsOutcome(200)).toBe("sent");
    expect(apnsOutcome(410)).toBe("unregistered");
    expect(apnsOutcome(400, "BadDeviceToken")).toBe("unregistered");
    expect(apnsOutcome(400, "BadTopic")).toBe("failed");
    expect(apnsOutcome(403, "InvalidProviderToken")).toBe("failed");
  });

  it("reads an escaped key and says whether it parses", () => {
    process.env.APNS_KEY = testKey().replace(/\n/g, "\\n");
    process.env.APNS_KEY_ID = "KEYID12345";
    process.env.APNS_TEAM_ID = "36U79UTZM9";
    process.env.APNS_BUNDLE_ID = "app.angles.ios";
    expect(describeApnsConfig()).toEqual({ configured: true, keyValid: true });
    process.env.APNS_KEY = "not a key";
    expect(describeApnsConfig()).toEqual({ configured: true, keyValid: false });
  });

  it("keeps only the reason from an error body", () => {
    expect(apnsReason('{"reason":"BadDeviceToken"}')).toBe("BadDeviceToken");
    expect(apnsReason("")).toBeUndefined();
    expect(apnsReason("<html>")).toBeUndefined();
    expect(apnsReason('{"reason":7}')).toBeUndefined();
  });
});

describe("APNs send", () => {
  let server: http2.Http2Server | null = null;

  afterEach(async () => {
    const current = server;
    server = null;
    if (current) {
      await new Promise<void>((resolve) => current.close(() => resolve()));
    }
  });

  async function serve(status: number, body: string) {
    const seen: { headers: http2.IncomingHttpHeaders; payload: string }[] = [];
    server = http2.createServer();
    server.on("stream", (stream: http2.ServerHttp2Stream, headers) => {
      let payload = "";
      stream.setEncoding("utf8");
      stream.on("data", (chunk: string) => {
        payload += chunk;
      });
      stream.on("end", () => {
        seen.push({ headers, payload });
        stream.respond({ ":status": status });
        stream.end(body);
      });
    });
    await new Promise<void>((resolve) => server?.listen(0, "127.0.0.1", () => resolve()));
    const { port } = server.address() as AddressInfo;
    return { origin: `http://127.0.0.1:${port}`, seen };
  }

  const config = (): ApnsConfig => ({
    key: testKey(),
    keyId: "KEYID12345",
    teamId: "36U79UTZM9",
    bundleId: "app.angles.ios",
  });

  const alert: FollowPushAlert = {
    token: "ab".repeat(32),
    environment: "production",
    collapseId: "00000000-0000-4000-8000-000000000001",
    title: "Alex Lee",
    body: "Followed you",
    badge: 1,
    notificationId: "00000000-0000-4000-8000-000000000001",
    actorId: "00000000-0000-4000-8000-000000000002",
  };

  it("resolves an empty 200 as sent without waiting for the timeout", async () => {
    const { origin, seen } = await serve(200, "");
    const started = Date.now();
    expect(await sendApnsAlert(alert, config(), origin)).toBe("sent");
    expect(Date.now() - started).toBeLessThan(2_000);
    expect(seen).toHaveLength(1);
    expect(seen[0]?.headers[":path"]).toBe(`/3/device/${alert.token}`);
    expect(seen[0]?.headers["apns-topic"]).toBe("app.angles.ios");
    expect(seen[0]?.headers["apns-push-type"]).toBe("alert");
    expect(JSON.parse(seen[0]?.payload ?? "{}")).toMatchObject({
      aps: { alert: { title: "Alex Lee", body: "Followed you" }, badge: 1, category: "follow" },
      actorId: alert.actorId,
    });
  });

  it("surfaces the reason on a rejected token and drops it", async () => {
    const { origin } = await serve(400, '{"reason":"BadDeviceToken"}');
    expect(await sendApnsAlert(alert, config(), origin)).toBe("unregistered");
  });

  it("reports a rejected key as failed", async () => {
    const { origin } = await serve(403, '{"reason":"InvalidProviderToken"}');
    expect(await sendApnsAlert(alert, config(), origin)).toBe("failed");
  });

  it("skips without a config", async () => {
    expect(await sendApnsAlert(alert, null)).toBe("skipped");
  });
});

let cachedKey: string | null = null;

function testKey(): string {
  cachedKey ??= generateKeyPairSync("ec", { namedCurve: "prime256v1" })
    .privateKey.export({ format: "pem", type: "pkcs8" })
    .toString();
  return cachedKey;
}
