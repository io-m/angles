// Writes the dark-mode copy of the save ride: same animation, colors remapped for the
// dark paper (#151413). Outlines and tires go light, white fills go to the dark
// surface, orange stays.
//
//   node scripts/lottie-dark-variant.mjs
//
// Re-run it whenever "Go to school.lottie" changes.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const RESOURCES = join(ROOT, "AnglesApp/AnglesApp/Resources");
const SOURCE = join(RESOURCES, "Go to school.lottie");
const TARGET = join(RESOURCES, "Go to school dark.lottie");

/** Light-theme color → dark-theme color. Anything not listed is kept. */
const DARK = {
  "1a1a1a": "ece8e3",
  "000000": "ece8e3",
  "030303": "ece8e3",
  "1c0311": "bdb7b0",
  ffffff: "292827",
};

const hex = (rgb) => rgb.slice(0, 3).map((v) => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
const rgb = (h) => [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);

const seen = new Map();
function recolor(node) {
  if (Array.isArray(node)) {
    node.forEach(recolor);
    return;
  }
  if (!node || typeof node !== "object") {
    return;
  }
  if ((node.ty === "fl" || node.ty === "st") && node.c) {
    if (node.c.a) {
      throw new Error("animated color found; extend the script to remap keyframes");
    }
    const from = hex(node.c.k);
    const to = DARK[from];
    seen.set(from, to ?? from);
    if (to) {
      node.c.k = [...rgb(to), node.c.k[3] ?? 1];
    }
  }
  if (node.ty === "gf" || node.ty === "gs") {
    throw new Error("gradient found; extend the script to remap gradient stops");
  }
  Object.values(node).forEach(recolor);
}

const work = mkdtempSync(join(tmpdir(), "lottie-dark-"));
try {
  execFileSync("unzip", ["-q", SOURCE, "-d", work]);
  const animDir = join(work, "animations");
  for (const file of readdirSync(animDir)) {
    const path = join(animDir, file);
    const json = JSON.parse(readFileSync(path, "utf8"));
    recolor(json.layers);
    recolor(json.assets);
    writeFileSync(path, JSON.stringify(json));
  }
  rmSync(TARGET, { force: true });
  execFileSync("zip", ["-q", "-X", "-D", "-r", TARGET, "manifest.json", "animations"], { cwd: work });
} finally {
  rmSync(work, { recursive: true, force: true });
}
console.log([...seen].map(([from, to]) => `#${from} -> #${to}`).join("\n"));
console.log(`wrote ${TARGET.replace(`${ROOT}/`, "")}`);
