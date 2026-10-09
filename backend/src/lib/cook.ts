/**
 * The cook pipeline without HTTP, metering, or signing: the decision call, then the
 * style writing. The route and the offline eval both run this. Never log the text.
 */

import type { FollowUpAnswer, ReframeResult, SafetyFlag, Style } from "../types/index.js";
import { asSolemn, runDecision, type ReadyDecision } from "./decision.js";
import { screensAsGrave } from "./graveScreen.js";
import {
  generateJson,
  generateReframe,
  LlmError,
  type JsonSchema,
  type LlmCallOptions,
  type LlmModelId,
} from "./llmClient.js";
import {
  lintRewriteUserPrompt,
  localLanguage,
  recookUserPrompt,
  REFRAME_HARD_MAX_CHARS,
  styleBatchPrompt,
  SYSTEM_PROMPTS,
  styleBatchUserPrompt,
  type LocalTarget,
} from "./prompts.js";
import { lintLocal, lintResults, OVERLAP_LIMIT, overlap, type LintIssue } from "./reframeLint.js";

/**
 * Two answered questions is the most the screen ever asks. From the second answer the
 * decision call is told to land it, safety aside.
 */
export const FORCE_READY_AFTER = 2;
/** Voice needs room to move; the decision call stays near-deterministic instead. */
export const WRITER_TEMPERATURE = 0.8;
/** A recook exists to say something the first answer did not. */
export const RECOOK_TEMPERATURE = 0.95;
/** About three characters a token for the worst-case language, so a full answer never truncates. */
const CHARS_PER_TOKEN = 3;
const JSON_OVERHEAD_TOKENS = 40;
/** One "technique_id: 3–8 word insight" line, with its key. */
const PLAN_TOKENS_PER_STYLE = 28;
/** Worth one more model call. A short answer may stay short: intensity 4–5 asks for it. */
const REWRITE_ISSUES: ReadonlySet<LintIssue> = new Set([
  "too_long",
  "question",
  "digits",
  "markdown",
  "cliche",
  "opener",
  "overlap",
]);
/** Below this much time before the cook deadline, a flagged answer ships as written. */
export const REWRITE_MIN_REMAINING_MS = 2_500;

/**
 * Output cap for one writer call: the plan and every style at the hard length, twice
 * over when each answer also comes in their language, plus keys and slack.
 */
export function writerMaxOutputTokens(styleCount: number, bilingual = false): number {
  const answer = Math.ceil(REFRAME_HARD_MAX_CHARS / CHARS_PER_TOKEN) * (bilingual ? 2 : 1);
  return styleCount * (answer + PLAN_TOKENS_PER_STYLE) + JSON_OVERHEAD_TOKENS;
}

export type CookCallOptions = Pick<
  LlmCallOptions,
  "abortSignal" | "beforeProviderCall" | "usageSink" | "fallbackModel" | "onAnsweredBy"
> & {
  deadlineAt: number;
  model?: LlmModelId;
};

/** What a writer call needs from a cook: the cleaned thought(s) and the signed meta. */
export type WriterInput = Pick<ReadyDecision, "thought" | "thoughtOriginal" | "meta">;

/** Answers come in their language too whenever they did not write English. */
function localTarget(cook: WriterInput): LocalTarget | undefined {
  const language = localLanguage(cook.meta.inputLanguage);
  return language ? { language, thought: cook.thoughtOriginal } : undefined;
}

export type CookOutcome =
  | { kind: "continue"; message: string; options: string[]; safety: SafetyFlag }
  | { kind: "ready"; decision: ReadyDecision; results: ReframeResult[] };

class StyleBatchParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StyleBatchParseError";
  }
}

export function trimToSentence(reframe: string): string {
  const clipped = reframe.slice(0, REFRAME_HARD_MAX_CHARS);
  const lastStop = Math.max(
    clipped.lastIndexOf("."),
    clipped.lastIndexOf("!"),
    clipped.lastIndexOf("?"),
  );
  if (lastStop > REFRAME_HARD_MAX_CHARS / 2) {
    return clipped.slice(0, lastStop + 1).trim();
  }
  return `${clipped.trim().replace(/[,;:\s]+$/, "")}…`;
}

