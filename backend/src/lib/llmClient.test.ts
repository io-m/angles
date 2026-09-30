import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { GEMINI_THINKING_HEADROOM, generateJson, generateReframe, LLM_MAX_OUTPUT_TOKENS, LlmError, MIN_LLM_CALL_MS, modelsForStep, resetMissingUsageCircuitForTests, STEP_DEFAULT_MODELS, timeoutMsUntil } from "./llmClient.js";

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
    resetMissingUsageCircuitForTests();
    vi.stubEnv("MISTRAL_API_KEY", "mistral-test");
    vi.stubEnv("GEMINI_API_KEY", "gemini-test");
    vi.stubEnv("DEEPSEEK_API_KEY", "deepseek-test");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
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

  it("uses the requested model", async () => {
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

    await expect(generateReframe({ ...INPUT, model: "gemini-3.8-flash" })).resolves.toBe(
      "Meet the moment you still control.",
    );

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
      temperature?: number;
    };
    expect(generationConfig.thinkingConfig.thinkingLevel).toBe("low");
    expect(generationConfig.maxOutputTokens).toBe(LLM_MAX_OUTPUT_TOKENS + GEMINI_THINKING_HEADROOM);
    expect(generationConfig.temperature).toBeUndefined();
  });

  it("sends a requested temperature to each provider in its own place", async () => {
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) =>
      String(url).includes("googleapis")
        ? jsonResponse({ candidates: [{ content: { parts: [{ text: "Hold steady." }] } }] })
        : jsonResponse({ choices: [{ message: { content: "Hold steady." } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await generateReframe({ ...INPUT, temperature: 0.8 });
    await generateReframe({ ...INPUT, temperature: 0.8, model: "gemini-3.8-flash" });

    const mistralBody = JSON.parse(String((fetchMock.mock.calls[0]?.[1] as RequestInit).body)) as {
      temperature?: number;
    };
    const geminiBody = JSON.parse(String((fetchMock.mock.calls[1]?.[1] as RequestInit).body)) as {
      generationConfig: { temperature?: number };
    };
    expect(mistralBody.temperature).toBe(0.8);
    expect(geminiBody.generationConfig.temperature).toBe(0.8);
  });

  it("falls back to another model once when the provider fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) =>
      String(url).includes("mistral")
        ? jsonResponse({ error: "overloaded" }, 503)
        : jsonResponse({ choices: [{ message: { content: "Take the next step." } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const answeredBy = vi.fn();
    const usageSink = vi.fn();

    await expect(
      generateReframe({ ...INPUT, fallbackModel: "deepseek-flash", onAnsweredBy: answeredBy, usageSink }),
    ).resolves.toBe("Take the next step.");

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1]?.[0])).toBe("https://api.deepseek.com/chat/completions");
    expect(answeredBy).toHaveBeenCalledWith("deepseek-flash");
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({ requestedModel: "mistral-small-latest", status: "failed" }),
    );
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({ requestedModel: "deepseek-flash", status: "succeeded" }),
    );
  });

  it("does not fall back on a request the provider rejected as malformed", async () => {
    const fetchMock = vi.fn(async () => jsonResponse({ error: "bad request" }, 400));
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, fallbackModel: "deepseek-flash" })).rejects.toThrow(
      "LLM HTTP 400",
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("does not start a call once the cook deadline is gone", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      generateReframe({ ...INPUT, deadlineAt: Date.now() + MIN_LLM_CALL_MS - 1 }),
    ).rejects.toThrow("Cook deadline exceeded");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("calls DeepSeek Flash with thinking disabled", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: [{ type: "text", text: "Keep moving." }] } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, model: "deepseek-flash" })).resolves.toBe("Keep moving.");

    const { url, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(body.model).toBe("deepseek-flash");
    expect(body.thinking).toEqual({ type: "disabled" });
  });

  it("calls DeepSeek Pro on the same endpoint", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: "Own the next step." } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, model: "deepseek-v4-pro" })).resolves.toBe(
      "Own the next step.",
    );

    const { url, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.deepseek.com/chat/completions");
    expect(body.model).toBe("deepseek-v4-pro");
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
    const usageSink = vi.fn();
    const request = generateReframe({ ...INPUT, usageSink });

    await expect(request).rejects.toThrow("LLM HTTP 500");
    await expect(request).rejects.toThrow(
      expect.not.stringContaining("bombed my job interview"),
    );
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({ status: "failed", usageSource: "estimated" }),
    );
  });

  it("emits normalized reported usage and provider metadata", async () => {
    const usageSink = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        jsonResponse({
          id: "req_123",
          model: "mistral-small-2506",
          choices: [{ message: { content: "Take the next controllable step." } }],
          usage: {
            prompt_tokens: 50,
            completion_tokens: 10,
            prompt_tokens_details: { cached_tokens: 20 },
          },
        }),
      ),
    );

    await generateReframe({
      ...INPUT,
      callKind: "reframe",
      attempt: 2,
      usageSink,
    });

    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({
        callKind: "reframe",
        attempt: 2,
        requestedModel: "mistral-small-latest",
        returnedModel: "mistral-small-2506",
        providerRequestId: "req_123",
        promptTokens: 30,
        cachedTokens: 20,
        completionTokens: 10,
        usageSource: "reported",
        companyCostNanoUsd: 13_500n,
      }),
    );
  });

  it("opens the per-model circuit after consecutive missing usage", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        jsonResponse({ choices: [{ message: { content: "Keep going." } }] }),
      ),
    );

    await expect(generateReframe(INPUT)).resolves.toBe("Keep going.");
    await expect(generateReframe(INPUT)).resolves.toBe("Keep going.");
    const usageSink = vi.fn();
    await expect(generateReframe({ ...INPUT, usageSink })).rejects.toThrow(
      "LLM model unavailable",
    );
    expect(usageSink).toHaveBeenCalledOnce();
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({
        status: "succeeded",
        usageSource: "estimated",
        companyCostNanoUsd: expect.any(BigInt),
      }),
    );
  });
});

