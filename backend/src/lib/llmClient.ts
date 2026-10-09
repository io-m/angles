/**
 * Isolated LLM call. The iOS app must never call an LLM provider directly.
 * Do not log `text` or provider response bodies.
 */

import { loadLocalEnvFile } from "./loadEnv.js";
import {
  LLM_RATE_VERSION,
  companyCostNanoUsd,
  estimateUsage,
  parseMistralUsage,
  parseOpenAIUsage,
  type LlmCallKind,
  type LlmUsageEvent,
  type NormalizedLlmUsage,
} from "./llmUsage.js";

loadLocalEnvFile({ skipWhenVitest: true });

export const LLM_TIMEOUT_MS = 8_000;
export const LLM_MAX_OUTPUT_TOKENS = 160;
export const DECISION_MAX_OUTPUT_TOKENS = 700;
/** Inside the phone's 15 s request timeout, with room for the response to travel. */
export const COOK_DEADLINE_MS = 13_000;
export const MIN_LLM_CALL_MS = 800;
export const DEFAULT_LLM_MODEL: LlmModelId = "mistral-small-latest";
const DEFAULT_MAX_IN_FLIGHT = 32;

export const LLM_MODEL_IDS = [
  "mistral-small-latest",
  "gpt-4.1-mini",
] as const;

export type LlmModelId = (typeof LLM_MODEL_IDS)[number];
type LlmProvider = "mistral" | "openai";

export const LLM_MODELS: Record<LlmModelId, { provider: LlmProvider }> = {
  "mistral-small-latest": { provider: "mistral" },
  "gpt-4.1-mini": { provider: "openai" },
};

export const LLM_PROVIDER_KEY_ENV: Record<LlmProvider, string> = {
  mistral: "MISTRAL_API_KEY",
  openai: "OPENAI_API_KEY",
};

/** The server picks the model for each step of a cook; the phone never does. */
export const LLM_STEPS = ["decision", "writer", "moderation"] as const;
export type LlmStep = (typeof LLM_STEPS)[number];

const STEP_ENV: Record<LlmStep, { model: string; fallback: string }> = {
  decision: { model: "LLM_DECISION_MODEL", fallback: "LLM_DECISION_FALLBACK_MODEL" },
  writer: { model: "LLM_WRITER_MODEL", fallback: "LLM_WRITER_FALLBACK_MODEL" },
  moderation: { model: "LLM_MODERATION_MODEL", fallback: "LLM_MODERATION_FALLBACK_MODEL" },
};

/** Chosen with `pnpm llm:eval`. Move a default only with a fresh eval run behind it. */
export const STEP_DEFAULT_MODELS: Record<LlmStep, LlmModelId> = {
  decision: "mistral-small-latest",
  writer: "mistral-small-latest",
  moderation: "mistral-small-latest",
};

/** A different provider, so one outage cannot take a step down on its own. */
const DEFAULT_FALLBACK: Record<LlmProvider, LlmModelId> = {
  mistral: "gpt-4.1-mini",
  openai: "mistral-small-latest",
};

export type StepModels = { primary: LlmModelId; fallback?: LlmModelId };

function configuredModel(environment: NodeJS.ProcessEnv, name: string): LlmModelId | undefined {
  const raw = environment[name]?.trim();
  if (!raw) {
    return undefined;
  }
  if (!isLlmModelId(raw)) {
    throw new LlmError(`Unknown ${name}`);
  }
  return raw;
}

/** `LLM_<STEP>_MODEL` or the default; `LLM_<STEP>_FALLBACK_MODEL=none` turns the fallback off. */
export function modelsForStep(
  step: LlmStep,
  environment: NodeJS.ProcessEnv = process.env,
): StepModels {
  const names = STEP_ENV[step];
  const primary = configuredModel(environment, names.model) ?? STEP_DEFAULT_MODELS[step];
  if (environment[names.fallback]?.trim().toLowerCase() === "none") {
    return { primary };
  }
  const fallback =
    configuredModel(environment, names.fallback) ?? DEFAULT_FALLBACK[LLM_MODELS[primary].provider];
  return fallback === primary ? { primary } : { primary, fallback };
}

