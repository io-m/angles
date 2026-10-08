import { beforeEach, describe, expect, it, vi } from "vitest";
import { DECISION_PROMPT, GRAVE_HUMOR_SKIP_REASON, GRAVE_TOUGH_LOVE_SKIP_REASON, styleBatchPrompt, SYSTEM_PROMPTS, THOUGHT_MAX_CHARS, THOUGHT_MAX_WORDS, THOUGHT_MIN_WORDS, REFRAME_HARD_MAX_CHARS } from "./lib/prompts.js";
import { signCook, signResult, verifyCook, type SignableMeta } from "./lib/cookSignature.js";
import { CATEGORIES, STYLES, type Style } from "./types/index.js";
import { LEGACY_STYLES } from "./lib/styleSet.js";

vi.mock("./lib/llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/llmClient.js")>();
  return {
    ...actual,
    generateReframe: vi.fn(),
    generateJson: vi.fn(),
  };
});

vi.mock("./db/metering.js", () => {
  class MeteringError extends Error {
    readonly status: 400 | 402 | 409 | 429;
    readonly code: string;
    constructor(message: string, code: string, status: 400 | 402 | 409 | 429) {
      super(message);
      this.name = "MeteringError";
      this.status = status;
      this.code = code;
    }
  }
  const summary = {
    creditsGranted: 600,
    creditsRemaining: 599,
    periodStart: "2026-09-01T00:00:00.000Z",
    periodEnd: "2026-10-01T00:00:00.000Z",
    resetsAt: "2026-10-01T00:00:00.000Z",
    warning: "normal" as const,
    creditCost: 1,
    plan: "membership" as const,
  };
  return {
    MeteringError,
    startMeterOperation: vi.fn(async (input: {
      ownerId: string;
      model: string;
      clientRequestId: string;
      requestFingerprint: string;
    }) => ({
      operationId: "00000000-0000-4000-8000-000000000777",
      ownerId: input.ownerId,
      model: input.model,
      taste: false,
      usage: summary,
    })),
    beginProviderCall: vi.fn(async () => undefined),
    beginStandaloneProviderCall: vi.fn(async () => undefined),
    finishMeterOperation: vi.fn(async () => summary),
    findReframeReplay: vi.fn(async () => null),
    getUsageSummary: vi.fn(async () => summary),
    recordStandaloneLlmUsage: vi.fn(async () => undefined),
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
const { DEV_USER_ID } = await import("./lib/authStub.js");
const { generateJson, generateReframe, LlmError } = await import("./lib/llmClient.js");
const { writerMaxOutputTokens } = await import("./lib/cook.js");
const { probeDatabase } = await import("./db/client.js");
const { findReframeReplay, finishMeterOperation, MeteringError, startMeterOperation } =
  await import("./db/metering.js");

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
    solemn: false,
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
    solemn: false,
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

async function post(body: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return app.request("/reframe", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

/** What a build that knows all six styles sends. */
const EXTENDED = { "Angles-Style-Set": "2" };

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

type ResponseUsage = {
  creditsUsed: number;
  remaining: number;
  granted: number;
  resetsAt: string | null;
  warning: string;
  creditCost: number;
};
type ContinueBody = {
  kind: string;
  message: string;
  options: string[];
  safety: string;
  crisisResource?: string;
  usage: ResponseUsage;
};
type ReadyBody = {
  kind: string;
  thought: string;
  thoughtOriginal?: string;
  results: { style: Style; reframe: string; reframeOriginal?: string; signature: string }[];
  model: string;
  signature: string;
  usage: ResponseUsage;
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
    expect(styleBatchPrompt([...STYLES])).toContain("Each JSON field is that style only");
  });

  it("cooks a named situation instead of bouncing it as nonsense", () => {
    expect(DECISION_PROMPT).toContain("small annoying son");
    expect(DECISION_PROMPT).toContain("If you can name the situation in one clause");
    expect(DECISION_PROMPT).not.toContain("invite them to try again");
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
    vi.unstubAllEnvs();
    delete process.env.USAGE_ENFORCEMENT;
    vi.mocked(generateJson).mockReset();
    vi.mocked(generateReframe).mockReset();
    vi.mocked(startMeterOperation).mockClear();
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
    expect(body).toMatchObject({
      kind: "continue",
      message: "You said the interview went badly — what part are you still replaying?",
      options: ["A question I fumbled", "How I came across"],
      safety: "none",
    });
    expect(generateReframe).not.toHaveBeenCalled();
    expect(body.usage).toMatchObject({
      creditsUsed: 0,
      remaining: 599,
      granted: 600,
      creditCost: 1,
    });
  });

  it("repairs a generic bounce continue on a thought that was already clear", async () => {
    stubDecision(
      continueDecision({
        message: "I didn't catch a clear thought there. Try again?",
        options: [],
      }),
      readyDecision({
        thought_en:
          "I don't have the willpower to take a walk with my wife and small annoying son.",
        category: "family",
        tags: ["willpower", "walk", "parenting"],
        emotions: ["overwhelm"],
        timeframe: "ongoing",
      }),
    );

    const response = await post({
      text: "I do not have a willpower to take a walk with my wife and small annoying son",
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.kind).toBe("ready");
    expect(body.meta.category).toBe("family");
    expect(body.thought).toContain("annoying son");
    expect(generateJson).toHaveBeenCalledTimes(3);
    expect(vi.mocked(generateJson).mock.calls[1]?.[0].systemPrompt).toContain(
      "already names a situation",
    );
  });

  it("repairs a stuck-on continue when the thought is already good news", async () => {
    stubDecision(
      continueDecision({
        message: "That sounds like a positive shift. What situation are you stuck on right now?",
        options: [
          "I'm not stuck, I'm just testing",
          "I'm happy with my unemployment",
          "I'm unsure about my side projects",
        ],
      }),
      readyDecision({
        thought_en:
          "I am happy about being unemployed right now, because I can be with my son and work on side projects.",
        category: "work",
        tags: ["unemployment", "son", "side_projects"],
        intensity: 1,
        emotions: [],
        timeframe: "ongoing",
      }),
    );

    const response = await post({
      text: "I am actually very happy about the current state of my unemployment! I can be with my son and work on side projects",
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.kind).toBe("ready");
    expect(body.thought).toContain("happy");
    expect(body.thought).toContain("son");
    expect(body.meta.emotions).toEqual([]);
    expect(body.results).toHaveLength(4);
    expect(generateJson).toHaveBeenCalledTimes(3);
    const repairPrompt = vi.mocked(generateJson).mock.calls[1]?.[0].systemPrompt ?? "";
    expect(repairPrompt).toContain("already names a situation");
    expect(repairPrompt).toContain("keep the gladness");
  });

  it("still asks what they are stuck on when the input is only ugh", async () => {
    stubDecision(
      continueDecision({
        message: "What situation are you stuck on right now?",
        options: [],
      }),
    );

    const body = (await jsonOf(await post({ text: "ugh" }))) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(body.message).toContain("stuck on");
    expect(generateJson).toHaveBeenCalledTimes(1);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("keeps a continue that names the missing fact", async () => {
    stubDecision(
      continueDecision({
        message: "You mentioned 'the thing yesterday' — what actually happened?",
        options: ["My boss called me out"],
      }),
    );

    const body = (await jsonOf(
      await post({ text: "everything is fine i guess but the thing yesterday" }),
    )) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(body.message).toContain("the thing yesterday");
    expect(generateJson).toHaveBeenCalledTimes(1);
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
        message: "I don't want to make light of this. Please reach someone right now.",
        options: ["I can do that"],
      }),
    );

    const response = await post({ text: "I don't want to be here anymore.", region: "US" });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as ContinueBody & { results?: unknown };
    expect(body.kind).toBe("continue");
    expect(body.safety).toBe("self_harm");
    expect(body.message).toBe("I don't want to make light of this. Please reach someone right now.");
    expect(body.crisisResource).toContain("988");
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
    expect(body.message).not.toMatch(/\d/);
    expect(body.crisisResource).toBeDefined();
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("never ships a reframe when the model uses a safety label outside the catalog", async () => {
    stubDecision(readyDecision({ safety: "suicide" }));

    const body = (await jsonOf(await post({ text: LONG_TEXT, region: "HR" }))) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(body.safety).toBe("self_harm");
    expect(body.crisisResource).toContain("112");
    expect(body.crisisResource).not.toContain("988");
    expect(generateJson).toHaveBeenCalledTimes(1);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("keeps an off-catalog crisis continue on a forced turn instead of repairing it into a cook", async () => {
    stubDecision(
      continueDecision({ safety: "self-injury", message: "Please reach a real person now.", options: ["OK"] }),
    );

    const body = (await jsonOf(
      await post({
        text: SHORT_TEXT,
        followUps: [
          { question: "What happened?", answer: "Everything." },
          { question: "Since when?", answer: "Months." },
          { question: "And now?", answer: "I want it to stop." },
        ],
      }),
    )) as ContinueBody;
    expect(body.kind).toBe("continue");
    expect(body.safety).toBe("self_harm");
    expect(body.options).toEqual([]);
    expect(generateJson).toHaveBeenCalledTimes(1);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("replaces a crisis message that names a number, since the model cannot know the country", async () => {
    stubDecision(
      continueDecision({ safety: "self_harm", message: "Please call 988 right now.", options: [] }),
    );

    const body = (await jsonOf(await post({ text: SHORT_TEXT, region: "DK" }))) as ContinueBody;
    expect(body.message).not.toContain("988");
    expect(body.message).not.toMatch(/\d/);
    expect(body.crisisResource).toContain("112");
  });

  it("falls back to the generic crisis line for a missing or malformed region", async () => {
    stubDecision(
      continueDecision({ safety: "abuse", message: "You should not be alone with this." }),
      continueDecision({ safety: "abuse", message: "You should not be alone with this." }),
    );

    const missing = (await jsonOf(await post({ text: SHORT_TEXT }))) as ContinueBody;
    const malformed = await post({ text: SHORT_TEXT, region: "not-a-region" });
    expect(malformed.status).toBe(200);
    const malformedBody = (await jsonOf(malformed)) as ContinueBody;
    for (const body of [missing, malformedBody]) {
      expect(body.crisisResource).toBe(
        "If you are in danger, call your local emergency number now, or reach out to someone you trust.",
      );
    }
  });

  it("sends no crisis line on an ordinary continue", async () => {
    stubDecision(continueDecision());

    const body = (await jsonOf(await post({ text: SHORT_TEXT, region: "US" }))) as ContinueBody;
    expect(body.safety).toBe("none");
    expect(body.crisisResource).toBeUndefined();
  });

  it("keeps crisis numbers out of the model prompts", () => {
    expect(DECISION_PROMPT).not.toMatch(/\b988\b|\b112\b|\b911\b/);
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
    expect(body.usage).toMatchObject({
      creditsUsed: 1,
      remaining: 599,
      granted: 600,
      creditCost: 1,
    });
    expect(body.results.map((item) => item.style)).toEqual([...LEGACY_STYLES]);
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
    expect(batchCall?.[0].maxOutputTokens).toBe(writerMaxOutputTokens(LEGACY_STYLES.length));
    expect(batchCall?.[0].maxOutputTokens).toBeGreaterThanOrEqual(
      LEGACY_STYLES.length * Math.ceil(REFRAME_HARD_MAX_CHARS / 3),
    );
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

  it("never writes a joke or a push on grief, and reports why", async () => {
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

    expect(body.results.map((item) => item.style)).toEqual(["stoic", "optimistic"]);
    expect(body.meta.skippedStyles).toEqual([
      { style: "humorous", reason: GRAVE_HUMOR_SKIP_REASON },
      { style: "tough_love", reason: GRAVE_TOUGH_LOVE_SKIP_REASON },
    ]);
    expect(generateJson).toHaveBeenCalledTimes(2);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  describe("style set", () => {
    const ranked = ["tender", "values", "humorous", "stoic", "optimistic", "tough_love"];
    const sixAnswers = () =>
      styleBatch({
        tender: "Watching your sister go through this is its own kind of weight, and you are allowed to feel all of it.",
        values: "The fear comes from how much she means to you, and that love is worth every sleepless hour it costs.",
      });

    it("never offers tender or values to an app that did not ask for them", async () => {
      stubDecision(readyDecision({ styles: ranked }));
      stubStyleBatch(sixAnswers());

      const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

      expect(body.results.map((item) => item.style)).toEqual(["humorous", "stoic", "optimistic", "tough_love"]);
      expect(JSON.stringify(body)).not.toMatch(/"(tender|values)"/);
    });

    it("writes the model's four best for an app that knows all six, best first", async () => {
      stubDecision(readyDecision({ styles: ranked }));
      stubStyleBatch(sixAnswers());

      const body = (await jsonOf(await post({ text: LONG_TEXT }, EXTENDED))) as ReadyBody;

      expect(body.results.map((item) => item.style)).toEqual(["tender", "values", "humorous", "stoic"]);
      const batch = vi.mocked(generateJson).mock.calls.find(([call]) => call.callKind === "batch")?.[0];
      expect(batch?.systemPrompt).toContain("tender (Tender)");
      expect(batch?.systemPrompt).not.toContain("tough_love (Tough Love)");
    });

    it("gives a solemn thought tender and values instead of a joke and a push", async () => {
      stubDecision(
        readyDecision({
          thought_en: "I am deeply concerned about Russian bombing of civilians in Ukraine.",
          solemn: true,
          styles: ["humorous", "stoic", "tender", "optimistic", "values"],
        }),
      );
      stubStyleBatch(sixAnswers());

      const body = (await jsonOf(await post({ text: LONG_TEXT }, EXTENDED))) as ReadyBody;

      expect(body.results.map((item) => item.style)).toEqual(["stoic", "tender", "optimistic", "values"]);
      expect(body.meta.skippedStyles.map((item) => item.style)).toEqual(["humorous", "tough_love"]);
    });

    it("refuses a recook of a style the app cannot show", async () => {
      stubDecision(readyDecision());
      const cook = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
      vi.mocked(generateJson).mockClear();

      const response = await post({
        recook: {
          style: "tender",
          cook: { thought: cook.thought, meta: cook.meta, model: cook.model, signature: cook.signature },
        },
      });

      expect(response.status).toBe(400);
      await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
      expect(generateJson).not.toHaveBeenCalled();
    });
  });

  it("drops a written joke that names real harm before signing the cook", async () => {
    stubDecision(readyDecision({ thought_en: "I keep worrying about the news and can't focus at work." }));
    stubStyleBatch(
      styleBatch({
        humorous: "Your brain set the soundtrack: heavy drums and a chorus of air raid sirens, then a sudden urge to bake.",
      }),
    );

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

    expect(body.results.map((item) => item.style)).toEqual(["stoic", "optimistic"]);
    expect(body.meta.skippedStyles.map((item) => item.style)).toEqual(["humorous", "tough_love"]);
    expect(
      verifyCook({
        ownerId: DEV_USER_ID,
        thought: body.thought,
        model: body.model,
        meta: (({ matching: _matching, ...rest }) => rest)(body.meta) as SignableMeta,
        signature: body.signature,
        results: [],
      }),
    ).toBe(true);
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

  it("trims a long batch reframe to the card and tries one targeted rewrite", async () => {
    stubDecision(readyDecision({ styles: ["stoic"], skipped_styles: [] }));
    stubStyleBatch(styleBatch({ stoic: "word ".repeat(120) }));
    vi.mocked(generateReframe).mockRejectedValueOnce(new LlmError("provider down"));
    const response = await post({ text: LONG_TEXT });
    const body = (await jsonOf(response)) as ReadyBody;

    expect(response.status).toBe(200);
    expect(generateJson).toHaveBeenCalledTimes(2);
    expect(generateReframe).toHaveBeenCalledTimes(1);
    expect(vi.mocked(generateReframe).mock.calls[0]?.[0].callKind).toBe("rewrite");
    expect(body.results[0]?.reframe.length).toBeLessThanOrEqual(REFRAME_HARD_MAX_CHARS);
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

  describe("recook", () => {
    const NEW_HUMOR =
      "Your brain replayed the interview so often it now qualifies as a streaming series, and nobody renewed it.";

    async function signedCook(decisionOverrides: DecisionOverrides = {}): Promise<ReadyBody> {
      stubDecision(readyDecision(decisionOverrides));
      const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
      vi.mocked(generateJson).mockClear();
      vi.mocked(generateReframe).mockClear();
      return body;
    }

    function recookOf(cook: ReadyBody, style: Style, overrides: Record<string, unknown> = {}) {
      const previous = cook.results.find((item) => item.style === style);
      return {
        recook: {
          style,
          cook: {
            thought: cook.thought,
            ...(cook.thoughtOriginal ? { thoughtOriginal: cook.thoughtOriginal } : {}),
            meta: cook.meta,
            model: cook.model,
            signature: cook.signature,
          },
          ...(previous
            ? {
                previous: {
                  reframe: previous.reframe,
                  ...(previous.reframeOriginal ? { reframeOriginal: previous.reframeOriginal } : {}),
                  signature: previous.signature,
                },
              }
            : {}),
          ...overrides,
        },
      };
    }

    it("writes one new answer from the signed cook without a decision call", async () => {
      const cook = await signedCook();
      vi.mocked(generateReframe).mockResolvedValueOnce(NEW_HUMOR);

      const response = await post(recookOf(cook, "humorous"));
      const body = (await jsonOf(response)) as ReadyBody;

      expect(response.status).toBe(200);
      expect(generateJson).not.toHaveBeenCalled();
      expect(generateReframe).toHaveBeenCalledTimes(1);
      const call = vi.mocked(generateReframe).mock.calls[0]?.[0];
      expect(call?.temperature).toBe(0.95);
      expect(call?.text).toContain("humorous reframe");
      expect(call?.text).toContain("different technique");
      expect(body.results).toEqual([
        {
          style: "humorous",
          reframe: NEW_HUMOR,
          signature: signResult(DEV_USER_ID, cook.thought, "humorous", NEW_HUMOR),
        },
      ]);
      expect(body.thought).toBe(cook.thought);
      expect(body.model).toBe(cook.model);
      expect(body.signature).toBe(cook.signature);
      expect(body.usage.creditsUsed).toBe(1);
      expect(vi.mocked(startMeterOperation).mock.calls.at(-1)?.[0].kind).toBe("recook");
    });

    it("answers a skipped style with its reason, without a model call or a charge", async () => {
      const cook = await signedCook({
        styles: ["stoic", "optimistic"],
        skipped_styles: [{ style: "humorous", reason: "A joke would land wrong on a loss this fresh." }],
      });

      const body = (await jsonOf(await post(recookOf(cook, "humorous")))) as ContinueBody;

      expect(body).toMatchObject({
        kind: "continue",
        message: "A joke would land wrong on a loss this fresh.",
        options: [],
        safety: "none",
      });
      expect(body.usage.creditsUsed).toBe(0);
      expect(generateJson).not.toHaveBeenCalled();
      expect(generateReframe).not.toHaveBeenCalled();
    });

    it("refuses a joke or a push on a grave cook signed before solemn existed", async () => {
      const ordinary = await signedCook();
      const thought = "I am deeply concerned about Russian bombing of civilians in Ukraine.";
      const signature = signCook({
        ownerId: DEV_USER_ID,
        thought,
        model: ordinary.model,
        meta: (({ matching: _matching, ...rest }) => rest)(ordinary.meta) as SignableMeta,
      });
      const grave = { ...ordinary, thought, signature, results: [] };

      for (const style of ["humorous", "tough_love"] as const) {
        const body = (await jsonOf(await post(recookOf(grave, style)))) as ContinueBody;
        expect(body).toMatchObject({ kind: "continue", options: [], safety: "none" });
        expect(body.message).toMatch(/grave/);
        expect(body.usage.creditsUsed).toBe(0);
      }
      expect(generateJson).not.toHaveBeenCalled();
      expect(generateReframe).not.toHaveBeenCalled();
    });

    it.each([
      ["thought", (cook: ReadyBody) => ({ cook: { ...recookOf(cook, "stoic").recook.cook, thought: "Something never cooked." } })],
      ["meta", (cook: ReadyBody) => ({ cook: { ...recookOf(cook, "stoic").recook.cook, meta: { ...cook.meta, category: "money" } } })],
      ["model", (cook: ReadyBody) => ({ cook: { ...recookOf(cook, "stoic").recook.cook, model: "gpt-4.1-mini" } })],
      ["previous answer", () => ({ previous: { reframe: "Words the server never wrote.", signature: "forged" } })],
    ])("rejects a recook with a tampered %s before any model call", async (_field, override) => {
      const cook = await signedCook();
      vi.mocked(startMeterOperation).mockClear();

      const response = await post(recookOf(cook, "stoic", override(cook)));

      expect(response.status).toBe(400);
      await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
      expect(startMeterOperation).not.toHaveBeenCalled();
      expect(generateReframe).not.toHaveBeenCalled();
    });

    it("rejects a recook signed for another account", async () => {
      const cook = await signedCook();
      const forged = signCook({
        ownerId: "00000000-0000-4000-8000-000000000199",
        thought: cook.thought,
        thoughtOriginal: cook.thoughtOriginal,
        model: cook.model,
        meta: (({ matching: _matching, ...rest }) => rest)(cook.meta) as SignableMeta,
      });
      const body = recookOf(cook, "stoic");
      const response = await post({ recook: { ...body.recook, cook: { ...body.recook.cook, signature: forged } } });

      expect(response.status).toBe(400);
    });

    it("rejects text and recook together", async () => {
      const cook = await signedCook();
      const response = await post({ text: LONG_TEXT, ...recookOf(cook, "stoic") });

      expect(response.status).toBe(400);
      await expect(jsonOf(response)).resolves.toMatchObject({ code: "VALIDATION_ERROR" });
    });

    it("signs both versions of a bilingual cook, and a recook must echo the pair it replaces", async () => {
      // A request without the style set header writes only the original four.
      const pairs: Partial<Record<Style, { en: string; local: string }>> = {
        stoic: {
          en: "One rough interview is a single afternoon, not a verdict on your whole career. Keep the lesson and let the tape stop.",
          local: "Jedan loš intervju je jedno poslijepodne, a ne presuda cijeloj karijeri. Zadrži lekciju i pusti snimku da stane.",
        },
        optimistic: {
          en: "Every shaky answer showed you exactly which stories to tighten, so the next panel meets a sharper version of you.",
          local: "Svaki drhtavi odgovor pokazao ti je koje priče treba zategnuti, pa sljedeća komisija upoznaje oštriju verziju tebe.",
        },
        humorous: {
          en: "Your brain has now rewatched that interview more times than any streaming hit, and still nobody is renewing the show.",
          local: "Mozak je taj intervju pogledao više puta od bilo koje serije, a nitko i dalje ne produljuje sezonu.",
        },
        tough_love: {
          en: "Replaying it will not change the outcome. Write down the two answers you fumbled, fix them tonight, and send the thank-you note.",
          local: "Vrtjeti to neće promijeniti ishod. Zapiši dva odgovora koja si zeznuo, popravi ih večeras i pošalji zahvalu.",
        },
      };
      const pair = (style: Style) => pairs[style] ?? { en: "", local: "" };
      const fresh = {
        en: "The interview happened once; the replay is happening hourly. Only one of those is still up to you tonight.",
        local: "Intervju se dogodio jednom, a vrtiš ga svaki sat. Samo je jedno od toga još uvijek na tebi večeras.",
      };
      stubDecision(
        readyDecision({
          input_language: "hr",
          thought_original_cleaned: "Upropastio sam intervju i stalno vrtim svaki drhtavi odgovor.",
        }),
        JSON.stringify(fresh),
      );
      stubStyleBatch(
        JSON.stringify({
          plan: Object.fromEntries(STYLES.map((style) => [style, `${style}: plan`])),
          ...Object.fromEntries(STYLES.map((style) => [style, pair(style)])),
        }),
      );

      const cook = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

      const stoic = cook.results.find((item) => item.style === "stoic");
      expect(stoic?.reframeOriginal).toBe(pair("stoic").local);
      expect(stoic?.signature).toBe(
        signResult(DEV_USER_ID, cook.thought, "stoic", pair("stoic").en, pair("stoic").local),
      );
      expect(stoic?.signature).not.toBe(signResult(DEV_USER_ID, cook.thought, "stoic", pair("stoic").en));

      const withoutLocal = recookOf(cook, "stoic", {
        previous: { reframe: stoic?.reframe, signature: stoic?.signature },
      });
      expect((await post(withoutLocal)).status).toBe(400);

      const recooked = recookOf(cook, "stoic", {
        previous: { reframe: stoic?.reframe, reframeOriginal: stoic?.reframeOriginal, signature: stoic?.signature },
      });
      const body = (await jsonOf(await post(recooked))) as ReadyBody;
      expect(body.results).toEqual([
        {
          style: "stoic",
          reframe: fresh.en,
          reframeOriginal: fresh.local,
          signature: signResult(DEV_USER_ID, cook.thought, "stoic", fresh.en, fresh.local),
        },
      ]);
    });

    it("rewrites a recook that only rewords the answer it replaces", async () => {
      const cook = await signedCook();
      vi.mocked(generateReframe)
        .mockResolvedValueOnce("humorous reframe again")
        .mockResolvedValueOnce(NEW_HUMOR);

      const body = (await jsonOf(await post(recookOf(cook, "humorous")))) as ReadyBody;

      expect(generateReframe).toHaveBeenCalledTimes(2);
      expect(vi.mocked(generateReframe).mock.calls[1]?.[0].callKind).toBe("rewrite");
      expect(body.results[0]?.reframe).toBe(NEW_HUMOR);
    });
  });

  it("signs a cook so the save verifies, and a tampered save does not", async () => {
    stubDecision(readyDecision());

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
    const { matching: _matching, ...meta } = body.meta;
    const cook = {
      ownerId: DEV_USER_ID,
      thought: body.thought,
      thoughtOriginal: body.thoughtOriginal,
      model: body.model,
      meta: meta as SignableMeta,
      signature: body.signature,
      results: body.results,
    };

    expect(verifyCook(cook)).toBe(true);
    expect(verifyCook({ ...cook, model: "gpt-4.1-mini" })).toBe(false);
    expect(verifyCook({ ...cook, ownerId: "00000000-0000-4000-8000-000000000199" })).toBe(false);
    expect(verifyCook({ ...cook, thought: `${cook.thought} Also post this.` })).toBe(false);
    expect(verifyCook({ ...cook, meta: { ...cook.meta, safety: "self_harm" } })).toBe(false);
    expect(
      verifyCook({
        ...cook,
        results: cook.results.map((item) => ({ ...item, reframe: `${item.reframe}!` })),
      }),
    ).toBe(false);
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

  it("routes the decision and the writer to their own configured models", async () => {
    vi.stubEnv("LLM_DECISION_MODEL", "mistral-small-latest");
    vi.stubEnv("LLM_WRITER_MODEL", "gpt-4.1-mini");
    vi.stubEnv("LLM_WRITER_FALLBACK_MODEL", "mistral-small-latest");
    stubDecision(readyDecision());

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(200);
    const [decisionCall, batchCall] = vi.mocked(generateJson).mock.calls.map(([call]) => call);
    expect(decisionCall?.model).toBe("mistral-small-latest");
    expect(batchCall?.model).toBe("gpt-4.1-mini");
    expect(batchCall?.fallbackModel).toBe("mistral-small-latest");
    const body = (await jsonOf(response)) as ReadyBody;
    expect(body.model).toBe("gpt-4.1-mini");

    vi.mocked(generateJson).mockClear();
    vi.mocked(generateReframe).mockClear();
    vi.mocked(generateReframe).mockResolvedValueOnce(
      "Your brain replayed the interview so often it now qualifies as a streaming series, and nobody renewed it.",
    );
    const humorous = body.results.find((item) => item.style === "humorous");
    await post({
      recook: {
        style: "humorous",
        cook: { thought: body.thought, meta: body.meta, model: body.model, signature: body.signature },
        previous: { reframe: humorous?.reframe, signature: humorous?.signature },
      },
    });

    expect(generateJson).not.toHaveBeenCalled();
    expect(generateReframe).toHaveBeenCalledWith(
      expect.objectContaining({ model: "gpt-4.1-mini", fallbackModel: "mistral-small-latest" }),
    );
  });

  it("signs and returns the fallback writer when it answered", async () => {
    vi.mocked(generateJson).mockImplementation(async (input) => {
      if (isStyleBatchPrompt(input.systemPrompt)) {
        input.onAnsweredBy?.("mistral-small-latest");
        return styleBatch();
      }
      return readyDecision();
    });

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;
    const { matching: _matching, ...meta } = body.meta;

    expect(body.model).toBe("mistral-small-latest");
    expect(
      verifyCook({
        ownerId: DEV_USER_ID,
        thought: body.thought,
        thoughtOriginal: body.thoughtOriginal,
        model: "mistral-small-latest",
        meta: meta as SignableMeta,
        signature: body.signature,
        results: body.results,
      }),
    ).toBe(true);
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

  it("rejects a cook without a session", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer none" },
      body: JSON.stringify({ text: SHORT_TEXT }),
    });

    expect(response.status).toBe(401);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "Sign in required",
      code: "UNAUTHENTICATED",
    });
    expect(generateJson).not.toHaveBeenCalled();
  });

  it("requires a UUID idempotency key when usage enforcement is required", async () => {
    process.env.USAGE_ENFORCEMENT = "required";
    const missing = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: SHORT_TEXT }),
    });
    expect(missing.status).toBe(400);
    expect(await jsonOf(missing)).toMatchObject({ code: "IDEMPOTENCY_KEY_REQUIRED" });

    const invalid = await app.request("/reframe", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": "not-a-uuid",
      },
      body: JSON.stringify({ text: SHORT_TEXT }),
    });
    expect(invalid.status).toBe(400);
    expect(await jsonOf(invalid)).toMatchObject({ code: "INVALID_IDEMPOTENCY_KEY" });
    expect(generateJson).not.toHaveBeenCalled();
  });

  it("assigns distinct random request IDs to identical enforcement-off requests", async () => {
    stubDecision(continueDecision(), continueDecision());

    expect((await post({ text: SHORT_TEXT })).status).toBe(200);
    expect((await post({ text: SHORT_TEXT })).status).toBe(200);

    const firstId = vi.mocked(startMeterOperation).mock.calls[0]?.[0].clientRequestId;
    const secondId = vi.mocked(startMeterOperation).mock.calls[1]?.[0].clientRequestId;
    expect(firstId).toMatch(/^[0-9a-f-]{36}$/);
    expect(secondId).toMatch(/^[0-9a-f-]{36}$/);
    expect(firstId).not.toBe(secondId);
    expect(
      vi.mocked(startMeterOperation).mock.calls[0]?.[0].requestFingerprint,
    ).toBe(
      vi.mocked(startMeterOperation).mock.calls[1]?.[0].requestFingerprint,
    );
  });

  describe("replay of a finished request", () => {
    const REQUEST_ID = "00000000-0000-4000-8000-000000000abc";
    const REPLAY_KEY = Buffer.alloc(32, 7).toString("base64url");

    async function postWithReplayKey(body: unknown, replayKey: string = REPLAY_KEY) {
      return app.request("/reframe", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": REQUEST_ID,
          "Replay-Key": replayKey,
        },
        body: JSON.stringify(body),
      });
    }

    function alreadyCompleted() {
      vi.mocked(startMeterOperation).mockRejectedValueOnce(
        new MeteringError("Request already completed", "REQUEST_ALREADY_COMPLETED", 409),
      );
    }

    beforeEach(() => {
      vi.mocked(finishMeterOperation).mockClear();
      vi.mocked(findReframeReplay).mockReset();
      vi.mocked(findReframeReplay).mockResolvedValue(null);
    });

    function sealedFromFinish() {
      const call = vi.mocked(finishMeterOperation).mock.calls.at(-1)?.[0];
      expect(call?.replay).toBeDefined();
      return call!.replay!;
    }

    it("stores no plaintext and returns the same signed cook to a retry", async () => {
      stubDecision(readyDecision());
      const first = await postWithReplayKey({ text: SHORT_TEXT });
      expect(first.status).toBe(200);
      const original = (await jsonOf(first)) as ReadyBody & { usage: ResponseUsage };
      const sealed = sealedFromFinish();
      expect(JSON.stringify(sealed)).not.toContain("interview");

      alreadyCompleted();
      vi.mocked(findReframeReplay).mockResolvedValueOnce({
        operationId: "00000000-0000-4000-8000-000000000777",
        chargedCredits: original.usage.creditsUsed,
        sealed,
      });
      const callsBefore = vi.mocked(generateJson).mock.calls.length;
      const retry = await postWithReplayKey({ text: SHORT_TEXT });

      expect(retry.status).toBe(200);
      const replayed = (await jsonOf(retry)) as ReadyBody & { usage: ResponseUsage };
      expect(replayed).toEqual(original);
      expect(vi.mocked(generateJson).mock.calls.length).toBe(callsBefore);
      expect(vi.mocked(findReframeReplay).mock.calls[0]?.[0]).toMatchObject({
        clientRequestId: REQUEST_ID,
      });
    });

    it("replays a crisis continue turn with its resource line", async () => {
      stubDecision(continueDecision({ safety: "self_harm", options: [] }));
      const first = await postWithReplayKey({ text: SHORT_TEXT, region: "US" });
      const original = (await jsonOf(first)) as ContinueBody;
      expect(original.crisisResource).toContain("988");

      alreadyCompleted();
      vi.mocked(findReframeReplay).mockResolvedValueOnce({
        operationId: "00000000-0000-4000-8000-000000000777",
        chargedCredits: 0,
        sealed: sealedFromFinish(),
      });
      const retry = await postWithReplayKey({ text: SHORT_TEXT, region: "US" });

      expect(retry.status).toBe(200);
      expect(await jsonOf(retry)).toEqual(original);
    });

    it("keeps the 409 when the replay key does not open the stored body", async () => {
      stubDecision(readyDecision());
      await postWithReplayKey({ text: SHORT_TEXT });
      const sealed = sealedFromFinish();

      alreadyCompleted();
      vi.mocked(findReframeReplay).mockResolvedValueOnce({
        operationId: "00000000-0000-4000-8000-000000000777",
        chargedCredits: 2,
        sealed,
      });
      const retry = await postWithReplayKey(
        { text: SHORT_TEXT },
        Buffer.alloc(32, 9).toString("base64url"),
      );

      expect(retry.status).toBe(409);
      expect(await jsonOf(retry)).toMatchObject({ code: "REQUEST_ALREADY_COMPLETED" });
    });

    it("keeps the 409 when nothing was stored for the request", async () => {
      alreadyCompleted();
      const retry = await postWithReplayKey({ text: SHORT_TEXT });

      expect(retry.status).toBe(409);
      expect(await jsonOf(retry)).toMatchObject({ code: "REQUEST_ALREADY_COMPLETED" });
    });

    it("stores nothing without a well-formed replay key", async () => {
      stubDecision(readyDecision(), readyDecision());
      await post({ text: SHORT_TEXT });
      expect(vi.mocked(finishMeterOperation).mock.calls.at(-1)?.[0].replay).toBeUndefined();

      await postWithReplayKey({ text: SHORT_TEXT }, "too-short");
      expect(vi.mocked(finishMeterOperation).mock.calls.at(-1)?.[0].replay).toBeUndefined();
    });
  });

  it("does not let failed metering cleanup mask the provider error response", async () => {
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.mocked(generateJson).mockRejectedValueOnce(new Error("provider failed"));
    vi.mocked(finishMeterOperation).mockRejectedValueOnce(new Error("cleanup failed"));

    const response = await post({ text: SHORT_TEXT });

    expect(response.status).toBe(500);
    expect(await jsonOf(response)).toMatchObject({ code: "LLM_ERROR" });
    errorLog.mockRestore();
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

  it("rejects a model chosen by the client", async () => {
    const response = await post({ text: LONG_TEXT, model: "gpt-4.1-mini" });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects a styles list: the decision picks the styles", async () => {
    const response = await post({ text: LONG_TEXT, styles: ["stoic"] });

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

  it("repairs an incomplete batch as one whole batch", async () => {
    stubDecision(readyDecision());
    stubStyleBatch(styleBatch({ humorous: undefined }), styleBatch());

    const body = (await jsonOf(await post({ text: LONG_TEXT }))) as ReadyBody;

    expect(generateJson).toHaveBeenCalledTimes(3);
    expect(generateReframe).not.toHaveBeenCalled();
    expect(body.results.map((item) => item.style)).toEqual([...LEGACY_STYLES]);
  });

  it("fails the whole request when the batch repair fails", async () => {
    stubDecision(readyDecision());
    stubStyleBatch(styleBatch({ humorous: undefined }));

    const response = await post({ text: LONG_TEXT });

    expect(response.status).toBe(500);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("LLM_ERROR");
  });
});
