import { beforeEach, describe, expect, it, vi } from "vitest";
import type { LlmUsageEvent } from "./llmUsage.js";

vi.mock("./llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./llmClient.js")>();
  return {
    ...actual,
    generateJson: vi.fn(),
  };
});

vi.mock("../db/metering.js", () => ({
  beginStandaloneProviderCall: vi.fn(async () => undefined),
  recordStandaloneLlmUsage: vi.fn(async () => undefined),
}));

const { generateJson } = await import("./llmClient.js");
const { beginStandaloneProviderCall, recordStandaloneLlmUsage } = await import(
  "../db/metering.js"
);
const { moderatePublicCard, PublicModerationUnavailableError } = await import(
  "./publicModeration.js"
);

describe("moderatePublicCard", () => {
  beforeEach(() => {
    process.env.USAGE_ENFORCEMENT = "off";
    vi.mocked(generateJson).mockReset();
    vi.mocked(beginStandaloneProviderCall).mockClear();
    vi.mocked(recordStandaloneLlmUsage).mockClear();
  });

  it("allows content only when the structured result has no violations", async () => {
    vi.mocked(generateJson).mockResolvedValue(JSON.stringify({ allowed: true, violations: [] }));
    await expect(
      moderatePublicCard({ thought: "A difficult day.", reframes: ["Tomorrow is another try."] }),
    ).resolves.toBe(true);
    expect(generateJson).toHaveBeenCalledOnce();
  });

  it("rejects content with a closed violation category", async () => {
    vi.mocked(generateJson).mockResolvedValue(
      JSON.stringify({ allowed: false, violations: ["personal_data"] }),
    );
    await expect(
      moderatePublicCard({ thought: "Contact details.", reframes: ["A response."] }),
    ).resolves.toBe(false);
  });

  it("fails closed when the provider response is invalid", async () => {
    vi.mocked(generateJson).mockResolvedValue("not json");
    await expect(
      moderatePublicCard({ thought: "A difficult day.", reframes: ["A response."] }),
    ).rejects.toBeInstanceOf(PublicModerationUnavailableError);
  });

  it.each(["off", "required"] as const)(
    "records company-funded usage when enforcement is %s",
    async (enforcement) => {
      process.env.USAGE_ENFORCEMENT = enforcement;
      const event: LlmUsageEvent = {
        callKind: "moderation",
        attempt: 1,
        requestedModel: "mistral-small-latest",
        returnedModel: "mistral-small-latest",
        status: "succeeded",
        promptTokens: 10,
        cachedTokens: 0,
        cacheHitTokens: 0,
        cacheMissTokens: 0,
        completionTokens: 2,
        thinkingTokens: 0,
        toolTokens: 0,
        usageSource: "reported",
        rateVersion: "2026-09-credits-v1",
        companyCostNanoUsd: 2_700n,
      };
      vi.mocked(generateJson).mockImplementation(async (options) => {
        await options.beforeProviderCall?.();
        options.usageSink?.(event);
        return JSON.stringify({ allowed: true, violations: [] });
      });

      await expect(
        moderatePublicCard({ thought: "A difficult day.", reframes: ["Try tomorrow."] }),
      ).resolves.toBe(true);

      expect(recordStandaloneLlmUsage).toHaveBeenCalledOnce();
      expect(recordStandaloneLlmUsage).toHaveBeenCalledWith(
        expect.objectContaining({ event }),
      );
      expect(beginStandaloneProviderCall).toHaveBeenCalledTimes(
        enforcement === "required" ? 1 : 0,
      );
    },
  );
});
