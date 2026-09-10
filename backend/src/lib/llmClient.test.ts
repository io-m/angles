import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { generateReframe, LLM_MAX_OUTPUT_TOKENS, LlmError } from "./llmClient.js";

const INPUT = {
  text: "I bombed my job interview today and cannot stop replaying every pause.",
  systemPrompt: "You reframe a negative thought in a Stoic tone.",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function lastRequest(fetchMock: ReturnType<typeof vi.fn>): {
  url: string;
  init: RequestInit;
  body: Record<string, unknown>;
} {
  const call = fetchMock.mock.calls[0];
  if (!call) {
    throw new Error("fetch was not called");
  }

  const url = String(call[0]);
  const init = (call[1] ?? {}) as RequestInit;
  const body = JSON.parse(String(init.body)) as Record<string, unknown>;
  return { url, init, body };
}

describe("generateReframe", () => {
  beforeEach(() => {
    vi.stubEnv("LLM_MODEL", "mistral-small-latest");
    vi.stubEnv("MISTRAL_API_KEY", "mistral-test");
    vi.stubEnv("GEMINI_API_KEY", "gemini-test");
    vi.stubEnv("DEEPSEEK_API_KEY", "deepseek-test");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it("calls Mistral with reasoning off", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: "  A stoic take.  " } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).resolves.toBe("A stoic take.");

    const { url, init, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.mistral.ai/v1/chat/completions");
    expect(init.headers).toMatchObject({
      Authorization: "Bearer mistral-test",
    });
    expect(body.model).toBe("mistral-small-latest");
    expect(body.reasoning_effort).toBe("none");
    expect(body.max_tokens).toBe(LLM_MAX_OUTPUT_TOKENS);
    expect(body.messages).toEqual([
      { role: "system", content: INPUT.systemPrompt },
      { role: "user", content: INPUT.text },
    ]);
  });

  it("uses a requested model instead of LLM_MODEL", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          {
            content: {
              parts: [{ text: "Meet the moment you still control." }],
            },
          },
        ],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      generateReframe({ ...INPUT, model: "gemini-3.8-flash" }),
    ).resolves.toBe("Meet the moment you still control.");

    const { url } = lastRequest(fetchMock);
    expect(url).toBe(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent",
    );
  });

  it("calls Gemini with thinking low and skips thought parts", async () => {
    vi.stubEnv("LLM_MODEL", "gemini-3.8-flash");
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        candidates: [
          {
            content: {
              parts: [
                { thought: true, text: "planning" },
                { text: "Meet the moment you still control." },
              ],
            },
          },
        ],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).resolves.toBe("Meet the moment you still control.");

    const { url, init, body } = lastRequest(fetchMock);
    expect(url).toBe(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent",
    );
    expect(init.headers).toMatchObject({
      "x-goog-api-key": "gemini-test",
    });
    expect(body.temperature).toBeUndefined();
    const generationConfig = body.generationConfig as {
      thinkingConfig: { thinkingLevel: string };
      maxOutputTokens: number;
    };
    expect(generationConfig.thinkingConfig.thinkingLevel).toBe("low");
    expect(generationConfig.maxOutputTokens).toBe(LLM_MAX_OUTPUT_TOKENS);
  });

  it("calls DeepSeek Flash with thinking disabled", async () => {
    vi.stubEnv("LLM_MODEL", "deepseek-flash");
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: [{ type: "text", text: "Keep moving." }] } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).resolves.toBe("Keep moving.");

    const { url, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(body.model).toBe("deepseek-flash");
    expect(body.thinking).toEqual({ type: "disabled" });
  });

  it("calls DeepSeek Pro on the same endpoint", async () => {
    vi.stubEnv("LLM_MODEL", "deepseek-v4-pro");
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: "Own the next step." } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).resolves.toBe("Own the next step.");

    const { url, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(body.model).toBe("deepseek-v4-pro");
  });

  it("rejects an unknown model without calling fetch", async () => {
    vi.stubEnv("LLM_MODEL", "muse-spark-1.3");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).rejects.toBeInstanceOf(LlmError);
    await expect(generateReframe(INPUT)).rejects.toThrow("Unknown LLM_MODEL");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a missing provider key", async () => {
    vi.stubEnv("MISTRAL_API_KEY", "");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe(INPUT)).rejects.toThrow("MISTRAL_API_KEY is not set");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects empty text", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ text: "   ", systemPrompt: INPUT.systemPrompt })).rejects.toThrow(
      "Cannot reframe empty text",
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects an empty model reply", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => jsonResponse({ choices: [{ message: { content: "  " } }] })),
    );

    await expect(generateReframe(INPUT)).rejects.toThrow("LLM returned an empty reframe");
  });

  it("maps HTTP failures without including the user text", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => jsonResponse({ error: INPUT.text }, 500)));

    await expect(generateReframe(INPUT)).rejects.toThrow("LLM HTTP 500");
    await expect(generateReframe(INPUT)).rejects.toThrow(
      expect.not.stringContaining("bombed my job interview"),
    );
  });
});
