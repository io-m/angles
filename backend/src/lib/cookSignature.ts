import { createHmac, timingSafeEqual } from "node:crypto";
import type { ReframeMeta, Style } from "../types/index.js";

const MIN_KEY_LENGTH = 32;
const VERSION = "v5";

/** The part of a cook's meta that the card stores. `matching` is re-derived on save. */
export type SignableMeta = Omit<ReframeMeta, "matching">;

export type SignableCook = {
  /** The account that cooked it. A cook signed for one account does not save under another. */
  ownerId: string;
  thought: string;
  thoughtOriginal?: string;
  /** The writer the server routed the cook to. A recook may be answered by another. */
  model: string;
  meta: SignableMeta;
};

function signingKey(): string {
  const key = process.env.COOK_SIGNING_KEY;
  if (!key || key.length < MIN_KEY_LENGTH) {
    throw new Error(`COOK_SIGNING_KEY must be set to at least ${MIN_KEY_LENGTH} characters`);
  }
  return key;
}

/** Fails startup instead of the first save. */
export function assertCookSigningKey(): void {
  signingKey();
}

function hmac(parts: unknown[]): string {
  return createHmac("sha256", signingKey()).update(JSON.stringify([VERSION, ...parts])).digest("base64url");
}

function matches(expected: string, actual: string): boolean {
  const left = Buffer.from(expected);
  const right = Buffer.from(actual);
  return left.length === right.length && timingSafeEqual(left, right);
}

// Values are trimmed the same way `POST /cards` trims them, so a signed cook verifies after validation.
function cookParts({ ownerId, thought, thoughtOriginal, model, meta }: SignableCook): unknown[] {
  return [
    "cook",
    ownerId.toLowerCase(),
    thought.trim(),
    thoughtOriginal?.trim() ?? null,
    model,
    meta.category,
    meta.proposedCategory ?? null,
    meta.proposedLabel ?? null,
    meta.tags,
    meta.intensity,
    meta.timeframe,
    meta.emotions,
    meta.distortions,
    meta.safety,
    meta.inputLanguage,
    meta.skippedStyles.map((item) => [item.style, item.reason]),
  ];
}

function resultParts(
  ownerId: string,
  thought: string,
  style: Style,
  reframe: string,
  reframeOriginal: string | undefined,
): unknown[] {
  return ["result", ownerId.toLowerCase(), thought.trim(), style, reframe.trim(), reframeOriginal?.trim() ?? null];
}

export function signCook(cook: SignableCook): string {
  return hmac(cookParts(cook));
}

/**
 * A result is bound to the cleaned thought it answers, so a recook verifies against the
 * same card, and to both versions of the answer, so neither can be swapped on save.
 */
export function signResult(
  ownerId: string,
  thought: string,
  style: Style,
  reframe: string,
  reframeOriginal?: string,
): string {
  return hmac(resultParts(ownerId, thought, style, reframe, reframeOriginal));
}

export function verifyCook(
  cook: SignableCook & {
    signature: string;
    results: { style: Style; reframe: string; reframeOriginal?: string; signature: string }[];
  },
): boolean {
  if (!matches(signCook(cook), cook.signature)) {
    return false;
  }
  return cook.results.every((item) =>
    matches(
      signResult(cook.ownerId, cook.thought, item.style, item.reframe, item.reframeOriginal),
      item.signature,
    ),
  );
}
