import { beforeEach, describe, expect, it, vi } from "vitest";
import { CLARIFY_BANK } from "./lib/refineDecision.js";
import { SYSTEM_PROMPTS } from "./lib/prompts.js";
import { STYLES } from "./types/index.js";

vi.mock("./lib/llmClient.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/llmClient.js")>();
  return {
    ...actual,
    generateReframe: vi.fn(),
  };
});

const { app } = await import("./app.js");
const { generateReframe } = await import("./lib/llmClient.js");

const SHORT_TEXT = "I bombed my job interview today.";
const LONG_TEXT =
  "I keep replaying the interview in my head and I cannot stop thinking that every pause and every shaky answer proved I was never going to get that job anyway.";

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

describe("SYSTEM_PROMPTS", () => {
  it("defines a prompt for every style", () => {
    for (const style of STYLES) {
      expect(SYSTEM_PROMPTS[style].length).toBeGreaterThan(0);
    }
  });
});

async function jsonOf(response: Response): Promise<unknown> {
  return response.json();
}

describe("GET /health", () => {
  it("returns ok", async () => {
    const response = await app.request("/health");
    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual({ status: "ok" });
  });
});

describe("POST /reframe", () => {
  beforeEach(() => {
    stubReframes();
  });

  it("asks a clarifying question for a short statement", async () => {
    vi.mocked(generateReframe).mockClear();

    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: SHORT_TEXT }),
    });

    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(CLARIFY_BANK[0]);
    expect(generateReframe).not.toHaveBeenCalled();
  });

  it("returns all four styles when the statement is already long enough", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as {
      kind: string;
      results: { style: string; reframe: string }[];
    };
    expect(body.kind).toBe("ready");
    expect(body.results.map((item) => item.style)).toEqual([...STYLES]);
    expect(body.results.map((item) => item.reframe)).toEqual([
      "stoic reframe",
      "optimistic reframe",
      "humorous reframe",
      "tough love reframe",
    ]);
    expect(generateReframe).toHaveBeenCalledTimes(4);
  });

  it("returns only the requested styles", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT, styles: ["humorous"] }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as {
      kind: string;
      results: { style: string; reframe: string }[];
    };
    expect(body).toEqual({
      kind: "ready",
      results: [{ style: "humorous", reframe: "humorous reframe" }],
    });
    expect(generateReframe).toHaveBeenCalledTimes(1);
  });

  it("dedupes requested styles", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT, styles: ["stoic", "stoic"] }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as { results: { style: string }[] };
    expect(body.results).toEqual([{ style: "stoic", reframe: "stoic reframe" }]);
    expect(generateReframe).toHaveBeenCalledTimes(1);
  });

  it("returns ready after one follow-up", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: SHORT_TEXT,
        followUps: [{ question: "What stings most about this?", answer: "The outcome" }],
      }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as { kind: string; results: unknown[] };
    expect(body.kind).toBe("ready");
    expect(body.results).toHaveLength(4);
  });

  it("forces ready after three follow-ups", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: SHORT_TEXT,
        followUps: [
          { question: "What stings most about this?", answer: "The outcome" },
          { question: "What do you want from here?", answer: "A next step" },
          { question: "Anything the first take would miss?", answer: "I'm mostly tired" },
        ],
      }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as { kind: string; results: unknown[] };
    expect(body.kind).toBe("ready");
    expect(body.results).toHaveLength(4);
  });

  it("rejects empty text", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "   " }),
    });

    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "text must not be empty",
      code: "VALIDATION_ERROR",
    });
  });

  it("rejects more than three follow-ups", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: SHORT_TEXT,
        followUps: [
          { question: "One?", answer: "A" },
          { question: "Two?", answer: "B" },
          { question: "Three?", answer: "C" },
          { question: "Four?", answer: "D" },
        ],
      }),
    });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("passes a requested model into generateReframe", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT, model: "gemini-3.8-flash" }),
    });

    expect(response.status).toBe(200);
    expect(generateReframe).toHaveBeenCalledWith(
      expect.objectContaining({ model: "gemini-3.8-flash" }),
    );
  });

  it("omits model on generateReframe when the body has none", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT }),
    });

    expect(response.status).toBe(200);
    const first = vi.mocked(generateReframe).mock.calls[0]?.[0];
    expect(first?.model).toBeUndefined();
  });

  it("rejects an unknown model", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT, model: "nope" }),
    });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects unknown styles", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: LONG_TEXT, styles: ["nope"] }),
    });

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
});
