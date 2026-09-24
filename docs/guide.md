# Linguini guide

Playing, building and working on Linguini. The original vision is in [core.md](core.md).

## Features

- Pair with a Sunshine or GeForce Experience host, pick an app and stream it. Video and audio go to the monitor in the room. All of this happens on the monitor itself.
- **Real Fishy Movement:** the stick or WASD steers from the fish's point of view, not the camera's. Forward swims along its heading, left and right turn it, and back makes it back up slowly. Input is an urge, not a velocity: the fish turns at a limited rate and moves in tail-beat pulses, so it swims in arcs. With no input it drifts.
- Third-person camera. Hold the gaze button to look past the fish at the monitor.
- Flash cards cover the whole controller. Cards can hold several inputs at once (combos), stay on until the fish comes back (toggles), or play a timed macro (sequences).
- A tank editor (F2) places, rebinds, duplicates and deletes cards, and saves named presets.
- A **tank cam** window (F4) shows the room camera's view with a fake ML fish-tracking overlay, ready for OBS to capture.
- Game audio plays from the speakers next to the monitor. While you pilot the fish you hear from the fish, lightly muffled by the water. Cards tap, the tank bubbles and hums, the fish swishes, and the room has its own tone in each mood.
- **Art, so far:** a fancy fantail goldfish that swims by vertex shader, a modelled tank and stand, glass with a hint of algae, a rippling water surface, and caustic light. The tank has editable decor: plants, rocks, driftwood, an air stone, a filter and ornaments. The tank sits under the window of a cosy streamer's bedroom, with lighting baked in Blender for three moods, and outside the window is a neighbourhood street with traffic and people. Every model comes from a Blender script.
- **Feel:** a punch of FOV when the fish darts, a pulse of a card's edge light as it presses, and motes and shafts of lamp light in the water.
- **Look:** matte laminated flash cards with printed button art in Xbox, PlayStation or Nintendo style, a cosy "streamer desktop" on the monitor, and no HUD. Held buttons show on the cards, and the camera's red tally light shows when you're live. The fonts are Nunito and JetBrains Mono.
- **Quality presets:** Low, Medium and High, auto-picked for your GPU.

`tools/tracker/` shows progress live.

## Controls

| | Keyboard / mouse | Gamepad |
|---|---|---|
| Swim forward / back up | W / S | Left stick up / down |
| Turn left / right | A / D | Left stick left / right |
| Rise / sink | Space / C | RB / LB |
| Dart | Shift | A |
| Look around | Mouse | Right stick |
| Watch the monitor | Hold right mouse (or Tab) | Hold LT |
| Menu | Esc | Start |
| Edit the tank | F2 | |
| Tank cam window | F4 | |
| Show card trigger zones | F3 | |

Your own keyboard and gamepad never reach the host. Only the cards do.

The gamepad names above are Xbox's. **Buttons** on the monitor's home page sets which controller's art the cards, menus and hints use: **Xbox**, **PlayStation** or **Nintendo**. It starts on **Auto**, which follows the controller you last used, going by its name. Only the art changes; the host always gets the same inputs. Nintendo's face letters swap by position, so the bottom button (A on Xbox) shows as B.

## Flash cards

The built-in Default layout is `godot/data/layouts/default.json`: one card for each input, on the back wall of the tank. Every card faces the front glass, where the room camera is. A card's trigger zone is the middle 90% of its footprint, extruded forward to the glass. From the room camera's point of view, the fish covering a card presses it.

- **Pressing:** a card presses as soon as the centre of the fish enters its zone. Fins, tail and the rest of the body don't count. It stays held while the fish stays there.
- **Releasing:** a card releases once the fish has been out of the zone for 150 ms. The zone also has a 1.5 cm margin while held, so a fish drifting along an edge doesn't make the button flicker.
- **Combos:** a card can hold several inputs together, such as RB + A, or L↑ + L→ for a stick diagonal.
- **Toggles:** a toggle card switches its inputs on when the fish arrives and keeps them held after it swims off, until it arrives again. Use one to aim down sights or sprint without parking the fish. It stays lit while it's on. Opening a menu or the editor switches toggles off.
- **Sequences:** a card can instead play a timed macro once each time the fish arrives. For example, "B for 80 ms, then RB at 180 ms for 80 ms". Each step holds one input from its start time for its length, and steps can overlap to press inputs together. A sequence finishes even if the fish swims off. Arriving again replays it.
- **The printed face:** a coloured band says what kind of input the card is (button, bumper, D-pad, left stick, combo, toggle, sequence). Under it is the button's glyph, an arrow, or a row of glyphs for a combo or sequence. While a card is held or toggled on, its laminated edge lights in the card's colour. A playing sequence fills a bar along the bottom.

