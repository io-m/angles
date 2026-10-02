import type { LlmModelId } from "./llmClient.js";

export const LLM_RATE_VERSION = "2026-10-providers-v1";

export type LlmCallKind = "decision" | "batch" | "reframe" | "moderation" | "rewrite";
export type LlmCallStatus = "succeeded" | "failed";
export type UsageSource = "reported" | "estimated";

export type NormalizedLlmUsage = {
  promptTokens: number;
  cachedTokens: number;
  cacheHitTokens: number;
  cacheMissTokens: number;
  completionTokens: number;
  thinkingTokens: number;
  toolTokens: number;
};

export type LlmUsageEvent = NormalizedLlmUsage & {
  callKind: LlmCallKind;
  attempt: number;
  requestedModel: LlmModelId;
  returnedModel: string;
  providerRequestId?: string;
  status: LlmCallStatus;
  usageSource: UsageSource;
  rateVersion: typeof LLM_RATE_VERSION;
  companyCostNanoUsd: bigint;
};

export const EMPTY_LLM_USAGE: NormalizedLlmUsage = {
  promptTokens: 0,
  cachedTokens: 0,
  cacheHitTokens: 0,
  cacheMissTokens: 0,
  completionTokens: 0,
  thinkingTokens: 0,
  toolTokens: 0,
};

function token(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : 0;
}

export function parseMistralUsage(value: unknown): NormalizedLlmUsage | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const usage = value as Record<string, unknown>;
  const promptTotal = token(usage.prompt_tokens);
  const completion = token(usage.completion_tokens);
  const total = token(usage.total_tokens);
  if (promptTotal === 0 && completion === 0) {
    return null;
  }
  const details =
    usage.prompt_tokens_details && typeof usage.prompt_tokens_details === "object"
      ? (usage.prompt_tokens_details as Record<string, unknown>)
      : {};
  const rawCached = token(details.cached_tokens);
  if (rawCached > promptTotal || (total > 0 && total !== promptTotal + completion)) {
    return null;
  }
  const cached = rawCached;
  return {
    ...EMPTY_LLM_USAGE,
    promptTokens: promptTotal - cached,
    cachedTokens: cached,
    completionTokens: completion,
  };
}

export function parseOpenAIUsage(value: unknown): NormalizedLlmUsage | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const usage = value as Record<string, unknown>;
  const promptTotal = token(usage.prompt_tokens);
  const completion = token(usage.completion_tokens);
  const total = token(usage.total_tokens);
  if (promptTotal === 0 && completion === 0) {
    return null;
  }
  const details =
    usage.prompt_tokens_details && typeof usage.prompt_tokens_details === "object"
      ? (usage.prompt_tokens_details as Record<string, unknown>)
      : {};
  const rawCached = token(details.cached_tokens);
  if (rawCached > promptTotal || (total > 0 && total !== promptTotal + completion)) {
    return null;
  }
  const cached = rawCached;
  return {
    ...EMPTY_LLM_USAGE,
    promptTokens: promptTotal - cached,
    cachedTokens: cached,
    completionTokens: completion,
  };
}

export function estimateUsage(inputChars: number, maxOutputTokens: number): NormalizedLlmUsage {
  return {
    ...EMPTY_LLM_USAGE,
    promptTokens: Math.max(1, Math.ceil(inputChars / 3)),
    completionTokens: Math.max(1, maxOutputTokens),
  };
}

export function companyCostNanoUsd(
  model: LlmModelId,
  usage: NormalizedLlmUsage,
): bigint {
  const prompt = BigInt(usage.promptTokens);
  const cached = BigInt(usage.cachedTokens);
  const output = BigInt(
    usage.completionTokens + usage.thinkingTokens,
  );
  const tool = BigInt(usage.toolTokens);

  switch (model) {
    case "mistral-small-latest":
      return (prompt + cached + tool) * 150n + output * 600n;
    case "gpt-4.1-mini":
      return (prompt + cached + tool) * 400n + output * 1_600n;
  }
}
