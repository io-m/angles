import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";
import {
  logPostgresNotice,
  productionMigrationsFolder,
  runMigrationWithLock,
} from "./productionMigrations.js";

describe("production migrations packaging", () => {
  it("resolves the packaged drizzle folder from source and build locations", () => {
    const sourceUrl = new URL("./productionMigrations.js", import.meta.url).href;
    const buildUrl = new URL("../../dist/db/productionMigrations.js", import.meta.url)
      .href;
    const expected = resolve(process.cwd(), "drizzle");

    expect(productionMigrationsFolder(sourceUrl)).toBe(`${expected}/`);
    expect(productionMigrationsFolder(buildUrl)).toBe(`${expected}/`);
  });

  it("contains the journal and every migration SQL file it names", () => {
    const folder = productionMigrationsFolder();
    const journal = JSON.parse(
      readFileSync(resolve(folder, "meta/_journal.json"), "utf8"),
    ) as { entries: Array<{ tag: string }> };

    expect(journal.entries.length).toBeGreaterThan(0);
    for (const entry of journal.entries) {
      expect(existsSync(resolve(folder, `${entry.tag}.sql`))).toBe(true);
    }
  });

  it("holds one session lock and always unlocks and closes its dedicated client", async () => {
    const unsafe = vi.fn(async (_statement: string) => []);
    const end = vi.fn(async () => undefined);
    const migrateDatabase = vi.fn(async () => {
      expect(unsafe).toHaveBeenCalledTimes(1);
    });

    await runMigrationWithLock({ unsafe, end } as never, migrateDatabase);

    expect(migrateDatabase).toHaveBeenCalledOnce();
    expect(unsafe.mock.calls.map(([statement]) => statement)).toEqual([
      expect.stringContaining("pg_advisory_lock"),
      expect.stringContaining("pg_advisory_unlock"),
    ]);
    expect(end).toHaveBeenCalledWith({ timeout: 5 });
  });

  it("drops already-exists schema notices and keeps other notices", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => undefined);
    const notice = {
      severity_local: "NOTICE",
      severity: "NOTICE",
      message: "already exists, skipping",
      file: "schemacmds.c",
      line: "132",
      routine: "CreateSchemaCommand",
    };

    logPostgresNotice({ ...notice, code: "42P06" });
    logPostgresNotice({ ...notice, code: "42P07" });
    expect(log).not.toHaveBeenCalled();

    logPostgresNotice({ ...notice, code: "01000", message: "unexpected notice" });
    expect(log).toHaveBeenCalledOnce();
    log.mockRestore();
  });

  it("unlocks and closes when migration fails", async () => {
    const unsafe = vi.fn(async (_statement: string) => []);
    const end = vi.fn(async () => undefined);
    const failure = new Error("migration failed");

    await expect(
      runMigrationWithLock(
        { unsafe, end } as never,
        async () => {
          throw failure;
        },
      ),
    ).rejects.toBe(failure);

    expect(unsafe).toHaveBeenCalledTimes(2);
    expect(end).toHaveBeenCalledOnce();
  });
});
