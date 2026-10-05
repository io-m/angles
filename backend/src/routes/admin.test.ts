import { beforeEach, describe, expect, it, vi } from "vitest";
import { issueLoginToken, issueSessionToken, readAdminConfig } from "../lib/adminSession.js";
import { resetAdminRateLimits } from "../lib/adminRateLimit.js";

vi.mock("../db/adminLogin.js", () => ({
  insertLoginChallenge: vi.fn(async () => undefined),
  consumeLoginChallenge: vi.fn(async () => "ok" as const),
}));

vi.mock("../lib/adminMail.js", () => ({
  sendAdminMagicLink: vi.fn(async () => "sent" as const),
}));

vi.mock("../db/reportReview.js", () => ({
  listPendingReports: vi.fn(),
  getCardReview: vi.fn(),
  getAuthorReview: vi.fn(),
  resolveCardReports: vi.fn(),
  publishHiddenCard: vi.fn(),
  deleteReportedCard: vi.fn(),
  suspendPublishing: vi.fn(),
  restorePublishing: vi.fn(),
  summarizeReports: vi.fn(),
  listReviewedReports: vi.fn(),
  listAuthorPublicCards: vi.fn(),
  searchAdmin: vi.fn(),
  thoughtExcerpt: (thought: string) => thought,
}));

const { createApp } = await import("../app.js");
const { consumeLoginChallenge, insertLoginChallenge } = await import("../db/adminLogin.js");
const { sendAdminMagicLink } = await import("../lib/adminMail.js");
const {
  deleteReportedCard,
  getAuthorReview,
  getCardReview,
  listAuthorPublicCards,
  listPendingReports,
  listReviewedReports,
  publishHiddenCard,
  resolveCardReports,
  restorePublishing,
  searchAdmin,
  summarizeReports,
  suspendPublishing,
} = await import("../db/reportReview.js");

const app = createApp();
const SECRET = "test-admin-session-secret-32chars-min";
const PROXY = "test-admin-proxy-secret-32-characters";
const EMAIL = "josipmiljak@proton.me";
const CARD_ID = "11111111-1111-4111-8111-111111111111";
const USER_ID = "22222222-2222-4222-8222-222222222222";

function sessionCookie(email = EMAIL): string {
  const { token } = issueSessionToken(SECRET, email);
  return `angles_admin=${token}`;
}

function authed(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("cookie", sessionCookie());
  return Promise.resolve(app.request(path, { ...init, headers }));
}

beforeEach(() => {
  process.env.ADMIN_SESSION_SECRET = SECRET;
  process.env.ADMIN_OPERATOR_EMAILS = "josipmiljak@proton.me,info@bithavn.app";
  process.env.ADMIN_APP_ORIGIN = "http://localhost:3000";
  delete process.env.ADMIN_PROXY_SECRET;
  resetAdminRateLimits();
  vi.clearAllMocks();
});

describe("admin auth", () => {
  it("rejects a report list and a mutation without a session", async () => {
    const list = await app.request("/admin/reports");
    const hide = await app.request(`/admin/reports/${CARD_ID}/hide`, { method: "POST" });
    expect(list.status).toBe(401);
    expect(hide.status).toBe(401);
    expect(await list.json()).toEqual({ error: "Unauthorized", code: "UNAUTHORIZED" });
    expect(resolveCardReports).not.toHaveBeenCalled();
  });

  it("does not mail an address that is not on the allowlist", async () => {
    const response = await app.request("/admin/login/request", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "stranger@example.com" }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(sendAdminMagicLink).not.toHaveBeenCalled();
    expect(insertLoginChallenge).not.toHaveBeenCalled();
  });

  it("mails an allowlisted address and sets a session cookie for that link", async () => {
    const requested = await app.request("/admin/login/request", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: ` ${EMAIL.toUpperCase()} ` }),
    });
    expect(requested.status).toBe(200);
    expect(sendAdminMagicLink).toHaveBeenCalledOnce();
    const link = vi.mocked(sendAdminMagicLink).mock.calls[0]?.[1];
    expect(link).toContain("http://localhost:3000/admin/login/verify#t=");
    expect(insertLoginChallenge).toHaveBeenCalledOnce();

    const jti = "33333333-3333-4333-8333-333333333333";
    const { token } = issueLoginToken(SECRET, EMAIL, jti);
    const verified = await app.request("/admin/login/verify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token }),
    });
    expect(verified.status).toBe(200);
    expect(consumeLoginChallenge).toHaveBeenCalledWith(jti, EMAIL);
    const cookie = verified.headers.get("set-cookie") ?? "";
    expect(cookie).toContain("angles_admin=");
    expect(cookie).toContain("HttpOnly");
    expect(cookie).toContain("Path=/api/admin");
    expect(cookie).not.toContain("Secure");
  });

  it("rejects a bad login token", async () => {
    const response = await app.request("/admin/login/verify", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: "not-a-token" }),
    });
    expect(response.status).toBe(401);
    expect(consumeLoginChallenge).not.toHaveBeenCalled();
  });

  it("rejects a session whose email is no longer allowlisted", async () => {
    const response = await app.request("/admin/session", {
      headers: { cookie: sessionCookie("other@example.com") },
    });
    expect(response.status).toBe(403);
  });

  it("requires the proxy header when the secret is set", async () => {
    process.env.ADMIN_PROXY_SECRET = PROXY;
    const blocked = await authed("/admin/session");
    expect(blocked.status).toBe(401);
    const allowed = await authed("/admin/session", {
      headers: { "x-angles-admin-proxy": PROXY },
    });
    expect(allowed.status).toBe(200);
    expect(await allowed.json()).toEqual({ email: EMAIL });
  });

  it("stays disabled in production without the proxy secret", () => {
    expect(
      readAdminConfig({
        NODE_ENV: "production",
        ADMIN_SESSION_SECRET: SECRET,
        ADMIN_OPERATOR_EMAILS: EMAIL,
      }),
    ).toBeNull();
  });
});

