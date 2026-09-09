import { serve } from "@hono/node-server";
import { app } from "./app.js";

function parsePort(raw: string | undefined): number {
  const port = Number.parseInt(raw ?? "8787", 10);
  if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
    throw new Error(`Invalid PORT: ${raw ?? ""}`);
  }
  return port;
}

const port = parsePort(process.env.PORT);

serve(
  {
    fetch: app.fetch,
    port,
    hostname: "0.0.0.0",
  },
  (info) => {
    console.log(`Angles API listening on http://127.0.0.1:${info.port}`);
  },
);
