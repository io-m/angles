/**
 * Isolated LLM call. Swap the body of `generateReframe` when a provider is chosen.
 * The iOS app must never call an LLM provider directly.
 */

export const LLM_TIMEOUT_MS = 15_000;

export type GenerateReframeInput = {
  text: string;
  systemPrompt: string;
};

export class LlmError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "LlmError";
  }
}

export async function generateReframe(
  input: GenerateReframeInput,
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, LLM_TIMEOUT_MS);

  try {
    return await mockGenerateReframe(input, controller.signal);
  } catch (error) {
    if (error instanceof LlmError) {
      throw error;
    }
    if (controller.signal.aborted) {
      throw new LlmError("LLM request timed out", { cause: error });
    }
    throw new LlmError("LLM request failed", { cause: error });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Placeholder until a provider/model is chosen.
 * Reads `LLM_API_KEY` only to prove env wiring; the mock does not call a network API.
 */
async function mockGenerateReframe(
  input: GenerateReframeInput,
  signal: AbortSignal,
): Promise<string> {
  if (signal.aborted) {
    throw new LlmError("LLM request aborted");
  }

  void process.env.LLM_API_KEY;

  const trimmed = input.text.trim();
  if (trimmed.length === 0) {
    throw new LlmError("Cannot reframe empty text");
  }

  const preview = trimmed.length > 80 ? `${trimmed.slice(0, 80)}…` : trimmed;
  const toneMatch = input.systemPrompt.match(/in an? (.+?) tone/i);
  const tone = toneMatch?.[1] ?? "Reframe";
  return `[mock ${tone}] ${preview}`;
}
