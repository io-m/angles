// Upload store/preview.mp4, the marketing frames, and the paywall review
// image to App Store Connect version 1.0 (en-US). Does not submit.
//
//   node demo/store_upload.mjs
//   node demo/store_upload.mjs --preview-only
import { createHash } from "node:crypto";
import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import { api } from "/tmp/asc/asc.mjs";

const ROOT = new URL("..", import.meta.url).pathname;
const STORE = join(ROOT, "store");
const LOCALE = "e6bb07ad-9f27-4626-a2bc-a9d0689cb9fd";
const SUBS = [
  ["6811875049", "yearly"],
  ["6811878672", "monthly"],
];
const FRAMES = [
  "01-four-ways.png",
  "02-write.png",
  "03-voice.png",
  "04-possible.png",
  "05-keep.png",
];

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
    data: {
      type,
      attributes,
      relationships: relationship,
    },
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

async function clearSet(setType, itemType, setId, listPath) {
  const listed = await api("GET", listPath);
  for (const item of listed.data ?? []) {
    await api("DELETE", `/v1/${itemType}/${item.id}`);
  }
  return setId;
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

function previewPosterTimeCode() {
  const editPath = join(STORE, "edit.json");
  if (existsSync(editPath)) {
    const edit = JSON.parse(readFileSync(editPath, "utf8"));
    if (edit.posterFrameTimeCode) return edit.posterFrameTimeCode;
  }
  return "00:00:05:00";
}

async function addPreview(setId, path) {
  const created = await reserve("appPreviews", {
    fileName: basename(path),
    fileSize: statSync(path).size,
    mimeType: "video/mp4",
  }, {
    appPreviewSet: { data: { type: "appPreviewSets", id: setId } },
  });
  await uploadParts(created.attributes.uploadOperations, path);
  await commit("appPreviews", created.id, path);
  for (let i = 0; i < 36; i++) {
    const row = await api("GET", `/v1/appPreviews/${created.id}`);
    const video = row.data.attributes.videoDeliveryState?.state;
    if (video === "COMPLETE") break;
    if (video === "FAILED") throw new Error("preview video FAILED");
    await new Promise((r) => setTimeout(r, 5000));
  }
  const posterFrameTimeCode = previewPosterTimeCode();
  await api("PATCH", `/v1/appPreviews/${created.id}`, {
    data: {
      type: "appPreviews",
      id: created.id,
      attributes: { previewFrameTimeCode: posterFrameTimeCode },
    },
  });
  console.error(`preview ${basename(path)} poster ${posterFrameTimeCode}`);
}

async function addReviewShot(subscriptionId, path) {
  const current = await api("GET", `/v1/subscriptions/${subscriptionId}/appStoreReviewScreenshot`).catch((error) => {
    if (error.status === 404) return { data: null };
    throw error;
  });
  if (current.data?.id) {
    await api("DELETE", `/v1/subscriptionAppStoreReviewScreenshots/${current.data.id}`);
  }
  const created = await reserve("subscriptionAppStoreReviewScreenshots", {
    fileName: basename(path),
    fileSize: statSync(path).size,
  }, {
    subscription: { data: { type: "subscriptions", id: subscriptionId } },
  });
  await uploadParts(created.attributes.uploadOperations, path);
  await commit("subscriptionAppStoreReviewScreenshots", created.id, path);
  console.error(`review screenshot ${subscriptionId}`);
}

const previewOnly = process.argv.includes("--preview-only");

const previewSet = await ensureSet("appPreviewSets", "appPreviews", "previewType", "IPHONE_67", "appPreviewSets");
await addPreview(previewSet, join(STORE, "preview.mp4"));

if (previewOnly) {
  console.log("uploaded preview only");
  process.exit(0);
}

const shotSet = await ensureSet("appScreenshotSets", "appScreenshots", "screenshotDisplayType", "APP_IPHONE_67", "appScreenshotSets");
for (const name of FRAMES) {
  const path = join(STORE, name);
  if (!statSync(path, { throwIfNoEntry: false })) {
    throw new Error(`missing ${path}`);
  }
  await addImage(shotSet, path);
}
if (statSync(join(STORE, "06-widget.png"), { throwIfNoEntry: false })) {
  await addImage(shotSet, join(STORE, "06-widget.png"));
}

const paywall = join(STORE, "paywall.png");
for (const [id, name] of SUBS) {
  console.error(`paywall -> ${name}`);
  await addReviewShot(id, paywall);
}

console.log("uploaded");
