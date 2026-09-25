export function assertCommunitySeedAllowed(
  environment: NodeJS.ProcessEnv = process.env,
): void {
  if (environment.NODE_ENV?.trim().toLowerCase() === "production") {
    throw new Error("Community seed is disabled in production");
  }
}
