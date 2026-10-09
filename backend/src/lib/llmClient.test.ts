import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { generateJson, generateReframe, LLM_MAX_OUTPUT_TOKENS, LlmError, MIN_LLM_CALL_MS, modelsForStep, resetMissingUsageCircuitForTests, STEP_DEFAULT_MODELS, timeoutMsUntil } from "./llmClient.js";

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
    vi.stubEnv("OPENAI_API_KEY", "openai-test");
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
        choices: [{ message: { content: "Meet the moment you still control." } }],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      generateReframe({ ...INPUT, model: "gpt-4.1-mini" }),
    ).resolves.toBe("Meet the moment you still control.");

    const { url, init, body } = lastRequest(fetchMock);
    expect(url).toBe("https://api.openai.com/v1/chat/completions");
    expect(init.headers).toMatchObject({
      Authorization: "Bearer openai-test",
    });
    expect(body.model).toBe("gpt-4.1-mini");
    expect(body.reasoning_effort).toBeUndefined();
    expect(body.thinking).toBeUndefined();
    expect(body.temperature).toBeUndefined();
  });

  it("sends a requested temperature to both providers", async () => {
    const fetchMock = vi.fn(async (_url: string, _init?: RequestInit) =>
      jsonResponse({ choices: [{ message: { content: "Hold steady." } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await generateReframe({ ...INPUT, temperature: 0.8 });
    await generateReframe({ ...INPUT, temperature: 0.8, model: "gpt-4.1-mini" });

    const mistralBody = JSON.parse(String((fetchMock.mock.calls[0]?.[1] as RequestInit).body)) as {
      temperature?: number;
    };
    const openAIBody = JSON.parse(String((fetchMock.mock.calls[1]?.[1] as RequestInit).body)) as {
      temperature?: number;
    };
    expect(mistralBody.temperature).toBe(0.8);
    expect(openAIBody.temperature).toBe(0.8);
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
      generateReframe({ ...INPUT, fallbackModel: "gpt-4.1-mini", onAnsweredBy: answeredBy, usageSink }),
    ).resolves.toBe("Take the next step.");

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1]?.[0])).toBe("https://api.openai.com/v1/chat/completions");
    expect(answeredBy).toHaveBeenCalledWith("gpt-4.1-mini");
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({ requestedModel: "mistral-small-latest", status: "failed" }),
    );
    expect(usageSink).toHaveBeenCalledWith(
      expect.objectContaining({ requestedModel: "gpt-4.1-mini", status: "succeeded" }),
    );
  });

  it("falls back once when the provider rejects the key or the request", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) =>
      String(url).includes("mistral")
        ? jsonResponse({ error: "unauthorized" }, 401)
        : jsonResponse({ choices: [{ message: { content: "Take the next step." } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, fallbackModel: "gpt-4.1-mini" })).resolves.toBe(
      "Take the next step.",
    );
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1]?.[0])).toBe("https://api.openai.com/v1/chat/completions");
  });

  it("tries the fallback once and stops when that call fails too", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const fetchMock = vi.fn(async () => jsonResponse({ error: "bad request" }, 400));
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, fallbackModel: "gpt-4.1-mini" })).rejects.toThrow(
      "LLM HTTP 400",
    );
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("does not start a call once the cook deadline is gone", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      generateReframe({ ...INPUT, deadlineAt: Date.now() + MIN_LLM_CALL_MS - 1 }),
    ).rejects.toThrow("Cook deadline exceeded");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects a missing provider key", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ ...INPUT, model: "gpt-4.1-mini" })).rejects.toThrow(
      "OPENAI_API_KEY is not set",
    );
    expect(fetchMock).not.toHaveBeenCalled();

    vi.stubEnv("OPENAI_API_KEY", "openai-test");
    vi.stubEnv("MISTRAL_API_KEY", "");
    fetchMock.mockImplementation(async () =>
      jsonResponse({ choices: [{ message: { content: "Take the next step." } }] }),
    );
    await expect(generateReframe({ ...INPUT, fallbackModel: "gpt-4.1-mini" })).resolves.toBe(
      "Take the next step.",
    );
    expect(String(fetchMock.mock.calls[0]?.[0])).toBe("https://api.openai.com/v1/chat/completions");
  });

  it("rejects empty text", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    await expect(generateReframe({ text: "   ", systemPrompt: INPUT.systemPrompt })).rejects.toThrow(
      "Cannot reframe empty text",
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("falls back once when the provider returns an empty reply", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const fetchMock = vi.fn(async (url: string, _init?: RequestInit) =>
      String(url).includes("mistral")
        ? jsonResponse({ choices: [{ message: { content: "  " } }] })
        : jsonResponse({ choices: [{ message: { content: "Take the next step." } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(
      generateReframe({ ...INPUT, fallbackModel: "gpt-4.1-mini" }),
    ).resolves.toBe("Take the next step.");
    expect(fetchMock).toHaveBeenCalledTimes(2);
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
        companyCostNanoUsd: 10_800n,
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
  it("uses Mistral with one OpenAI fallback for every step", () => {
    for (const name of ["decision", "writer", "moderation"] as const) {
      expect(modelsForStep(name, {})).toEqual({
        primary: "mistral-small-latest",
        fallback: "gpt-4.1-mini",
      });
      expect(STEP_DEFAULT_MODELS[name]).toBe("mistral-small-latest");
    }
  });

  it("reads a step override, a fallback override, and none", () => {
    expect(
      modelsForStep("writer", {
        LLM_WRITER_MODEL: "gpt-4.1-mini",
        LLM_WRITER_FALLBACK_MODEL: "mistral-small-latest",
      }),
    ).toEqual({ primary: "gpt-4.1-mini", fallback: "mistral-small-latest" });
    expect(modelsForStep("decision", { LLM_DECISION_FALLBACK_MODEL: "none" })).toEqual({
      primary: STEP_DEFAULT_MODELS.decision,
    });
  });

  it.each(["deepseek-flash", "deepseek-v4-pro", "gemini-3.8-flash"])(
    "rejects removed model id %s",
    (model) => {
      expect(() => modelsForStep("writer", { LLM_WRITER_MODEL: model })).toThrow(LlmError);
      expect(() => modelsForStep("writer", { LLM_WRITER_MODEL: model })).toThrow(
        "Unknown LLM_WRITER_MODEL",
      );
    },
  );
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
    vi.stubEnv("OPENAI_API_KEY", "openai-test");
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

  it("enforces the same strict schema on Mistral and OpenAI", async () => {
    const fetchMock = vi.fn(async (_url: string, _init?: RequestInit) =>
      jsonResponse({ choices: [{ message: { content: '{"stoic":"x"}' } }] }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const jsonSchema = { name: "reframes", schema: { type: "object", properties: { stoic: { type: "string" } } } };

    await generateJson({ text: "x", systemPrompt: "y", jsonSchema });
    await generateJson({ text: "x", systemPrompt: "y", jsonSchema, model: "gpt-4.1-mini" });

    const bodies = fetchMock.mock.calls.map(
      (call) => JSON.parse(String((call[1] as RequestInit).body)) as Record<string, unknown>,
    );
    expect(bodies[0]?.response_format).toEqual({
      type: "json_schema",
      json_schema: { name: "reframes", schema: jsonSchema.schema, strict: true },
    });
    expect(bodies[1]?.response_format).toEqual({
      type: "json_schema",
      json_schema: { name: "reframes", schema: jsonSchema.schema, strict: true },
    });
  });
});