function callOptions(options: CookCallOptions): LlmCallOptions & { model?: LlmModelId } {
  return {
    model: options.model,
    abortSignal: options.abortSignal,
    deadlineAt: options.deadlineAt,
    temperature: WRITER_TEMPERATURE,
    fallbackModel: options.fallbackModel,
    onAnsweredBy: options.onAnsweredBy,
    beforeProviderCall: options.beforeProviderCall,
    usageSink: options.usageSink,
  };
}

const ANSWER_PAIR = {
  type: "object",
  additionalProperties: false,
  required: ["en", "local"],
  properties: { en: { type: "string" }, local: { type: "string" } },
} as const;

const PAIR_SCHEMA: JsonSchema = { name: "reframe", schema: ANSWER_PAIR };

const styleFields = (chosen: readonly Style[], bilingual: boolean): Record<string, unknown> =>
  Object.fromEntries(chosen.map((style) => [style, bilingual ? ANSWER_PAIR : { type: "string" }]));

/** `plan` comes first so the model commits to distinct techniques before writing. */
function batchSchema(chosen: readonly Style[], bilingual: boolean): JsonSchema {
  return {
    name: "reframes",
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["plan", ...chosen],
      properties: {
        plan: {
          type: "object",
          additionalProperties: false,
          required: [...chosen],
          properties: styleFields(chosen, false),
        },
        ...styleFields(chosen, bilingual),
      },
    },
  };
}

type Answer = Omit<ReframeResult, "style">;

