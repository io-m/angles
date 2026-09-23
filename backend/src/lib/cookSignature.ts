import { createHmac, timingSafeEqual } from "node:crypto";
import type { ReframeMeta, Style } from "../types/index.js";

const MIN_KEY_LENGTH = 32;
const VERSION = "v1";

/** The part of a cook's meta that the card stores. `matching` is re-derived on save. */
export type SignableMeta = Omit<ReframeMeta, "matching">;

export type SignableCook = {
  thought: string;
  thoughtOriginal?: string;
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
function cookParts({ thought, thoughtOriginal, meta }: SignableCook): unknown[] {
  return [
    "cook",
    thought.trim(),
    thoughtOriginal?.trim() ?? null,
    meta.category,
    meta.proposedCategory ?? null,
    meta.proposedLabel ?? null,
    meta.tags,
    meta.intensity,
    meta.timeframe,
    meta.emotions,
    meta.safety,
    meta.inputLanguage,
    meta.skippedStyles.map((item) => [item.style, item.reason]),
  ];
}

function resultParts(thought: string, style: Style, reframe: string): unknown[] {
  return ["result", thought.trim(), style, reframe.trim()];
}

export function signCook(cook: SignableCook): string {
  return hmac(cookParts(cook));
}

/** A result is bound to the cleaned thought it answers, so a recook verifies against the same card. */
export function signResult(thought: string, style: Style, reframe: string): string {
  return hmac(resultParts(thought, style, reframe));
}

export function verifyCook(
  cook: SignableCook & {
    signature: string;
    results: { style: Style; reframe: string; signature: string }[];
  },
): boolean {
  if (!matches(signCook(cook), cook.signature)) {
    return false;
  }
  return cook.results.every((item) =>
    matches(signResult(cook.thought, item.style, item.reframe), item.signature),
  );
}
