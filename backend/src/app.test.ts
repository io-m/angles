import { beforeEach, describe, expect, it, vi } from "vitest";
import { STYLE_BATCH_PROMPT, SYSTEM_PROMPTS, THOUGHT_MAX_CHARS, THOUGHT_MAX_WORDS, THOUGHT_MIN_WORDS, REFRAME_HARD_MAX_CHARS } from "./lib/prompts.js";
import { CATEGORIES, STYLES, type Style } from "./types/index.js";

vi.mock("./lib/llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/llmClient.js")>();
  return {
    ...actual,
    generateReframe: vi.fn(),
    generateJson: vi.fn(),
  };
});

class DbError extends Error {
  readonly code?: string;
  constructor(message: string, code?: string) {
    super(message);
    this.name = "DbError";
    this.code = code;
  }
}

vi.mock("./db/client.js", () => ({
  probeDatabase: vi.fn(async () => "ok" as const),
  DbError,
  getDb: vi.fn(),
  getSql: vi.fn(),
  closePool: vi.fn(),
  assertSchemaCurrent: vi.fn(),
  wrapDbError: vi.fn(),
}));

const { app } = await import("./app.js");
const { generateJson, generateReframe, STYLE_BATCH_MAX_OUTPUT_TOKENS } = await import("./lib/llmClient.js");
const { probeDatabase } = await import("./db/client.js");

const SHORT_TEXT = "I bombed my job interview today.";
const LONG_TEXT =
  "I keep replaying the interview in my head and I cannot stop thinking that every pause and every shaky answer proved I was never going to get that job anyway.";

type DecisionOverrides = Record<string, unknown>;

function readyDecision(overrides: DecisionOverrides = {}): string {
  return JSON.stringify({
    kind: "ready",
    input_language: "en",
    safety: "none",
    message: null,
    options: [],
    thought_en: "I bombed my interview and I keep replaying every shaky answer.",
    thought_original_cleaned: null,
    styles: [...STYLES],
    skipped_styles: [],
    category: "work",
    proposed_category: null,
    proposed_label: null,
    tags: ["job_interview", "shame", "rejection"],
    intensity: 4,
    timeframe: "past",
    emotions: ["shame", "fear"],
    ...overrides,
  });
}

function continueDecision(overrides: DecisionOverrides = {}): string {
  return JSON.stringify({
    kind: "continue",
    input_language: "en",
    safety: "none",
    message: "You said the interview went badly — what part are you still replaying?",
    options: ["A question I fumbled", "How I came across"],
    thought_en: null,
    thought_original_cleaned: null,
    styles: [],
    skipped_styles: [],
    category: null,
    proposed_category: null,
    proposed_label: null,
    tags: [],
    intensity: null,
    timeframe: null,
    emotions: [],
    ...overrides,
  });
}

function styleBatch(overrides: Partial<Record<Style, string | undefined>> = {}): string {
  const body: Record<string, string> = {
    stoic: "stoic reframe",
    optimistic: "optimistic reframe",
    humorous: "humorous reframe",
    tough_love: "tough love reframe",
  };
  for (const [style, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete body[style];
    } else {
      body[style] = value;
    }
  }
  return JSON.stringify(body);
}

function isStyleBatchPrompt(systemPrompt: string): boolean {
  return systemPrompt.includes("Each JSON field is that style only");
}

let batchQueue: string[] | undefined;

function stubStyleBatch(...replies: string[]): void {
  batchQueue = [...replies];
}

function stubDecision(...replies: string[]): void {
  const queue = [...replies];
  vi.mocked(generateJson).mockImplementation(async ({ systemPrompt }) => {
    if (isStyleBatchPrompt(systemPrompt)) {
      if (batchQueue !== undefined) {
        const next = batchQueue.shift();
        if (next === undefined) {
          throw new Error("generateJson style batch called more times than stubbed");
        }
        return next;
      }
      return styleBatch();
    }
    const next = queue.shift();
    if (next === undefined) {
      throw new Error("generateJson called more times than stubbed");
    }
    return next;
  });
}

function stubReframes(): void {
  vi.mocked(generateReframe).mockImplementation(async ({ systemPrompt }) => {
    if (systemPrompt.includes("Stoic")) {
      return "stoic reframe";
    }
    if (systemPrompt.includes("Optimistic")) {
      return "optimistic reframe";
    }
    if (systemPrompt.includes("Humorous")) {
      return "humorous reframe";
    }
    if (systemPrompt.includes("Tough Love")) {
      return "tough love reframe";
    }
    return "other reframe";
  });
}

