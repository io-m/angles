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
}));

vi.mock("../db/follows.js", () => ({
  followUser: vi.fn(),
  unfollowUser: vi.fn(),
  followedAuthorIds: vi.fn(),
  listFollowing: vi.fn(),
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
const { listFollowing } = await import("../db/follows.js");
const { getUserById, setOwnerAvatar, updateOwnerInitials } = await import("../db/users.js");
const { deleteAvatar, getAvatar, putAvatar, StorageUnavailableError } = await import("../lib/objectStorage.js");

const app = createApp();

const owner = {
  id: DEV_USER_ID,
  initials: "JM",
  avatarKey: null as string | null,
  createdAt: new Date("2026-09-10T12:00:00.000Z"),
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

  it("returns not found when a user has no photo", async () => {
    const response = await app.request(`/avatars/${DEV_USER_ID}`);
    expect(response.status).toBe(404);
    expect(getAvatar).not.toHaveBeenCalled();
  });
});
