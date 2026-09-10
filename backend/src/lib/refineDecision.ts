import type { ClarifyResponse, FollowUpAnswer } from "../types/index.js";

export const READY_WORD_THRESHOLD = 24;

export const CLARIFY_BANK: readonly ClarifyResponse[] = [
  {
    kind: "clarify",
    question: "What stings most about this?",
    options: ["The outcome", "How I look to others", "That I can't control it"],
  },
  {
    kind: "clarify",
    question: "What do you want from here?",
    options: ["To feel calmer", "A next step", "To be honest with myself"],
  },
  {
    kind: "clarify",
    question: "Anything the first take would miss?",
    options: ["It's been going on a while", "I already know what I should do", "I'm mostly tired"],
  },
];

export function wordCount(text: string): number {
  return text
    .trim()
    .split(/\s+/)
    .filter((part) => part.length > 0).length;
}

export function shouldReturnReady(text: string, followUps: FollowUpAnswer[]): boolean {
  if (followUps.length >= 3) {
    return true;
  }

  if (followUps.length === 0 && wordCount(text) >= READY_WORD_THRESHOLD) {
    return true;
  }

  return followUps.length >= 1;
}

export function clarifyForFollowUps(followUps: FollowUpAnswer[]): ClarifyResponse {
  const index = Math.min(followUps.length, CLARIFY_BANK.length - 1);
  const entry = CLARIFY_BANK[index];
  if (!entry) {
    return CLARIFY_BANK[0]!;
  }
  return entry;
}

export function composeLlmText(text: string, followUps: FollowUpAnswer[]): string {
  if (followUps.length === 0) {
    return text;
  }

  const extras = followUps
    .map((item) => `Q: ${item.question}\nA: ${item.answer}`)
    .join("\n");
  return `${text}\n\n${extras}`;
}
