import { describe, expect, it } from "vitest";
import {
  companyCostNanoUsd,
  parseDeepSeekUsage,
  parseGeminiUsage,
  parseMistralUsage,
} from "./llmUsage.js";

describe("LLM usage normalization and rates", () => {
  it("separates Mistral cached prompt tokens without double counting", () => {
    const usage = parseMistralUsage({
      prompt_tokens: 100,
      completion_tokens: 20,
      total_tokens: 120,
      prompt_tokens_details: { cached_tokens: 30 },
    });
    expect(usage).toMatchObject({
      promptTokens: 70,
      cachedTokens: 30,
      completionTokens: 20,
    });
    expect(companyCostNanoUsd("mistral-small-latest", usage!)).toBe(27_000n);
  });

  it("separates DeepSeek hit, miss, and reasoning categories", () => {
    const usage = parseDeepSeekUsage({
      prompt_tokens: 100,
      completion_tokens: 30,
      prompt_tokens_details: { cached_tokens: 40, cache_miss_tokens: 60 },
      completion_tokens_details: { reasoning_tokens: 10 },
    });
    expect(usage).toMatchObject({
      promptTokens: 0,
      cacheHitTokens: 40,
      cacheMissTokens: 60,
      completionTokens: 20,
      thinkingTokens: 10,
    });
    expect(companyCostNanoUsd("deepseek-flash", usage!)).toBe(55_200n);
  });

  it("keeps Gemini cached and thought tokens from being counted twice", () => {
    const usage = parseGeminiUsage({
      promptTokenCount: 100,
      cachedContentTokenCount: 25,
      candidatesTokenCount: 20,
      thoughtsTokenCount: 10,
      toolUsePromptTokenCount: 5,
      totalTokenCount: 135,
    });
    expect(usage).toMatchObject({
      promptTokens: 75,
      cachedTokens: 25,
      completionTokens: 20,
      thinkingTokens: 10,
      toolTokens: 5,
    });
    expect(companyCostNanoUsd("gemini-3.8-flash", usage!)).toBe(191_250n);
  });

  it("returns null when a provider omits usable accounting", () => {
    expect(parseMistralUsage(undefined)).toBeNull();
    expect(parseDeepSeekUsage({})).toBeNull();
    expect(parseGeminiUsage({ totalTokenCount: 99 })).toBeNull();
  });

  it("rejects inconsistent totals so callers estimate conservatively", () => {
    expect(
      parseMistralUsage({
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 99,
      }),
    ).toBeNull();
    expect(
      parseDeepSeekUsage({
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 15,
        prompt_cache_hit_tokens: 8,
        prompt_cache_miss_tokens: 1,
      }),
    ).toBeNull();
    expect(
      parseGeminiUsage({
        promptTokenCount: 10,
        candidatesTokenCount: 5,
        thoughtsTokenCount: 3,
        totalTokenCount: 12,
      }),
    ).toBeNull();
  });
});
