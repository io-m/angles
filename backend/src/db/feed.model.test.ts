import { beforeEach, describe, expect, it, vi } from "vitest";

const { findMany } = vi.hoisted(() => ({
  findMany: vi.fn(async () => []),
}));

vi.mock("./client.js", () => {
  class DbError extends Error {
    readonly code?: string;
    constructor(message: string, code?: string) {
      super(message);
      this.name = "DbError";
      this.code = code;
    }
  }
  return {
    getDb: () => ({ query: { cards: { findMany } } }),
    DbError,
    wrapDbError: (error: unknown) => error,
  };
});

const { listPublicCardsForModel } = await import("./feed.js");

const CARD_A = "22222222-2222-4222-8222-222222222222";

function queryText(value: unknown): string {
  const seen = new WeakSet<object>();
  const parts: string[] = [];
  const visit = (item: unknown): void => {
    if (typeof item === "string" || typeof item === "number" || typeof item === "boolean") {
      parts.push(String(item));
      return;
    }
    if (item instanceof Date) {
      parts.push(item.toISOString());
      return;
    }
    if (item === null || item === undefined || typeof item === "function" || typeof item === "symbol") {
      return;
    }
    if (typeof item !== "object") {
      return;
    }
    if (seen.has(item)) {
      return;
    }
    seen.add(item);
    if (Array.isArray(item)) {
      for (const entry of item) {
        visit(entry);
      }
      return;
    }
    for (const entry of Object.values(item)) {
      visit(entry);
    }
  };
  visit(value);
  return parts.join(" ");
}

describe("listPublicCardsForModel", () => {
  beforeEach(() => {
    findMany.mockClear();
    findMany.mockResolvedValue([]);
  });

  it("keeps private cards out and seeks one model's public index order", async () => {
    await listPublicCardsForModel({ model: "deepseek-flash", limit: 24 });

    expect(findMany).toHaveBeenCalledOnce();
    const query = findMany.mock.calls[0]?.[0] as {
      where: unknown;
      orderBy: unknown;
      limit: number;
    };
    const where = queryText(query.where);
    expect(where).toContain("deepseek-flash");
    expect(where).toContain("is_public");
    expect(queryText(query.orderBy)).toContain("created_at");
    expect(query.limit).toBe(24);
  });

  it("seeks strictly older than the cursor so the boundary card is not repeated", async () => {
    const before = {
      createdAt: new Date("2026-09-10T12:00:00.000Z"),
      id: CARD_A,
    };
    await listPublicCardsForModel({ model: "mistral-small-latest", limit: 10, before });

    const where = queryText((findMany.mock.calls[0]?.[0] as { where: unknown }).where);
    expect(where).toContain("mistral-small-latest");
    expect(where).toContain("2026-09-10T12:00:00.000Z");
    expect(where).toContain(CARD_A);
    expect(where).toContain("<");
  });
});
