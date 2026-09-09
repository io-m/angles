import { Hono } from "hono";

export const healthRoute = new Hono();

healthRoute.get("/", (c) => c.json({ status: "ok" as const }));
