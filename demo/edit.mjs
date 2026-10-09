// Edits one raw take into demo/output/final_9x16.mp4.
//
//   node demo/edit.mjs demo/raw/take-YYYYMMDD-HHMMSS [demo/themes/<name>.json]
//
// Cut (every video): hook, type, send, short cook, four style chapters, outro.
// The four chapters are the four styles the cook wrote (any four of the six). The last
// one gets extra hold + a small zoom. No fifth "best" chapter, no Post, no Home. Theme
// words are the hook and the end card.
//
// Maestro marks plus scene scores pick in-points. The yellow chapter title
// lands on the same timeline frame as the cut. Composition:
// demo/lib/composition.template.html. Footage is trimmed and sped up only.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEMO = dirname(fileURLToPath(import.meta.url));
const take = process.argv[2];
if (!take) {
  console.error("usage: node demo/edit.mjs <take-dir>");
  process.exit(2);
}

const HYPERFRAMES = "hyperframes@0.8.113";
const config = JSON.parse(readFileSync(join(DEMO, "edit.config.json"), "utf8"));
const themePath = process.argv[3] ?? (existsSync(join(take, "theme.json")) ? join(take, "theme.json") : join(DEMO, "themes", "lost-job.json"));
const theme = JSON.parse(readFileSync(themePath, "utf8"));
const result = JSON.parse(readFileSync(join(take, "result.json"), "utf8"));
const t0 = Number(readFileSync(join(take, "record_start_ms"), "utf8").trim());
const screen = join(take, "screen.mp4");
const project = join(DEMO, "video");
const media = join(project, "media");
const build = join(DEMO, "build");
const music = join(DEMO, "assets", "music.mp3");
const outDir = join(DEMO, "output");
const output = join(outDir, "final_9x16.mp4");
const FPS = 30;
const NAMES = { stoic: "STOIC", hopeful: "HOPEFUL", witty: "WITTY", tough: "TOUGH", tender: "TENDER", values: "VALUES" };
const NUMBERS = ["CHAPTER ONE", "CHAPTER TWO", "CHAPTER THREE", "CHAPTER FOUR"];

const log = (...args) => console.error("[edit]", ...args);
const round = (n) => Math.round(n * 1000) / 1000;

