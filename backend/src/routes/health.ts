import { Hono } from "hono";
import { probeDatabase } from "../db/client.js";

export const healthRoute = new Hono();

healthRoute.get("/", async (c) => {
  const db = await probeDatabase();
  if (db === "down") {
    return c.json({ status: "error" as const, db: "down" as const }, 503);
  }
  return c.json({ status: "ok" as const, db: "ok" as const });
});
