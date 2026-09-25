export const REPORT_REASONS = [
  "spam",
  "harassment",
  "hate",
  "sexual",
  "illegal",
  "personal_data",
  "other",
] as const;

export type ReportReason = (typeof REPORT_REASONS)[number];
