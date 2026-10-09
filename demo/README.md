# Showcase video

A 20–32 s vertical TikTok of a **real** cook. Every video uses the same cut. Change only the **theme** (`demo/themes/<name>.json`). Do not invent extra beats.

**Cut contract** (hook → type → send → short cook → four style chapters → outro):

1. Yellow kinetic hook (~3 s), then the whole phone in a device frame.
2. Type the thought (~3.5 s sped up), tap Send at real speed.
3. Cooking bubble at 1.5x, **capped at ~1.8 s**. The first yellow chapter title lands **on the same frame as the card**, not after a hold on the bubble.
4. **Exactly four** chapters: the style that opened, then the other chips in tap order (Stoic, Hopeful, Witty, Tender, Values, Tough: Tough last when the card has it). Each of the first three is ~1.4 s. Yellow `CHAPTER n` + style name on the cut, no extra pause before the title.
5. Last chapter holds **~2 s extra** (~3.4 s) with a small slow zoom, then the end card (wordmark, App Store badge, follow).

The four chapters are whichever four styles the cook wrote, from Stoic, Hopeful, Witty, Tough, Tender, and Values. They are never forced: a thought that gets Tender and Values shows Tender and Values. The chapter title is that style's own label, and the pill widths for all six are in `edit.config.json`. `edit.mjs` stops with a clear error if a take has anything other than four chapters.

**Do not add** (these were tried and dropped): a fifth “best” chapter, jumping back to Stoic, a `bestNote` line, **undefined** chapter numbers, Post, the bike save cover, or Home / border glow. `pick_best.js` still scores answers for `report.md` only; it does not change the cut.

Nothing in the phone is mocked. The AI output is whatever the local API returned on that take. Timings live in `edit.config.json`. Full pipeline: `demo/README.md` below.

## Regenerate

```bash
demo/make_video.sh
```

The output is `demo/output/final_9x16.mp4` (1080x1920, 30 fps, H.264/AAC). Next to it are `report.md` (the answers and the checks), `contact_sheet.png`, `cover.png` (TikTok cover: first hook card, same as `frames/01-hook-1.png`), `frames/` (hook cards, every beat, the end card), and `edl.json` (the cut list). `make_video.sh` also keeps `demo/output/<theme>_cover.png` beside the themed `.mp4` copy.

Before you run it:

- Start the local API (`cd backend && pnpm dev`) with Postgres up. `ANGLES_API_BASE_URL` in `AnglesApp/project.yml` (Debug) must be this Mac's LAN IP.
- The script checks for its tools and prints the install command for any that are missing:
  - `brew install ffmpeg node ripgrep openjdk@17`
  - `curl -fsSL 'https://get.maestro.mobile.dev' | bash`
  - `corepack enable pnpm`
  - Xcode with an iOS 26 Simulator runtime

## What it does

1. `setup_sim.sh` creates or boots the **Angles Demo iPhone 17 Pro** Simulator and sets it up for recording: en_US locale, dark appearance, a 9:41 status bar with full battery and signal, and no hardware keyboard. It then builds Debug and installs it.
2. `pnpm demo:session` (in `backend/`) creates a local-only demo account, `demo@angles.local`, with Terms already accepted, and prints a 2-hour session token. It refuses to run against production or any database host that is not local.
3. The app launches with `-AnglesDemoSessionToken <token> -AnglesDemoEntitled YES`. These two launch arguments exist only in Debug Simulator builds (`DemoLaunch` in `AppConfig.swift`), so they skip Apple sign-in and StoreKit. The server still meters the cook as usual.
4. `flows/warmup.yaml` gets past first-launch prompts and the keyboard tip. Then `simctl io recordVideo` starts and `demo_flow.yaml` runs the take:
   - open compose with the sparkle button and type the line
   - Send, then answer at most one follow-up (a chip if one fits, otherwise `FOLLOWUP_REPLY`)
   - wait for the card without tapping anything
   - tap each other chip the card has, once (short holds; the edit trims tighter)
   - hold the last one; the edit cuts from there to the end card

   It stops with a clear reason if Angles asks a second follow-up, answers with a crisis line, or shows an error.
5. Each take is saved to `demo/raw/take-YYYYMMDD-HHMMSS/` and is never overwritten. A take holds `screen.mp4`, `answers.json`, the theme it was recorded with (`theme.json`), the Maestro logs, and the final view hierarchy.
6. `edit.mjs` snaps each beat to the real scene changes in the recording and builds the cut:
   - typing sped up to about 3.5 s, with the Send tap at real speed
   - cooking at 1.5x, capped at about 1.8 s
   - ~1.4 s for each of the first three styles, with the yellow chapter title on the same frame as the cut
   - ~3.4 s on the last style with a small zoom, then the end card

   It writes the cut, tap points, chapter cards, and camera moves into `video/index.html`, built from `lib/composition.template.html`. That file is a HyperFrames composition, and its footage is a constant-frame-rate copy of the take in `video/media/`. The phone is always shown whole, inside a device frame. The camera pushes in on the composer, the cooking bubble, and the answer card, so the card stays fully in frame. Taps the Simulator recording cannot show are drawn as ripples.

   HyperFrames checks and renders the picture to `demo/build/picture.mp4`; an unchanged composition is not rendered again. ffmpeg then adds sound effects, synthesized from tones and noise (a thump per hook beat, whooshes, tap clicks, chapter hits), and the music if any. It encodes the final file. `check.mjs` verifies the format and writes the report.

