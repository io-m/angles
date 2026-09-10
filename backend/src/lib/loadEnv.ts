import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Load backend/.env into process.env for keys that are not already set.
 * Vitest skips this by default so tests cannot pick up provider keys.
 */
export function loadLocalEnvFile(options?: { skipWhenVitest?: boolean }): void {
  if (options?.skipWhenVitest && process.env.VITEST === "true") {
    return;
  }

  let raw: string;
  try {
    raw = readFileSync(resolve(process.cwd(), ".env"), "utf8");
  } catch {
    return;
  }

  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith("#")) {
      continue;
    }

    const separator = trimmed.indexOf("=");
    if (separator <= 0) {
      continue;
    }

    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (
      (value.startsWith("\"") && value.endsWith("\"")) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

loadLocalEnvFile({ skipWhenVitest: true });
