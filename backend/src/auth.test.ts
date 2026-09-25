import { describe, expect, it, vi } from "vitest";

vi.mock("./db/client.js", () => {
  class DbError extends Error {
    readonly code?: string;
    constructor(message: string, code?: string) {
      super(message);
      this.name = "DbError";
      this.code = code;
    }
  }
  return {
    probeDatabase: vi.fn(async () => "ok" as const),
    DbError,
    getDb: vi.fn(),
    getSql: vi.fn(),
    closePool: vi.fn(),
    assertSchemaCurrent: vi.fn(),
    wrapDbError: vi.fn(),
  };
});

const { createApp } = await import("./app.js");
const app = createApp();

const appleSignInBody = JSON.stringify({
  provider: "apple",
  idToken: { token: "x", nonce: "y" },
  requestSignUp: true,
});

describe("native Apple sign-in", () => {
  it("does not CSRF-reject a cookie-bearing sign-in without Origin", async () => {
    const response = await app.request("/api/auth/sign-in/social", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Cookie: "better-auth.session_token=stale",
      },
      body: appleSignInBody,
    });
    expect(response.status).not.toBe(403);
    const body = (await response.json()) as { code?: string };
    expect(body.code).not.toBe("MISSING_OR_NULL_ORIGIN");
  });

  it("does not CSRF-reject a cookie-bearing sign-out without Origin", async () => {
    const response = await app.request("/api/auth/sign-out", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Cookie: "better-auth.session_token=stale",
      },
      body: "{}",
    });
    expect(response.status).not.toBe(403);
    const body = (await response.json()) as { code?: string };
    expect(body.code).not.toBe("MISSING_OR_NULL_ORIGIN");
  });

  it("does not CSRF-reject a bearer-only sign-out from a native client", async () => {
    // The app clears its session locally first, then revokes with the captured token.
    const response = await app.request("/api/auth/sign-out", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer stale-session-token",
      },
      body: "{}",
    });
    expect(response.status).not.toBe(403);
    const body = (await response.json()) as { code?: string };
    expect(body.code).not.toBe("MISSING_OR_NULL_ORIGIN");
  });

  it("does not CSRF-reject a bearer sign-out that also carries a leftover cookie", async () => {
    const response = await app.request("/api/auth/sign-out", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer stale-session-token",
        Cookie: "better-auth.session_token=stale",
      },
      body: "{}",
    });
    expect(response.status).not.toBe(403);
    const body = (await response.json()) as { code?: string };
    expect(body.code).not.toBe("MISSING_OR_NULL_ORIGIN");
  });
});
