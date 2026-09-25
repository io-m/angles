import { afterEach, describe, expect, it, vi } from "vitest";
import {
  allowedModelsForCredits,
  developmentUsagePeriod,
  paidUsagePeriod,
  requestFingerprint,
  usageWarning,
  utcMonthBoundary,
} from "./meteringPolicy.js";

describe("metering policy", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("gates models by the fixed tariff thresholds", () => {
    expect(allowedModelsForCredits(6)).toEqual([
      "mistral-small-latest",
      "deepseek-flash",
      "gemini-3.8-flash",
    ]);
    expect(allowedModelsForCredits(5)).toEqual([
      "mistral-small-latest",
      "deepseek-flash",
    ]);
    expect(allowedModelsForCredits(2)).toEqual([
      "mistral-small-latest",
      "deepseek-flash",
    ]);
    expect(allowedModelsForCredits(1)).toEqual(["mistral-small-latest"]);
    expect(allowedModelsForCredits(0)).toEqual([]);
    expect(usageWarning(0)).toBe("empty");
    expect(usageWarning(60)).toBe("critical");
    expect(usageWarning(61)).toBe("low");
    expect(usageWarning(120)).toBe("low");
    expect(usageWarning(121)).toBe("normal");
  });

  it("clamps month-end directly from a Jan 31 anchor without drift", () => {
    const anchor = new Date("2024-01-31T18:45:30.123Z");
    expect(utcMonthBoundary(anchor, 1).toISOString()).toBe("2024-02-29T18:45:30.123Z");
    expect(utcMonthBoundary(anchor, 2).toISOString()).toBe("2024-03-31T18:45:30.123Z");
    expect(utcMonthBoundary(anchor, 13).toISOString()).toBe("2025-02-28T18:45:30.123Z");
  });

  it("finds monthly periods for annual coverage and ignores local DST", () => {
    const anchor = new Date("2025-01-31T23:30:00.000Z");
    const february = paidUsagePeriod(anchor, new Date("2025-03-15T12:00:00.000Z"));
    expect(february.startsAt.toISOString()).toBe("2025-02-28T23:30:00.000Z");
    expect(february.endsAt.toISOString()).toBe("2025-03-31T23:30:00.000Z");

    const dev = developmentUsagePeriod(new Date("2026-03-29T01:30:00+01:00"));
    expect(dev.startsAt.toISOString()).toBe("2026-03-01T00:00:00.000Z");
    expect(dev.endsAt.toISOString()).toBe("2026-04-01T00:00:00.000Z");
  });

  it("fingerprints canonical validated requests independently of key order", () => {
    vi.stubEnv("USAGE_ENFORCEMENT", "off");
    expect(
      requestFingerprint({ text: "same", followUps: [{ answer: "a", question: "q" }] }, "deepseek-flash"),
    ).toBe(
      requestFingerprint({ followUps: [{ question: "q", answer: "a" }], text: "same" }, "deepseek-flash"),
    );
    expect(requestFingerprint({ text: "same" }, "deepseek-flash")).not.toBe(
      requestFingerprint({ text: "changed" }, "deepseek-flash"),
    );
  });
});