async function post(body: unknown): Promise<Response> {
  return app.request("/reframe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

type ContinueBody = { kind: string; message: string; options: string[]; safety: string };
type ReadyBody = {
  kind: string;
  thought: string;
  thoughtOriginal?: string;
  results: { style: Style; reframe: string }[];
  meta: {
    category: string;
    proposedCategory?: string;
    proposedLabel?: string;
    tags: string[];
    intensity: number;
    timeframe: string;
    emotions: string[];
    safety: string;
    inputLanguage: string;
    skippedStyles: { style: Style; reason: string }[];
    matching: { category: string; tags: string[]; intensityBand: string };
  };
};

describe("SYSTEM_PROMPTS", () => {
  it("defines a prompt for every style", () => {
    for (const style of STYLES) {
      expect(SYSTEM_PROMPTS[style].length).toBeGreaterThan(0);
    }
  });

  it("defines a batched style prompt", () => {
    expect(STYLE_BATCH_PROMPT).toContain("Each JSON field is that style only");
  });
});

describe("GET /health", () => {
  it("returns ok when the database is up", async () => {
    vi.mocked(probeDatabase).mockResolvedValueOnce("ok");
    const response = await app.request("/health");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ status: "ok", db: "ok" });
  });

  it("returns 503 when the database is down", async () => {
    vi.mocked(probeDatabase).mockResolvedValueOnce("down");
    const response = await app.request("/health");
    expect(response.status).toBe(503);
    await expect(jsonOf(response)).resolves.toEqual({ status: "error", db: "down" });
  });
});

