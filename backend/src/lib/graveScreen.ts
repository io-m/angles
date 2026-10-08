/**
 * A backstop under the decision call's `solemn` judgment. A thought that names real
 * harm to people is never answered with a joke or a push, even when the model said
 * it could be. Not a crisis screen: a hit still cooks, only the voices change.
 *
 * English only. On a ready turn the model's English `thought` is screened too, which
 * covers every other input language. A false positive costs one joke; a miss ships
 * one. Phrases are multi-word wherever a single word has an everyday idiom ("I bombed
 * my interview", "this meeting is torture", "price war", "it hit me"). Never log what
 * matched.
 */

import { normalizeForScreen } from "./safetyScreen.js";

const KIN =
  "(?:mum|mom|mother|mama|dad|father|papa|wife|husband|partner|son|daughter|child|kid|baby|brother|sister|" +
  "friend|best friend|grandma|grandmother|granny|grandpa|grandfather|aunt|uncle|cousin|niece|nephew|" +
  "girlfriend|boyfriend|fiance|fiancee|colleague|coworker|neighbour|neighbor|dog|cat|pet)";
const PEOPLE =
  "(?:civilians?|children|kids|babies|people|families|innocents|innocent people|refugees|villagers|women|" +
  "prisoners|hostages|students|patients)";
/** Optional auxiliaries: "civilians killed", "civilians are being killed", "kids keep dying". */
const AUX = "(?:(?:is|was|were|are|has been|have been|had been|keep|keeps) )?(?:being |getting |got )?";
const HARMED =
  "(?:killed|bombed|shelled|massacred|slaughtered|murdered|executed|starved|starving|tortured|raped|kidnapped|dying|dead)" +
  "(?! (?:it|to|tired|laughing|inside|of embarrassment))";
const ABUSER =
  "(?:husband|wife|partner|boyfriend|girlfriend|ex|dad|father|stepdad|stepfather|mum|mom|mother|stepmum|stepmom|parents?|brother|sister|uncle)";

const GRAVE_PHRASES: readonly string[] = [
  // Death and loss
  `${KIN} (?:just )?(?:died|passed|passed away|passed on|is dead|was killed|got killed|killed himself|killed herself|took (?:his|her) (?:own )?life)`,
  "passed away",
  "funerals?",
  "death of (?:my|our|his|her|their)",
  `lost (?:my|our) ${KIN}`,
  "(?:put|putting) (?:our|my|the) (?:dog|cat|pet) down",
  "had to put (?:him|her) down",
  "miscarri(?:age|ages|ed)",
  "stillb(?:irth|orn)",
  "lost (?:the|our|my) (?:baby|pregnancy)",
  "suicide",
  // Serious illness
  "cancer",
  "tumou?rs?",
  "chemo(?:therapy)?",
  "leuka?emia",
  "lymphoma",
  "metasta\\p{L}*",
  "terminal(?:ly)? (?:ill|illness|diagnosis|cancer|condition|stage)",
  "stage (?:3|4|iii|iv|three|four) (?:cancer|disease|tumou?r)",
  "(?:weeks|months|days) to live",
  "life threatening",
  "(?:seriously|critically|gravely) ill",
  "intensive care",
  "icu",
  "life support",
  "hospice",
  "palliative",
  "dementia",
  "alzheimer\\p{L}*",
  "parkinson\\p{L}*",
  "motor neuron(?:e)? disease",
  `${KIN} ${AUX}dying(?! (?:to|of laughing|laughing|inside))`,
  `${KIN} (?:had|has) (?:a )?(?:stroke|heart attack|seizure)`,
  // Sexual violence and abuse
  "rape(?:d|s)?",
  "raping",
  "sexual(?:ly)? (?:assault(?:ed)?|abuse(?:d)?|violence)",
  "molest(?:ed|ation|ing|er)?",
  "incest",
  "grooming (?:me|her|him|children|kids|a child|minors)",
  "child abuse",
  "domestic (?:violence|abuse)",
  `${ABUSER} (?:hits|hit|beats|beat|chokes|choked|slaps|slapped|kicks|kicked|strangled|abuses|abused) (?:me|us|my|her|him|them)(?! (?:at|to|in) )`,
  "abused (?:me|us|her|him|them|my)",
  "abusive (?:relationship|husband|wife|partner|father|mother|dad|mum|mom|parent|parents|boyfriend|girlfriend|home|ex)",
  // A child hurt
  `(?:my|our|a|the) (?:son|daughter|baby|child|kid|toddler|newborn) (?:is|was|got|has been|is being|was being) (?:hurt|injured|hospitali[sz]ed|in hospital|in the hospital|abused|missing)`,
  `(?:children|kids|a child|a baby|babies) ${AUX}(?:hurt|injured|abused|killed|dying|starving)(?! (?:to|it|laughing))`,
  // War, atrocity, terror
  `${PEOPLE} ${AUX}${HARMED}`,
  `(?:killing|bombing|shelling|massacre|slaughter|murder|starvation|torture|execution)s? (?:of )?${PEOPLE}`,
  "civilian (?:deaths|casualties|targets|areas|homes)",
  "bomb(?:s|ing|ings|ed)? (?:on |of )?(?:the )?(?:civilians|hospitals?|schools?|homes|houses|apartments?|cities|city|towns?|villages?|kids|children|people|families|shelters?)",
  "air ?strikes?",
  "air raids?",
  "missile (?:strikes?|attacks?)",
  "drone (?:strikes?|attacks?)",
  "shelling",
  "carpet bomb\\p{L}*",
  "war crimes?",
  "genocid\\p{L}*",
  "ethnic cleansing",
  "crimes against humanity",
  "holocaust",
  "concentration camps?",
  "death camps?",
  "pogroms?",
  "massacre of",
  "terror(?:ist)? attacks?",
  "terrorism",
  "suicide bomb\\p{L}*",
  "(?:school|mass) shootings?",
  "hostages",
  "taken hostage",
  "(?:invasion|occupation|siege|bombardment) of",
  "(?:the )?war in (?:ukraine|gaza|israel|palestine|sudan|syria|yemen|lebanon|iraq|afghanistan|congo|ethiopia|tigray|myanmar|the middle east)",
  "(?:russia|russian|russians|israeli|israel|hamas|military|army|soldiers?|troops|regime) (?:bomb|bombs|bombed|bombing|shell|shells|shelled|shelling|kill|kills|killed|killing|attack|attacks|attacked|attacking|invaded|invading|invasion)",
  "refugees?",
  "displaced (?:people|families|children|persons)",
  // Torture, slavery, trafficking, persecution
  "tortur(?:ed|ing)",
  "torture of",
  "slavery",
  "enslav\\p{L}*",
  "(?:human|sex|child) trafficking",
  "trafficked",
  "persecut\\p{L}*",
  "famine",
  "starving (?:people|children|kids|families|babies)",
  // Self-hatred
  // "I hate myself for wasting the weekend" is regret about one act, not self-hatred.
  "i (?:hate|loathe|despise) (?:myself|who i am)(?! for)",
  "i'?m (?:so )?(?:worthless|disgusting|a waste of space)",
  "i am (?:so )?(?:worthless|disgusting|a waste of space)",
];

const SCREEN = new RegExp(
  `(?<![\\p{L}\\p{N}])(?:${GRAVE_PHRASES.join("|")})(?![\\p{L}\\p{N}])`,
  "u",
);

/** True when any of these texts name real harm to people, so no joke or push is written. */
export function screensAsGrave(texts: readonly (string | undefined)[]): boolean {
  return texts.some((text) => text !== undefined && SCREEN.test(normalizeForScreen(text)));
}
