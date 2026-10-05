import { randomUUID } from "node:crypto";
import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { consumeLoginChallenge, insertLoginChallenge } from "../db/adminLogin.js";
import {
  deleteReportedCard,
  getAuthorReview,
  getCardReview,
  listAuthorPublicCards,
  listPendingReports,
  listReviewedReports,
  resolveCardReports,
  restorePublishing,
  searchAdmin,
  summarizeReports,
  suspendPublishing,
  thoughtExcerpt,
  type PendingReportedCard,
  type ReviewedCard,
} from "../db/reportReview.js";
import {
  ADMIN_PROXY_HEADER,
  clearSessionCookie,
  issueLoginToken,
  issueSessionToken,
  magicLinkUrl,
  proxyHeaderOk,
  readAdminConfig,
  readLoginToken,
  readSessionEmail,
  sessionCookie,
  sessionTokenFromCookie,
  type AdminConfig,
} from "../lib/adminSession.js";
import { sendAdminMagicLink } from "../lib/adminMail.js";
import {
  ADMIN_RATE_WINDOW_MS,
  LOGIN_EMAIL_LIMIT,
  LOGIN_IP_LIMIT,
  MUTATION_LIMIT,
  allowAdminRate,
} from "../lib/adminRateLimit.js";
import { errorBody, validationErrorMessage } from "../lib/http.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const emailSchema = z
  .object({
    email: z.string().trim().toLowerCase().pipe(z.email()),
  })
  .strict();

const tokenSchema = z
  .object({
    token: z.string().min(1).max(4_000),
  })
  .strict();

const cardIdSchema = z.object({
  cardId: z.string().regex(UUID, "cardId must be a UUID"),
});

const userIdSchema = z.object({
  userId: z.string().regex(UUID, "userId must be a UUID"),
});

type AdminEnv = {
  Variables: {
    adminConfig: AdminConfig;
    operatorEmail: string;
  };
};

function clientIp(header: string | undefined, forwardedFor: string | undefined): string {
  const direct = header?.trim();
  if (direct) {
    return direct.slice(0, 64);
  }
  const forwarded = forwardedFor?.split(",")[0]?.trim();
  return forwarded && forwarded.length > 0 ? forwarded.slice(0, 64) : "unknown";
}

const searchQuerySchema = z.object({
  q: z.string().trim().min(1).max(200),
});

function reportSummary(card: PendingReportedCard) {
  return {
    cardId: card.cardId,
    authorId: card.authorId,
    authorInitials: card.authorInitials,
    authorSuspended: card.authorSuspended,
    isPublic: card.isPublic,
    firstReportedAt: card.firstReportedAt.toISOString(),
    reasons: card.reasons,
    reportCount: card.reportCount,
    thoughtExcerpt: thoughtExcerpt(card.thought),
  };
}

function reviewedSummary(card: ReviewedCard) {
  return {
    cardId: card.cardId,
    authorId: card.authorId,
    authorInitials: card.authorInitials,
    authorSuspended: card.authorSuspended,
    isPublic: card.isPublic,
    reviewedAt: card.reviewedAt.toISOString(),
    resolution: card.resolution,
    reasons: card.reasons,
    thoughtExcerpt: thoughtExcerpt(card.thought),
  };
}

export const adminRoute = new Hono<AdminEnv>();

adminRoute.use("*", async (c, next) => {
  c.header("Cache-Control", "no-store");
  const config = readAdminConfig();
  if (!config) {
    return c.json(errorBody("Admin is not configured", "ADMIN_DISABLED"), 503);
  }
  if (!proxyHeaderOk(c.req.header(ADMIN_PROXY_HEADER), config)) {
    return c.json(errorBody("Unauthorized", "UNAUTHORIZED"), 401);
  }
  c.set("adminConfig", config);
  await next();
});

const invalidJson = (result: { success: boolean; error?: { issues: { message: string }[] } }, c: { json: (body: unknown, status: 400) => Response }) => {
  if (!result.success) {
    return c.json(errorBody(validationErrorMessage(result.error ?? { issues: [] }), "VALIDATION_ERROR"), 400);
  }
};

