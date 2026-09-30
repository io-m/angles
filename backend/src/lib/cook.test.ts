import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ReframeResult } from "../types/index.js";
import {
  recookStyle,
  REWRITE_MIN_REMAINING_MS,
  rewriteFlagged,
  writeStyleBatch,
  writerMaxOutputTokens,
} from "./cook.js";
import type { ReadyDecision } from "./decision.js";
import { generateJson, generateReframe, LlmError } from "./llmClient.js";

vi.mock("./llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./llmClient.js")>();
  return { ...actual, generateReframe: vi.fn(), generateJson: vi.fn() };
});

const decision: ReadyDecision = {
  kind: "ready",
  thought: "I bombed my interview and I keep replaying every shaky answer.",
  styles: ["stoic", "optimistic"],
  meta: {
    category: "work",
    tags: ["job_interview"],
    intensity: 3,
    timeframe: "past",
    emotions: ["shame"],
    distortions: ["catastrophizing"],
    safety: "none",
    inputLanguage: "en",
    skippedStyles: [],
    matching: { category: "work", tags: ["job_interview"], intensityBand: "mid" },
  },
};

const clean: ReframeResult = {
  style: "stoic",
  reframe: "The interview is over and the replay changes nothing about it. Keep what you learned and let the tape stop.",
};
const cliched: ReframeResult = {
  style: "optimistic",
  reframe: "On the bright side, every shaky answer showed you exactly which stories to tighten before the next interview.",
};

const soon = () => Date.now() + 10_000;

