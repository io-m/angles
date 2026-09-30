import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from "node:crypto";

/**
 * A finished `/reframe` response, sealed so the server can hand it back on a retry
 * without being able to read it at rest. The client sends a fresh 32-byte key with
 * every logical operation and keeps it beside the idempotency key. The server uses it
 * once to seal and once to open, and stores neither the key nor the plaintext.
 */

export const REPLAY_KEY_HEADER = "Replay-Key";
export const REPLAY_TTL_MS = 60 * 60 * 1000;

const KEY_BYTES = 32;
const IV_BYTES = 12;
const TAG_BYTES = 16;
const KEY_INFO = "angles:reframe-replay:v1";

export type SealedReplay = {
  iv: string;
  authTag: string;
  ciphertext: string;
};

/** 32 bytes as unpadded base64url, or null. A bad key only disables replay. */
export function parseReplayKey(raw: string | undefined): Buffer | null {
  if (!raw || !/^[A-Za-z0-9_-]{43}$/.test(raw)) {
    return null;
  }
  const key = Buffer.from(raw, "base64url");
  return key.length === KEY_BYTES ? key : null;
}

function derivedKey(clientKey: Buffer, operationId: string): Buffer {
  return Buffer.from(hkdfSync("sha256", clientKey, operationId, KEY_INFO, KEY_BYTES));
}

export function sealReplay(clientKey: Buffer, operationId: string, body: unknown): SealedReplay {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", derivedKey(clientKey, operationId), iv, {
    authTagLength: TAG_BYTES,
  });
  cipher.setAAD(Buffer.from(operationId, "utf8"));
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(body), "utf8"),
    cipher.final(),
  ]);
  return {
    iv: iv.toString("base64url"),
    authTag: cipher.getAuthTag().toString("base64url"),
    ciphertext: ciphertext.toString("base64url"),
  };
}

/** Null when the key is wrong or the row was altered. */
export function openReplay(
  clientKey: Buffer,
  operationId: string,
  sealed: SealedReplay,
): unknown | null {
  try {
    const decipher = createDecipheriv(
      "aes-256-gcm",
      derivedKey(clientKey, operationId),
      Buffer.from(sealed.iv, "base64url"),
      { authTagLength: TAG_BYTES },
    );
    decipher.setAAD(Buffer.from(operationId, "utf8"));
    decipher.setAuthTag(Buffer.from(sealed.authTag, "base64url"));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(sealed.ciphertext, "base64url")),
      decipher.final(),
    ]);
    return JSON.parse(plaintext.toString("utf8")) as unknown;
  } catch {
    return null;
  }
}
