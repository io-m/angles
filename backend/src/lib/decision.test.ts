import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  composeConversation,
  DecisionParseError,
  isGenericBounceContinue,
  looksLikeThought,
  normalizeSafety,
  parseDecision,
  runDecision,
} from "./decision.js";
import { generateJson, LlmError } from "./llmClient.js";
import { SAFETY_FALLBACK_MESSAGE } from "./prompts.js";

vi.mock("./llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./llmClient.js")>();
  return { ...actual, generateJson: vi.fn() };
});

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

  it("accepts a long cleaned thought only on the repair pass", () => {
    const long = `${"work keeps piling up and ".repeat(9)}I can't keep doing this.`;
    expect(() => parseDecision(raw({ thought_en: long }))).toThrow(/card budget/);
    expect(parseDecision(raw({ thought_en: long }), { repairPass: true }).kind).toBe("ready");
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

  it("treats a safety label outside the catalog as self-harm on a ready decision", () => {
    for (const label of ["suicide", "suicidal", "crisis", "Self Harm", "self-harm", "SELF_HARM"]) {
      const decision = parseDecision(raw({ safety: label }));
      if (decision.kind !== "ready") {
        throw new Error("expected ready");
      }
      expect(decision.meta.safety).toBe("self_harm");
    }
  });

  it("keeps a collapsed crisis continue flagged, without chips, even on a forced turn", () => {
    const decision = parseDecision(
      raw({ kind: "continue", message: "Please reach someone now.", options: ["OK"], safety: "suicide" }),
      { requireReady: true },
    );
    if (decision.kind !== "continue") {
      throw new Error("expected continue");
    }
    expect(decision.safety).toBe("self_harm");
    expect(decision.options).toEqual([]);
  });

  it("reads separator variants of catalog safety labels", () => {
    expect(normalizeSafety("harm-others")).toBe("harm_others");
    expect(normalizeSafety(" Abuse ")).toBe("abuse");
  });

  it("treats a missing or plainly negative safety label as none", () => {
    for (const label of [null, undefined, "", "  ", "none", "None", "null", "no", "false", "N/A", "safe"]) {
      expect(normalizeSafety(label)).toBe("none");
    }
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

  it("keeps at most two known distortions", () => {
    const decision = parseDecision(
      raw({ distortions: ["Mind Reading", "catastrophizing", "vibes", "labeling"] }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.meta.distortions).toEqual(["mind_reading", "catastrophizing"]);
  });

  it("still writes stoic and optimistic when the model tries to skip them", () => {
    const decision = parseDecision(
      raw({
        styles: ["stoic"],
        skipped_styles: [
          { style: "optimistic", reason: "Too bright." },
          { style: "humorous", reason: "A joke would land wrong." },
          { style: "tough_love", reason: "Too hard on this." },
        ],
      }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.styles).toEqual(["stoic", "optimistic"]);
    expect(decision.meta.skippedStyles.map((item) => item.style)).toEqual([
      "humorous",
      "tough_love",
    ]);
  });

  it("treats a style that is both chosen and skipped as skipped", () => {
    const decision = parseDecision(
      raw({ skipped_styles: [{ style: "humorous", reason: "A joke would land wrong." }] }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.styles).toEqual(["stoic", "optimistic", "tough_love"]);
  });

  it("holds tough love back from self-blame over a loss", () => {
    const decision = parseDecision(
      raw({
        category: "grief_loss",
        distortions: ["personalizing"],
        styles: ["stoic", "optimistic", "tough_love"],
        skipped_styles: [{ style: "humorous", reason: "Not on a loss." }],
      }),
    );
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.styles).toEqual(["stoic", "optimistic"]);
    expect(decision.meta.skippedStyles.map((item) => item.style)).toEqual(["humorous", "tough_love"]);
  });

  it("keeps tough love on self-blame outside a loss", () => {
    const decision = parseDecision(raw({ distortions: ["personalizing"] }));
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.styles).toContain("tough_love");
  });

  it("reads missing distortions as none", () => {
    const decision = parseDecision(raw());
    if (decision.kind !== "ready") {
      throw new Error("expected ready");
    }
    expect(decision.meta.distortions).toEqual([]);
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

describe("runDecision safety screen", () => {
  beforeEach(() => {
    vi.mocked(generateJson).mockReset();
  });

  const run = (text: string, followUps: { question: string; answer: string }[] = []) =>
    runDecision({ text, followUps, forceReady: false });

  it("turns a ready decision on explicit self-harm wording into crisis help", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(raw({ input_language: "en" }));
    await expect(run("Everyone would be better off without me")).resolves.toEqual({
      kind: "continue",
      message: SAFETY_FALLBACK_MESSAGE,
      options: [],
      safety: "self_harm",
      inputLanguage: "en",
    });
  });

  it("replaces a question and its chips on a thought the screen caught", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(
      raw({ kind: "continue", message: "What happened today?", options: ["Work stuff"] }),
    );
    const decision = await run("I wish I could go to sleep and never wake up");
    expect(decision).toMatchObject({ kind: "continue", safety: "self_harm", options: [] });
  });

  it("keeps the model's own crisis message when it already flagged the turn", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(
      raw({ kind: "continue", message: "I'm really glad you told me.", safety: "self_harm" }),
    );
    const decision = await run("I want to kill myself");
    expect(decision).toMatchObject({ kind: "continue", message: "I'm really glad you told me." });
  });

  it("screens the model's English copy of a thought in a language the screen has no list for", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(
      raw({
        thought_en: "I don't want to be alive anymore and nothing feels worth it.",
        thought_original_cleaned: "मैं अब और जीना नहीं चाहता, कुछ भी मायने नहीं रखता।",
        input_language: "hi",
      }),
    );
    await expect(run("मैं अब और जीना नहीं चाहता, कुछ भी मायने नहीं रखता")).resolves.toMatchObject({
      kind: "continue",
      safety: "self_harm",
      options: [],
      inputLanguage: "hi",
    });
  });

  it("screens the user's follow-up answers too", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(raw());
    const decision = await run("work has been a lot lately and nothing is going right", [
      { question: "What is weighing on you most?", answer: "honestly I don't want to be alive" },
    ]);
    expect(decision).toMatchObject({ kind: "continue", safety: "self_harm" });
  });

  it("still gives crisis help when the model fails on a screened thought", async () => {
    vi.mocked(generateJson).mockRejectedValue(new LlmError("provider down"));
    await expect(run("I want to end my life")).resolves.toMatchObject({
      kind: "continue",
      safety: "self_harm",
    });
  });

  it("tells the repair turn how long the rejected thought was", async () => {
    const long = `${"work keeps piling up and ".repeat(9)}I can't keep doing this.`;
    vi.mocked(generateJson)
      .mockResolvedValueOnce(raw({ thought_en: long }))
      .mockResolvedValueOnce(raw());
    await expect(run("work keeps piling up and my girlfriend says I'm never present")).resolves.toMatchObject({
      kind: "ready",
    });
    const repair = vi.mocked(generateJson).mock.calls[1]?.[0];
    expect(repair?.systemPrompt).toMatch(/was \d+ words and \d+ characters/);
    expect(repair?.systemPrompt).not.toContain("piling");
  });

  it("leaves idioms and ordinary failures alone", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(raw());
    await expect(run("This deadline is killing me, I have three reports due")).resolves.toMatchObject({
      kind: "ready",
    });

    vi.mocked(generateJson).mockRejectedValue(new LlmError("provider down"));
    await expect(run("This deadline is killing me, I have three reports due")).rejects.toThrow(
      LlmError,
    );
  });
});

describe("composeConversation", () => {
  it("frames a first turn in English", () => {
    expect(composeConversation("Osjećam se kao da kasnim.", [])).toBe(
      "They typed: Osjećam se kao da kasnim.",
    );
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

describe("looksLikeThought", () => {
  it("treats a family irritation sentence as a thought", () => {
    expect(
      looksLikeThought(
        "I do not have a willpower to take a walk with my wife and small annoying son",
      ),
    ).toBe(true);
  });

  it("rejects lone gestures even when they repeat past the word floor", () => {
    expect(looksLikeThought("ugh")).toBe(false);
    expect(looksLikeThought("test")).toBe(false);
    expect(looksLikeThought("hi")).toBe(false);
    expect(looksLikeThought("ugh ugh ugh ugh ugh ugh ugh ugh")).toBe(false);
  });
});

describe("isGenericBounceContinue", () => {
  it("matches the dead-end bounce from a model that pretended not to understand", () => {
    expect(isGenericBounceContinue("I didn't catch a clear thought there. Try again?")).toBe(
      true,
    );
    expect(isGenericBounceContinue("I did not catch a real thought. Please rephrase.")).toBe(
      true,
    );
    expect(isGenericBounceContinue("I don't understand.")).toBe(true);
  });

  it("lets a continue through when it names the missing fact", () => {
    expect(
      isGenericBounceContinue("You mentioned 'the thing yesterday' — what actually happened?"),
    ).toBe(false);
    expect(
      isGenericBounceContinue(
        "You said the interview went badly — what part are you still replaying?",
      ),
    ).toBe(false);
  });

  it("treats the stuck-on script as a dead-end bounce", () => {
    expect(
      isGenericBounceContinue(
        "That sounds like a positive shift. What situation are you stuck on right now?",
      ),
    ).toBe(true);
    expect(isGenericBounceContinue("What are you stuck on?")).toBe(true);
  });
});
