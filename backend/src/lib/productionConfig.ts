import { X509Certificate } from "node:crypto";
import {
  PUBLIC_LLM_MODELS,
  type PublicLlmModelId,
} from "./meteringPolicy.js";

type Environment = NodeJS.ProcessEnv;

const PUBLIC_MODEL_KEYS: Record<PublicLlmModelId, string> = {
  "mistral-small-latest": "MISTRAL_API_KEY",
  "deepseek-flash": "DEEPSEEK_API_KEY",
  "gemini-3.8-flash": "GEMINI_API_KEY",
};

const PLACEHOLDER_PATTERN =
  /^(?:missing|placeholder|change[-_ ]?me|replace[-_ ]?me|your[-_ ].+|example(?:[-_ ].*)?|<.+>)$/i;

function configuredValue(
  environment: Environment,
  name: string,
  errors: string[],
): string | undefined {
  const value = environment[name]?.trim();
  if (!value) {
    errors.push(`${name} is required`);
    return undefined;
  }
  return value;
}

function nonPlaceholderValue(
  environment: Environment,
  name: string,
  errors: string[],
): string | undefined {
  const value = configuredValue(environment, name, errors);
  if (value && PLACEHOLDER_PATTERN.test(value)) {
    errors.push(`${name} must not be a placeholder`);
    return undefined;
  }
  return value;
}

function requireExactValue(
  environment: Environment,
  name: string,
  expected: string,
  errors: string[],
): void {
  if (environment[name]?.trim().toLowerCase() !== expected) {
    errors.push(`${name} must be ${expected}`);
  }
}

function parseUrl(
  raw: string,
  name: string,
  protocols: readonly string[],
  errors: string[],
): URL | undefined {
  try {
    const url = new URL(raw);
    if (!protocols.includes(url.protocol) || !url.hostname) {
      throw new Error("invalid URL");
    }
    return url;
  } catch {
    errors.push(`${name} must be a valid ${protocols.join(" or ")} URL`);
    return undefined;
  }
}

function certificateValues(raw: string): unknown {
  if (raw.startsWith("[")) {
    return JSON.parse(raw) as unknown;
  }
  return raw.split(",").map((value) => value.trim());
}

function validateAppleRootCertificates(raw: string, errors: string[]): void {
  try {
    const values = certificateValues(raw);
    if (
      !Array.isArray(values) ||
      values.length === 0 ||
      values.some((value) => typeof value !== "string" || value.trim().length === 0)
    ) {
      throw new Error("empty certificate list");
    }
    for (const value of values) {
      const encoded = (value as string).trim();
      if (
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
          encoded,
        )
      ) {
        throw new Error("invalid base64");
      }
      const der = Buffer.from(encoded, "base64");
      if (der.length === 0) {
        throw new Error("empty certificate");
      }
      new X509Certificate(der);
    }
  } catch {
    errors.push(
      "APPLE_ROOT_CERTIFICATES_BASE64 must contain valid base64 DER certificates",
    );
  }
}

function validateBucketName(bucket: string, errors: string[]): void {
  const valid =
    bucket.length >= 3 &&
    bucket.length <= 63 &&
    /^[a-z0-9][a-z0-9.-]*[a-z0-9]$/.test(bucket) &&
    !bucket.includes("..") &&
    !/^\d{1,3}(?:\.\d{1,3}){3}$/.test(bucket);
  if (!valid) {
    errors.push("BUCKET must be a valid S3 bucket name");
  }
}

export function assertProductionConfiguration(
  environment: Environment = process.env,
): void {
  if (environment.NODE_ENV?.trim().toLowerCase() !== "production") {
    return;
  }

  const errors: string[] = [];

  const databaseUrl = configuredValue(environment, "DATABASE_URL", errors);
  if (databaseUrl) {
    parseUrl(databaseUrl, "DATABASE_URL", ["postgres:", "postgresql:"], errors);
  }

  const authUrl = configuredValue(environment, "BETTER_AUTH_URL", errors);
  if (authUrl) {
    parseUrl(authUrl, "BETTER_AUTH_URL", ["https:"], errors);
  }

  nonPlaceholderValue(environment, "APPLE_CLIENT_SECRET", errors);
  requireExactValue(
    environment,
    "SUBSCRIPTION_ENFORCEMENT",
    "required",
    errors,
  );
  requireExactValue(environment, "USAGE_ENFORCEMENT", "required", errors);

  const meteringKey = configuredValue(environment, "METERING_HMAC_KEY", errors);
  if (meteringKey && meteringKey.length < 32) {
    errors.push("METERING_HMAC_KEY must be at least 32 characters");
  }

  const certificates = configuredValue(
    environment,
    "APPLE_ROOT_CERTIFICATES_BASE64",
    errors,
  );
  if (certificates) {
    validateAppleRootCertificates(certificates, errors);
  }

  const appId = configuredValue(environment, "APPLE_APP_ID", errors);
  if (appId) {
    const parsed = Number(appId);
    if (!Number.isSafeInteger(parsed) || parsed <= 0) {
      errors.push("APPLE_APP_ID must be a positive integer");
    }
  }

  for (const model of PUBLIC_LLM_MODELS) {
    nonPlaceholderValue(environment, PUBLIC_MODEL_KEYS[model], errors);
  }

  const bucket = configuredValue(environment, "BUCKET", errors);
  if (bucket) {
    validateBucketName(bucket, errors);
  }
  nonPlaceholderValue(environment, "ACCESS_KEY_ID", errors);
  nonPlaceholderValue(environment, "SECRET_ACCESS_KEY", errors);

  const region = configuredValue(environment, "REGION", errors);
  if (region && !/^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(region)) {
    errors.push("REGION must be a valid region identifier");
  }

  const endpoint = configuredValue(environment, "ENDPOINT", errors);
  if (endpoint) {
    parseUrl(endpoint, "ENDPOINT", ["https:"], errors);
  }

  const urlStyle = configuredValue(environment, "S3_URL_STYLE", errors);
  if (urlStyle && urlStyle !== "virtual-hosted" && urlStyle !== "path") {
    errors.push("S3_URL_STYLE must be virtual-hosted or path");
  }

  if (errors.length > 0) {
    throw new Error(`Invalid production configuration: ${errors.join("; ")}`);
  }
}