describe("modelsForStep", () => {
  it("uses the step defaults with a fallback on another provider", () => {
    const decision = modelsForStep("decision", {});
    const writer = modelsForStep("writer", {});
    expect(decision.primary).toBe(STEP_DEFAULT_MODELS.decision);
    expect(writer.primary).toBe(STEP_DEFAULT_MODELS.writer);
    for (const step of [decision, writer]) {
      expect(step.fallback).toBeDefined();
      expect(step.fallback).not.toBe(step.primary);
    }
  });

  it("reads a step override, a fallback override, and none", () => {
    expect(
      modelsForStep("writer", {
        LLM_WRITER_MODEL: "gemini-3.8-flash",
        LLM_WRITER_FALLBACK_MODEL: "deepseek-flash",
      }),
    ).toEqual({ primary: "gemini-3.8-flash", fallback: "deepseek-flash" });
    expect(modelsForStep("decision", { LLM_DECISION_FALLBACK_MODEL: "none" })).toEqual({
      primary: STEP_DEFAULT_MODELS.decision,
    });
  });

  it("rejects an unknown model id", () => {
    expect(() => modelsForStep("writer", { LLM_WRITER_MODEL: "muse-spark-1.3" })).toThrow(
      LlmError,
    );
    expect(() => modelsForStep("writer", { LLM_WRITER_MODEL: "muse-spark-1.3" })).toThrow(
      "Unknown LLM_WRITER_MODEL",
    );
  });
});

describe("timeoutMsUntil", () => {
  it("caps at the per-call timeout", () => {
    expect(timeoutMsUntil(Date.now() + 60_000)).toBe(8_000);
  });

  it("fails when the cook budget is gone", () => {
    expect(() => timeoutMsUntil(Date.now() + MIN_LLM_CALL_MS - 1)).toThrow("Cook deadline exceeded");
  });
});

describe("generateJson", () => {
  beforeEach(() => {
    resetMissingUsageCircuitForTests();
    vi.stubEnv("LLM_MODEL", "mistral-small-latest");
    vi.stubEnv("MISTRAL_API_KEY", "mistral-test");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("sends the caller's max_tokens and plain JSON mode without a schema", async () => {
    const fetchMock = vi.fn(async () =>
      jsonResponse({
        choices: [{ message: { content: '{"stoic":"Keep the next attempt."}' } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await generateJson({
      text: "I bombed my interview.",
      systemPrompt: "Each JSON field is that style only",
      maxOutputTokens: 496,
    });

    const { body } = lastRequest(fetchMock);
    expect(body.max_tokens).toBe(496);
    expect(body.response_format).toEqual({ type: "json_object" });
  });

  it("enforces a schema on Mistral and Gemini, and keeps DeepSeek on JSON mode", async () => {
    vi.stubEnv("GEMINI_API_KEY", "gemini-test");
    vi.stubEnv("DEEPSEEK_API_KEY", "deepseek-test");
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) =>
      String(url).includes("googleapis")
        ? jsonResponse({ candidates: [{ content: { parts: [{ text: '{"stoic":"x"}' }] } }] })
        : jsonResponse({ choices: [{ message: { content: '{"stoic":"x"}' } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const jsonSchema = { name: "reframes", schema: { type: "object", properties: { stoic: { type: "string" } } } };

    await generateJson({ text: "x", systemPrompt: "y", jsonSchema });
    await generateJson({ text: "x", systemPrompt: "y", jsonSchema, model: "gemini-3.8-flash" });
    await generateJson({ text: "x", systemPrompt: "y", jsonSchema, model: "deepseek-flash" });

    const bodies = fetchMock.mock.calls.map(
      (call) => JSON.parse(String((call[1] as RequestInit).body)) as Record<string, unknown>,
    );
    expect(bodies[0]?.response_format).toEqual({
      type: "json_schema",
      json_schema: { name: "reframes", schema: jsonSchema.schema, strict: true },
    });
    expect((bodies[1]?.generationConfig as Record<string, unknown>).responseJsonSchema).toEqual(
      jsonSchema.schema,
    );
    expect(bodies[2]?.response_format).toEqual({ type: "json_object" });
  });
});
