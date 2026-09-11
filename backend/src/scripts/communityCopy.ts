import {
  CATEGORIES,
  EMOTIONS,
  STYLES,
  TIMEFRAMES,
  intensityBand,
  type Category,
  type Emotion,
  type Style,
  type Timeframe,
} from "../types/index.js";
import {
  REFRAME_MAX_CHARS,
  REFRAME_MAX_WORDS,
  REFRAME_MIN_CHARS,
  REFRAME_MIN_WORDS,
  THOUGHT_MAX_CHARS,
  THOUGHT_MAX_WORDS,
  THOUGHT_MIN_CHARS,
  THOUGHT_MIN_WORDS,
} from "../lib/prompts.js";

export type CommunityUser = {
  id: string;
  initials: string;
};

export type CommunityPost = {
  id: string;
  userId: string;
  createdAt: string;
  thought: string;
  thoughtOriginal?: string;
  inputLanguage: string;
  category: Category;
  tags: string[];
  intensity: number;
  intensityBand: ReturnType<typeof intensityBand>;
  timeframe: Timeframe;
  emotions: Emotion[];
  results: { style: Style; reframe: string }[];
  spotlightStyle: Style;
};

export type CommunityFixture = {
  users: CommunityUser[];
  posts: CommunityPost[];
};

export const DEV_USER_ID = "00000000-0000-4000-8000-000000000001";

function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function assertCopy(kind: string, text: string, minWords: number, maxWords: number, minChars: number, maxChars: number): void {
  const words = wordCount(text);
  const chars = text.length;
  if (words < minWords || words > maxWords || chars < minChars || chars > maxChars) {
    throw new Error(`${kind} out of budget (${words}w ${chars}c): ${text}`);
  }
}

function pad(n: number): string {
  return n.toString(16).padStart(12, "0");
}

function userId(n: number): string {
  return `00000000-0000-4000-8100-${pad(n)}`;
}

function postId(n: number): string {
  return `00000000-0000-4000-8200-${pad(n)}`;
}

const INITIALS = [
  "AL", "BR", "CK", "DN", "EV", "FT", "GW", "HX", "IP", "JQ",
  "KA", "LB", "MC", "ND", "OR", "PS", "QT", "RU", "SV", "TW",
  "UM", "VN", "WP", "XQ", "YL", "ZA", "AE", "BO", "CI", "DJ",
  "EK", "FL", "GM", "HN", "IO", "JP", "KQ", "LR", "MS", "NT",
  "OU", "PV", "QW", "RX", "SY", "TZ", "UA", "VB", "WC", "XD",
] as const;

type Scene = { thought: string; core: string; tags: string[] };

