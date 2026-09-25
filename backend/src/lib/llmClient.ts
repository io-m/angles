/**
 * Isolated LLM call. The iOS app must never call an LLM provider directly.
 * Do not log `text` or provider response bodies.
 */

import { loadLocalEnvFile } from "./loadEnv.js";
import {
  LLM_RATE_VERSION,
  companyCostNanoUsd,
  estimateUsage,
  parseDeepSeekUsage,
  parseGeminiUsage,
  parseMistralUsage,
  type LlmCallKind,
  type LlmUsageEvent,
  type NormalizedLlmUsage,
} from "./llmUsage.js";

loadLocalEnvFile({ skipWhenVitest: true });

export const LLM_TIMEOUT_MS = 8_000;
export const LLM_MAX_OUTPUT_TOKENS = 120;
export const DECISION_MAX_OUTPUT_TOKENS = 700;
/** Four short reframes as JSON: ~4 × 60 tokens plus keys. */
export const STYLE_BATCH_MAX_OUTPUT_TOKENS = 280;
export const COOK_DEADLINE_MS = 10_000;
export const MIN_LLM_CALL_MS = 800;
export const DEFAULT_LLM_MODEL = "mistral-small-latest";
const MAX_IN_FLIGHT = 3;

export const LLM_MODEL_IDS = [
  "mistral-small-latest",
  "gemini-3.8-flash",
  "deepseek-flash",
  "deepseek-v4-pro",
] as const;

export type LlmModelId = (typeof LLM_MODEL_IDS)[number];
type LlmProvider = "mistral" | "gemini" | "deepseek";

export const LLM_MODELS: Record<LlmModelId, { provider: LlmProvider }> = {
  "mistral-small-latest": { provider: "mistral" },
  "gemini-3.8-flash": { provider: "gemini" },
  "deepseek-flash": { provider: "deepseek" },
  "deepseek-v4-pro": { provider: "deepseek" },
};

const KEY_ENV: Record<LlmProvider, string> = {
  mistral: "MISTRAL_API_KEY",
  gemini: "GEMINI_API_KEY",
  deepseek: "DEEPSEEK_API_KEY",
};

const CHAT_COMPLETIONS_URL: Record<Exclude<LlmProvider, "gemini">, string> = {
  mistral: "https://api.mistral.ai/v1/chat/completions",
  deepseek: "https://api.deepseek.com/chat/completions",
};

export type LlmCallOptions = {
  timeoutMs?: number;
  abortSignal?: AbortSignal;
  callKind?: LlmCallKind;
  attempt?: number;
  beforeProviderCall?: () => Promise<void>;
  usageSink?: (event: LlmUsageEvent) => void;
};

export type GenerateReframeInput = {
  text: string;
  systemPrompt: string;
  model?: LlmModelId;
} & LlmCallOptions;

export type GenerateJsonInput = GenerateReframeInput & {
  maxOutputTokens?: number;
};

