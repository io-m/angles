// Resolve iPhone Duo outer / inner display ids for simctl io screenshot.
import { spawnSync } from "node:child_process";

const OUTER_WIDTH = 1398;
const INNER_WIDTH = 2007;

function parseEnumerate(stdout) {
  const displays = [];
  const blocks = stdout.split(/\nPort:\n/);
  for (const block of blocks) {
    if (!block.includes("Class: Display")) continue;
    const uuid = block.match(/UUID:\s*([0-9A-F-]{36})/i)?.[1];
    const width = block.match(/Default width:\s*(\d+)/)?.[1];
    const height = block.match(/Default height:\s*(\d+)/)?.[1];
    if (uuid && width && height) {
      displays.push({ uuid, width: Number(width), height: Number(height) });
    }
  }
  return displays;
}

export function enumerateDisplays(udid) {
  const result = spawnSync("xcrun", ["simctl", "io", udid, "enumerate"], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || "simctl io enumerate failed");
  }
  return parseEnumerate(result.stdout);
}

export function displayForPose(displays, pose) {
  if (pose === "outer") {
    const hit =
      displays.find((d) => d.width === OUTER_WIDTH && d.height === 2034)
      ?? displays.find((d) => d.width === OUTER_WIDTH)
      ?? displays.filter((d) => d.width < INNER_WIDTH).sort((a, b) => b.width - a.width)[0];
    if (!hit) {
      throw new Error(`no outer display (${OUTER_WIDTH}×2034); found ${JSON.stringify(displays)}`);
    }
    return hit.uuid;
  }
  if (pose === "inner") {
    const hit =
      displays.find((d) => d.width === INNER_WIDTH && d.height === 2853)
      ?? displays.find((d) => d.width === INNER_WIDTH)
      ?? displays.filter((d) => d.width >= INNER_WIDTH).sort((a, b) => a.width - b.width)[0];
    if (!hit) {
      throw new Error(
        `no inner display (${INNER_WIDTH}×2853); unfold iPhone Duo in Simulator, found ${JSON.stringify(displays)}`,
      );
    }
    return hit.uuid;
  }
  throw new Error(`pose must be outer or inner, got ${pose}`);
}
