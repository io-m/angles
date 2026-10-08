// Compose the App Store frames and the 886×1920 preview from one store take.
//
//   node demo/store_edit.mjs store/raw/take-…
//
// Screenshots are full-bleed app UI under a yellow Anton headline. The preview
// is the same recording, cut so the first angle is on screen at 5 seconds
// (Apple's default poster) and the whole piece stays between 15 and 30 seconds.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { layoutStoreCards, renderStoreEnd, renderStoreHook } from "./lib/storePreviewHook.mjs";

const DEMO = join(dirname(fileURLToPath(import.meta.url)));
const ROOT = join(DEMO, "..");
const STORE = join(ROOT, "store");
const take = process.argv[2];
if (!take) {
  console.error("usage: node demo/store_edit.mjs <take-dir>");
  process.exit(2);
}

const W = 1320;
const H = 2868;
const BAND = 420;
const STATUS = 186;
const PREVIEW_W = 886;
const PREVIEW_H = 1920;
/** Trim sim rounded-corner matte before scaling (cropdetect on store takes). */
const PREVIEW_SRC_CROP = { w: 1312, h: 2864, x: 4, y: 2 };
/** Inset so Connect’s device preview mask does not clip the status bar. */
const PREVIEW_SAFE_PAD = 28;
const FPS = 30;
const PAPER = "0x151413";
const YELLOW = "0xFFD21F";

const NAMES = {
  stoic: "STOIC",
  optimistic: "OPTIMISTIC",
  humorous: "HUMOROUS",
  tough_love: "TOUGH LOVE",
};
const STYLE_FILES = {
  stoic: "style-stoic.png",
  optimistic: "style-optimistic.png",
  humorous: "style-humorous.png",
  tough_love: "style-tough-love.png",
};

function log(message) {
  console.error(`[store_edit] ${message}`);
}
function run(cmd, args) {
  const result = spawnSync(cmd, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")}\n${result.stderr || result.stdout}`);
  }
  return result.stdout;
}
function probe(file) {
  const raw = run("ffprobe", [
    "-v", "error",
    "-select_streams", "v:0",
    "-show_entries", "stream=width,height,duration",
    "-of", "json",
    file,
  ]);
  return JSON.parse(raw).streams[0];
}

const ANTON = JSON.parse(readFileSync(join(DEMO, "lib", "anton-widths.json"), "utf8"));
function textEm(text) {
  return [...text].reduce((width, char) => width + (ANTON.advance[char] ?? 0.55), 0);
}
function fitSize(text, max, width) {
  const em = textEm(text);
  if (em <= 0) return max;
  return Math.max(40, Math.min(max, Math.floor(width / em)));
}

function ensureFont() {
  const ttf = join(STORE, ".tools", "Anton-Regular.ttf");
  if (existsSync(ttf)) return ttf;
  mkdirSync(dirname(ttf), { recursive: true });
  const py = join(STORE, ".tools");
  if (!existsSync(join(py, "fontTools", "__init__.py")) && !existsSync(join(py, "fonttools"))) {
    log("installing fonttools to decode Anton");
    run("python3", ["-m", "pip", "install", "--target", py, "fonttools", "brotli"]);
  }
  const script = `
import sys
sys.path.insert(0, ${JSON.stringify(py)})
from fontTools.ttLib import TTFont
font = TTFont(${JSON.stringify(join(DEMO, "video", "fonts", "Anton-Regular.woff2"))})
font.flavor = None
font.save(${JSON.stringify(ttf)})
`;
  run("python3", ["-c", script]);
  return ttf;
}

