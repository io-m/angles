/**
 * The house account's curated cards: `house/thoughts.json` through the real cook, signed,
 * moderated, and posted public as From Angles. They fill the stack once a visit's community
 * cards are used up.
 *
 *   pnpm db:house-cards                 post every thought (refuses if house cards exist)
 *   pnpm db:house-cards --append        post again next to the ones already there
 *   pnpm db:house-cards --replace       delete the house cards (and every save of them) first
 *   pnpm db:house-cards --only=a,b      only these thought ids
 *   pnpm db:house-cards --limit=5       stop after five posts
 *
 * Production (inside Railway, after the script is in the deployed image):
 *
 *   railway ssh --service api --environment production \
 *     "cd /app && HOUSE_CARDS=yes node dist/scripts/houseCards.js"
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { count, eq } from "drizzle-orm";
import { createCard } from "../db/cards.js";
import { closePool, getDb } from "../db/client.js";
import { cards, users } from "../db/schema.js";
import { runAsOwner } from "../lib/authStub.js";
import { runCook } from "../lib/cook.js";
import { signCook, signResult, verifyCook } from "../lib/cookSignature.js";
import { COOK_DEADLINE_MS, modelsForStep, type LlmModelId } from "../lib/llmClient.js";
import { loadLocalEnvFile } from "../lib/loadEnv.js";
import { moderatePublicCard } from "../lib/publicModeration.js";
import { runWithStyleSet, STYLE_SET_2 } from "../lib/styleSet.js";
import { CATEGORIES } from "../types/index.js";
import { assertCommunitySeedAllowed } from "./seedCommunityGuard.js";

type HouseThought = { id: string; area: string; text: string };

const HOUSE_EMAIL = "house@angles.invalid";

function assertHouseCardsAllowed(environment: NodeJS.ProcessEnv = process.env): void {
  if (environment.HOUSE_CARDS?.trim().toLowerCase() === "yes") {
    return;
  }
  assertCommunitySeedAllowed(environment);
}

function flag(argv: readonly string[], name: string): string | undefined {
  return argv.find((argument) => argument.startsWith(`--${name}=`))?.slice(`--${name}=`.length).trim();
}

function loadThoughts(): HouseThought[] {
  const path = resolve(process.cwd(), "house/thoughts.json");
  const thoughts = JSON.parse(readFileSync(path, "utf8")) as HouseThought[];
  const ids = new Set<string>();
  for (const thought of thoughts) {
    if (!thought.id || !thought.text?.trim() || ids.has(thought.id)) {
      throw new Error(`house/thoughts.json: missing or repeated id ${thought.id}`);
    }
    if (!(CATEGORIES as readonly string[]).includes(thought.area)) {
      throw new Error(`house/thoughts.json: ${thought.id} has unknown area ${thought.area}`);
    }
    ids.add(thought.id);
  }
  return thoughts;
}

/** The one house account, made on first run. It never signs in. */
async function houseAccount(): Promise<string> {
  const db = getDb();
  const [existing] = await db.select({ id: users.id }).from(users).where(eq(users.kind, "house"));
  if (existing) {
    return existing.id;
  }
  const [created] = await db
    .insert(users)
    .values({
      name: "Angles",
      email: HOUSE_EMAIL,
      emailVerified: true,
      initials: "A",
      kind: "house",
      termsAcceptedAt: new Date(),
      notifyFollows: false,
    })
    .returning({ id: users.id });
  if (!created) {
    throw new Error("could not create the house account");
  }
  return created.id;
}

type Outcome = "posted" | "continue" | "safety" | "moderation";

