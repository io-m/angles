import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts"],
    env: {
      COOK_SIGNING_KEY: "test-cook-signing-key-0123456789abcdef",
    },
  },
});