describe("rewriteFlagged", () => {
  beforeEach(() => {
    vi.mocked(generateReframe).mockReset();
  });

  it("rewrites only the flagged answer, once, as a rewrite call", async () => {
    vi.mocked(generateReframe).mockResolvedValueOnce(
      "Every shaky answer just showed you which stories to tighten, and the next interview gets the sharper version.",
    );
    const results = await rewriteFlagged(decision, [clean, cliched], { optimistic: "already_working: x" }, {
      deadlineAt: soon(),
    });

    expect(generateReframe).toHaveBeenCalledTimes(1);
    const call = vi.mocked(generateReframe).mock.calls[0]?.[0];
    expect(call?.callKind).toBe("rewrite");
    expect(call?.text).toContain("stock opener");
    expect(call?.text).toContain("already_working");
    expect(results[0]).toEqual(clean);
    expect(results[1]?.reframe).toMatch(/^Every shaky answer/);
  });

  it("keeps the draft when the rewrite is no better", async () => {
    vi.mocked(generateReframe).mockResolvedValueOnce("On the bright side, you got practice at interviewing under pressure today.");
    const results = await rewriteFlagged(decision, [clean, cliched], {}, { deadlineAt: soon() });
    expect(results).toEqual([clean, cliched]);
  });

  it("keeps the draft when the rewrite fails", async () => {
    vi.mocked(generateReframe).mockRejectedValueOnce(new LlmError("provider down"));
    const results = await rewriteFlagged(decision, [clean, cliched], {}, { deadlineAt: soon() });
    expect(results).toEqual([clean, cliched]);
  });

  it("ships the draft without a call when the deadline is close", async () => {
    const results = await rewriteFlagged(decision, [clean, cliched], {}, {
      deadlineAt: Date.now() + REWRITE_MIN_REMAINING_MS - 500,
    });
    expect(generateReframe).not.toHaveBeenCalled();
    expect(results).toEqual([clean, cliched]);
  });

  it("makes no call when nothing is flagged", async () => {
    await rewriteFlagged(decision, [clean], {}, { deadlineAt: soon() });
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("does not report a rewrite's model as the cook's writer", async () => {
    const onAnsweredBy = vi.fn();
    vi.mocked(generateReframe).mockResolvedValueOnce(
      "Every shaky answer just showed you which stories to tighten, and the next interview gets the sharper version.",
    );
    await rewriteFlagged(decision, [clean, cliched], {}, { deadlineAt: soon(), onAnsweredBy });
    expect(vi.mocked(generateReframe).mock.calls[0]?.[0].onAnsweredBy).toBeUndefined();
  });
});

describe("answers in their language", () => {
  const croatian: ReadyDecision = {
    ...decision,
    thought: "My boss said I'm lazy in front of the whole team.",
    thoughtOriginal: "Šef je rekao da sam lijen pred cijelim timom.",
    meta: { ...decision.meta, inputLanguage: "hr" },
  };
  const stoicEn =
    "Your boss said a word in a meeting. The word is his; what you do tomorrow is yours. Let the work answer it.";
  const stoicHr =
    "Šef je izgovorio jednu riječ na sastanku. Riječ je njegova; ono što sutra napraviš je tvoje. Neka posao odgovori.";
  const optimisticEn =
    "Being called out stings because you care how the team sees you, and that care is exactly what makes you worth keeping.";
  const optimisticHr =
    "Boli jer ti je stalo kako te tim vidi, a upravo te ta briga čini nekim koga vrijedi zadržati u timu.";

  beforeEach(() => {
    vi.mocked(generateReframe).mockReset();
    vi.mocked(generateJson).mockReset();
  });

  it("asks the batch for { en, local } pairs with double the room, and keeps both", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(
      JSON.stringify({
        plan: { stoic: "dichotomy_of_control: his word, your work", optimistic: "what_it_proves: care" },
        stoic: { en: stoicEn, local: stoicHr },
        optimistic: { en: optimisticEn, local: optimisticHr },
      }),
    );

    const results = await writeStyleBatch(croatian, ["stoic", "optimistic"], { deadlineAt: soon() });

    const call = vi.mocked(generateJson).mock.calls[0]?.[0];
    expect(call?.text).toContain("They wrote in Croatian.");
    expect(call?.text).toContain(croatian.thoughtOriginal);
    expect(call?.maxOutputTokens).toBe(writerMaxOutputTokens(2, true));
    expect(writerMaxOutputTokens(2, true)).toBeGreaterThan(writerMaxOutputTokens(2));
    const stoicSchema = (call?.jsonSchema?.schema as { properties: Record<string, { required?: string[] }> })
      .properties.stoic;
    expect(stoicSchema?.required).toEqual(["en", "local"]);
    expect(results).toEqual([
      { style: "stoic", reframe: stoicEn, reframeOriginal: stoicHr },
      { style: "optimistic", reframe: optimisticEn, reframeOriginal: optimisticHr },
    ]);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("never asks an English cook for a second version, and drops one it did not ask for", async () => {
    vi.mocked(generateJson).mockResolvedValueOnce(
      JSON.stringify({ plan: { stoic: "x" }, stoic: { en: stoicEn, local: stoicHr } }),
    );

    const results = await writeStyleBatch(decision, ["stoic"], { deadlineAt: soon() });

    expect(vi.mocked(generateJson).mock.calls[0]?.[0].text).not.toContain("They wrote in");
    expect(results).toEqual([{ style: "stoic", reframe: stoicEn }]);
  });

  it("rewrites both versions as one JSON pair when their version has a foreign number", async () => {
    const withHotline = "Šef je izgovorio jednu riječ. Nazovi 116 123 ako ti treba razgovor, a sutra neka posao odgovori.";
    vi.mocked(generateJson).mockResolvedValueOnce(JSON.stringify({ en: stoicEn, local: stoicHr }));

    const [result] = await rewriteFlagged(
      croatian,
      [{ style: "stoic", reframe: stoicEn, reframeOriginal: withHotline }],
      {},
      { deadlineAt: soon() },
    );

    const call = vi.mocked(generateJson).mock.calls[0]?.[0];
    expect(call?.callKind).toBe("rewrite");
    expect(call?.text).toContain("In the Croatian version:");
    expect(call?.text).toContain('"local"');
    expect(result).toEqual({ style: "stoic", reframe: stoicEn, reframeOriginal: stoicHr });
  });

  it("ships the English alone when their version still has a foreign number", async () => {
    const withHotline = "Šef je izgovorio jednu riječ. Nazovi 116 123 ako ti treba razgovor, a sutra neka posao odgovori.";
    vi.mocked(generateJson).mockRejectedValueOnce(new LlmError("provider down"));

    const [result] = await rewriteFlagged(
      croatian,
      [{ style: "stoic", reframe: stoicEn, reframeOriginal: withHotline }],
      {},
      { deadlineAt: soon() },
    );

    expect(result).toEqual({ style: "stoic", reframe: stoicEn });
  });

  it("recooks a bilingual cook as one JSON pair", async () => {
    const fresh =
      "A single word in a meeting is not a verdict on your work. Tomorrow you decide what the team sees next.";
    const freshHr =
      "Jedna riječ na sastanku nije presuda tvom radu. Sutra ti odlučuješ što će tim sljedeće vidjeti.";
    vi.mocked(generateJson).mockResolvedValueOnce(JSON.stringify({ en: fresh, local: freshHr }));

    const result = await recookStyle(croatian, "stoic", stoicEn, { deadlineAt: soon() });

    const call = vi.mocked(generateJson).mock.calls[0]?.[0];
    expect(call?.temperature).toBe(0.95);
    expect(call?.text).toContain(stoicEn);
    expect(call?.text).toContain("They wrote in Croatian.");
    expect(result).toEqual({ style: "stoic", reframe: fresh, reframeOriginal: freshHr });
    expect(generateReframe).not.toHaveBeenCalled();
  });
});
