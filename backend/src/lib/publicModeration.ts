import { z } from "zod";
import {
  beginStandaloneProviderCall,
  recordStandaloneLlmUsage,
} from "../db/metering.js";
import { getOwnerUserId } from "./authStub.js";
import { generateJson } from "./llmClient.js";
import type { LlmUsageEvent } from "./llmUsage.js";
import { isUsageEnforcementRequired } from "./meteringPolicy.js";

const PUBLIC_CONTENT_VIOLATIONS = [
  "hate",
  "harassment_or_threats",
  "sexual",
  "illegal",
  "personal_data",
  "spam",
] as const;

const moderationResponseSchema = z
  .object({
    allowed: z.boolean(),
    violations: z.array(z.enum(PUBLIC_CONTENT_VIOLATIONS)),
  })
  .strict()
  .refine((value) => value.allowed === (value.violations.length === 0), {
    message: "allowed must match violations",
  });

const PUBLIC_MODERATION_PROMPT = `You are a strict pre-publication safety classifier.
Review all supplied card text as one public post. Reject content containing any of:
- hate or dehumanization targeting protected classes
- harassment, targeted abuse, or threats
- sexual content
- instructions, solicitation, or promotion of illegal activity
- personal data that could identify or contact a person
- spam, scams, or repetitive promotion

Do not reject merely negative thoughts, profanity, criticism, or ordinary personal distress.
Return JSON only:
{"allowed":true,"violations":[]}
or
{"allowed":false,"violations":["hate"|"harassment_or_threats"|"sexual"|"illegal"|"personal_data"|"spam"]}`;

export class PublicModerationUnavailableError extends Error {
  constructor(options?: { cause?: unknown }) {
    super("Public moderation is unavailable", options);
    this.name = "PublicModerationUnavailableError";
  }
}

export async function moderatePublicCard(input: {
  thought: string;
  reframes: readonly string[];
}): Promise<boolean> {
  const ownerId = getOwnerUserId();
  const usageEvents: LlmUsageEvent[] = [];
  const persistUsageEvents = async (): Promise<void> => {
    while (usageEvents.length > 0) {
      const event = usageEvents.shift();
      if (event) {
        await recordStandaloneLlmUsage({ ownerId, event });
      }
    }
  };
  try {
    const raw = await generateJson({
      systemPrompt: PUBLIC_MODERATION_PROMPT,
      text: JSON.stringify({ thought: input.thought, reframes: input.reframes }),
      maxOutputTokens: 100,
      callKind: "moderation",
      attempt: 1,
      ...(isUsageEnforcementRequired()
        ? {
            beforeProviderCall: () => beginStandaloneProviderCall(ownerId),
          }
        : {}),
      usageSink: (event: LlmUsageEvent) => usageEvents.push(event),
    });
    const allowed = moderationResponseSchema.parse(JSON.parse(raw)).allowed;
    await persistUsageEvents();
    return allowed;
  } catch (error) {
    try {
      await persistUsageEvents();
    } catch (usageError) {
      console.error("public_moderation_usage_record_failed", {
        reason: usageError instanceof Error ? usageError.message : "unknown",
      });
    }
    throw new PublicModerationUnavailableError({ cause: error });
  }
}
