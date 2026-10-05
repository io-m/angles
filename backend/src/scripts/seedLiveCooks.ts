/**
 * Live LLM cooks → public cards for one existing account (real Mistral/OpenAI pipeline).
 *
 *   pnpm db:seed-live-cooks --email=you@example.com --posts=5
 *
 * Default thoughts are inline below (edit locally). --from=eval uses eval/thoughts.json.
 *
 * Production (inside Railway network, after script is in the deployed image):
 *
 *   railway ssh --service api --environment production \
 *     "cd /app && SEED_LIVE_COOKS=yes node dist/scripts/seedLiveCooks.js --email=you@example.com --posts=5"
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { eq } from "drizzle-orm";
import { runAsOwner } from "../lib/authStub.js";
import { runCook } from "../lib/cook.js";
import { signCook, signResult } from "../lib/cookSignature.js";
import { COOK_DEADLINE_MS, modelsForStep, type LlmModelId } from "../lib/llmClient.js";
import { loadLocalEnvFile } from "../lib/loadEnv.js";
import { createCard } from "../db/cards.js";
import { closePool, getDb } from "../db/client.js";
import { users } from "../db/schema.js";
import type { Style } from "../types/index.js";
import { assertCommunitySeedAllowed } from "./seedCommunityGuard.js";

type SeedThought = { id: string; text: string; expect?: { kind?: string } };

/** Edit here for one-off production seeds — not loaded from a separate JSON file. */
const DEFAULT_POSTS: SeedThought[] = [
  {
    id: "six_months_no_job",
    text: "Six months unemployed. I send applications and hear nothing back. My wife says it'll turn around but I don't know what to tell her anymore.",
  },
  {
    id: "denmark_cv",
    text: "Another rejection in Danish I had to google. I'm 34 and still feel like I'm proving I belong here.",
  },
  {
    id: "kid_bedtime",
    text: "My kid asked why I'm home every day when other dads go to work. I made a joke and changed the subject.",
  },
  {
    id: "croatian_family",
    text: "Video call with my parents in Croatia. They ask about work. I keep it short so they don't worry.",
  },
  {
    id: "a_kasse",
    text: "A-kasse paperwork again. I'm grateful it exists and ashamed I need it.",
  },
  {
    id: "wife_carrying",
    text: "My wife had a long day and I didn't make dinner on time. She didn't complain. That almost made it worse.",
  },
  {
    id: "interview_english",
    text: "Interview went fine until they switched to fast Danish small talk. I smiled through it and left unsure.",
  },
  {
    id: "weekend_fear",
    text: "Sunday evening in Denmark is quiet. I start counting Monday emails that won't come.",
  },
  {
    id: "identity",
    text: "Used to have a title. Now I introduce myself as someone's dad and someone's husband and skip the rest.",
  },
  {
    id: "small_win",
    text: "Got a callback for a role I'm overqualified for. Part of me wants to be offended. Part of me just wants it to end.",
  },
];

function assertLiveCookSeedAllowed(environment: NodeJS.ProcessEnv = process.env): void {
  if (environment.SEED_LIVE_COOKS?.trim().toLowerCase() === "yes") {
    return;
  }
  assertCommunitySeedAllowed(environment);
}

function parseFlag(argv: readonly string[], name: string, fallback: number): number {
  const flag = argv.find((argument) => argument.startsWith(`--${name}=`));
  const raw = flag?.slice(`--${name}=`.length).trim();
  const value = raw ? Number.parseInt(raw, 10) : fallback;
  if (!Number.isFinite(value) || value < 1) {
    throw new Error(`invalid --${name}`);
  }
  return value;
}

function parseEmail(argv: readonly string[]): string {
  const flag = argv.find((argument) => argument.startsWith("--email="));
  const email = flag?.slice("--email=".length).trim().toLowerCase();
  if (!email) {
    throw new Error("pass --email=your-apple-account-email");
  }
  return email;
}

function parseFrom(argv: readonly string[]): "live" | "eval" {
  const flag = argv.find((argument) => argument.startsWith("--from="));
  const value = flag?.slice("--from=".length).trim();
  if (value === "eval") {
    return "eval";
  }
  if (value && value !== "live") {
    throw new Error("use --from=live (default) or --from=eval");
  }
  return "live";
}

function loadThoughts(source: "live" | "eval"): SeedThought[] {
  if (source === "live") {
    return DEFAULT_POSTS;
  }
  const path = resolve(process.cwd(), "eval/thoughts.json");
  const cases = JSON.parse(readFileSync(path, "utf8")) as SeedThought[];
  return cases.filter((item) => item.expect?.kind !== "continue" && item.text.trim().length > 0);
}

function pickSpotlight(styles: Style[], index: number): Style {
  return styles[index % styles.length] ?? "stoic";
}

async function main(): Promise<void> {
  loadLocalEnvFile();
  assertLiveCookSeedAllowed();
  const email = parseEmail(process.argv);
  const source = parseFrom(process.argv);
  const targetPosts = parseFlag(process.argv, "posts", 5);
  const thoughts = loadThoughts(source);
  if (thoughts.length < targetPosts) {
    throw new Error(`need at least ${targetPosts} thoughts in the ${source} list`);
  }

  const db = getDb();
  const [owner] = await db.select({ id: users.id, email: users.email }).from(users).where(eq(users.email, email));
  if (!owner) {
    throw new Error(`no user with email ${email} — sign in once on this database first`);
  }

  const deadlineAt = Date.now() + COOK_DEADLINE_MS;
  let posted = 0;
  let thoughtIndex = 0;

  process.stderr.write(`Posting up to ${targetPosts} public cards as ${email} (${source} thoughts)\n`);

  while (posted < targetPosts && thoughtIndex < thoughts.length) {
    const thought = thoughts[thoughtIndex]!;
    thoughtIndex += 1;
    let answeredBy: LlmModelId = modelsForStep("writer").primary;

    process.stderr.write(`[${posted + 1}/${targetPosts}] cooking ${thought.id}…\n`);
    const outcome = await runCook({
      text: thought.text,
      followUps: [],
      deadlineAt,
      onAnsweredBy: (model) => {
        answeredBy = model;
      },
    });

    if (outcome.kind === "continue") {
      process.stderr.write(`  skip (continue): ${thought.id}\n`);
      continue;
    }
    if (outcome.decision.meta.safety !== "none") {
      process.stderr.write(`  skip (safety): ${thought.id}\n`);
      continue;
    }

    const { decision, results } = outcome;
    const cookSignature = signCook({
      ownerId: owner.id,
      thought: decision.thought,
      thoughtOriginal: decision.thoughtOriginal,
      model: answeredBy,
      meta: decision.meta,
    });
    const signedResults = results.map((item) => ({
      ...item,
      signature: signResult(
        owner.id,
        decision.thought,
        item.style,
        item.reframe,
        item.reframeOriginal,
      ),
    }));
    const spotlightStyle = pickSpotlight(
      signedResults.map((item) => item.style),
      posted,
    );

    await runAsOwner(owner.id, () =>
      createCard(
        {
          thought: decision.thought,
          thoughtOriginal: decision.thoughtOriginal,
          results: signedResults,
          meta: decision.meta,
          model: answeredBy,
          spotlightStyle,
          isPublic: true,
        },
        { cookSignature },
      ),
    );
    posted += 1;
    process.stderr.write(`  posted\n`);
  }

  console.log(`Seeded ${posted} public card(s) for ${email}.`);
  if (posted < targetPosts) {
    console.warn(`Only ${posted}/${targetPosts} posts; add more thoughts or re-run.`);
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