async function postThought(houseId: string, thought: HouseThought): Promise<Outcome> {
  let answeredBy: LlmModelId = modelsForStep("writer").primary;
  const outcome = await runWithStyleSet(STYLE_SET_2, () =>
    runCook({
      text: thought.text,
      followUps: [],
      catalog: STYLE_SET_2,
      deadlineAt: Date.now() + COOK_DEADLINE_MS,
      onAnsweredBy: (model) => {
        answeredBy = model;
      },
    }),
  );
  if (outcome.kind === "continue") {
    return "continue";
  }
  const { decision, results } = outcome;
  if (decision.meta.safety !== "none") {
    return "safety";
  }

  const cook = {
    ownerId: houseId,
    thought: decision.thought,
    thoughtOriginal: decision.thoughtOriginal,
    model: answeredBy,
    meta: decision.meta,
  };
  const signature = signCook(cook);
  const signedResults = results.map((item) => ({
    ...item,
    signature: signResult(houseId, decision.thought, item.style, item.reframe, item.reframeOriginal),
  }));
  if (!verifyCook({ ...cook, signature, results: signedResults })) {
    throw new Error(`${thought.id}: the cook did not verify`);
  }

  return runAsOwner(houseId, async () => {
    const allowed = await moderatePublicCard({
      thought: decision.thought,
      reframes: results.map((item) => item.reframe),
    });
    if (!allowed) {
      return "moderation" as const;
    }
    await createCard(
      {
        thought: decision.thought,
        thoughtOriginal: decision.thoughtOriginal,
        results,
        meta: decision.meta,
        model: answeredBy,
        // The decision ranks the styles best first; the first one opens the card.
        spotlightStyle: results[0]!.style,
        isPublic: true,
      },
      { cookSignature: signature },
    );
    return "posted" as const;
  });
}

async function main(): Promise<void> {
  loadLocalEnvFile();
  assertHouseCardsAllowed();
  const argv = process.argv.slice(2);
  const replace = argv.includes("--replace");
  const append = argv.includes("--append");
  const only = flag(argv, "only")?.split(",").map((id) => id.trim()).filter(Boolean);
  const limitRaw = flag(argv, "limit");
  const limit = limitRaw ? Number.parseInt(limitRaw, 10) : Number.POSITIVE_INFINITY;
  if (limitRaw && (!Number.isFinite(limit) || limit < 1)) {
    throw new Error("invalid --limit");
  }

  let thoughts = loadThoughts();
  if (only) {
    const unknown = only.filter((id) => !thoughts.some((thought) => thought.id === id));
    if (unknown.length > 0) {
      throw new Error(`unknown thought ids: ${unknown.join(", ")}`);
    }
    thoughts = thoughts.filter((thought) => only.includes(thought.id));
  }

  const db = getDb();
  const houseId = await houseAccount();
  const [{ value: existing } = { value: 0 }] = await db
    .select({ value: count() })
    .from(cards)
    .where(eq(cards.userId, houseId));
  if (existing > 0 && replace) {
    await db.delete(cards).where(eq(cards.userId, houseId));
    process.stderr.write(`Deleted ${existing} house card(s).\n`);
  } else if (existing > 0 && !append) {
    throw new Error(`the house account already has ${existing} card(s); pass --append or --replace`);
  }

  const tally: Record<Outcome, number> = { posted: 0, continue: 0, safety: 0, moderation: 0 };
  const failed: string[] = [];
  for (const thought of thoughts) {
    if (tally.posted >= limit) {
      break;
    }
    process.stderr.write(`[${tally.posted + 1}] ${thought.id} (${thought.area})… `);
    try {
      const outcome = await postThought(houseId, thought);
      tally[outcome] += 1;
      process.stderr.write(`${outcome}\n`);
    } catch (error) {
      failed.push(thought.id);
      process.stderr.write(`failed: ${error instanceof Error ? error.message : String(error)}\n`);
    }
  }

  console.log(
    `House cards: ${tally.posted} posted, ${tally.continue} asked a question, ${tally.safety} flagged, ` +
      `${tally.moderation} held by moderation, ${failed.length} failed.`,
  );
  if (failed.length > 0) {
    console.log(`Retry with --append --only=${failed.join(",")}`);
    process.exitCode = 1;
  }
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
