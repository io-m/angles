import { loadLocalEnvFile } from "./lib/loadEnv.js";
import { serve } from "@hono/node-server";
import { assertSchemaCurrent, closePool } from "./db/client.js";
import { app } from "./app.js";

loadLocalEnvFile();

function parsePort(raw: string | undefined): number {
  const port = Number.parseInt(raw ?? "8787", 10);
  if (!Number.isInteger(port) || port <= 0 || port > 65_535) {
    throw new Error(`Invalid PORT: ${raw ?? ""}`);
  }
  return port;
}

async function main(): Promise<void> {
  await assertSchemaCurrent();

  const port = parsePort(process.env.PORT);
  const server = serve(
    {
      fetch: app.fetch,
      port,
      hostname: "0.0.0.0",
    },
    (info) => {
      console.log(`Angles API listening on http://127.0.0.1:${info.port}`);
    },
  );

  let shuttingDown = false;
  const shutdown = (): void => {
    if (shuttingDown) {
      return;
    }
    shuttingDown = true;
    server.close(() => {
      void closePool().finally(() => {
        process.exit(0);
      });
    });
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "startup_failed";
  console.error(message);
  process.exit(1);
});
