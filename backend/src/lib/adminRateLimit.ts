const hits = new Map<string, number[]>();

export const ADMIN_RATE_WINDOW_MS = 60 * 60 * 1000;
export const LOGIN_EMAIL_LIMIT = 5;
export const LOGIN_IP_LIMIT = 30;
export const MUTATION_LIMIT = 60;

/** Test hook. The limiter is in-memory and lives with the API process. */
export function resetAdminRateLimits(): void {
  hits.clear();
}

/** True when this key is still under `limit` inside the window. */
export function allowAdminRate(
  key: string,
  limit: number,
  windowMs: number,
  now = Date.now(),
): boolean {
  const windowStart = now - windowMs;
  const recent = (hits.get(key) ?? []).filter((at) => at > windowStart);
  if (recent.length >= limit) {
    hits.set(key, recent);
    return false;
  }
  recent.push(now);
  hits.set(key, recent);
  return true;
}
