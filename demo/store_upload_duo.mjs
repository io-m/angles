// Upload iPhone Duo App Store screenshots (outer display set via API; inner drag in if needed).
//
// Do not run while version 1.0 is Waiting for Review — Connect rejects asset edits.
//
//   node demo/store_upload_duo.mjs
//   node demo/store_upload_duo.mjs --dry-run
//   node demo/store_upload_duo.mjs --inner   # attempt inner-sized files (may 422)
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname;
const STORE = join(ROOT, "store", "duo");
const LOCALE = "e6bb07ad-9f27-4626-a2bc-a9d0689cb9fd";
const FRAMES = [
  "01-four-ways.png",
  "02-write.png",
  "03-voice.png",
  "04-possible.png",
  "05-keep.png",
];

const dryRun = process.argv.includes("--dry-run");
const useInner = process.argv.includes("--inner");
const subdir = useInner ? "inner" : "outer";
const dir = join(STORE, subdir);
for (const name of FRAMES) {
  const path = join(dir, name);
  if (!existsSync(path)) {
    throw new Error(`missing ${path} — run demo/make_store_duo.sh first`);
  }
}

if (dryRun) {
  console.log(`dry-run: would upload ${subdir} frames from ${dir} as APP_IPHONE_DUO`);
  process.exit(0);
}

const { api } = await import("/tmp/asc/asc.mjs");

function md5(path) {
  return createHash("md5").update(readFileSync(path)).digest("hex");
}

async function uploadParts(operations, path) {
  const file = readFileSync(path);
  for (const op of operations) {
    const headers = {};
    for (const header of op.requestHeaders ?? []) {
      headers[header.name] = header.value;
    }
    const body = file.subarray(op.offset, op.offset + op.length);
    const res = await fetch(op.url, { method: op.method, headers, body });
    if (!res.ok) {
      throw new Error(`upload ${op.method} ${res.status} ${await res.text()}`);
    }
  }
}

async function reserve(type, attributes, relationship) {
  const json = await api("POST", `/v1/${type}`, {
    data: { type, attributes, relationships: relationship },
  });
  return json.data;
}

async function commit(type, id, path) {
  await api("PATCH", `/v1/${type}/${id}`, {
    data: {
      type,
      id,
      attributes: { uploaded: true, sourceFileChecksum: md5(path) },
    },
  });
}

async function ensureSet(setType, itemType, attrName, attrValue, listName) {
  const existing = await api("GET", `/v1/appStoreVersionLocalizations/${LOCALE}/${listName}`);
  let set = (existing.data ?? []).find((row) => row.attributes?.[attrName] === attrValue);
  if (!set) {
    set = await reserve(setType, { [attrName]: attrValue }, {
      appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: LOCALE } },
    });
  }
  const items = await api("GET", `/v1/${setType}/${set.id}/${itemType}`);
  for (const item of items.data ?? []) {
    await api("DELETE", `/v1/${itemType}/${item.id}`);
  }
  return set.id;
}

async function addImage(setId, path) {
  const created = await reserve("appScreenshots", {
    fileName: basename(path),
    fileSize: statSync(path).size,
  }, {
    appScreenshotSet: { data: { type: "appScreenshotSets", id: setId } },
  });
  await uploadParts(created.attributes.uploadOperations, path);
  await commit("appScreenshots", created.id, path);
  console.error(`screenshot ${basename(path)}`);
}

const shotSet = await ensureSet(
  "appScreenshotSets",
  "appScreenshots",
  "screenshotDisplayType",
  "APP_IPHONE_DUO",
  "appScreenshotSets",
);
for (const name of FRAMES) {
  await addImage(shotSet, join(dir, name));
}
console.log(`uploaded duo ${subdir} (${FRAMES.length} frames)`);
