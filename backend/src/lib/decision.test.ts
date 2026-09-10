import { describe, expect, it } from "vitest";
import { composeConversation, DecisionParseError, parseDecision } from "./decision.js";

function raw(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    kind: "ready",
    input_language: "en",
    safety: "none",
    message: null,
    options: [],
    thought_en: "I bombed my interview and I keep replaying every shaky answer.",
    thought_original_cleaned: null,
    styles: ["stoic", "optimistic", "humorous", "tough_love"],
    skipped_styles: [],
    category: "work",
    proposed_category: null,
    proposed_label: null,
    tags: ["job_interview", "shame"],
    intensity: 4,
    timeframe: "past",
    emotions: ["shame", "fear"],
    ...overrides,
  });
}

describe("parseDecision", () => {
  it("reads a fenced JSON object", () => {
    const decision = parseDecision("```json\n" + raw() + "\n```");
    expect(decision.kind).toBe("ready");
  });

  it("reads JSON wrapped in prose", () => {
    const decision = parseDecision(`Here you go: ${raw()} Hope that helps.`);
    expect(decision.kind).toBe("ready");
  });

  it("rejects a reply with no object", () => {
    expect(() => parseDecision("no json here")).toThrow(DecisionParseError);
  });

  it("rejects a ready decision without a cleaned thought", () => {
    expect(() => parseDecision(raw({ thought_en: "   " }))).toThrow(DecisionParseError);
  });

  it("rejects a cleaned thought far over the card budget", () => {
    expect(() => parseDecision(raw({ thought_en: "and then ".repeat(60) }))).toThrow(
      /card budget/,
    );
  });

  it("rejects a continue with no message", () => {
    expect(() => parseDecision(raw({ kind: "continue", message: null }))).toThrow(
      DecisionParseError,
    );
  });

  it("rejects a continue on a forced turn unless safety fired", () => {
    const body = raw({ kind: "continue", message: "One more thing?" });
    expect(() => parseDecision(body, { requireReady: true })).toThrow(/final turn/);

    const safe = parseDecision(
      raw({ kind: "continue", message: "Please call 988.", safety: "self_harm" }),
      { requireReady: true },
    );
    expect(safe.kind).toBe("continue");
  });

  it("derives the matching band from intensity", () => {
    for (const [intensity, band] of [
      [1, "low"],
      [2, "low"],
      [3, "mid"],
      [4, "high"],
      [5, "high"],
    ] as const) {
      const decision = parseDecision(raw({ intensity }));
      if (decision.kind !== "ready") {
        throw new Error("expected ready");
      }
      expect(decision.meta.matching.intensityBand).toBe(band);
    }
  });

  it("clamps a nonsense intensity", () => {
    const decision = parseDecision(raw({ intensity: 11 }));
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.meta.intensity).toBe(5);
  });

  it("normalises tags and drops unknown emotions", () => {
    const decision = parseDecision(
      raw({ tags: ["Job Interview", "job interview", "  ", "Shame!"], emotions: ["shame", "vibes"] }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.meta.tags).toEqual(["job_interview", "shame"]);
    expect(decision.meta.emotions).toEqual(["shame"]);
  });

  it("falls back to the unskipped styles when the model forgets the list", () => {
    const decision = parseDecision(
      raw({
        styles: null,
        skipped_styles: [{ style: "humorous", reason: "Not funny today." }],
      }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.styles).toEqual(["stoic", "optimistic", "tough_love"]);
  });

  it("drops thoughtOriginal when it matches the English thought", () => {
    const thought = "I bombed my interview and I keep replaying every shaky answer.";
    const decision = parseDecision(raw({ thought_original_cleaned: thought }));
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.thoughtOriginal).toBeUndefined();
  });

  it("defaults a broken language tag to en", () => {
    const decision = parseDecision(raw({ input_language: "Croatian (hr)" }));
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.meta.inputLanguage).toBe("en");
  });
});

describe("composeConversation", () => {
  it("returns the thought alone with no follow-ups", () => {
    expect(composeConversation("I feel behind.", [])).toBe("I feel behind.");
  });

  it("marks the exchange as already answered", () => {
    const composed = composeConversation("I feel behind.", [
      { question: "Behind whom?", answer: "My old classmates." },
    ]);
    expect(composed).toContain("They first typed: I feel behind.");
    expect(composed).toContain("Then you asked: Behind whom?");
    expect(composed).toContain("They answered: My old classmates.");
    expect(composed).toContain("do not ask again");
  });
});
