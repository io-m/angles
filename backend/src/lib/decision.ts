/**
 * The decision call: one structured LLM turn that cleans the thought, chooses
 * continue vs ready, picks the styles worth writing, and produces the matching
 * metadata. Never log the raw model output — it carries the user's thought.
 */

import { z } from "zod";
import {
  CATEGORIES,
  EMOTIONS,
  SAFETY_FLAGS,
  STYLES,
  TIMEFRAMES,
  intensityBand,
  type Category,
  type Emotion,
  type FollowUpAnswer,
  type ReframeMeta,
  type SafetyFlag,
  type SkippedStyle,
  type Style,
  type Timeframe,
} from "../types/index.js";
import { generateJson, LlmError, type LlmModelId } from "./llmClient.js";
import {
  DECISION_FORCE_READY,
  DECISION_PROMPT,
  DECISION_REPAIR_PROMPT,
  SAFETY_FALLBACK_MESSAGE,
  THOUGHT_HARD_MAX_CHARS,
  THOUGHT_HARD_MAX_WORDS,
} from "./prompts.js";

export type ContinueDecision = {
  kind: "continue";
  message: string;
  options: string[];
  safety: SafetyFlag;
  inputLanguage: string;
};

export type ReadyDecision = {
  kind: "ready";
  thought: string;
  thoughtOriginal?: string;
  styles: Style[];
  meta: ReframeMeta;
};

export type Decision = ContinueDecision | ReadyDecision;

export type RunDecisionInput = {
  text: string;
  followUps: FollowUpAnswer[];
  model?: LlmModelId;
  forceReady: boolean;
};

const MAX_OPTIONS = 3;
const MAX_TAGS = 8;
const MAX_EMOTIONS = 3;
const MAX_ECHOED_OUTPUT = 2000;

const skippedStyleSchema = z.object({
  style: z.enum(STYLES),
  reason: z.string().max(400),
});

/**
 * Loose on purpose: unknown enum values are normalised below instead of costing
 * a repair round-trip. Only the shape has to be right here.
 */
const rawDecisionSchema = z.object({
  kind: z.enum(["continue", "ready"]),
  input_language: z.string().max(32).nullish(),
  safety: z.string().max(32).nullish(),
  message: z.string().max(2000).nullish(),
  options: z.array(z.string().max(120)).nullish(),
  thought_en: z.string().max(4000).nullish(),
  thought_original_cleaned: z.string().max(4000).nullish(),
  styles: z.array(z.string().max(32)).nullish(),
  skipped_styles: z.array(skippedStyleSchema).nullish(),
  category: z.string().max(64).nullish(),
  proposed_category: z.string().max(64).nullish(),
  proposed_label: z.string().max(64).nullish(),
  tags: z.array(z.string().max(48)).nullish(),
  intensity: z.number().nullish(),
  timeframe: z.string().max(32).nullish(),
  emotions: z.array(z.string().max(32)).nullish(),
});

export type ParseOptions = {
  /** Reject a `continue` that is not justified by safety (final turn of an exchange). */
  requireReady?: boolean;
};

export class DecisionParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DecisionParseError";
  }
}

export function wordCount(text: string): number {
  return text
    .trim()
    .split(/\s+/)
    .filter((part) => part.length > 0).length;
}

export function composeConversation(text: string, followUps: FollowUpAnswer[]): string {
  if (followUps.length === 0) {
    return text;
  }

  const extras = followUps
    .map((item) => `Then you asked: ${item.question}\nThey answered: ${item.answer}`)
    .join("\n\n");
  return `They first typed: ${text}\n\n${extras}\n\nJudge all of the above together as one thought. They have answered you; do not ask again.`;
}

/** Models sometimes wrap JSON in prose or a fence. Take the outermost object. */
function extractJsonObject(raw: string): string {
  const withoutFence = raw.replace(/```[a-zA-Z]*\s*/g, "").replace(/```/g, "").trim();
  const start = withoutFence.indexOf("{");
  const end = withoutFence.lastIndexOf("}");
  if (start === -1 || end <= start) {
    throw new DecisionParseError("decision reply was not JSON");
  }
  return withoutFence.slice(start, end + 1);
}

