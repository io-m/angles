import { describe, expect, it } from "vitest";
import { app } from "./app.js";
import { CLARIFY_BANK } from "./lib/refineDecision.js";
import { SYSTEM_PROMPTS } from "./lib/prompts.js";
import { STYLES } from "./types/index.js";

const SHORT_TEXT = "I bombed my job interview today.";
const LONG_TEXT =
  "I keep replaying the interview in my head and I cannot stop thinking that every pause and every shaky answer proved I was never going to get that job anyway.";

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
  it("asks a clarifying question for a short statement", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: SHORT_TEXT }),
    });

    expect(response.status).toBe(200);
    await expect(jsonOf(response)).resolves.toEqual(CLARIFY_BANK[0]);
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
    const reframes = body.results.map((item) => item.reframe);
    expect(new Set(reframes).size).toBe(4);
    expect(reframes.every((item) => item.startsWith("[mock "))).toBe(true);
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