adminRoute.post("/login/request", zValidator("json", emailSchema, invalidJson), async (c) => {
  const { email } = c.req.valid("json");
  const ip = clientIp(c.req.header("x-angles-client-ip"), c.req.header("x-forwarded-for"));
  if (
    !allowAdminRate(`login:ip:${ip}`, LOGIN_IP_LIMIT, ADMIN_RATE_WINDOW_MS) ||
    !allowAdminRate(`login:email:${email}`, LOGIN_EMAIL_LIMIT, ADMIN_RATE_WINDOW_MS)
  ) {
    return c.json(errorBody("Too many requests", "RATE_LIMITED"), 429);
  }
  const config = c.get("adminConfig");
  if (!config.emails.has(email)) {
    return c.json({ ok: true as const });
  }
  const jti = randomUUID();
  const { token, expiresAt } = issueLoginToken(config.sessionSecret, email, jti);
  await insertLoginChallenge(jti, email, expiresAt);
  const link = magicLinkUrl(config.appOrigin, token);
  try {
    const sent = await sendAdminMagicLink(email, link);
    if (sent === "skipped") {
      console.warn("admin_mail_unconfigured");
    }
  } catch (error: unknown) {
    console.error("admin_mail_failed", { name: error instanceof Error ? error.name : "error" });
  }
  return c.json({ ok: true as const });
});

adminRoute.post("/login/verify", zValidator("json", tokenSchema, invalidJson), async (c) => {
  const config = c.get("adminConfig");
  const claims = readLoginToken(config.sessionSecret, c.req.valid("json").token);
  if (!claims || !config.emails.has(claims.email)) {
    return c.json(errorBody("Unauthorized", "UNAUTHORIZED"), 401);
  }
  const consumed = await consumeLoginChallenge(claims.jti, claims.email);
  if (consumed !== "ok") {
    return c.json(errorBody("Unauthorized", "UNAUTHORIZED"), 401);
  }
  const session = issueSessionToken(config.sessionSecret, claims.email);
  c.header("Set-Cookie", sessionCookie(session.token, session.maxAge, config.secureCookie));
  return c.json({ ok: true as const });
});

adminRoute.post("/logout", (c) => {
  const config = c.get("adminConfig");
  c.header("Set-Cookie", clearSessionCookie(config.secureCookie));
  return c.json({ ok: true as const });
});

function isOpenAdminPath(path: string): boolean {
  return path.endsWith("/login/request") || path.endsWith("/login/verify") || path.endsWith("/logout");
}

adminRoute.use("*", async (c, next) => {
  if (isOpenAdminPath(c.req.path)) {
    await next();
    return;
  }
  const config = c.get("adminConfig");
  const token = sessionTokenFromCookie(c.req.header("cookie"));
  const email = token ? readSessionEmail(config.sessionSecret, token) : null;
  if (!email) {
    return c.json(errorBody("Unauthorized", "UNAUTHORIZED"), 401);
  }
  if (!config.emails.has(email)) {
    return c.json(errorBody("Forbidden", "FORBIDDEN"), 403);
  }
  c.set("operatorEmail", email);
  await next();
});

adminRoute.get("/session", (c) => {
  return c.json({ email: c.get("operatorEmail") });
});

adminRoute.get("/reports", async (c) => {
  const pending = await listPendingReports();
  return c.json({ reports: pending.map(reportSummary) });
});

adminRoute.get("/reports/summary", async (c) => {
  return c.json(await summarizeReports());
});

adminRoute.get("/reports/reviewed", async (c) => {
  const reviewed = await listReviewedReports();
  return c.json({ reports: reviewed.map(reviewedSummary) });
});

adminRoute.get("/search", zValidator("query", searchQuerySchema, invalidJson), async (c) => {
  const found = await searchAdmin(c.req.valid("query").q);
  return c.json({
    cards: found.cards.map((card) => ({
      cardId: card.cardId,
      thoughtExcerpt: thoughtExcerpt(card.thought),
      isPublic: card.isPublic,
      authorId: card.authorId,
      authorInitials: card.authorInitials,
      authorEmail: card.authorEmail,
      authorSuspended: card.authorSuspended,
      reportCount: card.reportCount,
      reasons: card.reasons,
    })),
    users: found.users,
  });
});

