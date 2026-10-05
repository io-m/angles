import { createHmac, timingSafeEqual } from "node:crypto";

const MIN_SECRET_LENGTH = 32;
const SESSION_TTL_SECONDS = 12 * 60 * 60;
const LOGIN_TTL_MS = 15 * 60 * 1000;
export const ADMIN_COOKIE = "angles_admin";
export const ADMIN_PROXY_HEADER = "x-angles-admin-proxy";

export type AdminConfig = {
  emails: ReadonlySet<string>;
  sessionSecret: string;
  /** Null when the header is not required (local and tests). */
  proxySecret: string | null;
  appOrigin: string;
  secureCookie: boolean;
};

type LoginClaims = {
  v: 1;
  purpose: "login";
  email: string;
  exp: number;
  jti: string;
};

type SessionClaims = {
  v: 1;
  purpose: "session";
  email: string;
  exp: number;
};

function parseEmails(raw: string | undefined): Set<string> {
  const emails = new Set<string>();
  for (const part of (raw ?? "").split(",")) {
    const email = part.trim().toLowerCase();
    if (email.length > 0) {
      emails.add(email);
    }
  }
  return emails;
}

/**
 * Null when operator login cannot run. Production also requires the proxy secret so the
 * public API does not accept `/admin` from anywhere except the site worker.
 */
export function readAdminConfig(env: NodeJS.ProcessEnv = process.env): AdminConfig | null {
  const sessionSecret = env.ADMIN_SESSION_SECRET?.trim() ?? "";
  const emails = parseEmails(env.ADMIN_OPERATOR_EMAILS);
  const proxy = env.ADMIN_PROXY_SECRET?.trim() ?? "";
  const production = env.NODE_ENV?.trim().toLowerCase() === "production";
  if (sessionSecret.length < MIN_SECRET_LENGTH || emails.size === 0) {
    return null;
  }
  if (proxy.length > 0 && proxy.length < MIN_SECRET_LENGTH) {
    return null;
  }
  if (production && proxy.length < MIN_SECRET_LENGTH) {
    return null;
  }
  const appOrigin = (env.ADMIN_APP_ORIGIN?.trim() || "https://useangles.app").replace(/\/$/, "");
  return {
    emails,
    sessionSecret,
    proxySecret: proxy.length >= MIN_SECRET_LENGTH ? proxy : null,
    appOrigin,
    secureCookie: appOrigin.startsWith("https://"),
  };
}

export function proxyHeaderOk(header: string | undefined, config: AdminConfig): boolean {
  if (!config.proxySecret) {
    return true;
  }
  return secretsMatch(config.proxySecret, header);
}

export function issueLoginToken(
  secret: string,
  email: string,
  jti: string,
  now = Date.now(),
): { token: string; expiresAt: Date } {
  const expiresAt = new Date(now + LOGIN_TTL_MS);
  const claims: LoginClaims = {
    v: 1,
    purpose: "login",
    email,
    exp: Math.floor(expiresAt.getTime() / 1000),
    jti,
  };
  return { token: sign(secret, claims), expiresAt };
}

export function readLoginToken(
  secret: string,
  token: string,
  now = Date.now(),
): { email: string; jti: string } | null {
  const claims = open(secret, token);
  if (!isLoginClaims(claims) || !fresh(claims.exp, now)) {
    return null;
  }
  return { email: claims.email, jti: claims.jti };
}

export function issueSessionToken(
  secret: string,
  email: string,
  now = Date.now(),
): { token: string; maxAge: number } {
  const claims: SessionClaims = {
    v: 1,
    purpose: "session",
    email,
    exp: Math.floor(now / 1000) + SESSION_TTL_SECONDS,
  };
  return { token: sign(secret, claims), maxAge: SESSION_TTL_SECONDS };
}

export function readSessionEmail(secret: string, token: string, now = Date.now()): string | null {
  const claims = open(secret, token);
  if (!isSessionClaims(claims) || !fresh(claims.exp, now)) {
    return null;
  }
  return claims.email;
}

export function sessionTokenFromCookie(header: string | undefined): string | null {
  if (!header) {
    return null;
  }
  for (const part of header.split(";")) {
    const trimmed = part.trim();
    const eq = trimmed.indexOf("=");
    if (eq <= 0) {
      continue;
    }
    if (trimmed.slice(0, eq) === ADMIN_COOKIE) {
      const value = trimmed.slice(eq + 1);
      return value.length > 0 ? value : null;
    }
  }
  return null;
}

export function sessionCookie(token: string, maxAge: number, secure: boolean): string {
  return cookieHeader(token, maxAge, secure);
}

export function clearSessionCookie(secure: boolean): string {
  return cookieHeader("", 0, secure);
}

export function magicLinkUrl(appOrigin: string, token: string): string {
  return `${appOrigin}/admin/login/verify#t=${encodeURIComponent(token)}`;
}

function cookieHeader(token: string, maxAge: number, secure: boolean): string {
  const parts = [
    `${ADMIN_COOKIE}=${token}`,
    "HttpOnly",
    "SameSite=Lax",
    "Path=/api/admin",
    `Max-Age=${maxAge}`,
  ];
  if (secure) {
    parts.push("Secure");
  }
  return parts.join("; ");
}

function sign(secret: string, payload: LoginClaims | SessionClaims): string {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const mac = createHmac("sha256", secret).update(body).digest("base64url");
  return `${body}.${mac}`;
}

function open(secret: string, token: string): unknown {
  const dot = token.indexOf(".");
  if (dot <= 0 || dot !== token.lastIndexOf(".")) {
    return null;
  }
  const body = token.slice(0, dot);
  const mac = token.slice(dot + 1);
  const expected = createHmac("sha256", secret).update(body).digest("base64url");
  if (!secretsMatch(expected, mac)) {
    return null;
  }
  try {
    return JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as unknown;
  } catch {
    return null;
  }
}

function fresh(exp: number, now: number): boolean {
  return Number.isFinite(exp) && exp * 1000 > now;
}

function isLoginClaims(value: unknown): value is LoginClaims {
  if (!value || typeof value !== "object") {
    return false;
  }
  const claims = value as Partial<LoginClaims>;
  return (
    claims.v === 1 &&
    claims.purpose === "login" &&
    typeof claims.email === "string" &&
    typeof claims.exp === "number" &&
    typeof claims.jti === "string" &&
    claims.jti.length > 0
  );
}

function isSessionClaims(value: unknown): value is SessionClaims {
  if (!value || typeof value !== "object") {
    return false;
  }
  const claims = value as Partial<SessionClaims>;
  return (
    claims.v === 1 &&
    claims.purpose === "session" &&
    typeof claims.email === "string" &&
    typeof claims.exp === "number"
  );
}

function secretsMatch(expected: string, actual: string | undefined): boolean {
  if (actual === undefined) {
    return false;
  }
  const left = Buffer.from(expected);
  const right = Buffer.from(actual);
  return left.length === right.length && timingSafeEqual(left, right);
}
