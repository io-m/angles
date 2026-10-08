import { Hono } from "hono";
import { describe, expect, it } from "vitest";
import { STYLES } from "../types/index.js";
import {
  LEGACY_STYLES,
  STYLE_SET_2,
  STYLE_SET_HEADER,
  stylesForRequest,
  styleSetMiddleware,
} from "./styleSet.js";

async function stylesSeenBy(headers: Record<string, string>): Promise<readonly string[]> {
  const app = new Hono();
  app.use("*", styleSetMiddleware);
  app.get("/", (c) => c.json(stylesForRequest()));
  const response = await app.request("/", { headers });
  return (await response.json()) as string[];
}

describe("style sets", () => {
  it("header 2 is exactly the six styles that shipped with it", () => {
    expect([...STYLE_SET_2]).toEqual([
      "stoic",
      "optimistic",
      "humorous",
      "tough_love",
      "tender",
      "values",
    ]);
  });

  // An installed build fails a whole cook on a style it does not know. When STYLES grows,
  // this fails until the new style gets its own header value instead of joining set 2.
  it("STYLES has not outgrown set 2", () => {
    expect([...STYLES]).toEqual([...STYLE_SET_2]);
  });

  it("serves set 2 to header 2, and the original four to everything else", async () => {
    expect(await stylesSeenBy({ [STYLE_SET_HEADER]: "2" })).toEqual([...STYLE_SET_2]);
    expect(await stylesSeenBy({})).toEqual([...LEGACY_STYLES]);
    expect(await stylesSeenBy({ [STYLE_SET_HEADER]: "3" })).toEqual([...LEGACY_STYLES]);
    expect(await stylesSeenBy({ [STYLE_SET_HEADER]: "" })).toEqual([...LEGACY_STYLES]);
  });
});
