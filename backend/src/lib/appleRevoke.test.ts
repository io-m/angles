import { describe, expect, it, vi } from "vitest";
import {
  AppleRevokeError,
  exchangeAppleAuthorizationCode,
  revokeAppleGrant,
  subjectOfIdToken,
} from "./appleRevoke.js";

const env = { APPLE_CLIENT_ID: "app.angles.ios", APPLE_CLIENT_SECRET: "jwt.secret" } as NodeJS.ProcessEnv;

function idToken(claims: Record<string, unknown>): string {
  return `h.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.s`;
}

function formOf(init: RequestInit | undefined): URLSearchParams {
  return new URLSearchParams(String(init?.body));
}

describe("Apple revocation", () => {
  it("reads the subject from an id token", () => {
    expect(subjectOfIdToken(idToken({ sub: "001.abc" }))).toBe("001.abc");
    expect(subjectOfIdToken("garbage")).toBeNull();
    expect(subjectOfIdToken(idToken({}))).toBeNull();
  });

  it("refuses to call Apple without a client secret", async () => {
    const fetchImpl = vi.fn<typeof fetch>();
    await expect(
      exchangeAppleAuthorizationCode("code", fetchImpl, { APPLE_CLIENT_SECRET: "missing" }),
    ).rejects.toMatchObject({ step: "unconfigured" });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("trades a code for the refresh token and its subject", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      Response.json({ refresh_token: "r1", access_token: "a1", id_token: idToken({ sub: "001.abc" }) }),
    );
    await expect(exchangeAppleAuthorizationCode("c1", fetchImpl, env)).resolves.toEqual({
      subject: "001.abc",
      token: "r1",
      tokenTypeHint: "refresh_token",
    });
    const [url, init] = fetchImpl.mock.calls[0] ?? [];
    expect(url).toBe("https://appleid.apple.com/auth/token");
    expect(Object.fromEntries(formOf(init))).toEqual({
      client_id: "app.angles.ios",
      client_secret: "jwt.secret",
      code: "c1",
      grant_type: "authorization_code",
    });
  });

  it("falls back to the access token when Apple returns no refresh token", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () =>
      Response.json({ access_token: "a1", id_token: idToken({ sub: "001.abc" }) }),
    );
    await expect(exchangeAppleAuthorizationCode("c1", fetchImpl, env)).resolves.toMatchObject({
      token: "a1",
      tokenTypeHint: "access_token",
    });
  });

  it("fails an exchange Apple rejects", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => Response.json({ error: "invalid_grant" }, { status: 400 }));
    await expect(exchangeAppleAuthorizationCode("bad", fetchImpl, env)).rejects.toBeInstanceOf(
      AppleRevokeError,
    );
  });

  it("revokes with the token type it holds", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response(null, { status: 200 }));
    await revokeAppleGrant({ subject: "s", token: "r1", tokenTypeHint: "refresh_token" }, fetchImpl, env);
    const [url, init] = fetchImpl.mock.calls[0] ?? [];
    expect(url).toBe("https://appleid.apple.com/auth/revoke");
    expect(formOf(init).get("token")).toBe("r1");
    expect(formOf(init).get("token_type_hint")).toBe("refresh_token");
  });

  it("fails a revoke Apple rejects", async () => {
    const fetchImpl = vi.fn<typeof fetch>(async () => new Response(null, { status: 400 }));
    await expect(
      revokeAppleGrant({ subject: "s", token: "r1", tokenTypeHint: "refresh_token" }, fetchImpl, env),
    ).rejects.toMatchObject({ step: "revoke" });
  });
});
