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

/** What an operator decided about a report. An unreviewed report has none. */
export const REPORT_RESOLUTIONS = ["kept", "hidden"] as const;

export type ReportResolution = (typeof REPORT_RESOLUTIONS)[number];