/** A plain string, or `{ en, local }`. An answer without English is no answer. */
function readAnswer(value: unknown): Answer | undefined {
  if (typeof value === "string") {
    const reframe = value.trim();
    return reframe.length > 0 ? { reframe } : undefined;
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  const { en, local } = value as Record<string, unknown>;
  const reframe = typeof en === "string" ? en.trim() : "";
  if (reframe.length === 0) {
    return undefined;
  }
  const original = typeof local === "string" ? local.trim() : "";
  return original.length > 0 ? { reframe, reframeOriginal: original } : { reframe };
}

function readAnswerJson(raw: string): Answer | undefined {
  try {
    return readAnswer(JSON.parse(extractJsonObject(raw)));
  } catch {
    return undefined;
  }
}

type StyleBatch = {
  texts: Partial<Record<Style, Answer>>;
  /** Never returned to the phone. A rewrite uses it to steer away from a technique. */
  plan: Partial<Record<Style, string>>;
};

function extractJsonObject(raw: string): string {
  const withoutFence = raw.replace(/```[a-zA-Z]*\s*/g, "").replace(/```/g, "").trim();
  const start = withoutFence.indexOf("{");
  const end = withoutFence.lastIndexOf("}");
  if (start === -1 || end <= start) {
    throw new StyleBatchParseError("style batch reply was not JSON");
  }
  return withoutFence.slice(start, end + 1);
}

function parseStyleBatch(raw: string, chosen: readonly Style[]): StyleBatch {
  let parsed: unknown;
  try {
    parsed = JSON.parse(extractJsonObject(raw));
  } catch (error) {
    if (error instanceof StyleBatchParseError) {
      throw error;
    }
    throw new StyleBatchParseError("style batch reply was not JSON");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new StyleBatchParseError("style batch reply was not an object");
  }

  const record = parsed as Record<string, unknown>;
  const out: Partial<Record<Style, Answer>> = {};
  for (const style of chosen) {
    const answer = readAnswer(record[style]);
    if (answer) {
      out[style] = answer;
    }
  }
  if (Object.keys(out).length !== chosen.length) {
    throw new StyleBatchParseError("style batch reply omitted a requested style");
  }

  const plan: Partial<Record<Style, string>> = {};
  const rawPlan = record.plan;
  if (rawPlan !== null && typeof rawPlan === "object" && !Array.isArray(rawPlan)) {
    for (const style of chosen) {
      const line = (rawPlan as Record<string, unknown>)[style];
      if (typeof line === "string" && line.trim().length > 0) {
        plan[style] = line.trim().slice(0, 120);
      }
    }
  }
  return { texts: out, plan };
}

/**
 * "New answer" for one style of a signed cook: no decision call, the previous answer
 * in view, and more heat so it lands somewhere new.
 */
export async function recookStyle(
  cook: WriterInput,
  style: Style,
  previous: string | undefined,
  options: CookCallOptions,
): Promise<ReframeResult> {
  const local = localTarget(cook);
  const answer = await writeOne({
    text: recookUserPrompt(cook.thought, cook.meta, previous, local),
    style,
    local,
    callKind: "reframe",
    options,
    temperature: RECOOK_TEMPERATURE,
  });
  if (!answer) {
    throw new LlmError("LLM returned an empty reframe");
  }
  const [result] = await rewriteFlagged(
    cook,
    [{ style, ...fitAnswer(answer, local) }],
    {},
    options,
    previous === undefined ? {} : { [style]: previous },
  );
  if (!result) {
    throw new LlmError("LLM returned an empty reframe");
  }
  return result;
}

/** One style in one call: plain text, or the `{ en, local }` pair for a bilingual cook. */
async function writeOne(input: {
  text: string;
  style: Style;
  local: LocalTarget | undefined;
  callKind: "reframe" | "rewrite";
  options: CookCallOptions;
  temperature?: number;
}): Promise<Answer | undefined> {
  const call = {
    text: input.text,
    systemPrompt: SYSTEM_PROMPTS[input.style],
    callKind: input.callKind,
    attempt: 1,
    ...callOptions(input.options),
    ...(input.temperature === undefined ? {} : { temperature: input.temperature }),
  };
  if (!input.local) {
    return readAnswer(await generateReframe(call));
  }
  return readAnswerJson(
    await generateJson({ ...call, jsonSchema: PAIR_SCHEMA, maxOutputTokens: writerMaxOutputTokens(1, true) }),
  );
}

async function requestStyleBatch(
  decision: WriterInput,
  chosen: Style[],
  options: CookCallOptions,
  attempt: number,
): Promise<string> {
  const local = localTarget(decision);
  return generateJson({
    text: styleBatchUserPrompt(decision.thought, decision.meta, chosen, local),
    systemPrompt: styleBatchPrompt(chosen),
    maxOutputTokens: writerMaxOutputTokens(chosen.length, local !== undefined),
    jsonSchema: batchSchema(chosen, local !== undefined),
    callKind: "batch",
    attempt,
    ...callOptions(options),
  });
}

export async function writeStyleBatch(
  decision: ReadyDecision,
  chosen: Style[],
  options: CookCallOptions,
): Promise<ReframeResult[]> {
  let raw: string;
  try {
    raw = await requestStyleBatch(decision, chosen, options, 1);
  } catch (error) {
    if (error instanceof LlmError) {
      throw error;
    }
    throw new LlmError("Style batch failed", { cause: error });
  }

  let parsed: StyleBatch;
  try {
    parsed = parseStyleBatch(raw, chosen);
  } catch (error) {
    if (!(error instanceof StyleBatchParseError)) {
      throw error;
    }
    try {
      const retried = await requestStyleBatch(decision, chosen, options, 2);
      parsed = parseStyleBatch(retried, chosen);
    } catch {
      throw new LlmError("Style batch reply could not be parsed");
    }
  }

  const local = localTarget(decision);
  const results: ReframeResult[] = [];
  for (const style of chosen) {
    const fromBatch = parsed.texts[style];
    if (fromBatch === undefined) {
      throw new LlmError("Style batch reply omitted a requested style");
    }
    results.push({ style, ...fitAnswer(fromBatch, local) });
  }

  return rewriteFlagged(decision, results, parsed.plan, options);
}

function fitCard(reframe: string): string {
  return reframe.length <= REFRAME_HARD_MAX_CHARS ? reframe : trimToSentence(reframe);
}

/** Both versions fit the card. A second version nobody asked for, or one that is just the English, is dropped. */
function fitAnswer(answer: Answer, local: LocalTarget | undefined): Answer {
  const reframe = fitCard(answer.reframe);
  const original =
    local && answer.reframeOriginal !== undefined ? fitCard(answer.reframeOriginal) : undefined;
  return original !== undefined && original !== reframe ? { reframe, reframeOriginal: original } : { reframe };
}

function rewriteProblems(issues: Map<Style, LintIssue[]>, style: Style): LintIssue[] {
  return (issues.get(style) ?? []).filter((issue) => REWRITE_ISSUES.has(issue));
}

/** Every version of the thought, so a number they wrote is never foreign in either answer. */
function thoughtSource(cook: WriterInput): string {
  return [cook.thought, cook.thoughtOriginal ?? ""].join("\n");
}

/** What is wrong with the answer in their language; nothing to check on an English cook. */
function localProblems(
  result: ReframeResult,
  cook: WriterInput,
  local: LocalTarget | undefined,
): LintIssue[] {
  if (!local || result.reframeOriginal === undefined) {
    return [];
  }
  return lintLocal(result.reframeOriginal, thoughtSource(cook));
}

/** A missing second version counts as one problem, so a rewrite that fills it wins. */
function problemCount(
  issues: Map<Style, LintIssue[]>,
  result: ReframeResult,
  cook: WriterInput,
  local: LocalTarget | undefined,
): number {
  const missing = local && result.reframeOriginal === undefined ? 1 : 0;
  return rewriteProblems(issues, result.style).length + localProblems(result, cook, local).length + missing;
}

/** A phone number or statistic in their language never ships; the English answer still does. */
function withoutForeignDigits(result: ReframeResult, cook: WriterInput, local: LocalTarget | undefined): ReframeResult {
  if (!localProblems(result, cook, local).includes("digits")) {
    return result;
  }
  const { reframeOriginal: _dropped, ...english } = result;
  return english;
}

/** The lint, plus `overlap` on an answer that merely rewords the one it replaces. */
function lintAgainst(
  results: readonly ReframeResult[],
  thought: string,
  previous: Partial<Record<Style, string>>,
): Map<Style, LintIssue[]> {
  const issues = lintResults(results, thought);
  for (const result of results) {
    const before = previous[result.style];
    const own = issues.get(result.style);
    if (before !== undefined && own && !own.includes("overlap") && overlap(before, result.reframe) > OVERLAP_LIMIT) {
      own.push("overlap");
    }
  }
  return issues;
}

/**
 * One targeted rewrite for each answer the lint flags, all at once. A rewrite ships
 * only if it has fewer problems than the draft; a failed or late one never fails the cook.
 * `previous` holds answers being replaced, which the new ones must not repeat.
 */
export async function rewriteFlagged(
  cook: WriterInput,
  results: ReframeResult[],
  plan: Partial<Record<Style, string>>,
  options: CookCallOptions,
  previous: Partial<Record<Style, string>> = {},
): Promise<ReframeResult[]> {
  const local = localTarget(cook);
  const issues = lintAgainst(results, cook.thought, previous);
  const flagged = results.filter((result) => problemCount(issues, result, cook, local) > 0);
  if (flagged.length === 0 || options.deadlineAt - Date.now() < REWRITE_MIN_REMAINING_MS) {
    return results.map((result) => withoutForeignDigits(result, cook, local));
  }

  // The cook reports the writer that answered the batch, not a fallback that fixed one line.
  const { onAnsweredBy: _onAnsweredBy, ...rewriteOptions } = options;
  const rewrites = new Map<Style, Answer>();
  await Promise.all(
    flagged.map(async (result) => {
      const others = results.filter((other) => other.style !== result.style);
      const replaced = previous[result.style];
      try {
        const answer = await writeOne({
          text: lintRewriteUserPrompt({
            thought: cook.thought,
            meta: cook.meta,
            draft: result.reframe,
            problems: rewriteProblems(issues, result.style),
            technique: plan[result.style],
            others: replaced === undefined ? others : [...others, { style: result.style, reframe: replaced }],
            ...(local
              ? {
                  local: {
                    ...local,
                    draft: result.reframeOriginal,
                    problems: localProblems(result, cook, local),
                  },
                }
              : {}),
          }),
          style: result.style,
          local,
          callKind: "rewrite",
          options: rewriteOptions,
        });
        if (answer) {
          rewrites.set(result.style, fitAnswer(answer, local));
        }
      } catch {
        // The draft ships.
      }
    }),
  );

  const candidate = results.map((result) => {
    const rewritten = rewrites.get(result.style);
    return rewritten ? { style: result.style, ...rewritten } : result;
  });
  const candidateIssues = lintAgainst(candidate, cook.thought, previous);
  return results.map((result, index) => {
    const rewritten = candidate[index];
    const better =
      rewritten !== undefined &&
      rewrites.has(result.style) &&
      problemCount(candidateIssues, rewritten, cook, local) < problemCount(issues, result, cook, local);
    return withoutForeignDigits(better ? rewritten : result, cook, local);
  });
}

export function uniqueStyles(styles: readonly Style[]): Style[] {
  const seen = new Set<Style>();
  const unique: Style[] = [];
  for (const style of styles) {
    if (!seen.has(style)) {
      seen.add(style);
      unique.push(style);
    }
  }
  return unique;
}

type WrittenCook = { decision: ReadyDecision; results: ReframeResult[] };

/**
 * A joke that itself names real harm proves the thought was grave and both checks
 * missed it. The cook turns solemn: the joke and any push are dropped, never rewritten,
 * and the voices a solemn card has instead are written in one call. If that call fails
 * the cook fails, so no card ships short of what it should have.
 */
export async function withoutGraveJokes(
  decision: ReadyDecision,
  results: ReframeResult[],
  options: CookCallOptions,
): Promise<WrittenCook> {
  const joke = results.find((result) => result.style === "witty");
  if (decision.solemn || !joke || !screensAsGrave([joke.reframe, joke.reframeOriginal])) {
    return { decision, results };
  }
  const solemn = asSolemn(decision);
  const kept = results.filter((result) => solemn.styles.includes(result.style));
  const missing = solemn.styles.filter((style) => !kept.some((result) => result.style === style));
  const written = missing.length > 0 ? await writeStyleBatch(solemn, missing, options) : [];
  const byStyle = new Map([...kept, ...written].map((result) => [result.style, result]));
  const ordered = solemn.styles.flatMap((style) => byStyle.get(style) ?? []);
  if (ordered.length === 0 || ordered.length !== solemn.styles.length) {
    throw new LlmError("A grave cook could not be written without the joke");
  }
  return { decision: solemn, results: ordered };
}

/** Every style a ready decision chose, written and guarded. The decision may come back solemn. */
export async function writeCook(decision: ReadyDecision, options: CookCallOptions): Promise<WrittenCook> {
  const results = await writeStyleBatch(decision, uniqueStyles(decision.styles), options);
  return withoutGraveJokes(decision, results, options);
}

/** A full cook: the decision, then every style it chose in one batch. `model` is the writer. */
export async function runCook(
  input: {
    text: string;
    followUps: FollowUpAnswer[];
    decisionModel?: LlmModelId;
    catalog?: readonly Style[];
  } & CookCallOptions,
): Promise<CookOutcome> {
  const decision = await runDecision({
    text: input.text,
    followUps: input.followUps,
    catalog: input.catalog,
    model: input.decisionModel,
    forceReady: input.followUps.length >= FORCE_READY_AFTER,
    deadlineAt: input.deadlineAt,
    abortSignal: input.abortSignal,
    beforeProviderCall: input.beforeProviderCall,
    usageSink: input.usageSink,
  });
  if (decision.kind === "continue") {
    return {
      kind: "continue",
      message: decision.message,
      options: decision.options,
      safety: decision.safety,
    };
  }
  return { kind: "ready", ...(await writeCook(decision, input)) };
}
