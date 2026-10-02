import { beforeEach, describe, expect, it, vi } from "vitest";
import { DEV_USER_ID } from "../lib/authStub.js";

vi.mock("../db/client.js", () => {
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

vi.mock("../db/users.js", () => ({
  getUserById: vi.fn(),
  setOwnerAvatar: vi.fn(),
  updateOwnerInitials: vi.fn(),
  deleteOwnerAccount: vi.fn(),
  getOwnerAppleSubject: vi.fn(async () => "apple-sub-owner"),
  acceptOwnerTerms: vi.fn(),
}));

vi.mock("../lib/appleRevoke.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../lib/appleRevoke.js")>();
  return {
    ...actual,
    exchangeAppleAuthorizationCode: vi.fn(),
    revokeAppleGrant: vi.fn(),
  };
});

vi.mock("../db/follows.js", () => ({
  followUser: vi.fn(),
  unfollowUser: vi.fn(),
  followedAuthorIds: vi.fn(),
  listFollowing: vi.fn(),
}));

vi.mock("../db/communitySafety.js", () => ({
  listBlockedUsers: vi.fn(),
  blockUser: vi.fn(),
  unblockUser: vi.fn(),
  usersAreBlocked: vi.fn(),
  reportCard: vi.fn(),
}));

vi.mock("../db/metering.js", () => ({
  getUsageSummary: vi.fn(),
}));

vi.mock("../lib/objectStorage.js", () => {
  class StorageUnavailableError extends Error {
    constructor() {
      super("Object storage is not configured");
      this.name = "StorageUnavailableError";
    }
  }
  return {
    StorageUnavailableError,
    putAvatar: vi.fn(),
    deleteAvatar: vi.fn(),
    getAvatar: vi.fn(),
  };
});

const { createApp } = await import("../app.js");
const { listBlockedUsers } = await import("../db/communitySafety.js");
const { listFollowing } = await import("../db/follows.js");
const { getUsageSummary } = await import("../db/metering.js");
const { acceptOwnerTerms, getUserById, setOwnerAvatar, updateOwnerInitials, deleteOwnerAccount } =
  await import("../db/users.js");
const { deleteAvatar, getAvatar, putAvatar, StorageUnavailableError } = await import("../lib/objectStorage.js");
const { AppleRevokeError, exchangeAppleAuthorizationCode, revokeAppleGrant } = await import(
  "../lib/appleRevoke.js"
);

const app = createApp();

const owner = {
  id: DEV_USER_ID,
  initials: "JM",
  name: "JM",
  email: "dev@angles.invalid",
  emailVerified: false,
  image: null as string | null,
  avatarKey: null as string | null,
  tasteCompletedAt: null as Date | null,
  tasteConsumedAt: null as Date | null,
  termsAcceptedAt: null as Date | null,
  publishingSuspendedAt: null as Date | null,
  createdAt: new Date("2026-09-10T12:00:00.000Z"),
  updatedAt: new Date("2026-09-10T12:00:00.000Z"),
};

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

function user(overrides: Partial<typeof owner> = {}) {
  return { ...owner, ...overrides };
}

