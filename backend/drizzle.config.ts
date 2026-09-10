import { defineConfig } from "drizzle-kit";
import { loadLocalEnvFile } from "./src/lib/loadEnv.ts";

loadLocalEnvFile();

const databaseUrl =
  process.env.DATABASE_URL ?? "postgres://angles:angles@127.0.0.1:5433/angles";

export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: {
    url: databaseUrl,
  },
});
