import type { ApiErrorBody } from "../types/index.js";

export function errorBody(error: string, code: string): ApiErrorBody {
  return { error, code };
}

export function validationErrorMessage(error: { issues: { message: string }[] }): string {
  const first = error.issues[0];
  return first?.message ?? "Invalid request";
}