const CHAT_COMPLETIONS_URL: Record<LlmProvider, string> = {
  mistral: "https://api.mistral.ai/v1/chat/completions",
  openai: "https://api.openai.com/v1/chat/completions",
};

/** A JSON Schema enforced by both configured providers. */
export type JsonSchema = {
  name: string;
  schema: Record<string, unknown>;
};

export type LlmCallOptions = {
  timeoutMs?: number;
  /** Absolute cook deadline. The call's own timeout is taken from it once a slot is free. */
  deadlineAt?: number;
  abortSignal?: AbortSignal;
  callKind?: LlmCallKind;
  attempt?: number;
  temperature?: number;
  /** Tried once when the primary provider call fails for any reason. */
  fallbackModel?: LlmModelId;
  /** Which model actually answered, primary or fallback. */
  onAnsweredBy?: (model: LlmModelId) => void;
  beforeProviderCall?: () => Promise<void>;
  usageSink?: (event: LlmUsageEvent) => void;
};

export type GenerateReframeInput = {
  text: string;
  systemPrompt: string;
  model?: LlmModelId;
  maxOutputTokens?: number;
} & LlmCallOptions;

export type GenerateJsonInput = GenerateReframeInput & {
  jsonSchema?: JsonSchema;
};

type ProviderCallInput = GenerateJsonInput & {
  maxOutputTokens: number;
  json: boolean;
};

type ProviderCallResult = {
  content: string;
  returnedModel: string;
  providerRequestId?: string;
  usage: NormalizedLlmUsage | null;
};

const MISSING_USAGE_LIMIT = 3;
const consecutiveMissingUsage = new Map<LlmModelId, number>();

let inFlight = 0;
const waiters: Array<() => void> = [];

function maxInFlight(): number {
  const configured = Number(process.env.LLM_MAX_IN_FLIGHT);
  return Number.isInteger(configured) && configured > 0 ? configured : DEFAULT_MAX_IN_FLIGHT;
}

async function withConcurrencyLimit<T>(fn: () => Promise<T>): Promise<T> {
  while (inFlight >= maxInFlight()) {
    await new Promise<void>((resolve) => {
      waiters.push(resolve);
    });
  }
  inFlight += 1;
  try {
    return await fn();
  } finally {
    inFlight -= 1;
    waiters.shift()?.();
  }
}

/** Remaining time until a cook deadline, capped at the per-call timeout. */
export function timeoutMsUntil(deadlineAt: number): number {
  const remaining = deadlineAt - Date.now();
  if (remaining < MIN_LLM_CALL_MS) {
    throw new LlmError("Cook deadline exceeded");
  }
  return Math.min(LLM_TIMEOUT_MS, remaining);
}

export class LlmError extends Error {
  /** A provider-side failure another model could answer. */
  readonly retryable: boolean;

  constructor(message: string, options?: { cause?: unknown; retryable?: boolean }) {
    super(message, options);
    this.name = "LlmError";
    this.retryable = options?.retryable ?? false;
  }
}

export async function generateReframe(
  input: GenerateReframeInput,
): Promise<string> {
  return runWithFallback({
    ...input,
    maxOutputTokens: input.maxOutputTokens ?? LLM_MAX_OUTPUT_TOKENS,
    json: false,
  });
}

/** Structured JSON call (decision or writer). Returns the raw model string; the caller parses. */
export async function generateJson(input: GenerateJsonInput): Promise<string> {
  return runWithFallback({
    ...input,
    maxOutputTokens: input.maxOutputTokens ?? DECISION_MAX_OUTPUT_TOKENS,
    json: true,
  });
}

async function runWithFallback(input: ProviderCallInput): Promise<string> {
  const primary = resolveEffectiveModel(input.model);
  try {
    const content = await runWithTimeout(input, primary);
    input.onAnsweredBy?.(primary);
    return content;
  } catch (error) {
    const fallback = input.fallbackModel;
    if (
      fallback === undefined ||
      fallback === primary ||
      !(error instanceof LlmError) ||
      !error.retryable ||
      input.abortSignal?.aborted
    ) {
      throw error;
    }
    console.error("llm_fallback", { from: primary, to: fallback, reason: error.message });
    const content = await runWithTimeout(input, fallback);
    input.onAnsweredBy?.(fallback);
    return content;
  }
}

