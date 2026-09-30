import { describe, expect, it } from "vitest";
import { lintLocal, lintReframe, lintResults } from "./reframeLint.js";

const thought = "I have three reports due tomorrow and my boss keeps adding more.";

describe("lintReframe", () => {
  it("flags a phone number, a long figure, or a statistic the thought did not have", () => {
    for (const reframe of [
      "Call 988 tonight and let someone else carry the reports with you for a while.",
      "Ring 116 123 if the reports start to feel like more than a deadline problem tonight.",
      "Nearly 80% of people who miss a deadline are forgiven by the next week, and so will you be.",
      "By 2027 nobody will remember these reports, including the boss who keeps adding more of them.",
    ]) {
      expect(lintReframe("stoic", reframe, thought), reframe).toContain("digits");
    }
  });

  it("allows short counts and times", () => {
    for (const reframe of [
      "Pick one of the three reports and finish it in the next 24 hours, before anything new lands.",
      "Close the laptop at 6pm, and let tomorrow's version of you walk in rested enough to finish.",
    ]) {
      expect(lintReframe("tough_love", reframe, thought), reframe).not.toContain("digits");
    }
  });

  it("allows numbers the thought already had", () => {
    const withYear = "Since 2019 I have applied to every job and I still have nothing.";
    expect(
      lintReframe("stoic", "Every application since 2019 was a thing you did. The replies were never yours to write.", withYear),
    ).not.toContain("digits");
  });

  it("flags a style's own banned opener but not another style's", () => {
    const listen = "Listen, the reports are not the problem; saying yes to every new one is, so say no once today.";
    expect(lintReframe("tough_love", listen, thought)).toContain("opener");
    expect(lintReframe("stoic", listen, thought)).not.toContain("opener");
  });

  it("flags shared openers, questions, and clichés on any style", () => {
    expect(lintReframe("humorous", "It sounds like the reports have unionised against you and are winning the vote.", thought)).toContain("opener");
    expect(lintReframe("stoic", "What would it look like to finish one report before starting the next one tonight?", thought)).toContain("question");
    expect(lintReframe("optimistic", "This is part of your journey, and every report you finish makes the next one easier.", thought)).toContain("cliche");
  });
});

describe("lintLocal", () => {
  const source = "Imam tri izvještaja do sutra.\nI have three reports due tomorrow.";

  it("flags questions, formatting, and numbers in any language", () => {
    expect(lintLocal("¿Y si el jefe sólo tiene prisa?", source)).toContain("question");
    expect(lintLocal("Nazovi 116 123 večeras i pusti nekoga da ti pomogne.", source)).toContain("digits");
    expect(lintLocal("**Stoički:** izvještaji su samo izvještaji.", source)).toContain("markdown");
  });

  it("passes a clean answer and English-only rules never apply", () => {
    expect(lintLocal("Tri izvještaja su posao za sutra, ne presuda o tebi. Počni s najkraćim.", source)).toEqual([]);
    expect(lintLocal("Look, sutra je novi dan i izvještaji ne idu nikamo.", source)).toEqual([]);
  });
});

describe("lintResults", () => {
  it("marks only the later of two answers that say the same thing", () => {
    const same = "Finish one report tonight and ignore the new requests from your boss until the morning.";
    const issues = lintResults(
      [
        { style: "stoic", reframe: same },
        { style: "tough_love", reframe: `${same} Really.` },
      ],
      thought,
    );
    expect(issues.get("stoic")).not.toContain("overlap");
    expect(issues.get("tough_love")).toContain("overlap");
  });
});