function ffPath(path) {
  return path.replace(/\\/g, "\\\\").replace(/:/g, "\\:").replace(/'/g, "\\'");
}

function renderPng(kind, spec, outPath) {
  const tools = join(STORE, ".tools");
  mkdirSync(tools, { recursive: true });
  if (!existsSync(join(tools, "PIL", "__init__.py"))) {
    log("installing pillow");
    run("python3", ["-m", "pip", "install", "--target", tools, "pillow"]);
  }
  const script = `
import sys
sys.path.insert(0, ${JSON.stringify(tools)})
from PIL import Image, ImageDraw, ImageFont
spec = ${JSON.stringify(spec)}
font_path = ${JSON.stringify(join(tools, "Anton-Regular.ttf"))}
kind = ${JSON.stringify(kind)}
out = ${JSON.stringify(outPath)}

def fit(text, max_size, width):
    size = max_size
    while size > 36:
        font = ImageFont.truetype(font_path, size)
        if font.getlength(text) <= width:
            return font
        size -= 2
    return ImageFont.truetype(font_path, 36)

if kind == "band":
    w, h = spec["width"], spec["height"]
    img = Image.new("RGB", (w, h), (0x15, 0x14, 0x13))
    draw = ImageDraw.Draw(img)
    fonts = [fit(line, 128, w - 140) for line in spec["lines"]]
    gap = 16
    block = sum(font.size for font in fonts) + gap * (len(fonts) - 1)
    y = max(24, (h - block) // 2 - 10)
    for line, font in zip(spec["lines"], fonts):
        tw = font.getlength(line)
        draw.text(((w - tw) / 2, y), line, font=font, fill=(0xFF, 0xD2, 0x1F))
        y += font.size + gap
    draw.rectangle([80, h - 28, w - 80, h - 24], fill=(0xFF, 0xD2, 0x1F))
    img.save(out)
elif kind == "chapter":
    w, h = spec.get("width", 886), spec.get("height", 1920)
    # Same header scrim as demo/lib/composition.template.html #scrim (620px @ 1920).
    scrim_h = int(h * 620 / 1920)
    paper = (10, 9, 8)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for row in range(scrim_h):
        t = row / max(1, scrim_h - 1)
        if t <= 0.62:
            a = 0.94 - (0.14 * t / 0.62)
        else:
            a = 0.8 * (1.0 - (t - 0.62) / 0.38)
        a = max(0.0, min(1.0, a))
        draw.line([(0, row), (w, row)], fill=(*paper, int(255 * a)))
    font = fit(spec["text"], spec.get("max", 118), spec.get("maxWidth", w - 60))
    tw = font.getlength(spec["text"])
    y = spec.get("y", 168)
    tx = (w - tw) / 2
    draw.text((tx, y), spec["text"], font=font, fill=(0xFF, 0xD2, 0x1F, 255))
    img.save(out)
else:
    font = fit(spec["text"], spec.get("max", 52), spec.get("maxWidth", 780))
    pad_x, pad_y = 28, 14
    tw = font.getlength(spec["text"])
    w = int(tw + pad_x * 2)
    h = int(font.size + pad_y * 2)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, w - 1, h - 1], radius=h // 2, fill=(0x15, 0x14, 0x13, 214))
    draw.text((pad_x, pad_y - 6), spec["text"], font=font, fill=(0xFF, 0xD2, 0x1F, 255))
    img.save(out)
`;
  run("python3", ["-c", script]);
}
function composeShot(rawPath, lines, outPath, cropTop) {
  const info = probe(rawPath);
  if (info.width !== W || info.height !== H) {
    throw new Error(`${rawPath} is ${info.width}×${info.height}, expected ${W}×${H}`);
  }
  const uiH = H - BAND;
  if (cropTop + uiH > H) {
    throw new Error(`crop ${cropTop}+${uiH} exceeds ${H}`);
  }
  const band = outPath.replace(/\.png$/, ".band.png");
  renderPng("band", { lines, width: W, height: BAND }, band);
  run("ffmpeg", [
    "-y", "-v", "error",
    "-i", rawPath,
    "-i", band,
    "-filter_complex",
    `[0:v]format=rgb24,crop=${W}:${uiH}:0:${cropTop},pad=${W}:${H}:0:${BAND}:color=${PAPER}[base];[1:v]format=rgb24[band];[base][band]overlay=0:0,format=rgb24`,
    "-frames:v", "1",
    outPath,
  ]);
}

function shotFile(name) {
  const path = join(take, "shots", name);
  if (!existsSync(path)) {
    throw new Error(`missing screenshot ${path}`);
  }
  return path;
}

/** simctl recordVideo frames lag Maestro wall-clock marks on store sims (~2.4s). */
const SIMCTL_VIDEO_LAG_MS = 2400;

function takeMarks(result) {
  const t0 = Number(readFileSync(join(take, "record_start_ms"), "utf8").trim()) + SIMCTL_VIDEO_LAG_MS;
  const marks = {};
  for (const [name, at] of result.marks ?? []) {
    marks[name] = (at - t0) / 1000;
  }
  const need = (name) => {
    if (marks[name] === undefined) throw new Error(`mark ${name} missing from result.json`);
    return marks[name];
  };
  return { marks, need };
}

function chapterOrder(result, marks) {
  const firstStyle = result.firstStyle && NAMES[result.firstStyle] ? result.firstStyle : "stoic";
  const tapOrder = ["optimistic", "humorous", "stoic", "tough_love"];
  const rest = tapOrder.filter((style) => style !== firstStyle && marks[`shown_${style}`] !== undefined);
  return [firstStyle, ...rest];
}

function buildFrames(font) {
  const result = JSON.parse(readFileSync(join(take, "result.json"), "utf8"));
  const first = result.firstStyle && NAMES[result.firstStyle] ? result.firstStyle : "stoic";
  const initial = existsSync(join(take, "shots", "style-initial.png"))
    ? shotFile("style-initial.png")
    : shotFile(`style-${first.replace("_", "-")}.png`);
  const frames = [
    { raw: initial, lines: ["FOUR WAYS", "TO SEE IT."], out: "01-four-ways.png", cropTop: 320 },
    { raw: shotFile("composer.png"), lines: ["WRITE THE", "HARD THOUGHT."], out: "02-write.png", cropTop: 300 },
    { raw: shotFile("style-humorous.png"), lines: ["SAME THOUGHT.", "DIFFERENT VOICE."], out: "03-voice.png", cropTop: 320 },
    { raw: shotFile("style-optimistic.png"), lines: ["STILL", "POSSIBLE."], out: "04-possible.png", cropTop: 320 },
    { raw: shotFile("style-tough-love.png"), lines: ["KEEP THE ONE", "THAT FITS."], out: "05-keep.png", cropTop: 320 },
  ];
  mkdirSync(STORE, { recursive: true });
  for (const frame of frames) {
    const out = join(STORE, frame.out);
    log(`frame ${frame.out}`);
    composeShot(frame.raw, frame.lines, out, frame.cropTop);
  }
  const paywall = join(take, "shots", "paywall.png");
  if (existsSync(paywall)) {
    run("ffmpeg", ["-y", "-v", "error", "-i", paywall, "-frames:v", "1", "-pix_fmt", "rgb24", join(STORE, "paywall.png")]);
    log("copied paywall");
  } else {
    log("no simulator paywall; phone capture still open");
  }
  run("ffmpeg", [
    "-y", "-v", "error",
    ...frames.flatMap((frame) => ["-i", join(STORE, frame.out)]),
    "-filter_complex", `${frames.map((_, i) => `[${i}:v]scale=220:-1[s${i}]`).join(";")};${frames.map((_, i) => `[s${i}]`).join("")}hstack=inputs=${frames.length}`,
    "-frames:v", "1",
    join(STORE, "contact.png"),
  ]);
  return result;
}

function ensureCfr() {
  const tools = join(STORE, ".tools");
  mkdirSync(tools, { recursive: true });
  const screenRaw = join(take, "screen.mp4");
  const screen = join(tools, "cfr-screen.mp4");
  const stamp = `${screen}.stamp`;
  const token = `${take}\n${statSync(screenRaw).mtimeMs}`;
  if (!(existsSync(screen) && existsSync(stamp) && readFileSync(stamp, "utf8") === token)) {
    log(`CFR ${screen}`);
    run("ffmpeg", [
      "-y", "-v", "error", "-i", screenRaw,
      "-vf", `fps=${FPS},format=yuv420p`,
      "-c:v", "libx264", "-preset", "veryfast", "-crf", "16", "-g", "15", "-an", screen,
    ]);
    writeFileSync(stamp, token);
  }
  return { screen };
}

function scaleVf() {
  const { w, h, x, y } = PREVIEW_SRC_CROP;
  const pad = PREVIEW_SAFE_PAD;
  const innerW = PREVIEW_W - pad * 2;
  const innerH = PREVIEW_H - pad * 2;
  return [
    `crop=${w}:${h}:${x}:${y}`,
    `scale=${innerW}:${innerH}:force_original_aspect_ratio=increase`,
    `crop=${innerW}:${innerH}:(iw-${innerW})/2:0`,
    `pad=${PREVIEW_W}:${PREVIEW_H}:${pad}:${pad}:color=${PAPER}`,
    "setsar=1",
    "format=yuv420p",
  ].join(",");
}

function formatTimeCode(sec, fps = FPS) {
  const totalFrames = Math.round(sec * fps);
  const frames = totalFrames % fps;
  const wholeSec = Math.floor(totalFrames / fps);
  const s = wholeSec % 60;
  const m = Math.floor(wholeSec / 60) % 60;
  const h = Math.floor(wholeSec / 3600);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}:${String(frames).padStart(2, "0")}`;
}

function encodeClip({ file, start, end, outSec, chapterPath, segPath }) {
  const speed = (end - start) / outSec;
  const vf = `setpts=PTS/${speed.toFixed(5)},${scaleVf()}`;
  const args = ["-y", "-v", "error", "-ss", start.toFixed(3), "-t", (end - start).toFixed(3), "-i", file];
  if (chapterPath) {
    args.push(
      "-loop", "1", "-framerate", String(FPS), "-t", outSec.toFixed(3), "-i", chapterPath,
      "-filter_complex", `[0:v]${vf}[b];[1:v]format=rgba,fade=t=in:st=0:d=0.12:alpha=1[c];[b][c]overlay=0:0:format=auto,format=yuv420p[v]`,
      "-map", "[v]",
    );
  } else {
    args.push("-vf", vf);
  }
  args.push(
    "-an", "-t", outSec.toFixed(3),
    "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
    "-pix_fmt", "yuv420p", "-r", String(FPS), "-crf", "17",
    segPath,
  );
  run("ffmpeg", args);
}

function buildPreview(result, font) {
  const themePath = existsSync(join(take, "theme.json"))
    ? join(take, "theme.json")
    : join(DEMO, "themes", "lost-job.json");
  const theme = JSON.parse(readFileSync(themePath, "utf8"));
  if (!theme.storeHook?.length) {
    const fallback = JSON.parse(
      readFileSync(join(DEMO, "themes", "lost-job.json"), "utf8"),
    );
    theme.storeHook = fallback.storeHook;
  }
  if (!theme.storeEnd?.length) {
    const fallback = JSON.parse(
      readFileSync(join(DEMO, "themes", "lost-job.json"), "utf8"),
    );
    theme.storeEnd = fallback.storeEnd;
  }
  const { screen } = ensureCfr();
  const tools = join(STORE, ".tools");
  const segDir = join(tools, "segs");
  rmSync(segDir, { recursive: true, force: true });
  mkdirSync(segDir, { recursive: true });

  const hookMp4 = join(tools, "hook.mp4");
  const thumbPng = join(STORE, "preview-hook-thumbnail.png");
  const { hookOut, lines: hookLines } = renderStoreHook({
    theme,
    toolsDir: tools,
    fontPath: join(tools, "Anton-Regular.ttf"),
    outMp4: hookMp4,
    thumbPng,
    width: PREVIEW_W,
    height: PREVIEW_H,
    fps: FPS,
    log,
  });

  const { marks, need } = takeMarks(result);
  const screenDur = Number(probe(screen).duration);
  const chapters = chapterOrder(result, marks);
  const lastStyle = chapters[chapters.length - 1];
  const shownLastKey = `shown_${lastStyle}`;
  let lastOut = 3.3;
  const typeOut = 1.65;
  const sendOut = 0.55;
  const angleOut = 1.7;
  const endHold = layoutStoreCards(theme.storeEnd, PREVIEW_W, PREVIEW_H, {
    endHold: 1.05,
    centerRatio: 0.4,
  }).duration;
  const hookOutForMin = hookOut;
  const bodyForMin = typeOut + sendOut + 1.0 + angleOut * Math.max(0, chapters.length - 1);
  let estimatedForMin = hookOutForMin + bodyForMin + lastOut + endHold;
  if (estimatedForMin < 15.05) lastOut += 15.05 - estimatedForMin;
  if (marks[shownLastKey] === undefined) {
    throw new Error(`missing ${shownLastKey} in result.json`);
  }
  if (marks[shownLastKey] > screenDur - 0.35) {
    throw new Error(
      `${shownLastKey} at ${marks[shownLastKey].toFixed(2)}s with only ${screenDur.toFixed(2)}s on tape — `
      + "Tough Love is not in the recording. Re-run demo/make_store.sh (longer post-flow wait).",
    );
  }
  if (marks[shownLastKey] + lastOut > screenDur - 0.04) {
    lastOut = Math.max(1.0, screenDur - 0.04 - marks[shownLastKey]);
    log(`tough love clip ${lastOut.toFixed(2)}s (tape ends ${screenDur.toFixed(2)}s)`);
  }
  const typeStart = need("type_start");
  const typeEnd = need("type_end");
  const sendAt = need("send");
  const cardAt = need("card");
  let cookFrom = (marks.cooking_after_followup ?? marks.cooking ?? sendAt) + 0.45;
  if (cookFrom >= cardAt - 0.35) cookFrom = Math.max(sendAt + 0.15, cardAt - 0.8);
  const cookRaw = Math.max(0.4, cardAt - cookFrom);
  const cookOut = Math.min(1.0, cookRaw / 1.5);
  const body = typeOut + sendOut + cookOut + angleOut * Math.max(0, chapters.length - 1);
  const estimated = hookOut + body + lastOut + endHold;
  if (estimated < 15.05) lastOut += 15.05 - estimated;
  if (hookOut + body + lastOut + endHold > 30) {
    throw new Error(`preview would be ${(hookOut + body + lastOut + endHold).toFixed(2)}s, over 30s`);
  }
  // Keep the in-point on the style mark; shorten the clip if we are near end of tape.
  // Sliding the window backward (old behavior) put the wrong style under the yellow title.
  const windowAt = (start, wanted) => {
    const maxEnd = Math.max(0.2, screenDur - 0.04);
    const s = Math.max(0, Math.min(start, maxEnd - 0.12));
    const e = Math.min(maxEnd, s + wanted);
    if (e - s < 0.12) {
      throw new Error(`clip at ${start.toFixed(2)}s overruns the take (${screenDur.toFixed(2)}s)`);
    }
    return { start: s, end: e };
  };
  const sendWin = windowAt(sendAt, sendOut);
  const clips = [
    { kind: "type", file: screen, start: typeStart, end: typeEnd, out: typeOut },
    { kind: "send", file: screen, start: sendWin.start, end: sendWin.end, out: sendOut },
    { kind: "cook", file: screen, start: cookFrom, end: Math.min(cardAt, screenDur - 0.04), out: cookOut },
  ];
  chapters.forEach((style, index) => {
    let marked;
    if (index === 0) {
      marked = cardAt;
    } else {
      const shown = marks[`shown_${style}`];
      if (shown === undefined) {
        throw new Error(`missing shown_${style} in result.json`);
      }
      if (index === chapters.length - 1) {
        marked = Math.min(screenDur - 0.18, shown + 0.5);
      } else {
        marked = Math.max(0, shown - 0.12);
      }
    }
    const wanted = index === chapters.length - 1 ? lastOut : angleOut;
    const win = windowAt(marked, wanted);
    const out = win.end - win.start;
    clips.push({
      kind: "style",
      file: screen,
      start: win.start,
      end: win.end,
      out,
      label: NAMES[style],
    });
  });

  const previewMin = 15.05;
  let bodySansHook = clips.reduce((sum, clip) => sum + clip.out, 0);
  const projected = hookOut + bodySansHook + endHold;
  if (projected < previewMin) {
    clips[0].out += previewMin - projected;
    log(`pad type +${(previewMin - projected).toFixed(2)}s (Apple 15s minimum)`);
  }

  let at = hookOut;
  clips.forEach((clip, index) => {
    clip.at = at;
    at += clip.out;
    clip.seg = join(segDir, `seg-${index}.mp4`);
    let chapterPath;
    if (clip.label) {
      chapterPath = join(tools, `chapter-${index}.png`);
      renderPng("chapter", {
        text: clip.label,
        max: 118,
        maxWidth: PREVIEW_W - 80,
        width: PREVIEW_W,
        height: PREVIEW_H,
        y: 168,
      }, chapterPath);
    }
    log(`segment ${index} ${clip.kind} ${clip.label || ""} → ${clip.out.toFixed(2)}s`);
    encodeClip({
      file: clip.file,
      start: clip.start,
      end: clip.end,
      outSec: clip.out,
      chapterPath,
      segPath: clip.seg,
    });
  });

  const endMp4 = join(tools, "end.mp4");
  const bodyAt = hookOut + clips.reduce((sum, c) => sum + c.out, 0);
  const endAt = bodyAt;
  const { duration: endOut, lines: endLines } = renderStoreEnd({
    theme,
    toolsDir: tools,
    fontPath: join(tools, "Anton-Regular.ttf"),
    outMp4: endMp4,
    width: PREVIEW_W,
    height: PREVIEW_H,
    fps: FPS,
    log,
  });

  const bodyTotal = hookOut + clips.reduce((sum, c) => sum + c.out, 0) + endOut;
  const total = bodyTotal;
  if (total < 15 || total > 30) {
    throw new Error(`preview duration ${total.toFixed(2)}s is outside 15–30s`);
  }

  const listPath = join(segDir, "concat.txt");
  const paths = [hookMp4, ...clips.map((c) => c.seg), endMp4];
  writeFileSync(listPath, `${paths.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join("\n")}\n`);
  const picture = join(segDir, "picture.mp4");
  run("ffmpeg", [
    "-y", "-v", "error",
    "-f", "concat", "-safe", "0", "-i", listPath,
    "-c", "copy",
    picture,
  ]);

  const SFX = {
    thump: { d: 0.45, expr: "0.55*sin(2*PI*(70+140*exp(-t*30))*t)*exp(-t*9)" },
    hit: { d: 0.45, expr: "0.55*sin(2*PI*(70+140*exp(-t*30))*t)*exp(-t*9)" },
    click: { d: 0.12, expr: "0.4*sin(2*PI*2200*t)*exp(-t*90)+0.25*sin(2*PI*900*t)*exp(-t*50)" },
    whoosh: { d: 0.55, expr: "0.4*(2*random(0)-1)*pow(sin(PI*t/0.55),3)" },
  };
  const cues = [];
  const t0 = 0;
  for (const line of hookLines) {
    cues.push(["thump", t0 + line.at + 0.05]);
  }
  for (const clip of clips) {
    if (clip.kind === "type") {
      for (let time = 0.1; time < clip.out - 0.2; time += 0.35) {
        cues.push(["click", t0 + clip.at + time]);
      }
    }
    if (clip.kind === "send") cues.push(["click", t0 + clip.at + 0.08]);
    if (clip.kind === "cook") cues.push(["whoosh", t0 + clip.at + 0.04]);
    if (clip.kind === "style") cues.push(["hit", t0 + clip.at + 0.06]);
  }
  for (const line of endLines) {
    cues.push(["hit", endAt + line.at + 0.05]);
  }
  const sfxChains = cues.map(([kind, time], index) => {
    const sfx = SFX[kind];
    const ms = Math.max(0, Math.round(time * 1000));
    const after = kind === "whoosh" ? ",highpass=f=400,lowpass=f=4000" : "";
    return `aevalsrc='${sfx.expr}':s=48000:c=stereo:d=${sfx.d}${after},adelay=${ms}:all=1[s${index}]`;
  });
  const bed = `anoisesrc=color=white:amplitude=0.02:sample_rate=48000:d=${total.toFixed(3)},aformat=channel_layouts=stereo[bed]`;
  const audio = `${sfxChains.join(";")};${bed};${cues.map((_, i) => `[s${i}]`).join("")}amix=inputs=${cues.length}:normalize=0:duration=longest,volume=0.85,alimiter=limit=0.8:level=false,atrim=0:${total.toFixed(3)},apad=whole_dur=${total.toFixed(3)}[sfx];[sfx][bed]amix=inputs=2:normalize=0:duration=first[aout]`;

  const out = join(STORE, "preview.mp4");
  const firstAngleAt = hookOut + typeOut + sendOut + cookOut;
  const posterFrameTimeCode = formatTimeCode(firstAngleAt);
  log(`preview ${total.toFixed(2)}s (hook ${hookOut.toFixed(2)}s, first angle @ ${firstAngleAt.toFixed(2)}s, end ${endOut.toFixed(2)}s)`);
  run("ffmpeg", [
    "-y", "-v", "error",
    "-i", picture,
    "-filter_complex", audio,
    "-map", "0:v", "-map", "[aout]",
    "-t", total.toFixed(3),
    "-c:v", "copy",
    "-c:a", "aac_at", "-b:a", "256k", "-ac", "2", "-ar", "48000",
    "-movflags", "+faststart",
    out,
  ]);

  const frames = join(STORE, "frames");
  mkdirSync(frames, { recursive: true });
  for (const time of [0.5, 1, 5, 9, 13, Math.max(0, total - 0.4)]) {
    run("ffmpeg", [
      "-y", "-v", "error",
      "-ss", String(time), "-i", out,
      "-frames:v", "1",
      join(frames, `t${String(time).replace(".", "_")}.png`),
    ]);
  }
  writeFileSync(
    join(STORE, "edit.json"),
    `${JSON.stringify(
      {
        total,
        hookOut,
        endOut,
        endAt,
        clips,
        firstAngleAt,
        posterFrameTimeCode,
      },
      null,
      2,
    )}\n`,
  );
  log(`wrote ${out} frame ${posterFrameTimeCode}`);
}

function buildListFrames() {
  const dir = join(STORE, "list-shots");
  const frames = [
    { raw: join(dir, "feed.png"), lines: ["ANGLES FROM", "OTHER PEOPLE."], out: "03-people.png", cropTop: 170 },
    { raw: join(dir, "shelf.png"), lines: ["A SHELF FOR", "EACH VOICE."], out: "04-shelf.png", cropTop: 170 },
    { raw: join(dir, "flip.png"), lines: ["KEEP THE ONE", "THAT FITS."], out: "05-keep.png", cropTop: 150 },
  ];
  for (const frame of frames) {
    if (!existsSync(frame.raw)) throw new Error(`missing ${frame.raw}`);
    log(`frame ${frame.out}`);
    composeShot(frame.raw, frame.lines, join(STORE, frame.out), frame.cropTop);
  }
}

const font = ensureFont();
if (process.argv.includes("--list-frames")) {
  buildListFrames();
} else {
  const previewOnly = process.argv.includes("--preview-only");
  const result = previewOnly
    ? JSON.parse(readFileSync(join(take, "result.json"), "utf8"))
    : buildFrames(font);
  buildPreview(result, font);
}