### Tank editor

Press F2, or choose **Edit tank** on the monitor. The fish waits and nothing is sent to the host while you edit.
- **Moving things:** click a card or a piece of decor to select it, then drag to move it.
  - Cards move parallel to the glass; Shift+drag moves them nearer or further. The panel also has exact position fields.
  - Decor moves along whatever it's anchored to: the gravel, the water surface, or the back and side rims (the filter). Moss balls float anywhere, with Shift+drag for depth.
- **Camera:** right-drag orbits, and the wheel zooms.
- **Editing a card:** choose **Hold** or **Toggle** and pick one or more inputs, or choose **Sequence** and edit its steps. You can give it a name, which is shown on the card.
- **Editing decor:** set its colour variant and size (S, M or L), and turn it with the slider. Cards always face the glass, so only decor turns.
- **Actions:** **+ Card**, **Duplicate** and **Delete**. To add decor, click its picture in the **Add decor** palette. The selected card shows how it's printed, and selected decor shows its picture.
- **Presets:** **Load**, **Save**, **Save as** and **Delete**. A preset holds both the cards and the decor. Default is built in and read-only. Your presets are saved as JSON in the app's user folder under `layouts/`. The preset in use is remembered between sessions.

### Decor

The catalogue is `godot/data/decor.json`. It holds each piece's name, anchor and colour variants, and any bubbles or glow it has.
- **Solid pieces** (rocks, driftwood, the castle, the sign, the chest, the bonfire, the air stone and the filter): the fish bumps into them. The driftwood arch is solid only along the wood itself, so the fish can swim underneath.
- **Soft pieces** (grass, the broad-leaf plant, the moss ball and the lily pad): the fish swims through them. Plants sway in a gentle current and lean away as the fish passes.
- **Hiding the fish:** decor between the fish and the room camera lowers the tank cam's confidence, just as cards do.
- **Card zones:** decor may overlap them. A solid piece there makes that card harder to reach.

Esc or **Done** leaves the editor. Changes stay in the tank until you quit, even if they aren't saved.

## Room mood

**Mood** on the monitor's home page sets the bedroom's lighting. The choice is remembered.

- **Night gamer den** (the default): street lamps, lit windows and neon across the street, stars and a low moon, lamps on, the LED strip in purple.
- **Rainy evening:** rain falling outside and running down the window, a wet street reflecting the lights, umbrellas.
- **Golden hour:** the low sun behind the houses opposite and through the window, long shadows, lamps off, pigeons now and then.

Each mood has its own baked lightmap for the room. Live lights add the monitor's glow and light the fish, the tank and its decor.

Outside the window is a real street, seen from the third floor: brick rowhouses with stoops and fire escapes, a deli, a café, a noodle bar and a laundromat on the corner of a cross street, taller blocks behind and downtown in the distance. Every window has a room behind it, some lit. Cars drive past and stop at the lights, and people walk the sidewalks. The street has its own render layer and lights, so it doesn't disturb the room's baked lighting.

## Graphics quality

**Graphics** on the monitor's home page sets **Low**, **Medium** or **High**. It starts on **Auto**, which picks Low on integrated or software GPUs and High on dedicated ones.

| | Low | Medium | High |
|---|---|---|---|
| Caustics | off | on | on |
| Water refraction | off | on | on |
| Glow | off | on | on |
| Ambient occlusion (SSAO) | off | off | on |
| Anti-aliasing | off | 2× MSAA | 4× MSAA |
| Render scale | 0.8 | 1.0 | 1.0 |
| Shadow atlas | 1024 | 2048 | 4096 |
| Street: sun shadows, shop, neon and headlight lights | off | on | on |
| Street: people | half | all | all |
| Bubbles | 40% | 75% | 100% |

## Tank cam

The tank cam is a second window, titled "Linguini Tank Cam" and 1280×720, showing the room camera's view of the tank. To stream it, add a **Window Capture** source in OBS and pick that window. Turn it on with F4, or with **Tank cam window** on the monitor menu, which also sets the overlay style.