const SCENES: Record<Category, Scene[]> = {
  work: [
    { thought: "I keep replaying how I froze when they asked me to walk through my impact.", core: "freezing in that meeting", tags: ["meeting", "impact", "freeze"] },
    { thought: "They presented my deck as theirs, and I sat there smiling like it was fine.", core: "watching them take the deck", tags: ["credit", "deck", "silence"] },
    { thought: "My manager skipped me in the roundtable again and nobody even noticed.", core: "being skipped on purpose", tags: ["manager", "invisible", "roundtable"] },
    { thought: "I keep refreshing the hiring portal like staring will make them kinder.", core: "refreshing the portal", tags: ["job_search", "waiting", "portal"] },
    { thought: "I said yes to another late night and I can feel myself disappearing.", core: "saying yes again", tags: ["overwork", "boundaries", "nights"] },
    { thought: "They hired someone above me and called it a chance for me to learn.", core: "being passed over", tags: ["promotion", "hierarchy", "learn"] },
    { thought: "I sent the recap and now I am hunting for the sentence that ruined me.", core: "hunting the recap", tags: ["email", "rumination", "recap"] },
    { thought: "Everyone else seems fluent in the room and I am translating myself.", core: "translating myself at work", tags: ["imposter", "meetings", "fluency"] },
    { thought: "I asked for feedback and got a smile that felt like a closed door.", core: "feedback that went nowhere", tags: ["feedback", "avoidance", "smile"] },
    { thought: "I keep drafting the slack and deleting it because I sound needy.", core: "deleting the slack", tags: ["slack", "neediness", "draft"] },
    { thought: "The layoff rumor sits in every standup and I laugh like I am fine.", core: "laughing through layoff talk", tags: ["layoff", "standup", "rumor"] },
    { thought: "I finished the project and the praise went to the loudest person.", core: "losing the credit", tags: ["credit", "loud", "project"] },
    { thought: "I am terrified the next review will confirm I was never that good.", core: "dreading the review", tags: ["review", "fear", "competence"] },
    { thought: "They moved the deadline up and I nodded like my weekend was optional.", core: "nodding at the deadline", tags: ["deadline", "weekend", "people_pleasing"] },
    { thought: "I keep checking who got invited to the offsite and I was not there.", core: "missing the offsite list", tags: ["offsite", "exclusion", "invite"] },
    { thought: "I corrected a number and they looked at me like I had made a scene.", core: "being punished for accuracy", tags: ["accuracy", "conflict", "numbers"] },
    { thought: "I am doing three jobs and still apologizing for being behind.", core: "apologizing for three jobs", tags: ["workload", "apology", "behind"] },
    { thought: "The intern asked how I got here and I could not name a real answer.", core: "not knowing how I got here", tags: ["imposter", "intern", "origin"] },
    { thought: "I keep practicing the ask for a raise and then I swallow it.", core: "swallowing the raise ask", tags: ["raise", "money", "avoidance"] },
    { thought: "They called my careful work slow and I believed them by lunch.", core: "believing I am slow", tags: ["pace", "careful", "belief"] },
    { thought: "I left the camera off and now I am sure they think I am checked out.", core: "leaving the camera off", tags: ["camera", "remote", "shame"] },
    { thought: "I keep volunteering for the glue work nobody will remember in June.", core: "doing the forgotten glue", tags: ["glue_work", "invisible", "volunteer"] },
    { thought: "The strategy day felt like a play and I did not get a script.", core: "sitting without a script", tags: ["strategy", "script", "lost"] },
    { thought: "I got the meeting notes wrong and I want to disappear until Friday.", core: "getting the notes wrong", tags: ["notes", "mistake", "hide"] },
    { thought: "They keep saying we are a family while they cut another person loose.", core: "family talk during cuts", tags: ["layoff", "family", "hypocrisy"] },
    { thought: "I am scared my quiet competence reads as having nothing to say.", core: "quiet looking like nothing", tags: ["quiet", "competence", "voice"] },
    { thought: "I stayed late to look loyal and nobody even saw the lights on.", core: "loyalty nobody saw", tags: ["late", "loyalty", "unseen"] },
    { thought: "The client praised someone else for the idea I fought to keep.", core: "losing the idea in the room", tags: ["client", "idea", "credit"] },
    { thought: "I keep rereading the job post like it is already mourning me.", core: "rereading the job post", tags: ["job_post", "insecurity", "replace"] },
    { thought: "I said I was fine in standup and my voice did that thin little lie.", core: "the thin standup lie", tags: ["standup", "fine", "voice"] },
  ],
  money: [
    { thought: "I checked the balance again like the number might have grown kinder.", core: "checking the balance again", tags: ["balance", "checking", "anxiety"] },
    { thought: "Rent is due and I am doing math that never quite becomes a plan.", core: "rent math with no plan", tags: ["rent", "math", "due"] },
    { thought: "I told them dinner was on me and then I felt sick in the bathroom.", core: "paying and panicking", tags: ["dinner", "pride", "panic"] },
    { thought: "The invoice is late and I keep drafting a nudge that sounds desperate.", core: "the desperate invoice nudge", tags: ["invoice", "freelance", "nudge"] },
    { thought: "I bought the cheap version and still felt like I had been reckless.", core: "feeling reckless for cheap", tags: ["spending", "guilt", "cheap"] },
    { thought: "My friends talk trips and I smile while converting everything to rent.", core: "converting trips to rent", tags: ["friends", "trips", "rent"] },
    { thought: "I opened the tax email and my chest did that familiar drop.", core: "the tax email drop", tags: ["tax", "email", "dread"] },
    { thought: "I keep hiding the overdraft like it is a character flaw.", core: "hiding the overdraft", tags: ["overdraft", "shame", "hiding"] },
    { thought: "They asked what I do and I heard myself shrink the number.", core: "shrinking what I earn", tags: ["income", "shrink", "pride"] },
    { thought: "I cannot ask my parents again without feeling twelve years old.", core: "asking parents for money", tags: ["parents", "help", "shame"] },
    { thought: "The subscription pile is a museum of who I thought I would be.", core: "subscriptions as a museum", tags: ["subscriptions", "waste", "identity"] },
    { thought: "I split the bill too carefully and I am sure they noticed.", core: "splitting too carefully", tags: ["bill", "careful", "noticed"] },
    { thought: "I keep delaying the dentist because the quote still lives in my notes.", core: "delaying the dentist quote", tags: ["dentist", "delay", "quote"] },
    { thought: "Payday feels like a truce, not a win, and it is already spoken for.", core: "payday already spoken for", tags: ["payday", "truce", "bills"] },
    { thought: "I saw their kitchen renovation and did the ugly little comparison.", core: "comparing kitchens in my head", tags: ["comparison", "home", "envy"] },
    { thought: "I am scared one surprise bill will undo the last three careful months.", core: "one bill undoing months", tags: ["emergency", "fragile", "bills"] },
    { thought: "I keep the receipt like proof I was allowed to want something.", core: "keeping the receipt as proof", tags: ["receipt", "wanting", "permission"] },
    { thought: "They called it a fun little treat and I heard a future problem.", core: "a treat that sounds like trouble", tags: ["treat", "future", "worry"] },
    { thought: "I undersold the project because I was afraid they would walk.", core: "underselling out of fear", tags: ["rate", "fear", "walk"] },
    { thought: "I am tired of being the friend who suggests the cheaper place.", core: "always picking cheaper", tags: ["friends", "cheaper", "tired"] },
    { thought: "The savings account looks like a joke I am still telling myself.", core: "savings that look like a joke", tags: ["savings", "joke", "self"] },
    { thought: "I said I was busy instead of saying I could not afford it.", core: "busy instead of broke", tags: ["busy", "afford", "lie"] },
    { thought: "I keep calculating how many hours that coffee actually cost me.", core: "costing out the coffee", tags: ["coffee", "hours", "calculate"] },
    { thought: "The landlord raised it and I thanked them like manners could help.", core: "thanking for a raise in rent", tags: ["landlord", "rent", "manners"] },
    { thought: "I opened shopping and closed it four times like that was discipline.", core: "opening shopping as discipline", tags: ["shopping", "discipline", "loop"] },
    { thought: "I am embarrassed my emergency fund is a story, not a number.", core: "emergency fund as a story", tags: ["emergency", "story", "fund"] },
    { thought: "They offered to cover me and I wanted to disappear into the floor.", core: "being covered in public", tags: ["cover", "pride", "public"] },
    { thought: "I keep waiting for money to feel like safety and it never stays.", core: "money that never feels safe", tags: ["safety", "never", "waiting"] },
    { thought: "I priced myself like I was still proving I deserved the chair.", core: "pricing like I must prove it", tags: ["pricing", "deserve", "chair"] },
    { thought: "The late fee arrived and I felt personally unmasked by a number.", core: "unmasked by a late fee", tags: ["late_fee", "unmasked", "number"] },
  ],
  romantic: [
    { thought: "I keep rereading the last text like tone is something I can prove.", core: "rereading the last text", tags: ["text", "tone", "rumination"] },
    { thought: "They said they needed space and I heard I had been too much.", core: "space meaning too much", tags: ["space", "too_much", "break"] },
    { thought: "I almost said how I felt and then I made a joke instead.", core: "joking instead of saying it", tags: ["joke", "feelings", "avoidance"] },
    { thought: "I saw them laugh with someone else and my whole body went quiet.", core: "watching them laugh elsewhere", tags: ["jealousy", "laugh", "quiet"] },
    { thought: "We keep having the same fight like it is a room we cannot leave.", core: "the fight we cannot leave", tags: ["fight", "loop", "stuck"] },
    { thought: "I planned the weekend around them and they forgot I existed.", core: "planning around being forgotten", tags: ["weekend", "forgotten", "plan"] },
    { thought: "I am scared I am only easy to love when I ask for nothing.", core: "easy to love when I ask nothing", tags: ["easy", "ask", "love"] },
    { thought: "They touched my arm in public and I still do not trust it.", core: "not trusting a public touch", tags: ["touch", "public", "trust"] },
    { thought: "I keep waiting for the version of them that showed up in week two.", core: "waiting for week-two them", tags: ["early", "waiting", "change"] },
    { thought: "I said I was fine with casual and I have not been fine once.", core: "lying about casual", tags: ["casual", "fine", "lie"] },
    { thought: "The silence after goodnight feels like a test I keep failing.", core: "silence after goodnight", tags: ["goodnight", "silence", "test"] },
    { thought: "I compared our timeline to everyone else's and I felt behind.", core: "comparing our timeline", tags: ["timeline", "behind", "compare"] },
    { thought: "I want to be chosen out loud and I hate how hungry that sounds.", core: "wanting to be chosen out loud", tags: ["chosen", "hungry", "want"] },
    { thought: "They remember details about work and forget the things that hurt.", core: "remembering work not the hurt", tags: ["details", "hurt", "forget"] },
    { thought: "I keep drafting the breakup in my notes like that is control.", core: "drafting the breakup", tags: ["breakup", "notes", "control"] },
    { thought: "I flinched when they got close and then I apologized for flinching.", core: "apologizing for a flinch", tags: ["flinch", "apology", "close"] },
    { thought: "I am tired of being the one who names the weather in the room.", core: "naming the weather alone", tags: ["emotional_labor", "weather", "tired"] },
    { thought: "They said I was overthinking and I swallowed the rest of the night.", core: "swallowing after overthinking", tags: ["overthinking", "swallow", "night"] },
    { thought: "I keep checking if they viewed the story like that is a pulse.", core: "checking the story view", tags: ["story", "pulse", "check"] },
    { thought: "I miss them in the middle of an ordinary grocery run and it startles me.", core: "missing them in the grocery", tags: ["miss", "grocery", "ordinary"] },
    { thought: "I do not know if I want them or if I want to stop feeling optional.", core: "not wanting to feel optional", tags: ["optional", "want", "confusion"] },
    { thought: "We were good until the future came up and then everything went thin.", core: "the future making it thin", tags: ["future", "thin", "talk"] },
    { thought: "I keep performing unbothered and my jaw is tired of the act.", core: "performing unbothered", tags: ["unbothered", "jaw", "act"] },
    { thought: "They apologized in a way that asked me to move on immediately.", core: "an apology that rushes me", tags: ["apology", "rush", "move_on"] },
    { thought: "I am scared the spark was just relief at being wanted at all.", core: "spark that was only relief", tags: ["spark", "relief", "wanted"] },
    { thought: "I left my toothbrush there and now it feels like a hostage.", core: "the hostage toothbrush", tags: ["toothbrush", "hostage", "place"] },
    { thought: "I keep hoping a better conversation is waiting behind this one.", core: "hoping for a better conversation", tags: ["conversation", "hope", "behind"] },
    { thought: "They called me intense and I have been quieter ever since.", core: "going quiet after intense", tags: ["intense", "quiet", "label"] },
    { thought: "I do not recognize the version of me that begs in private.", core: "the private begging version", tags: ["private", "beg", "self"] },
    { thought: "I keep the photos and I hate that I still need the evidence.", core: "keeping photos as evidence", tags: ["photos", "evidence", "need"] },
  ],
  family: [
    { thought: "I hung up and immediately started defending myself to an empty room.", core: "defending myself after hanging up", tags: ["phone", "defend", "empty"] },
    { thought: "They asked when I was visiting like love is a calendar I keep failing.", core: "love as a failed calendar", tags: ["visit", "calendar", "guilt"] },
    { thought: "I became the translator at dinner and nobody asked if I was tired.", core: "translating dinner unpaid", tags: ["translator", "dinner", "tired"] },
    { thought: "Dad made the joke and everyone laughed except the part of me that was the joke.", core: "being the family joke", tags: ["joke", "dad", "laugh"] },
    { thought: "I keep hoping this holiday will be the one where I am not twelve.", core: "hoping the holiday grows me up", tags: ["holiday", "twelve", "hope"] },
    { thought: "They talk about my sibling like a trophy and me like a weather report.", core: "being the weather report child", tags: ["sibling", "trophy", "compare"] },
    { thought: "I told the truth at lunch and the table went polite and cold.", core: "truth that cooled the table", tags: ["truth", "lunch", "cold"] },
    { thought: "Mom says she is fine and I can hear the unpaid bill in her voice.", core: "hearing the bill in her voice", tags: ["mom", "fine", "bill"] },
    { thought: "I rehearsed a boundary and then I asked if they needed anything.", core: "rehearsing then people-pleasing", tags: ["boundary", "rehearse", "please"] },
    { thought: "They still introduce me with the old story I have been trying to outgrow.", core: "the old introduction story", tags: ["introduction", "old_story", "outgrow"] },
    { thought: "I am the emergency contact and never the person they are proud of.", core: "emergency not pride", tags: ["emergency", "pride", "role"] },
    { thought: "I left the group chat on mute and still felt like I was betraying them.", core: "muting as betrayal", tags: ["group_chat", "mute", "betray"] },
    { thought: "They asked why I was sensitive like my whole childhood was a mood.", core: "childhood called a mood", tags: ["sensitive", "childhood", "mood"] },
    { thought: "I keep bringing food because it is the only language that does not start a fight.", core: "food as the safe language", tags: ["food", "language", "fight"] },
    { thought: "I watched them rewrite the past until I wondered if I invented the hurt.", core: "watching them rewrite the past", tags: ["rewrite", "past", "gaslight"] },
    { thought: "I am tired of being the calm one while they get to fall apart.", core: "always being the calm one", tags: ["calm", "labor", "tired"] },
    { thought: "The house still smells like childhood and my shoulders go up at the door.", core: "shoulders up at the door", tags: ["house", "childhood", "body"] },
    { thought: "They needed a ride and I canceled my only quiet night without blinking.", core: "canceling the quiet night", tags: ["ride", "quiet", "cancel"] },
    { thought: "I keep waiting for an apology that would have to unmake too many years.", core: "an apology that unmakes years", tags: ["apology", "years", "waiting"] },
    { thought: "They posted a family photo and I was cropped by the angle, not by accident.", core: "cropped out of the photo", tags: ["photo", "cropped", "exclude"] },
    { thought: "I practiced saying no and my voice still arrived as a maybe.", core: "no arriving as maybe", tags: ["no", "maybe", "voice"] },
    { thought: "Uncle asked about my job like it was a test I had already failed.", core: "the uncle job test", tags: ["uncle", "job", "test"] },
    { thought: "I feel like a guest in the house I learned to walk in.", core: "a guest in the first house", tags: ["guest", "house", "belong"] },
    { thought: "They say we do not keep secrets and then they look at me to stay quiet.", core: "secrets I am told to keep", tags: ["secrets", "quiet", "look"] },
    { thought: "I packed the leftovers they did not want and called it being useful.", core: "packing leftovers as usefulness", tags: ["leftovers", "useful", "pack"] },
    { thought: "I am scared I am becoming the parent I swore I would not copy.", core: "becoming the parent I feared", tags: ["copy", "parent", "fear"] },
    { thought: "They remember my childhood wrong and correct me with confidence.", core: "being corrected about my childhood", tags: ["memory", "correct", "childhood"] },
    { thought: "I keep shrinking my news so nobody has to feel anything about me.", core: "shrinking my news", tags: ["news", "shrink", "protect"] },
    { thought: "The family thread is jokes until someone needs care, then it goes dead.", core: "jokes until care is needed", tags: ["thread", "jokes", "care"] },
    { thought: "I left early and spent the drive writing a nicer version of myself.", core: "rewriting myself on the drive", tags: ["drive", "rewrite", "early"] },
  ],
  friends_social: [
    { thought: "The group chat moved on without me and I read it like a verdict.", core: "the chat moving on", tags: ["group_chat", "verdict", "left_out"] },
    { thought: "They made plans in front of me and still said we should hang soon.", core: "plans made in front of me", tags: ["plans", "soon", "exclude"] },
    { thought: "I laughed too loud and then replayed it like I had broken a rule.", core: "replaying the loud laugh", tags: ["laugh", "replay", "rule"] },
    { thought: "I keep being the planner and nobody plans me back.", core: "planning nobody returns", tags: ["planner", "unreturned", "effort"] },
    { thought: "They posted the night I was not invited and the caption said family.", core: "family caption without me", tags: ["post", "invite", "family"] },
    { thought: "I told a real thing and they changed the subject to a meme.", core: "a real thing met with a meme", tags: ["real", "meme", "subject"] },
    { thought: "I am tired of being easy to cancel and hard to miss.", core: "easy to cancel, hard to miss", tags: ["cancel", "miss", "tired"] },
    { thought: "I saw the photos later and my smile looked like I was bargaining.", core: "a bargaining smile in photos", tags: ["photos", "smile", "bargain"] },
    { thought: "I keep offering help because it is the only way I know to stay.", core: "help as a way to stay", tags: ["help", "stay", "offer"] },
    { thought: "They said I had been distant and I had been waiting to be asked in.", core: "distant because I was waiting", tags: ["distant", "ask", "waiting"] },
    { thought: "I practiced a story for dinner and then I went quiet anyway.", core: "going quiet after practicing", tags: ["story", "quiet", "dinner"] },
    { thought: "The inside jokes arrived after I left and I felt replaceable.", core: "jokes after I left", tags: ["jokes", "replaceable", "left"] },
    { thought: "I keep checking who viewed my story like friendship has analytics.", core: "friendship as analytics", tags: ["story", "analytics", "check"] },
    { thought: "They vent to me for an hour and go quiet when I start a sentence.", core: "venting that does not come back", tags: ["vent", "one_way", "quiet"] },
    { thought: "I was fun until I needed something, and then I became a tone.", core: "becoming a tone when I need", tags: ["fun", "need", "tone"] },
    { thought: "I keep saying next time and I do not believe myself anymore.", core: "next time I do not believe", tags: ["next_time", "believe", "delay"] },
    { thought: "They introduced me wrong and I smiled so nobody would feel awkward.", core: "smiling through a wrong intro", tags: ["intro", "wrong", "smile"] },
    { thought: "I left the party early and spent the walk accusing myself of being boring.", core: "leaving early as boring", tags: ["party", "boring", "walk"] },
    { thought: "I am scared I am only kept around because I am useful in a crisis.", core: "kept for crisis usefulness", tags: ["crisis", "useful", "kept"] },
    { thought: "The birthday came and went and my name was a maybe on the list.", core: "a maybe on the birthday list", tags: ["birthday", "maybe", "list"] },
    { thought: "I keep matching their energy and losing the person I am alone.", core: "matching energy until I vanish", tags: ["energy", "vanish", "match"] },
    { thought: "They said we were close and still did not know the thing that hurt.", core: "close without the hurt", tags: ["close", "hurt", "know"] },
    { thought: "I drafted a message for three days and sent a heart instead.", core: "three days into a heart", tags: ["draft", "heart", "delay"] },
    { thought: "I feel like a plus-one in rooms where I used to have a chair.", core: "plus-one without a chair", tags: ["plus_one", "chair", "rooms"] },
    { thought: "They bonded over a trip I could not afford and called it nothing personal.", core: "a trip called nothing personal", tags: ["trip", "afford", "personal"] },
    { thought: "I keep laughing first so nobody has to wonder if I belong.", core: "laughing first to belong", tags: ["laugh", "belong", "first"] },
    { thought: "I watched two friends become a unit and I became the context.", core: "becoming the context", tags: ["unit", "context", "watch"] },
    { thought: "I am exhausted by being pleasant in rooms that never ask me back.", core: "pleasant in rooms that do not ask", tags: ["pleasant", "rooms", "ask"] },
    { thought: "They forgot my thing and remembered a stranger's dog's birthday.", core: "forgotten beside a dog birthday", tags: ["forgot", "dog", "birthday"] },
    { thought: "I keep shrinking my stories so they fit inside someone else's night.", core: "shrinking stories to fit", tags: ["stories", "shrink", "night"] },
  ],
  health: [
    { thought: "I woke up tired again and I am already apologizing to the day.", core: "apologizing to a tired morning", tags: ["tired", "morning", "apology"] },
    { thought: "The test results are taking forever and I keep inventing the worst line.", core: "inventing the worst test line", tags: ["test", "waiting", "worst"] },
    { thought: "I skipped the walk and then spent the evening prosecuting myself.", core: "prosecuting a skipped walk", tags: ["walk", "skip", "guilt"] },
    { thought: "My body did the sharp thing again and I pretended it was nothing.", core: "pretending the sharp thing is nothing", tags: ["pain", "pretend", "body"] },
    { thought: "I keep googling symptoms like knowledge could bargain with luck.", core: "googling as bargaining", tags: ["google", "symptoms", "luck"] },
    { thought: "The doctor spoke quickly and I nodded like I had understood my own life.", core: "nodding through the doctor", tags: ["doctor", "nod", "speed"] },
    { thought: "I am scared this tiredness is a warning I keep calling a personality.", core: "tiredness called personality", tags: ["fatigue", "warning", "personality"] },
    { thought: "I ate in the car and called it a plan so I would not feel behind.", core: "car food as a plan", tags: ["food", "car", "plan"] },
    { thought: "Sleep will not come and I am already dreading the person I will be at nine.", core: "dreading the nine o'clock self", tags: ["sleep", "dread", "night"] },
    { thought: "I keep postponing the appointment because wanting help feels dramatic.", core: "help feeling dramatic", tags: ["appointment", "help", "dramatic"] },
    { thought: "My hands shook in the meeting and I hid them under the table.", core: "hiding shaking hands", tags: ["hands", "meeting", "hide"] },
    { thought: "I compared my recovery to people online and decided I was failing quietly.", core: "failing recovery by comparison", tags: ["recovery", "online", "fail"] },
    { thought: "I took the pill and then felt guilty for needing a small chemical mercy.", core: "guilt after a needed pill", tags: ["pill", "guilt", "mercy"] },
    { thought: "The pain is not dramatic enough to count and still it runs the day.", core: "pain that does not count", tags: ["pain", "count", "day"] },
    { thought: "I keep promising I will start Monday like my body is a project.", core: "Monday as a body project", tags: ["monday", "project", "start"] },
    { thought: "I canceled because I felt awful and then I felt like a liar.", core: "canceling and feeling like a liar", tags: ["cancel", "awful", "liar"] },
    { thought: "I am tired of explaining a body that does not perform on command.", core: "a body not on command", tags: ["explain", "perform", "command"] },
    { thought: "The waiting room made me feel like I had imagined the whole problem.", core: "imagining the problem in waiting", tags: ["waiting_room", "imagine", "problem"] },
    { thought: "I keep stretching at my desk like that could undo the last five years.", core: "stretching to undo years", tags: ["stretch", "desk", "years"] },
    { thought: "I felt my heart race and immediately wrote a story about dying in line.", core: "a dying story in line", tags: ["heart", "line", "story"] },
    { thought: "I am scared the scan will confirm I waited too long to speak up.", core: "waiting too long to speak", tags: ["scan", "wait", "speak"] },
    { thought: "I tracked every bite and still felt like I had cheated the day.", core: "tracking and still cheating", tags: ["track", "bite", "cheat"] },
    { thought: "They said it was stress and I heard you are making this up.", core: "stress meaning made up", tags: ["stress", "made_up", "dismiss"] },
    { thought: "I keep bargaining with sleep like it is a person I have disappointed.", core: "bargaining with sleep", tags: ["sleep", "bargain", "disappoint"] },
    { thought: "My energy crashes at four and I spend the evening pretending I am still here.", core: "crashing at four", tags: ["crash", "four", "pretend"] },
    { thought: "I am embarrassed how much of my personality is managing this body.", core: "personality as body management", tags: ["manage", "body", "embarrassed"] },
    { thought: "I skipped lunch and called it focus so nobody would call it a problem.", core: "skipping lunch as focus", tags: ["lunch", "focus", "skip"] },
    { thought: "The flare came back and I mourned the week I thought I had earned.", core: "mourning a week I earned", tags: ["flare", "mourn", "week"] },
    { thought: "I keep smiling through the appointment so they will take me seriously.", core: "smiling to be taken seriously", tags: ["smile", "appointment", "serious"] },
    { thought: "I am scared my careful routines are just fear wearing a schedule.", core: "routines that are only fear", tags: ["routine", "fear", "schedule"] },
  ],
  self_worth: [
    { thought: "I keep waiting for someone to confirm I am allowed to take up the chair.", core: "waiting for permission to sit", tags: ["permission", "chair", "allowed"] },
    { thought: "I heard my own voice on the recording and I wanted to disappear.", core: "hating my recorded voice", tags: ["voice", "recording", "disappear"] },
    { thought: "I did the thing well and still hunted for the flaw like it was rent.", core: "hunting the flaw after doing well", tags: ["flaw", "rent", "hunt"] },
    { thought: "Compliments bounce off me and criticism moves in with furniture.", core: "criticism moving in", tags: ["compliment", "criticism", "furniture"] },
    { thought: "I keep shrinking in photos like the camera might catch me wanting space.", core: "shrinking in photos", tags: ["photos", "shrink", "space"] },
    { thought: "I said thank you too fast like gratitude could cancel the attention.", core: "thank you canceling attention", tags: ["thank_you", "attention", "fast"] },
    { thought: "I compare my insides to everyone else's highlight and call it data.", core: "calling comparison data", tags: ["compare", "highlight", "data"] },
    { thought: "I am scared people only like the useful version of me.", core: "being liked as the useful version", tags: ["useful", "liked", "version"] },
    { thought: "I keep apologizing for existing in the doorway a second too long.", core: "apologizing in the doorway", tags: ["apology", "doorway", "exist"] },
    { thought: "I achieved the thing and felt nothing, then felt broken for feeling nothing.", core: "feeling nothing at the win", tags: ["achieve", "nothing", "broken"] },
    { thought: "I talk myself out of applying before the page even loads.", core: "talking myself out of applying", tags: ["apply", "talk", "before"] },
    { thought: "I keep editing my stories until I sound like a person who does not need.", core: "editing out needing", tags: ["edit", "need", "stories"] },
    { thought: "I feel fake in rooms that asked me to come, like I snuck in.", core: "feeling fake in invited rooms", tags: ["fake", "invited", "sneak"] },
    { thought: "I cannot take a compliment without immediately offering a discount.", core: "discounting the compliment", tags: ["compliment", "discount", "cannot"] },
    { thought: "I keep a list of reasons they will leave once they know the rest.", core: "a list of reasons they will leave", tags: ["list", "leave", "know"] },
    { thought: "I am harsh with myself in a voice I would never use on a stranger.", core: "a voice I spare strangers", tags: ["harsh", "stranger", "voice"] },
    { thought: "I downplayed the win so nobody would have to clap for me.", core: "downplaying so nobody claps", tags: ["win", "downplay", "clap"] },
    { thought: "I keep waiting to feel ready like readiness is a personality I missed.", core: "readiness as a missed personality", tags: ["ready", "missed", "wait"] },
    { thought: "I saw my name on the list and assumed it was a clerical error.", core: "my name as a clerical error", tags: ["name", "list", "error"] },
    { thought: "I keep performing humble so nobody can accuse me of wanting more.", core: "humble as a defense", tags: ["humble", "want", "accuse"] },
    { thought: "I feel like a draft of a person other people already finished.", core: "a draft of a finished person", tags: ["draft", "finished", "person"] },
    { thought: "I practiced the introduction and still sounded like I was apologizing.", core: "an introduction that apologizes", tags: ["introduction", "practice", "apology"] },
    { thought: "I keep abandoning hobbies the moment I am not immediately good.", core: "abandoning hobbies that are not easy", tags: ["hobbies", "good", "abandon"] },
    { thought: "I am scared my personality is just a set of precautions.", core: "personality as precautions", tags: ["personality", "precautions", "scared"] },
    { thought: "I let someone else decide because choosing felt like arrogance.", core: "choosing feeling like arrogance", tags: ["choose", "arrogance", "let"] },
    { thought: "I keep translating my needs into jokes so they arrive smaller.", core: "needs arriving as jokes", tags: ["needs", "jokes", "smaller"] },
    { thought: "I feel behind a life I have not even admitted I want.", core: "behind a life I will not admit", tags: ["behind", "want", "admit"] },
    { thought: "I deleted the post because wanting to be seen felt indecent.", core: "wanting to be seen as indecent", tags: ["post", "seen", "delete"] },
    { thought: "I keep treating rest like a prize I have not earned this week.", core: "rest as an unearned prize", tags: ["rest", "prize", "earn"] },
    { thought: "I am tired of auditioning for a self I already live in.", core: "auditioning for the self I live", tags: ["audition", "self", "tired"] },
  ],
  future: [
    { thought: "I keep refreshing a future that has not written back yet.", core: "a future that has not written", tags: ["refresh", "future", "waiting"] },
    { thought: "Five-year plans make me feel like I am already late to myself.", core: "late to my five-year plan", tags: ["five_year", "late", "plan"] },
    { thought: "I cannot picture next year without flinching at the empty calendar.", core: "flinching at next year's calendar", tags: ["calendar", "next_year", "empty"] },
    { thought: "Everyone else seems to have a plot and I am still in the credits.", core: "still in the credits", tags: ["plot", "credits", "everyone"] },
    { thought: "I said I would know by now and I do not, and that feels like failure.", core: "not knowing by now", tags: ["know", "failure", "now"] },
    { thought: "I keep collecting tabs about other lives like that is a decision.", core: "tabs instead of a decision", tags: ["tabs", "lives", "decision"] },
    { thought: "The future used to feel wide and now it feels like a hallway.", core: "a hallway instead of a future", tags: ["hallway", "wide", "now"] },
    { thought: "I am scared I will still be circling this same doubt in ten years.", core: "the same doubt in ten years", tags: ["doubt", "ten_years", "circle"] },
    { thought: "I cannot tell if I am patient or if I am hiding in maybe.", core: "hiding in maybe", tags: ["patient", "maybe", "hide"] },
    { thought: "They asked where I saw myself and I offered a joke so I would not freeze.", core: "a joke instead of a future", tags: ["where", "joke", "freeze"] },
    { thought: "I keep waiting for a sign that will not look like ordinary Tuesday.", core: "waiting for more than Tuesday", tags: ["sign", "tuesday", "wait"] },
    { thought: "I feel behind people who started later and somehow arrived first.", core: "arriving after people who started later", tags: ["behind", "later", "arrived"] },
    { thought: "I mapped a plan and then I got tired of pretending I believed it.", core: "a plan I do not believe", tags: ["plan", "believe", "tired"] },
    { thought: "I am afraid choosing one life means I am killing the other ones.", core: "killing the other lives by choosing", tags: ["choose", "kill", "lives"] },
    { thought: "The clock on the application is loud and I am still rewriting the first line.", core: "rewriting the first line", tags: ["application", "clock", "rewrite"] },
    { thought: "I keep calling this a gap year in my head even though it is year three.", core: "a gap year that is year three", tags: ["gap", "three", "call"] },
    { thought: "I cannot commit because every path looks like the wrong hallway in the dark.", core: "every path a dark hallway", tags: ["commit", "path", "dark"] },
    { thought: "I watch other people move and I narrate why I cannot yet.", core: "narrating why I cannot move", tags: ["watch", "move", "narrate"] },
    { thought: "I am scared the best version of this already happened without me noticing.", core: "the best version already happened", tags: ["best", "happened", "notice"] },
    { thought: "I keep delaying the leap because I want a guarantee dressed as research.", core: "research instead of a leap", tags: ["leap", "guarantee", "research"] },
    { thought: "Tomorrow feels like a test I have not studied for in months.", core: "tomorrow as an unstudied test", tags: ["tomorrow", "test", "study"] },
    { thought: "I said someday so often it started to sound like never.", core: "someday sounding like never", tags: ["someday", "never", "sound"] },
    { thought: "I cannot tell ambition from panic when they wear the same calendar.", core: "ambition wearing panic's calendar", tags: ["ambition", "panic", "calendar"] },
    { thought: "I keep the old dream in a notes app like a person I ghosted.", core: "ghosting the old dream", tags: ["dream", "notes", "ghost"] },
    { thought: "I am tired of potential as a personality other people lend me.", core: "potential as a lent personality", tags: ["potential", "lend", "tired"] },
    { thought: "The future asks for a decision and I keep offering a mood.", core: "offering a mood to the future", tags: ["decision", "mood", "offer"] },
    { thought: "I feel like I missed a train that was never on the board.", core: "a train never on the board", tags: ["train", "missed", "board"] },
    { thought: "I keep waiting to want it enough, as if desire is a switch.", core: "waiting to want it enough", tags: ["desire", "switch", "wait"] },
    { thought: "I am scared I will choose safety and call it wisdom for decades.", core: "safety wearing wisdom for decades", tags: ["safety", "wisdom", "decades"] },
    { thought: "I packed a bag for a life I still will not name out loud.", core: "a packed bag for an unnamed life", tags: ["bag", "unnamed", "life"] },
  ],
  grief_loss: [
    { thought: "I reached for the phone to tell them and then I remembered the quiet.", core: "reaching for a phone that is quiet", tags: ["phone", "remember", "quiet"] },
    { thought: "The anniversary arrived like weather and I still pretended I had a plan.", core: "an anniversary without a plan", tags: ["anniversary", "weather", "plan"] },
    { thought: "I laughed and then felt like I had betrayed the missing.", core: "laughter as betrayal of the missing", tags: ["laugh", "betray", "missing"] },
    { thought: "Their mug is still in the cabinet and I cannot decide if that is love.", core: "a mug I cannot decide about", tags: ["mug", "cabinet", "love"] },
    { thought: "People say time helps and I want to put time in a chair and interview it.", core: "interviewing time about helping", tags: ["time", "helps", "people"] },
    { thought: "I keep their voicemail because deleting it feels like a second ending.", core: "a voicemail as a second ending", tags: ["voicemail", "delete", "ending"] },
    { thought: "The house is too loud with ordinary sounds they will never make again.", core: "ordinary sounds they will not make", tags: ["house", "sounds", "again"] },
    { thought: "I got angry at a stranger for living like the world had not cracked.", core: "anger at an uncracked world", tags: ["anger", "stranger", "world"] },
    { thought: "I tell the story shorter now so nobody has to sit in it with me.", core: "shortening the story for others", tags: ["story", "shorter", "sit"] },
    { thought: "I keep waiting for the version of me that can grocery shop without the drop.", core: "grocery shopping with the drop", tags: ["grocery", "drop", "wait"] },
    { thought: "Their birthday is on the calendar and I still do not know the etiquette.", core: "a birthday without etiquette", tags: ["birthday", "calendar", "etiquette"] },
    { thought: "I dreamed they were in the kitchen and waking up felt like a rude clerk.", core: "waking from the kitchen dream", tags: ["dream", "kitchen", "wake"] },
    { thought: "I am tired of being the strong one when I still set two plates.", core: "still setting two plates", tags: ["strong", "plates", "tired"] },
    { thought: "The song came on in a shop and I had to leave a basket behind.", core: "leaving a basket for a song", tags: ["song", "shop", "basket"] },
    { thought: "I keep their coat because the empty hook looks too honest.", core: "a coat hiding an honest hook", tags: ["coat", "hook", "empty"] },
    { thought: "People moved on with a softness I cannot fake yet.", core: "softness I cannot fake yet", tags: ["moved_on", "softness", "fake"] },
    { thought: "I talk to the ceiling at night like the air might still be listening.", core: "talking to the ceiling", tags: ["night", "ceiling", "listen"] },
    { thought: "I am scared I am forgetting the exact way they said my name.", core: "forgetting how they said my name", tags: ["name", "forget", "voice"] },
    { thought: "The world wants a lesson and I only have a hole with a schedule.", core: "a hole with a schedule", tags: ["lesson", "hole", "world"] },
    { thought: "I keep the last photo face down because looking feels like picking a scab.", core: "a face-down last photo", tags: ["photo", "scab", "last"] },
    { thought: "I got through the day and then the evening remembered everything.", core: "evening remembering everything", tags: ["day", "evening", "remember"] },
    { thought: "I am jealous of people who still have someone to be annoyed at.", core: "jealous of ordinary annoyance", tags: ["jealous", "annoyed", "still"] },
    { thought: "The condolence texts stopped and the quiet felt like a second death.", core: "quiet after the texts stopped", tags: ["texts", "quiet", "second"] },
    { thought: "I keep living around the absence like it is furniture I cannot donate.", core: "absence as undonatable furniture", tags: ["absence", "furniture", "live"] },
    { thought: "I said I was okay so they could leave the conversation intact.", core: "okay so they could leave intact", tags: ["okay", "conversation", "leave"] },
    { thought: "I found their handwriting and it undid an hour I thought I had earned.", core: "handwriting undoing an earned hour", tags: ["handwriting", "hour", "found"] },
    { thought: "I am learning a life that still has their shape cut out of it.", core: "a life with their shape cut out", tags: ["shape", "cut", "life"] },
    { thought: "The first holiday without them is a script with a missing line.", core: "a holiday missing a line", tags: ["holiday", "script", "missing"] },
    { thought: "I keep being told they would want me to be happy and I want them instead.", core: "wanting them instead of happy", tags: ["happy", "want", "instead"] },
    { thought: "I packed a box and then sat on the floor like moving was a betrayal.", core: "packing as a betrayal", tags: ["box", "floor", "move"] },
  ],
  identity: [
    { thought: "I keep translating myself in rooms that never asked who I actually am.", core: "translating myself unasked", tags: ["translate", "rooms", "who"] },
    { thought: "They used the old name and my whole body went polite and far away.", core: "the old name landing", tags: ["name", "old", "body"] },
    { thought: "I do not know which version of me is the one I am supposed to feed.", core: "not knowing which me to feed", tags: ["version", "feed", "supposed"] },
    { thought: "I smiled through a joke about people like me and hated my manners.", core: "manners around a joke about me", tags: ["joke", "manners", "smile"] },
    { thought: "I keep choosing clothes like armor and still feel see-through.", core: "clothes as see-through armor", tags: ["clothes", "armor", "see"] },
    { thought: "The form had no honest box and I sat there inventing a smaller self.", core: "inventing a smaller self on a form", tags: ["form", "box", "smaller"] },
    { thought: "I am tired of being interesting in theory and inconvenient in person.", core: "interesting until I am in person", tags: ["interesting", "inconvenient", "person"] },
    { thought: "I code-switch so fast I lose the sentence I started in.", core: "losing the sentence I started", tags: ["code_switch", "sentence", "fast"] },
    { thought: "They asked where I was really from and I gave them a map instead of a door.", core: "a map instead of a door", tags: ["from", "map", "door"] },
    { thought: "I keep performing easy so nobody has to update their idea of me.", core: "easy so they will not update", tags: ["easy", "perform", "update"] },
    { thought: "I do not recognize the laugh I use in that office.", core: "an office laugh I do not own", tags: ["laugh", "office", "recognize"] },
    { thought: "I am scared I built a self that only works in other people's lighting.", core: "a self for other lighting", tags: ["built", "lighting", "others"] },
    { thought: "The mirror and I are in a cold negotiation about who gets to stay.", core: "a cold negotiation with the mirror", tags: ["mirror", "negotiation", "stay"] },
    { thought: "I keep hiding the part of me that would make the dinner longer.", core: "hiding the part that lengthens dinner", tags: ["hide", "dinner", "part"] },
    { thought: "I said I was fine being undefined and I have never been fine with it.", core: "undefined and not fine", tags: ["undefined", "fine", "said"] },
    { thought: "I feel like a guest in the language I dreamed in as a kid.", core: "a guest in the first language", tags: ["language", "guest", "kid"] },
    { thought: "They clapped for the palatable story and I buried the rest in a pocket.", core: "burying the rest of the story", tags: ["palatable", "story", "bury"] },
    { thought: "I keep trying on futures like jackets that were cut for someone else.", core: "futures cut for someone else", tags: ["futures", "jackets", "else"] },
    { thought: "I am exhausted by explaining a self that should not need a pamphlet.", core: "a self that should not need a pamphlet", tags: ["explain", "pamphlet", "exhausted"] },
    { thought: "I changed the bio and then felt like I had committed a small crime.", core: "changing the bio as a crime", tags: ["bio", "change", "crime"] },
    { thought: "I keep splitting myself into rooms so nobody gets the whole weather.", core: "splitting myself into rooms", tags: ["split", "rooms", "weather"] },
    { thought: "I want to be specific and I am scared specificity is a dare.", core: "specificity as a dare", tags: ["specific", "dare", "scared"] },
    { thought: "They praised my resilience and I heard you may not rest here.", core: "resilience meaning do not rest", tags: ["resilience", "rest", "praise"] },
    { thought: "I am not sure if I am becoming or if I am just leaving disguises.", core: "becoming or leaving disguises", tags: ["become", "disguise", "leave"] },
    { thought: "I keep my voice smaller in family rooms and larger with strangers.", core: "a smaller voice in family rooms", tags: ["voice", "family", "strangers"] },
    { thought: "The group assumed I would speak for everyone who looked like a maybe.", core: "speaking for every maybe", tags: ["group", "speak", "maybe"] },
    { thought: "I feel fraudulent in both places, like I failed a test I never sat.", core: "fraudulent in both places", tags: ["fraud", "both", "test"] },
    { thought: "I keep sanding down the edges so I can fit a table that was never mine.", core: "sanding edges for a table", tags: ["edges", "table", "fit"] },
    { thought: "I want a name that does not arrive with a footnote.", core: "a name without a footnote", tags: ["name", "footnote", "want"] },
    { thought: "I am tired of being a bridge and never a place to land.", core: "a bridge that is never a landing", tags: ["bridge", "land", "tired"] },
  ],
  other: [
    { thought: "I cannot name the ache and it still runs the afternoon like a manager.", core: "an unnamed ache running the afternoon", tags: ["unnamed", "ache", "afternoon"] },
    { thought: "The day is fine on paper and my chest is still waiting for a verdict.", core: "a fine day waiting for a verdict", tags: ["fine", "chest", "verdict"] },
    { thought: "I keep almost crying in ordinary places like the feeling has no appointment.", core: "crying without an appointment", tags: ["crying", "ordinary", "appointment"] },
    { thought: "I am restless in a life I asked for and that contradiction wears me out.", core: "restless in the asked-for life", tags: ["restless", "asked", "life"] },
    { thought: "Nothing is wrong enough to count and everything is slightly too heavy.", core: "nothing wrong and still too heavy", tags: ["wrong", "heavy", "count"] },
    { thought: "I keep opening the notes app and closing it like a stalled confession.", core: "a stalled notes-app confession", tags: ["notes", "confession", "stall"] },
    { thought: "The weather changed and my mood followed it like I had no say.", core: "a mood that follows weather", tags: ["weather", "mood", "say"] },
    { thought: "I am bored of my own loops and still I run them before breakfast.", core: "running loops before breakfast", tags: ["loops", "bored", "breakfast"] },
    { thought: "I cannot tell if I need rest or a different life wearing rest's clothes.", core: "rest or a different life", tags: ["rest", "life", "clothes"] },
    { thought: "I keep waiting for a reason that would make this feeling respectable.", core: "wanting a respectable reason", tags: ["reason", "respectable", "wait"] },
    { thought: "Sunday evening arrives and I mourn a week that has not started.", core: "mourning a week that has not started", tags: ["sunday", "mourn", "week"] },
    { thought: "I am lonely in a full room and I blame my personality for the math.", core: "lonely in a full room", tags: ["lonely", "room", "math"] },
    { thought: "I keep tidying like order might convince my chest to stand down.", core: "tidying to stand the chest down", tags: ["tidy", "order", "chest"] },
    { thought: "The notification pile feels like people I have already disappointed.", core: "notifications as disappointment", tags: ["notifications", "disappoint", "pile"] },
    { thought: "I cannot land on a thought long enough to tell it the truth.", core: "not landing long enough for truth", tags: ["land", "thought", "truth"] },
    { thought: "I feel behind a day that has barely begun and I have not left the bed.", core: "behind a day from bed", tags: ["behind", "bed", "day"] },
    { thought: "I keep scrolling for a feeling that is not this dull static.", core: "scrolling for something not static", tags: ["scroll", "static", "feeling"] },
    { thought: "I said I was unmotivated and I think I am actually afraid.", core: "unmotivated that is actually afraid", tags: ["unmotivated", "afraid", "said"] },
    { thought: "The apartment is quiet in a way that feels like an unanswered question.", core: "quiet as an unanswered question", tags: ["apartment", "quiet", "question"] },
    { thought: "I keep almost starting and then I negotiate with the chair instead.", core: "negotiating with the chair", tags: ["start", "chair", "negotiate"] },
    { thought: "I am full of unfinished sentences and they all want to be emergencies.", core: "unfinished sentences as emergencies", tags: ["sentences", "unfinished", "emergency"] },
    { thought: "I cannot find the off switch for a brain that is doing unpaid overtime.", core: "a brain on unpaid overtime", tags: ["brain", "overtime", "off"] },
    { thought: "I keep mistaking numbness for calm because at least it is quiet.", core: "numbness wearing calm", tags: ["numb", "calm", "quiet"] },
    { thought: "I want a reset button and I am embarrassed how childish that sounds.", core: "wanting a childish reset", tags: ["reset", "childish", "want"] },
    { thought: "I am carrying a mood I cannot source, like lost luggage with my name on it.", core: "lost luggage with my name", tags: ["mood", "source", "luggage"] },
    { thought: "The to-do list looks reasonable and still it feels like a cliff.", core: "a reasonable list that is a cliff", tags: ["todo", "cliff", "reasonable"] },
    { thought: "I keep waiting for motivation like it is a guest who said they were coming.", core: "motivation as a late guest", tags: ["motivation", "guest", "wait"] },
    { thought: "I cannot tell hunger from sadness until I have already opened the cabinet.", core: "hunger and sadness in the cabinet", tags: ["hunger", "sadness", "cabinet"] },
    { thought: "I am tired of being a person who almost starts and then explains.", core: "almost starting then explaining", tags: ["almost", "start", "explain"] },
    { thought: "Nothing happened and I still feel like I lost an argument with the day.", core: "losing an argument with the day", tags: ["nothing", "argument", "day"] },
  ],
};

