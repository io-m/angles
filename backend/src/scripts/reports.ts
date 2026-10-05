/**
 * Review community reports. The Terms promise review as soon as possible.
 *
 *   pnpm reports                      list cards with open reports, oldest first
 *   pnpm reports hide <cardId>        make it private for good and uphold its reports
 *   pnpm reports keep <cardId>        dismiss its reports; it stays as it is
 *   pnpm reports delete <cardId>      delete the card
 *   pnpm reports suspend <userId>     stop an account publishing; all its cards go private
 *   pnpm reports unsuspend <userId>   let it publish again
 *
 * Production Postgres has no public URL, so the image ships this script and it runs in the API container:
 *   railway ssh --service api --environment production node dist/scripts/reports.js [action] [id]
 */
import { closePool } from "../db/client.js";
import {
  deleteReportedCard,
  listPendingReports,
  resolveCardReports,
  restorePublishing,
  suspendPublishing,
} from "../db/reportReview.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function databaseHost(): string {
  try {
    return new URL(process.env.DATABASE_URL ?? "").host || "unknown";
  } catch {
    return "unknown";
  }
}

function hoursSince(date: Date): string {
  return `${((Date.now() - date.getTime()) / 3_600_000).toFixed(1)}h`;
}

async function listPending(): Promise<void> {
  const pending = await listPendingReports();
  if (pending.length === 0) {
    console.log("No open reports.");
    return;
  }
  for (const card of pending) {
    const reasons = Object.entries(card.reasons)
      .map(([reason, count]) => `${reason} x${count}`)
      .join(", ");
    console.log(`== card ${card.cardId}`);
    console.log(
      `   ${card.reportCount} open report(s): ${reasons}; oldest ${hoursSince(card.firstReportedAt)} ago`,
    );
    console.log(
      `   author ${card.authorId} (${card.authorInitials})${card.authorSuspended ? " SUSPENDED" : ""}; ${card.isPublic ? "public" : "private"}`,
    );
    console.log(`   thought: ${card.thought}`);
    for (const item of card.reframes) {
      console.log(`   ${item.style}: ${item.reframe}`);
    }
    console.log("");
  }
}

function requireId(value: string | undefined, kind: string): string {
  if (!value || !UUID.test(value)) {
    throw new Error(`usage: pnpm reports <action> <${kind}>, where ${kind} is a UUID`);
  }
  return value;
}

async function main(): Promise<void> {
  const [action = "list", target] = process.argv.slice(2);
  console.log(`Database: ${databaseHost()}\n`);
  switch (action) {
    case "list":
      await listPending();
      return;
    case "hide":
    case "keep": {
      const cardId = requireId(target, "cardId");
      const result = await resolveCardReports(cardId, action === "hide" ? "hidden" : "kept");
      console.log(result === "ok" ? `${action === "hide" ? "Hid" : "Kept"} card ${cardId}.` : "No such card.");
      return;
    }
    case "delete": {
      const cardId = requireId(target, "cardId");
      console.log((await deleteReportedCard(cardId)) ? `Deleted card ${cardId}.` : "No such card.");
      return;
    }
    case "suspend":
    case "unsuspend": {
      const userId = requireId(target, "userId");
      const result =
        action === "suspend" ? await suspendPublishing(userId) : await restorePublishing(userId);
      console.log(result === "ok" ? `${action === "suspend" ? "Suspended" : "Restored"} ${userId}.` : "No such user.");
      return;
    }
    default:
      throw new Error(`unknown action "${action}": list, hide, keep, delete, suspend, unsuspend`);
  }
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => closePool());
