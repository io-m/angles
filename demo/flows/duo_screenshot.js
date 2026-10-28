// Maestro runScript: capture the Duo display at App Store pixel size (Rhino / Java).
// Env: DUO_UDID, DUO_DISPLAY_ID, SHOT_DIR; set output.shotName before calling.
var udid = DUO_UDID;
var displayId = DUO_DISPLAY_ID;
var shotDir = SHOT_DIR;
var name = output.shotName;
if (!udid || !displayId || !shotDir || !name) {
  throw new Error("duo_screenshot needs DUO_UDID, DUO_DISPLAY_ID, SHOT_DIR, output.shotName");
}
var dest = shotDir + "/" + name;
var cmd = [
  "xcrun",
  "simctl",
  "io",
  String(udid),
  "screenshot",
  "--display=" + String(displayId),
  String(dest),
];
var pb = new java.lang.ProcessBuilder(cmd);
pb.inheritIO();
var p = pb.start();
var code = p.waitFor();
if (code !== 0) {
  throw new Error("simctl screenshot failed with code " + code);
}