function callTimeoutMs(input: ProviderCallInput): number {
  if (input.deadlineAt !== undefined) {
    return Math.min(timeoutMsUntil(input.deadlineAt), input.timeoutMs ?? LLM_TIMEOUT_MS);
  }
  return Math.min(input.timeoutMs ?? LLM_TIMEOUT_MS, LLM_TIMEOUT_MS);
}

async function runWithTimeout(input: ProviderCallInput, model: LlmModelId): Promise<string> {
  return withConcurrencyLimit(async () => {
    const timeoutMs = callTimeoutMs(input);
    const timeoutController = new AbortController();
    const timer = setTimeout(() => {
      timeoutController.abort();
    }, timeoutMs);

    const clientSignal = input.abortSignal;
    const signal =
      clientSignal === undefined
        ? timeoutController.signal
        : AbortSignal.any([timeoutController.signal, clientSignal]);

    const provider = LLM_MODELS[model].provider;
    let providerAttempted = false;
    try {
      if (clientSignal?.aborted) {
        throw new LlmError("LLM request aborted");
      }
      const apiKey = apiKeyFor(provider);
      await input.beforeProviderCall?.();
      providerAttempted = true;
      const result = await callProvider(input, signal, model, provider, apiKey);
      const usage = result.usage ?? estimateUsage(
        input.text.length + input.systemPrompt.length,
        input.maxOutputTokens,
      );
      const usageSource = result.usage ? "reported" : "estimated";
      input.usageSink?.(
        usageEvent(input, model, result.returnedModel, "succeeded", usageSource, usage, result.providerRequestId),
      );

      if (result.usage) {
        consecutiveMissingUsage.set(model, 0);
      } else {
        const missing = (consecutiveMissingUsage.get(model) ?? 0) + 1;
        consecutiveMissingUsage.set(model, missing);
        console.error("usage_missing", { model });
        if (missing >= MISSING_USAGE_LIMIT) {
          throw new LlmError("LLM model unavailable", { retryable: true });
        }
      }
      return result.content;
    } catch (error) {
      if (providerAttempted && !clientSignal?.aborted) {
        // One searchable line per failed provider call (status, never the text), so two keys
        // rejected in the same second shows up as an alert rather than a post-mortem.
        console.error("llm_provider_failed", {
          model,
          provider,
          step: input.callKind ?? "unknown",
          reason: error instanceof LlmError
            ? error.message
            : timeoutController.signal.aborted
              ? "LLM request timed out"
              : "LLM request failed",
        });
      }
      if (providerAttempted && !(error instanceof LlmError && error.message === "LLM model unavailable")) {
        const usage = estimateUsage(
          input.text.length + input.systemPrompt.length,
          input.maxOutputTokens,
        );
        input.usageSink?.(
          usageEvent(input, model, model, "failed", "estimated", usage),
        );
      }
      if (error instanceof LlmError) {
        throw error;
      }
      if (error instanceof Error && error.name === "MeteringError") {
        throw error;
      }
      if (clientSignal?.aborted) {
        throw new LlmError("LLM request aborted", { cause: error });
      }
      if (timeoutController.signal.aborted) {
        throw new LlmError("LLM request timed out", { cause: error, retryable: true });
      }
      throw new LlmError("LLM request failed", { cause: error, retryable: true });
    } finally {
      clearTimeout(timer);
    }
  });
}

function usageEvent(
  input: ProviderCallInput,
  requestedModel: LlmModelId,
  returnedModel: string,
  status: "succeeded" | "failed",
  usageSource: "reported" | "estimated",
  usage: NormalizedLlmUsage,
  providerRequestId?: string,
): LlmUsageEvent {
  return {
    callKind: input.callKind ?? "reframe",
    attempt: input.attempt ?? 1,
    requestedModel,
    returnedModel,
    ...(providerRequestId ? { providerRequestId } : {}),
    status,
    ...usage,
    usageSource,
    rateVersion: LLM_RATE_VERSION,
    companyCostNanoUsd: companyCostNanoUsd(requestedModel, usage),
  };
}

