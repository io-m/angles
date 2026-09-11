import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  CATEGORIES,
  EMOTIONS,
  STYLES,
  type Category,
  type Emotion,
} from "./types/index.js";
import { DEV_USER_ID } from "./lib/authStub.js";
import {
  REFRAME_MAX_CHARS,
  REFRAME_MAX_WORDS,
  REFRAME_MIN_CHARS,
  REFRAME_MIN_WORDS,
  THOUGHT_MAX_CHARS,
  THOUGHT_MAX_WORDS,
  THOUGHT_MIN_CHARS,
  THOUGHT_MIN_WORDS,
} from "./lib/prompts.js";
import type { CommunityFixture } from "./scripts/communityCopy.js";

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

describe("community fixture", () => {
  const fixture = JSON.parse(
    readFileSync(resolve(process.cwd(), "fixtures/community.json"), "utf8"),
  ) as CommunityFixture;

  it("has enough fake users and posts, never JM", () => {
    expect(fixture.users).toHaveLength(50);
    expect(fixture.posts.length).toBeGreaterThanOrEqual(250);
    expect(fixture.posts.length).toBeLessThanOrEqual(500);
    expect(fixture.users.some((user) => user.id === DEV_USER_ID)).toBe(false);
    expect(fixture.posts.some((post) => post.userId === DEV_USER_ID)).toBe(false);
    expect(new Set(fixture.users.map((user) => user.initials)).size).toBe(50);
    expect(fixture.users.every((user) => user.initials.length === 2 && user.initials !== "JM")).toBe(
      true,
    );
  });

  it("spreads categories and emotions and keeps card-fit copy", () => {
    const categories = new Set(fixture.posts.map((post) => post.category));
    const emotions = new Set(fixture.posts.flatMap((post) => post.emotions));
    expect([...CATEGORIES].every((category) => categories.has(category))).toBe(true);
    expect([...EMOTIONS].every((emotion) => emotions.has(emotion))).toBe(true);

    for (const post of fixture.posts) {
      expect(post.tags.length).toBeGreaterThanOrEqual(3);
      expect(post.tags.length).toBeLessThanOrEqual(8);
      expect(post.emotions.length).toBeGreaterThanOrEqual(1);
      expect(post.emotions.length).toBeLessThanOrEqual(3);
      expect(post.emotions.every((emotion) => (EMOTIONS as readonly Emotion[]).includes(emotion))).toBe(
        true,
      );
      expect((CATEGORIES as readonly Category[]).includes(post.category)).toBe(true);
      expect(wordCount(post.thought)).toBeGreaterThanOrEqual(THOUGHT_MIN_WORDS);
      expect(wordCount(post.thought)).toBeLessThanOrEqual(THOUGHT_MAX_WORDS);
      expect(post.thought.length).toBeGreaterThanOrEqual(THOUGHT_MIN_CHARS);
      expect(post.thought.length).toBeLessThanOrEqual(THOUGHT_MAX_CHARS);
      expect(post.results.map((item) => item.style)).toEqual([...STYLES]);
      const reframes = new Set(post.results.map((item) => item.reframe));
      expect(reframes.size).toBe(4);
      for (const result of post.results) {
        expect(wordCount(result.reframe)).toBeGreaterThanOrEqual(REFRAME_MIN_WORDS);
        expect(wordCount(result.reframe)).toBeLessThanOrEqual(REFRAME_MAX_WORDS);
        expect(result.reframe.length).toBeGreaterThanOrEqual(REFRAME_MIN_CHARS);
        expect(result.reframe.length).toBeLessThanOrEqual(REFRAME_MAX_CHARS);
      }
    }
  });
});
