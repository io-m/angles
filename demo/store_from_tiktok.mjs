// App Store preview from the TikTok cut: same picture through Tough love,
// only the end card copy changes (no "Coming soon", no "Follow").
//
//   node demo/store_from_tiktok.mjs
//
// Reads demo/output/final_9x16.mp4 + edl.json. Writes store/preview.mp4 at 886×1920.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEMO = dirname(fileURLToPath(import.meta.url));
const ROOT = join(DEMO, "..");
const STORE = join(ROOT, "store");
const tiktok = join(DEMO, "output", "final_9x16.mp4");
const edl = JSON.parse(readFileSync(join(DEMO, "output", "edl.json"), "utf8"));
const PREVIEW_W = 886;
const PREVIEW_H = 1920;
const FPS = 30;
const appEnd = edl.composition.appEnd;
const total = edl.total;
const badgeAt = appEnd + 1.6;

if (!existsSync(tiktok)) throw new Error(`missing ${tiktok}`);

function run(cmd, args) {
  const result = spawnSync(cmd, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${cmd} failed\n${result.stderr || result.stdout}`);
  }
  return result.stdout;
}

const tools = join(STORE, ".tools");
mkdirSync(tools, { recursive: true });
mkdirSync(STORE, { recursive: true });
const cover = join(tools, "tiktok-end-cover.png");
const badge = join(tools, "tiktok-end-badge.png");
const font = join(tools, "Anton-Regular.ttf");
if (!existsSync(font)) throw new Error(`missing ${font}`);

const py = `
import sys
sys.path.insert(0, ${JSON.stringify(tools)})
from PIL import Image, ImageDraw, ImageFont
font_path = ${JSON.stringify(font)}
cover_path = ${JSON.stringify(cover)}
badge_path = ${JSON.stringify(badge)}
W, H = 1080, 1920
cover = Image.new("RGBA", (W, H), (0, 0, 0, 0))
cd = ImageDraw.Draw(cover)
cd.rectangle([80, 1078, 1000, 1450], fill=(0, 0, 0, 255))
cover.save(cover_path)
text = "ON THE APP STORE"
font = ImageFont.truetype(font_path, 52)
tw = font.getlength(text)
pad_x, pad_y = 40, 24
pw, ph = int(tw + pad_x * 2), 104
badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
bd = ImageDraw.Draw(badge)
x0 = (W - pw) // 2
y0 = 1100
bd.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=ph // 2, fill=(0xFF, 0xD2, 0x1F, 255))
ty = y0 + (ph - 52) // 2 - 4
bd.text(((W - tw) / 2, ty), text, font=font, fill=(0, 0, 0, 255))
badge.save(badge_path)
`;
run("python3", ["-c", py]);

const out = join(STORE, "preview.mp4");
const fit = `scale=${PREVIEW_W}:${PREVIEW_H}:force_original_aspect_ratio=decrease,pad=${PREVIEW_W}:${PREVIEW_H}:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=${FPS},format=yuv420p`;
run("ffmpeg", [
  "-y", "-v", "error",
  "-i", tiktok,
  "-loop", "1", "-t", String(total), "-i", cover,
  "-loop", "1", "-t", String(total), "-i", badge,
  "-filter_complex",
  `[1:v]format=rgba[cover];[2:v]format=rgba,fade=t=in:st=${badgeAt.toFixed(3)}:d=0.35:alpha=1[badge];[0:v][cover]overlay=0:0:enable='gte(t,${appEnd.toFixed(3)})'[c];[c][badge]overlay=0:0[v];[v]${fit}[vout];[0:a]atrim=0:${total},asetpts=PTS-STARTPTS,aresample=48000[aout]`,
  "-map", "[vout]", "-map", "[aout]",
  "-t", String(total),
  "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high", "-level", "4.0",
  "-pix_fmt", "yuv420p", "-r", String(FPS),
  "-c:a", "aac_at", "-b:a", "256k", "-ac", "2", "-ar", "48000",
  "-movflags", "+faststart",
  out,
]);

const frames = join(STORE, "frames");
mkdirSync(frames, { recursive: true });
for (const time of [0.5, 5, 9.6, 13.8, 18.2, 20.2]) {
  run("ffmpeg", [
    "-y", "-v", "error",
    "-ss", String(time), "-i", out,
    "-frames:v", "1",
    join(frames, `tiktok-t${String(time).replace(".", "_")}.png`),
  ]);
}
console.error(`[store_from_tiktok] ${out} ${total.toFixed(2)}s, end from ${appEnd.toFixed(2)}s, badge @ ${badgeAt.toFixed(2)}s`);
