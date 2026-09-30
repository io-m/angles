/**
 * Deterministic checks on written reframes. The cook rewrites a style that fails
 * one; the offline eval counts them. Pure: no text leaves this module.
 */

import type { Style } from "../types/index.js";
import {
  REFRAME_MAX_CHARS,
  REFRAME_MIN_WORDS,
  SHARED_BANNED_OPENERS,
  STYLE_VOICES,
} from "./prompts.js";

export const LINT_ISSUES = [
  "too_short",
  "too_long",
  "question",
  "digits",
  "markdown",
  "cliche",
  "opener",
  "overlap",
] as const;

export type LintIssue = (typeof LINT_ISSUES)[number];

/** Therapy-speak and greeting-card lines. Lowercase, matched as substrings. */
const CLICHES = [
  "it's okay to feel",
  "it is okay to feel",
  "it's ok to feel",
  "you are enough",
  "you're enough",
  "hold space",
  "your truth",
  "journey",
  "everything happens for a reason",
  "happens for a reason",
  "silver lining",
  "be kind to yourself",
  "be gentle with yourself",
  "self-care",
  "you've got this",
  "you got this",
  "at the end of the day",
  "it's not the end of the world",
  "your feelings are valid",
  "feelings are valid",
  "give yourself grace",
  "one day at a time",
  "this too shall pass",
];

const STOPWORDS = new Set(
  (
    "a an and are as at be been but by can do does for from had has have he her his how i if in into is it its " +
    "just me my not now of on or our she so than that the their them then there they this to too up us was " +
    "we were what when which who will with you your yours yourself it's you're that's don't can't isn't"
  ).split(" "),
);

/** Pairwise content-word overlap above this reads as the same angle twice. */
export const OVERLAP_LIMIT = 0.35;

export function contentWords(text: string): Set<string> {
  const words = text
    .toLowerCase()
    .replace(/[’]/g, "'")
    .split(/[^a-z0-9']+/)
    .filter((word) => word.length > 2 && !STOPWORDS.has(word));
  return new Set(words);
}

/** Jaccard overlap of content words, 0–1. */
export function overlap(left: string, right: string): number {
  const a = contentWords(left);
  const b = contentWords(right);
  if (a.size === 0 || b.size === 0) {
    return 0;
  }
  let shared = 0;
  for (const word of a) {
    if (b.has(word)) {
      shared += 1;
    }
  }
  return shared / (a.size + b.size - shared);
}

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter((part) => part.length > 0).length;
}

function normalized(text: string): string {
  return text.trim().toLowerCase().replace(/[’]/g, "'").replace(/^["“'\s]+/, "");
}

/** Three or more digits, however separated: a phone number, a hotline, a year, a big figure. */
const LONG_DIGIT_RUN = /\d(?:[\s().+-]*\d){2,}/g;
const PERCENTAGE = /\d+(?:[.,]\d+)?\s*(?:%|percent\b)/i;

/**
 * A phone number, hotline, or invented statistic the thought did not contain. Short
 * counts like "24 hours" or "6pm" are ordinary copy.
 */
function hasForeignDigits(reframe: string, thought: string): boolean {
  const runs = reframe.match(LONG_DIGIT_RUN) ?? [];
  if (runs.some((run) => !thought.includes(run.replace(/\s+/g, " ").trim()))) {
    return true;
  }
  return PERCENTAGE.test(reframe) && !PERCENTAGE.test(thought);
}

export function lintReframe(style: Style, reframe: string, thought: string): LintIssue[] {
  const issues: LintIssue[] = [];
  const text = reframe.trim();
  const lower = normalized(text);
  if (wordCount(text) < REFRAME_MIN_WORDS) {
    issues.push("too_short");
  }
  if (text.length > REFRAME_MAX_CHARS) {
    issues.push("too_long");
  }
  if (text.includes("?")) {
    issues.push("question");
  }
  if (hasForeignDigits(text, thought)) {
    issues.push("digits");
  }
  if (/[*_#`]|^\s*[-•]\s|^\s*(stoic|optimistic|humorous|tough love|tough_love)\s*:/im.test(text)) {
    issues.push("markdown");
  }
  if (CLICHES.some((phrase) => lower.includes(phrase))) {
    issues.push("cliche");
  }
  if (
    [...SHARED_BANNED_OPENERS, ...STYLE_VOICES[style].bannedOpeners].some((opener) =>
      lower.startsWith(opener),
    )
  ) {
    issues.push("opener");
  }
  return issues;
}

/**
 * The checks that hold in any language, for the answer in theirs. `source` is every
 * version of the thought, so a number they wrote themselves is not foreign.
 */
export function lintLocal(reframe: string, source: string): LintIssue[] {
  const issues: LintIssue[] = [];
  const text = reframe.trim();
  if (/[?¿？]/.test(text)) {
    issues.push("question");
  }
  if (hasForeignDigits(text, source)) {
    issues.push("digits");
  }
  if (/[*_#`]|^\s*[-•]\s/m.test(text)) {
    issues.push("markdown");
  }
  return issues;
}

/**
 * Every result's own issues, plus `overlap` on the later of any two styles that say
 * the same thing. The earlier one keeps its text, so a rewrite touches one side only.
 */
export function lintResults(
  results: readonly { style: Style; reframe: string }[],
  thought: string,
): Map<Style, LintIssue[]> {
  const issues = new Map<Style, LintIssue[]>();
  for (const result of results) {
    issues.set(result.style, lintReframe(result.style, result.reframe, thought));
  }
  for (let later = 1; later < results.length; later += 1) {
    const current = results[later];
    if (!current) {
      continue;
    }
    for (let earlier = 0; earlier < later; earlier += 1) {
      const previous = results[earlier];
      if (previous && overlap(previous.reframe, current.reframe) > OVERLAP_LIMIT) {
        issues.get(current.style)?.push("overlap");
        break;
      }
    }
  }
  return issues;
}
