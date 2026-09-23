# Linguini

A [Moonlight](https://moonlight-stream.org/) game-streaming client, inspired by the great deeds of the mighty Tortellini, where **you are the fish**. See [docs/core.md](docs/core.md) for the vision.

You play from inside a fish tank in a streamer's bedroom. The game stream plays on the monitor across the room. Flash cards in the tank press controller buttons on the host while the fish swims in front of them.

## Status: milestone 3a (fish, tank, water)

- Pair with a Sunshine or GeForce Experience host, pick an app and stream it. Video and audio go to the monitor in the room. All of this happens on the monitor itself.
- **Real Fishy Movement:** the stick or WASD steers from the fish's point of view, not the camera's. Forward swims along its heading, left and right turn it, and back makes it back up slowly. Input is an urge, not a velocity: the fish turns at a limited rate and moves in tail-beat pulses, so it swims in arcs. With no input it drifts.
- Third-person camera. Hold the gaze button to look past the fish at the monitor.
- Flash cards cover the whole controller, plus the stick diagonals. Cards can hold several inputs at once (combos) or play a timed macro (sequences).
- A tank editor (F2) places, rebinds, duplicates and deletes cards, and saves named presets.
- A **tank cam** window (F4) shows the room camera's view with a fake ML fish-tracking overlay, ready for OBS to capture.
- Game audio plays from the speakers next to the monitor, and it's muffled while the camera is underwater.
- **Art, so far:** a fancy fantail goldfish that swims by vertex shader, a modelled tank and stand, glass with a hint of algae, a rippling water surface, and caustic light. The tank has editable decor: plants, rocks, driftwood, an air stone, a filter and ornaments. The tank sits under the window of a cosy streamer's bedroom, with lighting baked in Blender for three moods. Every model comes from a Blender script.
- **Quality presets:** Low, Medium and High, auto-picked for your GPU.

Still to come in milestone 3: 3b the bedroom and its lighting, 3c card faces, the UI and the tank cam's look, and 3d feel and sound. `tools/tracker/` shows progress live.

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

## Flash cards

The built-in Default layout is `godot/data/layouts/default.json`. Every card faces the front glass, where the room camera is. A card's trigger zone is the middle 90% of its footprint, extruded forward to the glass. From the room camera's point of view, the fish covering a card presses it.

- **Pressing:** a card presses as soon as the centre of the fish enters its zone. Fins, tail and the rest of the body don't count. It stays held while the fish stays there.
- **Releasing:** a card releases once the fish has been out of the zone for 150 ms. The zone also has a 1.5 cm margin while held, so a fish drifting along an edge doesn't make the button flicker.
- **Combos:** a card can hold several inputs together, such as RB + A. Each stick is laid out as a 3×3 grid: the four directions, combo cards for the four diagonals in the corners, and an empty centre.
- **Sequences:** a card can instead play a timed macro once each time the fish arrives. For example, "B for 80 ms, then RB at 180 ms for 80 ms". Each step holds one input from its start time for its length, and steps can overlap to press inputs together. A sequence finishes even if the fish swims off. Arriving again replays it.

### Tank editor

Press F2, or choose **Edit tank** on the monitor. The fish waits and nothing is sent to the host while you edit.
- **Moving things:** click a card or a piece of decor to select it, then drag to move it.
  - Cards move parallel to the glass; Shift+drag moves them nearer or further. The panel also has exact position fields.
  - Decor moves along whatever it's anchored to: the gravel, the water surface, or the back and side rims (the filter). Moss balls float anywhere, with Shift+drag for depth.
- **Camera:** right-drag orbits, and the wheel zooms.
- **Editing a card:** choose **Hold** and pick one or more inputs, or choose **Sequence** and edit its steps. You can give it a name, which is shown on the card.
- **Editing decor:** set its colour variant and size (S, M or L), and turn it with the slider. Cards always face the glass, so only decor turns.
- **Actions:** **+ Card**, **+ Decor** (with the piece chosen from the list), **Duplicate** and **Delete**.
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

- **Night gamer den** (the default): city lights and stars outside, lamps on, the LED strip in purple.
- **Rainy evening:** a grey, hazy city, with rain running down the window.
- **Golden hour:** low sun through the window, lamps off.

Each mood has its own baked lightmap and window view. Live lights add the monitor's glow and light the fish, the tank and its decor.

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
| Bubbles | 40% | 75% | 100% |

## Tank cam

The tank cam is a second window, titled "Linguini Tank Cam" and 1280×720, showing the room camera's view of the tank. To stream it, add a **Window Capture** source in OBS and pick that window. Turn it on with F4, or with **Tank cam window** on the monitor menu, which also sets the overlay style.

Nothing in it is machine learning. The "detector" is the fish's real position projected into the camera. Its confidence score drops when a card hides the fish from the camera. There are three styles:
- **Earnest** (default): a straight-faced research tool. It shows a bounding box with a jittering confidence score, a motion trail, a heatmap of where the fish spends its time, the cards it's engaging, the inputs it's holding, and "TortelliNet-v3 · inference 31.4 fps".
- **Minimal:** the box, its label and the held inputs.
- **Over-the-top:** everything in Earnest, plus fake layer activations, an "INTENT" prediction, a scrolling log and scanlines.

## Game audio

The host's audio plays from the two speakers next to the monitor, placed in 3D: the left channel on the left speaker and the right on the right. When the camera is underwater, a low-pass filter muffles everything through the water and glass. It clears when the camera leaves the water, such as in the editor. To hear it without the room, set **Room speakers / Stereo** on the monitor's stream settings to Stereo.

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

On Nix, `nix develop` provides everything, Godot included. On Linux and macOS, the libraries are found with `pkg-config` (see [macOS](#macos) for Homebrew). On Windows, set `LINGUINI_DEPS_PREFIX` to a prefix with `include/` and `lib/`, such as a vcpkg `installed/x64-windows` tree.

### Tests

```sh
godot --headless --path godot -s res://tests/run_tests.gd
LINGUINI_TEST_HOST=192.168.1.20 godot --headless --path godot -s res://tests/run_tests.gd   # also query a real host
```

The tests cover:
- Fish behaviour: drift, cruise pulses, arcs, dart, backing up, rising.
- Card timing and geometry, combos and sequences, layouts and presets, and the controller state sent to the host.
- The tank editor: entering and leaving it, card edits, and saving and loading presets.
- The tank cam's detector: tracking, occlusion and what it reports.
- Game audio: channel routing and the underwater filter.
- Decor: placement by anchor, solid versus soft, saving with presets, the editor, and the default arrangement staying clear of card zones.
- Art: that the tank and fish models match the game's dimensions, and that the quality presets switch their effects.
- The bedroom: that it lands around the tank, uses its lightmaps, and switches lightmap, view and rain with the mood picker.
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

## Releases

Releases are made by GitHub Actions (`.github/workflows/release.yml`) when a version tag is pushed:

```sh
git tag v0.0.1 && git push origin v0.0.1
```

Until 0.1.0, releases are numbered 0.0.x.

That tag push does three things:
- **Package:** builds `linguini-linux-x86_64.tar.gz` with `packaging/linux/package.sh` and `linguini-macos-universal.zip` with `packaging/macos/package.sh` (on a `macos-14` runner, with the static dependencies cached).
- **Release:** publishes them as a GitHub Release for the tag, with `SHA256SUMS` and generated release notes. A tag with a hyphen, such as `v0.2.0-beta.1`, is marked as a pre-release.
- **Landing page:** rebuilds it with that version and download links pointing at the release, then deploys it to GitHub Pages.

For one-time setup, go to the repository's **Settings › Pages** and set **Source** to **GitHub Actions**.

Ordinary pushes and pull requests run `.github/workflows/build.yml`, which builds the extension and runs the tests on Linux and macOS.

## Landing page

`site/build.py` builds a static landing page with download links into `dist/site/`. It uses only the Python standard library.

```sh
python3 site/build.py                                    # dist/builds/* -> dist/site/
python3 site/build.py --builds DIR --out DIR --repo-url https://…
python3 site/build.py --base-url https://…/releases/v0.1.0/   # link to hosted files instead of copying
```

Put the packaged builds in `dist/builds/`. Each file is matched to a platform by its name:
- `linux`
- `win`, `windows` or `win64`
- `mac`, `macos`, `osx` or `darwin`

For example: `linguini-linux-x86_64.zip`, `linguini-windows-x86_64.zip`, `linguini-macos.zip`.

The script copies the builds into the site and writes `SHA256SUMS`. The page lists each file's size and SHA-256. On the visitor's own platform, the hero button becomes "Download for …". A platform without a build shows "Not built yet". The output is plain HTML and CSS with a small script, so any static host works.

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

The committed lightmaps are drafts; `layout.json` records which quality they were baked at. Keep the mood table in `godot/scripts/room_moods.gd` in step with `art/models/room/moods.py`.

### Progress tracker

```sh
python3 tools/tracker/server.py    # http://localhost:57197, and on your LAN
```

A live page with the roadmap and a render of every model, grouped by milestone. It refreshes itself every few seconds, picking up edits to `tools/tracker/roadmap.json` and new renders from `art/build.sh`. Renders are written to `art/renders/`, which isn't committed.

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

- Linux and macOS have been built and tested. The Windows paths in `SConstruct` and the shims are written but don't build yet. The Windows CI job is skipped until they do; set the repository variable `WINDOWS_CI` to `true` to run it.
- Hosts are added by IP or hostname. There's no mDNS discovery yet.
- Frames are decoded on the GPU where possible and copied back to system memory for upload. Zero-copy rendering is future work.
- Linux and macOS have packaged release builds. Windows needs its own packaging.
- The macOS build isn't notarized, so first launch needs a trip to System Settings.
- The macOS build has been tested with the test stream (VideoToolbox decoding, both architectures) but hasn't streamed from a real host yet, so the local network permission prompt is also untested.
- libgamestream requests can't be cancelled. "Back" during pairing stops waiting, but the host keeps the PIN prompt open until it's entered or times out.
- libgamestream names the client "roth" on the host's paired-devices list.

## License

Linguini is licensed under the [GNU General Public License v3.0](LICENSE). It builds in moonlight-common-c and moonlight-embedded, which are GPLv3 as well.
