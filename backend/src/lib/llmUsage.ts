import type { LlmModelId } from "./llmClient.js";

export const LLM_RATE_VERSION = "2026-09-credits-v1";

export type LlmCallKind = "decision" | "batch" | "reframe" | "moderation";
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

export function parseDeepSeekUsage(value: unknown): NormalizedLlmUsage | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const usage = value as Record<string, unknown>;
  const promptTotal = token(usage.prompt_tokens);
  const completionTotal = token(usage.completion_tokens);
  const total = token(usage.total_tokens);
  if (promptTotal === 0 && completionTotal === 0) {
    return null;
  }
  const details =
    usage.prompt_tokens_details && typeof usage.prompt_tokens_details === "object"
      ? (usage.prompt_tokens_details as Record<string, unknown>)
      : {};
  const completionDetails =
    usage.completion_tokens_details && typeof usage.completion_tokens_details === "object"
      ? (usage.completion_tokens_details as Record<string, unknown>)
      : {};
  const rawHit = token(
    details.cached_tokens ?? details.cache_hit_tokens ?? usage.prompt_cache_hit_tokens,
  );
  const rawReportedMiss = token(
    details.cache_miss_tokens ?? usage.prompt_cache_miss_tokens,
  );
  if (
    rawHit > promptTotal ||
    rawReportedMiss > promptTotal - rawHit ||
    (rawReportedMiss > 0 && rawHit + rawReportedMiss !== promptTotal) ||
    (total > 0 && total !== promptTotal + completionTotal)
  ) {
    return null;
  }
  const hit = rawHit;
  const reportedMiss = rawReportedMiss;
  const miss = reportedMiss > 0 ? reportedMiss : promptTotal - hit;
  const thinking = token(completionDetails.reasoning_tokens ?? usage.reasoning_tokens);
  if (thinking > completionTotal) {
    return null;
  }
  return {
    ...EMPTY_LLM_USAGE,
    cacheHitTokens: hit,
    cacheMissTokens: miss,
    completionTokens: completionTotal - thinking,
    thinkingTokens: thinking,
  };
}

export function parseGeminiUsage(value: unknown): NormalizedLlmUsage | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const usage = value as Record<string, unknown>;
  const promptTotal = token(usage.promptTokenCount);
  const rawCached = token(usage.cachedContentTokenCount);
  if (rawCached > promptTotal) {
    return null;
  }
  const cached = rawCached;
  const candidates = token(usage.candidatesTokenCount);
  const thinking = token(usage.thoughtsTokenCount);
  const tool = token(usage.toolUsePromptTokenCount);
  const total = token(usage.totalTokenCount);
  if (promptTotal === 0 && candidates === 0 && thinking === 0 && tool === 0) {
    return null;
  }

  // Gemini's cached count is a subset of promptTokenCount. Tool-use prompt
  // tokens can be separately itemized but are also bounded by totalTokenCount.
  const promptWithoutCache = promptTotal - cached;
  const knownWithoutTool = promptTotal + candidates + thinking;
  if (total > 0 && (total < knownWithoutTool || total > knownWithoutTool + tool)) {
    return null;
  }
  const distinctTool = total > 0 ? Math.min(tool, Math.max(0, total - knownWithoutTool)) : tool;
  return {
    ...EMPTY_LLM_USAGE,
    promptTokens: promptWithoutCache,
    cachedTokens: cached,
    completionTokens: candidates,
    thinkingTokens: thinking,
    toolTokens: distinctTool,
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
  const hit = BigInt(usage.cacheHitTokens);
  const miss = BigInt(usage.cacheMissTokens);
  const output = BigInt(
    usage.completionTokens + usage.thinkingTokens,
  );
  const tool = BigInt(usage.toolTokens);

  switch (model) {
    case "mistral-small-latest":
      return (prompt + cached + tool) * 150n + output * 600n;
    case "gemini-3.8-flash":
      return (prompt + cached + tool) * 750n + output * 3_750n;
    case "deepseek-flash":
    case "deepseek-v4-pro":
      return hit * 30n + (miss + prompt + cached + tool) * 300n + output * 1_200n;
  }
}
