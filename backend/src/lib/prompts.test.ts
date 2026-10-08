import { describe, expect, it } from "vitest";
import { STYLES } from "../types/index.js";
import {
  GOLD_CARDS,
  lintRewriteUserPrompt,
  localLanguage,
  REFRAME_MAX_WORDS,
  styleBatchPrompt,
  STYLE_VOICES,
  SYSTEM_PROMPTS,
} from "./prompts.js";
import { lintResults } from "./reframeLint.js";

describe("localLanguage", () => {
  it("names the language answers are also written in", () => {
    expect(localLanguage("hr")).toBe("Croatian");
    expect(localLanguage("de-at")).toBe("German");
    expect(localLanguage("es-419")).toBe("Spanish");
  });

  it("is nothing for English or a tag that names no language", () => {
    for (const tag of ["en", "en-gb", "und", "zxx", "qq"]) {
      expect(localLanguage(tag), tag).toBeUndefined();
    }
  });
});

describe("bilingual prompts", () => {
  it("asks for a missing version in their language by name", () => {
    const prompt = lintRewriteUserPrompt({
      thought: "My boss called me lazy.",
      meta: {
        category: "work",
        tags: [],
        intensity: 3,
        timeframe: "past",
        emotions: [],
        distortions: [],
        safety: "none",
        inputLanguage: "hr",
        skippedStyles: [],
        matching: { category: "work", tags: [], intensityBand: "mid" },
      },
      draft: "One word from him is not the whole of your work.",
      problems: [],
      others: [],
      local: { language: "Croatian", problems: [] },
    });
    expect(prompt).toContain("The Croatian version is missing.");
    expect(prompt).toContain('"local": "<the same answer in Croatian>"');
  });

  it("keeps every style prompt able to answer as a pair", () => {
    for (const style of STYLES) {
      expect(SYSTEM_PROMPTS[style]).toContain('"en" and "local"');
    }
    expect(styleBatchPrompt([...STYLES])).toContain("## Their language");
  });
});

describe("writer prompts", () => {
  it("gold examples pass the same lint the cook applies", () => {
    for (const card of GOLD_CARDS) {
      const results = STYLES.map((style) => ({ style, reframe: card.answers[style] }));
      const issues = lintResults(results, card.thought);
      for (const style of STYLES) {
        expect(issues.get(style), `${style}: ${card.answers[style]}`).toEqual([]);
        expect(card.answers[style].split(/\s+/).length).toBeLessThanOrEqual(REFRAME_MAX_WORDS);
      }
    }
  });

  it("gold plans name a technique from each style's own menu", () => {
    for (const card of GOLD_CARDS) {
      for (const style of STYLES) {
        const technique = card.plan[style].split(":")[0] ?? "";
        expect(Object.keys(STYLE_VOICES[style].techniques)).toContain(technique);
      }
    }
  });

  it("a single-style prompt names only its own style", () => {
    for (const style of STYLES) {
      for (const other of STYLES) {
        const label = STYLE_VOICES[other].label;
        expect(SYSTEM_PROMPTS[style].includes(label), `${style} prompt mentions ${label}`).toBe(
          other === style,
        );
      }
    }
  });

  it("the batch prompt asks for the plan first and keeps its marker", () => {
    const prompt = styleBatchPrompt([...STYLES]);
    expect(prompt).toContain("Each JSON field is that style only");
    expect(prompt).toContain('"plan"');
    for (const style of STYLES) {
      expect(prompt).toContain(`${style} (${STYLE_VOICES[style].label})`);
    }
  });

  it("the batch prompt carries only the voices this cook writes", () => {
    const chosen = ["stoic", "optimistic", "tender", "values"] as const;
    const prompt = styleBatchPrompt(chosen);
    for (const style of STYLES) {
      expect(prompt.includes(`${style} (${STYLE_VOICES[style].label})`), style).toBe(
        (chosen as readonly string[]).includes(style),
      );
    }
    expect(prompt).not.toContain(GOLD_CARDS[0]?.answers.humorous ?? "unreachable");
    expect(prompt).toContain(GOLD_CARDS[0]?.answers.tender ?? "unreachable");
    expect(styleBatchPrompt(chosen)).toBe(prompt);
    expect(prompt.length).toBeLessThan(styleBatchPrompt([...STYLES]).length);
  });
});
