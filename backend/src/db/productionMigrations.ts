import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/postgres-js";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import { loadLocalEnvFile } from "../lib/loadEnv.js";

const MIGRATION_LOCK_SQL =
  "select pg_advisory_lock(hashtextextended('angles:production-migrations', 0))";
const MIGRATION_UNLOCK_SQL =
  "select pg_advisory_unlock(hashtextextended('angles:production-migrations', 0))";

export function productionMigrationsFolder(
  moduleUrl: string = import.meta.url,
): string {
  return fileURLToPath(new URL("../../drizzle/", moduleUrl));
}

type MigrationClient = Pick<postgres.Sql, "unsafe" | "end">;

const EXISTING_OBJECT_NOTICE_CODES = new Set(["42P06", "42P07"]);

export function logPostgresNotice(notice: postgres.Notice): void {
  if (EXISTING_OBJECT_NOTICE_CODES.has(notice.code)) {
    return;
  }
  console.log(notice);
}

export async function runMigrationWithLock(
  client: MigrationClient,
  migrateDatabase: () => Promise<void>,
): Promise<void> {
  let locked = false;
  let failure: unknown;
  try {
    await client.unsafe(MIGRATION_LOCK_SQL);
    locked = true;
    await migrateDatabase();
  } catch (error) {
    failure = error;
  } finally {
    if (locked) {
      try {
        await client.unsafe(MIGRATION_UNLOCK_SQL);
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      await client.end({ timeout: 5 });
    } catch (error) {
      failure ??= error;
    }
  }
  if (failure) {
    throw failure;
  }
}

export async function runProductionMigrations(): Promise<void> {
  try {
    loadLocalEnvFile();
    const url = process.env.DATABASE_URL;
    if (!url) {
      throw new Error("DATABASE_URL is required");
    }
    const client = postgres(url, {
      max: 1,
      idle_timeout: 20,
      connect_timeout: 10,
      onnotice: logPostgresNotice,
    });
    await runMigrationWithLock(client, () =>
      migrate(drizzle(client), {
        migrationsFolder: productionMigrationsFolder(),
      }),
    );
  } catch (error) {
    const code =
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      typeof error.code === "string"
        ? error.code
        : undefined;
    console.error("database_migration_failed", { code });
    throw new Error("Database migrations failed", { cause: error });
  }
}