const TAG_EXTRAS = ["waiting", "shame", "replay", "quiet", "body", "night", "almost", "still"];

const EMOTION_PAIRS: Emotion[][] = [
  ["shame", "fear"],
  ["sadness", "loneliness"],
  ["anger", "overwhelm"],
  ["envy", "shame"],
  ["fear", "overwhelm"],
  ["sadness", "numbness"],
  ["loneliness", "hope"],
  ["anger", "sadness"],
  ["shame", "loneliness"],
  ["overwhelm", "numbness"],
  ["fear", "sadness"],
  ["hope", "sadness"],
];

const ORIGINALS: { thoughtOriginal: string; inputLanguage: string }[] = [
  { thoughtOriginal: "Ne mogu prestati osvježavati portal kao da će me to spasiti.", inputLanguage: "hr" },
  { thoughtOriginal: "Me quedé sonriendo mientras presentaban mi trabajo como suyo.", inputLanguage: "es" },
  { thoughtOriginal: "J'ai dit que j'allais bien et ma voix a trahi la phrase.", inputLanguage: "fr" },
  { thoughtOriginal: "Ich habe wieder ja gesagt und fühle mich schon unsichtbar.", inputLanguage: "de" },
  { thoughtOriginal: "Tengo miedo de que el próximo review confirme que nunca fui suficiente.", inputLanguage: "es" },
  { thoughtOriginal: "Još uvijek ostavljam dvije čaše i pretvaram se da je to navika.", inputLanguage: "hr" },
  { thoughtOriginal: "Rileggo l'ultimo messaggio come se il tono si potesse dimostrare.", inputLanguage: "it" },
  { thoughtOriginal: "Je garde le message vocal parce que l'effacer serait une deuxième fin.", inputLanguage: "fr" },
  { thoughtOriginal: "Sigo traduciendo quién soy en habitaciones que no preguntaron.", inputLanguage: "es" },
  { thoughtOriginal: "Ich lache zu laut und spule es danach wie eine Regelverletzung zurück.", inputLanguage: "de" },
  { thoughtOriginal: "Čekam da mi netko potvrdi da smijem sjediti na toj stolici.", inputLanguage: "hr" },
  { thoughtOriginal: "Apro il saldo di nuovo, come se il numero potesse diventare più gentile.", inputLanguage: "it" },
  { thoughtOriginal: "Je range pour que ma poitrine accepte enfin de se taire.", inputLanguage: "fr" },
  { thoughtOriginal: "Sigo esperando un futuro que todavía no me ha escrito.", inputLanguage: "es" },
  { thoughtOriginal: "Imam osjećaj da sam gost u kući u kojoj sam naučio hodati.", inputLanguage: "hr" },
];

