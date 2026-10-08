import { describe, expect, it } from "vitest";
import { screensAsGrave } from "./graveScreen.js";

describe("screensAsGrave", () => {
  it.each([
    "I am deeply concerned about Russian bombing of civilians in Ukraine",
    "I can't stop seeing the footage of children being killed in Gaza",
    "Civilians are being bombed every night and I feel useless",
    "The airstrikes on hospitals keep me awake",
    "Your brain set the soundtrack: heavy drums and a chorus of air raid sirens",
    "Reading about the genocide makes me sick",
    "I keep reading about war crimes and ethnic cleansing",
    "A terrorist attack in my city killed people I knew",
    "There was a school shooting near us today",
    "My sister was just diagnosed with stage 4 cancer",
    "My dad has a tumour and starts chemo next week",
    "Mum is in intensive care and the doctors say it's life threatening",
    "My grandmother is dying and I can't fly home",
    "my mum died last week and the house is so quiet",
    "We had to put our dog down this morning, he was 14",
    "I had a miscarriage last month and I keep thinking it was my fault",
    "My best friend passed away in March",
    "A friend told me she was sexually assaulted at a party",
    "I was raped two years ago and it still follows me",
    "My husband hits me when he drinks",
    "My son was hurt at school today and nobody called me",
    "People are starving in Sudan and nobody talks about it",
    "Refugees are drowning at sea and I can't look away",
    "They were tortured in prison for years",
    "Human trafficking is happening in my own town",
    "My people were persecuted for generations",
    "i hate myself",
    "I'm worthless and everyone knows it",
  ])("flags %s", (text) => {
    expect(screensAsGrave([text])).toBe(true);
  });

  it.each([
    "I totally bombed my job interview today",
    "That presentation bombed so hard",
    "You killed it at the talk yesterday",
    "I'm dying of embarrassment after that meeting",
    "My phone died right before the call",
    "There's a price war at work and my targets are impossible",
    "The reviews were a massacre and I want to hide",
    "This meeting is torture",
    "I'm a slave to my inbox",
    "This deadline is killing me, three reports due tomorrow",
    "I'm starving and the canteen is closed",
    "It suddenly hit me that I forgot her birthday",
    "My brother beat me at chess again",
    "My dog is well groomed but I'm a mess",
    "People are dying to see the new show and I didn't get tickets",
    "My boss is going to kill me",
    "My best friend drove two hours to surprise me on my birthday",
    "I procrastinated all weekend and now I hate myself for wasting it",
    "Nobody replied to my message in the group chat for hours",
  ])("leaves %s alone", (text) => {
    expect(screensAsGrave([text])).toBe(false);
  });

  it("ignores missing texts", () => {
    expect(screensAsGrave([undefined, "a normal day"])).toBe(false);
  });
});
