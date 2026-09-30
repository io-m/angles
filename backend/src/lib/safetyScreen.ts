/**
 * A backstop under the decision call's safety judgment. Explicit or passive
 * self-harm phrasing that the model marked safe is treated as self-harm anyway:
 * a false alarm costs one crisis message, a miss ships a reframe.
 *
 * Only self-harm is screened. Harm to others and abuse lean on idioms too often
 * ("my boss will kill me") for a phrase list to help. Never log what matched.
 */

const NOT = "(?:don't|dont|do not|doesn't|does not|never)";

/** Leaves the phrase alone when the next whole word is one of `words`. */
const unlessNext = (words: string): string => `(?! (?:${words})(?![\\p{L}\\p{N}]))`;

/**
 * Written against normalised text: lowercase, diacritics stripped, one apostrophe,
 * single spaces. That turns Cyrillic й into и, ё into е, and ї into і; letters with
 * no decomposition (ł, ı, ø) are matched with and without the mark. Idioms like
 * "this deadline is killing me", "I'm dying of embarrassment", or "I wanted to die
 * when I tripped" must not match, in any language.
 *
 * Languages written without spaces between words need a different boundary rule
 * and are not listed; the model's English copy of a ready thought is screened too.
 */
const SELF_HARM_PHRASES: readonly string[] = [
  // English, explicit
  "kill(?:ing)? my ?self",
  "end(?:ing)? my (?:own )?life",
  "tak(?:e|ing) my (?:own )?life",
  "end(?:ing)? it all",
  "suicidal",
  "(?:commit(?:ting)?|attempt(?:ing|ed)?|thinking about|thoughts of|consider(?:ing)?) suicide",
  "self ?-?harm(?:ing)?",
  "(?:cutting|burning|hurting|harming|starving) my ?self",
  "(?:want|wanna|going|gonna|urge|urges|need) (?:to )?(?:hurt|harm|cut|burn|kill) my ?self",
  "cutting again",
  "(?:want|wanna|going|gonna|planning|thinking about) (?:to )?overdose",
  // English, passive
  `(?<!${NOT} )(?:want|wanna) (?:to )?die(?! (?:of|from|laughing|alone|old|happy|in|at|with|for|on))`,
  "wish(?:ed)? i (?:was|were|could be) dead",
  "better off dead",
  "better off without me",
  "(?:sleep|go to sleep) and (?:never|not) wake up",
  "wish i (?:would(?:n't| not)|could(?:n't| not)|did(?:n't| not)|wo(?:n't| not)|never) wake up",
  `${NOT} want to wake up`,
  `${NOT} want to (?:be alive|exist|live)(?! (?:here|in|with|near|there|alone|together|at|on|like|through|without|by|so|for))`,
  "(?:point|reason) (?:in|of|to) (?:being alive|living|live|stay(?:ing)? alive)(?! (?:in|here|there|with|near|on))",
  "no reason to go on",
  "(?:tired|sick) of (?:being alive|living)(?! (?:in|here|there|with|near|on|like))",
  // Croatian, Bosnian, Serbian
  "ubi(?:ti|t cu|cu) se",
  "(?:ne zelim|necu) (?:vise )?(?:zivjeti|ziveti|zivit|zivjet)(?! (?:ovdje|ovde|u|s|sa|kod|tamo|ovako|bez))",
  "zelim (?:umrijeti|umreti|umrit)",
  "samoubo?(?:jstv|istv)[a-z]*",
  "naudi(?:ti|t) sebi",
  // German
  "mich (?:selbst )?umbringen",
  "(?:selbstmord|suizid)[a-z]*",
  "(?:will|mochte) nicht mehr leben",
  "(?:will|mochte) sterben",
  "mir das leben nehmen",
  // Spanish
  "(?:suicidarme|suicidio|matarme|quitarme la vida)",
  "quiero morir(?:me)?",
  "no quiero (?:seguir )?vivir(?! (?:aqui|en|con|asi|sin|alli|solo|sola))",
  // Danish, Norwegian
  "sla mig selv ihjel",
  "selvmord[a-z]*",
  `vil ikke leve${unlessNext("(?:mere |lenger |mer )?(?:med|i|her|der|sammen|uden|uten|alene|slik|pa)")}`,
  `vil (?:gerne |gjerne )?d[øo]${unlessNext("af|av|i|med|pa")}`,
  `ta livet (?:mitt|av meg)${unlessNext("tilbake")}`,
  "drepe meg selv",
  "(?:vil|kommer til a) skade meg selv",
  "skader meg selv",
  "(?:aldri|ikke) vakne (?:igjen|mer)",
  "bedre (?:av )?uten meg",
  "ingen (?:grunn|mening) (?:til a|med a) leve",
  // French
  "me suicider",
  "suicidaires?",
  "(?:pense|pensais|penser|songe) au suicide",
  "mettre fin a (?:mes jours|ma vie)",
  "en finir avec (?:la|ma) vie",
  `(?:envie d'|veux |vais |voudrais )en finir${unlessNext("avec")}`,
  `(?:veux|vais|voudrais|envie de|pense a) me tuer${unlessNext("a|au|pour")}`,
  "(?:veux|vais|voudrais|envie de|besoin de) me faire du mal",
  "me scarifi\\p{L}*",
  `(?:veux|voudrais|envie de|aimerais) mourir${unlessNext("de|du|des")}(?! d')`,
  `(?:ne veux plus|n'ai plus envie de|plus envie de) vivre${unlessNext("ici|la|a|au|en|avec|comme|dans|sans|chez|ainsi|ca|cela")}`,
  `ne (?:plus jamais|jamais plus|jamais|plus) me reveiller${unlessNext("la nuit|a|avant|en|pendant|toutes")}`,
  "(?:seraient|serait|seront|sera|serais) mieux sans moi",
  "(?:serais|serait) mieux morte?",
  "(?:aucune|plus de|pas de|plus aucune) raison de vivre",
  // Portuguese
  "(?:me suicidar|suicidar me|suicidas?)",
  `(?:quero|vou|penso em|pensando em|vontade de) me matar${unlessNext("de")}`,
  `(?:quero|vou) matar me${unlessNext("de")}`,
  "tirar a (?:minha )?(?:propria )?vida",
  "acabar com a (?:minha )?vida",
  `quero morrer${unlessNext("de")}`,
  `nao quero (?:mais )?viver${unlessNext("aqui|em|no|na|com|assim|sem|la|so|sozinh\\p{L}*|isso")}`,
  "dormir e (?:nunca mais|nao) acordar",
  `nao quero (?:mais )?acordar${unlessNext("cedo|as|amanha|tarde")}`,
  "(?:estariam|estaria|ficariam|ficaria|estao|ficam) melhor(?:es)? sem mim",
  "(?:quero|vontade de|preciso) me (?:machucar|cortar|ferir)",
  "nao (?:ha|tem|vejo|existe) (?:mais )?(?:razao|motivo|sentido) (?:para|pra|de|em) viver",
  // Italian
  "suicid(?:io|armi|arsi|are|a|i)",
  `(?:uccidermi|ammazzarmi)${unlessNext("di|dal|dalla|per")}`,
  `mi voglio (?:uccidere|ammazzare|suicidare)${unlessNext("di|dal|dalla|per")}`,
  "togliermi la vita",
  "(?:voglio|vorrei|devo|ho bisogno di) farmi del male",
  "(?:voglio|vorrei) tagliarmi",
  `(?:voglio|vorrei) morire${unlessNext("di|dal|dalla|dalle|dai")}`,
  `non voglio (?:piu )?vivere${unlessNext("qui|in|con|cosi|senza|li|la|da|a")}`,
  "non (?:voglio )?svegliarmi (?:piu|mai piu)",
  "(?:dormire|addormentarmi) e non svegliarmi",
  "(?:starebbero|starebbe|staranno|stanno) meglio senza di me",
  "(?:nessun motivo|nessuna ragione) (?:per|di) vivere",
  // Dutch
  "zelfmoord\\p{L}*",
  "mezelf (?:van kant (?:te )?maken|ombrengen|om te brengen|doodmaken|iets aan(?:doen| te doen))",
  "mijn leven (?:te )?beeindigen",
  `wil (?:graag )?(?:dood|doodgaan|sterven)${unlessNext("van|aan")}`,
  `wil niet meer leven${unlessNext("in|met|hier|zo|zonder|daar|bij")}`,
  "(?:nooit|niet) meer wakker (?:worden|word)",
  "beter af zonder mij",
  "geen reden (?:meer )?om te leven",
  // Polish
  `(?:zabic|zabije|zabijam|zabi[lł]bym|zabi[lł]abym) sie${unlessNext("ze|z")}`,
  "sie (?:zabic|zabije|zabijam)",
  "samobojstw\\p{L}*",
  "samobojcz\\p{L}*",
  "odebrac sobie zycie",
  `chce umrzec${unlessNext("ze|z")}`,
  `nie chce (?:juz )?zyc${unlessNext("tu|tutaj|w|we|z|ze|tak|bez|tam|obok")}`,
  "zasnac i (?:sie )?(?:nie|nigdy nie|juz nie) obudzic",
  "nie chce sie (?:juz )?(?:obudzic|budzic)",
  "lepiej (?:im |wam |wszystkim )?beze mnie",
  "(?:chce|musze) (?:zrobic sobie krzywde|skrzywdzic (?:sie|siebie))",
  "nie (?:ma|widze) (?:juz )?sensu (?:zyc|zycia)",
  // Russian
  "(?:убить|убью|убиваю) себя",
  "поконч\\p{L}* с (?:собои|жизнью)",
  "самоубииств\\p{L}*",
  "суицид\\p{L}*",
  `(?:хочу|хочется|хотел бы|хотела бы) (?:умереть|сдохнуть)${unlessNext("от|со|с")}`,
  `не хочу (?:больше )?жить${unlessNext("здесь|тут|в|во|с|со|так|без|там|у")}`,
  `не хочу (?:больше )?просыпаться${unlessNext("рано|в|по")}`,
  "(?:уснуть|заснуть) и не проснуться",
  "(?:будет|было бы|всем|им) лучше без меня",
  "лучше бы я (?:умер|умерла|не родился|не родилась)",
  "(?:нет|не вижу) смысла (?:жить|в жизни)",
  "(?:причинить|причиняю) себе (?:вред|боль)",
  "(?:режу|резать|порезать|порежу) себя",
  "вскр\\p{L}* (?:себе )?вены",
  // Ukrainian
  "(?:вбити|вб['ʼ]?ю|вбиваю) себе",
  "покінч\\p{L}* (?:з|із) (?:собою|життям)",
  "самогубств\\p{L}*",
  "суіцид\\p{L}*",
  `(?:хочу|хочеться|хотів би|хотіла б) (?:померти|здохнути)${unlessNext("від|зі|з")}`,
  `не хочу (?:більше )?жити${unlessNext("тут|в|у|з|із|так|без|там")}`,
  "не хочу (?:більше )?прокидатися",
  "(?:заснути|уснути) і не прокинутися",
  "(?:буде|було б|всім|усім|ім) краще без мене",
  "(?:немає|не бачу) сенсу (?:жити|в житті)",
  "(?:заподіяти|завдати) собі (?:шкоди|шкоду|болю|біль)",
  // Turkish
  "kendimi oldur\\p{L}*",
  "intihar\\p{L}*",
  "can[ıi]ma k[ıi]y\\p{L}*",
  "(?:olmek|olup gitmek) isti\\p{L}*",
  "(?<!\\p{L}{2}(?:da|de|ta|te|la|le) )yasamak istemi\\p{L}*",
  "bir daha uyanma\\p{L}*",
  "uyanmak istemi\\p{L}*",
  "bensiz daha iyi\\p{L}*",
  "kendime zarar ver\\p{L}*",
  "yasamak icin (?:bir )?(?:sebep|sebeb|neden)\\p{L}* (?:yok|kalmad[ıi])",
  // Indonesian
  "bunuh diri",
  "(?:ingin|pengen|pingin|kepengen) mati",
  "mau mati (?:aja|saja)",
  "lebih baik (?:aku |saya )?mati",
  "(?:tidak|tak|gak|ga|nggak|enggak|ngga) (?:ingin|mau|pengen) hidup lagi",
  "mengakhiri hidup\\p{L}*",
  "melukai diri",
  "lebih baik tanpa(?:ku| aku| saya| diriku)",
  "tidur (?:dan|terus|lalu) (?:tidak|tak|gak|nggak|ga) (?:usah )?bangun lagi",
  "(?:tidak ada|gak ada|nggak ada) (?:alasan|gunanya) (?:untuk |buat )?hidup",
  // Swedish
  "sjalvmord\\p{L}*",
  "ta livet av mig",
  "(?:doda|dodar) mig sjalv",
  "(?:vill|kommer att) skada mig sjalv",
  "skadar mig sjalv",
  `vill do${unlessNext("av|pa|i|med")}`,
  `vill inte leva${unlessNext("(?:langre |mer )?(?:med|i|har|sa|utan|ensam|dar|pa)")}`,
  "(?:aldrig|inte) vakna (?:igen|mer)",
  "battre (?:av )?utan mig",
  "ingen (?:anledning|mening) (?:att|med att) leva",
];

const SCREEN = new RegExp(
  `(?<![\\p{L}\\p{N}])(?:${SELF_HARM_PHRASES.join("|")})(?![\\p{L}\\p{N}])`,
  "u",
);

export function normalizeForScreen(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/đ/g, "d")
    .replace(/[’‘`´]/g, "'")
    .replace(/[^\p{L}\p{N}'\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** True when any of the user's own words carry explicit or passive self-harm phrasing. */
export function screensAsSelfHarm(texts: readonly string[]): boolean {
  return texts.some((text) => SCREEN.test(normalizeForScreen(text)));
}