const STOIC: Array<(core: string) => string> = [
  (core) => `Name ${core} as a fact, not a trial. You do not have to retry the scene until it likes you.`,
  (core) => `The sting of ${core} is allowed. It does not get to appoint itself manager of the rest of the day.`,
  (core) => `Hold ${core} without adding a second story. What happened is enough; the verdict can wait.`,
  (core) => `You can carry ${core} and still put your feet on the next ordinary task. Endurance is not a performance.`,
  (core) => `${core} does not get a gavel. Mark it, breathe once, and return to what is actually in your hands.`,
  (core) => `Let ${core} be smaller than the whole afternoon. Facts fit in a sentence; spirals do not.`,
  (core) => `You survived ${core} already. The replay is optional unpaid labor. Set it down when the hour turns.`,
  (core) => `Stay with ${core} long enough to tell the truth, then stop decorating it. Clarity is a kind of mercy.`,
];

const OPTIMISTIC: Array<(core: string) => string> = [
  (core) => `${core} is a hard chapter, not the whole book. You still get a next page that is not this sting.`,
  (core) => `Nothing about ${core} cancels the person who noticed it. That noticing is already a kind of strength.`,
  (core) => `You can want more than ${core} without being ungrateful. Wanting is information, not a character flaw.`,
  (core) => `This moment around ${core} is loud, not final. Tomorrow still has room for a kinder move.`,
  (core) => `You found the words for ${core}. That means you are not stuck as a mute extra in your own life.`,
  (core) => `${core} hurts because you are paying attention. Attention can also pick the next small repair.`,
  (core) => `There is still a version of the day after ${core} where you are not only the wound. Leave a light on for it.`,
  (core) => `You do not have to believe in a grand arc yet. One honest next step after ${core} still counts as hope.`,
];

