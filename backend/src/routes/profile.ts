import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { z } from "zod";
import { listFollowing } from "../db/follows.js";
import { getUserById, setOwnerAvatar, updateOwnerInitials, deleteOwnerAccount } from "../db/users.js";
import { getOwnerUserId, requireAuth } from "../lib/authStub.js";
import { avatarObjectKey, avatarUrlFor, initialsFromDisplayName } from "../lib/avatarUrl.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";
import {
  deleteAvatar,
  getAvatar,
  putAvatar,
  StorageUnavailableError,
} from "../lib/objectStorage.js";
import type { FollowingListResponse, ProfileBody, SessionBody } from "../types/index.js";

const MAX_AVATAR_BYTES = Math.floor(1.5 * 1024 * 1024);

const patchProfileSchema = z.object({
  displayName: z.string().max(40),
});

function profileBody(user: { id: string; initials: string; avatarKey: string | null }): ProfileBody {
  const body: ProfileBody = { initials: user.initials };
  const avatarUrl = avatarUrlFor(user.id, user.avatarKey);
  if (avatarUrl) {
    body.avatarUrl = avatarUrl;
  }
  return body;
}

function isJpeg(bytes: Uint8Array): boolean {
  return bytes.byteLength >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

function storageFailure(error: unknown): { error: string; code: "STORAGE_UNAVAILABLE"; status: 503 } | null {
  if (error instanceof StorageUnavailableError) {
    return { error: "Photo storage is unavailable", code: "STORAGE_UNAVAILABLE", status: 503 };
  }
  return null;
}

export const profileRoute = new Hono();

profileRoute.get("/session", requireAuth, async (c) => {
  const user = await getUserById(getOwnerUserId());
  if (!user) {
    return c.json(errorBody("Sign in required", "UNAUTHENTICATED"), 401);
  }
  const body: SessionBody = {
    id: user.id,
    initials: user.initials,
    name: user.name,
    tasteCompletedAt: user.tasteCompletedAt ? user.tasteCompletedAt.toISOString() : null,
  };
  const avatarUrl = avatarUrlFor(user.id, user.avatarKey);
  if (avatarUrl) {
    body.avatarUrl = avatarUrl;
  }
  return c.json(body);
});

profileRoute.delete("/", requireAuth, async (c) => {
  const ownerId = getOwnerUserId();
  const current = await getUserById(ownerId);
  if (!current) {
    return c.json(errorBody("Profile was not found", "NOT_FOUND"), 404);
  }
  if (current.avatarKey) {
    try {
      await deleteAvatar(current.avatarKey);
    } catch (error) {
      console.error("account_delete_avatar_failed", {
        name: error instanceof Error ? error.name : "error",
      });
    }
  }
  await deleteOwnerAccount();
  return c.body(null, 204);
});

profileRoute.get("/following", requireAuth, async (c) => {
  const body: FollowingListResponse = { users: await listFollowing() };
  return c.json(body);
});

profileRoute.patch(
  "/",
  requireAuth,
  zValidator("json", patchProfileSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    const { displayName } = c.req.valid("json");
    const initials = initialsFromDisplayName(displayName);
    if (!initials) {
      const current = await getUserById(getOwnerUserId());
      if (!current) {
        return c.json(errorBody("Profile was not found", "NOT_FOUND"), 404);
      }
      return c.json(profileBody(current));
    }
    const updated = await updateOwnerInitials(initials);
    return c.json(profileBody(updated));
  },
);

profileRoute.put(
  "/avatar",
  requireAuth,
  bodyLimit({
    maxSize: MAX_AVATAR_BYTES,
    onError: (c) => c.json(errorBody("Photo is too large", "PAYLOAD_TOO_LARGE"), 413),
  }),
  async (c) => {
    const contentType = c.req.header("content-type") ?? "";
    if (!contentType.startsWith("image/jpeg")) {
      return c.json(errorBody("Photo must be a JPEG", "VALIDATION_ERROR"), 400);
    }

    const bytes = new Uint8Array(await c.req.arrayBuffer());
    if (bytes.byteLength === 0 || !isJpeg(bytes)) {
      return c.json(errorBody("Photo must be a JPEG", "VALIDATION_ERROR"), 400);
    }

    const ownerId = getOwnerUserId();
    const previous = await getUserById(ownerId);
    if (!previous) {
      return c.json(errorBody("Profile was not found", "NOT_FOUND"), 404);
    }

    const key = avatarObjectKey(ownerId);
    try {
      await putAvatar(key, bytes);
    } catch (error) {
      const unavailable = storageFailure(error);
      if (unavailable) {
        return c.json(errorBody(unavailable.error, unavailable.code), unavailable.status);
      }
      console.error("avatar_put_failed", { name: error instanceof Error ? error.name : "error" });
      return c.json(errorBody("Couldn't store that photo", "STORAGE_UNAVAILABLE"), 503);
    }

    const updated = await setOwnerAvatar(key);
    if (previous.avatarKey && previous.avatarKey !== key) {
      try {
        await deleteAvatar(previous.avatarKey);
      } catch (error) {
        console.error("avatar_replace_delete_failed", {
          name: error instanceof Error ? error.name : "error",
        });
      }
    }
    return c.json(profileBody(updated));
  },
);

profileRoute.delete("/avatar", requireAuth, async (c) => {
  const ownerId = getOwnerUserId();
  const current = await getUserById(ownerId);
  if (!current) {
    return c.json(errorBody("Profile was not found", "NOT_FOUND"), 404);
  }
  if (!current.avatarKey) {
    return c.json(profileBody(current));
  }

  try {
    await deleteAvatar(current.avatarKey);
  } catch (error) {
    const unavailable = storageFailure(error);
    if (unavailable) {
      return c.json(errorBody(unavailable.error, unavailable.code), unavailable.status);
    }
    console.error("avatar_delete_failed", { name: error instanceof Error ? error.name : "error" });
    return c.json(errorBody("Couldn't remove that photo", "STORAGE_UNAVAILABLE"), 503);
  }

  const updated = await setOwnerAvatar(null);
  return c.json(profileBody(updated));
});

export const avatarsRoute = new Hono();

avatarsRoute.get("/:userId", async (c) => {
  const userId = c.req.param("userId");
  if (!z.uuid().safeParse(userId).success) {
    return c.json(errorBody("Not found", "NOT_FOUND"), 404);
  }

  const user = await getUserById(userId);
  if (!user?.avatarKey) {
    return c.json(errorBody("Not found", "NOT_FOUND"), 404);
  }

  let bytes: Uint8Array | null;
  try {
    bytes = await getAvatar(user.avatarKey);
  } catch (error) {
    const unavailable = storageFailure(error);
    if (unavailable) {
      return c.json(errorBody(unavailable.error, unavailable.code), unavailable.status);
    }
    console.error("avatar_get_failed", { name: error instanceof Error ? error.name : "error" });
    return c.json(errorBody("Couldn't load that photo", "STORAGE_UNAVAILABLE"), 503);
  }

  if (!bytes) {
    return c.json(errorBody("Not found", "NOT_FOUND"), 404);
  }

  return c.body(Buffer.from(bytes), 200, {
    "Content-Type": "image/jpeg",
    "Cache-Control": "public, max-age=86400",
  });
});
