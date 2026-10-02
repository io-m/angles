// Pulls the flow's DEMO_RESULT object out of the Maestro log and the final view
// hierarchy out of `maestro hierarchy`, into result.json and hierarchy.json.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const take = process.argv[2];
if (!take) {
  console.error("usage: extract_result.mjs <take-dir>");
  process.exit(2);
}

function findLogs(dir) {
  const found = [];
  if (!existsSync(dir)) {
    return found;
  }
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      found.push(...findLogs(path));
    } else if (name === "maestro.log") {
      found.push(path);
    }
  }
  return found;
}

/** The first balanced JSON object starting at `start`, respecting strings. */
function balancedObject(text, start) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

let result = null;
for (const log of findLogs(join(take, "maestro"))) {
  const text = readFileSync(log, "utf8");
  let at = text.indexOf("DEMO_RESULT {");
  while (at >= 0) {
    const json = balancedObject(text, at + "DEMO_RESULT ".length);
    if (json) {
      try {
        result = JSON.parse(json);
      } catch {
        // A logged copy of the script source, not the output.
      }
    }
    at = text.indexOf("DEMO_RESULT {", at + 1);
  }
}

if (!result) {
  console.error(`No DEMO_RESULT found under ${take}/maestro`);
  process.exit(1);
}
writeFileSync(join(take, "result.json"), `${JSON.stringify(result, null, 2)}\n`);
writeFileSync(join(take, "answers.json"), `${JSON.stringify({
  thought: result.thought ?? null,
  firstStyle: result.firstStyle ?? null,
  answers: result.answers ?? {},
  scores: result.scores ?? {},
  best: result.best ?? null,
  bestForced: result.bestForced ?? false,
  followups: result.followups ?? 0,
  followupQuestion: result.followupQuestion ?? null,
  followupAnswer: result.followupAnswer ?? null,
  crisis: result.crisis ?? false,
  error: result.error ?? null,
}, null, 2)}\n`);

const rawPath = join(take, "hierarchy.raw");
if (existsSync(rawPath)) {
  const raw = readFileSync(rawPath, "utf8");
  const start = raw.indexOf("{");
  const json = start >= 0 ? balancedObject(raw, start) : null;
  if (json) {
    writeFileSync(join(take, "hierarchy.json"), json);
  }
}
console.error(`[extract] best=${result.best} followups=${result.followups}`);
