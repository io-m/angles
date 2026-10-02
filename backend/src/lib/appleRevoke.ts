/**
 * Sign in with Apple token revocation for account deletion, as Apple requires.
 *
 * The phone signs in with an identity token only, so the server never holds an Apple refresh
 * token. Delete account asks Apple for a fresh authorization code; the server trades it for
 * tokens (which also proves which Apple ID it belongs to), deletes the account, then revokes.
 */

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_TIMEOUT_MS = 8_000;

export class AppleRevokeError extends Error {
  constructor(readonly step: "unconfigured" | "exchange" | "revoke", status?: number) {
    super(status === undefined ? `apple ${step} failed` : `apple ${step} failed with ${status}`);
    this.name = "AppleRevokeError";
  }
}

export type AppleGrant = {
  subject: string;
  token: string;
  tokenTypeHint: "refresh_token" | "access_token";
};

type AppleClient = { clientId: string; clientSecret: string };

function appleClient(env: NodeJS.ProcessEnv): AppleClient {
  const clientSecret = env.APPLE_CLIENT_SECRET?.trim();
  if (!clientSecret || clientSecret === "missing") {
    throw new AppleRevokeError("unconfigured");
  }
  return { clientId: env.APPLE_CLIENT_ID?.trim() || "app.angles.ios", clientSecret };
}

/** The `sub` claim of a token Apple just returned to us over TLS; its signature is not rechecked. */
export function subjectOfIdToken(idToken: string): string | null {
  const payload = idToken.split(".")[1];
  if (!payload) {
    return null;
  }
  try {
    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { sub?: unknown };
    return typeof claims.sub === "string" && claims.sub.length > 0 ? claims.sub : null;
  } catch {
    return null;
  }
}

export async function exchangeAppleAuthorizationCode(
  code: string,
  fetchImpl: typeof fetch = fetch,
  env: NodeJS.ProcessEnv = process.env,
): Promise<AppleGrant> {
  const { clientId, clientSecret } = appleClient(env);
  const response = await fetchImpl(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
    signal: AbortSignal.timeout(APPLE_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new AppleRevokeError("exchange", response.status);
  }
  const body = (await response.json()) as {
    refresh_token?: unknown;
    access_token?: unknown;
    id_token?: unknown;
  };
  const subject = typeof body.id_token === "string" ? subjectOfIdToken(body.id_token) : null;
  if (!subject) {
    throw new AppleRevokeError("exchange");
  }
  if (typeof body.refresh_token === "string" && body.refresh_token.length > 0) {
    return { subject, token: body.refresh_token, tokenTypeHint: "refresh_token" };
  }
  if (typeof body.access_token === "string" && body.access_token.length > 0) {
    return { subject, token: body.access_token, tokenTypeHint: "access_token" };
  }
  throw new AppleRevokeError("exchange");
}

export async function revokeAppleGrant(
  grant: AppleGrant,
  fetchImpl: typeof fetch = fetch,
  env: NodeJS.ProcessEnv = process.env,
): Promise<void> {
  const { clientId, clientSecret } = appleClient(env);
  const response = await fetchImpl(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      token: grant.token,
      token_type_hint: grant.tokenTypeHint,
    }),
    signal: AbortSignal.timeout(APPLE_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new AppleRevokeError("revoke", response.status);
  }
}