type ProviderCallInput = GenerateReframeInput & {
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

async function withConcurrencyLimit<T>(fn: () => Promise<T>): Promise<T> {
  while (inFlight >= MAX_IN_FLIGHT) {
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
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "LlmError";
  }
}

export async function generateReframe(
  input: GenerateReframeInput,
): Promise<string> {
  return runWithTimeout({
    ...input,
    maxOutputTokens: LLM_MAX_OUTPUT_TOKENS,
    json: false,
  });
}

/** Structured JSON call (decision or style batch). Returns the raw model string; the caller parses. */
export async function generateJson(input: GenerateJsonInput): Promise<string> {
  return runWithTimeout({
    text: input.text,
    systemPrompt: input.systemPrompt,
    model: input.model,
    timeoutMs: input.timeoutMs,
    abortSignal: input.abortSignal,
    callKind: input.callKind,
    attempt: input.attempt,
    beforeProviderCall: input.beforeProviderCall,
    usageSink: input.usageSink,
    maxOutputTokens: input.maxOutputTokens ?? DECISION_MAX_OUTPUT_TOKENS,
    json: true,
  });
}

async function runWithTimeout(input: ProviderCallInput): Promise<string> {
  return withConcurrencyLimit(async () => {
    const timeoutMs = Math.min(input.timeoutMs ?? LLM_TIMEOUT_MS, LLM_TIMEOUT_MS);
    const timeoutController = new AbortController();
    const timer = setTimeout(() => {
      timeoutController.abort();
    }, timeoutMs);

    const clientSignal = input.abortSignal;
    const signal =
      clientSignal === undefined
        ? timeoutController.signal
        : AbortSignal.any([timeoutController.signal, clientSignal]);

    const model = resolveEffectiveModel(input.model);
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
          throw new LlmError("LLM model unavailable");
        }
      }
      return result.content;
    } catch (error) {
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
        throw new LlmError("LLM request timed out", { cause: error });
      }
      throw new LlmError("LLM request failed", { cause: error });
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

function isLlmModelId(value: string): value is LlmModelId {
  return (LLM_MODEL_IDS as readonly string[]).includes(value);
}

export function resolveEffectiveModel(requested?: LlmModelId): LlmModelId {
  if (requested) {
    return requested;
  }

  const raw = process.env.LLM_MODEL?.trim() || DEFAULT_LLM_MODEL;
  if (!isLlmModelId(raw)) {
    throw new LlmError("Unknown LLM_MODEL");
  }
  return raw;
}

function apiKeyFor(provider: LlmProvider): string {
  const envName = KEY_ENV[provider];
  const key = process.env[envName]?.trim() ?? "";
  if (key.length === 0) {
    throw new LlmError(`${envName} is not set`);
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

  if (provider === "gemini") {
    return requestGemini({
      model,
      apiKey,
      systemPrompt: input.systemPrompt,
      text: trimmed,
      signal,
      maxOutputTokens: input.maxOutputTokens,
      json: input.json,
    });
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
      ...(provider === "mistral"
        ? { reasoning_effort: "none" }
        : { thinking: { type: "disabled" } }),
      ...(input.json ? { response_format: { type: "json_object" } } : {}),
    },
  });
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

type GeminiPart = {
  text?: string;
  thought?: boolean;
};

type GeminiGenerateResponse = {
  responseId?: string;
  modelVersion?: string;
  usageMetadata?: unknown;
  candidates?: Array<{
    content?: {
      parts?: GeminiPart[];
    };
  }>;
};

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
    throw new LlmError(`LLM HTTP ${response.status}`);
  }

  const payload = (await response.json()) as ChatCompletionResponse;
  const content = extractChatContent(payload.choices?.[0]?.message?.content);
  if (content.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
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
        : parseDeepSeekUsage(payload.usage),
  };
}

async function requestGemini(options: {
  model: string;
  apiKey: string;
  systemPrompt: string;
  text: string;
  signal: AbortSignal;
  maxOutputTokens: number;
  json: boolean;
}): Promise<ProviderCallResult> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${options.model}:generateContent`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": options.apiKey,
    },
    body: JSON.stringify({
      systemInstruction: {
        parts: [{ text: options.systemPrompt }],
      },
      contents: [{ role: "user", parts: [{ text: options.text }] }],
      generationConfig: {
        maxOutputTokens: options.maxOutputTokens,
        thinkingConfig: {
          thinkingLevel: "low",
        },
        ...(options.json ? { responseMimeType: "application/json" } : {}),
      },
    }),
    signal: options.signal,
  });

  if (!response.ok) {
    throw new LlmError(`LLM HTTP ${response.status}`);
  }

  const payload = (await response.json()) as GeminiGenerateResponse;
  const content = extractGeminiText(payload.candidates?.[0]?.content?.parts);
  if (content.length === 0) {
    throw new LlmError("LLM returned an empty reframe");
  }
  return {
    content,
    returnedModel: payload.modelVersion ?? options.model,
    ...(payload.responseId ? { providerRequestId: payload.responseId } : {}),
    usage: parseGeminiUsage(payload.usageMetadata),
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

function extractGeminiText(parts: GeminiPart[] | undefined): string {
  if (!parts) {
    return "";
  }

  return parts
    .filter((part) => part.thought !== true)
    .map((part) => part.text ?? "")
    .join("")
    .trim();
}

export function resetMissingUsageCircuitForTests(): void {
  if (process.env.VITEST === "true") {
    consecutiveMissingUsage.clear();
  }
}

