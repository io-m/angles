import { createPrivateKey, createSign, type KeyObject } from "node:crypto";
import http2 from "node:http2";

export type PushEnvironment = "sandbox" | "production";

export type ApnsConfig = {
  key: string;
  keyId: string;
  teamId: string;
  bundleId: string;
};

export type FollowPushAlert = {
  token: string;
  environment: PushEnvironment;
  collapseId: string;
  title: string;
  body: string;
  badge: number;
  notificationId: string;
  actorId: string;
};

export type ApnsSendResult = "sent" | "unregistered" | "skipped" | "failed";

const APNS_TIMEOUT_MS = 5_000;

/** Display name on the account, else initials, else Someone. Never thought text or counts. */
export function followActorPublicName(name: string, initials: string): string {
  const trimmedName = name.trim();
  if (trimmedName) {
    return trimmedName;
  }
  const trimmedInitials = initials.trim();
  return trimmedInitials || "Someone";
}

export function followPushAlertText(
  name: string,
  initials: string,
  followedBack: boolean,
): { title: string; body: string } {
  return {
    title: followActorPublicName(name, initials),
    body: followedBack ? "Followed you back" : "Followed you",
  };
}

/** One-line body for tests and older call sites. */
export function followAlertCopy(name: string, initials: string, followedBack: boolean): string {
  const { title, body } = followPushAlertText(name, initials, followedBack);
  return `${title} ${body.charAt(0).toLowerCase()}${body.slice(1)}`;
}

export function apnsConfigFromEnv(env: NodeJS.ProcessEnv = process.env): ApnsConfig | null {
  const key = env.APNS_KEY?.trim();
  const keyId = env.APNS_KEY_ID?.trim();
  const teamId = env.APNS_TEAM_ID?.trim();
  const bundleId = env.APNS_BUNDLE_ID?.trim();
  if (!key || !keyId || !teamId || !bundleId) {
    return null;
  }
  return { key: key.replace(/\\n/g, "\n"), keyId, teamId, bundleId };
}

/** Startup check. A key that does not parse would fail every send, so say so once at boot. */
export function describeApnsConfig(
  config: ApnsConfig | null = apnsConfigFromEnv(),
): { configured: boolean; keyValid: boolean } {
  if (!config) {
    return { configured: false, keyValid: false };
  }
  try {
    return { configured: true, keyValid: signingKey(config.key).asymmetricKeyType === "ec" };
  } catch {
    return { configured: true, keyValid: false };
  }
}

/**
 * A token APNs will never accept again is dropped. `BadDeviceToken` is also what a sandbox
 * token returns from the production host; the phone registers its real token on foreground.
 */
export function apnsOutcome(status: number, reason?: string): ApnsSendResult {
  if (status === 200) {
    return "sent";
  }
  if (status === 410 || (status === 400 && reason === "BadDeviceToken")) {
    return "unregistered";
  }
  return "failed";
}

/** APNs answers an error with `{ "reason": "..." }`. Only that field is kept. */
export function apnsReason(body: string): string | undefined {
  if (!body) {
    return undefined;
  }
  try {
    const parsed: unknown = JSON.parse(body);
    if (parsed && typeof parsed === "object" && "reason" in parsed) {
      const reason = (parsed as { reason: unknown }).reason;
      return typeof reason === "string" ? reason.slice(0, 64) : undefined;
    }
  } catch {
    return undefined;
  }
  return undefined;
}

let cachedJwt: { token: string; expiresAt: number; keyId: string } | null = null;

function base64url(value: Buffer | string): string {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return buffer.toString("base64url");
}

function providerToken(config: ApnsConfig, now = Math.floor(Date.now() / 1000)): string {
  if (cachedJwt && cachedJwt.keyId === config.keyId && cachedJwt.expiresAt - 60 > now) {
    return cachedJwt.token;
  }
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat: now }));
  const unsigned = `${header}.${claims}`;
  const signer = createSign("SHA256");
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign({ key: signingKey(config.key), dsaEncoding: "ieee-p1363" });
  const token = `${unsigned}.${base64url(signature)}`;
  cachedJwt = { token, expiresAt: now + 50 * 60, keyId: config.keyId };
  return token;
}

function signingKey(pem: string): KeyObject {
  return createPrivateKey(pem);
}

function apnsHost(environment: PushEnvironment): string {
  return environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
}

/** `origin` is for tests; production always derives the Apple host from the token's environment. */
export async function sendApnsAlert(
  alert: FollowPushAlert,
  config: ApnsConfig | null = apnsConfigFromEnv(),
  origin = `https://${apnsHost(alert.environment)}`,
): Promise<ApnsSendResult> {
  if (!config) {
    return "skipped";
  }
  try {
    const { status, reason } = await postAlert(alert, config, origin);
    const result = apnsOutcome(status, reason);
    console.log("apns_result", { status, reason: reason ?? null, environment: alert.environment, result });
    return result;
  } catch (error) {
    console.error("apns_send_failed", {
      name: error instanceof Error ? error.name : "error",
      code: (error as { code?: unknown } | null)?.code ?? null,
      environment: alert.environment,
    });
    return "failed";
  }
}

function postAlert(
  alert: FollowPushAlert,
  config: ApnsConfig,
  origin: string,
): Promise<{ status: number; reason?: string }> {
  const body = JSON.stringify({
    aps: {
      alert: { title: alert.title, body: alert.body },
      badge: alert.badge,
      sound: "default",
      category: "follow",
    },
    notificationId: alert.notificationId,
    actorId: alert.actorId,
  });
  return new Promise((resolve, reject) => {
    const client = http2.connect(origin);
    let settled = false;
    const finish = (error?: Error, status?: number, responseBody = "") => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      client.close();
      if (error) {
        reject(error);
        return;
      }
      const code = status ?? 0;
      resolve(code === 200 ? { status: code } : { status: code, reason: apnsReason(responseBody) });
    };
    const timer = setTimeout(() => {
      client.destroy();
      finish(new Error("apns timeout"));
    }, APNS_TIMEOUT_MS);
    client.on("error", (error) => {
      finish(error);
    });

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${alert.token}`,
      authorization: `bearer ${providerToken(config)}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": alert.collapseId,
    });
    request.setEncoding("utf8");
    let status = 0;
    let responseBody = "";
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    // The stream must be read: a paused HTTP/2 stream never emits `end`.
    request.on("data", (chunk: string) => {
      if (responseBody.length < 1024) {
        responseBody += chunk;
      }
    });
    request.on("end", () => {
      finish(undefined, status, responseBody);
    });
    request.on("error", (error) => {
      finish(error);
    });
    request.end(body);
  });
}
