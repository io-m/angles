export const STYLES = ["stoic", "optimistic", "humorous", "tough_love"] as const;

export type Style = (typeof STYLES)[number];

export type FollowUpAnswer = {
  question: string;
  answer: string;
};

export type ReframeRequest = {
  text: string;
  followUps?: FollowUpAnswer[];
  styles?: Style[];
  model?: string;
};

export type ReframeResult = {
  style: Style;
  reframe: string;
};

export type ClarifyResponse = {
  kind: "clarify";
  question: string;
  options: string[];
};

export type ReadyResponse = {
  kind: "ready";
  results: ReframeResult[];
};

export type ReframeResponse = ClarifyResponse | ReadyResponse;

export type ApiErrorBody = {
  error: string;
  code: string;
};

const STYLE_SET: ReadonlySet<string> = new Set(STYLES);

export function isStyle(value: string): value is Style {
  return STYLE_SET.has(value);
}
