import { z } from "zod";
import {
  CATEGORIES,
  DISTORTIONS,
  EMOTIONS,
  SAFETY_FLAGS,
  STYLES,
  TIMEFRAMES,
} from "../types/index.js";

const skippedStyleSchema = z.object({
  style: z.enum(STYLES),
  reason: z.string().min(1).max(400),
});

/**
 * The meta of a signed cook as the phone echoes it back to `POST /cards` or a recook.
 * `matching` is dropped: the server derives it again.
 */
export const signedMetaSchema = z
  .object({
    category: z.enum(CATEGORIES),
    proposedCategory: z.string().min(1).max(64).optional(),
    proposedLabel: z.string().min(1).max(64).optional(),
    tags: z.array(z.string().max(48)).max(8).default([]),
    intensity: z.number().int().min(1).max(5),
    timeframe: z.enum(TIMEFRAMES),
    emotions: z.array(z.enum(EMOTIONS)).max(3),
    distortions: z.array(z.enum(DISTORTIONS)).max(2).default([]),
    safety: z.enum(SAFETY_FLAGS),
    inputLanguage: z.string().min(1).max(32),
    skippedStyles: z.array(skippedStyleSchema).default([]),
    matching: z.unknown().optional(),
  })
  .transform(({ matching: _matching, ...rest }) => rest);