## Options

```bash
demo/make_video.sh --skip-build                      # reuse the build already installed on the Simulator
demo/make_video.sh --reuse-take demo/raw/take-…      # re-edit an existing take; no Simulator, no cook
demo/make_video.sh --theme lost-job                  # demo/themes/lost-job.json
demo/make_video.sh --theme lisbon-flight             # demo/themes/lisbon-flight.json
DEMO_LINE="…" demo/make_video.sh                     # a different thought, same on-screen words
FOLLOWUP_REPLY="…" demo/make_video.sh                # what to say if Angles asks a follow-up and no chip fits
```

`BEST_STYLE` still exists for the **report** (`flows/pick_best.js`). It does **not** insert a fifth held chapter. Timings, camera zoom, and the length target are in `edit.config.json`. `layoutPt` holds the points measured on the iPhone 17 Pro: composer, Send button, chip row. Re-measure them if the compose layout changes. The words come from the theme, and colors and motion live in `lib/composition.template.html`. The hook is sized with Anton's real letter widths (`lib/anton-widths.json`, read from the bundled font).

To preview without rendering, run `EDIT_ONLY=1 node demo/edit.mjs demo/raw/take-…`. Then run `npx hyperframes@0.8.113 preview` or `snapshot --at 2.9,12,20` in `demo/video/`.

## Make one with a new theme

Each video is one theme file in `demo/themes/`. It holds the thought that gets typed, and every word on screen that is not the app itself: the hook and the end card. The cut, camera, chapter cards, and sound stay the same for every theme (`lisbon-flight.json` is a recent example; `lost-job.json` still works).

To have an LLM make one, give it this:

> Read `demo/README.md` from the top (**Cut contract**) and `demo/themes/lisbon-flight.json`. Write `demo/themes/<short-name>.json` for this theme: **<your theme>**. Do not add Post, Home, or a fifth chapter. Then run `demo/make_video.sh --theme <short-name>`, read `demo/output/report.md` and `demo/output/contact_sheet.png`, and tell me if it is postable. Use `demo/output/<short-name>_cover.png` (or `cover.png`) as the TikTok cover — do not generate a separate cover graphic.

Rules for the theme file:

- `line` is the thought typed into Angles: first person, one sentence, 12–25 words. Include one concrete detail, like a number, a time, or a place, and a small twist; that is what makes the answers specific. It must not be about self-harm, because Angles answers with a crisis line and the flow stops. It must not name a real person. A vague line gets a follow-up question; the flow answers one with `followupReply` and stops on a second.
- `hook` is two cards shown in the first 3 seconds. Card one is the situation, taken from `line`, not made up. Card two is the turn and ends on a `slam` line.
  - `big` lines (yellow) and `slam` lines read largest at about 7 characters.
  - `small` lines (white) read largest at about 13 characters.
  - Longer lines shrink to fit, and the edit prints a warning when a line drops below 70% size.
  - Three lines per card is the sweet spot.
- `end` is the end card:
  - `tagline`: about 34 characters
  - `badge`: the yellow pill, about 29 characters
  - `follow`: about 24 characters
  - `wordmark`: the app name
- `bestNote` and `bestStyle` may still sit in a theme file; the edit **ignores** them for the picture (`bestStyle` only affects `report.md` scoring).

A run records a new take, which spends one cook credit on the demo account. If the answers read as generic, run it again, or sharpen `line`. To change only the words of an existing take (the hook and the end card), run `demo/make_video.sh --reuse-take demo/raw/take-… --theme <short-name>`. That does not record a new take, so `line` is not used. The colors, fonts, motion, and end-card layout are in `lib/composition.template.html`.

Each run writes `demo/output/final_9x16.mp4` and a copy named after the theme and take, like `demo/output/lost-job_take-20261002-211217.mp4`. Re-editing the same take with the same theme replaces that copy.

## Music

Put a track you have the rights to at `demo/assets/music.mp3`. It is looped or trimmed to fit, mixed low (`musicVolume`) under the sound effects, and faded in and out. Without it, the audio is the sound effects alone. Screen audio is never used.

## Check by eye before posting

- The answers are specific to this thought. If they read as generic, record another take or change `DEMO_LINE`.
- Exactly zero or one follow-up was asked (`report.md`).
- There is no notification banner, real name, or personal data. The account is "Angles Demo", shown with the initials "AD".
- The last chapter is readable on a phone at arm's length.
- The hook reads in one glance, and the end card's App Store and follow lines sit clear of TikTok's caption area.

`report.md` marks the video NOT POSTABLE when the flow saw more than one follow-up, a crisis line, or a take that does not have exactly four style chapters. The flow itself refuses to finish a take in those cases.