const HUMOROUS: Array<(core: string) => string> = [
  (core) => `${core} is not a personality. Put the phone down before it starts charging overtime for the spiral.`,
  (core) => `If ${core} were a coworker it would be on a performance plan. You do not have to keep it in the group chat.`,
  (core) => `Congratulations, your brain made a documentary about ${core} that nobody asked to stream. Credits can roll.`,
  (core) => `${core} would like a TED talk. Give it ninety seconds, then go drink water like a person with a body.`,
  (core) => `You are not a court. ${core} does not get unlimited closing arguments just because you are still awake.`,
  (core) => `Let ${core} sit in the cheap seats. Front row is for dinner, not for a thought that will not tip.`,
  (core) => `${core} is doing jazz hands in a quiet room. You can clap once and still leave at intermission.`,
  (core) => `Your inner narrator about ${core} needs an editor with a red pen and a bedtime. Fire the intern.`,
];

const TOUGH: Array<(core: string) => string> = [
  (core) => `Stop auditioning for ${core}. Do the next useful thing, even if it is small and unglamorous.`,
  (core) => `${core} is not paying rent in your head. Evict the replay and keep the fact. Then move.`,
  (core) => `You already know what ${core} costs. Quit romanticizing the loop and pick one adult action today.`,
  (core) => `Nobody is coming to reverse ${core} with a speech. Close the tab. Send the thing. Go to bed on time.`,
  (core) => `If ${core} is true, act like it. If it is a story, stop feeding it snacks at midnight.`,
  (core) => `You do not get extra credit for suffering ${core} beautifully. Choose the boring repair and do it twice.`,
  (core) => `Enough museum time with ${core}. Put the artifact down. Your life is not a guided tour of the wound.`,
  (core) => `${core} can be real and still not be the assignment. Do the assignment. Feelings can walk beside you.`,
];

