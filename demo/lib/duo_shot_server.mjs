// Local bridge so Maestro can ask simctl for a Duo display screenshot.
// Maestro's script runtime cannot spawn processes. It can POST here.
import { spawnSync } from "node:child_process";
import { createServer } from "node:http";

const port = Number(process.env.DUO_SHOT_PORT || 8765);
const server = createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.end("ok");
    return;
  }
  if (req.method !== "POST" || req.url !== "/shot") {
    res.writeHead(404);
    res.end("not found");
    return;
  }
  let raw = "";
  req.on("data", (chunk) => {
    raw += chunk;
  });
  req.on("end", () => {
    let body;
    try {
      body = JSON.parse(raw || "{}");
    } catch {
      res.writeHead(400);
      res.end("invalid json");
      return;
    }
    const { udid, display, dest } = body;
    if (!udid || !display || !dest) {
      res.writeHead(400);
      res.end("udid, display, and dest are required");
      return;
    }
    const result = spawnSync(
      "xcrun",
      ["simctl", "io", String(udid), "screenshot", `--display=${display}`, String(dest)],
      { encoding: "utf8" },
    );
    if (result.status !== 0) {
      res.writeHead(500);
      res.end(result.stderr || result.stdout || "screenshot failed");
      return;
    }
    res.end("ok");
  });
});

server.listen(port, "127.0.0.1", () => {
  console.error(`[duo_shot_server] 127.0.0.1:${port}`);
});
