import { X509Certificate } from "node:crypto";
import { rootCertificates } from "node:tls";
import { describe, expect, it } from "vitest";
import { assertProductionConfiguration } from "./productionConfig.js";

function validProductionEnvironment(): NodeJS.ProcessEnv {
  const root = rootCertificates[0];
  if (!root) {
    throw new Error("Node did not provide a root certificate for the test");
  }
  const certificate = new X509Certificate(root).raw.toString("base64");
  return {
    NODE_ENV: "production",
    DATABASE_URL: "postgresql://angles:test@db.internal:5432/angles",
    BETTER_AUTH_URL: "https://api.angles.app",
    APPLE_CLIENT_SECRET: "signed-apple-client-secret",
    SUBSCRIPTION_ENFORCEMENT: "required",
    USAGE_ENFORCEMENT: "required",
    METERING_HMAC_KEY: "test-metering-key-at-least-32-characters",
    APPLE_ROOT_CERTIFICATES_BASE64: certificate,
    APPLE_APP_ID: "123456789",
    MISTRAL_API_KEY: "test-mistral-key",
    GEMINI_API_KEY: "test-gemini-key",
    DEEPSEEK_API_KEY: "test-deepseek-key",
    BUCKET: "angles-avatars",
    ACCESS_KEY_ID: "test-access-key",
    SECRET_ACCESS_KEY: "test-secret-access-key",
    REGION: "us-east-1",
    ENDPOINT: "https://storage.example.test",
    S3_URL_STYLE: "virtual-hosted",
  };
}

describe("assertProductionConfiguration", () => {
  it("is permissive outside production", () => {
    expect(() =>
      assertProductionConfiguration({ NODE_ENV: "development" }),
    ).not.toThrow();
  });

  it("accepts a complete production environment without mutating process.env", () => {
    const before = { ...process.env };
    expect(() =>
      assertProductionConfiguration(validProductionEnvironment()),
    ).not.toThrow();
    expect(process.env).toEqual(before);
  });

  it("reports missing production variables without printing values", () => {
    expect(() =>
      assertProductionConfiguration({ NODE_ENV: "production" }),
    ).toThrow(
      /DATABASE_URL is required.*MISTRAL_API_KEY is required.*BUCKET is required/,
    );
  });

  it.each([
    ["DATABASE_URL", "mysql://db.internal/angles", "DATABASE_URL"],
    ["BETTER_AUTH_URL", "http://api.angles.app", "BETTER_AUTH_URL"],
    ["APPLE_CLIENT_SECRET", "placeholder", "APPLE_CLIENT_SECRET"],
    ["SUBSCRIPTION_ENFORCEMENT", "off", "SUBSCRIPTION_ENFORCEMENT"],
    ["USAGE_ENFORCEMENT", "off", "USAGE_ENFORCEMENT"],
    ["METERING_HMAC_KEY", "too-short", "METERING_HMAC_KEY"],
    [
      "APPLE_ROOT_CERTIFICATES_BASE64",
      "not-base64",
      "APPLE_ROOT_CERTIFICATES_BASE64",
    ],
    ["APPLE_APP_ID", "0", "APPLE_APP_ID"],
    ["MISTRAL_API_KEY", "change-me", "MISTRAL_API_KEY"],
    ["GEMINI_API_KEY", "missing", "GEMINI_API_KEY"],
    ["DEEPSEEK_API_KEY", "<key>", "DEEPSEEK_API_KEY"],
    ["BUCKET", "Invalid_Bucket", "BUCKET"],
    ["ACCESS_KEY_ID", "replace-me", "ACCESS_KEY_ID"],
    ["SECRET_ACCESS_KEY", "your-secret", "SECRET_ACCESS_KEY"],
    ["REGION", "US EAST 1", "REGION"],
    ["ENDPOINT", "http://storage.example.test", "ENDPOINT"],
    ["S3_URL_STYLE", "auto", "S3_URL_STYLE"],
  ])("rejects invalid %s", (name, value, expectedMessage) => {
    const environment = validProductionEnvironment();
    environment[name] = value;
    expect(() => assertProductionConfiguration(environment)).toThrow(
      expectedMessage,
    );
  });
});