Nothing in it is machine learning. The "detector" is the fish's real position projected into the camera. Its confidence score drops when a card hides the fish from the camera. There are three styles:
The fish is always labelled plainly, as "goldfish 0.97".
- **Earnest** (default): a straight-faced research tool. It shows the box and its track number, and a keypoint skeleton (nose, eyes, fins, tail). It adds a motion trail, a heatmap of where the fish spends its time, and dashed outlines on the card zones it's engaging. It also has inference rate and latency readouts, the inputs held, and a short detection log.
- **Minimal:** corner brackets around the fish, its label and the held inputs.
- **Over-the-top:** everything in Earnest, plus a model banner and a predicted trajectory. It also has fake layer activations, an "INTENT" guess, a scrolling log, scanlines and the odd "RECALIBRATING…" flicker.

## Sound

The host's audio plays from the two speakers next to the monitor, placed in 3D: the left channel on the left speaker and the right on the right. To hear it without the room, set **Room speakers / Stereo** on the monitor's stream settings to Stereo.

- **Where you hear from:** while you pilot the fish, sound is heard from the fish. It's always underwater, so everything is lightly muffled: a gentle low-pass at 3.5 kHz and a little reverb, clear enough to follow the game. In the menu and editor you hear from the camera; the menu's view is in the tank, so it's muffled too. Stereo mode skips the water altogether.
- **The tank:** the air stone bubbles, the filter trickles and the lamp hums, each from where it is.
- **The fish:** a swish on each tail beat, harder when it swims harder. It also whooshes when it darts and knocks when it bumps the glass or solid decor.
- **The cards:** a soft tap as a card presses, a lighter one on release, and a tick for each step of a sequence.
- **The room:** each mood has its own tone. Night has the PC fan and the distant city, the rainy evening has rain on the window, and golden hour has birds and a breeze. The monitor's buttons click.
- **Volume:** **Master**, **Game** (the stream), **Room & tank** and **UI** sliders on the monitor's home page. They're remembered.

The sounds are built by `audio/build.py` into `godot/audio/`:

```sh
nix develop .#audio -c python3 audio/build.py          # everything
nix develop .#audio -c python3 audio/build.py bubbles  # just these
```

Most are synthesized by the script. The rain and the birds are CC0 recordings from OpenGameArt, kept in `audio/sources/`; `godot/audio/CREDITS.txt` lists them, and the release packages include it.

## Building

