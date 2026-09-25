import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { processSubscriptionNotification } from "../db/subscriptions.js";
import {
  AppStoreVerificationError,
  getAppStoreVerifier,
} from "../lib/appStoreVerifier.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";

const notificationSchema = z.object({
  signedPayload: z.string().min(1).max(32_000),
});

export const appStoreNotificationsRoute = new Hono();

appStoreNotificationsRoute.post(
  "/",
  zValidator("json", notificationSchema, (result, c) => {
    if (!result.success) {
      return c.json(errorBody(validationErrorMessage(result.error), "VALIDATION_ERROR"), 400);
    }
  }),
  async (c) => {
    try {
      const notification = await getAppStoreVerifier().verifyNotification(
        c.req.valid("json").signedPayload,
      );
      const result = await processSubscriptionNotification(notification);
      return c.json({ accepted: true, duplicate: result === "duplicate" });
    } catch (error) {
      if (error instanceof AppStoreVerificationError) {
        if (error.kind === "configuration") {
          return c.json(
            errorBody("App Store verification is unavailable", "APP_STORE_NOT_CONFIGURED"),
            503,
          );
        }
        return c.json(
          errorBody("App Store notification could not be verified", "APP_STORE_VERIFICATION_FAILED"),
          401,
        );
      }
      throw error;
    }
  },
);
