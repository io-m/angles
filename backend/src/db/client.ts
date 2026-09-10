import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { loadLocalEnvFile } from "../lib/loadEnv.js";
import * as schema from "./schema.js";

const POOL_MAX = 8;

let sql: postgres.Sql | undefined;
let db: ReturnType<typeof drizzle<typeof schema>> | undefined;

export class DbError extends Error {
  readonly code?: string;

  constructor(message: string, code?: string) {
    super(message);
    this.name = "DbError";
    this.code = code;
  }
}

export function wrapDbError(error: unknown, operation: string): DbError {
  const code =
    typeof error === "object" && error !== null && "code" in error && typeof error.code === "string"
      ? error.code
      : undefined;
  console.error("db_error", { code, operation });
  return new DbError("Database error", code);
}

export function getSql(): postgres.Sql {
  if (!sql) {
    loadLocalEnvFile();
    const url = process.env.DATABASE_URL;
    if (!url) {
      throw new Error("DATABASE_URL is required");
    }
    sql = postgres(url, { max: POOL_MAX, idle_timeout: 20, connect_timeout: 10 });
  }
  return sql;
}

export function getDb() {
  if (!db) {
    db = drizzle(getSql(), { schema });
  }
  return db;
}

export async function closePool(): Promise<void> {
  if (sql) {
    await sql.end({ timeout: 5 });
    sql = undefined;
    db = undefined;
  }
}

export async function probeDatabase(): Promise<"ok" | "down"> {
  try {
    if (!process.env.DATABASE_URL) {
      return "down";
    }
    await getSql()`SELECT 1`;
    return "ok";
  } catch {
    return "down";
  }
}

type DrizzleJournal = {
  entries: { tag: string }[];
};

export async function assertSchemaCurrent(): Promise<void> {
  const behind = new Error("Database schema is behind. Run pnpm db:migrate");
  const journalPath = resolve(process.cwd(), "drizzle/meta/_journal.json");
  let journal: DrizzleJournal;
  try {
    journal = JSON.parse(readFileSync(journalPath, "utf8")) as DrizzleJournal;
  } catch {
    throw behind;
  }

  const expected = journal.entries.length;
  if (expected === 0) {
    return;
  }

  try {
    const rows = (await getSql().unsafe(
      "SELECT COUNT(*)::text AS count FROM drizzle.__drizzle_migrations",
    )) as unknown as { count: string }[];
    const applied = Number(rows[0]?.count ?? 0);
    if (applied < expected) {
      throw behind;
    }
  } catch (error) {
    if (error === behind) {
      throw error;
    }
    const code =
      typeof error === "object" && error !== null && "code" in error && typeof error.code === "string"
        ? error.code
        : undefined;
    console.error("schema_check_failed", { code });
    throw behind;
  }
}
