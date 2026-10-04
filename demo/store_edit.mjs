// Compose the App Store frames and the 886×1920 preview from one store take.
//
//   node demo/store_edit.mjs store/raw/take-…
//
// Screenshots are full-bleed app UI under a yellow Anton headline. The preview
// is the same recording, cut so the first angle is on screen at 5 seconds
// (Apple's default poster) and the whole piece stays between 15 and 30 seconds.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { renderStoreEnd, renderStoreHook } from "./lib/storePreviewHook.mjs";

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
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scrim_h = int(h * 0.26)
    for row in range(scrim_h):
        t = row / max(1, scrim_h - 1)
        a = int(235 * (1.0 - t * 0.88))
        draw.line([(0, row), (w, row)], fill=(10, 9, 8, a))
    font = fit(spec["text"], spec.get("max", 118), spec.get("maxWidth", w - 60))
    tw = font.getlength(spec["text"])
    y = spec.get("y", 148)
    draw.text(((w - tw) / 2, y), spec["text"], font=font, fill=(0xFF, 0xD2, 0x1F, 255))
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

function buildFrames(font) {
  const result = JSON.parse(readFileSync(join(take, "result.json"), "utf8"));
  // The stoic line is the one that reads in a glance. Humorous is the contrast.
  const frames = [
    { raw: shotFile("style-stoic.png"), lines: ["FOUR WAYS", "TO SEE IT."], out: "01-four-ways.png", cropTop: 320 },
    { raw: shotFile("composer.png"), lines: ["WRITE THE", "HARD THOUGHT."], out: "02-write.png", cropTop: 300 },
    { raw: shotFile("style-humorous.png"), lines: ["SAME THOUGHT.", "DIFFERENT VOICE."], out: "03-voice.png", cropTop: 320 },
    { raw: shotFile("home.png"), lines: ["ANGLES FROM", "OTHER PEOPLE."], out: "04-home.png", cropTop: 150 },
    { raw: shotFile("favorites.png"), lines: ["KEEP THE ONE", "THAT FITS."], out: "05-keep.png", cropTop: 150 },
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
  const heartRaw = join(take, "heart.mp4");
  const screen = join(tools, "cfr-screen.mp4");
  const heart = join(tools, "cfr-heart.mp4");
  for (const [raw, out] of [[screenRaw, screen], [heartRaw, heart]]) {
    const stamp = `${out}.stamp`;
    if (existsSync(out) && existsSync(stamp)) continue;
    log(`CFR ${out}`);
    run("ffmpeg", [
      "-y", "-v", "error", "-i", raw,
      "-vf", `fps=${FPS},format=yuv420p`,
      "-c:v", "libx264", "-preset", "veryfast", "-crf", "16", "-g", "15", "-an", out,
    ]);
    writeFileSync(stamp, "ok");
  }
  return { screen, heart };
}

function scaleVf() {
  return `scale=${PREVIEW_W}:${PREVIEW_H}:force_original_aspect_ratio=increase,crop=${PREVIEW_W}:${PREVIEW_H},setsar=1,format=yuv420p`;
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
  const { screen, heart } = ensureCfr();
  const tools = join(STORE, ".tools");
  const segDir = join(tools, "segs");
  rmSync(segDir, { recursive: true, force: true });
  mkdirSync(segDir, { recursive: true });

  const hookMp4 = join(tools, "hook.mp4");
  const thumbPng = join(STORE, "preview-thumbnail.png");
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

  const typeOut = 1.75;
  const cookOut = 0.95;
  const stoicOut = 3.15;
  const styleOut = 2.4;
  const heartOut = 2.0;
  const clips = [
    { kind: "type", file: screen, start: 26.2, end: 37.0, out: typeOut },
    { kind: "cook", file: screen, start: 38.4, end: 43.6, out: cookOut },
    { kind: "style", file: screen, start: 44.0, end: 48.0, out: stoicOut, label: "STOIC" },
    { kind: "style", file: screen, start: 74.6, end: 78.0, out: styleOut, label: "OPTIMISTIC" },
    { kind: "style", file: screen, start: 83.6, end: 87.0, out: styleOut, label: "HUMOROUS" },
    { kind: "style", file: screen, start: 97.0, end: 99.8, out: styleOut, label: "TOUGH LOVE" },
    { kind: "heart", file: heart, start: 17.2, end: 20.4, out: heartOut },
  ];

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
        y: 148,
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
  const endAt = hookOut + clips.reduce((sum, c) => sum + c.out, 0);
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

  const total = hookOut + clips.reduce((sum, c) => sum + c.out, 0) + endOut;
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
  for (const line of hookLines) {
    cues.push(["thump", line.at + 0.05]);
  }
  for (const clip of clips) {
    if (clip.kind === "type") {
      for (let time = 0.1; time < clip.out - 0.2; time += 0.35) cues.push(["click", clip.at + time]);
    }
    if (clip.kind === "cook") cues.push(["whoosh", clip.at + 0.04]);
    if (clip.kind === "style") cues.push(["hit", clip.at + 0.06]);
    if (clip.kind === "heart") cues.push(["click", clip.at + 0.55]);
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
  log(`preview ${total.toFixed(2)}s (hook ${hookOut.toFixed(2)}s, end ${endOut.toFixed(2)}s, poster @ 5s Stoic)`);
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
  writeFileSync(join(STORE, "edit.json"), `${JSON.stringify({ total, hookOut, endOut, endAt, clips, posterAt: 5 }, null, 2)}\n`);
  log(`wrote ${out} and ${thumbPng}`);
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
