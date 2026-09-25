import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins";
import { getDb } from "./db/client.js";
import { accounts, sessions, users, verifications } from "./db/schema.js";
import { initialsFromDisplayName } from "./lib/avatarUrl.js";

const TEST_AUTH_SECRET = "vitest-better-auth-secret-32chars-min";

function authSecret(): string {
  const secret = process.env.BETTER_AUTH_SECRET;
  if (secret && secret.length >= 32) {
    return secret;
  }
  if (process.env.VITEST === "true") {
    return TEST_AUTH_SECRET;
  }
  throw new Error("BETTER_AUTH_SECRET must be set (at least 32 characters)");
}

function authBaseURL(): string {
  return process.env.BETTER_AUTH_URL ?? "http://127.0.0.1:8787";
}

function initialsForNewUser(name: string, email: string): string {
  const fromName = initialsFromDisplayName(name);
  if (fromName) {
    return fromName;
  }
  const letter = email.trim().charAt(0);
  return letter ? letter.toLocaleUpperCase("en-US") : "?";
}

export function assertBetterAuthSecret(): void {
  authSecret();
}

let cached: ReturnType<typeof createAuth> | undefined;

export function getAuth(): ReturnType<typeof createAuth> {
  if (!cached) {
    cached = createAuth();
  }
  return cached;
}

function createAuth() {
  const appleClientId = process.env.APPLE_CLIENT_ID ?? "app.angles.ios";
  const appleClientSecret = process.env.APPLE_CLIENT_SECRET ?? "missing";

  return betterAuth({
    baseURL: authBaseURL(),
    secret: authSecret(),
    trustedOrigins: [
      authBaseURL(),
      "http://127.0.0.1:8787",
      "http://localhost:8787",
      "http://192.168.0.39:8787",
    ],
    emailAndPassword: { enabled: false },
    socialProviders: {
      apple: {
        clientId: appleClientId,
        clientSecret: appleClientSecret,
        appBundleIdentifier: "app.angles.ios",
      },
    },
    user: {
      additionalFields: {
        initials: {
          type: "string",
          required: true,
          defaultValue: "?",
          input: false,
        },
        avatarKey: {
          type: "string",
          required: false,
          input: false,
        },
        tasteCompletedAt: {
          type: "date",
          required: false,
          input: false,
        },
      },
    },
    database: drizzleAdapter(getDb(), {
      provider: "pg",
      usePlural: true,
      schema: {
        users,
        sessions,
        accounts,
        verifications,
      },
    }),
    plugins: [bearer()],
    advanced: {
      database: {
        generateId: () => crypto.randomUUID(),
      },
      useSecureCookies: authBaseURL().startsWith("https://"),
      // Native URLSession is not a browser. A leftover session cookie without
      // Origin is CSRF-rejected as 403 before Apple's token is even checked.
      disableCSRFCheck: true,
      disableOriginCheck: false,
    },
    databaseHooks: {
      user: {
        create: {
          before: async (user) => ({
            data: {
              ...user,
              initials: initialsForNewUser(user.name ?? "", user.email ?? ""),
            },
          }),
        },
      },
    },
  });
}