describe("admin report actions", () => {
  it("lists open reports with an excerpt and without the reframes", async () => {
    vi.mocked(listPendingReports).mockResolvedValueOnce([
      {
        cardId: CARD_ID,
        authorId: USER_ID,
        authorInitials: "JM",
        authorSuspended: false,
        isPublic: true,
        firstReportedAt: new Date("2026-10-05T10:00:00.000Z"),
        reasons: { harassment: 2 },
        reportCount: 2,
        thought: "private thought",
        reframes: [{ style: "stoic", reframe: "private answer" }],
      },
    ]);
    const response = await authed("/admin/reports");
    expect(response.status).toBe(200);
    const body = (await response.json()) as { reports: Record<string, unknown>[] };
    expect(body.reports).toEqual([
      {
        cardId: CARD_ID,
        authorId: USER_ID,
        authorInitials: "JM",
        authorSuspended: false,
        isPublic: true,
        firstReportedAt: "2026-10-05T10:00:00.000Z",
        reasons: { harassment: 2 },
        reportCount: 2,
        thoughtExcerpt: "private thought",
      },
    ]);
    expect(JSON.stringify(body)).not.toContain("private answer");
  });

  it("returns the card text on detail", async () => {
    vi.mocked(getCardReview).mockResolvedValueOnce({
      cardId: CARD_ID,
      authorId: USER_ID,
      authorInitials: "JM",
      authorEmail: "author@example.com",
      authorSuspended: true,
      isPublic: false,
      reportCount: 0,
      reasons: {},
      firstReportedAt: null,
      thought: "I keep replaying the interview.",
      reframes: [{ style: "stoic", reframe: "One answer." }],
    });
    const response = await authed(`/admin/reports/${CARD_ID}`);
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      thought: "I keep replaying the interview.",
      reframes: [{ style: "stoic", reframe: "One answer." }],
      authorEmail: "author@example.com",
      firstReportedAt: null,
    });
  });

  it("keeps, hides, publishes, and deletes a card", async () => {
    vi.mocked(resolveCardReports).mockResolvedValue("ok");
    vi.mocked(publishHiddenCard).mockResolvedValue("ok");
    vi.mocked(deleteReportedCard).mockResolvedValue(true);
    const keep = await authed(`/admin/reports/${CARD_ID}/keep`, { method: "POST" });
    const hide = await authed(`/admin/reports/${CARD_ID}/hide`, { method: "POST" });
    const published = await authed(`/admin/reports/${CARD_ID}/publish`, { method: "POST" });
    const deleted = await authed(`/admin/reports/${CARD_ID}/delete`, { method: "POST" });
    expect(keep.status).toBe(200);
    expect(hide.status).toBe(200);
    expect(published.status).toBe(200);
    expect(deleted.status).toBe(200);
    expect(resolveCardReports).toHaveBeenNthCalledWith(1, CARD_ID, "kept");
    expect(resolveCardReports).toHaveBeenNthCalledWith(2, CARD_ID, "hidden");
    expect(publishHiddenCard).toHaveBeenCalledWith(CARD_ID);
    expect(deleteReportedCard).toHaveBeenCalledWith(CARD_ID);
  });

  it("returns not found when publishing a missing card", async () => {
    vi.mocked(publishHiddenCard).mockResolvedValue("not_found");
    const response = await authed(`/admin/reports/${CARD_ID}/publish`, { method: "POST" });
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "No such card", code: "NOT_FOUND" });
  });

  it("suspends and restores publishing", async () => {
    vi.mocked(suspendPublishing).mockResolvedValue("ok");
    vi.mocked(restorePublishing).mockResolvedValue("ok");
    vi.mocked(getAuthorReview).mockResolvedValue({
      userId: USER_ID,
      email: "author@example.com",
      initials: "JM",
      publishingSuspended: false,
      publicCardCount: 3,
    });
    const author = await authed(`/admin/users/${USER_ID}`);
    const suspended = await authed(`/admin/users/${USER_ID}/suspend`, { method: "POST" });
    const restored = await authed(`/admin/users/${USER_ID}/unsuspend`, { method: "POST" });
    expect(author.status).toBe(200);
    expect(await author.json()).toMatchObject({ email: "author@example.com", publicCardCount: 3 });
    expect(suspended.status).toBe(200);
    expect(restored.status).toBe(200);
    expect(suspendPublishing).toHaveBeenCalledWith(USER_ID);
    expect(restorePublishing).toHaveBeenCalledWith(USER_ID);
  });

  it("rejects search and the overview without a session", async () => {
    const summary = await app.request("/admin/reports/summary");
    const found = await app.request("/admin/search?q=dad");
    expect(summary.status).toBe(401);
    expect(found.status).toBe(401);
    expect(summarizeReports).not.toHaveBeenCalled();
    expect(searchAdmin).not.toHaveBeenCalled();
  });

  it("returns the overview counts", async () => {
    vi.mocked(summarizeReports).mockResolvedValueOnce({
      openCount: 3,
      privateCount: 1,
      suspendedAuthorCount: 1,
      reviewedCount: 4,
      reasons: {
        spam: 0,
        harassment: 2,
        hate: 0,
        sexual: 0,
        illegal: 0,
        personal_data: 1,
        other: 0,
      },
    });
    const response = await authed("/admin/reports/summary");
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ openCount: 3, reasons: { harassment: 2, personal_data: 1 } });
  });

  it("searches by a thought fragment and by email", async () => {
    vi.mocked(searchAdmin).mockResolvedValueOnce({
      cards: [
        {
          cardId: CARD_ID,
          thought: "My kid asked why I am home.",
          isPublic: true,
          authorId: USER_ID,
          authorInitials: "JM",
          authorEmail: "author@example.com",
          authorSuspended: false,
          reportCount: 1,
          reasons: { personal_data: 1 },
        },
      ],
      users: [],
    });
    const byThought = await authed("/admin/search?q=home");
    expect(byThought.status).toBe(200);
    expect(searchAdmin).toHaveBeenCalledWith("home");
    expect(await byThought.json()).toMatchObject({
      cards: [{ thoughtExcerpt: "My kid asked why I am home.", authorEmail: "author@example.com" }],
    });

    vi.mocked(searchAdmin).mockResolvedValueOnce({
      cards: [],
      users: [
        {
          userId: USER_ID,
          email: "author@example.com",
          initials: "JM",
          publishingSuspended: false,
          publicCardCount: 6,
        },
      ],
    });
    const byEmail = await authed("/admin/search?q=author@example.com");
    expect(byEmail.status).toBe(200);
    expect(searchAdmin).toHaveBeenCalledWith("author@example.com");
    expect(await byEmail.json()).toMatchObject({ users: [{ email: "author@example.com", publicCardCount: 6 }] });
  });

  it("lists reviewed decisions and an author's public cards", async () => {
    vi.mocked(listReviewedReports).mockResolvedValueOnce([
      {
        cardId: CARD_ID,
        authorId: USER_ID,
        authorInitials: "JM",
        authorSuspended: false,
        isPublic: false,
        thought: "A reviewed thought.",
        resolution: "hidden",
        reviewedAt: new Date("2026-10-05T12:00:00.000Z"),
        reasons: { spam: 1 },
      },
    ]);
    vi.mocked(getAuthorReview).mockResolvedValueOnce({
      userId: USER_ID,
      email: "author@example.com",
      initials: "JM",
      publishingSuspended: false,
      publicCardCount: 1,
    });
    vi.mocked(listAuthorPublicCards).mockResolvedValueOnce([
      { cardId: CARD_ID, thought: "Still public.", createdAt: new Date("2026-10-01T00:00:00.000Z") },
    ]);
    const reviewed = await authed("/admin/reports/reviewed");
    const cards = await authed(`/admin/users/${USER_ID}/cards`);
    expect(reviewed.status).toBe(200);
    expect(await reviewed.json()).toMatchObject({
      reports: [{ resolution: "hidden", thoughtExcerpt: "A reviewed thought." }],
    });
    expect(cards.status).toBe(200);
    expect(await cards.json()).toMatchObject({ cards: [{ thoughtExcerpt: "Still public." }] });
  });

  it("rejects a card id that is not a UUID", async () => {
    const response = await authed("/admin/reports/not-a-uuid/hide", { method: "POST" });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: "VALIDATION_ERROR" });
    expect(resolveCardReports).not.toHaveBeenCalled();
  });
});
