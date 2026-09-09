import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { HTTPException } from "hono/http-exception";
import { logger } from "hono/logger";
import { errorBody } from "./lib/http.js";
import { healthRoute } from "./routes/health.js";
import { reframeRoute } from "./routes/reframe.js";

const MAX_BODY_BYTES = 8 * 1024;

export function createApp(): Hono {
  const app = new Hono();

  app.use("*", logger());
  app.use(
    "*",
    bodyLimit({
      maxSize: MAX_BODY_BYTES,
      onError: (c) => c.json(errorBody("Request body too large", "PAYLOAD_TOO_LARGE"), 413),
    }),
  );

  app.route("/health", healthRoute);
  app.route("/reframe", reframeRoute);

  app.notFound((c) => c.json(errorBody("Not found", "NOT_FOUND"), 404));

  app.onError((err, c) => {
    if (err instanceof HTTPException) {
      const status = err.status;
      if (status === 400) {
        const code = err.message.includes("JSON") ? "INVALID_JSON" : "BAD_REQUEST";
        return c.json(errorBody(err.message, code), 400);
      }
      return c.json(errorBody(err.message || "Request failed", "REQUEST_FAILED"), status);
    }
    if (err instanceof SyntaxError) {
      return c.json(errorBody("Invalid JSON", "INVALID_JSON"), 400);
    }
    console.error("unhandled_error", { name: err.name });
    return c.json(errorBody("Internal server error", "INTERNAL_ERROR"), 500);
  });

  return app;
}

export const app = createApp();
