/**
 * The decision call: one structured LLM turn that cleans the thought, chooses
 * continue vs ready, picks the styles worth writing, and produces the matching
 * metadata. Never log the raw model output — it carries the user's thought.
 */

import { z } from "zod";
import {
  CATEGORIES,
  DISTORTIONS,
  EMOTIONS,
  SAFETY_FLAGS,
  STYLES,
  TIMEFRAMES,
  matchingFor,
  type Category,
  type Distortion,
  type Emotion,
  type FollowUpAnswer,
  type ReframeMeta,
  type SafetyFlag,
  type SkippedStyle,
  type Style,
  type Timeframe,
} from "../types/index.js";
import {
  generateJson,
  LlmError,
  type JsonSchema,
  type LlmCallOptions,
  type LlmModelId,
} from "./llmClient.js";
import {
  DECISION_BOUNCE_REPAIR,
  DECISION_FORCE_READY,
  DECISION_PROMPT,
  DECISION_REPAIR_PROMPT,
  SAFETY_FALLBACK_MESSAGE,
  SELF_BLAME_LOSS_SKIP_REASON,
  THOUGHT_HARD_MAX_CHARS,
  THOUGHT_HARD_MAX_WORDS,
  THOUGHT_MAX_CHARS,
  THOUGHT_MAX_WORDS,
  THOUGHT_MIN_WORDS,
  THOUGHT_REPAIR_MAX_CHARS,
  THOUGHT_REPAIR_MAX_WORDS,
} from "./prompts.js";
import { screensAsSelfHarm } from "./safetyScreen.js";
import { slugify, titleCase, normalizeTagSlugs } from "./slugs.js";

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
  deadlineAt?: number;
  abortSignal?: AbortSignal;
} & Pick<LlmCallOptions, "beforeProviderCall" | "usageSink" | "fallbackModel">;

const MAX_OPTIONS = 3;
const MAX_EMOTIONS = 3;
const MAX_DISTORTIONS = 2;
const MAX_ECHOED_OUTPUT = 2000;
/** Triage and safety want the same answer every time. */
export const DECISION_TEMPERATURE = 0.2;

const nullable = (schema: Record<string, unknown>): Record<string, unknown> => ({
  anyOf: [schema, { type: "null" }],
});

/**
 * Enforced by providers that support it. The parser below still normalises and fails
 * closed, because DeepSeek only gets plain JSON mode.
 */
export const DECISION_JSON_SCHEMA: JsonSchema = {
  name: "decision",
  schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "kind",
      "input_language",
      "safety",
      "message",
      "options",
      "thought_en",
      "thought_original_cleaned",
      "styles",
      "skipped_styles",
      "category",
      "proposed_category",
      "proposed_label",
      "tags",
      "intensity",
      "timeframe",
      "emotions",
      "distortions",
    ],
    properties: {
      kind: { type: "string", enum: ["continue", "ready"] },
      input_language: { type: "string" },
      safety: { type: "string", enum: [...SAFETY_FLAGS] },
      message: nullable({ type: "string" }),
      options: { type: "array", items: { type: "string" } },
      thought_en: nullable({ type: "string" }),
      thought_original_cleaned: nullable({ type: "string" }),
      styles: { type: "array", items: { type: "string", enum: [...STYLES] } },
      skipped_styles: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["style", "reason"],
          properties: {
            style: { type: "string", enum: [...STYLES] },
            reason: { type: "string" },
          },
        },
      },
      category: nullable({ type: "string", enum: [...CATEGORIES] }),
      proposed_category: nullable({ type: "string" }),
      proposed_label: nullable({ type: "string" }),
      tags: { type: "array", items: { type: "string" } },
      intensity: nullable({ type: "integer" }),
      timeframe: nullable({ type: "string", enum: [...TIMEFRAMES] }),
      emotions: { type: "array", items: { type: "string", enum: [...EMOTIONS] } },
      distortions: { type: "array", items: { type: "string", enum: [...DISTORTIONS] } },
    },
  },
};

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
  distortions: z.array(z.string().max(48)).nullish(),
});

export type ParseOptions = {
  /** Reject a `continue` that is not justified by safety (final turn of an exchange). */
  requireReady?: boolean;
  /** The last chance: a long cleaned thought is accepted up to the repair cap. */
  repairPass?: boolean;
};

export class DecisionParseError extends Error {
  /** Told to the model on the repair turn. Counts only, never the user's text. */
  readonly repairHint?: string;

  constructor(message: string, repairHint?: string) {
    super(message);
    this.name = "DecisionParseError";
    this.repairHint = repairHint;
  }
}

export function wordCount(text: string): number {
  return text
    .trim()
    .split(/\s+/)
    .filter((part) => part.length > 0).length;
}

