// Upload dedicated header (21:9) and search (3:2) stills into Asset Library
// and place them on version 1.0. Does not submit for review.
//
//   node demo/store_upload_header.mjs
import { readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import { api } from "/tmp/asc/asc.mjs";

const ROOT = new URL("..", import.meta.url).pathname;
const STORE = join(ROOT, "store");
const LIBRARY = "6811873869";
const LOCALE = "e6bb07ad-9f27-4626-a2bc-a9d0689cb9fd";
const headerOnly = process.argv.includes("--header-only");
const ASSETS = [
  {
    path: join(STORE, "header-21x9.png"),
    referenceName: "Angles header 21x9",
    placementType: "PRODUCT_PAGE_HEADER_ASSET",
  },
  {
    path: join(STORE, "search-3x2.png"),
    referenceName: "Angles search 3x2",
    placementType: "APP_STORE_SEARCH_RESULTS_ASSET",
  },
].filter((a) => !headerOnly || a.placementType === "PRODUCT_PAGE_HEADER_ASSET");
const PLACEMENTS = ASSETS.map((a) => a.placementType);

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

async function uploadImage(path, referenceName) {
  const existing = await api("GET", `/v1/appAssetLibraries/${LIBRARY}/images?limit=200`);
  for (const row of existing.data ?? []) {
    if (row.attributes?.category === "CREATIVE_ASSETS" && row.attributes?.fileName === basename(path)) {
      await api("DELETE", `/v1/appAssetLibraryImages/${row.id}`);
      console.error(`removed previous ${row.id} ${basename(path)}`);
    }
  }
  const created = await api("POST", "/v1/appAssetLibraryImages", {
    data: {
      type: "appAssetLibraryImages",
      attributes: {
        fileName: basename(path),
        fileSize: statSync(path).size,
        category: "CREATIVE_ASSETS",
        referenceName,
      },
      relationships: {
        assetLibrary: { data: { type: "appAssetLibraries", id: LIBRARY } },
      },
    },
  });
  const id = created.data.id;
  await uploadParts(created.data.attributes.uploadOperations, path);
  await api("PATCH", `/v1/appAssetLibraryImages/${id}`, {
    data: {
      type: "appAssetLibraryImages",
      id,
      attributes: { uploaded: true },
    },
  });
  console.error(`image ${id} ${basename(path)}`);
  return id;
}

// Placements hold references to the previous images, so clear them before
// deleting anything from the Asset Library.
const placed = await api("GET", `/v1/appStoreVersionLocalizations/${LOCALE}/placements`);
for (const row of placed.data ?? []) {
  if (PLACEMENTS.includes(row.attributes?.placementType)) {
    await api("DELETE", `/v1/appAssetLibraryPlacements/${row.id}`);
    console.error(`cleared ${row.attributes.placementType}`);
  }
}

const ids = {};
for (const asset of ASSETS) {
  ids[asset.placementType] = await uploadImage(asset.path, asset.referenceName);
}

for (const asset of ASSETS) {
  const json = await api("POST", "/v1/appAssetLibraryPlacements", {
    data: {
      type: "appAssetLibraryPlacements",
      attributes: { placementType: asset.placementType },
      relationships: {
        appStoreVersionLocalization: {
          data: { type: "appStoreVersionLocalizations", id: LOCALE },
        },
        image: { data: { type: "appAssetLibraryImages", id: ids[asset.placementType] } },
      },
    },
  });
  console.error(`placed ${asset.placementType} ${json.data.id} ${json.data.attributes.state}`);
}

console.log("uploaded header and search");
