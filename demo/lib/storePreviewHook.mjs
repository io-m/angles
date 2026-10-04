// Renders App Store preview Anton title cards (~886×1920) as PNG frames + mp4.
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEMO = join(dirname(fileURLToPath(import.meta.url)), "..");

export function layoutStoreCards(cards, width, height, { endHold = 0.55, centerRatio = 0.368 } = {}) {
  const ANTON = JSON.parse(readFileSync(join(DEMO, "lib", "anton-widths.json"), "utf8"));
  if (!Array.isArray(cards) || !cards.length) {
    throw new Error("cards must be a non-empty list");
  }
  const LOOKS = { big: 246, slam: 246, small: 118 };
  const centerY = Math.round(height * centerRatio);
  const maxWidth = width - 80;
  const display = (text, look) => (look === "small" ? text : text.toLocaleUpperCase("en-US"));
  const textEm = (text) => [...text].reduce((w, c) => w + (ANTON.advance[c] ?? 0.5), 0);
  const fitSize = (text, max) => Math.min(max, Math.floor(maxWidth / Math.max(0.01, textEm(text))));

  let beatAt = 0.12;
  const lines = [];
  for (const card of cards) {
    for (const line of card) {
      if (!LOOKS[line.look]) throw new Error(`bad look ${line.look}`);
      const text = display(line.text, line.look);
      lines.push({
        text,
        look: line.look,
        size: fitSize(text, LOOKS[line.look]),
        at: beatAt,
      });
      beatAt += line.look === "small" ? 0.5 : 0.48;
    }
  }
  const duration = beatAt + endHold;
  const gap = (a, b) => (a.look !== "small" && b.look !== "small" ? 8 : a.look !== "small" ? 22 : 16);
  const blockH = lines.reduce((h, l, i) => h + l.size + (i ? gap(lines[i - 1], l) : 0), 0);
  let top = Math.round(centerY - blockH / 2);
  lines.forEach((l, i) => {
    top += i ? lines[i - 1].size + gap(lines[i - 1], l) : 0;
    l.top = top;
  });
  return { lines, duration, thumbAt: lines[lines.length - 1].at + 0.35 };
}

export function layoutStoreHook(theme, width, height) {
  const { lines, duration, thumbAt } = layoutStoreCards(theme.storeHook, width, height);
  return { lines, hookOut: duration, thumbAt };
}