export function isLlmModelId(value: string): value is LlmModelId {
  return (LLM_MODEL_IDS as readonly string[]).includes(value);
}

export function resolveEffectiveModel(requested?: LlmModelId): LlmModelId {
  return requested ?? DEFAULT_LLM_MODEL;
}

function apiKeyFor(provider: LlmProvider): string {
  const envName = LLM_PROVIDER_KEY_ENV[provider];
  const key = process.env[envName]?.trim() ?? "";
  if (key.length === 0) {
    throw new LlmError(`${envName} is not set`, { retryable: true });
  }
  return key;
}

async function callProvider(
  input: ProviderCallInput,
  signal: AbortSignal,
  model: LlmModelId,
  provider: LlmProvider,
  apiKey: string,
): Promise<ProviderCallResult> {
  if (signal.aborted) {
    throw new LlmError("LLM request aborted");
  }

  const trimmed = input.text.trim();
  if (trimmed.length === 0) {
    throw new LlmError("Cannot reframe empty text");
  }

  return requestChatCompletions({
    url: CHAT_COMPLETIONS_URL[provider],
    apiKey,
    model,
    systemPrompt: input.systemPrompt,
    text: trimmed,
    signal,
    maxOutputTokens: input.maxOutputTokens,
    extraBody: {
      ...(provider === "mistral" ? { reasoning_effort: "none" } : {}),
      ...(input.temperature !== undefined ? { temperature: input.temperature } : {}),
      ...(input.json ? { response_format: chatResponseFormat(input.jsonSchema) } : {}),
    },
  });
}

function chatResponseFormat(
  jsonSchema: JsonSchema | undefined,
): Record<string, unknown> {
  if (jsonSchema) {
    return {
      type: "json_schema",
      json_schema: { name: jsonSchema.name, schema: jsonSchema.schema, strict: true },
    };
  }
  return { type: "json_object" };
}

type ChatMessageContent =
  | string
  | ReadonlyArray<{ type?: string; text?: string }>
  | null
  | undefined;

type ChatCompletionResponse = {
  id?: string;
  model?: string;
  usage?: unknown;
  choices?: Array<{
    message?: {
      content?: ChatMessageContent;
    };
  }>;
};

function httpError(status: number): LlmError {
  return new LlmError(`LLM HTTP ${status}`, { retryable: true });
}

async function requestChatCompletions(options: {
  url: string;
  apiKey: string;
  model: string;
  systemPrompt: string;
  text: string;
  signal: AbortSignal;
  maxOutputTokens: number;
  extraBody: Record<string, unknown>;
}): Promise<ProviderCallResult> {
  const response = await fetch(options.url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${options.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: options.model,
      messages: [
        { role: "system", content: options.systemPrompt },
        { role: "user", content: options.text },
      ],
      max_tokens: options.maxOutputTokens,
      ...options.extraBody,
    }),
    signal: options.signal,
  });

  if (!response.ok) {
    throw httpError(response.status);
  }

  const payload = (await response.json()) as ChatCompletionResponse;
  const content = extractChatContent(payload.choices?.[0]?.message?.content);
  if (content.length === 0) {
    throw new LlmError("LLM returned an empty reframe", { retryable: true });
  }
  const requestedModel = options.model as LlmModelId;
  const provider = LLM_MODELS[requestedModel].provider;
  return {
    content,
    returnedModel: payload.model ?? options.model,
    ...(payload.id ? { providerRequestId: payload.id } : {}),
    usage:
      provider === "mistral"
        ? parseMistralUsage(payload.usage)
        : parseOpenAIUsage(payload.usage),
  };
}

function extractChatContent(content: ChatMessageContent): string {
  if (typeof content === "string") {
    return content.trim();
  }

  if (!Array.isArray(content)) {
    return "";
  }

  return content
    .map((part) => (typeof part.text === "string" ? part.text : ""))
    .join("")
    .trim();
}

export function resetMissingUsageCircuitForTests(): void {
  if (process.env.VITEST === "true") {
    consecutiveMissingUsage.clear();
  }
}
