import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { buildCommunityFixture } from "./communityCopy.js";

const fixture = buildCommunityFixture();
const path = resolve(process.cwd(), "fixtures/community.json");
writeFileSync(path, `${JSON.stringify(fixture, null, 2)}\n`);
console.log(`Wrote ${fixture.users.length} users and ${fixture.posts.length} posts to ${path}`);
