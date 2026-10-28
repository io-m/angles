// Maestro runScript: capture one Duo display at App Store pixel size.
// Env: DUO_UDID, DUO_DISPLAY_ID, SHOT_DIR; set output.shotName before calling.
// simctl runs in demo/lib/duo_shot_server.mjs, which make_store_duo.sh starts.
var udid = DUO_UDID;
var displayId = DUO_DISPLAY_ID;
var shotDir = SHOT_DIR;
var name = output.shotName;
if (!udid || !displayId || !shotDir || !name) {
  throw new Error("duo_screenshot needs DUO_UDID, DUO_DISPLAY_ID, SHOT_DIR, output.shotName");
}
var dest = shotDir + "/" + name;
var response = http.post("http://127.0.0.1:8765/shot", {
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    udid: String(udid),
    display: String(displayId),
    dest: String(dest),
  }),
});
if (!response.ok) {
  throw new Error("simctl screenshot failed: " + response.status + " " + response.body);
}
