// Checks demo/output/final_9x16.mp4 and writes what a person should look at:
// demo/output/frames/*.png, contact_sheet.png, cover.png (first hook frame), report.md.
//
//   node demo/check.mjs demo/raw/take-YYYYMMDD-HHMMSS
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEMO = dirname(fileURLToPath(import.meta.url));
const take = process.argv[2];
const outDir = join(DEMO, "output");
const video = join(outDir, "final_9x16.mp4");
const framesDir = join(outDir, "frames");
const edl = JSON.parse(readFileSync(join(outDir, "edl.json"), "utf8"));
const answers = JSON.parse(readFileSync(join(take, "answers.json"), "utf8"));
const NAMES = { stoic: "Stoic", hopeful: "Hopeful", witty: "Witty", tough: "Tough" };

function run(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  if (r.status !== 0) {
    throw new Error(`${cmd} failed: ${(r.stderr || "").slice(-1500)}`);
  }
  return r.stdout;
}

const probe = JSON.parse(run("ffprobe", ["-v", "error", "-show_entries", "stream=codec_type,codec_name,width,height,r_frame_rate:format=duration,size", "-of", "json", video]));
const v = probe.streams.find((s) => s.codec_type === "video");
const a = probe.streams.find((s) => s.codec_type === "audio");
const duration = Number(probe.format.duration);
const sizeMB = statSync(video).size / (1024 * 1024);

const problems = [];
const notPostable = [];
if (v?.codec_name !== "h264" || v.width !== 1080 || v.height !== 1920 || v.r_frame_rate !== "30/1") {
  problems.push(`video stream is ${v?.codec_name} ${v?.width}x${v?.height} @ ${v?.r_frame_rate}, expected h264 1080x1920 @ 30/1`);
}
if (a?.codec_name !== "aac") {
  problems.push(`audio stream is ${a?.codec_name ?? "missing"}, expected aac`);
}
if (duration < 20 || duration > 32) {
  problems.push(`duration ${duration.toFixed(2)} s is outside 20-32 s`);
}
if (sizeMB >= 50) {
  problems.push(`file is ${sizeMB.toFixed(1)} MB, must be under 50 MB`);
}
if ((answers.followups ?? 0) > 1) {
  notPostable.push("Angles asked more than one follow-up.");
}
if (answers.crisis) {
  notPostable.push("Angles answered with a crisis line.");
}
for (const style of Object.keys(NAMES)) {
  if (!answers.answers?.[style]) {
    notPostable.push(`No ${NAMES[style]} answer was read from the card.`);
  }
}

// Review frames: both hook cards, the middle of every app beat, each angle once it settles, the end card.
rmSync(framesDir, { recursive: true, force: true });
mkdirSync(framesDir, { recursive: true });
const picks = [];
for (const beat of edl.timeline) {
  if (beat.name === "hook") {
    const cards = edl.composition.hook.cards;
    cards.forEach((card, i) => {
      const end = i + 1 < cards.length ? cards[i + 1][0].at : beat.outEnd;
      picks.push({ name: `hook-${i + 1}`, at: end - 0.2 });
    });
    continue;
  }
  const at = beat.name.startsWith("best-")
    ? beat.outStart + 3
    : beat.name.startsWith("chapter-") || beat.name === "end"
      ? beat.outEnd - 0.25
      : (beat.outStart + beat.outEnd) / 2;
  picks.push({ name: beat.name, at });
}
picks.forEach((p, i) => {
  const file = join(framesDir, `${String(i + 1).padStart(2, "0")}-${p.name}.png`);
  run("ffmpeg", ["-y", "-v", "error", "-ss", p.at.toFixed(3), "-i", video, "-frames:v", "1", file]);
  p.file = file;
});
const sheet = join(outDir, "contact_sheet.png");
const inputs = picks.flatMap((p) => ["-i", p.file]);
const cols = Math.min(picks.length, 6);
const layout = picks.map((_, i) => `${(i % cols) * 360}_${Math.floor(i / cols) * 640}`).join("|");
run("ffmpeg", [
  "-y", "-v", "error", ...inputs,
  "-filter_complex", `${picks.map((_, i) => `[${i}:v]scale=360:640[t${i}]`).join(";")};${picks.map((_, i) => `[t${i}]`).join("")}xstack=inputs=${picks.length}:layout=${layout}:fill=black`,
  sheet,
]);
copyFileSync(picks[0].file, join(outDir, "cover.png"));

const best = answers.best;
const lines = [
  "# Demo video report",
  "",
  `- Output: \`demo/output/final_9x16.mp4\` (${duration.toFixed(2)} s, ${sizeMB.toFixed(1)} MB, ${v?.width}x${v?.height}, ${a?.codec_name ?? "no audio"}${edl.music ? ", music and sound effects" : ", sound effects only"})`,
  `- Take: \`${take.replace(`${dirname(DEMO)}/`, "")}\``,
  `- Follow-ups asked: ${answers.followups ?? 0}${answers.followupQuestion ? ` ("${answers.followupQuestion}" answered with "${answers.followupAnswer}")` : ""}`,
  `- Strongest scored (report only, not a fifth chapter): **${NAMES[best] ?? best}**${answers.bestForced ? " (forced with BEST_STYLE)" : " (auto pick)"}`,
  "",
  "## Answers",
  "",
  `Thought on the card: ${answers.thought ?? "(not read)"}`,
  "",
  ...Object.keys(NAMES).map((s) => `- **${NAMES[s]}** (score ${answers.scores?.[s] ?? "n/a"}): ${answers.answers?.[s] ?? "(missing)"}`),
  "",
  "## Checks",
  "",
  ...(problems.length ? problems.map((p) => `- FAIL: ${p}`) : ["- Format, length, and size are within spec."]),
  ...(notPostable.length ? notPostable.map((p) => `- NOT POSTABLE: ${p}`) : []),
  "",
  "## Check by eye",
  "",
  "- Are the answers specific to this thought, or generic? Generic means do not post.",
  "- Is the last chapter (Tough) readable on a phone at arm's length?",
  "- No notification, real name, or personal data anywhere (the account is \"Angles Demo\").",
  "- The hook cards read in one glance, and the end card's App Store line and follow line are clear of TikTok's caption area.",
  "",
  "## Beats",
  "",
  ...edl.timeline.map((b) => `- ${b.outStart.toFixed(2)}-${b.outEnd.toFixed(2)} s: ${b.name}${b.speed && b.speed !== 1 ? ` (${b.speed.toFixed(2)}x)` : ""}`),
  "",
];
writeFileSync(join(outDir, "report.md"), lines.join("\n"));
console.error(`[check] ${problems.length ? `${problems.length} problem(s)` : "spec ok"}; ${notPostable.length ? "NOT POSTABLE" : "no automatic not-postable flags"}; report: demo/output/report.md`);
if (problems.length) {
  process.exit(1);
}
