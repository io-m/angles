import { describe, expect, it } from "vitest";
import { app } from "./app.js";
import { SYSTEM_PROMPTS } from "./lib/prompts.js";
import { STYLES } from "./types/index.js";

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
  it("returns a mock reframe for one style", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: "I bombed my job interview today and I feel like a failure.",
        styles: ["stoic"],
      }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as {
      results: { style: string; reframe: string }[];
    };
    expect(body.results).toHaveLength(1);
    expect(body.results[0]?.style).toBe("stoic");
    expect(body.results[0]?.reframe.startsWith("[mock] ")).toBe(true);
  });

  it("calls every requested style in one response", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        text: "My friend cancelled on me again.",
        styles: [...STYLES],
      }),
    });

    expect(response.status).toBe(200);
    const body = (await jsonOf(response)) as {
      results: { style: string; reframe: string }[];
    };
    expect(body.results.map((item) => item.style)).toEqual([...STYLES]);
  });

  it("rejects empty text", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "   ", styles: ["stoic"] }),
    });

    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "text must not be empty",
      code: "VALIDATION_ERROR",
    });
  });

  it("rejects unknown style names", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "I feel stuck.", styles: ["stoic", "zen"] }),
    });

    expect(response.status).toBe(400);
    const body = (await jsonOf(response)) as { code: string };
    expect(body.code).toBe("VALIDATION_ERROR");
  });

  it("rejects duplicate styles", async () => {
    const response = await app.request("/reframe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: "I feel stuck.", styles: ["stoic", "stoic"] }),
    });

    expect(response.status).toBe(400);
    await expect(jsonOf(response)).resolves.toEqual({
      error: "styles must not contain duplicates",
      code: "VALIDATION_ERROR",
    });
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
