/**
 * Mint a short-lived Better Auth session for the Simulator demo recording
 * (`demo/make_video.sh`). Local database only.
 *
 *   pnpm --silent demo:session        # prints the bearer token on stdout
 *
 * The demo account has accepted the Terms and spent its taste, so the app goes
 * straight to Home once the Debug Simulator build is launched with
 * `-AnglesDemoEntitled YES`. Credits come from the local development period
 * (`USAGE_ENFORCEMENT` off). Earlier demo sessions are removed each run.
 */
import { randomBytes, randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { closePool, getDb } from "../db/client.js";
import { sessions, users } from "../db/schema.js";
import { loadLocalEnvFile } from "../lib/loadEnv.js";

const DEMO_EMAIL = "demo@angles.local";
const DEMO_NAME = "Angles Demo";
const DEMO_INITIALS = "AD";
const SESSION_TTL_MS = 2 * 60 * 60 * 1000;
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

export function assertDemoSessionAllowed(environment: NodeJS.ProcessEnv = process.env): void {
  if (environment.NODE_ENV?.trim().toLowerCase() === "production") {
    throw new Error("Demo sessions are disabled in production");
  }
  const raw = environment.DATABASE_URL;
  if (!raw) {
    throw new Error("DATABASE_URL is required");
  }
  let host: string;
  try {
    host = new URL(raw).hostname;
  } catch {
    throw new Error("DATABASE_URL is not a valid URL");
  }
  if (!LOCAL_HOSTS.has(host)) {
    throw new Error("Demo sessions only run against a local database");
  }
}

async function main(): Promise<void> {
  loadLocalEnvFile();
  assertDemoSessionAllowed();
  const db = getDb();
  const now = new Date();

  const [user] = await db
    .insert(users)
    .values({
      email: DEMO_EMAIL,
      name: DEMO_NAME,
      emailVerified: true,
      initials: DEMO_INITIALS,
      termsAcceptedAt: now,
      tasteConsumedAt: now,
      tasteCompletedAt: now,
    })
    .onConflictDoUpdate({
      target: users.email,
      set: { name: DEMO_NAME, initials: DEMO_INITIALS, updatedAt: now },
    })
    .returning({ id: users.id, termsAcceptedAt: users.termsAcceptedAt });
  if (!user) {
    throw new Error("Could not create the demo user");
  }
  if (!user.termsAcceptedAt) {
    await db.update(users).set({ termsAcceptedAt: now }).where(eq(users.id, user.id));
  }

  await db.delete(sessions).where(eq(sessions.userId, user.id));
  const token = randomBytes(24).toString("base64url");
  await db.insert(sessions).values({
    id: randomUUID(),
    token,
    userId: user.id,
    expiresAt: new Date(now.getTime() + SESSION_TTL_MS),
    userAgent: "angles-demo-recording",
  });

  process.stdout.write(`${token}\n`);
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
