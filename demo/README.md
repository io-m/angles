# Showcase video

A 25–35 s vertical video of a real cook:

- A yellow kinetic-type hook: "I lost my job 5 months ago. So I asked AI to see it 4 ways."
- A zoom-through into the full phone screen. The thought is typed, Send is tapped, and the real cooking bubble runs.
- A chapter card for each style as the camera moves over the real answer card, then a long hold on the best answer.
- An end card: the Angles mark, "Coming soon to the App Store", and "Follow for more".

Nothing in the phone is mocked. The AI output is whatever the local API returned on that take.

## Regenerate

```bash
demo/make_video.sh
```

The output is `demo/output/final_9x16.mp4` (1080x1920, 30 fps, H.264/AAC). Next to it are `report.md` (the answers, the one that was held, and the checks), `contact_sheet.png`, `frames/` (both hook cards, every beat, the end card), and `edl.json` (the cut list).

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
   - tap Optimistic, Humorous, Stoic, and Tough love in turn
   - return to the best answer and hold it

   The flow never taps Post or Save. It stops with a clear reason if Angles asks a second follow-up, answers with a crisis line, or shows an error.
5. Each take is saved to `demo/raw/take-YYYYMMDD-HHMMSS/` and is never overwritten. A take holds `screen.mp4`, `answers.json`, the theme it was recorded with (`theme.json`), the Maestro logs, and the final view hierarchy.
6. `edit.mjs` snaps each beat to the real scene changes in the recording and builds the cut:
   - typing sped up to about 3.5 s, with the Send tap at real speed
   - cooking at 1.5x, capped at 4 s
   - the first answer for 2.4 s
   - 1.5 s for each other style
   - about 7 s on the best answer

   It writes the cut, tap points, chapter cards, and camera moves into `video/index.html`, built from `lib/composition.template.html`. That file is a HyperFrames composition, and its footage is a constant-frame-rate copy of the take in `video/media/`. The phone is always shown whole, inside a device frame. The camera pushes in on the composer, the cooking bubble, and the answer card, so the card stays fully in frame. Taps the Simulator recording cannot show are drawn as ripples.

   HyperFrames checks and renders the picture to `demo/build/picture.mp4`; an unchanged composition is not rendered again. ffmpeg then adds sound effects, synthesized from tones and noise (a thump per hook beat, whooshes, tap clicks, chapter hits), and the music if any. It encodes the final file. `check.mjs` verifies the format and writes the report.

## Options

```bash
demo/make_video.sh --skip-build                      # reuse the build already installed on the Simulator
demo/make_video.sh --reuse-take demo/raw/take-…      # re-edit an existing take; no Simulator, no cook
demo/make_video.sh --theme lost-job                  # demo/themes/lost-job.json (the default)
DEMO_LINE="…" demo/make_video.sh                     # a different thought, same on-screen words
FOLLOWUP_REPLY="…" demo/make_video.sh                # what to say if Angles asks a follow-up and no chip fits
BEST_STYLE=stoic demo/make_video.sh                  # force the held answer (stoic|optimistic|humorous|tough_love)
```

By default, `flows/pick_best.js` picks the held answer by favouring concrete objects and a next step and penalising stock phrases. The report shows every score. Timings, camera zoom levels, and the length target are in `edit.config.json`. `layoutPt` holds the points measured on the iPhone 17 Pro: composer, Send button, chip row. Re-measure them if the compose layout changes. The words come from the theme, and colors and motion live in `lib/composition.template.html`. The hook is sized with Anton's real letter widths (`lib/anton-widths.json`, read from the bundled font).

To preview without rendering, run `EDIT_ONLY=1 node demo/edit.mjs demo/raw/take-…`. Then run `npx hyperframes@0.8.113 preview` or `snapshot --at 2.9,12,20` in `demo/video/`.

## Make one with a new theme

Each video is one theme file in `demo/themes/`. It holds the thought that gets typed, and every word on screen that is not the app itself: the hook, the note under the best answer, and the end card. `lost-job.json` is the reference. Everything else (the recording, cuts, camera, chapter cards, sound) stays the same.

To have an LLM make one, give it this:

> Read `demo/README.md` ("Make one with a new theme") and `demo/themes/lost-job.json`. Write `demo/themes/<short-name>.json` for this theme: **<your theme>**. Then run `demo/make_video.sh --theme <short-name>`, read `demo/output/report.md` and `demo/output/contact_sheet.png`, and tell me if it is postable.

Rules for the theme file:

- `line` is the thought typed into Angles: first person, one sentence, 12–25 words. Include one concrete detail, like a number, a time, or a place, and a small twist; that is what makes the answers specific. It must not be about self-harm, because Angles answers with a crisis line and the flow stops. It must not name a real person. A vague line gets a follow-up question; the flow answers one with `followupReply` and stops on a second.
- `hook` is two cards shown in the first 3 seconds. Card one is the situation, taken from `line`, not made up. Card two is the turn and ends on a `slam` line.
  - `big` lines (yellow) and `slam` lines read largest at about 7 characters.
  - `small` lines (white) read largest at about 13 characters.
  - Longer lines shrink to fit, and the edit prints a warning when a line drops below 70% size.
  - Three lines per card is the sweet spot.
- `bestNote` is the line under the last chapter card, up to about 34 characters.
- `end` is the end card:
  - `tagline`: about 34 characters
  - `badge`: the yellow pill, about 29 characters
  - `follow`: about 24 characters
  - `wordmark`: the app name
- `bestStyle` is `auto`, or a style to force as the held answer.

A run records a new take, which spends one cook credit on the demo account. If the answers read as generic, run it again, or sharpen `line`. To change only the words of an existing take (the hook, the note, the end card), run `demo/make_video.sh --reuse-take demo/raw/take-… --theme <short-name>`. That does not record a new take, so `line` is not used. The colors, fonts, motion, and end-card layout are in `lib/composition.template.html`.

Each run writes `demo/output/final_9x16.mp4` and a copy named after the theme and take, like `demo/output/lost-job_take-20261002-211217.mp4`. Re-editing the same take with the same theme replaces that copy.

## Music

Put a track you have the rights to at `demo/assets/music.mp3`. It is looped or trimmed to fit, mixed low (`musicVolume`) under the sound effects, and faded in and out. Without it, the audio is the sound effects alone. Screen audio is never used.

## Check by eye before posting

- The answers are specific to this thought. If they read as generic, record another take or change `DEMO_LINE`.
- Exactly zero or one follow-up was asked (`report.md`).
- There is no notification banner, real name, or personal data. The account is "Angles Demo", shown with the initials "AD".
- The held answer is readable on a phone at arm's length.
- The hook reads in one glance, and the end card's App Store and follow lines sit clear of TikTok's caption area.

`report.md` marks the video NOT POSTABLE when the flow saw more than one follow-up, a crisis line, or a missing style. The flow itself refuses to finish a take in those cases.
