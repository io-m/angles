import { describe, expect, it } from "vitest";
import { openReplay, parseReplayKey, sealReplay } from "./reframeReplay.js";

const OPERATION_ID = "00000000-0000-4000-8000-000000000777";
const KEY = parseReplayKey(Buffer.alloc(32, 5).toString("base64url"))!;
const BODY = { kind: "ready", thought: "I keep replaying the interview." };

describe("reframe replay", () => {
  it("accepts only 32 random bytes as unpadded base64url", () => {
    expect(KEY).toHaveLength(32);
    expect(parseReplayKey(undefined)).toBeNull();
    expect(parseReplayKey("")).toBeNull();
    expect(parseReplayKey(Buffer.alloc(16, 5).toString("base64url"))).toBeNull();
    expect(parseReplayKey(`${Buffer.alloc(32, 5).toString("base64url")}=`)).toBeNull();
    expect(parseReplayKey(Buffer.alloc(32, 5).toString("base64"))).toBeNull();
  });

  it("round-trips without the text appearing in what is stored", () => {
    const sealed = sealReplay(KEY, OPERATION_ID, BODY);
    expect(JSON.stringify(sealed)).not.toContain("interview");
    expect(openReplay(KEY, OPERATION_ID, sealed)).toEqual(BODY);
  });

  it("does not open under another key, another operation, or after tampering", () => {
    const sealed = sealReplay(KEY, OPERATION_ID, BODY);
    const otherKey = Buffer.alloc(32, 6);
    expect(openReplay(otherKey, OPERATION_ID, sealed)).toBeNull();
    expect(openReplay(KEY, "00000000-0000-4000-8000-000000000778", sealed)).toBeNull();

    const bytes = Buffer.from(sealed.ciphertext, "base64url");
    bytes[0] = (bytes[0] ?? 0) ^ 1;
    expect(
      openReplay(KEY, OPERATION_ID, { ...sealed, ciphertext: bytes.toString("base64url") }),
    ).toBeNull();
    expect(openReplay(KEY, OPERATION_ID, { ...sealed, authTag: "AAAA" })).toBeNull();
  });

  it("uses a fresh IV for every seal", () => {
    const first = sealReplay(KEY, OPERATION_ID, BODY);
    const second = sealReplay(KEY, OPERATION_ID, BODY);
    expect(first.iv).not.toBe(second.iv);
    expect(first.ciphertext).not.toBe(second.ciphertext);
  });
});