adminRoute.get("/reports/:cardId", zValidator("param", cardIdSchema, invalidJson), async (c) => {
  const card = await getCardReview(c.req.valid("param").cardId);
  if (!card) {
    return c.json(errorBody("No such card", "NOT_FOUND"), 404);
  }
  return c.json({
    cardId: card.cardId,
    authorId: card.authorId,
    authorInitials: card.authorInitials,
    authorEmail: card.authorEmail,
    authorSuspended: card.authorSuspended,
    isPublic: card.isPublic,
    reportCount: card.reportCount,
    reasons: card.reasons,
    firstReportedAt: card.firstReportedAt?.toISOString() ?? null,
    thought: card.thought,
    reframes: card.reframes,
  });
});

async function mutate(c: { get: (key: "operatorEmail") => string; json: (body: unknown, status: 429) => Response }): Promise<Response | null> {
  if (!allowAdminRate(`mutate:${c.get("operatorEmail")}`, MUTATION_LIMIT, ADMIN_RATE_WINDOW_MS)) {
    return c.json(errorBody("Too many requests", "RATE_LIMITED"), 429);
  }
  return null;
}

adminRoute.post("/reports/:cardId/keep", zValidator("param", cardIdSchema, invalidJson), async (c) => {
  const limited = await mutate(c);
  if (limited) {
    return limited;
  }
  const result = await resolveCardReports(c.req.valid("param").cardId, "kept");
  if (result === "not_found") {
    return c.json(errorBody("No such card", "NOT_FOUND"), 404);
  }
  return c.json({ ok: true as const });
});

adminRoute.post("/reports/:cardId/hide", zValidator("param", cardIdSchema, invalidJson), async (c) => {
  const limited = await mutate(c);
  if (limited) {
    return limited;
  }
  const result = await resolveCardReports(c.req.valid("param").cardId, "hidden");
  if (result === "not_found") {
    return c.json(errorBody("No such card", "NOT_FOUND"), 404);
  }
  return c.json({ ok: true as const });
});

adminRoute.post("/reports/:cardId/delete", zValidator("param", cardIdSchema, invalidJson), async (c) => {
  const limited = await mutate(c);
  if (limited) {
    return limited;
  }
  const deleted = await deleteReportedCard(c.req.valid("param").cardId);
  if (!deleted) {
    return c.json(errorBody("No such card", "NOT_FOUND"), 404);
  }
  return c.json({ ok: true as const });
});

adminRoute.get("/users/:userId/cards", zValidator("param", userIdSchema, invalidJson), async (c) => {
  const author = await getAuthorReview(c.req.valid("param").userId);
  if (!author) {
    return c.json(errorBody("No such user", "NOT_FOUND"), 404);
  }
  const listed = await listAuthorPublicCards(author.userId);
  return c.json({
    cards: listed.map((card) => ({
      cardId: card.cardId,
      thoughtExcerpt: thoughtExcerpt(card.thought),
      createdAt: card.createdAt.toISOString(),
    })),
  });
});

adminRoute.get("/users/:userId", zValidator("param", userIdSchema, invalidJson), async (c) => {
  const author = await getAuthorReview(c.req.valid("param").userId);
  if (!author) {
    return c.json(errorBody("No such user", "NOT_FOUND"), 404);
  }
  return c.json(author);
});

adminRoute.post("/users/:userId/suspend", zValidator("param", userIdSchema, invalidJson), async (c) => {
  const limited = await mutate(c);
  if (limited) {
    return limited;
  }
  const result = await suspendPublishing(c.req.valid("param").userId);
  if (result === "not_found") {
    return c.json(errorBody("No such user", "NOT_FOUND"), 404);
  }
  return c.json({ ok: true as const });
});

adminRoute.post("/users/:userId/unsuspend", zValidator("param", userIdSchema, invalidJson), async (c) => {
  const limited = await mutate(c);
  if (limited) {
    return limited;
  }
  const result = await restorePublishing(c.req.valid("param").userId);
  if (result === "not_found") {
    return c.json(errorBody("No such user", "NOT_FOUND"), 404);
  }
  return c.json({ ok: true as const });
});