describe("profile avatar", () => {
  beforeEach(() => {
    vi.mocked(getUserById).mockReset();
    vi.mocked(setOwnerAvatar).mockReset();
    vi.mocked(updateOwnerInitials).mockReset();
    vi.mocked(putAvatar).mockReset();
    vi.mocked(deleteAvatar).mockReset();
    vi.mocked(getAvatar).mockReset();
    vi.mocked(getUserById).mockResolvedValue(user());
    vi.mocked(getUsageSummary).mockResolvedValue({
      creditsGranted: 600,
      creditsRemaining: 594,
      periodStart: "2026-09-01T00:00:00.000Z",
      periodEnd: "2026-10-01T00:00:00.000Z",
      resetsAt: "2026-10-01T00:00:00.000Z",
      warning: "normal",
      creditCost: 1,
      plan: "membership",
    });
    vi.mocked(putAvatar).mockResolvedValue(undefined);
    vi.mocked(deleteAvatar).mockResolvedValue(undefined);
  });

  it("writes initials from a display name", async () => {
    vi.mocked(updateOwnerInitials).mockResolvedValue(user({ initials: "AL" }));
    const response = await app.request("/profile", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ displayName: "Ada Lovelace" }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ initials: "AL" });
    expect(updateOwnerInitials).toHaveBeenCalledWith("AL");
  });

  it("keeps initials when the name is cleared", async () => {
    const response = await app.request("/profile", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ displayName: "   " }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ initials: "JM" });
    expect(updateOwnerInitials).not.toHaveBeenCalled();
  });

  it("stores a jpeg and returns a cache-busted avatar path", async () => {
    vi.mocked(setOwnerAvatar).mockImplementation(async (key) => user({ avatarKey: key }));
    const response = await app.request("/profile/avatar", {
      method: "PUT",
      headers: { "Content-Type": "image/jpeg" },
      body: jpeg,
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { initials: string; avatarUrl: string };
    expect(body.initials).toBe("JM");
    expect(body.avatarUrl).toMatch(new RegExp(`^/avatars/${DEV_USER_ID}\\?v=\\d+$`));
    expect(putAvatar).toHaveBeenCalledOnce();
    expect(setOwnerAvatar).toHaveBeenCalledWith(expect.stringMatching(new RegExp(`^avatars/${DEV_USER_ID}-\\d+\\.jpg$`)));
  });

  it("rejects a body that is not a jpeg", async () => {
    const response = await app.request("/profile/avatar", {
      method: "PUT",
      headers: { "Content-Type": "image/jpeg" },
      body: new Uint8Array([1, 2, 3, 4]),
    });
    expect(response.status).toBe(400);
    expect(putAvatar).not.toHaveBeenCalled();
  });

  it("reports storage as unavailable", async () => {
    vi.mocked(putAvatar).mockRejectedValue(new StorageUnavailableError());
    const response = await app.request("/profile/avatar", {
      method: "PUT",
      headers: { "Content-Type": "image/jpeg" },
      body: jpeg,
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({
      error: "Photo storage is unavailable",
      code: "STORAGE_UNAVAILABLE",
    });
    expect(setOwnerAvatar).not.toHaveBeenCalled();
  });

  it("removes the stored photo", async () => {
    vi.mocked(getUserById).mockResolvedValue(user({ avatarKey: `avatars/${DEV_USER_ID}-1.jpg` }));
    vi.mocked(setOwnerAvatar).mockResolvedValue(user({ avatarKey: null }));
    const response = await app.request("/profile/avatar", { method: "DELETE" });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ initials: "JM" });
    expect(deleteAvatar).toHaveBeenCalledWith(`avatars/${DEV_USER_ID}-1.jpg`);
    expect(setOwnerAvatar).toHaveBeenCalledWith(null);
  });

  it("serves the jpeg for a user who has one", async () => {
    vi.mocked(getUserById).mockResolvedValue(user({ avatarKey: `avatars/${DEV_USER_ID}-1.jpg` }));
    vi.mocked(getAvatar).mockResolvedValue(jpeg);
    const response = await app.request(`/avatars/${DEV_USER_ID}`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/jpeg");
    expect(response.headers.get("cache-control")).toBe("public, max-age=86400");
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(jpeg);
  });

  it("returns the people the viewer follows", async () => {
    vi.mocked(listFollowing).mockResolvedValue([
      { id: "00000000-0000-4000-8000-000000000099", initials: "AL", following: true },
    ]);
    const response = await app.request("/profile/following");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      users: [{ id: "00000000-0000-4000-8000-000000000099", initials: "AL", following: true }],
    });
  });

  it("returns the people the viewer blocked", async () => {
    vi.mocked(listBlockedUsers).mockResolvedValue([
      { id: "00000000-0000-4000-8000-000000000099", initials: "AL", following: false },
    ]);
    const response = await app.request("/profile/blocks");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      users: [{ id: "00000000-0000-4000-8000-000000000099", initials: "AL", following: false }],
    });
  });

  it("returns not found when a user has no photo", async () => {
    const response = await app.request(`/avatars/${DEV_USER_ID}`);
    expect(response.status).toBe(404);
    expect(getAvatar).not.toHaveBeenCalled();
  });

  it("returns the session for the signed-in user", async () => {
    const tasted = new Date("2026-09-25T12:00:00.000Z");
    vi.mocked(getUserById).mockResolvedValue(user({ tasteCompletedAt: tasted }));
    const response = await app.request("/profile/session");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      id: DEV_USER_ID,
      initials: "JM",
      name: "JM",
      tasteCompletedAt: tasted.toISOString(),
      tasteConsumedAt: null,
      termsAcceptedAt: null,
    });
  });

  it("records the Terms acceptance and reports it in the session", async () => {
    const accepted = new Date("2026-10-02T12:00:00.000Z");
    vi.mocked(acceptOwnerTerms).mockResolvedValueOnce(accepted);
    const put = await app.request("/profile/terms", { method: "PUT" });
    expect(put.status).toBe(200);
    expect(await put.json()).toEqual({ termsAcceptedAt: accepted.toISOString() });

    vi.mocked(getUserById).mockResolvedValue(user({ termsAcceptedAt: accepted }));
    const session = await app.request("/profile/session");
    expect(await session.json()).toMatchObject({ termsAcceptedAt: accepted.toISOString() });
  });

  it("returns taste consumption before the ready card is saved", async () => {
    const consumed = new Date("2026-09-25T12:00:00.000Z");
    vi.mocked(getUserById).mockResolvedValue(user({ tasteConsumedAt: consumed }));
    const response = await app.request("/profile/session");
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      tasteCompletedAt: null,
      tasteConsumedAt: consumed.toISOString(),
    });
  });

  it("returns only credit availability from usage diagnostics", async () => {
    const response = await app.request("/profile/usage");
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      creditsGranted: 600,
      creditsRemaining: 594,
      creditCost: 1,
    });
    expect(body.tokens).toBeUndefined();
    expect(body.cost).toBeUndefined();
  });

  it("rejects a missing session", async () => {
    const response = await app.request("/profile/session", {
      headers: { Authorization: "Bearer none" },
    });
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({ code: "UNAUTHENTICATED" });
  });

  it("deletes the account", async () => {
    vi.mocked(deleteOwnerAccount).mockReset();
    vi.mocked(deleteOwnerAccount).mockResolvedValue(undefined);
    const response = await app.request("/profile", { method: "DELETE" });
    expect(response.status).toBe(204);
    expect(deleteOwnerAccount).toHaveBeenCalledOnce();
  });

  it("retries a failed photo delete before deleting the account", async () => {
    vi.mocked(deleteOwnerAccount).mockReset();
    vi.mocked(deleteOwnerAccount).mockResolvedValue(undefined);
    vi.mocked(getUserById).mockResolvedValue(user({ avatarKey: `avatars/${DEV_USER_ID}-1.jpg` }));
    vi.mocked(deleteAvatar)
      .mockRejectedValueOnce(new Error("timeout"))
      .mockResolvedValueOnce(undefined);
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => undefined);

    const response = await app.request("/profile", { method: "DELETE" });

    expect(response.status).toBe(204);
    expect(deleteAvatar).toHaveBeenCalledTimes(2);
    expect(deleteOwnerAccount).toHaveBeenCalledOnce();
    errorLog.mockRestore();
  });

  it("keeps the account when the photo cannot be deleted", async () => {
    vi.mocked(deleteOwnerAccount).mockReset();
    vi.mocked(getUserById).mockResolvedValue(user({ avatarKey: `avatars/${DEV_USER_ID}-1.jpg` }));
    vi.mocked(deleteAvatar).mockRejectedValue(new Error("timeout"));
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => undefined);

    const response = await app.request("/profile", { method: "DELETE" });

    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ code: "STORAGE_UNAVAILABLE" });
    expect(deleteAvatar).toHaveBeenCalledTimes(3);
    expect(deleteOwnerAccount).not.toHaveBeenCalled();
    errorLog.mockRestore();
  });

  describe("Sign in with Apple revocation", () => {
    const grant = { subject: "apple-sub-owner", token: "r.token", tokenTypeHint: "refresh_token" as const };
    const deleteWith = (body: string) =>
      app.request("/profile", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body,
      });

    beforeEach(() => {
      vi.mocked(deleteOwnerAccount).mockReset();
      vi.mocked(deleteOwnerAccount).mockResolvedValue(undefined);
      vi.mocked(exchangeAppleAuthorizationCode).mockReset();
      vi.mocked(revokeAppleGrant).mockReset();
    });

    it("trades the code first, deletes, then revokes", async () => {
      vi.mocked(exchangeAppleAuthorizationCode).mockResolvedValue(grant);
      vi.mocked(revokeAppleGrant).mockResolvedValue(undefined);

      const response = await deleteWith(JSON.stringify({ appleAuthorizationCode: "c.code" }));

      expect(response.status).toBe(204);
      expect(exchangeAppleAuthorizationCode).toHaveBeenCalledWith("c.code");
      expect(revokeAppleGrant).toHaveBeenCalledWith(grant);
      expect(vi.mocked(deleteOwnerAccount).mock.invocationCallOrder[0]).toBeLessThan(
        vi.mocked(revokeAppleGrant).mock.invocationCallOrder[0] ?? 0,
      );
    });

    it("refuses a code for another Apple ID and deletes nothing", async () => {
      vi.mocked(exchangeAppleAuthorizationCode).mockResolvedValue({ ...grant, subject: "someone-else" });

      const response = await deleteWith(JSON.stringify({ appleAuthorizationCode: "c.code" }));

      expect(response.status).toBe(400);
      expect(deleteOwnerAccount).not.toHaveBeenCalled();
      expect(revokeAppleGrant).not.toHaveBeenCalled();
    });

    it("still deletes when Apple is unreachable", async () => {
      vi.mocked(exchangeAppleAuthorizationCode).mockRejectedValue(new AppleRevokeError("exchange", 503));
      const errorLog = vi.spyOn(console, "error").mockImplementation(() => undefined);

      const response = await deleteWith(JSON.stringify({ appleAuthorizationCode: "c.code" }));

      expect(response.status).toBe(204);
      expect(deleteOwnerAccount).toHaveBeenCalledOnce();
      expect(revokeAppleGrant).not.toHaveBeenCalled();
      errorLog.mockRestore();
    });

    it("keeps the deletion when revoke fails afterwards", async () => {
      vi.mocked(exchangeAppleAuthorizationCode).mockResolvedValue(grant);
      vi.mocked(revokeAppleGrant).mockRejectedValue(new AppleRevokeError("revoke", 500));
      const errorLog = vi.spyOn(console, "error").mockImplementation(() => undefined);

      const response = await deleteWith(JSON.stringify({ appleAuthorizationCode: "c.code" }));

      expect(response.status).toBe(204);
      expect(deleteOwnerAccount).toHaveBeenCalledOnce();
      errorLog.mockRestore();
    });

    it("rejects malformed JSON before touching anything", async () => {
      const response = await deleteWith("{nope");
      expect(response.status).toBe(400);
      expect(await response.json()).toMatchObject({ code: "INVALID_JSON" });
      expect(deleteOwnerAccount).not.toHaveBeenCalled();
    });
  });
});
