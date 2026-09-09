import type { ApiErrorBody } from "../types/index.js";

export function errorBody(error: string, code: string): ApiErrorBody {
  return { error, code };
}