function renderAntonSequence({
  lines,
  duration,
  toolsDir,
  fontPath,
  outMp4,
  thumbPng,
  width,
  height,
  fps,
  log,
  label,
  zoomOutEnd,
}) {
  const framesDir = join(toolsDir, `${label}-frames`);
  rmSync(framesDir, { recursive: true, force: true });
  mkdirSync(framesDir, { recursive: true });
  const frameCount = Math.ceil(duration * fps);
  const thumbAt = thumbPng ? lines[lines.length - 1].at + 0.35 : -1;
  const script = `
import math, sys
sys.path.insert(0, ${JSON.stringify(toolsDir)})
from PIL import Image, ImageDraw, ImageFont
lines = ${JSON.stringify(lines)}
duration = ${duration}
fps = ${fps}
w, h = ${width}, ${height}
frames_dir = ${JSON.stringify(framesDir)}
font_path = ${JSON.stringify(fontPath)}
zoom_out = ${zoomOutEnd ? "True" : "False"}
thumb_at = ${thumbAt}
thumb_path = ${JSON.stringify(thumbPng ?? "")}

def fit(text, max_size):
    size = max_size
    while size > 32:
        font = ImageFont.truetype(font_path, size)
        if font.getlength(text) <= w - 80:
            return font
        size -= 2
    return ImageFont.truetype(font_path, 32)

def shake_offset(t, at):
    dt = t - at
    if dt < 0 or dt > 0.14:
        return 0, 0
    amp = 14 * (1 - dt / 0.14)
    return amp * math.sin(dt * 90), amp * math.cos(dt * 70) * 0.5

fonts = {i: fit(l["text"], l["size"]) for i, l in enumerate(lines)}
thumb_frame = int(thumb_at * fps) if thumb_at >= 0 else -1

for fi in range(int(duration * fps) + 1):
    t = fi / fps
    img = Image.new("RGB", (w, h), (0x15, 0x14, 0x13))
    stage_s = 1.0
    stage_a = 1.0
    if zoom_out and t > duration - 0.38:
        p = min(1, (t - (duration - 0.38)) / 0.38)
        stage_s = 1 + 1.55 * p
        stage_a = 1 - p
    ox, oy = 0, 0
    for l in lines:
        sx, sy = shake_offset(t, l["at"] + (0.2 if l["look"] == "slam" else 0.16))
        ox += sx
        oy += sy
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for i, l in enumerate(lines):
        if t < l["at"]:
            continue
        dt = t - l["at"]
        pop = min(1, dt / 0.08)
        base = 1.9 if l["look"] == "slam" else 1.65
        sc = 1 + (base - 1) * max(0, 1 - min(1, dt / 0.28)) ** 2
        font = fonts[i]
        tw = font.getlength(l["text"]) * sc
        th = l["size"] * sc
        cx = w / 2
        cy = l["top"] + l["size"] / 2
        color = (255, 210, 31, int(255 * pop * stage_a)) if l["look"] != "small" else (255, 255, 255, int(255 * pop * stage_a))
        txt = Image.new("RGBA", (int(tw + 20), int(th + 20)), (0, 0, 0, 0))
        td = ImageDraw.Draw(txt)
        td.text((10, 5), l["text"], font=font, fill=color)
        txt = txt.resize((int(txt.width * sc), int(txt.height * sc)), Image.LANCZOS)
        px = int(cx - txt.width / 2 + ox)
        py = int(cy - txt.height / 2 + oy)
        layer.paste(txt, (px, py), txt)
    if stage_s != 1:
        nw, nh = int(w * stage_s), int(h * stage_s)
        layer = layer.resize((nw, nh), Image.LANCZOS)
        layer = layer.crop(((nw - w) // 2, (nh - h) // 2, (nw + w) // 2, (nh + h) // 2))
    out = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
    out.save(f"{frames_dir}/f{fi:04d}.png")
    if fi == thumb_frame and thumb_path:
        out.save(thumb_path)
`;
  const py = spawnSync("python3", ["-c", script], { encoding: "utf8" });
  if (py.status !== 0) throw new Error(py.stderr || py.stdout);
  log(`${label} ${duration.toFixed(2)}s, ${frameCount} frames`);
  const ff = spawnSync("ffmpeg", [
    "-y", "-v", "error",
    "-framerate", String(fps),
    "-i", join(framesDir, "f%04d.png"),
    "-frames:v", String(frameCount + 1),
    "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
    "-pix_fmt", "yuv420p", "-r", String(fps), "-crf", "17",
    "-an", outMp4,
  ], { encoding: "utf8" });
  if (ff.status !== 0) throw new Error(ff.stderr || ff.stdout);
  return { duration, lines };
}

export function renderStoreHook({ theme, toolsDir, fontPath, outMp4, thumbPng, width, height, fps, log }) {
  const { lines, hookOut, thumbAt } = layoutStoreHook(theme, width, height);
  const { duration, lines: outLines } = renderAntonSequence({
    lines,
    duration: hookOut,
    toolsDir,
    fontPath,
    outMp4,
    thumbPng,
    width,
    height,
    fps,
    log,
    label: "hook",
    zoomOutEnd: true,
  });
  return { hookOut: duration, thumbAt, lines: outLines };
}

export function renderStoreEnd({ theme, toolsDir, fontPath, outMp4, width, height, fps, log }) {
  const cards = theme.storeEnd;
  if (!Array.isArray(cards) || !cards.length) {
    throw new Error("theme.storeEnd must be a non-empty list of cards");
  }
  const { lines, duration } = layoutStoreCards(cards, width, height, { endHold: 1.05, centerRatio: 0.4 });
  return renderAntonSequence({
    lines,
    duration,
    toolsDir,
    fontPath,
    outMp4,
    thumbPng: null,
    width,
    height,
    fps,
    log,
    label: "end",
    zoomOutEnd: false,
  });
}
