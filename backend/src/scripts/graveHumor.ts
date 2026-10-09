/**
 * Public cards about real harm that still carry a joke or a push from before the
 * solemn rule. Dry run by default: it only lists them.
 *
 *   pnpm db:grave-humor --dry-run     list the cards and the angles that would go
 *   pnpm db:grave-humor --apply       remove those angles and their hearts
 *
 * `--apply` removes only witty and tough, moves the cover to an angle that
 * stays, and records our skip reason on the card. A card with no other angle is left
 * alone and listed. Production Postgres has no public URL, so it runs in the API container:
 *   railway ssh --service api --environment production node dist/scripts/graveHumor.js --dry-run
 */
import { closePool, getSql } from "../db/client.js";
import { SOLEMN_BLOCKED_STYLES, solemnSkipFor } from "../lib/decision.js";
import type { Category, SkippedStyle, Style } from "../types/index.js";

type CardRow = {
  id: string;
  thought_en: string;
  thought_original: string | null;
  category: Category;
  spotlight_style: Style;
  skipped_styles: SkippedStyle[];
  styles: Style[];
};

type Finding = { card: CardRow; drop: Style[]; keep: Style[]; reasons: SkippedStyle[] };

function databaseHost(): string {
  try {
    return new URL(process.env.DATABASE_URL ?? "").host || "unknown";
  } catch {
    return "unknown";
  }
}

async function findings(): Promise<Finding[]> {
  const sql = getSql();
  const rows = await sql<CardRow[]>`
    select c.id, c.thought_en, c.thought_original, c.category, c.spotlight_style, c.skipped_styles,
      array_agg(r.style::text order by r.position) as styles
    from cards c
    join card_reframes r on r.card_id = c.id
    where c.is_public = true
    group by c.id
    having bool_or(r.style::text in ('witty', 'tough'))
  `;
  const out: Finding[] = [];
  for (const card of rows) {
    const reasons = card.styles
      .map((style) =>
        solemnSkipFor(style, {
          thought: card.thought_en,
          ...(card.thought_original ? { thoughtOriginal: card.thought_original } : {}),
          meta: { category: card.category },
        }),
      )
      .filter((item): item is SkippedStyle => item !== undefined);
    if (reasons.length > 0) {
      const drop = reasons.map((item) => item.style);
      out.push({ card, drop, keep: card.styles.filter((style) => !drop.includes(style)), reasons });
    }
  }
  return out;
}

async function apply(finding: Finding): Promise<void> {
  const { card, drop, keep, reasons } = finding;
  const cover = keep.includes(card.spotlight_style) ? card.spotlight_style : keep[0];
  const skipped = [
    ...card.skipped_styles.filter((item) => !SOLEMN_BLOCKED_STYLES.includes(item.style)),
    ...reasons,
  ];
  await getSql().begin(async (tx) => {
    await tx`delete from saved_angles where card_id = ${card.id} and style::text in ${tx(drop)}`;
    await tx`delete from card_reframes where card_id = ${card.id} and style::text in ${tx(drop)}`;
    await tx`
      update cards
      set spotlight_style = ${cover ?? card.spotlight_style}, skipped_styles = ${tx.json(skipped)}
      where id = ${card.id}
    `;
  });
}

async function main(): Promise<void> {
  const applying = process.argv.includes("--apply");
  console.log(`Database: ${databaseHost()}${applying ? "" : " (dry run)"}\n`);
  const found = await findings();
  if (found.length === 0) {
    console.log("No public grave card has a joke or a push.");
    return;
  }
  let changed = 0;
  for (const finding of found) {
    const { card, drop, keep } = finding;
    console.log(`== card ${card.id}`);
    console.log(`   thought: ${card.thought_en}`);
    console.log(`   remove: ${drop.join(", ")}; keep: ${keep.join(", ") || "nothing"}`);
    if (keep.length === 0) {
      console.log("   left alone: no other angle would remain");
    } else if (applying) {
      await apply(finding);
      changed += 1;
      console.log("   removed");
    }
    console.log("");
  }
  console.log(applying ? `Changed ${changed} of ${found.length} card(s).` : `${found.length} card(s) would change.`);
}

main()
  .catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => closePool());
