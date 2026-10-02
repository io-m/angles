import { describe, expect, it } from "vitest";
import {
  companyCostNanoUsd,
  parseMistralUsage,
  parseOpenAIUsage,
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

  it("separates OpenAI cached prompt tokens and records its cost", () => {
    const usage = parseOpenAIUsage({
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
    expect(companyCostNanoUsd("gpt-4.1-mini", usage!)).toBe(72_000n);
  });

  it("returns null when a provider omits usable accounting", () => {
    expect(parseMistralUsage(undefined)).toBeNull();
    expect(parseOpenAIUsage({})).toBeNull();
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
      parseOpenAIUsage({
        prompt_tokens: 10,
        completion_tokens: 5,
        total_tokens: 99,
      }),
    ).toBeNull();
  });
});