function slugify(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function titleCase(slug: string): string {
  return slug
    .split("_")
    .filter((part) => part.length > 0)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function cleanString(value: string | null | undefined): string | undefined {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeSafety(value: string | null | undefined): SafetyFlag {
  const candidate = value?.trim().toLowerCase() ?? "";
  return (SAFETY_FLAGS as readonly string[]).includes(candidate)
    ? (candidate as SafetyFlag)
    : "none";
}

function normalizeLanguage(value: string | null | undefined): string {
  const candidate = cleanString(value)?.toLowerCase();
  if (!candidate || !/^[a-z]{2,3}(-[a-z0-9]{2,8})*$/.test(candidate)) {
    return "en";
  }
  return candidate;
}

function normalizeCategory(value: string | null | undefined): {
  category: Category;
  proposedCategory?: string;
  proposedLabel?: string;
} {
  const candidate = slugify(value ?? "");
  if ((CATEGORIES as readonly string[]).includes(candidate)) {
    return { category: candidate as Category };
  }

  if (candidate.length === 0) {
    return { category: "other" };
  }

  // An off-catalog answer is a proposal, not a failure.
  return { category: "other", proposedCategory: candidate, proposedLabel: titleCase(candidate) };
}

function normalizeTags(values: readonly string[] | null | undefined): string[] {
  const tags: string[] = [];
  for (const value of values ?? []) {
    const slug = slugify(value);
    if (slug.length > 0 && !tags.includes(slug)) {
      tags.push(slug);
    }
    if (tags.length === MAX_TAGS) {
      break;
    }
  }
  return tags;
}

function normalizeEmotions(values: readonly string[] | null | undefined): Emotion[] {
  const emotions: Emotion[] = [];
  for (const value of values ?? []) {
    const candidate = value.trim().toLowerCase();
    if ((EMOTIONS as readonly string[]).includes(candidate) && !emotions.includes(candidate as Emotion)) {
      emotions.push(candidate as Emotion);
    }
    if (emotions.length === MAX_EMOTIONS) {
      break;
    }
  }
  return emotions;
}

function normalizeTimeframe(value: string | null | undefined): Timeframe {
  const candidate = value?.trim().toLowerCase() ?? "";
  return (TIMEFRAMES as readonly string[]).includes(candidate)
    ? (candidate as Timeframe)
    : "ongoing";
}

function normalizeIntensity(value: number | null | undefined): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return 3;
  }
  return Math.min(5, Math.max(1, Math.round(value)));
}

function normalizeStyles(values: readonly string[] | null | undefined): Style[] {
  const styles: Style[] = [];
  for (const value of values ?? []) {
    const candidate = value.trim().toLowerCase();
    if ((STYLES as readonly string[]).includes(candidate) && !styles.includes(candidate as Style)) {
      styles.push(candidate as Style);
    }
  }
  return styles;
}

function normalizeSkipped(values: readonly SkippedStyle[] | null | undefined): SkippedStyle[] {
  const skipped: SkippedStyle[] = [];
  for (const value of values ?? []) {
    const reason = cleanString(value.reason);
    if (reason && !skipped.some((item) => item.style === value.style)) {
      skipped.push({ style: value.style, reason });
    }
  }
  return skipped;
}

export function parseDecision(raw: string, options: ParseOptions = {}): Decision {
  const parsed = rawDecisionSchema.safeParse(JSON.parse(extractJsonObject(raw)));
  if (!parsed.success) {
    throw new DecisionParseError("decision JSON did not match the schema");
  }

  const value = parsed.data;
  const safety = normalizeSafety(value.safety);

  if (value.kind === "continue") {
    const message = cleanString(value.message);
    if (!message) {
      throw new DecisionParseError("continue decision had no message");
    }
    if (options.requireReady && safety === "none") {
      throw new DecisionParseError("expected a ready decision on the final turn");
    }

    const chips = (value.options ?? [])
      .map((option) => option.trim())
      .filter((option) => option.length > 0)
      .slice(0, MAX_OPTIONS);

    return {
      kind: "continue",
      message,
      options: safety === "none" ? chips : [],
      safety,
      inputLanguage: normalizeLanguage(value.input_language),
    };
  }

  const thought = cleanString(value.thought_en);
  if (!thought) {
    throw new DecisionParseError("ready decision had no cleaned thought");
  }
  if (wordCount(thought) > THOUGHT_HARD_MAX_WORDS || thought.length > THOUGHT_HARD_MAX_CHARS) {
    throw new DecisionParseError("cleaned thought was far over the card budget");
  }

  const skippedStyles = normalizeSkipped(value.skipped_styles);
  const requested = normalizeStyles(value.styles);
  const styles =
    requested.length > 0
      ? requested
      : STYLES.filter((style) => !skippedStyles.some((item) => item.style === style));
  if (styles.length === 0) {
    throw new DecisionParseError("ready decision chose no styles");
  }

  const { category, proposedCategory, proposedLabel } = normalizeCategory(value.category);
  const intensity = normalizeIntensity(value.intensity);
  const tags = normalizeTags(value.tags);

  const explicitProposed = cleanString(value.proposed_category);
  const proposal =
    category === "other"
      ? explicitProposed
        ? { slug: slugify(explicitProposed), label: cleanString(value.proposed_label) }
        : proposedCategory
          ? { slug: proposedCategory, label: proposedLabel }
          : undefined
      : undefined;

  const meta: ReframeMeta = {
    category,
    ...(proposal?.slug
      ? {
          proposedCategory: proposal.slug,
          proposedLabel: proposal.label ?? titleCase(proposal.slug),
        }
      : {}),
    tags,
    intensity,
    timeframe: normalizeTimeframe(value.timeframe),
    emotions: normalizeEmotions(value.emotions),
    safety,
    inputLanguage: normalizeLanguage(value.input_language),
    skippedStyles,
    matching: { category, tags, intensityBand: intensityBand(intensity) },
  };

  const original = cleanString(value.thought_original_cleaned);

  return {
    kind: "ready",
    thought,
    thoughtOriginal: original && original !== thought ? original : undefined,
    styles,
    meta,
  };
}

/** A reframe must never ship for a thought the model itself flagged as unsafe. */
function refuseUnsafeReframe(decision: Decision): Decision {
  if (decision.kind === "ready" && decision.meta.safety !== "none") {
    return {
      kind: "continue",
      message: SAFETY_FALLBACK_MESSAGE,
      options: [],
      safety: decision.meta.safety,
      inputLanguage: decision.meta.inputLanguage,
    };
  }
  return decision;
}

export async function runDecision(input: RunDecisionInput): Promise<Decision> {
  const systemPrompt = input.forceReady
    ? `${DECISION_PROMPT}\n\n${DECISION_FORCE_READY}`
    : DECISION_PROMPT;
  const conversation = composeConversation(input.text, input.followUps);

  const first = await generateJson({
    text: conversation,
    systemPrompt,
    model: input.model,
  });

  try {
    return refuseUnsafeReframe(parseDecision(first, { requireReady: input.forceReady }));
  } catch (error) {
    if (!(error instanceof DecisionParseError) && !(error instanceof SyntaxError)) {
      throw error;
    }
  }

  const repaired = await generateJson({
    text: `${conversation}\n\n---\nYour previous reply, which was rejected:\n${first.slice(0, MAX_ECHOED_OUTPUT)}`,
    systemPrompt: `${systemPrompt}\n\n${DECISION_REPAIR_PROMPT}`,
    model: input.model,
  });

  try {
    // The second pass accepts a `continue` even on a forced turn: a stubborn
    // model gets to keep the conversation rather than fail the request.
    return refuseUnsafeReframe(parseDecision(repaired));
  } catch (error) {
    if (error instanceof DecisionParseError || error instanceof SyntaxError) {
      throw new LlmError("Decision reply could not be parsed");
    }
    throw error;
  }
}
