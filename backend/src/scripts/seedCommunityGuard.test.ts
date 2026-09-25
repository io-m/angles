import { describe, expect, it } from "vitest";
import { assertCommunitySeedAllowed } from "./seedCommunityGuard.js";

describe("assertCommunitySeedAllowed", () => {
  it("refuses production with no override escape hatch", () => {
    expect(() =>
      assertCommunitySeedAllowed({
        NODE_ENV: "production",
        ALLOW_PRODUCTION_SEED: "true",
      }),
    ).toThrow("Community seed is disabled in production");
  });

  it("allows local and test environments", () => {
    expect(() =>
      assertCommunitySeedAllowed({ NODE_ENV: "development" }),
    ).not.toThrow();
    expect(() =>
      assertCommunitySeedAllowed({ NODE_ENV: "test" }),
    ).not.toThrow();
  });
});
