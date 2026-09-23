# Linguini

A [Moonlight](https://moonlight-stream.org/) game-streaming client, inspired by the great deeds of the mighty Tortellini, where **you are the fish**. See [docs/core.md](docs/core.md) for the vision.

You play from inside a fish tank in a streamer's bedroom. The game stream plays on the monitor across the room. Flash cards in the tank press controller buttons on the host while the fish swims in front of them.

## Status: milestone 1 (vertical slice)

- Pair with a Sunshine or GeForce Experience host, pick an app and stream it. Video and audio go to the monitor in the room. All of this happens on the monitor itself.
- **Real Fishy Movement:** the stick or WASD sets the direction the fish wants to go and how hard to swim, not a velocity. The fish turns at a limited rate and moves in tail-beat pulses, so it swims in arcs. With no input it drifts.
- Third-person camera. Hold the gaze button to look past the fish at the monitor.
- 24 flash cards cover the whole controller.

Milestone 2 adds the card editor and presets, the fake ML tracking-camera window, and 3D speaker audio. Milestone 3 is the art pass.

## Controls

| | Keyboard / mouse | Gamepad |
|---|---|---|
| Swim | WASD | Left stick |
| Rise / sink | Space / C | RB / LB |
| Dart | Shift | A |
| Look around | Mouse | Right stick |
| Watch the monitor | Hold right mouse (or Tab) | Hold LT |
| Menu | Esc | Start |
| Show card trigger zones | F3 | |

Your own keyboard and gamepad never reach the host. Only the cards do.

## Flash cards

The default layout is in `godot/data/layouts/default.json`. Every card faces the front glass, where the room camera is. A card's trigger zone is its footprint, enlarged by 10%, extruded forward to the glass. From the room camera's point of view, the fish covering a card presses it.

- **Pressing:** a card presses as soon as the fish's body touches its zone. It stays held while the fish stays there.
- **Releasing:** a card releases once the fish has been out of the zone for 150 ms. The zone also has a 1.5 cm margin while held, so a fish drifting along an edge doesn't make the button flicker.
- **Stick diagonals:** stick directions are arranged as a cross with an empty centre. Swim into the corner between two arms to get a diagonal.

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
- Card timing and geometry, and the controller state sent to the host.
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
git tag v0.1.0 && git push origin v0.1.0
```

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

## Layout

```
native/src/            GDExtension: MoonlightClient node, FFmpeg video decoder, Opus audio
native/compat/         shims that let libgamestream build unmodified off Linux
godot/scripts/         fish, camera, cards, monitor + menu, room builder (greybox)
godot/shaders/         monitor screen (YUV -> RGB, letterboxing, menu overlay)
godot/data/layouts/    card layouts
godot/tests/           headless tests
third_party/           submodules
```

## Known limitations

- Linux and macOS have been built and tested. The Windows paths in `SConstruct`, the shims, and the CI job are written but haven't been run.
- Hosts are added by IP or hostname. There's no mDNS discovery yet.
- Frames are decoded on the GPU where possible and copied back to system memory for upload. Zero-copy rendering is future work.
- Linux and macOS have packaged release builds. Windows needs its own packaging.
- The macOS build isn't notarized, so first launch needs a trip to System Settings.
- The macOS build has been tested with the test stream (VideoToolbox decoding, both architectures) but hasn't streamed from a real host yet, so the local network permission prompt is also untested.
- libgamestream requests can't be cancelled. "Back" during pairing stops waiting, but the host keeps the PIN prompt open until it's entered or times out.
- libgamestream names the client "roth" on the host's paired-devices list.

## License

Linguini is licensed under the [GNU General Public License v3.0](LICENSE). It builds in moonlight-common-c and moonlight-embedded, which are GPLv3 as well.