describe("POST /reframe", () => {
  beforeEach(() => {
    vi.mocked(generateJson).mockReset();
    vi.mocked(generateReframe).mockReset();
    batchQueue = undefined;
    stubReframes();
  });

  it("always runs the decision call, even for a short statement", async () => {
    stubDecision(readyDecision());

    const response = await post({ text: SHORT_TEXT });

    expect(response.status).toBe(200);
    expect(generateJson).toHaveBeenCalledTimes(2);
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.kind).toBe("ready");
    expect(JSON.stringify(body)).not.toContain("What stings most about this?");
  });

  it("returns a continue turn with the model's own question and chips", async () => {
    stubDecision(continueDecision());

    const response = await post({ text: "ugh" });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as ContinueBody;
    expect(body).toEqual({
      kind: "continue",
      message: "You said the interview went badly — what part are you still replaying?",
      options: ["A question I fumbled", "How I came across"],
      safety: "none",
    });
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("caps continue chips at three", async () => {
    stubDecision(
      continueDecision({ options: ["one", "two", "three", "four", "five"] }),
    );

    const body = (await jsonOf(await post({ text: "ugh" }))) as ContinueBody;
    expect(body.options).toEqual(["one", "two", "three"]);
  });

  it("refuses to reframe a safety thought and returns no results", async () => {
    stubDecision(
      continueDecision({
        safety: "self_harm",
        message: "I don't want to make light of this. Please call or text 988 right now.",
        options: ["I can do that"],
      }),
    );

    const response = await post({ text: "I don't want to be here anymore." });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as ContinueBody & { results?: unknown };
    expect(body.kind).toBe("continue");
    expect(body.safety).toBe("self_harm");
    expect(body.options).toEqual([]);
    expect(body.results).toBeUndefined();
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("never ships a reframe for a ready decision that flagged safety", async () => {
    stubDecision(
      readyDecision({ safety: "self_harm" }),
      readyDecision({ safety: "self_harm" }),
    );

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(body.safety).toBe("self_harm");
    expect(body.message).toContain("988");
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("returns a card-fit thought, the chosen styles, and matching metadata", async () => {
    stubDecision(readyDecision());

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

    expect(body.kind).toBe("ready");
    const words = body.thought.split(/\s+/).length;
    expect(words).toBeGreaterThanOrEqual(THOUGHT_MIN_WORDS);
    expect(words).toBeLessThanOrEqual(THOUGHT_MAX_WORDS);
    expect(body.thought.length).toBeLessThanOrEqual(THOUGHT_MAX_CHARS);
    expect(body.thoughtOriginal).toBeUndefined();
    expect(body.results.map((item) => item.style)).toEqual([...STYLES]);
    expect(body.meta.matching).toEqual({
      category: "work",
      tags: ["job_interview", "shame", "rejection"],
      intensityBand: "high",
    });
    expect(generateJson).toHaveBeenCalledTimes(2);
    expect(generateReframe).not.toHaveBeenCalled();
    const batchCall = vi.mocked(generateJson).mock.calls.find(([call]) =>
      isStyleBatchPrompt(call.systemPrompt),
    );
    expect(batchCall?.[0].maxOutputTokens).toBe(STYLE_BATCH_MAX_OUTPUT_TOKENS);
  });

  it("keeps the cleaned original when the input was not English", async () => {
    stubDecision(
      readyDecision({
        input_language: "hr",
        thought_original_cleaned: "Zeznuo sam razgovor za posao i stalno ga vrtim u glavi.",
      }),
    );

    const body = (await jsonOf(await post({ text: "zeznia sam intervju danas jbg" }))) as ReadyBody;
    expect(body.thoughtOriginal).toBe(
      "Zeznuo sam razgovor za posao i stalno ga vrtim u glavi.",
    );
    expect(body.meta.inputLanguage).toBe("hr");
  });

  it("skips humorous on grief and reports why", async () => {
    stubDecision(
      readyDecision({
        thought_en: "My mother died last week and the house is unbearably quiet.",
        category: "grief_loss",
        emotions: ["sadness", "loneliness"],
        timeframe: "ongoing",
        intensity: 5,
        styles: ["stoic", "optimistic", "tough_love"],
        skipped_styles: [
          { style: "humorous", reason: "A joke would land wrong on a loss this fresh." },
        ],
      }),
    );

    const body = (await jsonOf(await post({ text: "my mum died last week" }))) as ReadyBody;

    expect(body.results.map((item) => item.style)).toEqual(["stoic", "optimistic", "tough_love"]);
    expect(body.meta.skippedStyles).toEqual([
      { style: "humorous", reason: "A joke would land wrong on a loss this fresh." },
    ]);
    expect(generateJson).toHaveBeenCalledTimes(2);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("keeps category inside the closed set", async () => {
    stubDecision(readyDecision());

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
    expect(CATEGORIES).toContain(body.meta.category);
  });

  it("turns an off-catalog category into other plus a proposal", async () => {
    stubDecision(readyDecision({ category: "Creative Block" }));

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
    expect(body.meta.category).toBe("other");
    expect(body.meta.proposedCategory).toBe("creative_block");
    expect(body.meta.proposedLabel).toBe("Creative Block");
  });

  it("repairs an unparseable decision reply once", async () => {
    stubDecision("Sure! Here you go:", `\`\`\`json\n${readyDecision()}\n\`\`\``);

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(200);
    expect(generateJson).toHaveBeenCalledTimes(3);
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.kind).toBe("ready");
  });

  it("fails with LLM_ERROR when the repair is also unparseable", async () => {
    stubDecision("not json", "still not json");

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(500);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "Failed to generate reframe",
      code: "LLM_ERROR",
    });
  });

  it("repairs a cleaned thought that blows past the card budget", async () => {
    stubDecision(readyDecision({ thought_en: "and then ".repeat(60) }), readyDecision());

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(200);
    expect(generateJson).toHaveBeenCalledTimes(3);
  });

  it("retries a style once when the reframe is way too long", async () => {
    stubDecision(readyDecision({ styles: ["stoic"], skipped_styles: [] }));
    stubStyleBatch(styleBatch({ stoic: "word ".repeat(120) }));
    vi.mocked(generateReframe).mockImplementation(async ({ systemPrompt }) =>
      systemPrompt.includes("too long for the card")
        ? "You cannot control the panel, only how you show up next time."
        : "word ".repeat(120),
    );

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

    expect(generateJson).toHaveBeenCalledTimes(2);
    expect(generateReframe).toHaveBeenCalledTimes(1);
    expect(body.results).toEqual([
      { style: "stoic", reframe: "You cannot control the panel, only how you show up next time." },
    ]);
  });

  it("trims at a sentence boundary when the retry is still too long", async () => {
    stubDecision(readyDecision({ styles: ["stoic"], skipped_styles: [] }));
    const sentence = "You control the next attempt. ";
    stubStyleBatch(styleBatch({ stoic: sentence.repeat(20) }));
    vi.mocked(generateReframe).mockImplementation(async () => sentence.repeat(20));

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
    const reframe = body.results[0]?.reframe ?? "";
    expect(reframe.length).toBeLessThanOrEqual(REFRAME_HARD_MAX_CHARS);
    expect(reframe.endsWith(".")).toBe(true);
  });

  it("returns one style on a recook", async () => {
    stubDecision(readyDecision());

    const body = (await jsonOf(
      await post({ text: LONG_TEXT, styles: ["humorous"] }),
    )) as ReadyBody;

    expect(body.results).toEqual([{ style: "humorous", reframe: "humorous reframe" }]);
    expect(generateReframe).toHaveBeenCalledTimes(1);
  });

  it("answers a recook of a now-inappropriate style with continue", async () => {
    stubDecision(
      readyDecision({
        styles: ["stoic", "optimistic"],
        skipped_styles: [
          { style: "humorous", reason: "A joke would land wrong on a loss this fresh." },
        ],
      }),
    );

    const body = (await jsonOf(
      await post({ text: LONG_TEXT, styles: ["humorous"] }),
    )) as ContinueBody;

    expect(body).toEqual({
      kind: "continue",
      message: "A joke would land wrong on a loss this fresh.",
      options: [],
      safety: "none",
    });
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("dedupes requested styles", async () => {
    stubDecision(readyDecision());

    const body = (await jsonOf(
      await post({ text: LONG_TEXT, styles: ["stoic", "stoic"] }),
    )) as ReadyBody;

    expect(body.results).toEqual([{ style: "stoic", reframe: "stoic reframe" }]);
    expect(generateReframe).toHaveBeenCalledTimes(1);
  });

  it("forces ready once the exchange has three follow-ups", async () => {
    stubDecision(continueDecision(), readyDecision());

    const response = await post({
      text: SHORT_TEXT,
      followUps: [
        { question: "What part stings?", answer: "The silence after" },
        { question: "What did you want?", answer: "To sound competent" },
        { question: "What happens next?", answer: "They email on Friday" },
      ],
    });

    expect(response.status).toBe(200);
    expect(generateJson).toHaveBeenCalledTimes(3);
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.kind).toBe("ready");
    const [firstCall] = vi.mocked(generateJson).mock.calls;
    expect(firstCall?.[0].systemPrompt).toContain("This is the final turn");
  });

  it("keeps the exchange open before the third follow-up", async () => {
    stubDecision(continueDecision());

    const response = await post({
      text: SHORT_TEXT,
      followUps: [{ question: "What part stings?", answer: "The silence after" }],
    });

    const body = (await jsonOf(response)) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(generateJson).toHaveBeenCalledTimes(1);
  });

  it("passes the selected model to every call in the request", async () => {
    stubDecision(readyDecision());

    const response = await post({ text: LONG_TEXT, model: "gemini-3.8-flash" });

    expect(response.status).toBe(200);
    expect(
      vi.mocked(generateJson).mock.calls.every(([call]) => call.model === "gemini-3.8-flash"),
    ).toBe(true);

    vi.mocked(generateJson).mockClear();
    vi.mocked(generateReframe).mockClear();
    stubReframes();
    stubDecision(readyDecision());

    await post({ text: LONG_TEXT, styles: ["humorous"], model: "gemini-3.8-flash" });

    expect(vi.mocked(generateJson).mock.calls[0]?.[0].model).toBe("gemini-3.8-flash");
    expect(generateReframe).toHaveBeenCalledWith(
      expect.objectContaining({ model: "gemini-3.8-flash" }),
    );
  });

  it("omits model when the body has none", async () => {
    stubDecision(readyDecision());

    await post({ text: LONG_TEXT });

    expect(vi.mocked(generateJson).mock.calls[0]?.[0].model).toBeUndefined();
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("never sends the raw text to a style call", async () => {
    stubDecision(readyDecision());

    await post({ text: LONG_TEXT });

    const batchCalls = vi.mocked(generateJson).mock.calls.filter(([call]) =>
      isStyleBatchPrompt(call.systemPrompt),
    );
    expect(batchCalls.length).toBe(1);
    for (const [call] of batchCalls) {
      expect(call.text).not.toContain("shaky answer proved");
      expect(call.text).toContain("I bombed my interview");
    }
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("rejects empty text", async () => {
    const response = await post({ text: "   " });

    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "text must not be empty",
      code: "VALIDATION_ERROR",
    });
    expect(generateJson).not.toHaveBeenCalled();
  });

  it("rejects more than six follow-ups", async () => {
    const response = await post({
      text: SHORT_TEXT,
      followUps: Array.from({ length: 7 }, (_, index) => ({
        question: `Question ${index}?`,
        answer: `Answer ${index}`,
      })),
    });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects an unknown model", async () => {
    const response = await post({ text: LONG_TEXT, model: "nope" });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects unknown styles", async () => {
    const response = await post({ text: LONG_TEXT, styles: ["nope"] });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects invalid JSON", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{not-json",
    });

    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "Malformed JSON in request body",
      code: "INVALID_JSON",
    });
  });

  it("retries only the missing style from a batch", async () => {
    stubDecision(readyDecision());
    stubStyleBatch(styleBatch({ humorous: undefined }));

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

    expect(generateReframe).toHaveBeenCalledTimes(1);
    expect(vi.mocked(generateReframe).mock.calls[0]?.[0].systemPrompt).toContain("Humorous");
    expect(body.results.map((item) => item.style)).toEqual([...STYLES]);
  });

  it("fails the whole request when a style retry fails", async () => {
    stubDecision(readyDecision());
    stubStyleBatch(styleBatch({ humorous: undefined }));
    vi.mocked(generateReframe).mockImplementation(async () => {
      throw new Error("provider exploded");
    });

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(500);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("LLM_ERROR");
  });
});
