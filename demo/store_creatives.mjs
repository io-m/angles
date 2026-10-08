// Render App Store header (21:9) and search (3:2) stills.
//
//   node demo/store_creatives.mjs
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEMO = dirname(fileURLToPath(import.meta.url));
const py = join(DEMO, "lib", "storeCreatives.py");
const env = {
  ...process.env,
  PYTHONPATH: ["/tmp/angles-pil", process.env.PYTHONPATH].filter(Boolean).join(":"),
};

// /tmp/angles-pil is built for the Xcode CLT Python (3.9). A newer Homebrew
// python3 cannot load its compiled modules, so probe for one that can.
let python = "python3";
for (const candidate of ["python3", "/usr/bin/python3"]) {
  const probe = spawnSync(candidate, ["-c", "from PIL import Image"], {
    encoding: "utf8",
    env,
  });
  if (probe.status === 0) {
    python = candidate;
    break;
  }
}
const result = spawnSync(python, [py], { encoding: "utf8", env });
if (result.stdout) process.stderr.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