The extension is C++ on top of [godot-cpp](https://github.com/godotengine/godot-cpp). It builds these into one library:
- [moonlight-common-c](https://github.com/moonlight-stream/moonlight-common-c), for the streaming session.
- `libgamestream` from [moonlight-embedded](https://github.com/moonlight-stream/moonlight-embedded), for pairing, the app list and launching.

It needs Godot 4.5+ and SCons. It also needs these libraries: FFmpeg (libavcodec, libavutil), Opus, OpenSSL, libcurl and expat.

```sh
git submodule update --init --recursive
scons                          # builds godot/bin/liblinguini.*
godot --path godot             # run it (or open godot/ in the editor)
```

On Nix, `nix develop` provides everything, Godot included. On Linux and macOS, the libraries are found with `pkg-config` (see [macOS](#macos) for Homebrew). On Windows, build them once with `packaging\windows\build-deps.ps1` (see [Windows](#windows)).

### Tests

```sh
godot --headless --path godot -s res://tests/run_tests.gd
LINGUINI_TEST_HOST=192.168.1.20 godot --headless --path godot -s res://tests/run_tests.gd   # also query a real host
```

The tests cover:
- Fish behaviour: drift, cruise pulses, arcs, dart, backing up, rising.
- Card timing and geometry, combos, toggles and sequences, layouts and presets, and the controller state sent to the host.
- The tank editor: entering and leaving it, card edits, and saving and loading presets.
- The tank cam's detector: tracking, occlusion and what it reports.
- Game audio: channel routing, the light underwater muffle, and Stereo skipping it.
- Decor: placement by anchor, solid versus soft, saving with presets, and the editor.
- Art: that the tank and fish models match the game's dimensions, and that the quality presets switch their effects.
- The bedroom: that it lands around the tank, uses its lightmaps, and switches lightmap, view and rain with the mood picker.
- The look: button glyph sets and their detection, the card slab's orientation, the idle monitor and tally lights, the editor's decor palette and the tank cam's keypoints.
- Feel and sound: the mixer buses and volumes, hearing from the fish while piloting, card taps, tank and room sounds, the dart kick, and motes and shafts by quality.
- The decode path, from an H.264 test stream to the Y/UV planes.
- Host requests.
- The fish staying inside the tank under physics.

Two headless tools help on machines without a display:

```sh
godot --headless --path godot -- --tool=pair HOST                     # prints a PIN, waits for it to be entered
godot --headless --path godot -- --tool=stream_check HOST Desktop 15 frame.png
./Linguini.x86_64 --headless -- --tool=pair HOST                      # the same from a packaged build
```

`pair` pairs with a host. `stream_check` launches an app on a paired host and streams for the given number of seconds. It then reports decoded video, audio received and input, saves the last frame's luma plane, and quits the app.

`main.tscn` also accepts `-- --swim --test-video=PATH --gaze --zones --room-camera --screenshot=PATH` for manual checks without a host. The full list is in `godot/scripts/main.gd`.

## Packaging

```sh
packaging/linux/package.sh     # -> dist/builds/linguini-linux-x86_64.tar.gz
```

The Linux release build is made in Docker (`packaging/linux/Dockerfile`, Ubuntu 22.04), so it runs on most distributions:
- **Static dependencies:** OpenSSL, Opus, expat, curl and FFmpeg are built from source as static libraries. FFmpeg is cut down to H.264, HEVC and AV1 decoding plus VA-API.
- **What's left:** the extension needs only glibc 2.35 or newer and libva from the user's system. The script fails if the extension picks up any other dynamic dependency.

After building, the script exports the project with the `Linux` preset (`godot/export_presets.cfg`). It then packs the executable, the extension, a README and the third-party licences.

It needs Docker, plus a Godot editor with matching export templates. Set `GODOT` and `GODOT_TEMPLATES`, or let it take both from the Nix flake. It keeps its own Godot data directory, so your editor settings aren't touched.

### macOS

```sh
packaging/macos/package.sh     # -> dist/builds/linguini-macos-universal.zip
```

The macOS build is made natively on a Mac, Apple Silicon or Intel. It produces one universal app that runs on both, on macOS 11 or later.
- **Static dependencies:** `packaging/macos/build-deps.sh` builds the same versions of OpenSSL, Opus, expat, curl and FFmpeg as the Linux Dockerfile, once for each architecture, into `dist/macos/deps-*`. FFmpeg decodes H.264 and HEVC with VideoToolbox. AV1 decodes in software, because FFmpeg 7.1 has no VideoToolbox AV1. The builds are reused until the script changes.
- **Universal extension:** the extension is built for arm64 and x86_64 and joined with `lipo` into `liblinguini.macos.template_release.framework`. The script fails if either half links anything outside `/usr/lib` and the system frameworks, or targets a macOS other than 11.0.
- **Export:** the `macOS` preset in `godot/export_presets.cfg` is universal, ad-hoc signed with the hardened runtime, and includes an `NSLocalNetworkUsageDescription`, because macOS asks permission before the app can reach hosts on the LAN. `rendering/textures/vram_compression/import_etc2_astc` is on, because Godot refuses arm64 or universal exports without it.
- **Checks:** the zip holds `Linguini.app`, a README and the licences. The script finishes by running `packaging/macos/validate.py` on it, which checks both architectures, the signatures, the linked libraries, the game data and the licences.

It needs the Xcode command line tools, SCons, nasm (for x86_64 FFmpeg), and a Godot editor with the matching macOS export template. Set `GODOT` and `GODOT_TEMPLATES`, or let it use `godot` and Godot's own export templates directory. To set up a Mac:

```sh
brew install scons nasm pkg-config ffmpeg opus openssl@3 curl expat   # the last five for development builds
brew install --cask godot
# then install the export templates from the editor (Editor › Manage Export Templates)
```

For development builds, `scons` finds Homebrew's libraries through `pkg-config`. Homebrew doesn't link OpenSSL, curl or expat into its prefix, so add them to the path first:

```sh
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig:$(brew --prefix curl)/lib/pkgconfig:$(brew --prefix expat)/lib/pkgconfig"
scons arch=arm64               # or x86_64; builds godot/bin/liblinguini.macos.template_debug.framework
```

The app is ad-hoc signed but not notarized. Gatekeeper blocks it on first launch until the user allows it under **System Settings › Privacy & Security** (see `packaging/macos/README.txt`). Notarizing needs an Apple Developer ID.

### Windows

```powershell
packaging\windows\package.ps1   # -> dist\builds\linguini-windows-x86_64.zip
```

The Windows build is made natively with MSVC, for 64-bit Windows 10 and 11.
- **Static dependencies:** `packaging/windows/build-deps.ps1` builds FFmpeg, Opus, OpenSSL, curl (over OpenSSL) and expat with [vcpkg](https://vcpkg.io), from `packaging/windows/vcpkg.json`. They're static and use the static C runtime (`/MT`), as godot-cpp does, with vcpkg's `x64-windows-static-release` triplet. FFmpeg decodes with D3D11VA or DXVA2, falling back to software. The script pins vcpkg to one commit and fetches it into `dist/windows/vcpkg`; set `VCPKG_ROOT` to use your own checkout. The first run builds FFmpeg from source and takes a while. Later runs reuse vcpkg's binary cache in `dist/windows/vcpkg-cache`.
- **The extension:** `liblinguini.windows.template_release.x86_64.dll`. The script fails if it links anything outside `System32`, or anything from the Visual C++ redistributable.
- **Export:** the `Windows` preset in `godot/export_presets.cfg` embeds the game data in `Linguini.exe` and adds `Linguini.console.exe`, the same program with a console for the headless tools. The zip holds both, the extension, a README and the licences, including each vcpkg library's.

It needs git, Python with SCons, Visual Studio 2022 or its Build Tools with the **Desktop development with C++** workload, and a Godot editor with the matching export templates. Set `GODOT` (use the `_console.exe` build, so its output reaches the terminal) and `GODOT_TEMPLATES`, or let it use `godot` and Godot's own export templates directory. Godot's own settings aren't touched: the script gives Godot a private `APPDATA` while it exports.

For development builds, build the dependencies once and point `scons` at them:

```powershell
pip install scons
packaging\windows\build-deps.ps1
$env:LINGUINI_DEPS_PREFIX = "$pwd\dist\windows\deps\x64-windows-static-release"
scons                          # builds godot\bin\liblinguini.windows.template_debug.x86_64.dll
```

SCons finds Visual Studio itself, so a plain PowerShell works; you don't need a developer prompt. The build isn't signed, so SmartScreen warns on first launch (see `packaging/windows/README.txt`).

## Releases

Releases are made by GitHub Actions (`.github/workflows/release.yml`) when a version tag is pushed:

```sh
git tag v0.0.1 && git push origin v0.0.1
```

Until 0.1.0, releases are numbered 0.0.x.

That tag push does three things:
- **Package:** builds `linguini-linux-x86_64.tar.gz` with `packaging/linux/package.sh`, `linguini-macos-universal.zip` with `packaging/macos/package.sh` (on a `macos-14` runner) and `linguini-windows-x86_64.zip` with `packaging/windows/package.ps1` (on a `windows-2022` runner). The macOS and Windows static dependencies are cached.
- **Release:** publishes them as a GitHub Release for the tag, with `SHA256SUMS` and generated release notes. A tag with a hyphen, such as `v0.2.0-beta.1`, is marked as a pre-release.
- **Landing page:** runs `.github/workflows/pages.yml` for the tag, which rebuilds the page with download links pointing at the new release and deploys it to GitHub Pages.

One-time setup, in the repository's settings:
- **Pages:** set **Source** to **GitHub Actions**.
- **Environments › github-pages › Deployment branches and tags:** add a tag rule for `v*`. Otherwise only `main` may deploy, and the tag's deploy is rejected.

The landing page doesn't need a release to update. `pages.yml` also runs on every push to `main` that changes `site/`, linking the latest release, and it can be run by hand from the Actions tab.

Ordinary pushes and pull requests run `.github/workflows/build.yml`, which builds the extension and runs the tests on Linux, macOS and Windows.

## Landing page

`site/build.py` builds a static landing page with download links into `dist/site/`. It uses only the Python standard library.

```sh
python3 site/build.py                                    # dist/builds/* -> dist/site/
python3 site/build.py --builds DIR --out DIR --repo-url https://…
python3 site/build.py --base-url https://…/releases/v0.1.0/   # link to hosted files instead of copying
python3 site/build.py --version v0.1.0 --date 2026-10-01      # label the builds (defaults: git describe, today)
```

Put the packaged builds in `dist/builds/`. Each file is matched to a platform by its name:
- `linux`
- `win`, `windows` or `win64`
- `mac`, `macos`, `osx` or `darwin`

For example: `linguini-linux-x86_64.zip`, `linguini-windows-x86_64.zip`, `linguini-macos.zip`.

The script copies the builds into the site and writes `SHA256SUMS`. The page lists each build with its size; platforms without a build are left off. The output is plain HTML and CSS, so any static host works. Its screenshots in `site/assets/` come from the tracker's snapshots (see [Progress tracker](#progress-tracker)).

## Art pipeline

Every model is built by a Blender Python script in `art/`. The generated `.glb` files are committed, so building the game doesn't need Blender.

```sh
nix develop .#art -c art/build.sh              # rebuild every model (and its preview renders)
nix develop .#art -c art/build.sh fish castle  # just these
python3 art/check.py                           # fails if a .glb is out of date with its script
```

- **The catalogue:** `art/catalog.json` lists each model: its id, script, output, milestone and status.
  - Scripts live in `art/models/`. Shared helpers for materials, painting, sweeps, colliders and studio renders live in `art/lib/`.
  - `art/manifest.json` records a hash of each model's inputs, which is what `check.py` compares. CI runs the check.
- **Conventions** (details in `art/lib/common.py` and `art/lib/decor.py`):
  - Units are metres, and a model facing Blender +Y faces Godot −Z.
  - Painted colour goes in the `Col` attribute.
  - Animation weights go in a second UV map, which Godot reads as `UV2`.
  - Materials are named, and Godot swaps in its own shaders or recolours by those names.
  - Objects named `*-convcolonly` become collision-only shapes.

### The bedroom and its lightmaps

The room (`art/models/room/`) is one mesh with a second UV map for its lightmap. Cycles bakes the light arriving on every surface, once per mood, into `godot/art/room/lightmap_<mood>.exr`. Godot multiplies in each material's colour. `layout.json` tells Godot where the tank, monitor, speakers, camera and lamps are.

```sh
nix develop .#art -c art/build.sh room                             # draft bakes: 512 px, 128 samples, a couple of minutes on a laptop
ART_BAKE=final ART_DEVICE=GPU nix develop .#art -c art/build.sh room   # final bakes: 2048 px at 256 samples, saved at 1024 px; use a fast GPU
ART_BAKE=none nix develop .#art -c art/build.sh room               # geometry only, keeping the existing bakes
```

The committed lightmaps are final bakes; `layout.json` records which quality they were baked at. Keep the mood table in `godot/scripts/room_moods.gd` in step with `art/models/room/moods.py`.

### Progress tracker

```sh
python3 tools/tracker/server.py    # http://localhost:57197, and on your LAN
```

A live page with the roadmap, in-game snapshots of the whole scene, and a render of every model, grouped by milestone. It refreshes itself every few seconds, picking up edits to `tools/tracker/roadmap.json`, new renders from `art/build.sh` and new snapshots. Renders and snapshots are written to `art/renders/`, which isn't committed.

```sh
nix develop -c python3 tools/tracker/capture.py                 # every shot in shots.json, for the current milestone
nix develop -c python3 tools/tracker/capture.py --only menu editor
```

A snapshot runs the game once per shot in `tools/tracker/shots.json`, headless under `xvfb-run`, and saves the screenshots with the milestone, time and commit. The page shows the newest snapshot large, a timeline of every snapshot, and each milestone's newest snapshot in its roadmap entry.

## Layout

```
native/src/            GDExtension: MoonlightClient node, FFmpeg video decoder, Opus audio
native/compat/         shims that let libgamestream build unmodified off Linux
art/                   Blender scripts for every model (see Art pipeline)
godot/art/             the generated models (.glb)
godot/scripts/         fish, camera, cards, decor, editor, monitor + menu, room, quality
godot/shaders/         fish, glass, water, caustics, plants, bubbles, monitor screen
godot/data/            card layouts and the decor catalogue
godot/tests/           headless tests
tools/tracker/         the progress tracker
third_party/           submodules
```

## Known limitations

- Hosts are added by IP or hostname. There's no mDNS discovery yet.
- Frames are decoded on the GPU where possible and copied back to system memory for upload. Zero-copy rendering is future work.
- The Windows build isn't code-signed, so SmartScreen warns on first launch.
- The macOS build isn't notarized, so first launch needs a trip to System Settings.
- The macOS build has been tested with the test stream (VideoToolbox decoding, both architectures) but hasn't streamed from a real host yet, so the local network permission prompt is also untested.
- libgamestream requests can't be cancelled. "Back" during pairing stops waiting, but the host keeps the PIN prompt open until it's entered or times out.
- libgamestream names the client "roth" on the host's paired-devices list.