const EMPTY_GESTURE =
  /^(?:ugh+|ok(?:ay)?|hi+|hey+|hello+|test+|asdf+|lol+|lmao+|hmm+|idk|yes|no|k)(?:[.!?…,\s]+(?:ugh+|ok(?:ay)?|hi+|hey+|hello+|test+|asdf+|lol+|lmao+|hmm+|idk|yes|no|k))*[.!?…\s]*$/i;

/** First-turn input that already names a situation, not a lone gesture. */
export function looksLikeThought(text: string): boolean {
  const trimmed = text.trim();
  if (wordCount(trimmed) < THOUGHT_MIN_WORDS) {
    return false;
  }
  return !EMPTY_GESTURE.test(trimmed);
}

/** Dead-end continue copy: "didn't catch a thought" / "try again" / "rephrase". */
export function isGenericBounceContinue(message: string): boolean {
  const lower = message.trim().toLowerCase();
  if (lower.length === 0) {
    return false;
  }

  if (
    /(didn['’]?t|did not|couldn['’]?t|could not)\s+(catch|figure(?:\s+out)?).{0,80}thought/.test(
      lower,
    ) ||
    /not\s+(a\s+)?(clear|real|actual)\s+thought/.test(lower) ||
    /no\s+(clear|real|actual)\s+thought/.test(lower) ||
    /\brephrase\b/.test(lower) ||
    /\btry again\b/.test(lower)
  ) {
    return true;
  }

  return (
    /\b(i don['’]?t understand|i do not understand)\b/.test(lower) &&
    wordCount(message) <= 12
  );
}

function isRejectedBounceContinue(decision: Decision, input: RunDecisionInput): boolean {
  return (
    decision.kind === "continue" &&
    decision.safety === "none" &&
    input.followUps.length === 0 &&
    looksLikeThought(input.text) &&
    isGenericBounceContinue(decision.message)
  );
}

/** An English frame keeps a small model on the English rules when they typed in another language. */
export function composeConversation(text: string, followUps: FollowUpAnswer[]): string {
  if (followUps.length === 0) {
    return `They typed: ${text}`;
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

function cleanString(value: string | null | undefined): string | undefined {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : undefined;
}

/** Ways a model says "no safety concern" without using the catalog word. */
const NO_SAFETY_CONCERN: ReadonlySet<string> = new Set(["null", "no", "false", "n/a", "na", "safe"]);

/**
 * Fails closed. Any label outside the catalog ("suicide", "suicidal", "crisis", ...) is
 * treated as self-harm: a false alarm costs one crisis message, a miss ships a reframe.
 */
export function normalizeSafety(value: string | null | undefined): SafetyFlag {
  const candidate = (value ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  if (candidate === "" || NO_SAFETY_CONCERN.has(candidate)) {
    return "none";
  }
  return (SAFETY_FLAGS as readonly string[]).includes(candidate)
    ? (candidate as SafetyFlag)
    : "self_harm";
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

function normalizeDistortions(values: readonly string[] | null | undefined): Distortion[] {
  const distortions: Distortion[] = [];
  for (const value of values ?? []) {
    const candidate = value.trim().toLowerCase().replace(/[\s-]+/g, "_");
    if (
      (DISTORTIONS as readonly string[]).includes(candidate) &&
      !distortions.includes(candidate as Distortion)
    ) {
      distortions.push(candidate as Distortion);
    }
    if (distortions.length === MAX_DISTORTIONS) {
      break;
    }
  }
  return distortions;
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

/**
 * A style the model both chose and skipped counts as skipped. Tough love is held back
 * from someone blaming themselves for a loss even when the model wrote it in.
 */
function chooseStyles(
  requested: Style[],
  skipped: SkippedStyle[],
  selfBlameLoss: boolean,
): { styles: Style[]; skippedStyles: SkippedStyle[] } {
  let skippedStyles = skipped;
  const base =
    requested.length > 0 ? requested : STYLES.filter((style) => !skipped.some((item) => item.style === style));
  let styles = base.filter((style) => !skipped.some((item) => item.style === style));
  if (styles.length === 0) {
    styles = base;
    skippedStyles = skipped.filter((item) => !base.includes(item.style));
  }

  if (selfBlameLoss && styles.includes("tough_love") && styles.length > 1) {
    styles = styles.filter((style) => style !== "tough_love");
    skippedStyles = [
      ...skippedStyles.filter((item) => item.style !== "tough_love"),
      { style: "tough_love", reason: SELF_BLAME_LOSS_SKIP_REASON },
    ];
  }
  return { styles, skippedStyles };
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
  const maxWords = options.repairPass ? THOUGHT_REPAIR_MAX_WORDS : THOUGHT_HARD_MAX_WORDS;
  const maxChars = options.repairPass ? THOUGHT_REPAIR_MAX_CHARS : THOUGHT_HARD_MAX_CHARS;
  if (wordCount(thought) > maxWords || thought.length > maxChars) {
    throw new DecisionParseError(
      "cleaned thought was far over the card budget",
      `Your "thought_en" was ${wordCount(thought)} words and ${thought.length} characters. Rewrite it in at most ${THOUGHT_MAX_WORDS} words and ${THOUGHT_MAX_CHARS} characters: keep the sting, drop side details.`,
    );
  }

  const { category, proposedCategory, proposedLabel } = normalizeCategory(value.category);
  const distortions = normalizeDistortions(value.distortions);
  const { styles, skippedStyles } = chooseStyles(
    normalizeStyles(value.styles),
    normalizeSkipped(value.skipped_styles),
    category === "grief_loss" && distortions.includes("personalizing"),
  );
  if (styles.length === 0) {
    throw new DecisionParseError("ready decision chose no styles");
  }

  const intensity = normalizeIntensity(value.intensity);
  const tags = normalizeTagSlugs(value.tags);

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
    distortions,
    safety,
    inputLanguage: normalizeLanguage(value.input_language),
    skippedStyles,
    matching: matchingFor({ category, tags, intensity }),
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

function screenedContinue(inputLanguage: string): ContinueDecision {
  return {
    kind: "continue",
    message: SAFETY_FALLBACK_MESSAGE,
    options: [],
    safety: "self_harm",
    inputLanguage,
  };
}

/**
 * The phrase screen wins over a model that called explicit self-harm wording safe.
 * A ready decision's cleaned copy is screened too: its English `thought` carries the
 * English phrases for a language the screen has no list for.
 */
function applySafetyScreen(decision: Decision, screened: boolean): Decision {
  if (decision.kind === "continue") {
    return screened && decision.safety === "none" ? screenedContinue(decision.inputLanguage) : decision;
  }
  const cleaned = [decision.thought, ...(decision.thoughtOriginal ? [decision.thoughtOriginal] : [])];
  return screened || screensAsSelfHarm(cleaned) ? screenedContinue(decision.meta.inputLanguage) : decision;
}

export async function runDecision(input: RunDecisionInput): Promise<Decision> {
  const screened = screensAsSelfHarm([input.text, ...input.followUps.map((item) => item.answer)]);
  try {
    return applySafetyScreen(await decide(input), screened);
  } catch (error) {
    // A thought the screen caught still gets crisis help when the model fails.
    if (screened && error instanceof LlmError) {
      return screenedContinue("en");
    }
    throw error;
  }
}

async function decide(input: RunDecisionInput): Promise<Decision> {
  const systemPrompt = input.forceReady
    ? `${DECISION_PROMPT}\n\n${DECISION_FORCE_READY}`
    : DECISION_PROMPT;
  const conversation = composeConversation(input.text, input.followUps);

  const callOptions = {
    model: input.model,
    abortSignal: input.abortSignal,
    beforeProviderCall: input.beforeProviderCall,
    usageSink: input.usageSink,
    fallbackModel: input.fallbackModel,
    deadlineAt: input.deadlineAt,
    temperature: DECISION_TEMPERATURE,
    jsonSchema: DECISION_JSON_SCHEMA,
  };

  const first = await generateJson({
    text: conversation,
    systemPrompt,
    callKind: "decision",
    attempt: 1,
    ...callOptions,
  });

  let bounceRejected = false;
  let repairHint: string | undefined;
  try {
    const decision = refuseUnsafeReframe(
      parseDecision(first, { requireReady: input.forceReady }),
    );
    if (isRejectedBounceContinue(decision, input)) {
      bounceRejected = true;
      throw new DecisionParseError("continue bounced a thought that was already clear");
    }
    return decision;
  } catch (error) {
    if (!(error instanceof DecisionParseError) && !(error instanceof SyntaxError)) {
      throw error;
    }
    repairHint = error instanceof DecisionParseError ? error.repairHint : undefined;
  }

  const repairPrompt = [
    systemPrompt,
    DECISION_REPAIR_PROMPT,
    ...(bounceRejected ? [DECISION_BOUNCE_REPAIR] : []),
    ...(repairHint ? [repairHint] : []),
  ].join("\n\n");
  const repaired = await generateJson({
    text: `${conversation}\n\n---\nYour previous reply, which was rejected:\n${first.slice(0, MAX_ECHOED_OUTPUT)}`,
    systemPrompt: repairPrompt,
    callKind: "decision",
    attempt: 2,
    ...callOptions,
  });

  try {
    // The second pass accepts a `continue` even on a forced turn: a stubborn
    // model gets to keep the conversation rather than fail the request.
    return refuseUnsafeReframe(parseDecision(repaired, { repairPass: true }));
  } catch (error) {
    if (error instanceof DecisionParseError || error instanceof SyntaxError) {
      throw new LlmError("Decision reply could not be parsed");
    }
    throw error;
  }
}