function tagsFor(scene: Scene, category: Category, index: number): string[] {
  const extras = TAG_EXTRAS.filter((_, extraIndex) => (index + extraIndex) % 3 !== 0).slice(0, 3);
  const unique = [...new Set([category, ...scene.tags, ...extras])];
  return unique.slice(0, 8);
}

function resultsFor(core: string, index: number): { style: Style; reframe: string }[] {
  const pick = index % 8;
  return [
    { style: "stoic", reframe: STOIC[pick]!(core) },
    { style: "optimistic", reframe: OPTIMISTIC[pick]!(core) },
    { style: "humorous", reframe: HUMOROUS[pick]!(core) },
    { style: "tough_love", reframe: TOUGH[pick]!(core) },
  ];
}

export function buildCommunityFixture(): CommunityFixture {
  const users: CommunityUser[] = INITIALS.map((initials, index) => ({
    id: userId(index + 1),
    initials,
  }));

  const scenes = CATEGORIES.flatMap((category) =>
    SCENES[category].map((scene) => ({ category, scene })),
  );

  const posts: CommunityPost[] = scenes.map((item, index) => {
    assertCopy("thought", item.scene.thought, THOUGHT_MIN_WORDS, THOUGHT_MAX_WORDS, THOUGHT_MIN_CHARS, THOUGHT_MAX_CHARS);
    const results = resultsFor(item.scene.core, index);
    for (const result of results) {
      assertCopy(
        `${result.style} reframe`,
        result.reframe,
        REFRAME_MIN_WORDS,
        REFRAME_MAX_WORDS,
        REFRAME_MIN_CHARS,
        REFRAME_MAX_CHARS,
      );
    }
    const user = users[index % users.length]!;
    const intensity = ((index % 5) + 1) as 1 | 2 | 3 | 4 | 5;
    const emotions = EMOTION_PAIRS[index % EMOTION_PAIRS.length]!;
    const original = index % 18 === 0 ? ORIGINALS[Math.floor(index / 18) % ORIGINALS.length] : undefined;
    const created = new Date(Date.UTC(2026, 6, 1, 8, 0, 0) + index * 3 * 60 * 60 * 1000);
    const post: CommunityPost = {
      id: postId(index + 1),
      userId: user.id,
      createdAt: created.toISOString(),
      thought: item.scene.thought,
      inputLanguage: original?.inputLanguage ?? "en",
      category: item.category,
      tags: tagsFor(item.scene, item.category, index),
      intensity,
      intensityBand: intensityBand(intensity),
      timeframe: TIMEFRAMES[index % TIMEFRAMES.length]!,
      emotions,
      results,
      spotlightStyle: STYLES[index % STYLES.length]!,
    };
    if (original) {
      post.thoughtOriginal = original.thoughtOriginal;
    }
    if (post.userId === DEV_USER_ID) {
      throw new Error("seed post used DEV_USER_ID");
    }
    return post;
  });

  return { users, posts };
}
