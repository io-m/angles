/**
 * Which styles the calling app build can decode. Build 30 and older send no header and
 * fail a whole cook on a style they do not know, so every request without it is served
 * the original four: cooks choose among them, and every card is projected onto them.
 */

import { AsyncLocalStorage } from "node:async_hooks";
import type { MiddlewareHandler } from "hono";
import { z } from "zod";
import { STYLES, type Style } from "../types/index.js";

export const STYLE_SET_HEADER = "Angles-Style-Set";

/** What an app that sends no style set header knows. Never shrink it. */
export const LEGACY_STYLES: readonly Style[] = ["stoic", "optimistic", "humorous", "tough_love"];

const EXTENDED_STYLE_SET = "2";

const styleSetContext = new AsyncLocalStorage<readonly Style[]>();

/** The calling app's styles. Outside a request (scripts, the eval) every style. */
export function stylesForRequest(): readonly Style[] {
  return styleSetContext.getStore() ?? STYLES;
}

/** Run `fn` as an app that shows these styles, the way a request does. For tests and scripts. */
export function runWithStyleSet<T>(styles: readonly Style[], fn: () => Promise<T>): Promise<T> {
  return styleSetContext.run(styles, fn);
}

export function isStyleShown(style: Style): boolean {
  return stylesForRequest().includes(style);
}

/** A style at the HTTP boundary: one of the catalog, and one the calling app can show. */
export function shownStyleSchema() {
  return z.enum(STYLES).refine(isStyleShown, { message: "style is not available in this app version" });
}

export const styleSetMiddleware: MiddlewareHandler = async (c, next) => {
  const styles = c.req.header(STYLE_SET_HEADER)?.trim() === EXTENDED_STYLE_SET ? STYLES : LEGACY_STYLES;
  await styleSetContext.run(styles, () => next());
};
