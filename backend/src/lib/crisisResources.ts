import { SAFETY_FALLBACK_MESSAGE } from "./prompts.js";

/**
 * Crisis contacts are chosen here, never by the model: a model-written number can be
 * wrong for the country the person is in. `region` is the device's ISO 3166-1 alpha-2
 * region, which is where the person most likely is, not what language they write in.
 */

const EUROPE_112 = [
  "AT", "BE", "BG", "CH", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FR", "GR", "HR",
  "HU", "IS", "IT", "LI", "LT", "LU", "LV", "MT", "NL", "NO", "PL", "PT", "RO", "SE",
  "SI", "SK",
] as const;

const EUROPE_LINE =
  "If you are in danger, call 112 now. It reaches emergency services anywhere in Europe.";

const LINES: Readonly<Record<string, string>> = {
  US: "In the US, call or text 988 any time, or call 911 in an emergency.",
  CA: "In Canada, call or text 988 any time, or call 911 in an emergency.",
  GB: "In the UK, call Samaritans free on 116 123 any time, or 999 in an emergency.",
  IE: "In Ireland, call Samaritans free on 116 123 any time, or 112 in an emergency.",
  AU: "In Australia, call Lifeline on 13 11 14 any time, or 000 in an emergency.",
  NZ: "In New Zealand, call or text 1737 any time, or call 111 in an emergency.",
  ...Object.fromEntries(EUROPE_112.map((code) => [code, EUROPE_LINE])),
};

export const UNKNOWN_REGION_CRISIS_LINE =
  "If you are in danger, call your local emergency number now, or reach out to someone you trust.";

export function crisisResourceLine(region: string | undefined): string {
  return (region && LINES[region.toUpperCase()]) || UNKNOWN_REGION_CRISIS_LINE;
}

/** The prompt forbids numbers, but a model that writes one anyway cannot say for which country. */
export function crisisMessage(modelMessage: string): string {
  return /\d/.test(modelMessage) ? SAFETY_FALLBACK_MESSAGE : modelMessage;
}