function run(cmd, args, options = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 256 * 1024 * 1024, ...options });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${args[0] ?? ""} failed:\n${((r.stderr || "") + (r.stdout || "")).slice(-4000)}`);
  }
  return r.stdout;
}

// ---------- marks ----------
const marks = {};
for (const [name, at] of result.marks) {
  marks[name] = (at - t0) / 1000;
}
const need = (name) => {
  if (marks[name] === undefined) {
    throw new Error(`mark ${name} missing from result.json`);
  }
  return marks[name];
};

// ---------- source geometry ----------
const probe = JSON.parse(
  run("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height:format=duration", "-of", "json", screen]),
);
const SRC_W = probe.streams[0].width;
const SRC_H = probe.streams[0].height;
const P = SRC_W / (config.screenWidthPt ?? 402);
const L = config.layoutPt;

/** Point bounds of the compose card in the final hierarchy. */
function cardFromHierarchy() {
  const path = join(take, "hierarchy.json");
  if (!existsSync(path)) {
    return null;
  }
  const root = JSON.parse(readFileSync(path, "utf8"));
  const parse = (b) => {
    const m = /\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]/.exec(b || "");
    return m ? { x0: +m[1], y0: +m[2], x1: +m[3], y1: +m[4] } : null;
  };
  const found = { chips: [], privacy: null, recook: null };
  const walk = (node, depth) => {
    const a = node.attributes || {};
    const b = parse(a.bounds);
    const id = a["resource-id"] || "";
    const text = a.accessibilityText || "";
    if (b && id.startsWith("chip.")) {
      found.chips.push({ depth, style: id.slice(5), ...b });
    }
    if (b && (text === "Public" || text === "Private") && (!found.privacy || b.x1 - b.x0 > found.privacy.x1 - found.privacy.x0)) {
      found.privacy = b;
    }
    if (b && /^New .+ answer$/.test(text)) {
      found.recook = b;
    }
    for (const child of node.children || []) {
      walk(child, depth + 1);
    }
  };
  walk(root, 0);
  // Home feed chips sit deeper in the tree than the compose card's.
  const minDepth = Math.min(...found.chips.map((c) => c.depth));
  const chips = found.chips.filter((c) => c.depth === minDepth);
  if (!chips.length || !found.privacy || !found.recook) {
    return null;
  }
  return {
    x0: Math.min(...chips.map((c) => c.x0)) - 14,
    x1: found.privacy.x1 + 14,
    y0: found.privacy.y0 - 14,
    y1: found.recook.y1 + 14,
    chipX0: Math.min(...chips.map((c) => c.x0)),
    // Left to right, as the card lays them out (the cook's own order).
    chipOrder: [...chips].sort((a, b) => a.x0 - b.x0).map((c) => c.style),
  };
}
// iPhone 17 Pro fallback, measured from a take.
const card = cardFromHierarchy() ?? { x0: 70, x1: 380, y0: 249, y1: 670, chipX0: 84, chipOrder: null };

// ---------- real change times ----------
function sceneScores(cropPx) {
  const filter = [
    cropPx ? `crop=${cropPx.w}:${cropPx.h}:${cropPx.x}:${cropPx.y}` : null,
    "scale=160:-2",
    "select='gt(scene,0.004)'",
    "metadata=print:file=-",
  ].filter(Boolean).join(",");
  const text = run("ffmpeg", ["-v", "error", "-i", screen, "-vf", filter, "-an", "-f", "null", "-"]);
  const points = [];
  let time = null;
  for (const line of text.split("\n")) {
    const t = /pts_time:([\d.]+)/.exec(line);
    if (t) {
      time = Number(t[1]);
      continue;
    }
    const s = /lavfi\.scene_score=([\d.]+)/.exec(line);
    if (s && time !== null) {
      points.push({ t: time, s: Number(s[1]) });
      time = null;
    }
  }
  return points;
}
const even = (n) => Math.round(n / 2) * 2;
const fullScores = sceneScores(null);
const cardScores = sceneScores({
  x: Math.round(card.x0 * P),
  y: Math.round(card.y0 * P),
  w: even((card.x1 - card.x0) * P),
  h: even((card.y1 - card.y0) * P),
});

function firstChange(scores, from, to, minScore) {
  return scores.find((p) => p.t >= from && p.t <= to && p.s >= minScore)?.t ?? null;
}
function biggestChange(scores, from, to) {
  let best = null;
  for (const p of scores) {
    if (p.t >= from && p.t <= to && (!best || p.s > best.s)) {
      best = p;
    }
  }
  return best?.t ?? null;
}

const composeOpen = biggestChange(fullScores, need("flow_start") - 0.5, need("keyboard_up") + 0.5) ?? need("compose_tap");
const typeFirst = firstChange(fullScores, need("type_start") - 0.2, need("type_end") + 1, 0.006) ?? need("type_start");
const sendAt = biggestChange(fullScores, need("send"), need("send") + 4) ?? need("send") + 1;
const followupMarks = Object.keys(marks).filter((k) => /^followup_\d+$/.test(k));
let followupAnswerAt = null;
if (followupMarks.length) {
  followupAnswerAt = firstChange(fullScores, need("followup_answer"), need("followup_answer") + 4, 0.006) ?? need("followup_answer") + 1;
}
const cookFrom = (followupAnswerAt ?? sendAt) + 0.6;
const cardMark = need("card");
const cardScene =
  firstChange(cardScores, cookFrom + 0.4, cardMark + 0.5, 0.03)
  ?? biggestChange(cardScores, cookFrom + 0.4, cardMark + 0.5);
// Cut as soon as the card is on screen so the first chapter overlay is not waiting on settle.
const cardAt = cardScene ?? cardMark;

// The order the flow tapped the chips in (by when each answer showed); the card opened on firstStyle.
const tapOrder = Object.keys(NAMES)
  .filter((style) => marks[`shown_${style}`] !== undefined)
  .sort((a, b) => marks[`shown_${a}`] - marks[`shown_${b}`]);
const firstStyle = result.firstStyle && NAMES[result.firstStyle] ? result.firstStyle : null;
if (!firstStyle) {
  throw new Error("result.json has no firstStyle; the flow could not read which style the card opened on");
}
const chipAt = {};
for (const style of tapOrder) {
  chipAt[style] = need(`shown_${style}`) - 0.12;
}

/** Center of a chip in points, given which chip was selected (and so wide) at the time. */
const CHIP_ORDER = card.chipOrder ?? [firstStyle, ...tapOrder];
function chipCenter(style, selected) {
  let x = card.chipX0 + 2;
  for (const s of CHIP_ORDER) {
    const w = s === selected ? L.chipPill[s] : L.chipCircle;
    if (s === style) {
      return { x: x + w / 2, y: L.chipRowY };
    }
    x += w + L.chipGap;
  }
  throw new Error(`unknown style ${style}`);
}

// ---------- the hook and end card, laid out from the theme ----------
const ANTON = JSON.parse(readFileSync(join(DEMO, "lib", "anton-widths.json"), "utf8"));
const escapeHtml = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const upper = (s) => s.toLocaleUpperCase("en-US");
/** Rendered width of uppercase Anton text, in em, including letter-spacing. */
function textEm(text, spacingEm) {
  return [...text].reduce((w, c) => w + (ANTON.advance[c] ?? 0.5) + spacingEm, 0);
}
/** The largest font size up to `max` at which `text` fits in `width` pixels. */
const fitSize = (text, max, width, spacingEm) => Math.min(max, Math.floor(width / textEm(text, spacingEm)));

const LOOKS = { big: 300, slam: 300, small: 168 };
const HOOK_CENTER_Y = 860;
const gapBetween = (a, b) => (a.look !== "small" && b.look !== "small" ? 10 : a.look !== "small" ? 30 : 22);
if (!Array.isArray(theme.hook) || !theme.hook.length || theme.hook.some((card) => !card.length)) {
  throw new Error(`${themePath}: hook must be a list of cards, each a list of lines`);
}
let beatAt = 0.1;
const hookCards = theme.hook.map((card, ci) => {
  if (ci > 0) {
    beatAt += 0.15;
  }
  const lines = card.map((line, li) => {
    if (!LOOKS[line.look]) {
      throw new Error(`${themePath}: hook line "${line.text}" has look "${line.look}"; use big, small, or slam`);
    }
    const text = upper(line.text);
    const size = fitSize(text, LOOKS[line.look], 940, 0.01);
    const at = round(beatAt);
    beatAt += 0.45;
    return { id: `hk-${ci}-${li}`, text, look: line.look, size, at };
  });
  const height = lines.reduce((h, l, i) => h + l.size + (i ? gapBetween(lines[i - 1], l) : 0), 0);
  let top = Math.round(HOOK_CENTER_Y - height / 2);
  lines.forEach((l, i) => {
    top += i ? lines[i - 1].size + gapBetween(lines[i - 1], l) : 0;
    l.top = top;
  });
  return lines;
});
const TH = round(beatAt + 0.25);
const hookTags = hookCards.flat().map((l) =>
  `<div id="${l.id}" class="hk ${l.look}" data-layout-allow-overlap style="top: ${l.top}px; font-size: ${l.size}px">${escapeHtml(l.text)}</div>`);

const end = theme.end ?? {};
const endText = {
  wordmark: upper(end.wordmark ?? "Angles"),
  tagline: upper(end.tagline ?? "One thought. Four ways to see it."),
  badge: upper(end.badge ?? "Coming soon to the App Store"),
  follow: upper(end.follow ?? "Follow for more"),
};
const endSize = {
  wordmark: fitSize(endText.wordmark, 250, 940, 0.02),
  tagline: fitSize(endText.tagline, 60, 940, 0.04),
  badge: fitSize(endText.badge, 52, 700, 0.04),
  follow: fitSize(`${endText.follow} →`, 64, 900, 0.08),
};

// ---------- the cut ----------
const shots = [];
let cursor = TH;
const beats = [{ name: "hook", outStart: 0, outEnd: TH }];
function shot(name, mediaStart, timelineDur, rate = 1) {
  if (timelineDur <= 0.05) {
    return null;
  }
  const s = { name, at: round(cursor), mediaStart: round(mediaStart), dur: round(timelineDur), rate: round(rate) };
  shots.push(s);
  beats.push({ name, outStart: s.at, outEnd: round(cursor + timelineDur), speed: rate, source: [s.mediaStart, round(mediaStart + timelineDur * rate)] });
  cursor += timelineDur;
  return s;
}

const typingStart = Math.max(composeOpen + 0.5, typeFirst - 0.5);
const typingRaw = sendAt - 0.35 - typingStart;
const typingRate = Math.min(config.typingMaxSpeed, Math.max(1, typingRaw / config.typingOutSeconds));
shot("typing", typingStart, typingRaw / typingRate, typingRate);
const sendShot = shot("send", sendAt - 0.35, 0.95);

function cooking(name, from, to) {
  const rate = config.cookingSpeed;
  const raw = to - from;
  if (raw / rate <= config.cookingMaxOutSeconds) {
    shot(name, from, raw / rate, rate);
    return;
  }
  const headOut = config.cookingMaxOutSeconds * 0.4;
  const tailOut = config.cookingMaxOutSeconds - headOut;
  shot(`${name}-head`, from, headOut, rate);
  shot(`${name}-tail`, to - tailOut * rate, tailOut, rate);
}
let followupShot = null;
if (followupAnswerAt !== null) {
  const questionAt = firstChange(fullScores, sendAt + 0.6, need("followup_1") + 0.5, 0.01) ?? need("followup_1");
  cooking("decision", sendAt + 0.6, questionAt);
  followupShot = shot("followup", questionAt, followupAnswerAt + 0.6 - questionAt);
  cooking("cooking", followupAnswerAt + 0.6, cardAt);
} else {
  cooking("cooking", sendAt + 0.6, cardAt);
}

const rest = tapOrder.filter((s) => s !== firstStyle && chipAt[s] !== undefined);
const angleSeconds = config.angleSeconds ?? config.chipSeconds ?? config.firstAnswerSeconds;
const lastExtra = config.lastAngleExtraSeconds ?? 2;
const [minTotal, maxTotal] = config.targetTotalSeconds;

function angleChapter(name, mediaStart, style, tap, dur) {
  const s = shot(name, mediaStart, dur);
  return { style, shot: s, changeAt: s.at, tap };
}

const arrival = angleChapter(`chapter-${firstStyle}`, cardAt, firstStyle, null, angleSeconds);
const angleShots = [arrival];
for (let i = 0; i < rest.length; i++) {
  const style = rest[i];
  const isLast = i === rest.length - 1;
  const before = i === 0 ? firstStyle : rest[i - 1];
  const dur = isLast ? angleSeconds + lastExtra : angleSeconds;
  angleShots.push(angleChapter(`chapter-${style}`, chipAt[style], style, chipCenter(style, before), dur));
}
if (angleShots.length !== 4) {
  throw new Error(`the cut needs exactly four style chapters; this take has ${angleShots.length} (${angleShots.map((a) => a.style).join(", ")}). Record another take.`);
}
const lastShot = angleShots[angleShots.length - 1];

const appEnd = round(cursor);
const total = round(appEnd + 0.45 + config.endCardSeconds);
beats.push({ name: "end", outStart: appEnd, outEnd: total });
if (total < minTotal || total > maxTotal) {
  throw new Error(`edit would be ${total.toFixed(2)} s; expected ${minTotal}-${maxTotal} s. Adjust demo/edit.config.json.`);
}

// ---------- composition data ----------
const C = config.camera;
const px = (pt) => round(pt * P);
const cardMidY = (card.y0 + card.y1) / 2;
const cam = {
  wide: { sx: SRC_W / 2, sy: SRC_H / 2, S: 1, ly: 980 },
  compose: { sx: SRC_W / 2, sy: px(L.composer.y), S: C.composeScale, ly: 1010 },
  cook: { sx: SRC_W / 2, sy: px(L.bubble.y), S: C.cookScale, ly: 760 },
  // A little right of the screen's middle, so the answer stays clear of TikTok's right rail.
  card: { sx: px(C.cardCenterXPt), sy: px(cardMidY), S: C.cardScale, ly: 1075 },
  best: { sx: px(C.cardCenterXPt + 2), sy: px(cardMidY), S: C.bestScale, ly: 1060 },
};
const lastDur = lastShot.shot.dur;
const moves = [
  { at: round(TH + 0.55), key: "compose", dur: 2.2, ease: "power2.inOut" },
  { at: round(sendShot.at + 0.35), key: "cook", dur: 0.7, ease: "power3.inOut" },
  { at: round(arrival.changeAt), key: "card", dur: 0.45, ease: "power3.out" },
  { at: round(lastShot.changeAt), key: "best", dur: round(Math.max(0.8, lastDur - 0.2)), ease: "sine.inOut" },
];
if (followupShot) {
  moves.splice(2, 0, { at: followupShot.at, key: "compose", dur: 0.6, ease: "power3.inOut" });
}

const taps = [{ id: "tap-send", at: round(sendShot.at + 0.15), x: px(L.send.x), y: px(L.send.y) }];
for (const a of angleShots) {
  if (a.tap) {
    taps.push({ id: `tap-${a.style}`, at: round(a.shot.at - 0.06), x: px(a.tap.x), y: px(a.tap.y) });
  }
}
const chapters = angleShots.map((a, i) => ({
  at: round(a.changeAt),
  num: NUMBERS[i] ?? "",
  name: NAMES[a.style],
  note: null,
  noteAfter: 0,
}));
const data = {
  source: { width: SRC_W, height: SRC_H },
  cornerPx: px(L.screenCorner),
  hook: { cards: hookCards.map((card) => card.map(({ id, look, at }) => ({ id, look, at }))) },
  hookOut: TH,
  cam,
  moves,
  taps,
  punches: chapters.slice(1).map((c) => c.at),
  chapters,
  appEnd,
};

// ---------- write the composition ----------
mkdirSync(media, { recursive: true });
mkdirSync(build, { recursive: true });
mkdirSync(outDir, { recursive: true });

// HyperFrames seeks a constant-frame-rate copy. simctl's file is variable-rate and stops at the last
// change, so the last frame is held for the best-answer hold.
const cfr = join(media, "screen.mp4");
const stamp = join(media, "screen.source");
if (!existsSync(cfr) || !existsSync(stamp) || readFileSync(stamp, "utf8") !== `${screen}:${statSync(screen).mtimeMs}`) {
  log("making a constant-frame-rate copy of the take");
  run("ffmpeg", [
    "-y", "-v", "error", "-i", screen,
    "-vf", `fps=${FPS},tpad=stop_mode=clone:stop_duration=20,format=yuv420p`,
    "-c:v", "libx264", "-preset", "fast", "-crf", "12", "-g", "15", "-an", cfr,
  ]);
  writeFileSync(stamp, `${screen}:${statSync(screen).mtimeMs}`);
}

const shotTags = shots.map((s, i) => `<video id="shot-${i}" class="clip shot" src="media/screen.mp4" data-start="${s.at}" data-duration="${s.dur}" data-media-start="${s.mediaStart}" data-playback-rate="${s.rate}" data-track-index="0" muted playsinline></video>`);
const tapTags = taps.map((t) => `<div id="${t.id}" class="tap" style="left: ${t.x}px; top: ${t.y}px"><div class="dot"></div><div class="ring"></div><div class="ring"></div></div>`);
// Anton's line boxes are taller than its caps, so stacked lines touch boxes without touching ink.
const chapterTags = chapters.map((c, i) => `<div id="chapter-${i}" class="chapter"><span class="num" data-layout-allow-overlap>${c.num}</span><span class="name" data-layout-allow-overlap>${c.name}</span>${c.note ? `<span class="note" data-layout-allow-overlap style="font-size: ${fitSize(c.note, 52, 860, 0.06)}px">${escapeHtml(c.note)}</span>` : ""}</div>`);
const shrunk = [
  ...hookCards.flat().map((l) => [l.text, l.size, LOOKS[l.look]]),
  ...Object.keys(endText).map((k) => [endText[k], endSize[k], { wordmark: 250, tagline: 60, badge: 52, follow: 64 }[k]]),
  ...chapters.filter((c) => c.note).map((c) => [c.note, fitSize(c.note, 52, 860, 0.06), 52]),
].filter(([, size, max]) => size < max * 0.7);
for (const [text, size, max] of shrunk) {
  log(`warning: "${text}" had to shrink to ${size}px (from ${max}px) to fit; a shorter line reads bigger`);
}
const template = readFileSync(join(DEMO, "lib", "composition.template.html"), "utf8");
const html = template
  .replace("__DURATION__", String(total))
  .replace("<!--SHOTS-->", shotTags.join("\n                  "))
  .replace("<!--TAPS-->", tapTags.join("\n                  "))
  .replace("<!--CHAPTERS-->", chapterTags.join("\n        "))
  .replace("<!--HOOK-->", hookTags.join("\n          "))
  .replace(/__(WORDMARK|TAGLINE|BADGE|FOLLOW)(_SIZE)?__/g, (_, key, size) =>
    size ? String(endSize[key.toLowerCase()]) : escapeHtml(endText[key.toLowerCase()]))
  .replace("/*DEMO_DATA*/", JSON.stringify(data));
writeFileSync(join(project, "index.html"), html);
log(`shots: ${shots.map((s) => `${s.name} ${s.mediaStart}+${round(s.dur * s.rate)}${s.rate !== 1 ? ` @${s.rate}x` : ""}`).join(" | ")}`);

if (process.env.EDIT_ONLY === "1") {
  log("EDIT_ONLY=1: wrote demo/video/index.html, skipping render");
  process.exit(0);
}

// ---------- render and encode ----------
log("checking the composition");
const check = spawnSync("npx", ["--yes", HYPERFRAMES, "check"], { cwd: project, encoding: "utf8", env: { ...process.env, HYPERFRAMES_SKIP_SKILLS: "1" } });
const checkText = `${check.stdout}\n${check.stderr}`;
writeFileSync(join(build, "check.txt"), checkText);
if (check.status !== 0) {
  throw new Error(`hyperframes check failed (see demo/build/check.txt):\n${checkText.slice(-3000)}`);
}

const picture = join(build, "picture.mp4");
const rendered = join(build, "composition.html");
if (existsSync(picture) && existsSync(rendered) && readFileSync(rendered, "utf8") === html) {
  log("composition unchanged; reusing demo/build/picture.mp4");
} else {
  log("rendering with HyperFrames");
  run("npx", ["--yes", HYPERFRAMES, "render", "-o", picture, "--fps", String(FPS), "--quality", "high", "--video-frame-format", "png"], {
    cwd: project,
    env: { ...process.env, HYPERFRAMES_SKIP_SKILLS: "1" },
  });
  writeFileSync(rendered, html);
}

// Sound effects are synthesized here (no downloaded audio): a thump per hook slam, a whoosh into
// the app and into the end card, a click per tap, a hit per chapter card.
const SFX = {
  thump: { d: 0.6, expr: "0.9*sin(2*PI*(42+120*exp(-t*26))*t)*exp(-t*6.5)" },
  slam: { d: 0.9, expr: "sin(2*PI*(38+150*exp(-t*22))*t)*exp(-t*4.5)+0.35*(2*random(0)-1)*exp(-t*30)" },
  hit: { d: 0.5, expr: "0.6*sin(2*PI*(60+150*exp(-t*32))*t)*exp(-t*9)+0.22*(2*random(0)-1)*exp(-t*45)" },
  click: { d: 0.12, expr: "0.45*sin(2*PI*2300*t)*exp(-t*95)+0.3*sin(2*PI*950*t)*exp(-t*55)" },
  whoosh: { d: 0.6, expr: "0.55*(2*random(0)-1)*pow(sin(PI*t/0.6),3)", after: "highpass=f=350,lowpass=f=3800" },
};
const hookBeats = hookCards.flat().map((l) => l.at);
const cues = [
  ...hookBeats.slice(0, -1).map((at) => ["thump", at]),
  ["slam", hookBeats[hookBeats.length - 1]],
  ["whoosh", TH - 0.25],
  ...taps.map((t) => ["click", t.at]),
  ...chapters.map((c) => ["hit", c.at]),
  ["whoosh", appEnd - 0.2],
  ["slam", appEnd + 0.85],
  ["click", appEnd + 1.6],
  ["click", appEnd + 2.0],
];
const sfxChains = cues.map(([kind, at], i) => {
  const s = SFX[kind];
  const ms = Math.max(0, Math.round(at * 1000));
  return `aevalsrc='${s.expr}':s=48000:c=stereo:d=${s.d}${s.after ? `,${s.after}` : ""},adelay=${ms}:all=1[s${i}]`;
});
const sfxMix = `${cues.map((_, i) => `[s${i}]`).join("")}amix=inputs=${cues.length}:normalize=0:duration=longest,apad,atrim=0:${total}[sfx]`;

const hasMusic = existsSync(music);
const audioIn = hasMusic ? ["-stream_loop", "-1", "-i", music] : [];
const audioFilter = hasMusic
  ? `[1:a]atrim=0:${total},asetpts=PTS-STARTPTS,volume=${config.musicVolume},afade=t=in:st=0:d=0.4,afade=t=out:st=${round(total - 1.5)}:d=1.5,aresample=48000[music];[sfx]volume=0.7[sfxq];[music][sfxq]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.7:level=false[aout]`
  : `[sfx]volume=0.7,alimiter=limit=0.7:level=false[aout]`;
run("ffmpeg", [
  "-y", "-v", "error",
  "-i", picture, ...audioIn,
  "-filter_complex", `[0:v]fps=${FPS},format=yuv420p,setsar=1[vout];${sfxChains.join(";")};${sfxMix};${audioFilter}`,
  "-map", "[vout]", "-map", "[aout]",
  "-t", String(total),
  "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", String(FPS),
  "-c:a", "aac", "-b:a", "160k", "-ar", "48000",
  "-movflags", "+faststart",
  output,
]);

writeFileSync(
  join(outDir, "edl.json"),
  `${JSON.stringify({ take, total, music: hasMusic, source: { width: SRC_W, height: SRC_H }, events: { composeOpen, typeFirst, sendAt, followupAnswerAt, cardAt, chipAt }, timeline: beats, composition: data, sfx: cues }, null, 2)}\n`,
);
log(`wrote ${output} (${total.toFixed(2)} s, music: ${hasMusic ? "yes" : "no"})`);
