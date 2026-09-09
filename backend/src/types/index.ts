export const STYLES = ["stoic", "optimistic", "humorous", "tough_love"] as const;

export type Style = (typeof STYLES)[number];

export type ReframeRequest = {
  text: string;
  styles: Style[];
};

export type ReframeResult = {
  style: Style;
  reframe: string;
};

export type ReframeResponse = {
  results: ReframeResult[];
};

export type ApiErrorBody = {
  error: string;
  code: string;
};

const STYLE_SET: ReadonlySet<string> = new Set(STYLES);

export function isStyle(value: string): value is Style {
  return STYLE_SET.has(value);
}
